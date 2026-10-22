shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
#include "res://render/tree_identity.gdshaderinc"
#include "res://render/tree_wind.gdshaderinc"

global uniform float sim_clock;
global uniform vec3 wind_vec;
uniform bool wind_enabled = true; // capture ablation switch; cards follow the session wind (global wind_vec, ShaderClock)

// Landscape improvement phases 0/1/3 (docs/research/landscape-improvement-2026-10-07, report 02):
// - one crown normal per pixel: an ellipsoid around the crown centre in the view plane, written in fragment() (after
//   Godot's back-face flip), so the three crossed cards agree and the half-lit/half-dark seam disappears;
// - soft fill (BACKLIGHT, a sky lean of the normal, a bounded underside) and trunk-base contact darkening;
// - leaves and bark graded toward measured reflectance (linear space), with modest foliage-only patch and tree variation.
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
// Data mask baked from the source glTF material IDs; intentionally no source_color hint.
uniform sampler2D foliage_mask : filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 frame_sizes = vec3(1.125001);
// Stable slots now contain downloaded oak, maple and pine. Fractions measured
// from the realistic atlas's source-material foliage mask (2026-10-20 bake).
const vec3 CROWN_CENTRE = vec3(0.612061, 0.598877, 0.704346);
const vec3 CROWN_HALF_W = vec3(0.416383, 0.339478, 0.187867);
const vec3 CROWN_HALF_H = vec3(0.366, 0.404, 0.289);
uniform float up_bias = 0.5;
uniform float underside = -0.5;
uniform float backlight = 0.4;
uniform float base_dark = 0.65;
uniform float leaf_saturation = 0.95;
uniform float leaf_gain = 1.0;
uniform float bark_gain = 1.0;

varying vec3 crown_view;
varying vec2 crown_radius;
varying vec3 up_view;
varying float height_frac;
varying float far_tree;
varying vec3 foliage_tint;

void vertex() {
    // INSTANCE_CUSTOM encodes each translation (N/E) in four exact bytes.
    vec2 ne = tree_position(INSTANCE_CUSTOM);
    far_tree = step(600.0, length(ne));
    vec3 identity = tree_identity(ne);
    int species = int(identity.x);
    float ratio = frame_sizes[species] / frame_sizes.x;
    VERTEX.xz *= ratio;
    VERTEX.y = (VERTEX.y - 0.5) * ratio + 0.5;
    height_frac = VERTEX.y; // 0 at the base, about 1 at the top (before the height scale)
    float c = cos(identity.z);
    float s = sin(identity.z);
    mat2 spin = mat2(vec2(c, -s), vec2(s, c));
    VERTEX.xz = spin * VERTEX.xz;
    NORMAL.xz = spin * NORMAL.xz;
    VERTEX *= identity.y;
    vec3 crown = vec3(0.0, CROWN_CENTRE[species] * identity.y, 0.0);
    if (wind_enabled && dot(wind_vec.xz, wind_vec.xz) > 0.0) {
        // Tree instances have rotation-only/translation transforms. Convert world
        // air velocity (where it goes TO) once; identity yaw is already applied.
        vec3 local_wind = transpose(mat3(MODEL_MATRIX)) * vec3(wind_vec.x, 0.0, wind_vec.z);
        uint phase_hash = tree_hash(ne);
        VERTEX = tree_bend(VERTEX, local_wind.xz, identity.y, phase_hash, sim_clock);
        crown = tree_bend(crown, local_wind.xz, identity.y, phase_hash, sim_clock);
    }
    crown_view = (MODELVIEW_MATRIX * vec4(crown, 1.0)).xyz;
    crown_radius = vec2(CROWN_HALF_W[species], CROWN_HALF_H[species]) * identity.y;
    up_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
    // Per-tree tint remains small; a broader continuous value field keeps nearby trees in a patch coherent.
    // MODEL_MATRIX translation is absolute rendered N/E, so the tint stays fixed in world space.
    vec2 world_ne = vec2(-MODEL_MATRIX[3].z, MODEL_MATRIX[3].x);
    float patch_value = tree_patch_noise(world_ne);
    uint h2 = (tree_hash(ne) * 25173u + 13849u) % 65521u;
    float individual_value = float(h2 % 997u) / 996.0 * 2.0 - 1.0;
    float foliage_gain = 1.0 + patch_value * 0.035 + individual_value * 0.020;
    foliage_tint = foliage_gain * vec3(1.0 + patch_value * 0.010,
                                      1.0,
                                      1.0 - patch_value * 0.015);
    // The template carries CommonTree_1 UVs including its half-texel inset.
    UV += species == 1 ? vec2(0.5, 0.0) : (species == 2 ? vec2(0.0, 0.5) : vec2(0.0));
}

void fragment() {
    vec4 tex = texture(atlas, UV);
    vec3 c = tex.rgb;
    float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
    // Material identity comes from the source-derived mask. Color variation only reaches foliage;
    // trunks keep their source bark grade even when their trees share a tinted forest patch.
    float foliage = texture(foliage_mask, UV).r;
    vec3 bark = c * bark_gain; // retain the downloaded bark texture's actual hue
    vec3 leaves = mix(vec3(luma), c, leaf_saturation) * leaf_gain;
    vec3 graded = mix(bark, leaves, foliage);
    ALBEDO = graded * mix(vec3(1.0), foliage_tint, foliage) * mix(base_dark, 1.0, smoothstep(0.0, 0.25, height_frac));
    // GLES3 has no alpha-to-coverage here. Recover some leaf coverage as the
    // atlas mip averages thin silhouettes; L6b near trees remain unchanged.
    float texel_footprint = max(fwidth(UV).x, fwidth(UV).y) * float(textureSize(atlas, 0).x);
    float mip_level = max(log2(max(texel_footprint, 1.0)), 0.0);
    float alpha_scale = 1.0 + 0.06 * mip_level * far_tree;
    ALPHA = min(tex.a * alpha_scale, 1.0);
    ALPHA_SCISSOR_THRESHOLD = 0.5;
    vec2 q = (VERTEX.xy - crown_view.xy) / crown_radius;
    q /= max(1.0, length(q));
    q.y = max(q.y, underside);
    NORMAL = normalize(vec3(q, sqrt(max(0.0, 1.0 - dot(q, q)))) + up_bias * up_view);
    BACKLIGHT = backlight * ALBEDO;
    ROUGHNESS = 1.0;
    METALLIC = 0.0;
}

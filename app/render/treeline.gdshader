shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
#include "res://render/tree_identity.gdshaderinc"

// Landscape improvement phases 0/1/3 (docs/research/landscape-improvement-2026-10-07, report 02):
// - one crown normal per pixel: an ellipsoid around the crown centre in the view plane, written in fragment() (after
//   Godot's back-face flip), so the three crossed cards agree and the half-lit/half-dark seam disappears;
// - soft fill (BACKLIGHT, a sky lean of the normal, a bounded underside) and trunk-base contact darkening;
// - leaves and bark graded toward measured reflectance (linear space), plus a small per-tree tint from the hash.
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 frame_sizes = vec3(1.125001);
// Per species (CommonTree_1, CommonTree_3, Pine_1), fractions of the tree height, measured from the atlas (report 02).
const vec3 CROWN_CENTRE = vec3(0.71, 0.67, 0.63);
const vec3 CROWN_HALF_W = vec3(0.26, 0.20, 0.34);
const vec3 CROWN_HALF_H = vec3(0.29, 0.34, 0.34);
uniform float up_bias = 0.5;
uniform float underside = -0.5;
uniform float backlight = 0.4;
uniform float base_dark = 0.65;
uniform float leaf_saturation = 0.6;
uniform float leaf_gain = 1.0;
uniform float bark_gain = 0.65;

varying vec3 crown_view;
varying vec2 crown_radius;
varying vec3 up_view;
varying float height_frac;
varying vec3 tint;

void vertex() {
    // INSTANCE_CUSTOM encodes each translation (N/E) in four exact bytes.
    vec2 ne = tree_position(INSTANCE_CUSTOM);
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
    crown_view = (MODELVIEW_MATRIX * vec4(0.0, CROWN_CENTRE[species] * identity.y, 0.0, 1.0)).xyz;
    crown_radius = vec2(CROWN_HALF_W[species], CROWN_HALF_H[species]) * identity.y;
    up_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
    // Per-tree tint: a further integer step of the identity hash (h % 3 and h % 1024 are taken).
    uint h2 = (tree_hash(ne) * 25173u + 13849u) % 65521u;
    float u = float(h2 % 997u) / 996.0 * 2.0 - 1.0;
    tint = vec3(1.0) + vec3(0.10, 0.06, -0.08) * u;
    // The template carries CommonTree_1 UVs including its half-texel inset.
    UV += species == 1 ? vec2(0.5, 0.0) : (species == 2 ? vec2(0.0, 0.5) : vec2(0.0));
}

void fragment() {
    vec4 tex = texture(atlas, UV);
    vec3 c = tex.rgb;
    float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
    // Bark is the reddish part of the atlas; leaves are green. Grades in linear space (report 02 §4).
    vec3 graded = c.r > c.g ? luma * bark_gain * vec3(1.22, 0.96, 0.70) : mix(vec3(luma), c, leaf_saturation) * leaf_gain;
    ALBEDO = graded * tint * mix(base_dark, 1.0, smoothstep(0.0, 0.25, height_frac));
    ALPHA = tex.a;
    ALPHA_SCISSOR_THRESHOLD = 0.5;
    vec2 q = (VERTEX.xy - crown_view.xy) / crown_radius;
    q /= max(1.0, length(q));
    q.y = max(q.y, underside);
    NORMAL = normalize(vec3(q, sqrt(max(0.0, 1.0 - dot(q, q)))) + up_bias * up_view);
    BACKLIGHT = backlight * ALBEDO;
    ROUGHNESS = 1.0;
    METALLIC = 0.0;
}

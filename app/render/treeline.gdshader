shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
#include "res://render/tree_identity.gdshaderinc"

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 frame_sizes = vec3(1.125001);

void vertex() {
    // INSTANCE_CUSTOM encodes each translation (N/E) in four exact bytes.
    vec3 identity = tree_identity(tree_position(INSTANCE_CUSTOM));
    int species = int(identity.x);
    float ratio = frame_sizes[species] / frame_sizes.x;
    VERTEX.xz *= ratio;
    VERTEX.y = (VERTEX.y - 0.5) * ratio + 0.5;
    float c = cos(identity.z);
    float s = sin(identity.z);
    mat2 spin = mat2(vec2(c, -s), vec2(s, c));
    VERTEX.xz = spin * VERTEX.xz;
    NORMAL.xz = spin * NORMAL.xz;
    VERTEX *= identity.y;
    // The template carries CommonTree_1 UVs including its half-texel inset.
    UV += species == 1 ? vec2(0.5, 0.0) : (species == 2 ? vec2(0.0, 0.5) : vec2(0.0));
}

void fragment() {
    vec4 leaf = texture(atlas, UV);
    ALBEDO = leaf.rgb;
    ALPHA = leaf.a;
    ALPHA_SCISSOR_THRESHOLD = 0.5;
    ROUGHNESS = 1.0;
    METALLIC = 0.0;
}

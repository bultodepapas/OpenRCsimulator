// FW-RGB: linear-light emission overlay for owned opaque aircraft skin clones.
// Keep source textures and colors unhinted so both renderers feed this explicit sRGB decode.
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, fog_disabled, shadows_disabled;

#include "res://render/world/engine_srgb.gdshaderinc"

uniform sampler2D emission_map : filter_linear_mipmap, repeat_disable;
uniform vec4 emission_color = vec4(1.0);
uniform float energy = 0.0;

vec3 to_linear_srgb(vec3 color_srgb) {
	vec3 low = color_srgb / 12.92;
	vec3 high = pow((color_srgb + vec3(0.055)) / 1.055, vec3(2.4));
	return mix(high, low, lessThanEqual(color_srgb, vec3(0.04045)));
}

void fragment() {
	vec3 texture_linear = to_linear_srgb(clamp(texture(emission_map, UV).rgb, vec3(0.0), vec3(1.0)));
	vec3 color_linear = to_linear_srgb(clamp(emission_color.rgb, vec3(0.0), vec3(1.0)));
	vec3 emission_linear = texture_linear * color_linear * max(energy, 0.0);
	ALBEDO = encode_for_engine(emission_linear);
	ALPHA = 1.0;
}

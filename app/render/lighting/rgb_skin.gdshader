// FW-RGB: linear-light emission overlay for owned opaque aircraft skin clones.
// Keep source textures and colors unhinted so both renderers feed this explicit sRGB decode.
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, fog_disabled, shadows_disabled;

#include "res://render/world/engine_srgb.gdshaderinc"

#include "res://render/lighting/rgb_patterns.gdshaderinc"

// Root-to-tip coordinate on the registered covering UV layout; signed length mirrors the left wing.
uniform vec2 span_uv_range = vec2(0.0, 1.0);

uniform sampler2D emission_map : filter_linear_mipmap, repeat_disable;
uniform vec4 emission_color = vec4(1.0);
uniform float energy = 0.0;

void fragment() {
	vec3 texture_linear = to_linear_srgb(clamp(texture(emission_map, UV).rgb, vec3(0.0), vec3(1.0)));
	vec3 color_linear = to_linear_srgb(clamp(emission_color.rgb, vec3(0.0), vec3(1.0)));
	float arc_u = clamp((UV.x - span_uv_range.x) / span_uv_range.y, 0.0, 1.0);
	vec4 pattern_linear = lighting_pattern(arc_u, fwidth(arc_u));
	vec3 emission_linear = texture_linear * color_linear * pattern_linear.rgb * pattern_linear.a * max(energy, 0.0);
	ALBEDO = encode_for_engine(emission_linear);
	ALPHA = 1.0;
}

shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled, skip_vertex_transform;

#include "res://render/world/engine_srgb.gdshaderinc"

uniform sampler2D flame_atlas : source_color, filter_linear;
uniform float exposure_value = 1.0;
uniform float base_gain = 0.68;
uniform float display_cap = 0.72;

void vertex() {
	// Material overrides replace Sprite3D's automatic billboard material state. Rebuild its quad in view space,
	// retaining the generated local size and inherited scale while keeping it camera-facing from every direction.
	vec3 center_view = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float width_scale = length(MODELVIEW_MATRIX[0].xyz);
	float height_scale = length(MODELVIEW_MATRIX[1].xyz);
	VERTEX = center_view + vec3(VERTEX.x * width_scale, VERTEX.y * height_scale, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	// Sprite3D.region_enabled supplies atlas-normalized UVs for its current region.
	vec4 flame = texture(flame_atlas, UV);
	float safe_exposure = max(exposure_value, 0.001);
	float gain = min(base_gain, display_cap / safe_exposure);
	ALBEDO = encode_for_engine(min(flame.rgb * vec3(1.0, 0.65, 0.25) * COLOR.rgb * gain, vec3(display_cap / safe_exposure)));
	ALPHA = clamp(flame.a * COLOR.a, 0.0, 1.0);
}

shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://render/windsock_deformation.gdshaderinc"

uniform sampler2D fabric_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D fabric_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D fabric_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float circumference_m = 1.414;


void vertex() {
	vec3 deformed_position;
	vec3 deformed_normal;
	vec3 deformed_tangent;
	vec3 deformed_binormal;
	windsock_deform_fabric_vertex(UV, deformed_position, deformed_normal, deformed_tangent, deformed_binormal);
	VERTEX = deformed_position;
	NORMAL = deformed_normal;
	TANGENT = deformed_tangent;
	BINORMAL = deformed_binormal;
}


void fragment() {
	// Arc-length coordinates keep the existing free fabric maps locked to the cloth.
	float circumference_here = mix(circumference_m, PI * tail_diameter_m, UV.x);
	vec2 metres = vec2(UV.x * length_m, UV.y * circumference_here);
	vec2 weave = metres / vec2(0.72, 1.02);
	float grain = dot(texture(fabric_color, weave).rgb, vec3(0.2126, 0.7152, 0.0722));
	float aa = max(fwidth(metres.x), 0.0005);
	float band_distance = min(fract(UV.x * 5.0), 1.0 - fract(UV.x * 5.0)) * length_m / 5.0;
	float panel_phase = fract(UV.y * 4.0);
	float panel_distance = min(panel_phase, 1.0 - panel_phase) * circumference_here / 4.0;
	float seam = 1.0 - smoothstep(0.0025, 0.0055, min(band_distance, panel_distance));
	float end_distance = min(UV.x, 1.0 - UV.x) * length_m;
	float hem = 1.0 - smoothstep(0.012, 0.012 + aa, end_distance);
	float support_tape = 1.0 - smoothstep(0.007, 0.014, abs(UV.x - 0.375) * length_m);
	float dash = smoothstep(0.15, 0.45, sin(metres.x * 720.0));
	float stitches = (1.0 - smoothstep(0.0005, 0.0017, panel_distance)) * dash;
	vec3 cloth = COLOR.rgb * clamp(0.99 + (grain - 0.58) * 0.16, 0.90, 1.05);
	// Preserve weave and seam contrast under the field's strong direct sun.
	cloth *= mix(1.0, 0.68, step(COLOR.r * 0.9, COLOR.g));
	cloth *= 1.0 - seam * 0.11 - hem * 0.15;
	cloth = mix(cloth, COLOR.rgb * 0.88, support_tape * 0.28);
	ALBEDO = mix(cloth, vec3(0.59, 0.52, 0.42), stitches * 0.16);
	ROUGHNESS = clamp(0.78 + texture(fabric_roughness, weave).r * 0.20, 0.78, 1.0);
	NORMAL_MAP = texture(fabric_normal, weave).rgb;
	NORMAL_MAP_DEPTH = 0.42;
	SPECULAR = 0.15;
}

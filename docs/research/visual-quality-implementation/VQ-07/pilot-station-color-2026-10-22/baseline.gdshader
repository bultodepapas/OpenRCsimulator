shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D wood_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wood_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wood_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metal_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metal_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
varying float material_id;
varying float variation;

void vertex() {
	material_id = COLOR.b > 0.8 && COLOR.r < 0.1 ? 0.0 : (COLOR.r > 0.5 && COLOR.g < 0.5 ? 1.0 : (COLOR.g > 0.7 ? 2.0 : (COLOR.r < 0.03 ? 3.0 : 4.0)));
	variation = clamp((COLOR.r - 0.62) / 0.18, 0.0, 1.0);
	vec3 axis = material_id == 1.0 && COLOR.b > 0.2 ? vec3(0,0,1) : vec3(1,0,0);
	if (abs(dot(axis, NORMAL)) > 0.9) { axis = vec3(0,1,0); }
	TANGENT = normalize(axis - NORMAL * dot(axis, NORMAL));
	BINORMAL = normalize(cross(NORMAL, TANGENT));
	UV = vec2(dot(VERTEX, TANGENT), dot(VERTEX, BINORMAL));
	if (material_id == 0.0) { UV /= vec2(1.1, 0.55); }
	else if (material_id == 1.0) { UV = UV / 0.8 + vec2(variation * 2.17, variation * 3.31); }
	else { UV /= 0.25; }
}

void fragment() {
	METALLIC = 0.0;
	if (material_id < 0.5) {
		ALBEDO = texture(concrete_color, UV).rgb * vec3(0.90, 0.92, 0.93);
		ROUGHNESS = clamp(texture(concrete_roughness, UV).r, 0.80, 1.0);
		NORMAL_MAP = texture(concrete_normal, UV).rgb;
		NORMAL_MAP_DEPTH = 0.25;
	} else if (material_id < 1.5) {
		ALBEDO = texture(wood_color, UV).rgb * vec3(1.0, 0.91, 0.75) * mix(0.90, 1.04, variation);
		ROUGHNESS = clamp(texture(wood_roughness, UV).r * 0.35 + 0.35, 0.45, 0.7);
		NORMAL_MAP = texture(wood_normal, UV).rgb;
		NORMAL_MAP_DEPTH = 0.18;
	} else if (material_id < 2.5) {
		ALBEDO = vec3(0.55, 0.60, 0.62);
		METALLIC = 0.75;
		ROUGHNESS = 0.30 + texture(metal_roughness, UV).r * 0.20;
		NORMAL_MAP = texture(metal_normal, UV).rgb;
		NORMAL_MAP_DEPTH = 0.12;
	} else if (material_id < 3.5) {
		ALBEDO = vec3(0.018, 0.023, 0.024);
		ROUGHNESS = 0.95;
		NORMAL_MAP = vec3(0.5, 0.5, 1.0);
	} else {
		ALBEDO = vec3(0.035, 0.105, 0.125);
		ROUGHNESS = 0.42 + texture(metal_roughness, UV).r * 0.16;
		NORMAL_MAP = texture(metal_normal, UV).rgb;
		NORMAL_MAP_DEPTH = 0.10;
	}
}

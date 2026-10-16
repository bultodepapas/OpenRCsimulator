shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D wood_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wood_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wood_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
varying float is_wood;
varying float height_m;
varying float board_variation;

void vertex() {
	is_wood = step(COLOR.b * 1.3, COLOR.r);
	height_m = VERTEX.y;
	board_variation = clamp((COLOR.r - 0.72) / 0.18, 0.0, 1.0);
	// Model-space mapping survives the damage batch's vertex/normal/colour rebuild.
	// Wood049 is a horizontal-grain 0.8 m tile; red carries a per-board offset.
	vec3 n = NORMAL;
	TANGENT = abs(n.x) > 0.9 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
	BINORMAL = normalize(cross(n, TANGENT));
	UV = vec2(dot(VERTEX, TANGENT), dot(VERTEX, BINORMAL)) / 0.8;
	UV += vec2(board_variation * 2.17, board_variation * 3.31);
}

void fragment() {
	vec3 timber = texture(wood_color, UV).rgb;
	float rough = texture(wood_roughness, UV).r;
	// A restrained warm stain; retain the downloaded grain and knots.
	vec3 stain = mix(vec3(0.82, 0.69, 0.53), vec3(1.0, 0.87, 0.69), board_variation);
	vec3 wood = timber * stain * 1.2;
	float soil = mix(0.68, 1.0, smoothstep(0.015, 0.13, height_m));
	ALBEDO = mix(COLOR.rgb * soil, wood, is_wood);
	ROUGHNESS = mix(0.48, clamp(rough * 0.65 + 0.28, 0.65, 0.95), is_wood);
	METALLIC = mix(0.65, 0.0, is_wood);
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), texture(wood_normal, UV).rgb, is_wood);
	NORMAL_MAP_DEPTH = 0.32;
}

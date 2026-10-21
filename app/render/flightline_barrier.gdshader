shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://scenery/vertex_color_linear.gdshaderinc"

uniform sampler2D wood_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wood_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wood_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metal_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metal_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metal_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metalness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D zinc_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D zinc_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D zinc_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D zinc_metalness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float barrier_height_m = 0.65;
varying float is_wood;
varying float height_m;
varying float board_variation;
varying vec2 metal_uv;
varying float upward;
varying float downward;
varying float rail_end_face;
varying float is_fitting;
varying float fitting_tone;

void vertex() {
	// MeshKit's material tags must have the same values on both renderers.
	vec3 mesh_color = vertex_color_to_linear(COLOR.rgb);
	is_wood = step(mesh_color.b * 1.3, mesh_color.r);
	is_fitting = (1.0 - step(0.25, mesh_color.g)) * (1.0 - is_wood);
	fitting_tone = clamp((mesh_color.b - 0.40) / 0.16, 0.0, 1.0);
	height_m = VERTEX.y;
	board_variation = clamp((mesh_color.r - 0.72) / 0.18, 0.0, 1.0);
	// Model-space mapping survives the damage batch's vertex/normal/colour rebuild.
	// Wood060 is a lengthwise-grain 1.15 m tile; red offsets each board.
	vec3 n = NORMAL;
	upward = max(n.y, 0.0);
	downward = max(-n.y, 0.0);
	rail_end_face = step(0.9, abs(n.x));
	TANGENT = abs(n.x) > 0.9 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
	BINORMAL = normalize(cross(n, TANGENT));
	UV = vec2(dot(VERTEX, TANGENT), dot(VERTEX, BINORMAL)) / 1.15;
	UV += vec2(board_variation * 2.17, board_variation * 3.31);
	metal_uv = vec2(dot(VERTEX, TANGENT), dot(VERTEX, BINORMAL)) / 0.35;
}

void fragment() {
	vec3 timber = texture(wood_color, UV).rgb;
	float timber_rough = texture(wood_roughness, UV).r;
	// Wood060 carries actual lengthwise grain. Variation changes exposure, not the grain.
	float patches = texture(wood_roughness, UV * vec2(0.47, 0.73) + vec2(0.21)).r;
	float sunbleach = clamp(0.12 + board_variation * 0.25 + upward * 0.12 + patches * 0.12, 0.0, 0.58);
	// The scan is very dark and high contrast at this scale. Toned, partly
	// silvered timber keeps its real grain without bright orange stippling.
	// These sRGB-authored albedo palette colors need decoding for RD.
	// Numeric literals have no source_color hint; leave GL's accepted recipe intact.
	vec3 wood = mix(timber, vertex_color_to_linear(vec3(0.29, 0.26, 0.22)), 0.60);
	wood = mix(wood, vertex_color_to_linear(vec3(0.32, 0.31, 0.28)), sunbleach * 0.36);
	wood *= 1.27;
	float damp = 1.0 - smoothstep(0.02, 0.22 + patches * 0.12, height_m);
	wood *= mix(vec3(1.0), vec3(0.67, 0.72, 0.61), damp * 0.32);
	// End grain absorbs finish, while downward faces receive a narrow contact shadow.
	wood *= 1.0 - 0.16 * rail_end_face - 0.10 * downward;
	// Metal038 provides real zinc spangle and scratches on posts and fittings.
	vec3 zinc = texture(zinc_color, metal_uv).rgb * vec3(0.80, 0.83, 0.81) + vec3(0.19, 0.20, 0.19);
	float zinc_rough = texture(zinc_roughness, metal_uv).r;
	float zinc_metal = texture(zinc_metalness, metal_uv).r;
	float old_rough = texture(metal_roughness, metal_uv * 0.76).r;
	float rail_step = max((barrier_height_m - 0.06 - 0.24) / 3.0, 0.001);
	float joint = 0.0;
	for (int rail = 0; rail < 4; rail++) {
		joint = max(joint, 1.0 - smoothstep(0.012, 0.055, abs(height_m - (0.24 + float(rail) * rail_step))));
	}
	// Corrosion is confined to the planted foot and the post faces behind saddles.
	float post_joint = joint * rail_end_face * (1.0 - is_fitting);
	float corrosion = (0.02 + damp * (0.14 + old_rough * 0.25) + post_joint * (0.035 + old_rough * 0.10)) * (1.0 - is_fitting);
	vec3 steel = mix(zinc * 0.91, texture(metal_color, metal_uv * 0.76).rgb * 0.93, corrosion);
	vec3 clean_fitting = zinc * (0.97 + 0.12 * fitting_tone);
	steel = mix(steel, clean_fitting, is_fitting);
	// Small local darkening gives the rail bearing and post junction visible depth.
	steel *= 1.0 - 0.08 * downward - 0.07 * post_joint - 0.055 * is_fitting * (1.0 - fitting_tone);
	ALBEDO = mix(steel, wood, is_wood);
	float steel_rough = clamp(0.31 + zinc_rough * 0.42 + corrosion * 0.22 + damp * 0.06, 0.40, 0.82);
	float fitting_rough = clamp(0.30 + zinc_rough * 0.39, 0.39, 0.68);
	ROUGHNESS = mix(mix(steel_rough, fitting_rough, is_fitting), clamp(timber_rough * 0.50 + 0.44, 0.73, 0.97), is_wood);
	METALLIC = mix(mix(mix(zinc_metal * 0.84, texture(metalness, metal_uv * 0.76).r, corrosion), zinc_metal * 0.91, is_fitting), 0.0, is_wood);
	vec3 steel_normal = mix(texture(zinc_normal, metal_uv).rgb, texture(metal_normal, metal_uv * 0.76).rgb, corrosion);
	NORMAL_MAP = mix(steel_normal, texture(wood_normal, UV).rgb, is_wood);
	NORMAL_MAP_DEPTH = mix(mix(0.18, 0.13, is_fitting), 0.11, is_wood);
}

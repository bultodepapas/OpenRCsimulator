shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D wood_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wood_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wood_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metal_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metal_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metal_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metalness : filter_linear_mipmap_anisotropic, repeat_enable;
varying float is_wood;
varying float height_m;
varying float board_variation;
varying vec2 metal_uv;
varying float upward;
varying float is_fitting;
varying float fitting_tone;

void vertex() {
	is_wood = step(COLOR.b * 1.3, COLOR.r);
	is_fitting = (1.0 - step(0.25, COLOR.g)) * (1.0 - is_wood);
	fitting_tone = clamp((COLOR.b - 0.40) / 0.16, 0.0, 1.0);
	height_m = VERTEX.y;
	board_variation = clamp((COLOR.r - 0.72) / 0.18, 0.0, 1.0);
	// Model-space mapping survives the damage batch's vertex/normal/colour rebuild.
	// Wood049 is a horizontal-grain 0.8 m tile; red carries a per-board offset.
	vec3 n = NORMAL;
	upward = max(n.y, 0.0);
	TANGENT = abs(n.x) > 0.9 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
	BINORMAL = normalize(cross(n, TANGENT));
	UV = vec2(dot(VERTEX, TANGENT), dot(VERTEX, BINORMAL)) / 0.8;
	UV += vec2(board_variation * 2.17, board_variation * 3.31);
	metal_uv = vec2(dot(VERTEX, TANGENT), dot(VERTEX, BINORMAL)) / 0.35;
}

void fragment() {
	vec3 timber = texture(wood_color, UV).rgb;
	float rough = texture(wood_roughness, UV).r;
	// Weathering follows the downloaded grain, with distinct exposure per board.
	float patches = texture(wood_roughness, UV * vec2(0.43, 0.71) + vec2(0.21)).r;
	float sunbleach = clamp(0.24 + board_variation * 0.29 + upward * 0.18 + patches * 0.14, 0.0, 0.82);
	float luminance = dot(timber, vec3(0.2126, 0.7152, 0.0722));
	vec3 silvered = vec3(luminance * 0.95 + 0.025, luminance * 0.95 + 0.025, luminance * 0.89 + 0.024);
	vec3 wood = mix(timber * vec3(1.02, 0.88, 0.70), silvered, sunbleach);
	float damp = 1.0 - smoothstep(0.02, 0.22 + patches * 0.12, height_m);
	wood *= mix(vec3(1.0), vec3(0.56, 0.62, 0.43), damp * 0.45);
	// Reuse Metal026's actual corrosion, not orange noise over every surface.
	float wear = clamp(0.45 + damp * 0.42 + upward * 0.12, 0.0, 1.0);
	vec3 steel = mix(COLOR.rgb * 0.78, texture(metal_color, metal_uv).rgb * 1.25, wear);
	steel *= mix(vec3(1.0), vec3(0.48, 0.53, 0.37), damp * 0.6);
	// Zinc-coated saddles and fasteners are cleaner than the older exposed posts.
	float zinc_fleck = texture(metal_roughness, metal_uv * 0.7).r;
	vec3 zinc = mix(vec3(0.43, 0.48, 0.49), vec3(0.65, 0.69, 0.69), fitting_tone);
	steel = mix(steel, zinc * mix(0.93, 1.07, zinc_fleck), is_fitting);
	ALBEDO = mix(steel, wood, is_wood);
	ROUGHNESS = mix(mix(mix(0.48, texture(metal_roughness, metal_uv).r, wear), 0.46 + zinc_fleck * 0.12, is_fitting), clamp(rough * 0.5 + 0.43, 0.73, 0.97), is_wood);
	METALLIC = mix(mix(mix(0.65, texture(metalness, metal_uv).r, wear), 0.78, is_fitting), 0.0, is_wood);
	NORMAL_MAP = mix(texture(metal_normal, metal_uv).rgb, texture(wood_normal, UV).rgb, is_wood);
	NORMAL_MAP_DEPTH = mix(mix(0.2, 0.10, is_fitting), 0.25, is_wood);
}

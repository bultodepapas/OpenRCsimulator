shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

global uniform float sim_clock;
global uniform vec3 wind_vec;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_albedo_texture = false;
uniform vec2 uv1_scale = vec2(1.0);
uniform vec2 uv1_offset = vec2(0.0);
uniform bool use_vertex_color = true;
uniform bool vertex_color_is_srgb = false;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap;
uniform bool use_normal_texture = false;
uniform float normal_scale = 1.0;
uniform float roughness = 1.0;
uniform float metallic = 0.0;
uniform float specular = 0.5;
uniform bool use_alpha_scissor = false;
uniform float alpha_scissor_threshold = 0.5;
uniform float plant_height = 1.0;
uniform float plant_base_y = 0.0;
uniform vec2 wind_direction = vec2(0.8, 0.6);
uniform float wind_strength = 0.0;
// Tree wind (L15b-R2) uses imported_tree_wind*.gdshader; this shader is the legacy all-role path.

void vertex() {
	float raw_height = (VERTEX.y - plant_base_y) / max(plant_height, 0.001);
	float normalized_height = clamp(raw_height, 0.0, 1.0);
	vec3 local_wind = transpose(mat3(MODEL_MATRIX)) * vec3(wind_vec.x, 0.0, wind_vec.z);
	float wind_speed = length(wind_vec.xz);
	vec2 direction = local_wind.xz / max(length(local_wind.xz), 0.001);
	float phase = 6.2831853 * fract((256.0 / 1024.0) * sim_clock + INSTANCE_CUSTOM.r);
	phase += dot(VERTEX.xz, wind_direction) * 0.7;
	float phase_amplitude = sin(phase) * wind_strength * min(wind_speed / 5.0, 1.0);
	float sway = phase_amplitude
		* normalized_height * normalized_height;
	VERTEX.xz += direction * sway;
}

vec3 srgb_to_linear(vec3 value) {
	return vec3(
		value.r <= 0.04045 ? value.r / 12.92 : pow((value.r + 0.055) / 1.055, 2.4),
		value.g <= 0.04045 ? value.g / 12.92 : pow((value.g + 0.055) / 1.055, 2.4),
		value.b <= 0.04045 ? value.b / 12.92 : pow((value.b + 0.055) / 1.055, 2.4)
	);
}

void fragment() {
	vec4 color = albedo_color;
	vec2 material_uv = UV * uv1_scale + uv1_offset;
	if (use_albedo_texture) {
		color *= texture(albedo_texture, material_uv);
	}
	if (use_vertex_color) {
		vec4 vertex_color = COLOR;
		if (vertex_color_is_srgb) {
			vertex_color.rgb = srgb_to_linear(vertex_color.rgb);
		}
		color *= vertex_color;
	}
	if (use_alpha_scissor) {
		if (color.a < alpha_scissor_threshold) {
			discard;
		}
		color.a = 1.0;
	}
	ALBEDO = color.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = specular;
	if (use_normal_texture) {
		NORMAL_MAP = texture(normal_texture, material_uv).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
}

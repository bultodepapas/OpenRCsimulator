// L15c: qualified opaque Quaternius grass; source color/UVs and back-face lighting retained.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

global uniform float sim_clock;
global uniform vec3 wind_vec;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec2 uv1_scale = vec2(1.0);
uniform vec2 uv1_offset = vec2(0.0);
uniform bool use_vertex_color = false;
uniform float roughness = 1.0;
uniform float metallic = 0.0;
uniform float specular = 0.5;
uniform float plant_height = 1.0;
uniform float plant_base_y = 0.0;
uniform float wind_strength = 0.12;
varying float blade_height;

void vertex() {
	blade_height = clamp((VERTEX.y - plant_base_y) / max(plant_height, 0.001), 0.0, 1.0);
	// The source pipeline accepts uniform scale. Normalization removes its magnitude.
	vec2 local_wind = (transpose(mat3(MODEL_MATRIX)) * vec3(wind_vec.x, 0.0, wind_vec.z)).xz;
	vec2 direction = local_wind / max(length(local_wind), 0.0001);
	vec3 anchor = (MODEL_MATRIX * vec4(0.0, plant_base_y, 0.0, 1.0)).xyz;
	// Both frequencies are integer multiples of 1/1024 Hz, matching ShaderClock's wrap.
	float gust = sin(6.28318530718 * (96.0 / 1024.0) * sim_clock + dot(anchor.xz, vec2(0.07, 0.09)));
	float flutter = sin(6.28318530718 * ((256.0 / 1024.0) * sim_clock + INSTANCE_CUSTOM.r));
	float response = min(length(wind_vec.xz) / 5.0, 1.0) * (0.55 + 0.25 * gust + 0.20 * flutter);
	float bend = clamp(wind_strength, 0.0, 0.12) * response;
	if (bend > 0.0) {
		VERTEX.xz += direction * plant_height * bend * blade_height * blade_height;
		// Inverse-transpose of the height-weighted shear keeps lighting attached to the bent blade.
		NORMAL.y -= dot(NORMAL.xz, direction) * (2.0 * bend * blade_height);
		NORMAL = normalize(NORMAL);
	}
	UV = UV * uv1_scale + uv1_offset;
}

void fragment() {
	ALBEDO = albedo_color.rgb * texture(albedo_texture, UV).rgb;
	if (use_vertex_color) {
		ALBEDO *= COLOR.rgb;
	}
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = specular;
}

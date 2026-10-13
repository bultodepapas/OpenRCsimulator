shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_albedo_texture = false;
uniform bool use_vertex_color = true;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap;
uniform bool use_normal_texture = false;
uniform float normal_scale = 1.0;
uniform float roughness = 1.0;
uniform float metallic = 0.0;
uniform bool use_alpha_scissor = false;
uniform float alpha_scissor_threshold = 0.5;
uniform float plant_height = 1.0;
uniform float plant_base_y = 0.0;

instance uniform vec2 wind_direction = vec2(1.0, 0.0);
instance uniform float wind_strength = 0.0;

void vertex() {
	float normalized_height = clamp((VERTEX.y - plant_base_y) / max(plant_height, 0.001), 0.0, 1.0);
	float phase = INSTANCE_CUSTOM.r * 6.2831853 + TIME * 1.35 + dot(VERTEX.xz, wind_direction) * 0.7;
	float sway = sin(phase) * wind_strength * normalized_height * normalized_height;
	VERTEX.x += wind_direction.x * sway;
	VERTEX.z += wind_direction.y * sway;
}

void fragment() {
	vec4 color = albedo_color;
	if (use_albedo_texture) {
		color *= texture(albedo_texture, UV);
	}
	if (use_vertex_color) {
		color *= COLOR;
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
	if (use_normal_texture) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
}

shader_type spatial;
render_mode blend_mix, depth_draw_never;

uniform float dirt_amount : hint_range(0.0, 0.46) = 0.0;
uniform float dirt_opacity_gain : hint_range(1.0, 2.0) = 1.0;
uniform float wet_amount : hint_range(0.0, 1.0) = 0.0;
uniform float dirt_band_bottom = -0.02;
uniform float dirt_band_top = 0.08;
uniform bool use_vehicle_space = false;
uniform mat4 vehicle_from_world;

varying float model_height;

void vertex() {
	model_height = VERTEX.y;
	if (use_vehicle_space) {
		model_height = (vehicle_from_world * MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	}
}

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	float vertical_mask = 1.0 - smoothstep(dirt_band_bottom, dirt_band_top, model_height);
	float broad = hash21(floor(UV * vec2(18.0, 12.0)));
	float grit = hash21(floor(UV * vec2(107.0, 83.0)));
	float pattern = 0.2 + 0.52 * broad + 0.28 * grit;
	float dirt_alpha = clamp(
		dirt_amount * vertical_mask * pattern * dirt_opacity_gain,
		0.0,
		0.24 * dirt_opacity_gain
	);
	if (wet_amount <= 0.0) {
		ALBEDO = vec3(0.22, 0.13, 0.065);
		ROUGHNESS = 1.0;
		ALPHA = dirt_alpha;
	} else {
		float sheen_alpha = clamp(wet_amount * 0.12 * (0.3 + 0.7 * vertical_mask), 0.0, 0.12);
		float combined_alpha = 1.0 - (1.0 - dirt_alpha) * (1.0 - sheen_alpha);
		float sheen_weight = sheen_alpha / max(combined_alpha, 0.0001);
		ALBEDO = mix(vec3(0.22, 0.13, 0.065), vec3(0.16, 0.21, 0.24), sheen_weight);
		ROUGHNESS = mix(1.0, 0.13, clamp(wet_amount, 0.0, 1.0));
		SPECULAR = mix(0.5, 0.92, clamp(wet_amount, 0.0, 1.0));
		METALLIC = 0.04 * clamp(wet_amount, 0.0, 1.0);
		ALPHA = combined_alpha;
	}
}

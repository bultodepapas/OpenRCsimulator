shader_type spatial;
render_mode blend_mix, depth_draw_never;

uniform float dirt_amount : hint_range(0.0, 0.46) = 0.0;
uniform float dirt_band_bottom = -0.02;
uniform float dirt_band_top = 0.08;

varying float model_height;

void vertex() {
	model_height = VERTEX.y;
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
	ALBEDO = vec3(0.22, 0.13, 0.065);
	ROUGHNESS = 1.0;
	ALPHA = clamp(dirt_amount * vertical_mask * pattern, 0.0, 0.24);
}

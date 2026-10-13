// LU-24 original rooted botanical wind. Opaque, double-sided geometry; no alpha overdraw.
shader_type spatial;
render_mode cull_disabled;
global uniform float sim_clock;
global uniform vec3 wind_vec;
varying vec3 plant_colour;

void vertex() {
	plant_colour = COLOR.rgb * INSTANCE_CUSTOM.rgb;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = fract(origin.x * 0.137 + origin.z * 0.719);
	float h = clamp(VERTEX.y, 0.0, 1.0);
	float speed = length(wind_vec.xz);
	vec2 direction = wind_vec.xz / max(speed, 0.001);
	float wave = sin(TAU * fract(0.25 * sim_clock + phase));
	float breeze = sin(TAU * fract(0.5 * sim_clock + phase));
	// Maximum local displacement 0.058 m; placement reserves 0.4 m and node bounds 0.12 m.
	VERTEX.xz += (direction * 0.05 * min(speed / 5.0, 1.0) * wave + vec2(0.008 * breeze, 0.0)) * h * h;
}

void fragment() {
	ALBEDO = plant_colour;
	ROUGHNESS = 0.96;
	SPECULAR = 0.15;
}

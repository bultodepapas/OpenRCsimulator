// Local leaf litter from Poly Haven Forest Leaves 02 (CC0); world-space metres.
shader_type spatial;
render_mode cull_back, depth_draw_never;

uniform sampler2D litter_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 world_position;

float noise_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise_value(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(noise_hash(cell), noise_hash(cell + vec2(1.0, 0.0)), f.x),
		mix(noise_hash(cell + vec2(0.0, 1.0)), noise_hash(cell + vec2(1.0)), f.x), f.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// A 3 m source tile retains the supplier's physical scale. Edges stay inside each certified square.
	ALBEDO = texture(litter_albedo, world_position.xz / 3.0).rgb;
	float irregular_radius = length((UV - 0.5) * 2.0)
		+ 0.20 * (noise_value(world_position.xz * 1.7) - 0.5);
	float edge = 1.0 - smoothstep(0.38, 0.92, irregular_radius);
	float mottling = 0.26 + 0.24 * noise_value(world_position.xz * 2.3);
	float distance_fade = 1.0 - smoothstep(45.0, 80.0, distance(world_position, CAMERA_POSITION_WORLD));
	ALPHA = edge * mottling * distance_fade;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

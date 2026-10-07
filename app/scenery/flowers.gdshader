// SCENERY-PLAN SC-16: wildflower cushions, one MultiMesh per chunk. Ours, MIT. The cushion mesh carries its green in the
// vertex colour (alpha 1; linearised by the engine) and marks petal vertices with alpha 0; each instance's petal colour arrives in INSTANCE_CUSTOM
// (already linear; Compatibility packs custom data to 16-bit halves, enough for colour). Sway on sim_clock, never TIME.
shader_type spatial;
render_mode cull_back;

global uniform float sim_clock;
global uniform vec3 wind_vec;

varying vec3 v_col;

void vertex() {
	vec3 leaf = COLOR.rgb; // Compatibility already delivers vertex colours linearised (measured: same pixels as an albedo colour)
	v_col = mix(leaf, INSTANCE_CUSTOM.rgb, 1.0 - COLOR.a);
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float ph = fract(origin.x * 0.137 + origin.z * 0.719); // per-plant phase from its position, no RNG
	float h = clamp(VERTEX.y / 0.4, 0.0, 1.0);
	float wind = length(wind_vec);
	float sway = (0.012 + 0.006 * min(wind, 10.0)) * h * h; // metres, estimated
	VERTEX.x += sway * sin(TAU * fract(0.5 * sim_clock + ph)); // 0.5 Hz = 512/1024
}

void fragment() {
	ALBEDO = v_col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}

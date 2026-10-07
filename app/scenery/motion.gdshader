// SCENERY-PLAN SC-18: moving scenery parts (turbine rotors, the club flag). Ours, MIT. Never TIME (L0d): everything runs
// on the global sim_clock (simulation time wrapped to [0, 1024) s) and wind_vec (zero until M5), so the same simulation
// time gives the same pixels, pause freezes, and every frequency is a multiple of 1/1024 Hz (the wrap is seamless).
// Vertex colours are written in sRGB by mesh_kit.gd; Compatibility linearises them before the shader (measured).
shader_type spatial;
render_mode cull_back;

global uniform float sim_clock;
global uniform vec3 wind_vec;

uniform int mode = 0;          // 0: rotor about local +Z; 1: flag waving along local +X
uniform float rate = 0.25;     // rotor turns per second (multiple of 1/1024)
uniform float phase = 0.0;     // fraction of a turn / wave
uniform float idle_wind = 3.0; // m/s the flag shows while the simulation has no wind (a gentle breeze, estimated)

varying vec3 v_col;

void vertex() {
	v_col = COLOR.rgb; // already linear in Compatibility (measured, see flowers.gdshader)
	if (mode == 0) {
		float a = -TAU * fract(rate * sim_clock + phase);
		mat2 r = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
		VERTEX.xy = r * VERTEX.xy;
		NORMAL.xy = r * NORMAL.xy;
	} else {
		float wind = max(length(wind_vec), idle_wind);
		float x = max(VERTEX.x, 0.0);
		float amp = 0.035 + 0.012 * clamp(wind, 0.0, 15.0); // metres per metre from the hoist, estimated
		float w = TAU * fract(1.0 * sim_clock + phase);      // 1 Hz = 1024/1024
		float k = 3.2;                                       // rad per metre along the flag
		float s = sin(k * x - w);
		VERTEX.z += amp * x * s;
		VERTEX.y -= 0.04 * x * x * max(0.0, 1.0 - wind / 8.0); // droops a little in light wind
		vec3 tangent = normalize(vec3(1.0, 0.0, amp * (s + k * x * cos(k * x - w))));
		NORMAL = normalize(vec3(-tangent.z, 0.0, tangent.x)) * sign(NORMAL.z + 1e-4);
	}
}

void fragment() {
	ALBEDO = v_col;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
}

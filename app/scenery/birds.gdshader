// SCENERY-PLAN SC-20 (optional, off by default): a distant flock on an analytic path. Ours, MIT. No state and no TIME:
// position and wingbeat are functions of sim_clock only (frequencies are multiples of 1/1024 Hz), so the same simulation
// time draws the same birds. Each instance's offset and phase arrive in INSTANCE_CUSTOM.
shader_type spatial;
render_mode cull_disabled;

global uniform float sim_clock;

uniform float radius_m = 140.0;
uniform float loop_hz = 0.0078125; // 8/1024 Hz: one lap every 128 s
uniform float flap_hz = 4.0;       // 4096/1024 Hz

varying vec3 v_col;

void vertex() {
	vec4 c = INSTANCE_CUSTOM; // xyz: offset in the flock (m), w: phase in [0, 1)
	float a = TAU * fract(loop_hz * sim_clock + c.w * 0.05);
	vec3 centre = vec3(cos(a) * radius_m, 6.0 * sin(2.0 * a) + c.y, sin(a) * radius_m * 0.6);
	vec3 tangent = normalize(vec3(-sin(a) * radius_m, 12.0 * cos(2.0 * a), cos(a) * radius_m * 0.6));
	float yaw = atan(tangent.x, tangent.z);
	float flap = sin(TAU * fract(flap_hz * sim_clock + c.w));
	vec3 v = VERTEX;
	v.y += flap * 0.35 * abs(v.x);
	mat2 r = mat2(vec2(cos(yaw), -sin(yaw)), vec2(sin(yaw), cos(yaw)));
	v.xz = r * v.xz;
	VERTEX = v + centre + vec3(c.x, 0.0, c.z);
	v_col = vec3(0.05, 0.05, 0.06);
}

void fragment() {
	ALBEDO = v_col;
	ROUGHNESS = 1.0;
}

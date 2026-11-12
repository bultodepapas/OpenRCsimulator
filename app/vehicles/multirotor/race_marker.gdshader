// DR-32 floating guidance light: a camera-facing additive sprite (unlit, never a solid). shape 0 draws a soft dot (the
// path to the next gate, brightness flowing toward it by the instance's COLOR.a position); shape 1 draws a downward
// chevron that bobs above the next gate.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 marker_color : source_color = vec4(0.3, 1.0, 0.2, 1.0);
uniform float energy = 1.0;
uniform int shape = 0;
uniform float flow_speed = 0.9;
uniform float bob_m = 0.12;

varying float flow;

void vertex() {
	flow = COLOR.a;
	vec3 lift = shape == 1 ? vec3(0.0, sin(TIME * 2.6) * bob_m, 0.0) : vec3(0.0);
	// Billboard: keep the instance origin, face the camera.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3] + vec4(lift, 0.0));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float alpha;
	if (shape == 1) {
		// A "V" pointing down: distance to the two arms.
		// UV y grows downward: the apex sits low (p.y = 0.35) and the arms rise outward, a "V".
		float arm = abs(p.y - 0.35 + abs(p.x) * 0.9);
		alpha = (1.0 - smoothstep(0.08, 0.22, arm)) * step(abs(p.x), 0.85);
	} else {
		alpha = pow(clamp(1.0 - length(p), 0.0, 1.0), 2.0);
	}
	float wave = shape == 1 ? 1.0 : 0.35 + 0.65 * pow(fract(flow * 4.0 - TIME * flow_speed), 3.0);
	ALBEDO = marker_color.rgb * alpha * energy * wave;
}

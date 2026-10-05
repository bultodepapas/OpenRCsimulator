// Sky background (L1a, LANDSCAPE-PLAN; investigations 01 and 02). Ours, MIT.
// Gradient pow(1 − y, 2.6) from zenith to horizon (fitted to Hosek-Wilkie at a 45° sun), a 0.53° sun disc and halo
// drawn from LIGHT0 (so the disc and the DirectionalLight3D share one direction by construction), Godot's
// interleaved-gradient debanding. Never TIME: the radiance is not re-rendered every frame and captures repeat.
shader_type sky;
render_mode use_debanding;

uniform vec3 zenith_color : source_color = vec3(0.306, 0.408, 0.576);
uniform vec3 horizon_color : source_color = vec3(0.788, 0.890, 0.929);
uniform vec3 ground_color : source_color = vec3(0.541, 0.604, 0.502);
uniform float gradient_curve = 2.6;
uniform float sun_radius = 0.0046251; // rad: half of 0.53°, from Spec.ATMOSPHERE (LIGHT0_SIZE defaults to 0)

vec3 sky_color(vec3 dir) {
	vec3 col;
	if (dir.y >= 0.0) {
		col = mix(zenith_color, horizon_color, pow(1.0 - dir.y, gradient_curve));
	} else {
		col = mix(horizon_color, ground_color, smoothstep(0.0, 0.08, -dir.y));
	}
	if (LIGHT0_ENABLED) {
		float ang = acos(clamp(dot(dir, LIGHT0_DIRECTION), -1.0, 1.0));
		col += LIGHT0_COLOR * (exp(-ang * 18.0) * 0.35 + 4.0 * (1.0 - smoothstep(0.9 * sun_radius, 1.1 * sun_radius, ang)));
	}
	return col;
}

void sky() {
	COLOR = sky_color(EYEDIR);
}

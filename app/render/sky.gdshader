// Sky background (L1a, L2; LANDSCAPE-PLAN, investigations 01 and 02). Ours, MIT.
// Gradient from the horizon haze to the zenith with weight 1 − (1 − y)^2.6 (Hosek-Wilkie fit at a 45° sun). The
// horizon is EXACTLY the colour the engine fogs distant objects toward (GLES3 fog_process: fog light colour + the
// sun's ×π scatter term), so far terrain melts into the sky with no seam. Below the horizon: pure haze. A 0.53° sun
// disc and halo. Godot's debanding. Never TIME (captures repeat; the radiance renders once).
//
// Colour space (read from the 4.7.2 GLES3 sky.glsl, line 250): Compatibility treats a sky shader's COLOR as sRGB
// and converts it with a cubic srgb_to_linear right after our code. So all maths here is linear (uniforms are linear,
// computed on the CPU) and the result is encoded with the exact inverse of that cubic: the engine gets our linear
// value back, the same number the ground's fog and the engine's object fog use.
shader_type sky;
render_mode use_debanding;

uniform vec3 zenith_lin = vec3(0.076, 0.138, 0.287);
uniform vec3 haze_lin = vec3(0.584, 0.768, 0.846); // fog_light_color.srgb_to_linear() * fog_light_energy
uniform vec3 sun_dir = vec3(0.0, 0.707, 0.707);    // toward the sun == the light's basis.z
uniform vec3 sun_lin = vec3(3.14159);              // light_color.srgb_to_linear() * light_energy * PI
uniform float sun_scatter = 0.0;                   // == Environment.fog_sun_scatter
uniform float gradient_curve = 2.6;
uniform float sun_radius = 0.0046251;              // rad: half of 0.53° (LIGHT0_SIZE defaults to 0)

vec3 haze(vec3 d) {
	return haze_lin + sun_lin * pow(max(dot(d, sun_dir), 0.0), 8.0) * sun_scatter;
}

// Exact inverse of the engine's srgb_to_linear(s) = s·(s·(0.305306011·s + 0.682171111) + 0.012522878):
// Newton's method from the engine's own linear_to_srgb approximation; 3 steps reach float precision.
vec3 encode_for_engine(vec3 x) {
	vec3 s = max(vec3(1.055) * pow(max(x, vec3(0.0)), vec3(0.416666667)) - vec3(0.055), vec3(0.0));
	for (int i = 0; i < 3; i++) {
		vec3 f = s * (s * (s * 0.305306011 + 0.682171111) + 0.012522878) - x;
		vec3 df = s * (s * 0.915918033 + 1.364342222) + 0.012522878;
		s -= f / df;
	}
	return s;
}

void sky() {
	float y = max(EYEDIR.y, 0.0);
	vec3 col = mix(haze(EYEDIR), zenith_lin, 1.0 - pow(1.0 - y, gradient_curve));
	float ang = acos(clamp(dot(EYEDIR, sun_dir), -1.0, 1.0));
	col += (sun_lin / PI) * (exp(-ang * 18.0) * 0.35 + 4.0 * (1.0 - smoothstep(0.9 * sun_radius, 1.1 * sun_radius, ang)));
	COLOR = encode_for_engine(col);
}

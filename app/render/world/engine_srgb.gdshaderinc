// FIELD-WORLD-PLAN FW-24/FW-33: Godot 4.7.2 Compatibility converts every material's ALBEDO and EMISSION with its
// cubic srgb_to_linear (drivers/gles3/shaders/scene.glsl line 2398; tonemap_inc.glsl), as it does for a sky
// shader's COLOR (LANDSCAPE L2). Self-luminous unshaded shaders that compute LINEAR scene radiance encode it here
// with the exact inverse of that cubic, so the engine gets the intended value back. Without it a faint value is
// divided by ~13 (the cubic's slope at zero is 0.0125): stars and lamp sprites came out ~40× too dim (FW-24).

// Exact inverse of s·(s·(0.305306011·s + 0.682171111) + 0.012522878): Newton from the sRGB curve, 3 steps.
vec3 encode_for_engine(vec3 x) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 s = max(vec3(1.055) * pow(max(x, vec3(0.0)), vec3(0.416666667)) - vec3(0.055), vec3(0.0));
	for (int i = 0; i < 3; i++) {
		vec3 f = s * (s * (s * 0.305306011 + 0.682171111) + 0.012522878) - x;
		vec3 df = s * (s * 0.915918033 + 1.364342222) + 0.012522878;
		s -= f / df;
	}
	return s;
#else
	// RD spatial ALBEDO is already linear; applying the GL inverse here makes
	// faint stars, lamps and weather effects excessively bright at night.
	return x;
#endif
}

// FW-84 seeded storm channel ribbon: no particles, timers, collision queries or TIME.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled;

uniform vec3 bolt_color = vec3(0.69, 0.82, 1.0);
uniform float bolt_intensity = 0.0;
uniform bool core_pass = false;
uniform float display_cap = 2.0;
uniform float albedo_display_cap = 0.75;

void fragment() {
	float across = abs(UV.x * 2.0 - 1.0);
	float along = smoothstep(0.0, 0.04, UV.y) * (1.0 - smoothstep(0.94, 1.0, UV.y));
	float edge = 1.0 - smoothstep(0.08, 1.0, across);
	float core = 1.0 - smoothstep(0.0, 0.42, across);
	float value = core_pass ? core : edge * 0.28;
	float glow = clamp(bolt_intensity, 0.0, 1.5) * value * along;
	if (glow <= 0.001) {
		discard;
	}
	// Unshaded material output is not scaled by Environment exposure in the same
	// way as lit surfaces. Keep its capped color independent of the exposure input.
	ALBEDO = bolt_color * min(1.0, albedo_display_cap);
	float base_emission = core_pass ? 4.8 : 1.5;
	float output_gain = min(glow * base_emission, display_cap);
	EMISSION = bolt_color * output_gain;
	ALPHA = clamp(glow * (core_pass ? 0.95 : 0.42), 0.0, 0.88);
}

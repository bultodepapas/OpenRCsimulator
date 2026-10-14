// FW-84 seeded storm channel ribbon: no particles, timers, collision queries or TIME.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled;
#include "res://render/world/engine_srgb.gdshaderinc"

uniform vec3 bolt_color = vec3(0.88, 0.94, 1.0);
uniform float bolt_intensity = 0.0;
uniform bool core_pass = false;
uniform float display_cap = 2.0;
uniform float scene_exposure = 1.0;

void fragment() {
	float across = abs(UV.x * 2.0 - 1.0);
	float along = smoothstep(0.0, 0.04, UV.y) * (1.0 - smoothstep(0.94, 1.0, UV.y));
	float edge = 1.0 - smoothstep(0.08, 1.0, across);
	// Keep a small bright core readable through the distant rain at 720p.
	// Ribbon widths represent apparent bloom, not a physical channel diameter.
	float core = 1.0 - smoothstep(0.18, 0.72, across);
	float value = core_pass ? core : edge * 0.45;
	float glow = clamp(bolt_intensity, 0.0, 1.5) * value * along;
	if (glow <= 0.001) {
		discard;
	}
	// GLES3 linearizes ALBEDO then applies exposure even for unshaded materials.
	// Encode a bounded scene-linear contribution; MODE_UNSHADED ignores EMISSION.
	ALBEDO = encode_for_engine(bolt_color * display_cap / max(scene_exposure, 0.001));
	ALPHA = clamp(glow * (core_pass ? 1.6 : 0.8), 0.0, 0.95);
}

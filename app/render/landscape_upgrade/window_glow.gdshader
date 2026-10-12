// LU-03: transparent glazing overlay for the shallow clubhouse window inserts and shielded wall lamps.
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

#include "res://render/world/engine_srgb.gdshaderinc"

global uniform float world_exposure;

uniform vec3 warm_tint : source_color = vec3(1.0, 0.62, 0.34);
uniform float night_glow : hint_range(0.0, 1.0) = 0.0;
uniform float display_cap = 0.55;

void fragment() {
	float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float pane = smoothstep(0.0, 0.08, edge);
	float room_variation = 0.72 + 0.28 * UV.y;
	vec3 tint = warm_tint * room_variation;
	float target = display_cap * night_glow;
	float brightest = max(max(tint.r, tint.g), tint.b);
	vec3 display_color = tint * min(1.0, target / max(brightest * world_exposure, 0.0001));
	ALBEDO = encode_for_engine(display_color);
	ALPHA = pane * mix(0.015, 0.50, night_glow);
}

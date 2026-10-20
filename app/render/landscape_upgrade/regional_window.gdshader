// Seeded occupied rooms. Facade quads keep real orientation and depth occlusion.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, fog_disabled, shadows_disabled;
#include "res://render/world/engine_srgb.gdshaderinc"
global uniform float world_exposure;
uniform float night_factor = 0.0;
varying vec3 tint;
varying float occupancy;
void vertex() {
	tint = COLOR.rgb;
	occupancy = INSTANCE_CUSTOM.r;
}
void fragment() {
	float edge = min(min(UV.x, 1.0-UV.x), min(UV.y, 1.0-UV.y));
	float mullion = smoothstep(0.018, 0.038, abs(UV.x - 0.5));
	float curtain = mix(0.45, 1.0, smoothstep(0.12, 0.3, UV.x));
	float room = (0.65 + 0.35 * UV.y) * curtain;
	ALBEDO = encode_for_engine(tint * room * 0.48 * occupancy * night_factor / max(world_exposure, 0.001));
	ALPHA = smoothstep(0.0, 0.06, edge) * mullion * night_factor;
}

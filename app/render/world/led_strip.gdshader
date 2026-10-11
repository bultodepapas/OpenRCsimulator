// FIELD-WORLD-PLAN FW-62: a self-luminous LED strip as a ribbon along a centre line. Each vertex sits on the line;
// NORMAL carries the across-strip direction and UV.x the side (−1/+1). The ribbon is `width_m` wide up close and held
// at `min_px` reference pixels far away, its radiance scaled by the width ratio so the strip's flux is conserved
// (like render/world/light_sprite.gdshader). Capped on screen against the eye's adaptation (`world_exposure`), and
// encoded for the engine's ALBEDO linearisation.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, fog_disabled, shadows_disabled, skip_vertex_transform;
#include "res://render/world/engine_srgb.gdshaderinc"

global uniform float world_exposure;

uniform vec3 light_color : source_color = vec3(0.12, 0.72, 1.0);
uniform float radiance = 1.0;
uniform float width_m = 0.015;
uniform float min_px = 2.0;
uniform float rad_per_px = 0.001212;
uniform float display_cap = 2.0;

varying float gain;

void vertex() {
	vec3 centre = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 side = normalize(mat3(MODELVIEW_MATRIX) * NORMAL);
	float width = max(width_m, length(centre) * min_px * rad_per_px);
	VERTEX = centre + side * UV.x * width * 0.5;
	NORMAL = vec3(0.0, 0.0, 1.0);
	gain = width_m / width;
}

void fragment() {
	ALBEDO = encode_for_engine(light_color * min(radiance * gain, display_cap / world_exposure));
}

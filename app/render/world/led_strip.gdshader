// FIELD-WORLD-PLAN FW-62: a self-luminous LED strip as a ribbon along a centre line. Each vertex sits on the line;
// NORMAL carries the across-strip direction and UV.x the side (−1/+1). The ribbon is `width_m` wide up close and held
// at `min_px` pixels in the current camera far away, its radiance scaled by the width ratio so flux is conserved
// (like render/world/light_sprite.gdshader). Capped on screen against the eye's adaptation (`world_exposure`), and
// encoded for the engine's ALBEDO linearisation.
shader_type spatial;
// Add light without covering the aircraft with an opaque, dim ribbon at dusk (FW-62-R1).
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled, skip_vertex_transform;
#include "res://render/world/engine_srgb.gdshaderinc"

global uniform float world_exposure;

uniform vec3 light_color : source_color = vec3(0.12, 0.72, 1.0);
uniform float radiance = 1.0;
uniform float width_m = 0.015;
uniform float min_px = 2.0;
uniform float display_cap = 2.0;

varying float gain;
varying float underside;

void vertex() {
	vec3 centre = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 side = normalize(mat3(MODELVIEW_MATRIX) * NORMAL);
	// The pilot zoom and viewport size change every frame. A fixed 50-degree reference made a two-pixel strip
	// almost eighteen pixels wide at six degrees, pushing it through and outside the wing.
	float depth_scale = PROJECTION_MATRIX[3][3] == 0.0 ? max(-centre.z, 0.001) : 1.0;
	float metres_per_pixel = 2.0 * depth_scale / (VIEWPORT_SIZE.y * abs(PROJECTION_MATRIX[1][1]));
	float width = max(width_m, min_px * metres_per_pixel);
	VERTEX = centre + side * UV.x * width * 0.5;
	NORMAL = vec3(0.0, 0.0, 1.0);
	gain = width_m / width;
	// The root-frame belly faces -Y. Suppress the strip from above even if sub-pixel wing depth rounds to a tie.
	vec3 belly = normalize(mat3(MODELVIEW_MATRIX) * vec3(0.0, -1.0, 0.0));
	underside = dot(belly, normalize(-centre));
}

void fragment() {
	ALBEDO = encode_for_engine(light_color * min(radiance * gain, display_cap / world_exposure));
	ALPHA = exp(-4.0 * UV.x * UV.x) * smoothstep(0.0, 0.15, underside);
}

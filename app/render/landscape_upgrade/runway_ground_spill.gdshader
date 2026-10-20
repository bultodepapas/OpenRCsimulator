// A small diffuse pool on dry turf immediately under each low edge marker.
// This is a batched visual approximation, not a specular reflection or a lux measurement.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

#include "res://render/world/engine_srgb.gdshaderinc"

global uniform float world_exposure;

uniform vec3 tint : source_color = vec3(0.91, 0.87, 0.78);
uniform float radiance = 0.02;
uniform float display_cap = 0.05;
uniform float night_factor = 0.0;

void fragment() {
	float radius = length(UV * 2.0 - 1.0);
	float falloff = pow(max(1.0 - radius, 0.0), 2.0);
	float emission = min(radiance, display_cap / max(world_exposure, 0.001)) * night_factor;
	ALBEDO = encode_for_engine(tint * emission);
	ALPHA = falloff * 0.35;
}

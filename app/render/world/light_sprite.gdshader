// FIELD-WORLD-PLAN FW-33/FW-35: a self-luminous point (LED, lamp, beacon) as a camera-facing quad.
// Physical core: `size_m` across at `radiance` (scene-linear, sun irradiance = 1). Far away the quad is held at
// `min_px` reference pixels and its radiance scaled down by the area ratio, so the light's flux is conserved: a
// navigation LED vanishes in daylight but blazes under the night exposure, as real ones do.
// `display_cap` / `world_exposure` limits the on-screen value after exposure, so a saturated LED keeps its hue instead of
// clipping to white under the night exposure (ACES desaturates very bright values); it never brightens anything.
// Optional flashing on sim_clock (never TIME): `flash` = (period s, pulse s, second pulse offset s, 0/1 enabled);
// periods must be multiples of 1/1024 s so the clock wrap is seamless.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled, skip_vertex_transform;

#include "res://render/world/engine_srgb.gdshaderinc"

global uniform float sim_clock;
global uniform float world_exposure; // the eye's current adaptation (render/world/exposure.gd)

uniform vec3 light_color : source_color = vec3(1.0);
uniform float radiance = 2.0;
uniform float size_m = 0.02;
uniform float min_px = 2.5;
uniform float rad_per_px = 0.001212;   // reference 50° / 720 px
uniform vec4 flash = vec4(1.0, 0.0, 0.0, 0.0);
uniform float display_cap = 1.5;

varying float gain;

void vertex() {
	vec3 center = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float dist = length(center);
	float size = max(size_m, dist * min_px * rad_per_px);
	VERTEX = center + vec3(VERTEX.xy * size, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
	gain = (size_m * size_m) / (size * size);
	if (flash.w > 0.5) {
		float t = mod(sim_clock, flash.x);
		gain *= (t < flash.y || (flash.z > 0.0 && t >= flash.z && t < flash.z + flash.y)) ? 1.0 : 0.0;
	}
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	ALBEDO = encode_for_engine(light_color * min(radiance * gain, display_cap / world_exposure)); // linearised again by the engine
	ALPHA = exp(-4.0 * dot(p, p));
}

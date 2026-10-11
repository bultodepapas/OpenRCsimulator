// FIELD-WORLD-PLAN FW-24: naked-eye stars as tiny camera-facing quads of a fixed pixel size, one MultiMesh.
// Brightness is physical (render/world/stars.gd: star irradiance spread over the quad), so the exposure alone decides
// when they show: invisible by day, the brightest in nautical twilight, thousands on a moonless night.
// Dimmed by atmospheric extinction near the horizon, hidden by the same cloud deck the sky draws, gently scintillating
// on sim_clock (never TIME). Ground, hills and trees hide them by depth.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled, skip_vertex_transform;
#include "res://render/cloud_field.gdshaderinc"
#include "res://render/world/engine_srgb.gdshaderinc"

global uniform float sim_clock;
global uniform vec2 cloud_drift_offset;

uniform float radiance_scale = 8.2e-6;     // peak quad radiance of a V = 0 star (scene units)
uniform float size_px = 3.0;               // quad edge in pixels
uniform float rad_per_px = 0.001212;       // angular pixel size of the reference view (50° over 720 px)
uniform float extinction_mag = 0.2;        // V-band extinction per airmass (borrowed: a good rural site)
uniform float scintillation = 0.18;        // relative flicker amplitude at the horizon (estimate)
uniform float cloud_coverage = 0.35;
uniform float cloud_scale = 6.0;
uniform uint cloud_seed = 1u;
uniform float cluster_strength = 0.0;

varying vec3 star_light;

void vertex() {
	vec4 center_world = MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	vec3 dir = normalize(center_world.xyz - CAMERA_POSITION_WORLD);
	// A view-space billboard of constant angular size: size_px reference pixels wide at any distance.
	vec3 center_view = (VIEW_MATRIX * center_world).xyz;
	VERTEX = center_view + vec3(VERTEX.xy * length(center_view) * size_px * rad_per_px, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);

	float flux = INSTANCE_CUSTOM.r;                                   // 10^(−0.4·V)
	float airmass = 1.0 / (max(dir.y, 0.0) + 0.025 * exp(-11.0 * max(dir.y, 0.0)));
	flux *= pow(10.0, -0.4 * extinction_mag * airmass);
	// Scintillation: per-star phase from the instance index; 7168/1024 = 7 Hz keeps the 1024 s clock wrap seamless.
	uint h = uint(INSTANCE_ID) * 747796405u + 2891336453u; // PCG hash (no sin() hashes: precision varies by GPU)
	h = ((h >> ((h >> 28u) + 4u)) ^ h) * 277803737u;
	float phase = float(((h >> 22u) ^ h) & 65535u) / 65536.0;
	flux *= 1.0 + scintillation * (1.0 - clamp(dir.y, 0.0, 1.0)) * sin(TAU * (7168.0 / 1024.0 * sim_clock + phase));
	// The sky's cloud deck (render/sky.gdshader): same projection, same field, same drift.
	if (dir.y > 0.0 && cloud_coverage > 0.0) {
		vec2 deck = dir.xz / max(dir.y, 0.02);
		vec2 cells = mod(deck * cloud_scale + cloud_drift_offset, float(CLOUD_FIELD_PERIOD));
		float density = cloud_density(cells, cloud_seed, cloud_coverage, cluster_strength) * smoothstep(0.03, 0.25, dir.y);
		flux *= 1.0 - density;
	}
	star_light = COLOR.rgb * flux * radiance_scale * step(0.0, dir.y);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	ALBEDO = encode_for_engine(star_light); // the engine linearises ALBEDO again
	ALPHA = exp(-4.0 * dot(p, p));
}

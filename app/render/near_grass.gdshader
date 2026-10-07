// L11a opaque near-field blades. Artistic dimensions; deterministic clock, no physics or collision.
shader_type spatial;
render_mode cull_disabled, world_vertex_coords;
#include "res://render/grass_surface.gdshaderinc"
#include "res://render/cloud_field.gdshaderinc"

global uniform float sim_clock;
global uniform vec3 wind_vec;
global uniform vec2 cloud_drift_offset;
uniform vec3 haze_lin = vec3(0.584, 0.768, 0.846);
uniform vec3 sun_dir = vec3(0.0, 0.707, 0.707);
uniform vec3 sun_lin = vec3(3.14159);
uniform float sun_scatter = 0.0;
uniform float beta = 0.00017;
uniform float cloud_coverage = 0.35;
uniform float cloud_scale = 6.0;
uniform uint cloud_seed = 1253u;
uniform float cluster_strength = 0.0;
uniform float cloud_deck_m = 1500.0;
uniform float cloud_shadow_strength = 0.0;
uniform float fade_start_m = 22.0;
uniform float fade_end_m = 30.0;
varying vec3 world_pos;
varying float cloud_transmission;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	// The field is planted around the pilot. A distant chase camera must not retain a grass disk behind it.
	float d = max(distance(origin.xz, pilot_xz), distance(origin, CAMERA_POSITION_WORLD));
	float shrink = 1.0 - smoothstep(fade_start_m, fade_end_m, d);
	vec3 offset = VERTEX - origin;
	float speed = length(wind_vec.xz);
	vec2 direction = wind_vec.xz / max(speed, 1e-4);
	float phase = fract(origin.x * 0.137 + origin.z * 0.719);
	// 0.25 Hz = 256/1024: continuous across ShaderClock's wrap. Zero wind means zero sway until M5.
	float sway = 0.035 * min(speed / 5.0, 1.0) * sin(TAU * fract(0.25 * sim_clock + phase));
	offset.xz += direction * sway * UV.y * UV.y;
	VERTEX = origin + offset * shrink; // collapse the whole triangle at 30 m, no flat z-fighting remnant
	world_pos = VERTEX;
}

void fragment() {
	// Override after the renderer's back-face flip: grass roots receive the same upward lighting as the ground.
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ALBEDO = rough_grass_colour(world_pos.xz) * mix(1.0, 0.94, UV.y);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	cloud_transmission = 1.0;
	if (cloud_shadow_strength > 0.0 && cloud_coverage > 0.0 && sun_dir.y > 0.01) {
		vec2 deck = world_pos.xz + max(cloud_deck_m - world_pos.y, 0.0) * sun_dir.xz / sun_dir.y;
		float density = cloud_density(deck * (cloud_scale / cloud_deck_m) + cloud_drift_offset, cloud_seed, cloud_coverage, cluster_strength);
		cloud_transmission -= clamp(cloud_shadow_strength, 0.0, 1.0) * density * smoothstep(0.01, 0.1, sun_dir.y);
	}
	vec3 to_frag = world_pos - CAMERA_POSITION_WORLD;
	float d = length(to_frag);
	vec3 v = to_frag / max(d, 1e-3);
	vec3 haze = haze_lin + sun_lin * pow(max(dot(v, sun_dir), 0.0), 8.0) * sun_scatter;
	FOG = vec4(haze, 1.0 - exp(-beta * d));
}

void light() {
	float diffuse = max(dot(NORMAL, LIGHT), 0.0) * (1.0 / PI);
	DIFFUSE_LIGHT += LIGHT_COLOR * diffuse * ATTENUATION * (LIGHT_IS_DIRECTIONAL ? cloud_transmission : 1.0);
}

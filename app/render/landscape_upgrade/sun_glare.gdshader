// LU-04. Original MIT optical approximation, bounded for aircraft visibility. No screen-color copy/readback.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled;
#include "res://render/cloud_field.gdshaderinc"
uniform sampler2D depth_buffer : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec2 sun_uv = vec2(0.5);
uniform float aspect = 1.77778;
uniform float disc_radius = 0.006;
uniform float far_distance = 21000.0;
uniform float strength = 0.0;
uniform float exposure = 0.6;
uniform vec3 source_dir = vec3(0.0, 1.0, 0.0);
uniform float cloud_scale = 6.0;
uniform uint cloud_seed = 1u;
uniform float cloud_coverage = 0.35;
uniform vec2 cloud_offset = vec2(0.0);
uniform float cluster_strength = 0.0;
uniform float cirrus_strength = 0.0;
uniform float cirrus_coverage = 0.34;
varying float cloud_transmission;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
	vec2 deck = source_dir.xz / max(source_dir.y, 0.02);
	vec2 cells = mod(deck * cloud_scale + cloud_offset, float(CLOUD_FIELD_PERIOD));
	float body = cloud_density(cells, cloud_seed, cloud_coverage, cluster_strength) * smoothstep(0.03, 0.25, source_dir.y);
	float cirrus = cloud_stretched_density(cells, cloud_seed + 15485863u, cirrus_coverage, vec2(3.0, 51.0) / 64.0)
		* smoothstep(0.02, 0.18, source_dir.y) * clamp(cirrus_strength, 0.0, 0.12);
	cloud_transmission = exp(-8.0 * (body + cirrus));
}

float sky_at(vec2 uv, mat4 inverse_projection) {
	float depth = textureLod(depth_buffer, clamp(uv, vec2(0.0), vec2(1.0)), 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
#endif
	vec4 point = inverse_projection * vec4(ndc, 1.0);
	float distance_to_surface = abs(point.z / max(abs(point.w), 1e-8));
	return step(far_distance * 0.98, distance_to_surface);
}

void fragment() {
	float clear_disc = sky_at(sun_uv, INV_PROJECTION_MATRIX);
	for (int i = 0; i < 8; i++) {
		float a = float(i) * TAU / 8.0;
		vec2 offset = vec2(cos(a) / aspect, sin(a)) * disc_radius * 0.76;
		clear_disc += sky_at(sun_uv + offset, INV_PROJECTION_MATRIX);
	}
	clear_disc /= 9.0;
	vec2 delta = (SCREEN_UV - sun_uv) * vec2(aspect, 1.0);
	float r = length(delta) / max(disc_radius, 0.001);
	float halo = 0.32 * exp(-r / 19.0) + 0.2 * exp(-r / 3.5);
	float rays = pow(abs(cos(atan(delta.y, delta.x) * 4.0)), 18.0) * 0.08 * exp(-r / 28.0);
	vec2 ghost_at = vec2(0.5) + (vec2(0.5) - sun_uv) * 0.5;
	float ghost_r = length((SCREEN_UV - ghost_at) * vec2(aspect, 1.0));
	float ghost = exp(-pow((ghost_r - 0.037) / 0.009, 2.0)) * 0.012;
	float adaptation = clamp(exposure / (exposure + 0.5), 0.05, 1.0);
	float veil = (0.015 + halo + rays + ghost) * strength * adaptation * clear_disc * cloud_transmission;
	ALBEDO = vec3(1.0, 0.90, 0.72);
	ALPHA = clamp(veil, 0.0, 0.30);
}

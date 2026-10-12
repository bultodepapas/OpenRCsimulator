// LU-09: original, batched runway-marker optics; no external texture or art asset.
// The 50 mm lens size comes from the existing field-lights data. Core/halo screen sizes and display cap are
// art-directed readability estimates. Direction cues borrow the FAA AIM 2-1-4 red-inward/green-outward scheme;
// this is a visual cue for an RC club field, not a claim of full-size airport compliance.
// Reference: https://www.faa.gov/air_traffic/publications/aim_html/chap2_section_1.html . Original shader/geometry
// is covered by the repository MIT license; no external assets, textures, or plugins are used.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled, skip_vertex_transform;

#include "res://render/world/engine_srgb.gdshaderinc"

global uniform float world_exposure;

uniform vec3 edge_color : source_color = vec3(0.93, 0.75, 0.52);
uniform vec3 threshold_green : source_color = vec3(0.48, 0.88, 0.58);
uniform vec3 threshold_red : source_color = vec3(1.0, 0.40, 0.31);
uniform float radiance = 0.08;
uniform float size_m = 0.05;
uniform float core_min_px = 2.5;
uniform float halo_min_px = 6.5;
uniform float display_cap = 1.0;
uniform float camera_offset_m = 0.075;
uniform float readability_gain_floor = 0.0025;
uniform float distance_fade_start_m = 300.0;
uniform float distance_fade_end_m = 600.0;
uniform float night_factor = 0.0;
uniform bool threshold_mode = false;

varying float core_radius_uv;
varying float core_gain;
varying float distance_fade;
varying float outward_view;

void vertex() {
	vec3 center = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float distance_to_camera = length(center);
	float view_depth = max(-center.z, 0.001);
	// Derive world size from this camera's projection and render target, so FOV/resolution changes keep
	// the authored pixel readability estimate stable.
	float projected_pixels = max(VIEWPORT_SIZE.y * abs(PROJECTION_MATRIX[1][1]), 1.0);
	float units_per_pixel = (2.0 * view_depth) / projected_pixels;
	float core_diameter = max(size_m, core_min_px * units_per_pixel);
	float halo_diameter = max(core_diameter * 2.25, halo_min_px * units_per_pixel);
	VERTEX = center + vec3(VERTEX.xy * halo_diameter, camera_offset_m);
	NORMAL = vec3(0.0, 0.0, 1.0);
	core_radius_uv = core_diameter / halo_diameter;
	float inverse_square_gain = (size_m * size_m) / (core_diameter * core_diameter);
	core_gain = max(inverse_square_gain, readability_gain_floor);
	distance_fade = 1.0 - smoothstep(distance_fade_start_m, distance_fade_end_m, distance_to_camera);
	vec3 marker_world = (INV_VIEW_MATRIX * vec4(center, 1.0)).xyz;
	float marker_east = marker_world.x;
	outward_view = sign(marker_east) * (CAMERA_POSITION_WORLD.x - marker_east);
}

void fragment() {
	float radius = length(UV * 2.0 - 1.0);
	float core = 1.0 - smoothstep(core_radius_uv * 0.72, core_radius_uv, radius);
	float halo_edge = smoothstep(core_radius_uv * 0.9, core_radius_uv * 1.55, radius);
	float halo = exp(-7.0 * radius * radius) * halo_edge * 0.22;
	vec3 tint = edge_color;
	if (threshold_mode) {
		tint = outward_view >= 0.0 ? threshold_green : threshold_red;
	}
	// Cap after the size gain, scale that cap with dusk, then fade the capped output with range. Applying
	// the range fade after the cap keeps the 300–600 m transition visible even at high FW exposure.
	float exposure_cap = display_cap * night_factor / max(world_exposure, 0.001);
	float emission = min(radiance * core_gain, exposure_cap) * distance_fade;
	ALBEDO = encode_for_engine(tint * emission);
	ALPHA = clamp(core * 0.92 + halo, 0.0, 1.0);
}

// RCV track presentation. Reuses the already bundled Poly Haven CC0 dirt maps.
// All marks are shading only: contact height and road normals remain authoritative.
uniform vec4 rc_track_shape = vec4(0.0, -45.0, 12.0, 6.0); // east, render Z, half straight, radius (m)
uniform float rc_track_lane_half_width_m = 1.6;

float rc_track_center_distance(vec2 p) {
	vec2 relative = p - rc_track_shape.xy;
	float end_distance = max(abs(relative.x) - rc_track_shape.z, 0.0);
	return length(vec2(end_distance, relative.y)) - rc_track_shape.w;
}

void rc_track_surface_finish(vec2 p, vec2 gx, vec2 gy, float view_distance_m,
		float coverage, mat4 view_matrix, inout vec3 albedo,
		inout vec3 surface_normal, inout float roughness) {
	// A second, much smaller tile restores pebble-scale detail in chase view. The
	// derivative fade prevents aliasing as those grains become subpixel.
	float footprint = max(length(gx), length(gy));
	float near_detail = (1.0 - smoothstep(13.0, 45.0, view_distance_m))
		* (1.0 - smoothstep(0.022, 0.13, footprint))
		* smoothstep(0.18, 0.72, coverage);
	vec2 fine_uv = (p + vec2(7.31, -3.74)) / 0.38;
	vec3 fine_color = textureGrad(rc_dirt_albedo, fine_uv, gx / 0.38, gy / 0.38).rgb;
	// Asset luminance is approximately 0.34 in sRGB, 0.10 in linear space.
	float neutral = OUTPUT_IS_SRGB ? 0.34 : 0.10;
	float gain = OUTPUT_IS_SRGB ? 0.68 : 1.2;
	float grain = dot(fine_color, vec3(0.2126, 0.7152, 0.0722)) - neutral;
	albedo *= clamp(1.0 + grain * gain * near_detail, 0.79, 1.22);
	if (near_detail > 0.001) {
		vec3 fine_normal = textureGrad(rc_dirt_normal, fine_uv, gx / 0.38, gy / 0.38).rgb;
		vec3 mapped = rc_project_normal(surface_normal, fine_normal, view_matrix, 0.30);
		surface_normal = normalize(mix(surface_normal, mapped, near_detail * 0.62));
	}

	float signed_distance = rc_track_center_distance(p);
	float lane_distance = abs(signed_distance);
	float lane = 1.0 - smoothstep(rc_track_lane_half_width_m - 0.26,
		rc_track_lane_half_width_m + 0.08, lane_distance);
	if (lane > 0.001) {
		float wheel_wander = (vnoise(p * 0.18 + vec2(16.0, 3.0)) - 0.5) * 0.19;
		float wheel = 1.0 - smoothstep(0.045, 0.105,
			abs(abs(signed_distance - wheel_wander) - 0.245));
		float interruptions = mix(0.34, 1.0,
			smoothstep(0.24, 0.76, vnoise(p * 0.75 + vec2(11.0, 29.0))));
		float compaction = wheel * lane * interruptions * smoothstep(0.55, 0.9, coverage);
		// These are worn color/roughness marks, never geometric grooves.
		albedo *= 1.0 - 0.115 * compaction;
		roughness = mix(roughness, max(roughness - 0.055, 0.62), compaction);
	}

	// Broken, slightly lighter aggregate on the margins of the driven lane.
	float shoulder = smoothstep(rc_track_lane_half_width_m - 0.42,
		rc_track_lane_half_width_m + 0.10, lane_distance)
		* (1.0 - smoothstep(rc_track_lane_half_width_m + 0.70,
			rc_track_lane_half_width_m + 1.16, lane_distance));
	if (shoulder > 0.001) {
		float looseness = 0.45 + 0.55 * vnoise(p * 1.8 + vec2(27.0, 5.0));
		albedo *= 1.0 + shoulder * looseness * coverage * 0.075;
		roughness = mix(roughness, max(roughness, 0.88), shoulder * coverage * 0.55);
	}
}

// Paint lies in the road material itself, following the exact sampled surface.
// Its ragged opacity models rubbed chalk; it adds no visual or physical height.
void rc_track_paint_lane(vec2 p, vec2 gx, vec2 gy, float coverage,
		inout vec3 albedo, inout float roughness) {
	float lane_distance = abs(rc_track_center_distance(p));
	float from_line = abs(lane_distance - rc_track_lane_half_width_m);
	if (from_line > 0.10) {
		return;
	}
	float edge_noise = vnoise(p * 19.0 + vec2(41.0, 13.0));
	float ragged_distance = from_line + (edge_noise - 0.5) * 0.018;
	float pixel_m = max(length(gx), length(gy));
	float stripe = 1.0 - smoothstep(0.024, 0.043 + min(pixel_m * 0.45, 0.055), ragged_distance);
	float chips = smoothstep(0.26, 0.54, vnoise(p * 11.0 + vec2(8.0, 34.0)));
	float opacity = stripe * (0.16 + 0.72 * chips) * smoothstep(0.28, 0.72, coverage);
	vec3 chalk = OUTPUT_IS_SRGB ? vec3(0.88, 0.84, 0.73) : vec3(0.75, 0.67, 0.49);
	albedo = mix(albedo, chalk, opacity);
	roughness = mix(roughness, 0.96, opacity);
}

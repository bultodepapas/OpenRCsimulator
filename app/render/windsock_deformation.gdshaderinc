// Shared geometry for the visible sleeve and its projected contact-shadow mask.
uniform float length_m = 2.5;
uniform float throat_diameter_m = 0.45;
uniform float tail_diameter_m = 0.12;
uniform float basket_height_m = 4.0;
uniform float arm_m = 0.35;
uniform float basket_yaw_rad = 0.0;
uniform float inflation = 0.0;
uniform vec3 centerline_points[13];
global uniform float sim_clock;

const float RIGID_FRACTION = 0.375;


float windsock_station_fraction(int point_index) {
	if (point_index <= 5) {
		return RIGID_FRACTION * float(point_index) / 5.0;
	}
	return RIGID_FRACTION + (1.0 - RIGID_FRACTION) * float(point_index - 5) / 7.0;
}


vec3 windsock_sample_centerline(float t, out vec3 tangent) {
	// Keep the rigid cage straight instead of spline-interpolating through its tail link.
	if (t <= RIGID_FRACTION) {
		tangent = vec3(1.0, 0.0, 0.0);
		return vec3(t * length_m, 0.0, 0.0);
	}
	int segment_index;
	segment_index = min(5 + int(floor((t - RIGID_FRACTION) * 7.0 / (1.0 - RIGID_FRACTION))), 11);
	float t0 = windsock_station_fraction(segment_index);
	float t1 = windsock_station_fraction(segment_index + 1);
	float span = max(t1 - t0, 0.000001);
	float u = clamp((t - t0) / span, 0.0, 1.0);
	vec3 p0 = centerline_points[segment_index];
	vec3 p1 = centerline_points[segment_index + 1];
	vec3 m0;
	vec3 m1;
	if (segment_index == 5) {
		// Start the unsupported section tangent to the rigid axis at the cage end.
		m0 = vec3(span * length_m, 0.0, 0.0);
	} else if (segment_index == 0) {
		m0 = p1 - p0;
	} else {
		float previous_span = max(t1 - windsock_station_fraction(segment_index - 1), 0.000001);
		m0 = (p1 - centerline_points[segment_index - 1]) * (span / previous_span);
	}
	if (segment_index == 11) {
		m1 = p1 - p0;
	} else {
		float next_span = max(windsock_station_fraction(segment_index + 2) - t0, 0.000001);
		m1 = (centerline_points[segment_index + 2] - p0) * (span / next_span);
	}
	float u2 = u * u;
	float u3 = u2 * u;
	float h00 = 2.0 * u3 - 3.0 * u2 + 1.0;
	float h10 = u3 - 2.0 * u2 + u;
	float h01 = -2.0 * u3 + 3.0 * u2;
	float h11 = u3 - u2;
	vec3 centre = h00 * p0 + h10 * m0 + h01 * p1 + h11 * m1;
	float dh00 = 6.0 * u2 - 6.0 * u;
	float dh10 = 3.0 * u2 - 4.0 * u + 1.0;
	float dh01 = -6.0 * u2 + 6.0 * u;
	float dh11 = 3.0 * u2 - 2.0 * u;
	tangent = normalize((dh00 * p0 + dh10 * m0 + dh01 * p1 + dh11 * m1) / span);
	return centre;
}


vec3 windsock_rotate_yaw(vec3 value, float yaw) {
	float c = cos(yaw);
	float s = sin(yaw);
	return vec3(c * value.x + s * value.z, value.y, -s * value.x + c * value.z);
}


void windsock_fabric_geometry(float t, float angle, out vec3 centreline, out vec3 axis,
		out vec3 radial, out vec3 around, out float radius) {
	centreline = windsock_sample_centerline(t, axis);
	// Project local BACK onto the section plane; this remains stable through vertical flex.
	vec3 side = normalize(vec3(0.0, 0.0, 1.0) - axis * axis.z);
	vec3 up = normalize(cross(side, axis));
	float taper = t;
	float extension = clamp(inflation, 0.0, 1.0);
	float nominal_radius = mix(throat_diameter_m * 0.5, tail_diameter_m * 0.5, taper);
	float slack_taper = clamp((t - RIGID_FRACTION) / (1.0 - RIGID_FRACTION), 0.0, 1.0);
	float up_scale = mix(1.0, mix(0.92, 1.0, extension), slack_taper);
	float side_scale = mix(1.0, mix(0.16, 1.0, extension), slack_taper);
	float slack = slack_taper * (1.0 - extension);
	float folds = 1.0 + slack * (0.070 * sin(angle * 6.0 + t * 12.0)
		+ 0.030 * sin(angle * 11.0 - t * 9.0));
	radius = nominal_radius * folds;
	radial = up * (cos(angle) * up_scale) + side * (sin(angle) * side_scale);
	around = normalize(up * (-sin(angle) * up_scale) + side * (cos(angle) * side_scale));
	float flex_envelope = smoothstep(RIGID_FRACTION, 1.0, t) * extension;
	float flutter_a = sin(TAU * fract((2560.0 / 1024.0) * sim_clock - 1.75 * t));
	float flutter_b = sin(TAU * fract((1792.0 / 1024.0) * sim_clock + 1.25 * t));
	float flutter_m = length_m * 0.004 * flex_envelope * (0.65 * flutter_a + 0.35 * flutter_b);
	centreline += side * flutter_m;
}


vec3 windsock_deform_fabric_position(vec2 uv) {
	float t = clamp(uv.x, 0.0, 1.0);
	float angle = uv.y * TAU;
	vec3 centreline;
	vec3 axis;
	vec3 radial;
	vec3 around;
	float radius;
	windsock_fabric_geometry(t, angle, centreline, axis, radial, around, radius);
	vec3 local_position = vec3(arm_m, basket_height_m, 0.0) + centreline + radial * radius;
	return windsock_rotate_yaw(local_position, basket_yaw_rad);
}


void windsock_deform_fabric_vertex(vec2 uv, out vec3 vertex_position, out vec3 vertex_normal,
		out vec3 vertex_tangent, out vec3 vertex_binormal) {
	float t = clamp(uv.x, 0.0, 1.0);
	float angle = uv.y * TAU;
	vec3 centreline;
	vec3 axis;
	vec3 radial;
	vec3 around;
	float radius;
	windsock_fabric_geometry(t, angle, centreline, axis, radial, around, radius);
	vec3 local_position = vec3(arm_m, basket_height_m, 0.0) + centreline + radial * radius;
	vec3 surface_tangent = normalize(axis + radial * ((tail_diameter_m - throat_diameter_m) / max(length_m, 0.001)));
	vec3 surface_normal = normalize(cross(around, surface_tangent));
	vertex_position = windsock_rotate_yaw(local_position, basket_yaw_rad);
	vertex_normal = normalize(windsock_rotate_yaw(surface_normal, basket_yaw_rad));
	vertex_tangent = normalize(windsock_rotate_yaw(surface_tangent, basket_yaw_rad));
	vertex_binormal = normalize(windsock_rotate_yaw(around, basket_yaw_rad));
}

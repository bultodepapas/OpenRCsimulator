shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D fabric_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D fabric_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D fabric_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float length_m = 2.5;
uniform float circumference_m = 1.414;
uniform float throat_diameter_m = 0.45;
uniform float tail_diameter_m = 0.12;
uniform float basket_height_m = 4.0;
uniform float arm_m = 0.35;
uniform float basket_yaw_rad = 0.0;
uniform float inflation = 0.0;
uniform vec3 centerline_points[13];
global uniform float sim_clock;

const float RIGID_FRACTION = 0.375;


float station_fraction(int point_index) {
	if (point_index <= 5) {
		return RIGID_FRACTION * float(point_index) / 5.0;
	}
	return RIGID_FRACTION + (1.0 - RIGID_FRACTION) * float(point_index - 5) / 7.0;
}


vec3 sample_centerline(float t, out vec3 tangent) {
	// The metal cage carries a perfectly straight rigid mouth section. Do not
	// spline through its last link into the flexible tail.
	if (t <= RIGID_FRACTION) {
		tangent = vec3(1.0, 0.0, 0.0);
		return vec3(t * length_m, 0.0, 0.0);
	}
	int segment_index;
	segment_index = min(5 + int(floor((t - RIGID_FRACTION) * 7.0 / (1.0 - RIGID_FRACTION))), 11);
	float t0 = station_fraction(segment_index);
	float t1 = station_fraction(segment_index + 1);
	float span = max(t1 - t0, 0.000001);
	float u = clamp((t - t0) / span, 0.0, 1.0);
	vec3 p0 = centerline_points[segment_index];
	vec3 p1 = centerline_points[segment_index + 1];
	vec3 m0;
	vec3 m1;
	if (segment_index == 5) {
		// Hold the flexible spline tangent to the rigid axis at the cage end.
		m0 = vec3(span * length_m, 0.0, 0.0);
	} else if (segment_index == 0) {
		m0 = p1 - p0;
	} else {
		float previous_span = max(t1 - station_fraction(segment_index - 1), 0.000001);
		m0 = (p1 - centerline_points[segment_index - 1]) * (span / previous_span);
	}
	if (segment_index == 11) {
		m1 = p1 - p0;
	} else {
		float next_span = max(station_fraction(segment_index + 2) - t0, 0.000001);
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


vec3 rotate_yaw(vec3 value, float yaw) {
	float c = cos(yaw);
	float s = sin(yaw);
	return vec3(c * value.x + s * value.z, value.y, -s * value.x + c * value.z);
}


void vertex() {
	float t = clamp(UV.x, 0.0, 1.0);
	float angle = UV.y * TAU;
	vec3 axis;
	vec3 centreline = sample_centerline(t, axis);
	// Project local BACK onto the section plane. This stays stable as the tail
	// flexes through vertical, unlike a world-up switch that can twist abruptly.
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
	float radius = nominal_radius * folds;
	vec3 radial = up * (cos(angle) * up_scale) + side * (sin(angle) * side_scale);
	vec3 around = normalize(up * (-sin(angle) * up_scale) + side * (cos(angle) * side_scale));
	float flex_envelope = smoothstep(RIGID_FRACTION, 1.0, t) * extension;
	float flutter_a = sin(TAU * fract((2560.0 / 1024.0) * sim_clock - 1.75 * t));
	float flutter_b = sin(TAU * fract((1792.0 / 1024.0) * sim_clock + 1.25 * t));
	float flutter_m = length_m * 0.004 * flex_envelope * (0.65 * flutter_a + 0.35 * flutter_b);
	centreline += side * flutter_m;
	vec3 local_position = vec3(arm_m, basket_height_m, 0.0) + centreline + radial * radius;
	vec3 surface_tangent = normalize(axis + radial * ((tail_diameter_m - throat_diameter_m) / max(length_m, 0.001)));
	vec3 surface_normal = normalize(cross(around, surface_tangent));
	VERTEX = rotate_yaw(local_position, basket_yaw_rad);
	NORMAL = normalize(rotate_yaw(surface_normal, basket_yaw_rad));
	TANGENT = normalize(rotate_yaw(surface_tangent, basket_yaw_rad));
	BINORMAL = normalize(rotate_yaw(around, basket_yaw_rad));
}


void fragment() {
	// Arc-length coordinates keep the existing free fabric maps locked to the cloth.
	float circumference_here = mix(circumference_m, PI * tail_diameter_m, UV.x);
	vec2 metres = vec2(UV.x * length_m, UV.y * circumference_here);
	vec2 weave = metres / vec2(0.72, 1.02);
	float grain = dot(texture(fabric_color, weave).rgb, vec3(0.2126, 0.7152, 0.0722));
	float aa = max(fwidth(metres.x), 0.0005);
	float band_distance = min(fract(UV.x * 5.0), 1.0 - fract(UV.x * 5.0)) * length_m / 5.0;
	float panel_phase = fract(UV.y * 4.0);
	float panel_distance = min(panel_phase, 1.0 - panel_phase) * circumference_here / 4.0;
	float seam = 1.0 - smoothstep(0.0025, 0.0055, min(band_distance, panel_distance));
	float end_distance = min(UV.x, 1.0 - UV.x) * length_m;
	float hem = 1.0 - smoothstep(0.012, 0.012 + aa, end_distance);
	float support_tape = 1.0 - smoothstep(0.007, 0.014, abs(UV.x - 0.375) * length_m);
	float dash = smoothstep(0.15, 0.45, sin(metres.x * 720.0));
	float stitches = (1.0 - smoothstep(0.0005, 0.0017, panel_distance)) * dash;
	vec3 cloth = COLOR.rgb * clamp(0.99 + (grain - 0.58) * 0.16, 0.90, 1.05);
	// Preserve weave and seam contrast under the field's strong direct sun.
	cloth *= mix(1.0, 0.68, step(COLOR.r * 0.9, COLOR.g));
	cloth *= 1.0 - seam * 0.11 - hem * 0.15;
	cloth = mix(cloth, COLOR.rgb * 0.88, support_tape * 0.28);
	ALBEDO = mix(cloth, vec3(0.59, 0.52, 0.42), stitches * 0.16);
	ROUGHNESS = clamp(0.78 + texture(fabric_roughness, weave).r * 0.20, 0.78, 1.0);
	NORMAL_MAP = texture(fabric_normal, weave).rgb;
	NORMAL_MAP_DEPTH = 0.42;
	SPECULAR = 0.15;
}

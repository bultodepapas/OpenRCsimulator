// Presentation-only night rotor lights. A fixed 1/60 s shutter sweeps the points
// from the caller's signed angular speed and phase; no wall or simulation clock is used.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled, skip_vertex_transform;

#include "res://render/world/engine_srgb.gdshaderinc"

global uniform float world_exposure;

uniform vec3 light_color : source_color = vec3(1.0, 0.56, 0.18);
uniform float surface_side = 1.0;
uniform float omega_rad_s = 0.0;
uniform float phase_rad = 0.0;
uniform float shutter_s = 0.016666667;
uniform float width_m = 0.008;
uniform float min_px = 2.0;
uniform float radiance = 5.0;
uniform float display_cap = 1.35;
uniform float effect_gain = 1.0;

const float TWO_PI = 6.283185307179586;

varying vec2 local_path_xy;
varying float local_radius;
varying float projected_radius_px;
varying float screen_area_gain;
varying float side_facing;

float positive_mod(float value, float period) {
	return mod(mod(value, period) + period, period);
}

float arc_sample(float angle, float base_phase, float span, float edge) {
	float direction = omega_rad_s >= 0.0 ? 1.0 : -1.0;
	float start_phase = base_phase - omega_rad_s * shutter_s;
	float progress = positive_mod((angle - start_phase) * direction, TWO_PI);
	if (span >= TWO_PI) {
		return 1.0;
	}
	if (span <= 2.0 * edge) {
		float distance = abs(positive_mod(angle - base_phase + 0.5 * TWO_PI, TWO_PI) - 0.5 * TWO_PI);
		return 1.0 - smoothstep(edge * 0.65, edge, distance);
	}
	float start_distance = min(progress, TWO_PI - progress);
	float start_gate = smoothstep(0.0, edge, start_distance);
	float end_gate = 1.0 - smoothstep(span - edge, span + edge, progress);
	return start_gate * end_gate;
}

void vertex() {
	vec3 path_position = VERTEX;
	float radius = max(length(path_position.xy), 0.0001);
	vec3 center = (MODELVIEW_MATRIX * vec4(path_position, 1.0)).xyz;
	vec3 radial_view = normalize(mat3(MODELVIEW_MATRIX) * NORMAL);
	float depth_scale = PROJECTION_MATRIX[3][3] == 0.0 ? max(-center.z, 0.001) : 1.0;
	float metres_per_pixel = 2.0 * depth_scale / (VIEWPORT_SIZE.y * abs(PROJECTION_MATRIX[1][1]));
	// Compensate projected width at shallow pilot-view angles too. Expanding only
	// in the rotor plane without this factor makes a nominal two-pixel ring dotted.
	float radial_projection = max(length(radial_view.xy), 0.06);
	float screen_width = max(width_m, min_px * metres_per_pixel / radial_projection);
	// A soft LED point-spread halo in the same draw, without scene-wide bloom.
	VERTEX = center + radial_view * UV.x * screen_width * 1.5;
	NORMAL = vec3(0.0, 0.0, 1.0);
	local_path_xy = path_position.xy;
	local_radius = radius;
	vec3 radial_offset_view = (MODELVIEW_MATRIX * vec4(path_position.xy, 0.0, 0.0)).xyz;
	projected_radius_px = max(length(radial_offset_view.xy) / metres_per_pixel, 1.0);
	float physical_half_angle = 0.5 * width_m / radius;
	float minimum_half_angle = 0.5 * min_px / projected_radius_px;
	screen_area_gain = (width_m / screen_width) * (physical_half_angle / max(physical_half_angle, minimum_half_angle));
	vec3 axis_view = normalize(mat3(MODELVIEW_MATRIX) * vec3(0.0, 0.0, 1.0));
	side_facing = dot(axis_view, normalize(-center));
}

void fragment() {
	float angle = atan(local_path_xy.y, local_path_xy.x);
	float span = abs(omega_rad_s) * shutter_s;
	float physical_half_angle = 0.5 * width_m / max(local_radius, 0.0001);
	float pixel_half_angle = 0.5 * min_px / projected_radius_px;
	float edge = max(physical_half_angle, pixel_half_angle);
	// Count both LEDs and every complete revolution in this exposure. Overlapping
	// trails add energy; a fast tail rotor must not lose energy at the 2*pi seam.
	float turns = floor(span / TWO_PI);
	float remainder = mod(span, TWO_PI);
	float partial = remainder > 1e-8 || span <= 1e-8 ?
		arc_sample(angle, phase_rad, remainder, edge) +
		arc_sample(angle, phase_rad + 3.141592653589793, remainder, edge) : 0.0;
	float coverage = 2.0 * turns + partial;
	float side_visibility = smoothstep(0.0, 0.06, side_facing * surface_side);
	float temporal_gain = span <= 1e-8 ? 1.0 : min(1.0, (2.0 * physical_half_angle) / (span + 2.0 * physical_half_angle));
	float exposure = max(world_exposure, 0.001);
	// Fixed astronomical SDR uses exposure 0.6 rather than the adapted night eye.
	// This declared appearance gain keeps the time-averaged blade LEDs readable
	// there too, under the same display cap; it is not photometric calibration.
	float night_display_gain = max(1.0, 60.0 / exposure);
	float brightness = min(radiance * screen_area_gain * temporal_gain * coverage * night_display_gain, display_cap / exposure) * effect_gain;
	ALBEDO = encode_for_engine(light_color * brightness);
	float radial_distance = UV.x * 3.0;
	ALPHA = side_visibility * (exp(-3.0 * radial_distance * radial_distance) +
		0.14 * exp(-0.5 * radial_distance * radial_distance)) / 1.14;
}

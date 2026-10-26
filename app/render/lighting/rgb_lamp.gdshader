// Per-instance aircraft lamp and bounded VFX material.
// Billboard mode replaces the legacy sim_clock/world_exposure globals with local supplied values.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled, skip_vertex_transform;

#include "res://render/world/engine_srgb.gdshaderinc"
global uniform bool aircraft_reduced_flashes;

uniform vec3 light_color : source_color = vec3(1.0);
uniform float radiance = 2.0;
uniform float effect_gain = 1.0;
uniform float size_m = 0.02;
uniform float min_px = 2.5;
uniform vec4 flash = vec4(1.0, 0.0, 0.0, 0.0); // period, pulse, second pulse offset, enabled
uniform float display_cap = 1.5;
uniform float local_exposure = 1.0;
uniform float local_clock = 0.0;
uniform float vfx_mode = 0.0; // 0 = projection-aware billboard, 1 = pre-oriented VFX instances
uniform float radial_shape = 1.0; // VFX only: 1 = spark, 0 = ribbon
uniform float ribbon_min_width_px = 1.25;
uniform float ribbon_max_width_m = 0.35;

varying float billboard_gain;

vec3 to_linear_srgb(vec3 c) {
	vec3 low = c / 12.92;
	vec3 high = pow((c + vec3(0.055)) / 1.055, vec3(2.4));
	return mix(high, low, lessThanEqual(c, vec3(0.04045)));
}

void vertex() {
	vec3 centre = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float gain = 1.0;
	if (vfx_mode < 0.5) {
		float depth_scale = PROJECTION_MATRIX[3][3] == 0.0 ? max(-centre.z, 0.001) : 1.0;
		float metres_per_pixel = 2.0 * depth_scale / (VIEWPORT_SIZE.y * abs(PROJECTION_MATRIX[1][1]));
		float size = max(size_m, min_px * metres_per_pixel);
		VERTEX = centre + vec3(VERTEX.xy * size, 0.0);
		gain = (size_m * size_m) / (size * size);
		if (flash.w > 0.5 && flash.x > 0.0 && !aircraft_reduced_flashes) {
			float t = mod(max(local_clock, 0.0), flash.x);
			bool on = t < flash.y || (flash.z > 0.0 && t >= flash.z && t < flash.z + flash.y);
			gain *= on ? 1.0 : 0.0;
		}
	} else {
		vec3 position = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		if (radial_shape < 0.5) {
			vec3 side_axis_view = (MODELVIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
			float side_width_m = length(side_axis_view);
			if (side_width_m > 0.000001) {
				float depth_scale = PROJECTION_MATRIX[3][3] == 0.0 ? max(-centre.z, 0.001) : 1.0;
				float metres_per_pixel = 2.0 * depth_scale / (VIEWPORT_SIZE.y * abs(PROJECTION_MATRIX[1][1]));
				float requested_width_m = max(side_width_m, ribbon_min_width_px * metres_per_pixel);
				float maximum_width_m = max(ribbon_max_width_m, side_width_m);
				float expanded_width_m = min(requested_width_m, maximum_width_m);
				if (expanded_width_m > side_width_m) {
					position += side_axis_view * VERTEX.y * (expanded_width_m / side_width_m - 1.0);
					gain = side_width_m / expanded_width_m;
				}
			}
		}
		VERTEX = position;
	}
	NORMAL = vec3(0.0, 0.0, 1.0);
	billboard_gain = gain;
}

void fragment() {
	float cap = max(display_cap, 0.0) / max(local_exposure, 0.001);
	if (vfx_mode > 0.5) {
		vec2 p = UV * 2.0 - 1.0;
		float spark_mask = exp(-5.0 * dot(p, p));
		float ribbon_mask = 1.0 - smoothstep(0.62, 1.0, abs(p.y));
		float mask = mix(ribbon_mask, spark_mask, clamp(radial_shape, 0.0, 1.0));
		ALBEDO = encode_for_engine(to_linear_srgb(COLOR.rgb) * min(max(radiance, 0.0), cap) * max(effect_gain, 0.0));
		ALPHA = mask * COLOR.a * (radial_shape < 0.5 ? billboard_gain : 1.0);
	} else {
		vec2 p = UV * 2.0 - 1.0;
		ALBEDO = encode_for_engine(light_color * min(max(radiance * billboard_gain, 0.0), cap) * max(effect_gain, 0.0));
		ALPHA = exp(-4.0 * dot(p, p));
	}
}

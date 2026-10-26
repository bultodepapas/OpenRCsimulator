// FW-RGB-05: animated per-instance presentation over the existing NightKit strip geometry.
// Animation time and local exposure are supplied by the displayed-pose owner; this shader never reads TIME.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled, skip_vertex_transform;

#include "res://render/world/engine_srgb.gdshaderinc"

uniform vec4 palette[8];
uniform vec4 pattern_settings = vec4(0.0, 1.0, 1.0, 0.5); // id, palette count, floor, duty
uniform vec4 pattern_extras = vec4(1.0, 0.0, 0.0, 0.0); // segments, reverse, spatial phase turns, reserved
uniform vec3 axis_dir = vec3(1.0, 0.0, 0.0);
uniform vec2 axis_range = vec2(0.0, 1.0); // projected start and length in the strip mesh's local frame
uniform bool use_path_uv = false; // authored centerline arc length; legacy fitted strips retain axis projection
uniform vec3 face_dir = vec3(0.0, -1.0, 0.0);
uniform float pattern_phase = 0.0; // bounded phase in [0,1), supplied from presentation time
uniform float effect_gain = 1.0;
uniform float local_exposure = 1.0;
uniform float radiance = 0.25;
uniform float width_m = 0.015;
uniform float min_px = 2.0;
uniform float display_cap = 2.0;

varying float width_gain;
varying float underside;
varying float arc_u;

vec3 to_linear_srgb(vec3 c) {
	vec3 low = c / 12.92;
	vec3 high = pow((c + vec3(0.055)) / 1.055, vec3(2.4));
	return mix(high, low, lessThanEqual(c, vec3(0.04045)));
}

vec3 palette_color(int index, int count) {
	return to_linear_srgb(palette[clamp(index, 0, 7)].rgb);
}

vec3 palette_at(float t, int count) {
	float p = fract(t) * float(count);
	int i = int(floor(p));
	float f = smoothstep(0.0, 1.0, fract(p));
	return mix(palette_color(i, count), palette_color((i + 1) % count, count), f);
}

void vertex() {
	// Keep the source-frame projection before VERTEX becomes view-space for the width correction.
	float projected = dot(VERTEX, axis_dir);
	vec3 centre = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 side = normalize(mat3(MODELVIEW_MATRIX) * NORMAL);
	float depth_scale = PROJECTION_MATRIX[3][3] == 0.0 ? max(-centre.z, 0.001) : 1.0;
	float metres_per_pixel = 2.0 * depth_scale / (VIEWPORT_SIZE.y * abs(PROJECTION_MATRIX[1][1]));
	float width = max(width_m, min_px * metres_per_pixel);
	VERTEX = centre + side * UV.x * width * 0.5;
	NORMAL = vec3(0.0, 0.0, 1.0);
	width_gain = width_m / width;
	vec3 facing = normalize(mat3(MODELVIEW_MATRIX) * face_dir);
	underside = dot(facing, normalize(-centre));
	arc_u = use_path_uv ? clamp(UV.y, 0.0, 1.0) : clamp((projected - axis_range.x) / max(axis_range.y, 0.00001), 0.0, 1.0);
}

void fragment() {
	int pattern_id = int(pattern_settings.x + 0.5);
	int count = clamp(int(pattern_settings.y + 0.5), 1, 8);
	float floor_level = clamp(pattern_settings.z, 0.0, 1.0);
	float duty = clamp(pattern_settings.w, 0.05, 0.95);
	float phase_offset = pattern_id == 6 ? 0.0 : pattern_extras.z;
	float phase = fract(pattern_phase + phase_offset);
	float direction = pattern_extras.y > 0.5 ? -1.0 : 1.0;
	float spatial_offset = pattern_id == 6 ? pattern_extras.z : 0.0;
	float spatial = fract(arc_u * direction + spatial_offset);
	vec3 base = palette_color(0, count);
	vec3 result = base;
	float envelope = 1.0;
	if (pattern_id == 1) {
		envelope = floor_level + (1.0 - floor_level) * (0.5 - 0.5 * cos(TAU * phase));
	} else if (pattern_id == 2) {
		float edge = min(0.08, duty * 0.25);
		float on = smoothstep(0.0, edge, phase) * (1.0 - smoothstep(max(0.0, duty - edge), duty, phase));
		envelope = floor_level + (1.0 - floor_level) * on;
	} else if (pattern_id == 3) {
		float distance_to_head = abs(fract(spatial - phase + 0.5) - 0.5);
		float half_width = max(0.04, duty * 0.5);
		float band = 1.0 - smoothstep(half_width - 0.04, half_width + 0.04, distance_to_head);
		result = mix(base, palette_color(min(1, count - 1), count), band);
		envelope = floor_level + (1.0 - floor_level) * band;
	} else if (pattern_id == 4) {
		result = palette_at(spatial - phase, count);
	} else if (pattern_id == 5) {
		result = palette_at(spatial + phase, count);
	} else if (pattern_id == 6) {
		float segment_count = clamp(pattern_extras.x, 1.0, 256.0);
		float segment_pos = fract(spatial) * segment_count;
		int segment = int(floor(segment_pos));
		result = palette_color(segment % count, count);
		envelope = floor_level + (1.0 - floor_level) * duty;
	}
	float cap = max(display_cap, 0.0) / max(local_exposure, 0.001);
	// Adapt the emitter first: capping after modulation would flatten breathing and
	// brightness controls under the world's large night exposure.
	float emitted = min(max(radiance * width_gain, 0.0), cap) * max(effect_gain * envelope, 0.0);
	ALBEDO = encode_for_engine(result * emitted);
	ALPHA = exp(-4.0 * UV.x * UV.x) * smoothstep(0.0, 0.15, underside);
}

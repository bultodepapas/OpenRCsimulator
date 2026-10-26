// Shared linear-light LED pattern evaluator. Coordinates and bounded phase are supplied by each owner.
uniform vec4 palette[8];
uniform vec4 pattern_settings = vec4(0.0, 1.0, 1.0, 0.5);
uniform vec4 pattern_extras = vec4(1.0, 0.0, 0.0, 0.0);
uniform float pattern_phase = 0.0;

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

// Integral of one palette entry's coverage along a repeating finite strip.
// A partial last palette cycle matters when segments is not a multiple of count.
float segment_coverage(float x, float segments, float count, float index) {
	float periods = floor(x / segments);
	float local = x - periods * segments;
	float per_period = floor(segments / count) + clamp(mod(segments, count) - index, 0.0, 1.0);
	return periods * per_period + floor(local / count) + clamp(mod(local, count) - index, 0.0, 1.0);
}

vec3 filtered_segments(float spatial, float footprint, float segments, int count) {
	float width = min(footprint * segments, segments);
	float centre = spatial * segments;
	// Resolved segment interiors need no palette integration.
	if (width < 0.001 || floor(centre - width * 0.5) == floor(centre + width * 0.5)) {
		return palette_color(int(floor(centre)) % count, count);
	}
	float begin = centre - width * 0.5;
	float end = centre + width * 0.5;
	vec3 color = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		if (i < count) {
			float coverage = (segment_coverage(end, segments, float(count), float(i))
				- segment_coverage(begin, segments, float(count), float(i))) / width;
			color += palette_color(i, count) * clamp(coverage, 0.0, 1.0);
		}
	}
	return color;
}

vec4 lighting_pattern(float arc_u, float path_footprint) {
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
		result = filtered_segments(spatial, path_footprint, segment_count, count);
		envelope = floor_level + (1.0 - floor_level) * duty;
	}
	return vec4(result, envelope);
}

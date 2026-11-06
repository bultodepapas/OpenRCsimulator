// DT-MAC-06b C2: ground cloud-shadow density from the periodic noise tile (render/cloud_shadow_map.gd).
// Include after cloud_field.gdshaderinc. Disabled, or for any seed other than the tile's, this is exactly
// cloud_density(); the tile replaces only the five-octave fbm and cluster noise, not the thresholding.
uniform sampler2D cloud_shadow_map : filter_linear, repeat_enable;
uniform bool cloud_shadow_map_enabled = false;
uniform uint cloud_shadow_map_seed = 0u;

// Exactly cloud_density()'s cluster shift: one per-pixel value-noise sample, only when clustering is on.
float _cloud_tile_coverage(vec2 cells, uint seed, float bounded_coverage, float cluster_strength) {
	float strength = clamp(cluster_strength, 0.0, 1.0);
	if (strength <= 0.0) {
		return bounded_coverage;
	}
	vec2 coarse_cells = mod(cells, float(CLOUD_FIELD_PERIOD)) / 16.0;
	float cluster = smoothstep(0.2, 0.8, cloud_field_value_noise(coarse_cells, ivec2(4), seed + 104729u));
	return clamp(bounded_coverage + (cluster - 0.5) * 0.7 * strength, 0.0, 1.0);
}


float cloud_shadow_density(vec2 cells, uint seed, float coverage, float cluster_strength) {
	if (!cloud_shadow_map_enabled || seed != cloud_shadow_map_seed) {
		return cloud_density(cells, seed, coverage, cluster_strength);
	}
	float bounded_coverage = clamp(coverage, 0.0, 1.0);
	if (bounded_coverage <= 0.0) {
		return 0.0;
	}
	float noise = texture(cloud_shadow_map, cells / float(CLOUD_FIELD_PERIOD)).r;
	return cloud_field_threshold(noise, _cloud_tile_coverage(cells, seed, bounded_coverage, cluster_strength));
}



// C5b: cloud_density() with octaves 0-2 from the tile's half-float G channel and octaves 3-4 evaluated here,
// exactly as cloud_field_fbm(); the per-pixel octaves keep the high-frequency detail that relief shading needs.
float cloud_detail_density(vec2 cells, uint seed, float coverage, float cluster_strength) {
	if (!cloud_shadow_map_enabled || seed != cloud_shadow_map_seed) {
		return cloud_density(cells, seed, coverage, cluster_strength);
	}
	float bounded_coverage = clamp(coverage, 0.0, 1.0);
	if (bounded_coverage <= 0.0) {
		return 0.0;
	}
	float sum = texture(cloud_shadow_map, cells / float(CLOUD_FIELD_PERIOD)).g;
	for (int octave = 3; octave < 5; octave++) {
		float scale = exp2(float(octave));
		vec2 period = vec2(float(CLOUD_FIELD_PERIOD) * scale);
		sum += 0.5 / scale * cloud_field_value_noise(mod(cells * scale, period), ivec2(floor(period + vec2(0.5))),
			seed + uint(octave) * 7919u);
	}
	return cloud_field_threshold(sum / 0.96875, _cloud_tile_coverage(cells, seed, bounded_coverage, cluster_strength));
}

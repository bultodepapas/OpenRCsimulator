// DT-MAC-06b C2: ground cloud-shadow density from the periodic noise tile (render/cloud_shadow_map.gd).
// Include after cloud_field.gdshaderinc. Disabled, or for any seed other than the tile's, this is exactly
// cloud_density(); the tile replaces only the five-octave fbm and cluster noise, not the thresholding.
uniform sampler2D cloud_shadow_map : filter_linear, repeat_enable;
uniform bool cloud_shadow_map_enabled = false;
uniform bool cloud_shadow_map_ground_enabled = true;
uniform bool cloud_shadow_map_detail_enabled = true;
uniform uint cloud_shadow_map_seed = 0u;
#ifdef OPENRC_CLOUD_SKY
// Additional sky-only relief tiles. Each seed is checked before sampling; absent
// or over-capacity layers keep the exact analytic path.
uniform sampler2D cloud_relief_map_1 : filter_linear, repeat_enable;
uniform bool cloud_relief_map_1_enabled = false;
uniform uint cloud_relief_map_1_seed = 0u;
uniform sampler2D cloud_relief_map_2 : filter_linear, repeat_enable;
uniform bool cloud_relief_map_2_enabled = false;
uniform uint cloud_relief_map_2_seed = 0u;
uniform sampler2D cloud_relief_map_3 : filter_linear, repeat_enable;
uniform bool cloud_relief_map_3_enabled = false;
uniform uint cloud_relief_map_3_seed = 0u;
#endif

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
	if (!cloud_shadow_map_enabled || !cloud_shadow_map_ground_enabled || seed != cloud_shadow_map_seed) {
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
	bool primary = cloud_shadow_map_enabled && cloud_shadow_map_detail_enabled && seed == cloud_shadow_map_seed;
	bool slot1 = false;
	bool slot2 = false;
	bool slot3 = false;
#ifdef OPENRC_CLOUD_SKY
	slot1 = cloud_relief_map_1_enabled && seed == cloud_relief_map_1_seed;
	slot2 = cloud_relief_map_2_enabled && seed == cloud_relief_map_2_seed;
	slot3 = cloud_relief_map_3_enabled && seed == cloud_relief_map_3_seed;
#endif
	if (!primary && !slot1 && !slot2 && !slot3) {
		return cloud_density(cells, seed, coverage, cluster_strength);
	}
	float bounded_coverage = clamp(coverage, 0.0, 1.0);
	if (bounded_coverage <= 0.0) {
		return 0.0;
	}
	vec2 uv = cells / float(CLOUD_FIELD_PERIOD);
	float sum = 0.0;
	if (primary) { sum = texture(cloud_shadow_map, uv).g; }
#ifdef OPENRC_CLOUD_SKY
	else if (slot1) { sum = texture(cloud_relief_map_1, uv).g; }
	else if (slot2) { sum = texture(cloud_relief_map_2, uv).g; }
	else { sum = texture(cloud_relief_map_3, uv).g; }
#endif
	for (int octave = 3; octave < 5; octave++) {
		float scale = exp2(float(octave));
		vec2 period = vec2(float(CLOUD_FIELD_PERIOD) * scale);
		sum += 0.5 / scale * cloud_field_value_noise(mod(cells * scale, period), ivec2(floor(period + vec2(0.5))),
			seed + uint(octave) * 7919u);
	}
	return cloud_field_threshold(sum / 0.96875, _cloud_tile_coverage(cells, seed, bounded_coverage, cluster_strength));
}

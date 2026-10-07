// Shared deterministic cloud noise (L4b / landscape Phase 6). No textures or TIME.
// Coordinates are measured in base noise cells. Any CPU drift added to them must wrap at CLOUD_FIELD_PERIOD.
// The returned coverage is raw 0..1 density; callers apply their own horizon fade and lighting.
// For L15d at a 1,500 m deck with scale 6, project the ground point to the sun ray, then multiply by 6/1500.
// Positive offset moves the pattern opposite its apparent drift: the current +0.004/+0.0015 cells/s is -1/-0.375 m/s.
const int CLOUD_FIELD_PERIOD = 64;

float cloud_field_hash2(ivec2 c, uint seed) {
	uvec2 q = uvec2(c) * uvec2(1597334677u, 3812015801u);
	uint n = (q.x ^ q.y ^ (seed * 2654435761u)) * 1597334677u;
	return float(n >> 8u) * (1.0 / 16777216.0);
}

int cloud_field_wrap(int value, int period) {
	return (value % period + period) % period;
}

// Quintic value noise with independent axis periods. Independent periods let stretched decks
// remain exactly periodic when the unscaled input shifts by CLOUD_FIELD_PERIOD cells.
float cloud_field_value_noise(vec2 p, ivec2 period, uint seed) {
	vec2 i = floor(p);
	vec2 f = p - i;
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	ivec2 c = ivec2(i);
	int x0 = cloud_field_wrap(c.x, period.x);
	int x1 = cloud_field_wrap(c.x + 1, period.x);
	int y0 = cloud_field_wrap(c.y, period.y);
	int y1 = cloud_field_wrap(c.y + 1, period.y);
	float a = cloud_field_hash2(ivec2(x0, y0), seed);
	float b = cloud_field_hash2(ivec2(x1, y0), seed);
	float d = cloud_field_hash2(ivec2(x0, y1), seed);
	float e = cloud_field_hash2(ivec2(x1, y1), seed);
	return mix(mix(a, b, u.x), mix(d, e, u.x), u.y);
}

// Five octave value noise. `frequency` and `64 * frequency` periods must be exact integer
// lattice ratios; this is true for the shared base deck and its cirrus stretch below.
float cloud_field_fbm(vec2 cells, uint seed, vec2 frequency) {
	vec2 p = cells * frequency;
	vec2 period = float(CLOUD_FIELD_PERIOD) * frequency;
	float sum = 0.0;
	float amp = 0.5;
	for (int octave = 0; octave < 5; octave++) {
		vec2 q = mod(p, period);
		ivec2 lattice_period = ivec2(floor(period + vec2(0.5)));
		sum += amp * cloud_field_value_noise(q, lattice_period, seed + uint(octave) * 7919u);
		p *= 2.0;
		period *= 2.0;
		amp *= 0.5;
	}
	return sum / 0.96875;
}

float cloud_field_threshold(float noise, float coverage) {
	float bounded_coverage = clamp(coverage, 0.0, 1.0);
	return smoothstep(1.0 - bounded_coverage, 1.25 - bounded_coverage, noise);
}

// One coarse, 16-cell cluster octave shifts the local coverage threshold to leave broad clear gaps.
// cluster_strength=0 is exactly the L4 threshold and is the legacy A/B setting.
float cloud_density(vec2 cells, uint seed, float coverage, float cluster_strength) {
	float bounded_coverage = clamp(coverage, 0.0, 1.0);
	if (bounded_coverage <= 0.0) {
		return 0.0;
	}
	float noise = cloud_field_fbm(cells, seed, vec2(1.0));
	float strength = clamp(cluster_strength, 0.0, 1.0);
	float local_coverage = bounded_coverage;
	if (strength > 0.0) {
		vec2 coarse_cells = mod(cells, float(CLOUD_FIELD_PERIOD)) / 16.0;
		float cluster = cloud_field_value_noise(coarse_cells, ivec2(4), seed + 104729u);
		cluster = smoothstep(0.2, 0.8, cluster);
		local_coverage = clamp(bounded_coverage + (cluster - 0.5) * 0.7 * strength, 0.0, 1.0);
	}
	return cloud_field_threshold(noise, local_coverage);
}

// A separate stretched deck (for cirrus). Frequency is an exact rational of base coordinates,
// so adding any integer multiple of 64 to `cells` produces identical output.
float cloud_stretched_density(vec2 cells, uint seed, float coverage, vec2 frequency) {
	float noise = cloud_field_fbm(cells, seed, frequency);
	return cloud_field_threshold(noise, coverage);
}

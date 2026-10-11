// L4c: bounded 2.5D optical-depth lighting of the existing fair-weather deck.
// Artistic estimates in noise-cell units, not a physical cloud volume. MIT.
// The shared cloud field remains the sole source of coverage and ground shadows.
vec3 cloud_relief(vec2 cells, float body, vec3 direction, vec3 light_direction,
		vec3 light_color, uint seed, float coverage, float clustering) {
	// Three increasing light-path samples approximate occlusion through a rounded
	// layer. A horizontal sun has a bounded path; zenith has no arbitrary azimuth.
	vec2 ray = light_direction.xz / max(light_direction.y, 0.28);
	float near_body = cloud_density(cells + ray * 0.10, seed, coverage, clustering);
	float mid_body = cloud_density(cells + ray * 0.28, seed, coverage, clustering);
	float far_body = cloud_density(cells + ray * 0.62, seed, coverage, clustering);
	float optical_depth = 0.65 * near_body + 0.45 * mid_body + 0.25 * far_body;
	float transmission = exp(-1.6 * optical_depth);
	// Ambient multiple-scattering floor keeps the aircraft background readable.
	float illumination = 0.62 + 0.38 * transmission;
	// Density differences reveal the sunward shoulders without differentiating
	// screen pixels (which would make shape depend on FOV and viewport size).
	float shoulder = clamp((body - near_body) * 1.5, -0.12, 0.20);
	float forward = pow(max(dot(direction, light_direction), 0.0), 12.0);
	float edge = 4.0 * body * (1.0 - body);
	float scatter = 0.12 * edge * forward * transmission;
	return light_color * clamp(illumination + shoulder + scatter, 0.50, 1.12);
}

// Managed pasture and its worn shoulders share these planes, row filtering and cover colours.
uniform int meadow_count = 0;
uniform vec4 meadow_extent;
uniform vec4 meadow_bounds[4]; // north/east min and max, metres
uniform vec4 meadow_edges[16]; // inward unit normal, offset, cover (pasture, hay, grazed, close-grazed)

// A square wave of period 1 (+1, then -1) box-filtered over du: the exact mean via its triangle-wave integral.
float square_filtered(float u, float du) {
	du = max(du, 1e-4);
	float a = 0.5 - abs(fract(u + 0.5 * du) - 0.5);
	float b = 0.5 - abs(fract(u - 0.5 * du) - 0.5);
	return (a - b) / du;
}

vec3 meadow_colour(vec3 grass_colour, vec2 ne, vec2 footprint) {
	if (any(lessThan(ne, meadow_extent.xy)) || any(greaterThan(ne, meadow_extent.zw))) return grass_colour;
	for (int i = 0; i < meadow_count; i++) {
		vec4 bounds = meadow_bounds[i];
		if (any(lessThan(ne, bounds.xy)) || any(greaterThan(ne, bounds.zw))) continue;
		vec4 first = meadow_edges[i * 4];
		float across = dot(first.xy, ne) + first.z;
		float inset = across;
		for (int j = 1; j < 4; j++) {
			vec4 edge = meadow_edges[i * 4 + j];
			inset = min(inset, dot(edge.xy, ne) + edge.z);
		}
		if (inset <= 0.0) continue;
		// Grazing and regrowth form patches; only the hay field has parallel cutting passes.
		float mottling = vnoise(ne * 0.073 + first.z * 0.13);
		mottling = mix(mottling, 0.5, smoothstep(0.25, 0.9, max(footprint.x, footprint.y) * 0.073));
		float verge = smoothstep(0.3, 2.1 + mottling * 1.5, inset);
		vec3 tint = mix(vec3(0.78, 0.97, 0.84), vec3(0.93, 1.06, 0.89), mottling);
		if (first.w > 2.5) {
			// The home paddock has short pale grass with exposed soil on the most heavily used spots.
			tint = mix(vec3(1.07, 1.03, 0.78), vec3(1.43, 1.02, 0.70), smoothstep(0.38, 0.75, mottling));
		} else if (first.w > 1.5) {
			tint = mix(vec3(0.91, 1.01, 0.77), vec3(1.23, 1.09, 0.84), smoothstep(0.26, 0.76, mottling));
		} else if (first.w > 0.5) {
			// Leave the headland free for turning. Windrows wander gently with the cut.
			float pitch = 7.8;
			float phase = (across + (mottling - 0.5) * 1.7) / pitch;
			float pixel = max(0.001, dot(abs(first.xy), footprint) / pitch);
			float cut = square_filtered(phase, pixel);
			float straw = 1.0 - smoothstep(0.025, 0.085 + pixel, abs(fract(phase + 0.5) - 0.5));
			straw *= 1.0 - smoothstep(0.08, 0.35, pixel);
			float rows = smoothstep(3.5, 6.0, inset);
			tint = vec3(1.32, 1.09, 0.76) * (1.0 + cut * 0.045 * rows);
			tint += vec3(0.31, 0.19, 0.06) * straw * rows;
		}
		tint = mix(vec3(0.78, 0.90, 0.72), tint, verge);
		return grass_colour * mix(vec3(1.0), tint, smoothstep(0.0, max(0.65, max(footprint.x, footprint.y)), inset));
	}
	return grass_colour;
}

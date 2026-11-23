// Managed pasture and its worn shoulders share these planes, row filtering and cover colours.
#include "res://render/club_infield.gdshaderinc"
uniform int meadow_count = 0;
uniform vec4 meadow_extent;
uniform vec4 meadow_bounds[5]; // north/east min and max, metres
uniform vec4 meadow_edges[20]; // four inward planes per field; w follows SceneryLoader.FIELD_COVERS

// A square wave of period 1 (+1, then -1) box-filtered over du: the exact mean via its triangle-wave integral.
float square_filtered(float u, float du) {
	du = max(du, 1e-4);
	float a = 0.5 - abs(fract(u + 0.5 * du) - 0.5);
	float b = 0.5 - abs(fract(u - 0.5 * du) - 0.5);
	return (a - b) / du;
}

vec3 meadow_colour(vec3 grass_colour, vec2 ne, vec2 footprint) {
	grass_colour = club_infield_colour(grass_colour, ne, footprint);
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
		// Work in metres along this field's own fence, so rows turn with the parcel.
		float along = dot(vec2(-first.y, first.x), ne);
		float across_pixel = dot(abs(first.xy), footprint);
		float mottling = vnoise(ne * 0.073 + first.z * 0.13);
		mottling = mix(mottling, 0.5, smoothstep(0.25, 0.9, max(footprint.x, footprint.y) * 0.073));
		float verge = smoothstep(0.3, 2.1 + mottling * 1.5, inset);
		vec3 tint;
		if (first.w > 3.5) {
			// Leafy forage in drills with visible earth and a grass headland for turning.
			float phase = (across + 0.38 * sin(along * 0.047)) / 0.88;
			float resolved = 1.0 - smoothstep(0.18, 0.8, across_pixel / 0.88);
			float leaf = 0.61 + 0.39 * cos(TAU * phase) * resolved;
			vec3 plants = mix(vec3(0.48, 0.90, 0.76), vec3(0.66, 0.99, 0.68), mottling);
			vec3 tilth = vec3(1.12, 0.68, 0.53);
			// Two wheel marks recur at implement width; filter both out on distant flyovers.
			float wheel = abs(abs(fract(phase / 16.0 + 0.5) - 0.5) * 14.08 - 0.86);
			float tread = (1.0 - smoothstep(0.09, 0.23 + across_pixel * 0.35, wheel))
				* (1.0 - smoothstep(0.25, 0.95, across_pixel));
			tint = mix(vec3(0.95, 1.01, 0.83), mix(tilth, plants, leaf * (1.0 - tread)),
				smoothstep(2.9, 4.3, inset));
		} else if (first.w > 2.5) {
			// Short buff turf inside the stock pen; repeated use wears a narrow line along the rails.
			float rail_wear = 1.0 - smoothstep(0.45, 1.45, abs(inset - 1.9));
			rail_wear *= 1.0 - smoothstep(0.65, 2.8, max(footprint.x, footprint.y));
			tint = mix(vec3(1.01, 1.03, 0.75), vec3(1.30, 1.01, 0.71), smoothstep(0.38, 0.75, mottling));
			tint = mix(tint, vec3(1.24, 0.90, 0.70), rail_wear * (0.38 + 0.36 * mottling));
		} else if (first.w > 1.5) {
			// Rotational grazing leaves islands of mature grass in the shorter, warmer sward.
			tint = mix(vec3(0.74, 0.98, 0.69), vec3(1.15, 1.07, 0.82), smoothstep(0.30, 0.69, mottling));
		} else if (first.w > 0.5) {
			// Long hay swaths with a perimeter pass where the mower turns across the ends.
			float pitch = 7.8;
			float phase = (across + 0.7 * sin(along * 0.029) + (mottling - 0.5) * 0.8) / pitch;
			float pixel = max(0.001, across_pixel / pitch);
			float cut = square_filtered(phase, pixel);
			float straw = 1.0 - smoothstep(0.025, 0.085 + pixel, abs(fract(phase + 0.5) - 0.5));
			straw *= (1.0 - smoothstep(0.08, 0.35, pixel)) * (0.55 + 0.45 * mottling);
			float rows = smoothstep(5.0, 7.5, inset);
			float turn = square_filtered(inset / pitch, max(footprint.x, footprint.y) / pitch);
			tint = vec3(1.26, 1.09, 0.76) * (1.0 + mix(turn, cut, rows) * 0.065);
			tint += vec3(0.27, 0.17, 0.05) * straw * rows;
		} else {
			// Rested deep-green pasture: fine clumps and soft growth bands rather than cut rows.
			vec2 growth_uv = vec2(across * 0.35, along * 0.16) + first.z;
			float tuft = (vnoise(growth_uv) - 0.5) * (1.0 - smoothstep(0.6, 2.4, max(footprint.x, footprint.y)));
			tint = mix(vec3(0.62, 0.89, 0.76), vec3(0.82, 1.07, 0.88), mottling) * (1.0 + tuft * 0.16);
		}
		tint = mix(vec3(0.78, 0.90, 0.72), tint, verge);
		// Keep the base grass visible through dry spots and the cut rows under the field lighting.
		float coverage = smoothstep(0.0, max(0.65, max(footprint.x, footprint.y)), inset);
		return grass_colour * mix(vec3(1.0), tint, coverage * 0.78);
	}
	return grass_colour;
}

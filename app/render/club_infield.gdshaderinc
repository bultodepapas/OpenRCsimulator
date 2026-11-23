// All coordinates are north/east metres, shared by turf and worn-path shoulders.
uniform int club_infield_edge_count = 0;
uniform vec4 club_infield_edges[16]; // start.xy and step.zw, including gate closure
uniform vec4 club_infield_bounds;
uniform vec4 club_infield_core = vec4(1.0, 1.0, -1.0, -1.0);
uniform vec4 club_infield_apron = vec4(0.0, 0.0, -8.0, -8.0);

vec3 club_infield_colour(vec3 grass_colour, vec2 ne, vec2 footprint) {
	if (club_infield_edge_count == 0 || any(lessThan(ne, club_infield_bounds.xy))
			|| any(greaterThan(ne, club_infield_bounds.zw))) return grass_colour;
	vec2 apron_delta = abs(ne - club_infield_apron.xy) - club_infield_apron.zw;
	float apron_clearance = max(apron_delta.x, apron_delta.y);
	if (apron_clearance <= 0.0) return grass_colour;

	float edge_distance = 8.0;
	if (any(lessThan(ne, club_infield_core.xy)) || any(greaterThan(ne, club_infield_core.zw))) {
		bool inside = false;
		float distance_sq = edge_distance * edge_distance;
		for (int i = 0; i < club_infield_edge_count; i++) {
			vec4 edge = club_infield_edges[i];
			vec2 q = ne - edge.xy;
			vec2 step_ne = edge.zw;
			// Half-open east intervals count a ray through a vertex once.
			if ((q.y < 0.0) != (q.y < step_ne.y)) {
				float side = step_ne.x * q.y - step_ne.y * q.x;
				if ((side > 0.0) == (step_ne.y > 0.0)) inside = !inside;
			}
			vec2 half_step = step_ne * 0.5;
			if (all(lessThan(abs(q - half_step), abs(half_step) + vec2(8.0)))) {
				float t = clamp(dot(q, step_ne) / max(dot(step_ne, step_ne), 0.0001), 0.0, 1.0);
				vec2 nearest = q - t * step_ne;
				distance_sq = min(distance_sq, dot(nearest, nearest));
			}
		}
		if (!inside) return grass_colour;
		edge_distance = sqrt(distance_sq);
	}

	// A 3.4 m deck works along the long axis, then turns around the headland.
	vec2 cut_normal = vec2(0.9976, 0.0698);
	float pitch = 6.8;
	float inner_pass = cos(TAU * dot(ne, cut_normal) / pitch);
	float border_pass = cos(TAU * edge_distance / pitch);
	float edge_filter = max(footprint.x, footprint.y);
	border_pass *= 1.0 - smoothstep(0.2, 0.75, edge_filter / pitch);
	inner_pass *= 1.0 - smoothstep(0.2, 0.75, dot(footprint, cut_normal) / pitch);
	float cut = mix(border_pass, inner_pass, smoothstep(4.0, 8.0, edge_distance));
	float treatment = smoothstep(0.0, max(1.0, edge_filter), edge_distance) * smoothstep(0.0, 5.0, apron_clearance);
	vec3 turf_tint = vec3(0.90, 1.025, 0.97) * (1.0 + 0.052 * cut);
	return grass_colour * mix(vec3(1.0), turf_tint, treatment);
}

shader_type canvas_item;
render_mode unshaded;

// UI-22-R6. Adapted from sentinelcmd's CC0 Liquid Glass UI (rounded mask/edge)
// and DimensionAlmios' MIT Shine Sweep (projected glint). See LICENSE.txt.
// Explicit event-driven progress; no wall clock, screen copy or background blur.
uniform vec2 rect_size = vec2(320.0, 56.0);
uniform float corner_radius = 7.0;
uniform vec4 base_color : source_color = vec4(0.714, 1.0, 0.263, 1.0);
uniform vec4 crystal_color : source_color = vec4(0.89, 1.0, 0.76, 1.0);
uniform float primary = 1.0;
uniform float energy = 0.0;
uniform float shine_progress = -1.0;
uniform float press_depth = 0.0;
uniform float disabled = 0.0;
varying vec4 vertex_tint;

void vertex() {
	vertex_tint = COLOR;
}

float rounded_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// Analytic contour normal: stable on straight edges and rounded corners at any UI scale.
vec2 contour_normal(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	vec2 corner = max(q, vec2(0.0));
	float corner_length = length(corner);
	vec2 axis = q.x > q.y ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
	return (corner_length > 0.0001 ? corner / max(corner_length, 0.0001) : axis) * sign(p);
}

void fragment() {
	vec2 half_size = max(rect_size * 0.5, vec2(1.0));
	float radius = min(corner_radius, min(half_size.x, half_size.y));
	vec2 p = (UV - 0.5) * rect_size;
	float sdf = rounded_box(p, half_size, radius);
	float aa = max(fwidth(sdf), 0.6);
	float mask = 1.0 - smoothstep(-aa, aa, sdf);
	float depth = max(-sdf, 0.0);
	float bevel = 1.0 - smoothstep(1.0, mix(2.5, 6.0, primary), depth);
	float light = pow(1.0 - UV.y, 2.0);
	float diagonal = UV.x * cos(0.38) + UV.y * sin(0.38);
	float reflection = 1.0 - smoothstep(0.0, 0.36, abs(diagonal - 0.26));

	// A continuous convex highlight replaces the hard halfway stripe. The saturated
	// body remains readable; all extra light stays above the tested .76 * .88 floor.
	vec3 bright = mix(base_color.rgb, crystal_color.rgb, 0.24);
	vec3 button_body = mix(base_color.rgb * 0.76, bright, 1.0 - UV.y);
	button_body = mix(button_body, crystal_color.rgb, light * 0.16);
	button_body += crystal_color.rgb * reflection * 0.025;
	button_body *= 1.0 - press_depth * 0.12;
	vec3 panel_body = base_color.rgb + crystal_color.rgb * (light * 0.012 + reflection * 0.006);
	vec3 body = mix(panel_body, button_body, primary);

	// Two opposing edge catches suggest polished thickness, without sampling or
	// distorting the scene. The lower inset is a stylized light return, not a caustic simulation.
	vec2 normal = contour_normal(p, half_size, radius);
	float key_light = pow(max(dot(normal, vec2(-0.45, -0.893)), 0.0), 2.0);
	float return_light = pow(max(dot(normal, vec2(0.3, 0.954)), 0.0), 4.0);
	float edge_light = bevel * (0.12 + key_light * 0.64 + return_light * 0.24);
	body = mix(body, crystal_color.rgb, edge_light * mix(0.09, 0.58, primary) * (1.0 - press_depth * 0.45));
	float inset = 1.0 - smoothstep(0.45, 0.45 + aa, abs(depth - 4.0));
	float lower_edge = smoothstep(0.62, 0.94, UV.y);
	body += crystal_color.rgb * inset * lower_edge * primary * (0.055 + energy * 0.045);
	body += base_color.rgb * bevel * energy * primary * 0.045;

	// One manually driven specular sweep; the published auto-clock branch is deliberately omitted.
	float distance_to_shine = abs(diagonal - shine_progress);
	float soft = 1.0 - smoothstep(0.0, 0.12, distance_to_shine);
	float hard = 1.0 - smoothstep(0.012 - fwidth(diagonal), 0.012 + fwidth(diagonal), distance_to_shine);
	float shine = mix(soft, hard, 0.24);
	float sheen_strength = mix(0.025, 0.14 + bevel * 0.36, primary) * (1.0 - disabled);
	body += crystal_color.rgb * shine * sheen_strength;
	body = mix(body, base_color.rgb, disabled);
	COLOR = vec4(body, mask * base_color.a) * vertex_tint;
}

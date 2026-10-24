shader_type canvas_item;
render_mode unshaded;

// UI-22-R7. Adapted from sentinelcmd's CC0 Liquid Glass UI (rounded mask/edge)
// and DimensionAlmios' MIT Shine Sweep (projected glint). See LICENSE.txt.
// Explicit event-driven progress; no wall clock, screen copy or background blur.
uniform vec2 rect_size = vec2(320.0, 56.0);
uniform float corner_radius = 7.0;
uniform vec4 base_color : source_color = vec4(0.031, 0.161, 0.059, 0.92);
uniform vec4 crystal_color : source_color = vec4(0.769, 1.0, 0.702, 1.0);
uniform vec4 emission_color : source_color = vec4(0.4, 1.0, 0.086, 1.0);
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
	float bevel = 1.0 - smoothstep(1.0, mix(2.5, 9.0, primary), depth);
	float light = pow(1.0 - UV.y, 2.0);
	float diagonal = UV.x * cos(0.38) + UV.y * sin(0.38);
	float reflection = 1.0 - smoothstep(0.0, 0.36, abs(diagonal - 0.26));

	// The reference glass holds darkness inside and concentrates fluorescence at its
	// thickness. Keep the text well dark, including during the specular sweep.
	vec3 button_body = base_color.rgb * (0.74 + light * 0.26);
	button_body += emission_color.rgb * reflection * 0.022;
	float folded_reflection = 1.0 - smoothstep(0.005, 0.060, abs(diagonal - 0.31));
	float reflection_echo = 1.0 - smoothstep(0.002, 0.012, abs(diagonal - 0.37));
	button_body += emission_color.rgb * (folded_reflection * 0.060 + reflection_echo * 0.018);
	button_body *= 1.0 - press_depth * 0.16;
	vec3 panel_body = base_color.rgb + crystal_color.rgb * (light * 0.012 + reflection * 0.006);
	vec3 body = mix(panel_body, button_body, primary);

	// Opposing polished catches and two nested contours suggest thick fluorescent
	// glass. These are analytic light cues, not scene refraction or physical caustics.
	vec2 normal = contour_normal(p, half_size, radius);
	float key_light = pow(max(dot(normal, vec2(-0.45, -0.893)), 0.0), 2.0);
	float return_light = pow(max(dot(normal, vec2(0.3, 0.954)), 0.0), 4.0);
	float edge_light = bevel * (0.12 + key_light * 0.64 + return_light * 0.24);
	vec3 panel_edge = mix(body, crystal_color.rgb, edge_light * 0.09);
	float lip = 1.0 - smoothstep(0.65, 0.65 + aa, abs(depth - 1.6));
	float inset = 1.0 - smoothstep(0.45, 0.45 + aa, abs(depth - 5.0));
	float lower_edge = smoothstep(0.48, 0.95, UV.y);
	float key_falloff = 0.35 + 0.65 * pow(1.0 - UV.x, 2.0);
	float return_falloff = 0.35 + 0.65 * pow(UV.x, 2.0);
	float fluorescence = bevel * (0.14 + return_light * return_falloff * 0.20 + energy * 0.10);
	fluorescence += lip * (0.24 + key_light * key_falloff * 0.50 + return_light * return_falloff * 0.20);
	fluorescence += inset * (0.14 + lower_edge * 0.34) * (1.0 - press_depth * 0.35);
	vec3 glass_edge = body + emission_color.rgb * fluorescence;
	glass_edge += crystal_color.rgb * lip * pow(key_light, 3.0) * 0.16;
	body = mix(panel_edge, glass_edge, primary);

	// One manually driven specular sweep; the published auto-clock branch is deliberately omitted.
	float distance_to_shine = abs(diagonal - shine_progress);
	float soft = 1.0 - smoothstep(0.0, 0.12, distance_to_shine);
	float hard = 1.0 - smoothstep(0.012 - fwidth(diagonal), 0.012 + fwidth(diagonal), distance_to_shine);
	float shine = mix(soft, hard, 0.24);
	float sheen_strength = mix(0.025, 0.012 + bevel * 0.44, primary) * (1.0 - disabled);
	body += mix(crystal_color.rgb, emission_color.rgb, primary * 0.72) * shine * sheen_strength;
	body = mix(body, base_color.rgb, disabled);
	float opacity = mix(base_color.a, 1.0, bevel * primary * (1.0 - disabled));
	COLOR = vec4(body, mask * opacity) * vertex_tint;
}

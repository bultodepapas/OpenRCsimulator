shader_type canvas_item;
render_mode unshaded;

// UI-22-R8. Adapted from sentinelcmd's CC0 Liquid Glass UI (rounded mask/edge)
// and DimensionAlmios' MIT Shine Sweep (projected glint). See LICENSE.txt.
// Explicit event-driven progress; no wall clock, screen copy or background blur.
uniform vec2 rect_size = vec2(320.0, 56.0);
uniform float corner_radius = 7.0;
uniform vec4 base_color : source_color = vec4(0.031, 0.161, 0.059, 0.86);
uniform vec4 crystal_color : source_color = vec4(0.769, 1.0, 0.702, 1.0);
uniform vec4 emission_color : source_color = vec4(0.239, 1.0, 0.039, 1.0);
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
	float light = pow(1.0 - UV.y, 2.0);
	float diagonal = UV.x * cos(0.38) + UV.y * sin(0.38);
	float reflection = 1.0 - smoothstep(0.0, 0.36, abs(diagonal - 0.26));
	vec2 normal = contour_normal(p, half_size, radius);
	float key_light = pow(max(dot(normal, vec2(-0.45, -0.893)), 0.0), 2.0);
	float return_light = pow(max(dot(normal, vec2(0.3, 0.954)), 0.0), 4.0);

	// One manually driven specular sweep; the published auto-clock branch is deliberately omitted.
	float distance_to_shine = abs(diagonal - shine_progress);
	float soft = 1.0 - smoothstep(0.0, 0.12, distance_to_shine);
	float hard = 1.0 - smoothstep(0.012 - fwidth(diagonal), 0.012 + fwidth(diagonal), distance_to_shine);
	float shine = mix(soft, hard, 0.24);
	vec3 body = base_color.rgb;
	float opacity = base_color.a;
	if (primary < 0.5) {
		// Neutral panels bypass the extra fluorescent-wall/reflection work.
		float bevel = 1.0 - smoothstep(1.0, 2.5, depth);
		float edge_light = bevel * (0.12 + key_light * 0.64 + return_light * 0.24);
		body += crystal_color.rgb * (light * 0.012 + reflection * 0.006);
		body = mix(body, crystal_color.rgb, edge_light * 0.09);
		body += crystal_color.rgb * shine * 0.025;
	} else if (disabled < 0.5) {
		float bevel = 1.0 - smoothstep(1.0, 9.0, depth);
		// The interior carries a restrained green body color and reflected light,
		// while the much brighter wall communicates the thickness of the glass.
		body *= 0.74 + light * 0.26;
		body += emission_color.rgb * (0.055 + reflection * 0.022);
		float folded_reflection = 1.0 - smoothstep(0.005, 0.060, abs(diagonal - 0.31));
		float reflection_echo = 1.0 - smoothstep(0.002, 0.012, abs(diagonal - 0.37));
		body += emission_color.rgb * (folded_reflection * 0.140 + reflection_echo * 0.035);
		float face_arc = UV.y + 0.07 * sin(UV.x * 4.0 - 1.0);
		float face_reflection = exp(-pow((face_arc - 0.20) / 0.11, 2.0));
		body += emission_color.rgb * face_reflection * (0.085 + energy * 0.018);
		body *= 1.0 - press_depth * 0.16;

		// A rounded wall carries broad transmitted light between thin grazing catches.
		float lower_edge = smoothstep(0.48, 0.95, UV.y);
		float key_falloff = 0.35 + 0.65 * pow(1.0 - UV.x, 2.0);
		float return_falloff = 0.35 + 0.65 * pow(UV.x, 2.0);
		float wall = exp(-pow((depth - 3.6) / 2.7, 2.0));
		float outer_catch = 1.0 - smoothstep(0.35, 0.35 + aa, abs(depth - 1.2));
		float inner_catch = 1.0 - smoothstep(0.3, 0.3 + aa, abs(depth - 7.0));
		// Offset rear lip, following the overlapping rims in the supplied bowls.
		float rear_sdf = rounded_box(p - vec2(0.0, 1.4), max(half_size - vec2(2.8), vec2(0.5)), max(radius - 2.8, 0.0));
		float rear_catch = 1.0 - smoothstep(0.15, 0.15 + aa, abs(rear_sdf));
		float light_path = 0.24 + key_light * key_falloff * 0.60 + return_light * return_falloff * 0.38;
		float fluorescence = wall * light_path * (0.85 + energy * 0.18);
		fluorescence += outer_catch * (0.12 + key_light * key_falloff * 0.38);
		fluorescence += inner_catch * (0.035 + lower_edge * return_falloff * 0.24);
		fluorescence += rear_catch * (0.055 + lower_edge * return_falloff * 0.18);
		fluorescence += exp(-depth / 4.0) * 0.10;
		fluorescence *= 1.0 - press_depth * 0.22;
		body += emission_color.rgb * fluorescence;
		body += crystal_color.rgb * outer_catch * pow(key_light * key_falloff, 3.0) * 0.12;
		body += mix(crystal_color.rgb, emission_color.rgb, 0.72) * shine * (0.012 + bevel * 0.44);
		// Protect the text well while retaining a broad luminous wall outside it.
		body = mix(body, min(body, vec3(0.10, 0.30, 0.10)), smoothstep(7.0, 10.0, depth));
		opacity = mix(base_color.a, 1.0, bevel);
	}
	COLOR = vec4(body, mask * opacity) * vertex_tint;
}

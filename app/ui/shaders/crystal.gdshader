shader_type canvas_item;
render_mode unshaded;

// UI-22-R4. Adapted from sentinelcmd's CC0 Liquid Glass UI (rounded mask/edge)
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

void fragment() {
	vec2 half_size = max(rect_size * 0.5, vec2(1.0));
	float radius = min(corner_radius, min(half_size.x, half_size.y));
	float sdf = rounded_box((UV - 0.5) * rect_size, half_size, radius);
	float aa = max(fwidth(sdf), 0.6);
	float mask = 1.0 - smoothstep(-aa, aa, sdf);
	float rim = 1.0 - smoothstep(0.0, 1.8, -sdf);
	float light = 1.0 - smoothstep(0.0, 0.54, UV.y);
	float glass_band = 1.0 - smoothstep(0.40, 0.46, UV.y);
	float diagonal = UV.x * cos(0.38) + UV.y * sin(0.38);
	float reflection = 1.0 - smoothstep(0.0, 0.36, abs(diagonal - 0.26));

	vec3 bright = mix(base_color.rgb, crystal_color.rgb, 0.36);
	vec3 button_body = mix(base_color.rgb * 0.76, bright, 1.0 - UV.y);
	button_body = mix(button_body, crystal_color.rgb, glass_band * 0.18 + light * 0.12);
	button_body += crystal_color.rgb * reflection * 0.035;
	button_body *= 1.0 - press_depth * 0.12;
	vec3 panel_body = base_color.rgb + crystal_color.rgb * (light * 0.018 + reflection * 0.012);
	vec3 body = mix(panel_body, button_body, primary);

	// One manually driven specular sweep; the published auto-clock branch is deliberately omitted.
	float distance_to_shine = abs(diagonal - shine_progress);
	float soft = 1.0 - smoothstep(0.0, 0.15, distance_to_shine);
	float hard = 1.0 - smoothstep(0.045 - fwidth(diagonal), 0.045 + fwidth(diagonal), distance_to_shine);
	float shine = mix(soft, hard, 0.32);
	float sheen_strength = mix(0.045, 0.28, primary) * (1.0 - disabled);
	body += crystal_color.rgb * shine * sheen_strength;
	float rim_light = (0.2 + light * 0.5 + energy * 0.2) * rim;
	body = mix(body, crystal_color.rgb, rim_light * mix(0.18, 0.55, primary) * (1.0 - disabled));
	body = mix(body, base_color.rgb, disabled);
	COLOR = vec4(body, mask * base_color.a) * vertex_tint;
}

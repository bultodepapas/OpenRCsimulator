shader_type canvas_item;
render_mode unshaded;

// HUD-13-R14. Local tank optics; no screen texture, wall clock or physics feedback.
global uniform float sim_clock;
uniform vec2 rect_size = vec2(200.0, 100.0);
uniform vec4 liquid_color : source_color = vec4(0.945, 0.792, 0.49, 1.0);
uniform float fill = -1.0;
uniform float sample_clock = 0.0;
uniform float tilt = 0.0;
uniform float tilt_velocity = 0.0;
uniform float target_tilt = 0.0;
uniform float wave_energy = 0.0;

// Exact area quantile of a rectangle projected along a unit normal. Unlike a
// slope/height graph this works through both knife edges and inverted flight.
float surface_offset(vec2 down, vec2 extent, float amount) {
	vec2 spans = abs(down) * extent;
	float a = max(max(spans.x, spans.y), 0.0001);
	float b = min(spans.x, spans.y);
	float tail = min(amount, 1.0 - amount);
	float distance = tail < b / (2.0 * a)
		? a + b - sqrt(max(0.0, 8.0 * a * b * tail))
		: a * (1.0 - 2.0 * tail);
	return amount < 0.5 ? distance : -distance;
}

void fragment() {
	vec2 half_size = rect_size * 0.5;
	vec2 q = abs((UV - 0.5) * rect_size) - half_size + 8.0;
	float sdf = min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - 8.0;
	float aa = max(fwidth(sdf), 0.6);
	float mask = 1.0 - smoothstep(-aa, aa, sdf);
	// Match the CPU spring; clamp stale samples and handle the shared 1024 s clock wrap.
	// The render clock may trail the accepted tick by one interpolation step.
	float dt = clamp(mod(sim_clock - sample_clock + 512.0, 1024.0) - 512.0, 0.0, 2.0);
	float offset = tilt - target_tilt;
	float angle = target_tilt + exp(-4.0 * dt) * (offset * cos(9.0 * dt)
		+ (tilt_velocity + 4.0 * offset) / 9.0 * sin(9.0 * dt));
	vec2 down = vec2(sin(angle), cos(angle));
	vec2 tangent = vec2(down.y, -down.x);
	float energy = wave_energy * exp(-2.8 * dt);
	float clearance = clamp(min(fill, 1.0 - fill) / 0.15, 0.0, 1.0);
	float phase = 6.28318530718 * fract(sim_clock * (704.0 / 1024.0));
	vec2 point = (UV - 0.5) * rect_size;
	float along = dot(point, tangent) / max(dot(abs(tangent), rect_size), 1.0) + 0.5;
	float wave = clearance * energy * (2.4 * sin(along * 6.28318530718 + phase)
		+ 1.2 * sin(along * 12.56637061436 - phase * 2.0));
	float surface = surface_offset(down, half_size, clamp(fill, 0.0, 1.0));
	float depth = dot(point, down) - surface - wave;
	float edge = max(fwidth(depth), 0.6);
	float wet = smoothstep(-edge, edge, depth);
	if (fill <= 0.0) { wet = 0.0; }
	if (fill >= 1.0) { wet = 1.0; }
	float optical_depth = fill >= 1.0 ? 1.0 : clamp(depth / max(dot(abs(down), rect_size), 1.0), 0.0, 1.0);
	// Actual alpha blending transmits the inner tank ribs. Deeper fluid absorbs
	// more light; a fine meniscus and doubled reflection suggest clear tinted liquid.
	vec3 color = liquid_color.rgb * mix(0.8, 0.48, optical_depth);
	float opacity = wet * mix(0.28, 0.57, sqrt(optical_depth));
	float crest = fill > 0.0 && fill < 1.0 ? exp(-abs(depth) / 0.4) : 0.0;
	color = mix(color, mix(liquid_color.rgb, vec3(1.0), 0.65), crest * 0.75);
	opacity = max(opacity, crest * 0.85);
	float reflection = 1.0 - smoothstep(0.0, 0.045, abs(UV.x + UV.y * 0.14 - 0.18));
	float return_reflection = 1.0 - smoothstep(0.0, 0.018, abs(UV.x + UV.y * 0.14 - 0.28));
	float rim = 1.0 - smoothstep(0.0, 1.7, -sdf);
	float glass = reflection * 0.08 + return_reflection * 0.025 + rim * 0.25;
	color = mix(color, vec3(0.65, 0.8, 0.86), glass);
	opacity = max(opacity, glass);
	if (fill < 0.0) {
		float hatch = step(0.82, fract((UV.x * rect_size.x + UV.y * rect_size.y) / 14.0));
		color = vec3(0.18);
		opacity = hatch * 0.22 + rim * 0.3;
	}
	COLOR = vec4(color, mask * opacity);
}

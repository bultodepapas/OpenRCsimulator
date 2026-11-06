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
	float slope = target_tilt + exp(-4.0 * dt) * (offset * cos(9.0 * dt)
		+ (tilt_velocity + 4.0 * offset) / 9.0 * sin(9.0 * dt));
	float energy = wave_energy * exp(-2.8 * dt);
	// Whole cycles across the chamber have zero mean; taper near full/empty so waves cannot create fuel.
	float clearance = clamp(min(fill, 1.0 - fill) / 0.34, 0.0, 1.0);
	float phase = 6.28318530718 * fract(sim_clock * (704.0 / 1024.0));
	float wave = energy * (0.024 * sin(UV.x * 6.28318530718 + phase)
		+ 0.012 * sin(UV.x * 12.56637061436 - phase * 2.0));
	float surface = 1.0 - clamp(fill, 0.0, 1.0) + clearance * (clamp(slope, -0.6, 0.6) * (UV.x - 0.5) + wave);
	float edge = max(fwidth(UV.y), 0.002);
	float depth = UV.y - surface;
	float wet = smoothstep(-edge, edge, depth);
	if (fill <= 0.0) { wet = 0.0; }
	if (fill >= 1.0) { wet = 1.0; }
	vec3 dry_color = vec3(0.023, 0.037, 0.044);
	vec3 fluid = liquid_color.rgb * mix(0.86, 0.26, smoothstep(0.0, 0.85, depth));
	// A narrow bright meniscus and restrained moving light give the liquid depth.
	float crest = exp(-abs(depth) * rect_size.y / 2.0);
	float caustic = pow(0.5 + 0.5 * sin(UV.x * 18.0 + UV.y * 7.0 + phase), 6.0);
	fluid += liquid_color.rgb * (0.06 * caustic * energy + 0.12 * pow(UV.y, 3.0));
	vec3 color = mix(dry_color, fluid, wet);
	if (fill > 0.0 && fill < 1.0) { color += mix(liquid_color.rgb, vec3(1.0), 0.55) * crest * 0.5; }
	// Static glass highlights stay quiet when the aircraft is steady or paused.
	float reflection = 1.0 - smoothstep(0.0, 0.085, abs(UV.x + UV.y * 0.14 - 0.18));
	float rim = 1.0 - smoothstep(0.0, 1.7, -sdf);
	color += vec3(0.55, 0.7, 0.76) * (reflection * 0.07 + rim * 0.22);
	if (fill < 0.0) {
		float hatch = step(0.82, fract((UV.x * rect_size.x + UV.y * rect_size.y) / 14.0));
		color = dry_color + vec3(0.04) * hatch + vec3(0.1) * rim;
	}
	COLOR = vec4(color, mask);
}

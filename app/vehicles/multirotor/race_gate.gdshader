// DR-32 race gate panel: one solid frame box (post or bar) drawn as a fabric panel band in model space: alternating
// stripes along the long axis (or a checker for the start/finish gate), white piping on the outer edge, and an
// emissive LED strip on the edge that borders the aperture. Model axes: the long axis, the in-plane across axis
// (toward the aperture is +inner_sign) and the gate normal. Presentation only; the box itself is the collision box.
shader_type spatial;
render_mode cull_back;

uniform vec4 color_a : source_color = vec4(0.95, 0.18, 0.55, 1.0);
uniform vec4 color_b : source_color = vec4(0.12, 0.12, 0.14, 1.0);
uniform vec4 led_color : source_color = vec4(0.35, 1.0, 0.95, 1.0);
uniform vec3 long_axis = vec3(0.0, 1.0, 0.0);
uniform vec3 across_axis = vec3(1.0, 0.0, 0.0);
uniform float inner_sign = 1.0;
uniform float half_across = 0.09;
uniform float stripe_period = 0.6;
uniform float led_width = 0.025;
uniform float piping_width = 0.012;
uniform float led_energy = 1.0;
uniform float panel_glow = 0.0;
uniform bool checker = false;
uniform bool solid = false;
uniform float checker_cell = 0.09;
// LED animation: chase runs segments along the strip (the next gate); flash is a short white burst (a gate passed);
// breathe is a slow calm-state swell; weave is the fabric mesh texture strength.
uniform float chase = 0.0;
uniform float chase_speed = 1.6;
uniform float flash = 0.0;
uniform float breathe = 0.0;
uniform float weave = 0.05;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float along = dot(local_pos, long_axis);
	float across = dot(local_pos, across_axis) * inner_sign;
	vec3 base;
	if (checker) {
		float c = mod(floor(along / checker_cell) + floor((across + half_across) / checker_cell), 2.0);
		base = mix(vec3(0.95), vec3(0.04), c);
	} else if (solid) {
		base = color_a.rgb;
	} else {
		float stripe = step(0.5, fract(along / stripe_period));
		base = mix(color_a.rgb, color_b.rgb, stripe);
	}
	// Woven vinyl mesh: a fine two-axis grid darkens the fabric slightly (reads only up close).
	vec2 fibre = fract(vec2(along, across) * 55.0);
	base *= 1.0 - weave * (step(0.5, fibre.x) + step(0.5, fibre.y));
	float led = step(half_across - led_width, across);
	float piping = step(half_across - piping_width, -across);
	vec3 albedo = mix(base, vec3(0.97), piping);
	vec3 led_rgb = mix(led_color.rgb, vec3(1.0), clamp(flash, 0.0, 1.0));
	albedo = mix(albedo, led_rgb, led);
	float run = 0.45 + 0.55 * smoothstep(0.35, 0.65, fract(along / 0.35 - TIME * chase_speed));
	float swell = 1.0 + breathe * 0.35 * sin(TIME * 1.7);
	float level = led_energy * mix(1.0, run, chase) * swell + flash * 2.0;
	ALBEDO = albedo;
	ROUGHNESS = mix(0.75, 0.35, led);
	EMISSION = led_rgb * led * level + base * panel_glow;
}

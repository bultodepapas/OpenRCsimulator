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
	float led = step(half_across - led_width, across);
	float piping = step(half_across - piping_width, -across);
	vec3 albedo = mix(base, vec3(0.97), piping);
	albedo = mix(albedo, led_color.rgb, led);
	ALBEDO = albedo;
	ROUGHNESS = mix(0.75, 0.35, led);
	EMISSION = led_color.rgb * led * led_energy + base * panel_glow;
}

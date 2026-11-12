// DR-32 neon halo of a gate's LED edge: an additive, unlit quad in the gate plane that fades from the LED line into
// the aperture (light, not a solid: it never collides), with an optional chase running along the edge.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 glow_color : source_color = vec4(0.3, 1.0, 0.2, 1.0);
uniform float energy = 0.5;
// The quad edge that carries the LED, in UV space: (0,-1) top, (0,1) bottom, (-1,0) left, (1,0) right.
uniform vec2 edge_dir = vec2(0.0, -1.0);
uniform float chase = 0.0;
uniform float chase_speed = 1.6;
// Chase segments along the edge (edge length / segment length).
uniform float segments = 8.0;
uniform float flash = 0.0;
// 1 / the scene's tonemap exposure (eye adaptation at night would otherwise burn the halo to white).
uniform float exposure_comp = 1.0;

void fragment() {
	float d = dot(UV - vec2(0.5), edge_dir) * 2.0;
	float falloff = pow(clamp(0.5 * (d + 1.0), 0.0, 1.0), 3.0);
	float along = abs(edge_dir.x) > 0.5 ? UV.y : UV.x;
	float run = 0.45 + 0.55 * smoothstep(0.35, 0.65, fract(along * segments - TIME * chase_speed));
	float modulation = mix(1.0, run, chase);
	vec3 colour = mix(glow_color.rgb, vec3(1.0), clamp(flash, 0.0, 1.0));
	ALBEDO = colour * falloff * (energy * modulation + flash * 1.5) * exposure_comp;
}

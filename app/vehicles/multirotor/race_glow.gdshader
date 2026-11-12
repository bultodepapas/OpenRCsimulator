// DR-32 neon halo of a gate's LED edges: the four edge quads of one gate merged into one mesh in the gate plane. Each
// quad fades from its LED line into the aperture (light, not a solid: it never collides), with an optional chase along
// the edge. Per quad the mesh carries in COLOR: rg = the LED edge direction in UV space, mapped from -1..1 to 0..1
// ((0,-1) top, (0,1) bottom, (-1,0) left, (1,0) right), b = chase segments / 64.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 glow_color : source_color = vec4(0.3, 1.0, 0.2, 1.0);
uniform float energy = 0.5;
uniform float chase = 0.0;
uniform float chase_speed = 1.6;
uniform float flash = 0.0;
global uniform float race_exposure_comp;

varying vec3 edge;

void vertex() {
	edge = vec3(COLOR.rg * 2.0 - 1.0, COLOR.b * 64.0);
}

void fragment() {
	vec2 edge_dir = vec2(round(edge.x), round(edge.y));
	float d = dot(UV - vec2(0.5), edge_dir) * 2.0;
	float falloff = pow(clamp(0.5 * (d + 1.0), 0.0, 1.0), 3.0);
	float along = abs(edge_dir.x) > 0.5 ? UV.y : UV.x;
	float run = 0.8 + 0.2 * smoothstep(0.2, 0.8, fract(along * edge.z - TIME * chase_speed));
	float modulation = mix(1.0, run, chase);
	vec3 colour = mix(glow_color.rgb, vec3(1.0), clamp(flash, 0.0, 1.0));
	ALBEDO = colour * falloff * (energy * modulation + flash * 1.5) * race_exposure_comp;
}

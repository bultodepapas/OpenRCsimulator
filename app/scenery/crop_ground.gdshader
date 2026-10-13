// LU-25 original cultivated soil: filtered clods and tillage variation on the existing flat ground.
shader_type spatial;
render_mode world_vertex_coords;
varying vec3 world_position;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise21(vec2 p) {
	vec2 cell = floor(p);
	vec2 t = fract(p);
	t = t * t * (3.0 - 2.0 * t);
	return mix(mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), t.x),
		mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + vec2(1.0)), t.x), t.y);
}

void vertex() {
	world_position = VERTEX;
}

void fragment() {
	vec2 p = world_position.xz;
	float footprint = max(length(dFdx(p)), length(dFdy(p)));
	float clods = (noise21(p * 4.0) - 0.5) * (1.0 - smoothstep(0.08, 0.35, footprint));
	float broad = noise21(p * 0.8) - 0.5;
	ALBEDO = COLOR.rgb * (1.0 + broad * 0.18 + clods * 0.16);
	ROUGHNESS = 1.0;
	SPECULAR = 0.05;
}

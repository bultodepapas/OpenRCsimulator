// Thin, worn course paint for direction arrows and the start grid.
// The marked meshes sample the authoritative road; this shader only erodes pigment.
shader_type spatial;
render_mode cull_disabled;

uniform vec4 pigment : source_color = vec4(0.82, 0.78, 0.68, 1.0);
varying vec2 world_xz;

float paint_hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

float paint_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 blend = fract(point);
	blend = blend * blend * (3.0 - 2.0 * blend);
	return mix(mix(paint_hash(cell), paint_hash(cell + vec2(1.0, 0.0)), blend.x),
		mix(paint_hash(cell + vec2(0.0, 1.0)), paint_hash(cell + vec2(1.0, 1.0)), blend.x), blend.y);
}

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float coarse = paint_noise(world_xz * 5.5 + vec2(3.7, 14.1));
	float grain = paint_noise(world_xz * 19.0 + vec2(21.0, 7.0));
	float footprint = max(length(dFdx(world_xz)), length(dFdy(world_xz)));
	float visible_wear = 1.0 - smoothstep(0.020, 0.080, footprint);
	float intact = smoothstep(0.16, 0.34, grain) * smoothstep(0.12, 0.29, coarse);
	ALBEDO = pigment.rgb * (0.86 + 0.13 * coarse);
	ROUGHNESS = 0.96;
	METALLIC = 0.0;
	ALPHA = mix(1.0, intact, visible_wear);
	ALPHA_SCISSOR_THRESHOLD = 0.49;
}

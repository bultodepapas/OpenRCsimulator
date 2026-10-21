// CC0 Nymphaea mesh: Starry Skydancer, OpenGameArt "Lily Pads".
// Radial leaf shading and height follow this lake's two analytic waves.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

global uniform float sim_clock;
uniform int wave_count = 0;
uniform vec4 wave_params[2];
uniform float wave_phase_rad[2];
uniform float shore_fade_m = 5.5;
uniform bool flower_mode = false;
uniform vec3 flower_color : source_color = vec3(0.82, 0.77, 0.58);

varying vec3 leaf_color;
varying vec2 leaf_uv;

void vertex() {
	vec3 mean_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 ne = vec2(-mean_world.z, mean_world.x);
	float shore_t = clamp(INSTANCE_CUSTOM.r / shore_fade_m, 0.0, 1.0);
	float fade = shore_t * shore_t * (3.0 - 2.0 * shore_t);
	float height = 0.0;
	for (int i = 0; i < 2; i++) {
		if (i >= wave_count) { break; }
		vec4 wave = wave_params[i];
		vec2 heading = vec2(cos(wave.w), sin(wave.w));
		height += wave.x * sin(TAU * dot(heading, ne) / wave.y
			- TAU * sim_clock / wave.z + wave_phase_rad[i]);
	}
	VERTEX.y += height * fade;
	leaf_color = COLOR.rgb;
	leaf_uv = UV;
}

void fragment() {
	if (flower_mode) {
		ALBEDO = flower_color;
		METALLIC = 0.0;
		ROUGHNESS = 0.82;
		SPECULAR = 0.25;
	} else {
	// UVs are radial from the retained source's petiole/notch attachment.
	vec2 p = (leaf_uv - vec2(0.499, 0.628)) * vec2(1.0, 1.04);
	float r = length(p);
	float angle = atan(p.y, p.x);
	float midrib = pow(max(0.0, 1.0 - abs(sin(angle * 12.0 + r * 1.6))), 12.0);
	float small_veins = pow(max(0.0, 1.0 - abs(sin(angle * 35.0 - r * 5.0))), 18.0);
	float marbling = sin(leaf_uv.x * 67.0 + sin(leaf_uv.y * 41.0) * 1.8)
		* sin(leaf_uv.y * 57.0 - leaf_uv.x * 29.0);
	float olive_edge = smoothstep(0.27, 0.52, r);
	vec3 green = mix(vec3(0.21, 0.31, 0.10), vec3(0.37, 0.48, 0.16),
		clamp(0.38 + 0.13 * marbling + 0.24 * midrib + 0.08 * small_veins, 0.0, 1.0));
	green = mix(green, vec3(0.24, 0.30, 0.10), olive_edge * 0.32);
	ALBEDO = green * leaf_color;
	METALLIC = 0.0;
	ROUGHNESS = 0.72;
	SPECULAR = 0.28;
	}
}

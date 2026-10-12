shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

global uniform float sim_clock;
uniform vec4 base_color : source_color = vec4(1.0);
uniform sampler2D base_texture : source_color, filter_linear_mipmap_anisotropic;
uniform bool has_texture = false;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap;
uniform bool has_normal = false;
uniform float normal_strength = 1.0;
uniform float roughness_value = 0.85;
uniform bool fabric = false;
uniform bool skin = false;
uniform float shirt_start = 0.90;
varying float shirt_weight;
varying vec3 shirt_tint;
varying float skin_tone;

void vertex() {
	// Sub-centimeter breathing/weight shift, feet anchored. Integer cycles make the
	// 1024 s simulation-clock wrap seamless; pause and replay never use wall time.
	float phase = INSTANCE_CUSTOM.x * 6.28318530718;
	float motion = INSTANCE_CUSTOM.y;
	float upper = smoothstep(0.65, 1.5, VERTEX.y);
	shirt_weight = smoothstep(shirt_start, shirt_start + 0.12, VERTEX.y);
	shirt_tint = COLOR.rgb;
	skin_tone = INSTANCE_CUSTOM.z;
	VERTEX.x += sin(sim_clock * (6.28318530718 * 43.0 / 1024.0) + phase) * 0.004 * upper * motion;
	VERTEX.z += sin(sim_clock * (6.28318530718 * 171.0 / 1024.0) + phase) * 0.002 * upper * motion;
}

void fragment() {
	vec4 texel = has_texture ? texture(base_texture, UV) : vec4(1.0);
	ALBEDO = base_color.rgb * texel.rgb;
	if (fabric) {
		float detail = dot(ALBEDO, vec3(0.2126, 0.7152, 0.0722));
		ALBEDO = mix(ALBEDO, detail * shirt_tint * 2.2, shirt_weight);
	}
	if (skin) {
		ALBEDO *= mix(vec3(1.0), vec3(0.58, 0.42, 0.32), skin_tone);
	}
	ALPHA = base_color.a * texel.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
	SPECULAR = 0.22;
	if (has_normal) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
		NORMAL_MAP_DEPTH = normal_strength;
	}
}

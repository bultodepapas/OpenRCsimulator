shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform sampler2D fabric_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D fabric_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D fabric_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float length_m = 2.5;
uniform float circumference_m = 1.414;

void fragment() {
	// Arc-length UVs follow the bent sleeve; no projected grain sliding at the fold.
	vec2 metres = UV * vec2(length_m, circumference_m);
	vec2 weave = metres / vec2(0.72, 1.02);
	float grain = dot(texture(fabric_color, weave).rgb, vec3(0.2126, 0.7152, 0.0722));
	float band_distance = min(fract(UV.x * 5.0), 1.0 - fract(UV.x * 5.0)) * length_m / 5.0;
	float end_distance = min(UV.x, 1.0 - UV.x) * length_m;
	float long_distance = abs(UV.y - 0.75) * circumference_m;
	float aa = max(fwidth(metres.x), 0.0005);
	float hem = 1.0 - smoothstep(0.010, 0.010 + aa, end_distance);
	float seam = 1.0 - smoothstep(0.003, 0.003 + aa, min(band_distance, long_distance));
	float stitch_line = 1.0 - smoothstep(0.0006, 0.0006 + aa, abs(band_distance - 0.005));
	float stitch = stitch_line * smoothstep(0.25, 0.45, sin(metres.y * 900.0)) * (1.0 - smoothstep(0.0015, 0.004, aa));
	vec3 cloth = COLOR.rgb * clamp(0.80 + (grain - 0.72) * 1.5, 0.40, 1.04);
	// Keep the cream bands below clipping under the field's direct midday sun.
	cloth *= mix(1.0, 0.82, step(COLOR.r * 0.85, COLOR.g));
	cloth *= 1.0 - hem * 0.20 - seam * 0.12;
	ALBEDO = mix(cloth, vec3(0.50, 0.46, 0.36), stitch * 0.22);
	ROUGHNESS = clamp(texture(fabric_roughness, weave).r * 0.35 + 0.6, 0.78, 1.0);
	NORMAL_MAP = texture(fabric_normal, weave).rgb;
	NORMAL_MAP_DEPTH = 0.65;
	SPECULAR = 0.15;
}

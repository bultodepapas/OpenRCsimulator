shader_type spatial;
render_mode cull_disabled, diffuse_burley;
uniform sampler2D leaf_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 leaf_tint : source_color = vec4(0.48, 0.56, 0.29, 1.0);
uniform float source_height = 1.0;
varying float blade_height;
void vertex() {
	blade_height = clamp(VERTEX.y / source_height, 0.0, 1.0);
}
void fragment() {
	vec4 leaf = texture(leaf_color, UV);
	float tone = dot(leaf.rgb * COLOR.rgb, vec3(0.2126, 0.7152, 0.0722));
	// Keep the downloaded leaf texture, with an outdoor olive palette and dry tips.
	float variation = clamp(tone * 2.3, 0.65, 1.35);
	vec3 green = leaf_tint.rgb * variation;
	vec3 dry = vec3(0.22, 0.17, 0.075) * variation;
	float tip = smoothstep(0.6, 1.0, blade_height) * 0.32;
	ALBEDO = mix(green, dry, tip) * mix(0.72, 1.0, smoothstep(0.0, 0.28, blade_height));
	ROUGHNESS = 0.95;
	ALPHA = leaf.a;
	ALPHA_SCISSOR_THRESHOLD = 0.35;
}

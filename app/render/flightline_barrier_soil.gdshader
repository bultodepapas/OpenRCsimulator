shader_type spatial;
render_mode blend_mix, depth_draw_never;
uniform sampler2D soil_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec2 soil_uv;
void vertex() {
	soil_uv = VERTEX.xz * 3.0;
}
void fragment() {
	vec3 soil = texture(soil_color, soil_uv).rgb;
	ALBEDO = soil * vec3(0.74, 0.69, 0.59);
	ROUGHNESS = 1.0;
	ALPHA = COLOR.a * 0.7;
}

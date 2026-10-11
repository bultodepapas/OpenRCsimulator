shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform sampler2D mask : filter_linear, repeat_disable;
uniform float opacity = 0.5;
uniform float blur_uv = 0.01;

void fragment() {
	// Fixed, symmetric 13-tap disk kernel; no random rotation or temporal noise.
	float coverage = texture(mask, UV).a * 0.2;
	for (int i = 0; i < 6; i++) {
		float angle = float(i) * 1.0471975512;
		vec2 offset = vec2(cos(angle), sin(angle));
		coverage += texture(mask, UV + offset * blur_uv * 0.45).a * 0.08;
		coverage += texture(mask, UV + offset * blur_uv).a * 0.0533333333;
	}
	ALBEDO = vec3(0.0);
	ALPHA = coverage * opacity;
}

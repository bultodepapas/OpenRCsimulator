uniform sampler2D panel_1 : source_color, filter_linear, repeat_disable;
uniform sampler2D panel_2 : source_color, filter_linear, repeat_disable;
uniform sampler2D panel_3 : source_color, filter_linear, repeat_disable;
uniform sampler2D panel_4 : source_color, filter_linear, repeat_disable;
uniform sampler2D panel_5 : source_color, filter_linear, repeat_disable;
uniform sampler2D panel_6 : source_color, filter_linear, repeat_disable;

vec4 panel(vec3 ray) {
	vec3 major = abs(ray);
	if (major.y >= max(major.x, major.z)) {
		vec2 local = vec2(ray.x, -sign(ray.y) * ray.z) / major.y;
		vec2 st = local * 0.5 + 0.5;
		return ray.y > 0.0 ? texture(panel_5, st) : texture(panel_6, st);
	}
	if (major.x > major.z) {
		vec2 local = vec2(sign(ray.x) * ray.z, -ray.y) / major.x;
		vec2 st = local * 0.5 + 0.5;
		return ray.x > 0.0 ? texture(panel_2, st) : texture(panel_4, st);
	}
	vec2 local = vec2(-sign(ray.z) * ray.x, -ray.y) / major.z;
	vec2 st = local * 0.5 + 0.5;
	return ray.z < 0.0 ? texture(panel_1, st) : texture(panel_3, st);
}

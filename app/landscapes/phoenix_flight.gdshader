shader_type spatial;
render_mode unshaded, cull_front, fog_disabled, shadows_disabled;

#include "res://landscapes/phoenix_faces.gdshaderinc"

uniform float panorama_yaw;
varying vec3 direction;

void vertex() {
	direction = VERTEX;
}

void fragment() {
	vec3 ray = direction;
	ray.xz = vec2(cos(panorama_yaw) * ray.x - sin(panorama_yaw) * ray.z,
		sin(panorama_yaw) * ray.x + cos(panorama_yaw) * ray.z);
	ALBEDO = panel(ray).rgb;
}

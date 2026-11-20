shader_type canvas_item;

#include "res://landscapes/phoenix_faces.gdshaderinc"
uniform float yaw;
uniform float pitch;
uniform float aspect = 1.0;

void fragment() {
	// A 60-degree vertical field of view. Yaw and pitch rotate about the fixed camera eye.
	vec2 plane = (UV - 0.5) * vec2(aspect, -1.0) * 1.1547005;
	vec3 ray = vec3(plane, -1.0);
	ray.yz = vec2(cos(pitch) * ray.y - sin(pitch) * ray.z,
		sin(pitch) * ray.y + cos(pitch) * ray.z);
	ray.xz = vec2(cos(yaw) * ray.x - sin(yaw) * ray.z, sin(yaw) * ray.x + cos(yaw) * ray.z);
	COLOR = vec4(panel(ray).rgb, 1.0);
}

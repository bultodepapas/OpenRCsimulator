shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, fog_disabled;

#include "res://render/windsock_deformation.gdshaderinc"

uniform mat3 aircraft_basis;
uniform vec3 light_direction = vec3(0.0, 1.0, 0.0);
uniform vec2 frame_center;
uniform float frame_size = 2.0;
uniform bool deform_fabric = false;
uniform bool turn_with_basket = false;


void vertex() {
	vec3 shadow_vertex = VERTEX;
	if (deform_fabric) {
		shadow_vertex = windsock_deform_fabric_position(UV);
	} else if (turn_with_basket) {
		shadow_vertex = windsock_rotate_yaw(shadow_vertex, basket_yaw_rad);
	}
	vec3 p = aircraft_basis * shadow_vertex;
	vec2 ground = p.xz - light_direction.xz * p.y / max(light_direction.y, 0.05);
	vec2 clip = (ground - frame_center) * 2.0 / frame_size;
	// Keep the established Compatibility clip mapping; +z becomes +V on PlaneMesh.
	POSITION = vec4(clip.x, clip.y, 0.0, 1.0);
}


void fragment() {
	ALBEDO = vec3(1.0);
}

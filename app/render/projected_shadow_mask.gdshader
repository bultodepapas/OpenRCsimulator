shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, fog_disabled;

uniform mat3 aircraft_basis;
uniform vec3 light_direction = vec3(0.0, 1.0, 0.0);
uniform vec2 frame_center;
uniform float frame_size = 2.0;

void vertex() {
	vec3 p = aircraft_basis * VERTEX;
	vec2 ground = p.xz - light_direction.xz * p.y / max(light_direction.y, 0.05);
	vec2 clip = (ground - frame_center) * 2.0 / frame_size;
	// Compatibility render targets flip clip Y: +z must become +V on PlaneMesh.
	// The asymmetric GPU probe guards this mapping (and catches a negated clip.y).
	POSITION = vec4(clip.x, clip.y, 0.0, 1.0);
}

void fragment() {
	ALBEDO = vec3(1.0);
}

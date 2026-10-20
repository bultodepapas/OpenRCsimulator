// Bounded footprint approximation for distant downward fixtures; not a dynamic light.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
#include "res://render/world/engine_srgb.gdshaderinc"
global uniform float world_exposure;
uniform float night_factor = 0.0;
varying vec3 tint;
varying float gain;
void vertex() {
	tint = COLOR.rgb;
	gain = INSTANCE_CUSTOM.r;
	// Match countryside overlay ordering without physically raising the road.
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v.z += min(6.0, v.z * v.z * 0.0000015) * 1.35;
	POSITION = PROJECTION_MATRIX * v;
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float falloff = pow(max(0.0, 1.0 - dot(p, p)), 2.5);
	ALBEDO = encode_for_engine(tint * 0.065 * gain * night_factor / max(world_exposure, 0.001));
	ALPHA = falloff;
}

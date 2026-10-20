// LU-29: bounded distant optics, not photometric or aviation certification.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled, skip_vertex_transform;
#include "res://render/world/engine_srgb.gdshaderinc"
global uniform float world_exposure;
global uniform float sim_clock;
uniform float night_factor = 0.0;
varying vec3 tint;
varying float gain;
void vertex() {
	vec3 center = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float distance_m = length(center);
	float pixel_m = 2.0 * max(-center.z, 0.001) / (VIEWPORT_SIZE.y * abs(PROJECTION_MATRIX[1][1]));
	float diameter = max(0.12, 5.5 * pixel_m);
	VERTEX = center + vec3(VERTEX.xy * diameter, 0.025);
	NORMAL = vec3(0.0, 0.0, 1.0);
	tint = COLOR.rgb;
	// r = flash (shared 2 s cycle), g = output, b = shielded downlight, a = max range.
	gain = INSTANCE_CUSTOM.g * (1.0 - smoothstep(INSTANCE_CUSTOM.a * 0.65, INSTANCE_CUSTOM.a, distance_m));
	if (INSTANCE_CUSTOM.r > 0.5) {
		float phase = mod(sim_clock, 2.0);
		gain *= 1.0 - smoothstep(0.35, 0.55, phase);
	}
	if (INSTANCE_CUSTOM.b > 0.5) {
		vec3 world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		// Hood hides the lens from above; keep a grazing view, not a glowing skyward sphere.
		gain *= 1.0 - smoothstep(-0.04, 0.12, normalize(CAMERA_POSITION_WORLD - world).y);
	}
}
void fragment() {
	float radius = length(UV * 2.0 - 1.0);
	float core = 1.0 - smoothstep(0.18, 0.46, radius);
	float halo = exp(-8.0 * radius * radius) * 0.12;
	ALBEDO = encode_for_engine(tint * night_factor * gain / max(world_exposure, 0.001));
	ALPHA = clamp(core + halo, 0.0, 1.0);
}

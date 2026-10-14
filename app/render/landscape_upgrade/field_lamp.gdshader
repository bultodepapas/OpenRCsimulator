// FW-70: directional optical face for field luminaires; aircraft sprites retain their own shader.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled, skip_vertex_transform;
#include "res://render/world/engine_srgb.gdshaderinc"
global uniform float world_exposure;
uniform vec3 light_color : source_color = vec3(1.0);
uniform vec3 source_direction = vec3(0.0, -1.0, 0.0);
uniform float radiance = 2.0;
uniform float size_m = 0.24;
uniform float min_px = 3.0;
uniform float display_cap = 2.0;
varying float gain;
varying float facing;
void vertex() {
	vec3 center = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	center.z += 0.12; // keep the camera-facing halo clear of its own angled bezel; scene depth still occludes it
	vec3 source_position = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	facing = smoothstep(0.0, 0.3, dot(normalize(CAMERA_POSITION_WORLD - source_position), normalize(source_direction)));
	float depth_scale = PROJECTION_MATRIX[3][3] == 0.0 ? max(-center.z, 0.001) : 1.0;
	float units_per_pixel = 2.0 * depth_scale / max(VIEWPORT_SIZE.y * abs(PROJECTION_MATRIX[1][1]), 1.0);
	float core = max(size_m, min_px * units_per_pixel);
	VERTEX = center + vec3(VERTEX.xy * core * 1.8, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
	gain = size_m * size_m / (core * core);
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);
	float core = 1.0 - smoothstep(0.25, 0.52, radius);
	float halo = exp(-7.0 * dot(p, p)) * 0.12;
	ALBEDO = encode_for_engine(light_color * min(radiance * gain, display_cap / max(world_exposure, 0.001)));
	ALPHA = clamp(core * 0.85 + halo, 0.0, 1.0) * facing * (1.0 - smoothstep(0.85, 1.0, radius));
}

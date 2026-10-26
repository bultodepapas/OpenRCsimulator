// FW-RGB-05: animated per-instance presentation over the existing NightKit strip geometry.
// Animation time and local exposure are supplied by the displayed-pose owner; this shader never reads TIME.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled, skip_vertex_transform;

#include "res://render/world/engine_srgb.gdshaderinc"

#include "res://render/lighting/rgb_patterns.gdshaderinc"

uniform vec3 axis_dir = vec3(1.0, 0.0, 0.0);
uniform vec2 axis_range = vec2(0.0, 1.0); // projected start and length in the strip mesh's local frame
uniform bool use_path_uv = false; // authored centerline arc length; legacy fitted strips retain axis projection
uniform vec3 face_dir = vec3(0.0, -1.0, 0.0);
uniform float effect_gain = 1.0;
uniform float local_exposure = 1.0;
uniform float radiance = 0.25;
uniform float width_m = 0.015;
uniform float min_px = 2.0;
uniform float display_cap = 2.0;

varying float width_gain;
varying float underside;
varying float arc_u;

void vertex() {
	// Keep the source-frame projection before VERTEX becomes view-space for the width correction.
	float projected = dot(VERTEX, axis_dir);
	vec3 centre = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 side = normalize(mat3(MODELVIEW_MATRIX) * NORMAL);
	float depth_scale = PROJECTION_MATRIX[3][3] == 0.0 ? max(-centre.z, 0.001) : 1.0;
	float metres_per_pixel = 2.0 * depth_scale / (VIEWPORT_SIZE.y * abs(PROJECTION_MATRIX[1][1]));
	float width = max(width_m, min_px * metres_per_pixel);
	VERTEX = centre + side * UV.x * width * 0.5;
	NORMAL = vec3(0.0, 0.0, 1.0);
	width_gain = width_m / width;
	vec3 facing = normalize(mat3(MODELVIEW_MATRIX) * face_dir);
	underside = dot(facing, normalize(-centre));
	arc_u = use_path_uv ? clamp(UV.y, 0.0, 1.0) : clamp((projected - axis_range.x) / max(axis_range.y, 0.00001), 0.0, 1.0);
}

void fragment() {
	// Derive from the continuous coordinate before fract/reverse or pattern branches.
	// Every camera (including orthographic previews and insets) supplies its own footprint.
	float path_footprint = fwidth(arc_u);
	vec4 sampled = lighting_pattern(arc_u, path_footprint);
	float cap = max(display_cap, 0.0) / max(local_exposure, 0.001);
	// Adapt the emitter first: capping after modulation would flatten breathing and
	// brightness controls under the world's large night exposure.
	float emitted = min(max(radiance * width_gain, 0.0), cap) * max(effect_gain * sampled.a, 0.0);
	ALBEDO = encode_for_engine(sampled.rgb * emitted);
	ALPHA = exp(-4.0 * UV.x * UV.x) * smoothstep(0.0, 0.15, underside);
}

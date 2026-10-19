// FW-MOON-01 candidate B spike: a camera-centred moon quad on a far sphere (research only, not shipped).
// The disc maths copies sky.gdshader's moon(); cloud transmission copies the sky's legacy deck (density, horizon fade,
// cirrus) and the layered decks (as stars.gdshader does), evaluated per fragment from the shared include.
// Blend add: the sky shader also adds the disc (col += moon) before the clouds mix over it, so the transmitted part
// moon * (1 - density) is what B adds on top of the cloudy sky. Exact before the tonemap; Compatibility tonemaps each
// pass (glow off), so the sum is taken after the tonemap here: the parity test measures that difference.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled, skip_vertex_transform;
#include "res://render/cloud_field.gdshaderinc"
#include "res://render/world/engine_srgb.gdshaderinc"

uniform vec3 moon_dir = vec3(0.0, 0.42, -0.9);
uniform vec3 moon_lin = vec3(0.0);
uniform vec3 moon_sun_dir = vec3(0.0, 1.0, 0.0);
uniform float moon_radius = 0.0045379;
uniform float far_distance = 20000.0; // inside Camera.far (21000), so terrain and trees hide it by depth

// Mirrored sky uniforms (same names as sky.gdshader).
uniform float cloud_coverage = 0.35;
uniform float cloud_scale = 6.0;
uniform vec2 cloud_offset = vec2(0.0);
uniform uint cloud_seed = 1u;
uniform float cluster_strength = 0.0;
uniform float cirrus_strength = 0.0;
uniform float cirrus_coverage = 0.34;
uniform bool layered_appearance = false;
uniform int appearance_layer_count = 0;
uniform vec4 appearance_layer_parameters[8];
uniform vec4 appearance_layer_motion[8];
uniform int appearance_layer_seeds[8];
uniform float appearance_cloud_density = 1.0;

varying vec3 world_dir;

float layered_cloud_alpha(vec3 dir) {
	float total = 0.0;
	if (dir.y <= 0.0 || appearance_layer_count <= 0) {
		return total;
	}
	float horizon_fade = smoothstep(0.03, 0.25, dir.y);
	for (int order = 0; order < 8; order++) {
		int layer_index = appearance_layer_count - 1 - order;
		if (layer_index < 0) {
			break;
		}
		vec4 layer = appearance_layer_parameters[layer_index];
		vec4 layer_motion = appearance_layer_motion[layer_index];
		uint layer_seed = uint(max(appearance_layer_seeds[layer_index], 0));
		vec2 deck = (dir.xz / max(dir.y, 0.02)) * (layer.x / max(layer.y, 1.0));
		vec2 cells = mod(deck + layer_motion.xy, float(CLOUD_FIELD_PERIOD));
		int shape = int(floor(layer_motion.w + 0.5));
		float body;
		if (shape == 1) {
			body = cloud_stretched_density(cells, layer_seed, layer.z, vec2(3.0, 51.0) / 64.0);
		} else if (shape == 2) {
			body = cloud_stretched_density(cells, layer_seed, layer.z, vec2(7.0, 45.0) / 64.0);
		} else {
			body = cloud_density(cells, layer_seed, layer.z, layer_motion.z);
		}
		if (shape == 3) {
			float ceiling = smoothstep(0.02, 0.13, dir.y) * smoothstep(0.52, 0.94, layer.z);
			body = max(body, 0.90 * ceiling);
		}
		float optical = clamp(layer.w, 0.0, 1.0) * clamp(appearance_cloud_density, 0.0, 1.0);
		float layer_horizon_fade = shape == 3 ? smoothstep(0.005, 0.11, dir.y) : horizon_fade;
		float tower_height = shape == 4 ? mix(0.68, 1.0, smoothstep(0.025, 0.52, dir.y)) : 1.0;
		float alpha = clamp(body * optical * layer_horizon_fade * tower_height, 0.0, 0.98);
		total = 1.0 - (1.0 - total) * (1.0 - alpha);
	}
	return total;
}

// Fraction of the disc light that reaches the eye through the sky's clouds in direction `dir`.
float cloud_transmission(vec3 dir) {
	if (layered_appearance) {
		return 1.0 - layered_cloud_alpha(dir);
	}
	if (dir.y <= 0.0 || cloud_coverage <= 0.0) {
		return 1.0;
	}
	vec2 deck = dir.xz / max(dir.y, 0.02);
	vec2 cells = mod(deck * cloud_scale + cloud_offset, float(CLOUD_FIELD_PERIOD));
	float density = cloud_density(cells, cloud_seed, cloud_coverage, cluster_strength) * smoothstep(0.03, 0.25, dir.y);
	float cirrus_amount = 0.0;
	if (cirrus_strength > 0.0) {
		float cirrus = cloud_stretched_density(cells, cloud_seed + 15485863u, cirrus_coverage, vec2(3.0, 51.0) / 64.0)
			* smoothstep(0.02, 0.18, dir.y);
		cirrus_amount = clamp(cirrus * clamp(cirrus_strength, 0.0, 0.12), 0.0, 0.12);
	}
	return (1.0 - density) * (1.0 - cirrus_amount);
}

void vertex() {
	// QuadMesh of size 2: VERTEX.xy in [-1, 1] spans the disc plus the sky shader's 1.3x edge margin.
	vec3 d = normalize(moon_dir);
	vec3 up = abs(d.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 right = normalize(cross(up, d));
	vec3 v_up = cross(d, right);
	float half_size = tan(moon_radius * 1.3);
	world_dir = d + (right * VERTEX.x + v_up * VERTEX.y) * half_size;
	vec3 world = CAMERA_POSITION_WORLD + world_dir * far_distance;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec3 d = normalize(world_dir);
	float c = dot(d, moon_dir);
	vec3 col = vec3(0.0);
	if (c >= cos(moon_radius * 1.3) && dot(moon_lin, vec3(1.0)) > 0.0) {
		vec3 offset = (d - moon_dir * c) / sin(moon_radius);
		float r2 = dot(offset, offset);
		float edge = 1.0 - smoothstep(0.85, 1.0, sqrt(r2));
		vec3 normal = offset - moon_dir * sqrt(max(1.0 - r2, 0.0));
		float lit = smoothstep(-0.04, 0.04, dot(normal, moon_sun_dir));
		col = moon_lin * edge * (lit + 0.02) * cloud_transmission(d);
	}
	ALBEDO = encode_for_engine(col);
}

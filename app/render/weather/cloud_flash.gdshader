// FW-84 scene-local cloud illumination. This plane samples the same periodic density
// field as the sky using the same ray-to-deck projection; it never writes Sky uniforms.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled, world_vertex_coords;
#include "res://render/cloud_field.gdshaderinc"

uniform float cloud_altitude_m = 3900.0;
uniform float cloud_scale_m = 6000.0;
uniform vec2 cloud_offset = vec2(0.0);
uniform uint cloud_seed = 1u;
uniform float cloud_coverage = 0.94;
uniform float cloud_density_scale = 0.97;
uniform float cluster_strength = 0.65;
uniform vec3 flash_source = vec3(0.0, 3600.0, -9000.0);
uniform float flash_intensity = 0.0;
uniform float display_cap = 2.0;
uniform float albedo_display_cap = 0.75;
uniform float flash_radius_m = 4200.0;
uniform float flash_vertical_radius_m = 1350.0;
uniform vec3 flash_color = vec3(0.72, 0.84, 1.0);

varying vec3 world_position;

void vertex() {
	world_position = VERTEX;
}

void fragment() {
	vec3 ray = world_position - CAMERA_POSITION_WORLD;
	float ray_length = length(ray);
	vec3 ray_direction = ray / max(ray_length, 1e-3);
	if (ray_direction.y <= 0.0 || flash_intensity <= 0.001) {
		discard;
	}
	// Match sky.gdshader's cloud ray projection, including its absolute deck altitude.
	vec2 cells = mod((ray_direction.xz / max(ray_direction.y, 0.02))
		* (cloud_altitude_m / max(cloud_scale_m, 1.0)) + cloud_offset,
		float(CLOUD_FIELD_PERIOD));
	float cloud_mask = cloud_density(cells, cloud_seed, cloud_coverage, cluster_strength);
	cloud_mask *= clamp(cloud_density_scale, 0.0, 1.0);
	cloud_mask *= smoothstep(0.03, 0.25, ray_direction.y);
	vec2 horizontal_delta = world_position.xz - flash_source.xz;
	float horizontal_weight = exp(-dot(horizontal_delta, horizontal_delta)
		/ max(flash_radius_m * flash_radius_m, 1.0));
	float vertical_delta = (world_position.y - flash_source.y) / max(flash_vertical_radius_m, 1.0);
	float vertical_weight = exp(-vertical_delta * vertical_delta);
	float glow = clamp(flash_intensity, 0.0, 1.5) * cloud_mask
		* horizontal_weight * vertical_weight;
	if (glow <= 0.001) {
		discard;
	}
	// This unshaded local overlay is already capped in shader color space; dividing
	// again by scene exposure makes real-time night flashes disappear.
	ALBEDO = flash_color * min(1.0, albedo_display_cap);
	float output_gain = min(glow * 1.4, display_cap);
	EMISSION = flash_color * output_gain;
	ALPHA = clamp(glow * 0.68, 0.0, 0.78);
}

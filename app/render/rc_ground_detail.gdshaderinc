// L9d: downloaded CC0 surface detail, enabled only by the RC presentation.
// UVs are world X/Z metres. Translation-only decorrelation keeps normal orientation.
uniform bool rc_surface_enabled = false;
uniform bool rc_track_surface = false;
uniform sampler2D rc_dirt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rc_dirt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rc_dirt_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rc_grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rc_grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rc_grass_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
// Means of the pinned ambientCG Grass001 2K Color map (asset receipt).
const vec3 RC_GRASS_MEAN_LINEAR = vec3(0.0612683820, 0.1103692457, 0.0229264520);
const vec3 RC_GRASS_MEAN_SRGB = vec3(0.2672256236, 0.3588871535, 0.1582020114);
varying float rc_coverage;
varying float rc_soil_specular;

float rc_near_weight(vec2 gx, vec2 gy, float distance_m) {
	return (1.0 - smoothstep(28.0, 65.0, distance_m))
		* (1.0 - smoothstep(0.025, 0.12, max(length(gx), length(gy))));
}

// A projected OpenGL normal in a frame orthogonal to the actual bank normal.
// Image V increases toward world +Z, so the OpenGL +Y tangent points toward -Z.
vec3 rc_project_normal(vec3 base, vec3 map, mat4 view_matrix, float strength) {
	vec3 east = (view_matrix * vec4(1.0, 0.0, 0.0, 0.0)).xyz;
	vec3 tangent = normalize(east - base * dot(east, base));
	vec3 bitangent = normalize(cross(base, tangent));
	vec2 xy = (map.rg * 2.0 - 1.0) * strength;
	// hint_normal can use RG compression: reconstruct Z rather than read blue.
	return normalize(tangent * xy.x + bitangent * xy.y + base * sqrt(max(1.0 - dot(xy, xy), 0.01)));
}

// Same offsets/weights for every map; gradients are taken before offset selection.
void rc_uvs(vec2 p, float tile_size_m, out vec2 a, out vec2 b, out float blend) {
	vec2 uv = p / tile_size_m;
	float k = vnoise(p * 0.21 + 31.0) * 8.0;
	float cell = floor(k);
	a = uv + hash22(vec2(cell, 43.0));
	b = uv + hash22(vec2(cell + 1.0, 43.0));
	blend = smoothstep(0.15, 0.85, fract(k));
}

void rc_grass_sample(vec2 a, vec2 b, vec2 gx, vec2 gy, float blend,
		out vec3 color, out vec3 normal_map, out float roughness) {
	color = mix(textureGrad(rc_grass_albedo, a, gx, gy).rgb, textureGrad(rc_grass_albedo, b, gx, gy).rgb, blend);
	normal_map = mix(textureGrad(rc_grass_normal, a, gx, gy).rgb, textureGrad(rc_grass_normal, b, gx, gy).rgb, blend);
	roughness = mix(textureGrad(rc_grass_roughness, a, gx, gy).r, textureGrad(rc_grass_roughness, b, gx, gy).r, blend);
}

void rc_dirt_sample(vec2 a, vec2 b, vec2 gx, vec2 gy, float blend,
		out vec3 color, out vec3 normal_map, out float roughness) {
	color = mix(textureGrad(rc_dirt_albedo, a, gx, gy).rgb, textureGrad(rc_dirt_albedo, b, gx, gy).rgb, blend);
	normal_map = mix(textureGrad(rc_dirt_normal, a, gx, gy).rgb, textureGrad(rc_dirt_normal, b, gx, gy).rgb, blend);
	roughness = mix(textureGrad(rc_dirt_roughness, a, gx, gy).r, textureGrad(rc_dirt_roughness, b, gx, gy).r, blend);
}

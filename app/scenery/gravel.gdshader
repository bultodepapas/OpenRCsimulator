// LU-12. Original MIT procedural aggregate, in metres. No textures or wall clock.
// MeshKit's sRGB vertex colours arrive linear in Compatibility, as in motion.gdshader.
// Alpha is a material mask only: this shader never writes ALPHA and remains opaque.
shader_type spatial;
render_mode cull_back;

uniform float detail_strength : hint_range(0.0, 1.0) = 1.0;
varying vec3 ground_color;
varying vec2 ground_position;
varying float aggregate_mask;

// Reuse the project's integer cloud hash: stable across large/negative world coordinates.
#include "res://render/cloud_field.gdshaderinc"

float lattice(vec2 p) {
	return cloud_field_hash2(ivec2(p), 8137u);
}

float grain(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(lattice(cell), lattice(cell + vec2(1.0, 0.0)), f.x),
		mix(lattice(cell + vec2(0.0, 1.0)), lattice(cell + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	ground_color = COLOR.rgb;
	ground_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	aggregate_mask = clamp((1.0 - COLOR.a) * 2.0, 0.0, 1.0);
}

void fragment() {
	vec2 p = ground_position;
	// Fade before a stone is subpixel. Automatic fragment derivatives work in GLES3.
	float footprint = max(length(dFdx(p)), length(dFdy(p)));
	float fine_filter = 1.0 - smoothstep(0.012, 0.05, footprint);
	float broad_filter = 1.0 - smoothstep(0.06, 0.22, footprint);
	float amount = aggregate_mask * detail_strength;
	float fine = grain(p * 23.0) - 0.5;
	float broad = grain(p * mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * 6.0) - 0.5;
	float variation = amount * (0.32 * fine * fine_filter + 0.12 * broad * broad_filter);
	ALBEDO = ground_color * (1.0 + variation);
	ROUGHNESS = 0.88;
	SPECULAR = 0.3;
	// A submillimetre bump conveys grain without moving the actual ground plane.
	float height = amount * 0.0006 * fine;
	vec3 dx = dFdx(VERTEX);
	vec3 dy = dFdy(VERTEX);
	vec3 rx = cross(dy, NORMAL);
	vec3 ry = cross(NORMAL, dx);
	float determinant = dot(dx, rx);
	// Differentiate only the spatial signal; applying the footprint afterwards avoids
	// undefined higher-order derivatives of fine_filter.
	float hx = dFdx(height) * fine_filter;
	float hy = dFdy(height) * fine_filter;
	if (abs(determinant) > 0.00000001) {
		NORMAL = normalize(abs(determinant) * NORMAL - sign(determinant) * (hx * rx + hy * ry));
	}
}

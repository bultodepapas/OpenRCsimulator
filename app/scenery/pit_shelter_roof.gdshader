// Shared opaque material for the merged open pit shelter surface.
// MeshKit vertex tags select photographed corrugated steel (magenta/cyan) and
// timber (red=X, green=Z, blue=Y, orange/azure=diagonal grain), and slab (yellow).
// Other geometry keeps its
// vertex colour, matching scenery.opaque_material() in Compatibility rendering.
shader_type spatial;
render_mode cull_back;

#include "res://scenery/vertex_color_linear.gdshaderinc"

uniform sampler2D roof_albedo : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D roof_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D roof_arm : repeat_enable, filter_linear_mipmap_anisotropic;

// Existing CC0 ambientCG Wood049 maps in assets/landscape/flightline/.
uniform sampler2D wood_albedo : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
// No hint_normal here: preserve all three source channels from the shared
// lossless Wood049 import for this custom tangent-frame shader.
uniform sampler2D wood_normal : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D wood_roughness : repeat_enable, filter_linear_mipmap_anisotropic;

// Reuse the CC0 ambientCG Concrete034 maps already installed for pilot stations.
uniform sampler2D slab_albedo : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D slab_normal : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D slab_roughness : repeat_enable, filter_linear_mipmap_anisotropic;

// Corrugated Iron 02 is 2.7 m wide. Its photographed ridges run along image V,
// roughly 0.25 m apart across U. Map U across local X and V down the local-Z slope.
uniform vec2 roof_tile_size_m = vec2(2.7, 2.7);
uniform float roof_normal_strength : hint_range(0.0, 1.0) = 0.72;
uniform float roof_weathering_strength : hint_range(0.0, 1.0) = 0.72;
uniform float roof_clean_roughness : hint_range(0.0, 1.0) = 0.42;
uniform float roof_clean_metallic : hint_range(0.0, 1.0) = 0.78;
uniform float roof_underside_roughness_add : hint_range(0.0, 0.5) = 0.12;
uniform float roof_underside_metallic = 0.62;
uniform vec4 roof_clean_sheet_tint : source_color = vec4(0.64, 0.66, 0.68, 1.0);
uniform vec4 roof_top_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 roof_underside_tint : source_color = vec4(0.84, 0.86, 0.88, 1.0);

// Wood049 is a 0.8 m square tile. Its grain runs along image U, which maps up
// local Y on post sides; image V crosses the face. Top caps use local X/Z.
uniform vec2 wood_tile_size_m = vec2(0.8, 0.8);
uniform float wood_normal_strength : hint_range(0.0, 1.0) = 0.35;
uniform float wood_weathering_strength : hint_range(0.0, 1.0) = 0.24;
uniform float wood_weathered_roughness = 0.80;
uniform vec3 wood_weathering_tint : source_color = vec3(0.91, 0.90, 0.85);

// Concrete034's physical tile is 1.1 by 0.55 m. Low relief suits a level
// trowelled slab; its downloaded color and roughness supply fine variation.
uniform vec2 slab_tile_size_m = vec2(1.1, 0.55);
uniform float slab_normal_strength : hint_range(0.0, 1.0) = 0.32;
uniform vec3 slab_tint : source_color = vec3(0.88, 0.86, 0.82);

varying vec2 roof_uv_local;
varying vec2 wood_uv_local;
varying float roof_surface_tag;
varying float roof_top_facing;
varying float wood_surface_tag;
varying float wood_grain_axis;
varying float wood_seed;
varying vec2 slab_uv_local;
varying float slab_surface_tag;

void vertex() {
	// Material tags and tone seeds are raw packed metadata in both renderers.
	// Color transfer functions would change grain offsets and per-piece variation.
	vec3 mesh_color = COLOR.rgb;
	// Exact magenta top faces (1,0,1) and cyan underside faces (0,1,1).
	bool roof_top_tag = mesh_color.r == 1.0 && mesh_color.g == 0.0 && mesh_color.b == 1.0;
	bool roof_under_tag = mesh_color.r == 0.0 && mesh_color.g == 1.0 && mesh_color.b == 1.0;
	bool slab_tag = mesh_color.r == 1.0 && mesh_color.g == 1.0 && mesh_color.b == 0.0;
	// Timber tags: red (tone,0,0) means X grain, green (0,tone,0) means Z,
	// and blue (0,0,tone) means Y. The threshold separates these markers from
	// ordinary tints; it is not a color-space conversion boundary.
	bool wood_x_tag = mesh_color.r >= 0.45 && mesh_color.g < 0.02 && mesh_color.b < 0.02;
	bool wood_z_tag = mesh_color.r < 0.02 && mesh_color.g >= 0.45 && mesh_color.b < 0.02;
	bool wood_y_tag = mesh_color.r < 0.02 && mesh_color.g < 0.02 && mesh_color.b >= 0.45;
	// Pure red/blue endpoints keep the two diagonal markers distinct from
	// ordinary prop colours, roof markers, and the yellow concrete slab.
	bool wood_diag_pos_tag = mesh_color.r == 1.0 && mesh_color.b == 0.0 && mesh_color.g > 0.15 && mesh_color.g < 0.6;
	bool wood_diag_neg_tag = mesh_color.r == 0.0 && mesh_color.b == 1.0 && mesh_color.g > 0.15 && mesh_color.g < 0.6;
	bool wood_tag = wood_x_tag || wood_z_tag || wood_y_tag || wood_diag_pos_tag || wood_diag_neg_tag;

	roof_surface_tag = float(roof_top_tag || roof_under_tag);
	wood_surface_tag = float(wood_tag);
	slab_surface_tag = float(slab_tag);
	wood_grain_axis = 0.0;
	if (wood_z_tag) {
		wood_grain_axis = 1.0;
	} else if (wood_y_tag) {
		wood_grain_axis = 2.0;
	} else if (wood_diag_pos_tag) {
		wood_grain_axis = 3.0;
	} else if (wood_diag_neg_tag) {
		wood_grain_axis = 4.0;
	}
	float wood_tone = max(mesh_color.r, max(mesh_color.g, mesh_color.b));
	wood_seed = clamp((wood_tone - 0.5) * 2.0, 0.0, 1.0);

	// Face normals decide which finish is visible, while vertex markers restrict
	// PBR sampling to the intended roof sheets and timber parts.
	roof_top_facing = smoothstep(-0.08, 0.22, normalize(NORMAL).y);
	roof_uv_local = VERTEX.xz / max(roof_tile_size_m, vec2(0.001));
	slab_uv_local = VERTEX.xz / max(slab_tile_size_m, vec2(0.001));

	// Project the tagged axis onto each face so grain stays lengthwise on posts,
	// beams, rafters, purlins, and braces with no mesh UVs.
	vec3 grain_axis = vec3(0.0, 1.0, 0.0);
	if (wood_grain_axis < 0.5) {
		grain_axis = vec3(1.0, 0.0, 0.0);
	} else if (wood_grain_axis < 1.5) {
		grain_axis = vec3(0.0, 0.0, 1.0);
	} else if (wood_grain_axis > 2.5 && wood_grain_axis < 3.5) {
		grain_axis = normalize(vec3(0.5, 0.65, 0.0));
	} else if (wood_grain_axis > 3.5) {
		grain_axis = normalize(vec3(-0.5, 0.65, 0.0));
	}
	vec3 n = normalize(NORMAL);
	vec3 projected_grain = grain_axis - n * dot(grain_axis, n);
	if (length(projected_grain) < 0.001) {
		vec3 fallback_axis = abs(grain_axis.y) > 0.5 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
		projected_grain = fallback_axis - n * dot(fallback_axis, n);
	}
	vec3 wood_u_axis = normalize(projected_grain);
	vec3 wood_v_axis = normalize(cross(n, wood_u_axis));
	wood_uv_local = vec2(dot(VERTEX, wood_u_axis), dot(VERTEX, wood_v_axis))
		/ max(wood_tile_size_m, vec2(0.001));
	// The encoded tone gives adjacent wood pieces slight UV and albedo variation.
	wood_uv_local += vec2((wood_seed - 0.5) * 0.16, (wood_seed - 0.5) * 0.08);
}

vec3 normal_from_uv(vec3 base_normal, vec2 uv_dx, vec2 uv_dy,
		vec3 position_dx, vec3 position_dy, vec3 sampled_normal, float strength) {
	float determinant = uv_dx.x * uv_dy.y - uv_dx.y * uv_dy.x;
	if (abs(determinant) < 0.000001) {
		return base_normal;
	}
	vec3 tangent = (position_dx * uv_dy.y - position_dy * uv_dx.y) / determinant;
	vec3 bitangent = (position_dy * uv_dx.x - position_dx * uv_dy.x) / determinant;
	tangent = normalize(tangent - base_normal * dot(base_normal, tangent));
	bitangent = normalize(bitangent - base_normal * dot(base_normal, bitangent)
		- tangent * dot(tangent, bitangent));
	vec3 tangent_normal = sampled_normal * 2.0 - 1.0;
	tangent_normal.xy *= strength;
	tangent_normal = normalize(tangent_normal);
	return normalize(tangent * tangent_normal.x + bitangent * tangent_normal.y
		+ base_normal * tangent_normal.z);
}

void fragment() {
	// Untagged scenery keeps its MeshKit palette color in linear space.
	ALBEDO = vertex_color_to_linear(COLOR.rgb);
	ROUGHNESS = 0.88;
	METALLIC = 0.0;
	SPECULAR = 0.3;
	AO = 1.0;

	// Evaluate derivatives before the per-tag branches so they remain defined for
	// every fragment. Both tangent frames follow their planar local projections.
	vec3 position_dx = dFdx(VERTEX);
	vec3 position_dy = dFdy(VERTEX);
	vec2 roof_uv_dx = dFdx(roof_uv_local);
	vec2 roof_uv_dy = dFdy(roof_uv_local);
	vec2 wood_uv_dx = dFdx(wood_uv_local);
	vec2 wood_uv_dy = dFdy(wood_uv_local);
	vec2 slab_uv_dx = dFdx(slab_uv_local);
	vec2 slab_uv_dy = dFdy(slab_uv_local);
	vec3 base_normal = normalize(NORMAL);

	if (roof_surface_tag > 0.5) {
		vec3 photo_color = texture(roof_albedo, roof_uv_local).rgb;
		vec3 arm = texture(roof_arm, roof_uv_local).rgb;
		float weather = clamp(roof_weathering_strength, 0.0, 1.0);
		float top_mask = roof_top_facing;
		float underside = 1.0 - top_mask;
		vec3 side_tint = mix(roof_underside_tint.rgb, roof_top_tint.rgb, top_mask);
		vec3 surface_color = mix(roof_clean_sheet_tint.rgb, photo_color, weather);
		ALBEDO = surface_color * side_tint;
		ROUGHNESS = clamp(mix(roof_clean_roughness, arm.g, weather)
			+ roof_underside_roughness_add * underside, 0.0, 1.0);
		METALLIC = clamp(mix(mix(roof_clean_metallic, arm.b, weather),
			roof_underside_metallic, underside), 0.0, 1.0);
		AO = mix(1.0, arm.r, weather);
		NORMAL = normal_from_uv(base_normal, roof_uv_dx, roof_uv_dy,
			position_dx, position_dy, texture(roof_normal, roof_uv_local).rgb,
			roof_normal_strength);
	} else if (wood_surface_tag > 0.5) {
		vec3 photo_color = texture(wood_albedo, wood_uv_local).rgb;
		vec3 roughness_sample = texture(wood_roughness, wood_uv_local).rgb;
		float weather = clamp(wood_weathering_strength, 0.0, 1.0);
		float seed_tone = mix(0.97, 1.03, wood_seed);
		ALBEDO = photo_color * mix(vec3(1.0), wood_weathering_tint, weather) * seed_tone;
		ROUGHNESS = clamp(mix(roughness_sample.r,
			max(roughness_sample.r, wood_weathered_roughness), weather), 0.0, 1.0);
		METALLIC = 0.0;
		SPECULAR = 0.3;
		AO = 1.0;
		NORMAL = normal_from_uv(base_normal, wood_uv_dx, wood_uv_dy,
			position_dx, position_dy, texture(wood_normal, wood_uv_local).rgb,
			wood_normal_strength);
	} else if (slab_surface_tag > 0.5) {
		ALBEDO = texture(slab_albedo, slab_uv_local).rgb * slab_tint;
		ROUGHNESS = texture(slab_roughness, slab_uv_local).r;
		METALLIC = 0.0;
		SPECULAR = 0.3;
		NORMAL = normal_from_uv(base_normal, slab_uv_dx, slab_uv_dy,
			position_dx, position_dy, texture(slab_normal, slab_uv_local).rgb,
			slab_normal_strength);
	}
	// No ALPHA assignment: roof, timber, and retained vertex-colour geometry stay opaque.
}

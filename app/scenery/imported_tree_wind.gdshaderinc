// L15b-R2: wind for downloaded close trees. The material terms mirror Godot 4.7.2's
// StandardMaterial3D generator (scene/resources/material.cpp) for the features that
// ImportedVegetation._tree_material_support_reason() accepts, so calm wind keeps the
// source appearance. Variant files set the cull mode and define TREE_WIND_CLAMP for
// non-repeating textures before including this file.
#include "res://render/tree_wind.gdshaderinc"

global uniform float sim_clock;
global uniform vec3 wind_vec;

#ifdef TREE_WIND_CLAMP
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_disable;
uniform sampler2D metallic_texture : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform sampler2D roughness_texture : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform sampler2D ao_texture : hint_default_white, filter_linear_mipmap, repeat_disable;
#else
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D metallic_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D roughness_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D ao_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
#endif
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_albedo_texture = false;
uniform vec2 uv1_scale = vec2(1.0);
uniform vec2 uv1_offset = vec2(0.0);
uniform bool use_vertex_color = false;
uniform bool vertex_color_is_srgb = false;
uniform bool use_normal_texture = false;
uniform float normal_scale = 1.0;
uniform float metallic = 0.0;
uniform bool use_metallic_texture = false;
uniform vec4 metallic_texture_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform float roughness = 1.0;
uniform bool use_roughness_texture = false;
uniform vec4 roughness_texture_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform float specular = 0.5;
uniform bool use_ao = false;
uniform bool use_ao_texture = false;
uniform vec4 ao_texture_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform float ao_light_affect = 0.0;
uniform bool use_alpha_scissor = false;
uniform float alpha_scissor_threshold = 0.5;
// L6c-R1: highest mip for the foliage alpha test; the default never clamps (StandardMaterial3D parity).
uniform float alpha_scissor_max_mip = 1000.0;
// Source-mesh bend frame (local units) and the per-asset crown-top limit in metres.
uniform float plant_height = 1.0;
uniform float plant_base_y = 0.0;
uniform float tree_lean_limit_m = 0.0;
// Foliage-only shading flutter: normal tilt, no displacement (no collision effect).
uniform float leaf_flutter_tilt = 0.0;

// Crown-top displacement in metres: tree_bend()'s speed-squared saturation,
// 0.20–0.50 Hz height law and 0.75–1.0 sway cycle, with a bounded amplitude.
float close_tree_top_sway_m(float speed_squared, float height_m, float phase_offset, float clock, float limit_m) {
	float height_weight = clamp((height_m - 12.0) / 13.0, 0.0, 1.0);
	float cycles = round(mix(512.0, 205.0, height_weight));
	float phase = fract(clock * (cycles / 1024.0) + phase_offset);
	float sway = 0.75 + 0.25 * sin(6.28318530718 * phase);
	return min(limit_m, TREE_WIND_LEAN_M) * min(speed_squared / 100.0, 1.0) * sway;
}

void vertex() {
	if (use_vertex_color && vertex_color_is_srgb) {
		if (!OUTPUT_IS_SRGB) {
			COLOR.rgb = mix(
					pow((COLOR.rgb + vec3(0.055)) * (1.0 / (1.0 + 0.055)), vec3(2.4)),
					COLOR.rgb * (1.0 / 12.92),
					lessThan(COLOR.rgb, vec3(0.04045)));
		}
	}
	UV = UV * uv1_scale + uv1_offset;
	// Branch-free: every wind term is exactly zero in calm air or for a static asset, so
	// calm rendering keeps the source material's compiled geometry path bit for bit.
	float speed_squared = dot(wind_vec.xz, wind_vec.xz);
	// Placement transforms are upright with uniform scale (guarded on the CPU).
	float scale = length(MODEL_MATRIX[1].xyz);
	vec3 local_wind = transpose(mat3(MODEL_MATRIX)) * vec3(wind_vec.x, 0.0, wind_vec.z);
	vec2 direction = local_wind.xz / max(length(local_wind.xz), 0.000001);
	float top_sway = close_tree_top_sway_m(
			speed_squared, plant_height * scale, INSTANCE_CUSTOM.r, sim_clock, tree_lean_limit_m) / scale;
	float raw_height = (VERTEX.y - plant_base_y) / max(plant_height, 0.001);
	float normalized_height = clamp(raw_height, 0.0, 1.0);
	// Horizontal quadratic bend: the root stays fixed and no vertex rises.
	VERTEX.xz += direction * (top_sway * normalized_height * normalized_height);
	// F(p) = p + (direction.x, 0, direction.y) * sway(y). Add the inverse-transpose Jacobian
	// term to normals and the Jacobian term to the tangent frame (unnormalized, as MikkTSpace
	// expects); the shear stays below 1.5 degrees at the measured limits.
	float sway_gradient_y = raw_height > 0.0 && raw_height < 1.0
			? 2.0 * top_sway * normalized_height / max(plant_height, 0.001) : 0.0;
	vec3 shear = vec3(direction.x, 0.0, direction.y) * sway_gradient_y;
	NORMAL.y -= dot(shear, NORMAL);
	TANGENT += shear * TANGENT.y;
	BINORMAL += shear * BINORMAL.y;
	// Leaves catch the light differently as they flutter (1.2 and 1.7 Hz, integer cycles
	// per 1024 s clock wrap); phases vary over about 3 m within a crown. Shading only.
	vec3 crown_m = VERTEX * scale;
	float flutter = leaf_flutter_tilt * min(sqrt(speed_squared) / 8.0, 1.0);
	float phase_a = fract(sim_clock * (1229.0 / 1024.0) + dot(crown_m, vec3(0.23, 0.11, 0.31)) + INSTANCE_CUSTOM.r);
	float phase_b = fract(sim_clock * (1741.0 / 1024.0) + dot(crown_m, vec3(-0.29, 0.17, 0.19)) + INSTANCE_CUSTOM.r);
	NORMAL.xz += flutter * vec2(sin(6.28318530718 * phase_a), sin(6.28318530718 * phase_b));
}

void fragment() {
	vec2 base_uv = UV;
	vec4 albedo_tex = use_albedo_texture ? texture(albedo_texture, base_uv) : vec4(1.0);
	float alpha_tex = albedo_tex.a;
	if (use_alpha_scissor && use_albedo_texture && alpha_scissor_max_mip < 1000.0) {
		vec2 texel = base_uv * vec2(textureSize(albedo_texture, 0));
		vec2 texel_dx = dFdx(texel);
		vec2 texel_dy = dFdy(texel);
		float mip = 0.5 * log2(max(max(dot(texel_dx, texel_dx), dot(texel_dy, texel_dy)), 1.0));
		if (mip > alpha_scissor_max_mip) {
			// Small distant leaf cards sample mips whose averaged alpha falls under the cutoff, so
			// crowns turn bare. Stay on the last mip that keeps the atlas coverage; its colour keeps
			// the near tone (un-premultiplying the black transparent texels would brighten it).
			albedo_tex = textureLod(albedo_texture, base_uv, alpha_scissor_max_mip);
			alpha_tex = albedo_tex.a;
		}
	}
	if (use_vertex_color) {
		albedo_tex *= COLOR;
		alpha_tex *= COLOR.a;
	}
	ALBEDO = albedo_color.rgb * albedo_tex.rgb;
	float metallic_tex = use_metallic_texture ? dot(texture(metallic_texture, base_uv), metallic_texture_channel) : 1.0;
	METALLIC = metallic_tex * metallic;
	SPECULAR = specular;
	float roughness_tex = use_roughness_texture ? dot(texture(roughness_texture, base_uv), roughness_texture_channel) : 1.0;
	ROUGHNESS = roughness_tex * roughness;
	if (use_normal_texture) {
		NORMAL_MAP = texture(normal_texture, base_uv).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
	if (use_alpha_scissor && albedo_color.a * alpha_tex < alpha_scissor_threshold) {
		discard;
	}
	if (use_ao) {
		AO = use_ao_texture ? dot(texture(ao_texture, base_uv), ao_texture_channel) : 1.0;
		AO_LIGHT_AFFECT = ao_light_affect;
	}
}

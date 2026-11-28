shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_map : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D arm_map : repeat_enable, filter_linear_mipmap_anisotropic;
uniform vec3 tint : source_color = vec3(1.0);
uniform float normal_strength : hint_range(0.0, 1.0) = 0.65;
uniform float metallic_scale : hint_range(0.0, 1.0) = 0.0;
uniform float roughness_floor : hint_range(0.0, 1.0) = 0.65;

void fragment() {
	vec3 base_normal = normalize(NORMAL);
	vec3 position_dx = dFdx(VERTEX);
	vec3 position_dy = dFdy(VERTEX);
	vec2 uv_dx = dFdx(UV);
	vec2 uv_dy = dFdy(UV);
	float determinant = uv_dx.x * uv_dy.y - uv_dx.y * uv_dy.x;
	float uv_scale_sq = max(dot(uv_dx, uv_dx), dot(uv_dy, uv_dy));
	vec3 mapped_normal = base_normal;
	// A close-up shrinks both UV derivatives without making their frame singular.
	if (abs(determinant) > 1e-6 * uv_scale_sq) {
		vec3 tangent = (position_dx * uv_dy.y - position_dy * uv_dx.y) / determinant;
		vec3 bitangent = (position_dy * uv_dx.x - position_dx * uv_dy.x) / determinant;
		vec3 perpendicular = cross(base_normal, tangent);
		float signed_area = dot(perpendicular, bitangent);
		// A zero projected axis cannot define a normal map. The area sign preserves mirrored UVs.
		if (signed_area * signed_area > 1e-12 * dot(tangent, tangent) * dot(bitangent, bitangent)) {
			perpendicular = normalize(perpendicular);
			tangent = cross(perpendicular, base_normal);
			bitangent = sign(signed_area) * perpendicular;
			vec3 sampled = textureGrad(normal_map, UV, uv_dx, uv_dy).rgb * 2.0 - 1.0;
			sampled.xy *= normal_strength;
			mapped_normal = normalize(tangent * sampled.x + bitangent * sampled.y
				+ base_normal * sampled.z);
		}
	}
	vec3 arm = texture(arm_map, UV).rgb;
	ALBEDO = texture(albedo_map, UV).rgb * tint;
	NORMAL = mapped_normal;
	AO = arm.r;
	ROUGHNESS = clamp(arm.g, roughness_floor, 1.0);
	METALLIC = arm.b * metallic_scale;
	SPECULAR = 0.35;
}

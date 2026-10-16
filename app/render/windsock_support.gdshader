shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D metal_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metal_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
varying float concrete;
varying float base_height;
void vertex() {
	concrete = COLOR.b > 0.9 && COLOR.r < 0.1 ? 1.0 : 0.0;
	base_height = VERTEX.y;
	vec3 axis = abs(NORMAL.y) < 0.9 ? vec3(0,1,0) : vec3(1,0,0);
	TANGENT = normalize(axis - NORMAL * dot(axis, NORMAL));
	BINORMAL = normalize(cross(NORMAL, TANGENT));
	UV = vec2(dot(VERTEX, TANGENT), dot(VERTEX, BINORMAL)) / 0.3;
}
void fragment() {
	float dirt = (1.0 - smoothstep(0.01, 0.08, base_height)) * 0.18;
	vec3 steel = COLOR.rgb * 0.65;
	vec3 pad = texture(concrete_color, UV * vec2(0.3 / 1.1, 0.3 / 0.55)).rgb * 0.67;
	ALBEDO = mix(steel, pad, concrete) * (1.0 - dirt);
	METALLIC = (1.0 - concrete) * 0.65;
	ROUGHNESS = mix(0.40 + texture(metal_roughness, UV).r * 0.25, 0.92, concrete);
	NORMAL_MAP = mix(texture(metal_normal, UV).rgb, texture(concrete_normal, UV * vec2(0.3 / 1.1, 0.3 / 0.55)).rgb, concrete);
	NORMAL_MAP_DEPTH = 0.18;
}

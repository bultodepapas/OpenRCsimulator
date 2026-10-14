// FW-83 cloud impostors; unchanged CC0 cloud images by WickedInsignia.
// Distinct world centres provide parallax. Only each small lobe faces the camera.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, skip_vertex_transform;
uniform sampler2D cloud_texture : filter_linear_mipmap, repeat_disable;
uniform vec3 cloud_color = vec3(0.8);
uniform vec3 haze_color = vec3(0.6, 0.7, 0.8);
uniform float haze_density = 0.00005;
uniform float bank_base = 1450.0;
uniform float bank_top = 6200.0;
varying vec3 world_position;

void vertex() {
	vec2 facing = CAMERA_POSITION_WORLD.xz - MODEL_MATRIX[3].xz;
	vec3 right = length(facing) > 0.001 ? normalize(vec3(facing.y, 0.0, -facing.x)) : vec3(1.0, 0.0, 0.0);
	world_position = MODEL_MATRIX[3].xyz + right * VERTEX.x + vec3(0.0, VERTEX.y, 0.0);
	VERTEX = (VIEW_MATRIX * vec4(world_position, 1.0)).xyz;
}

void fragment() {
	vec4 shape = texture(cloud_texture, UV);
	float opacity = min(shape.a * 1.45, 0.98);
	if (opacity < 0.008) { discard; }
	float height = clamp((world_position.y - bank_base) / (bank_top - bank_base), 0.0, 1.0);
	float relief = smoothstep(0.015, 0.46, dot(shape.rgb, vec3(0.3333)));
	float shade = mix(0.20, 0.95, relief) * mix(0.44, 1.12, smoothstep(0.05, 0.85, height));
	vec3 color = cloud_color * shade;
	float transmission = exp(-length(CAMERA_POSITION_WORLD - world_position) * haze_density);
	ALBEDO = mix(haze_color, color, transmission);
	ALPHA = opacity;
}

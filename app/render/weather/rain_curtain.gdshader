// FW-83 distant rain veil, using the same downloaded CC0 alpha as the cloud fragments.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, world_vertex_coords;
uniform sampler2D cloud_texture : filter_linear_mipmap, repeat_disable;
uniform vec3 rain_color = vec3(0.13, 0.15, 0.18);
uniform vec3 haze_color = vec3(0.6, 0.7, 0.8);
uniform float haze_density = 0.00005;
uniform float opacity = 0.5;
varying vec3 world_position;
void vertex() { world_position = VERTEX; }
void fragment() {
	// Broad rain shafts have irregular edges, taper into the cloud base, and fade at ground level.
	float shaft = texture(cloud_texture, vec2(UV.x, 0.48 + UV.y * 0.12)).a;
	float fine = texture(cloud_texture, vec2(fract(UV.x * 3.0), 0.46)).a;
	float edge = smoothstep(0.0, 0.12, UV.x) * smoothstep(0.0, 0.12, 1.0 - UV.x);
	float vertical = smoothstep(0.0, 0.15, UV.y) * smoothstep(0.0, 0.20, 1.0 - UV.y);
	float alpha = (0.24 + shaft * 0.55 + fine * 0.21) * edge * vertical * opacity;
	float transmission = exp(-length(CAMERA_POSITION_WORLD - world_position) * haze_density);
	ALBEDO = mix(haze_color, rain_color, transmission);
	ALPHA = alpha;
}

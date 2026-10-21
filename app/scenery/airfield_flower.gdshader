// Poly Haven's 1K glTF carries a JPEG diffuse and a separate Alpha map.
// Bind both source maps so the scanned petals cut out cleanly in Godot.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D diffuse_map : source_color, filter_linear_mipmap;
uniform sampler2D alpha_map : filter_linear_mipmap;

void fragment() {
	ALBEDO = texture(diffuse_map, UV).rgb;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
	ALPHA = texture(alpha_map, UV).r;
	ALPHA_SCISSOR_THRESHOLD = 0.38;
}

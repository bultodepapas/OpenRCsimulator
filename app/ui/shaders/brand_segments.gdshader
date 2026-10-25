shader_type canvas_item;
render_mode unshaded;

uniform float clock = 0.0;
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 ink = texture(TEXTURE, UV);
	vec2 texel = TEXTURE_PIXEL_SIZE * 2.0;
	float surrounding = max(max(texture(TEXTURE, UV + vec2(texel.x, 0.0)).a,
		texture(TEXTURE, UV - vec2(texel.x, 0.0)).a),
		max(texture(TEXTURE, UV + vec2(0.0, texel.y)).a,
		texture(TEXTURE, UV - vec2(0.0, texel.y)).a));
	float edge = max(0.0, surrounding - ink.a);
	vec2 halo_texel = texel * 3.5;
	float halo = (texture(TEXTURE, UV + vec2(halo_texel.x, 0.0)).a
		+ texture(TEXTURE, UV - vec2(halo_texel.x, 0.0)).a
		+ texture(TEXTURE, UV + vec2(0.0, halo_texel.y)).a
		+ texture(TEXTURE, UV - vec2(0.0, halo_texel.y)).a) * 0.25;
	float solid = smoothstep(1.05, 2.5, clock);
	float sweep_position = mix(-0.2, 1.4, clamp((clock - 2.4) / 1.6, 0.0, 1.0));
	float sweep = exp(-pow((SCREEN_UV.x + SCREEN_UV.y * 0.14 - sweep_position) * 34.0, 2.0));
	vec3 blue = vec3(0.12, 0.72, 0.95);
	vec3 base = mix(blue * 0.5, ink.rgb, solid);
	base += sweep * vec3(0.45, 0.7, 0.8) * solid;
	float opacity = ink.a * mix(0.09, 1.0, solid);
	float glow = max(0.0, halo - ink.a) * (0.22 * (1.0 - solid) + sweep * 0.32);
	COLOR = vec4(mix(base, blue, max(edge, step(0.001, glow))),
		max(max(opacity, edge * (1.0 - solid)), glow) * tint.a);
}

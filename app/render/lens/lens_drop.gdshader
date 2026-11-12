// LENS-08 (docs/plans/lens-screen-effects.md §6.5). Ours, MIT. One water drop on the lens, drawn as one instance of a
// unit quad in a MultiMeshInstance2D (cost follows the screen area the drops cover, not a loop over all drops per
// pixel). The quad is stretched along the drop's motion: a round head in front, a tapering tail behind.
// Optics of a drop on glass: a small ball lens. The scene inside it appears inverted and minified, out of focus by the
// lens's own depth of field; total internal reflection darkens the rim; a sharp highlight catches the sky.
// Custom data: x elongation, y opacity, z seed, w radius in pixels. No TIME: the pool animates on the CPU.
shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float focus_lod = 1.5;          // blur of the scene seen through the drop (defocus)
uniform float magnification = 2.6;      // > 1: the image inside is minified; the minus sign below inverts it
uniform float rim_darkening = 0.55;
uniform float highlight = 0.65;
uniform float flash = 0.0;              // FW-84 lightning radiance reaching the lens, 0…1
uniform float opacity = 1.0;

varying vec4 drop;
varying vec2 local;
varying vec2 axis_x;

float sd_uneven_capsule(vec2 p, float r1, float r2, float h) {
	// Inigo Quilez's 2D uneven capsule (MIT): base circle r1 at the origin, top circle r2 at (0, h).
	p.x = abs(p.x);
	float b = (r1 - r2) / h;
	float a = sqrt(max(1.0 - b * b, 0.0));
	float k = dot(p, vec2(-b, a));
	if (k < 0.0) return length(p) - r1;
	if (k > a * h) return length(p - vec2(0.0, h)) - r2;
	return dot(p, vec2(a, b)) - r1;
}

// Distance in drop radii; the head (radius 1) sits at x = e, the tail tapers back along −x.
float drop_sdf(vec2 q, float e) {
	float head = length(q - vec2(e, 0.0)) - 1.0;
	if (e < 0.08) return head;
	float tail_r = 0.38;
	float tail_x = -(1.0 + e) + tail_r;
	float body = sd_uneven_capsule(vec2(q.y, q.x - tail_x), tail_r, 1.0, e - tail_x);
	return min(head, body);
}

void vertex() {
	drop = INSTANCE_CUSTOM;
	local = VERTEX;
	axis_x = normalize(MODEL_MATRIX[0].xy);
}

void fragment() {
	float e = drop.x;
	float radius_px = max(drop.w, 1.0);
	vec2 q = vec2(local.x * 2.0 * (1.0 + e), local.y * 2.0);
	float d = drop_sdf(q, e);
	float edge_px = 1.0 / radius_px;
	float coverage = 1.0 - smoothstep(-edge_px, edge_px, d);
	if (coverage <= 0.0) {
		discard;
	}
	// Spherical-cap height and the outward direction (numerical gradient of the distance).
	float rel = clamp(1.0 + d, 0.0, 1.0);
	float height = sqrt(max(1.0 - rel * rel, 0.0));
	const float eps = 0.03;
	vec2 grad = vec2(drop_sdf(q + vec2(eps, 0.0), e) - drop_sdf(q - vec2(eps, 0.0), e),
		drop_sdf(q + vec2(0.0, eps), e) - drop_sdf(q - vec2(0.0, eps), e));
	vec2 outward = length(grad) > 1e-5 ? normalize(grad) : vec2(0.0);

	// Screen-space offset of this fragment from the head's centre (canvas pixels are viewport pixels here).
	vec2 axis_y = vec2(-axis_x.y, axis_x.x);
	vec2 offset_local = (q - vec2(e, 0.0)) * radius_px;
	vec2 offset_uv = (axis_x * offset_local.x + axis_y * offset_local.y) * SCREEN_PIXEL_SIZE;
	vec2 centre_uv = SCREEN_UV - offset_uv;
	// Ball-lens view: inverted and minified, stronger toward the rim (fisheye).
	float mag = magnification * (1.0 + 0.6 * (1.0 - height));
	vec2 sample_uv = clamp(centre_uv - offset_uv * mag, vec2(0.001), vec2(0.999));
	vec3 seen = textureLod(screen_texture, sample_uv, focus_lod + 0.5 * (1.0 - height)).rgb;

	// Total internal reflection darkens the rim; the thin tail is mostly the background, slightly darkened.
	float rim = smoothstep(0.55, 1.0, rel);
	vec3 colour = seen * mix(1.0, 1.0 - rim_darkening, rim);
	// A sharp sky highlight on the upper-left of the cap, and a softer caustic opposite it.
	vec2 light_dir = normalize(vec2(-0.55, -0.85));
	float spec = pow(clamp(dot(outward, light_dir) * rel, 0.0, 1.0), 6.0) * smoothstep(0.35, 0.8, rel);
	float caustic = pow(clamp(dot(outward, -light_dir) * rel, 0.0, 1.0), 3.0) * 0.25;
	vec3 sky = textureLod(screen_texture, vec2(SCREEN_UV.x, 0.08), 4.0).rgb;
	colour += (sky * 0.6 + vec3(0.4)) * spec * highlight;
	colour += seen * caustic;
	colour += vec3(0.75, 0.82, 1.0) * flash * (0.25 + 0.75 * spec);
	float alpha = coverage * drop.y * opacity * mix(0.55, 1.0, smoothstep(0.0, 0.3, height));
	COLOR = vec4(colour, alpha);
}

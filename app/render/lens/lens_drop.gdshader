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
uniform float rim_darkening = 0.42;
uniform float highlight = 0.65;
uniform float flash = 0.0;              // FW-84 lightning radiance reaching the lens, 0…1
uniform vec2 sun_uv = vec2(-1.0);       // the sun (or moon) on screen; x < 0 when behind the camera
uniform float sun_strength = 0.0;       // how directly it shines into the lens, 0…2
uniform float opacity = 1.0;
// Physical pixels per canvas pixel: the UI may stretch the canvas (content scale) on 1440p and 4K screens.
uniform float canvas_scale = 1.0;

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

// Distance in drop radii; the head (radius 1) sits at x = e, the tail tapers back along −x. The contact line catches
// on the glass, so the outline is not a perfect circle: a few seeded low harmonics wobble it by a few percent.
float drop_sdf(vec2 q, float e, float seed_value) {
	vec2 hq = q - vec2(e, 0.0);
	float theta = atan(hq.y, hq.x);
	float wobble = 0.045 * sin(3.0 * theta + seed_value * 40.0) + 0.03 * sin(5.0 * theta + seed_value * 91.0);
	float head = length(hq) - (1.0 + wobble);
	if (e < 0.08) return head;
	float tail_r = 0.2;
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
	float d = drop_sdf(q, e, drop.z);
	float edge_px = 1.0 / (radius_px * canvas_scale);
	float coverage = 1.0 - smoothstep(-edge_px, edge_px, d);
	if (coverage <= 0.0) {
		discard;
	}
	// Spherical-cap height and the outward direction (numerical gradient of the distance).
	float rel = clamp(1.0 + d, 0.0, 1.0);
	float height = sqrt(max(1.0 - rel * rel, 0.0));
	const float eps = 0.03;
	vec2 grad = vec2(drop_sdf(q + vec2(eps, 0.0), e, drop.z) - drop_sdf(q - vec2(eps, 0.0), e, drop.z),
		drop_sdf(q + vec2(0.0, eps), e, drop.z) - drop_sdf(q - vec2(0.0, eps), e, drop.z));
	vec2 outward = length(grad) > 1e-5 ? normalize(grad) : vec2(0.0);

	// Screen-space offset of this fragment from the head's centre, from canvas pixels to screen uv.
	vec2 axis_y = vec2(-axis_x.y, axis_x.x);
	vec2 offset_local = (q - vec2(e, 0.0)) * radius_px;
	vec2 offset_uv = (axis_x * offset_local.x + axis_y * offset_local.y) * SCREEN_PIXEL_SIZE * canvas_scale;
	vec2 centre_uv = SCREEN_UV - offset_uv;
	// Ball-lens view: inverted and minified, stronger toward the rim (fisheye).
	float mag = magnification * (1.0 + 0.6 * (1.0 - height));
	vec2 sample_uv = clamp(centre_uv - offset_uv * mag, vec2(0.001), vec2(0.999));
	vec3 seen = textureLod(screen_texture, sample_uv, focus_lod + 0.5 * (1.0 - height)).rgb;

	// Total internal reflection darkens the rim; the thin tail is mostly the background, slightly darkened.
	float rim = smoothstep(0.62, 1.0, rel);
	vec3 colour = seen * mix(1.0, 1.0 - rim_darkening, rim);
	// A sharp sky highlight on the upper-left of the cap, and a softer caustic opposite it.
	// The highlight faces the brightest source: the sky above, or the sun when it shines into the lens.
	vec2 light_screen = normalize(vec2(-0.55, -0.85));
	if (sun_uv.x >= 0.0) {
		vec2 to_sun = (sun_uv - centre_uv) * vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
		if (length(to_sun) > 1e-4) {
			light_screen = normalize(mix(light_screen, normalize(to_sun), clamp(sun_strength, 0.0, 1.0)));
		}
	}
	vec2 light_dir = normalize(vec2(dot(light_screen, axis_x), dot(light_screen, axis_y)));
	float spec = pow(clamp(dot(outward, light_dir) * rel, 0.0, 1.0), 6.0) * smoothstep(0.35, 0.8, rel);
	float caustic = pow(clamp(dot(outward, -light_dir) * rel, 0.0, 1.0), 3.0) * 0.25;
	vec3 sky = textureLod(screen_texture, vec2(SCREEN_UV.x, 0.08), 4.0).rgb;
	colour += (sky * 0.6 + vec3(0.4)) * spec * highlight;
	colour += seen * caustic;
	colour += vec3(0.75, 0.82, 1.0) * flash * (0.25 + 0.75 * spec);
	// Into the sun every drop carries a hot pin-point glint.
	colour += vec3(1.0, 0.95, 0.84) * pow(spec, 4.0) * sun_strength * 2.2;
	// The head is a lens; the trail behind a running drop is a thin wet film that barely bends the image.
	float in_head = 1.0 - smoothstep(-0.05, 0.05, length(q - vec2(e, 0.0)) - 1.0);
	float alpha = coverage * drop.y * opacity * mix(0.28, 1.0, max(in_head, smoothstep(0.0, 0.45, height)));
	COLOR = vec4(colour, alpha);
}

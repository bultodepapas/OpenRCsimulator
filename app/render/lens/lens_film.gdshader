// LENS-03/10/11 (docs/plans/lens-screen-effects.md §5.3, §7). Ours, MIT. The one full-screen pass of the lens stack,
// drawn only while one of its films is active. It composites, back to front:
//   oil   a slow haze of glow-engine exhaust residue on an onboard lens (blur and bloom around bright sources);
//   dust  a blotchy contrast-losing veil after a dusty impact;
//   blood the classic curtain: a liquid sheet runs down from the top edge with uneven drips, holds, then drains from
//         the top and darkens as it dries. It absorbs the live image (Beer–Lambert: red passes, green and blue are
//         eaten), refracts it slightly through its own thickness and carries a wet highlight;
//   pulse a soft red edge pulse (never a full-screen flash: WCAG 2.3.1).
// The CPU drives every clock (curtain_t is presentation time since the strike): no TIME, no wall clock here.
shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;

uniform float curtain_on = 0.0;
uniform float curtain_t = 0.0;
uniform float depth = 1.0;              // deepest sheet front, share of the screen height (strength already applied)
uniform float speed = 0.8;              // screen heights per second
uniform float drain_start = 3.0;        // seconds after the strike
uniform float drain_rate = 0.42;        // screen heights per second emptied from the top
uniform float fade = 1.0;
uniform float seed = 0.0;
uniform float clear_centre = 0.0;
uniform float columns = 30.0;           // drip columns across a 16:9 screen
uniform vec3 sigma = vec3(0.55, 7.5, 8.5);
uniform vec3 albedo = vec3(0.30, 0.012, 0.010);
uniform vec3 dry_albedo = vec3(0.16, 0.022, 0.014);

uniform float dust = 0.0;
uniform vec3 dust_tint = vec3(0.62, 0.55, 0.45);
uniform float dust_seed = 0.0;
uniform float oil = 0.0;
uniform float pulse = 0.0;

uint lowbias32(uint x) {
	x ^= x >> 16u;
	x *= 2146121005u;
	x ^= x >> 15u;
	x *= 2221713035u;
	x ^= x >> 16u;
	return x;
}

float hash01(int a, int b) {
	return float(lowbias32(uint(a) * 1597334677u ^ uint(b) * 3812015801u) >> 8u) / 16777215.0;
}

float value_noise(vec2 p, int salt) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 s = f * f * (3.0 - 2.0 * f);
	int x = int(i.x);
	int y = int(i.y);
	float a = hash01(x + salt * 131, y);
	float b = hash01(x + 1 + salt * 131, y);
	float c = hash01(x + salt * 131, y + 1);
	float d = hash01(x + 1 + salt * 131, y + 1);
	return mix(mix(a, b, s.x), mix(c, d, s.x), s.y);
}

// Film thickness of the curtain at a screen point (y = 0 at the top). Continuous across drip columns.
float curtain_height(vec2 uv, float aspect) {
	float t = curtain_t;
	int salt = int(seed * 997.0);
	float sheet = min(t * speed, depth);
	float x = uv.x * aspect;
	float wave = 0.03 * sin(x * 6.3 + seed * 11.0) + 0.018 * sin(x * 15.1 + seed * 5.0);
	float front = sheet + wave * smoothstep(0.0, 0.15, sheet);
	float column_coord = x * columns / 1.7778;
	float cell = floor(column_coord);
	float f = fract(column_coord);
	int c = int(cell);
	float r = hash01(c, salt);
	float width = mix(0.22, 0.62, hash01(c, salt + 7));
	float lobe = max(0.0, 1.0 - pow(abs(f - 0.5) / (0.5 * width), 2.0));
	// A few long runners keep creeping during the hold; most columns only bulge.
	float growth = smoothstep(0.15, 1.4, t) + 0.06 * max(t - 1.4, 0.0);
	float drip = (0.04 + 0.42 * pow(r, 3.0)) * growth * smoothstep(0.02, 0.12, sheet);
	front += drip * lobe;
	float inside = 1.0 - smoothstep(front - 0.012, front, uv.y);
	float drained = max(t - drain_start, 0.0) * drain_rate;
	inside *= smoothstep(drained, drained + 0.07, uv.y);
	float profile = mix(1.0, 0.45, clamp(uv.y / max(front, 1e-3), 0.0, 1.0));
	float bead = (1.0 - smoothstep(0.0, 0.022, abs(uv.y - (front - 0.014)))) * (0.35 + 0.65 * lobe) * 0.75;
	float thin = 1.0 - 0.6 * clamp((t - drain_start) / 4.0, 0.0, 1.0);
	float h = inside * (profile + bead) * thin;
	if (clear_centre > 0.0) {
		float radial = length((uv - vec2(0.5)) * vec2(aspect, 1.0));
		h *= mix(1.0, smoothstep(0.18, 0.42, radial), clear_centre);
	}
	return h;
}

void over(inout vec4 acc, vec3 colour, float alpha) {
	alpha = clamp(alpha, 0.0, 1.0);
	acc.rgb = colour * alpha + acc.rgb * (1.0 - alpha);
	acc.a = alpha + acc.a * (1.0 - alpha);
}

float luminance(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec4 acc = vec4(0.0);

	if (oil > 0.0) {
		vec3 blurred = textureLod(screen_texture, uv, 3.5).rgb;
		vec3 bloom = max(blurred - vec3(0.62), vec3(0.0)) * 2.2 * vec3(1.0, 0.94, 0.82);
		float smear = 0.6 + 0.4 * value_noise(vec2(uv.x * aspect * 3.0, uv.y * 0.8), 3);
		over(acc, blurred + bloom, oil * 0.55 * smear);
	}
	if (dust > 0.0) {
		vec3 wide = textureLod(screen_texture, uv, 4.5).rgb;
		float blotch = value_noise(uv * vec2(aspect, 1.0) * 5.0 + dust_seed * 17.0, 5) * 0.6
			+ value_noise(uv * vec2(aspect, 1.0) * 17.0 + dust_seed * 5.0, 9) * 0.4;
		vec3 haze = mix(vec3(luminance(wide)), dust_tint, 0.55) + vec3(0.04);
		over(acc, haze, dust * (0.25 + 0.6 * blotch));
	}
	if (curtain_on > 0.0) {
		float h = curtain_height(uv, aspect);
		if (h > 0.0005) {
			vec2 px = SCREEN_PIXEL_SIZE * 2.0;
			float hx = curtain_height(uv + vec2(px.x, 0.0), aspect);
			float hy = curtain_height(uv + vec2(0.0, px.y), aspect);
			vec2 grad = vec2(hx - h, hy - h);
			vec3 behind = textureLod(screen_texture, clamp(uv - grad * 0.6, vec2(0.0), vec2(1.0)), 0.6 + 2.2 * min(h, 1.0)).rgb;
			vec3 ambient = textureLod(screen_texture, uv, 5.0).rgb;
			float density = 1.35 * h;
			float dry = clamp((curtain_t - drain_start) / 3.5, 0.0, 1.0);
			vec3 film_albedo = mix(albedo, dry_albedo, dry);
			vec3 colour = behind * exp(-sigma * density)
				+ film_albedo * (1.0 - exp(-2.4 * density)) * (0.35 + 0.65 * luminance(ambient)) * 1.6;
			vec3 normal = normalize(vec3(-grad * 70.0, 1.0));
			float spec = pow(max(dot(normal, normalize(vec3(-0.35, -0.55, 0.76))), 0.0), 36.0);
			colour += vec3(0.55, 0.45, 0.42) * spec * (0.35 + 0.65 * luminance(ambient)) * (1.0 - dry * 0.7);
			over(acc, colour, clamp(h * 4.0, 0.0, 1.0) * fade);
		}
	}
	if (pulse > 0.0) {
		float radial = length((uv - vec2(0.5)) * vec2(aspect / 1.7778, 1.0));
		over(acc, vec3(0.42, 0.0, 0.0), pulse * 0.55 * smoothstep(0.32, 0.8, radial));
	}
	if (acc.a <= 0.0005) {
		discard;
	}
	COLOR = vec4(acc.rgb / acc.a, acc.a);
}

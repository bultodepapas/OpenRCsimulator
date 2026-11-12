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
uniform vec3 sigma = vec3(1.8, 9.0, 10.0);
uniform vec3 albedo = vec3(0.19, 0.009, 0.008);
uniform vec3 dry_albedo = vec3(0.16, 0.022, 0.014);

uniform float wetness = 0.0;            // fine beads covering a wet lens, 0…1
uniform float wet_clock = 0.0;          // presentation seconds: beads appear and evaporate in turn
uniform float wet_focus = 1.5;
uniform vec2 sun_uv = vec2(-1.0);       // the sun (or moon) on screen; x < 0 when behind the camera
uniform float sun_strength = 0.0;
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

// Film thickness of the curtain at a screen point (y = 0 at the top, lengths in screen heights). The sheet's lower
// edge is a slow wave; from some columns hang runners: a narrow channel widening into a meniscus where it leaves the
// sheet and ending in a round bead, the way a liquid film drains down glass. Runners stay inside their column, so
// the field is continuous across columns.
float curtain_height(vec2 uv, float aspect) {
	float t = curtain_t;
	int salt = int(seed * 997.0);
	float sheet = min(t * speed, depth);
	float x = uv.x * aspect;
	float y = uv.y;
	float wave = 0.022 * sin(x * 5.1 + seed * 11.0) + 0.012 * sin(x * 13.7 + seed * 5.0) + 0.006 * sin(x * 31.0 + seed);
	float edge = sheet + wave * smoothstep(0.0, 0.15, sheet);
	// Sheet: thick at the top, thinner toward the edge, a slightly fuller rim held by surface tension.
	float in_sheet = 1.0 - smoothstep(edge - 0.004, edge + 0.002, y);
	float profile = mix(1.0, 0.5, clamp(y / max(edge, 1e-3), 0.0, 1.0));
	float rim = exp(-pow((edge - y - 0.006) / 0.008, 2.0)) * 0.35;
	float h = in_sheet * (profile + rim);
	// Runners.
	float column_width = 1.7778 / columns;
	float column_coord = x / column_width;
	int c = int(floor(column_coord));
	float dx = (fract(column_coord) - 0.5) * column_width;
	float r = hash01(c, salt);
	if (r > 0.3 && sheet > 0.02) {
		float growth = smoothstep(0.1, 1.3, t) + 0.05 * max(t - 1.3, 0.0);
		float reach = (0.015 + 0.38 * pow((r - 0.3) / 0.7, 2.2)) * growth;
		float w0 = mix(0.0035, 0.0095, hash01(c, salt + 7));
		float centre_shift = (hash01(c, salt + 13) - 0.5) * (column_width * 0.5 - 2.0 * w0);
		float px = dx - centre_shift;
		float local_edge = edge - 0.004;
		float yy = y - local_edge;
		float d = 1e3;
		if (yy > -0.01 && yy < reach) {
			float meniscus = 1.0 + 2.2 * exp(-max(yy, 0.0) / 0.012);
			d = abs(px) - w0 * meniscus;
		}
		d = min(d, length(vec2(px, yy - reach) * vec2(1.0, 0.85)) - w0 * 1.45);
		float runner = 1.0 - smoothstep(-0.0012, 0.0012, d);
		float bead = 1.0 - smoothstep(0.0, w0 * 1.5, length(vec2(px, yy - reach)));
		h = max(h, runner * (0.55 + 0.45 * bead + 0.3 * (1.0 - clamp(-d / w0, 0.0, 1.0))));
	}
	// Flow streaks inside the film.
	h *= 0.9 + 0.12 * value_noise(vec2(x * 22.0, y * 1.6 + seed * 3.0), 11) + 0.06 * value_noise(vec2(x * 61.0, y * 4.0), 17);
	// Draining empties the top and leaves a faint residue: a few thin rivulets, not a pattern.
	float drained = max(t - drain_start, 0.0) * drain_rate;
	float rivulet_coord = x * 26.0 + 0.4 * sin(y * 9.0 + x * 3.0);
	float rivulet = smoothstep(0.82, 0.97, hash01(int(floor(rivulet_coord)), salt + 29))
		* (1.0 - smoothstep(0.08, 0.32, abs(fract(rivulet_coord) - 0.5)));
	float residue = (0.03 + 0.09 * rivulet) * step(y, drained) * (1.0 - smoothstep(0.0, 3.0, (drained - y) / max(drain_rate, 1e-3)));
	float kept = drained > 0.0 ? smoothstep(drained, drained + 0.06, y) : 1.0;
	h = h * kept + residue * in_sheet;
	h *= 1.0 - 0.55 * clamp((t - drain_start) / 4.0, 0.0, 1.0);
	if (clear_centre > 0.0) {
		float radial = length((uv - vec2(0.5)) * vec2(aspect, 1.0));
		h *= mix(1.0, smoothstep(0.18, 0.42, radial), clear_centre);
	}
	return h;
}

// Fine static beads on a wet lens, after StaticDrops in "Rain on Glass" by Gerardo LCDF (MIT, see
// IMPACT_GLASS_LICENSE.txt): one bead per grid cell at a hashed offset, fading in and out on its own phase.
vec3 n13(float p) {
	vec3 p3 = fract(vec3(p) * vec3(0.1031, 0.11369, 0.13787));
	p3 += dot(p3, p3.yzx + 19.19);
	return fract(vec3((p3.x + p3.y) * p3.z, (p3.x + p3.z) * p3.y, (p3.y + p3.z) * p3.x));
}

float saw(float b, float t) {
	return smoothstep(0.0, b, t) * (1.0 - smoothstep(b, 1.0, t));
}

float static_drops(vec2 uv, float t) {
	uv *= 40.0;
	vec2 id = floor(uv);
	vec3 n = n13(id.x * 106.45 + id.y * 3543.654);
	vec2 centre = (n.xy - 0.5) * 0.6;
	uv = fract(uv) - 0.5;
	float drop = 1.0 - smoothstep(0.0, 0.3, length(uv - centre));
	return drop * saw(0.10, fract(t + n.y)) * fract(n.z * 27.0);
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
	if (wetness > 0.0) {
		vec2 wet_uv = vec2(uv.x * aspect, uv.y);
		float t = wet_clock * 0.05;
		float c = static_drops(wet_uv, t) * 2.0 * wetness;
		float bead = smoothstep(0.3, 1.0, c);
		// Most pixels hold no bead: the slope (two more evaluations) is paid only inside one.
		if (bead > 0.0) {
			vec2 e = SCREEN_PIXEL_SIZE.yy * 0.5;
			float cx = static_drops(wet_uv + vec2(e.x, 0.0), t) * 2.0 * wetness;
			float cy = static_drops(wet_uv + vec2(0.0, e.y), t) * 2.0 * wetness;
			vec2 slope = vec2(cx - c, cy - c);
			vec3 seen = textureLod(screen_texture, clamp(uv + slope * 0.6, vec2(0.0), vec2(1.0)), wet_focus).rgb;
			over(acc, seen * 1.05, bead);
		}
	}
	if (wetness > 0.0 && sun_uv.x >= 0.0 && sun_strength > 0.0) {
		// A wet lens scatters a bright source: a soft warm halo and a vertical smear along the water film.
		vec2 d = (uv - sun_uv) * vec2(aspect, 1.0);
		float halo = exp(-dot(d, d) / 0.018);
		float smear = exp(-d.x * d.x / 0.0006) * exp(-d.y * d.y / 0.09);
		float glare = wetness * sun_strength * (0.55 * halo + 0.35 * smear);
		over(acc, vec3(1.0, 0.93, 0.8), clamp(glare, 0.0, 0.75));
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
		// The film's slope from screen derivatives (per two pixels, as the refraction and highlight expect): one
		// evaluation of the curtain per pixel instead of three. The field is continuous, so 2×2 quads stay smooth.
		vec2 grad = vec2(dFdx(h), dFdy(h)) * 2.0;
		if (h > 0.0005) {
			vec3 behind = textureLod(screen_texture, clamp(uv - grad * 0.6, vec2(0.0), vec2(1.0)), 0.6 + 2.2 * min(h, 1.0)).rgb;
			vec3 ambient = textureLod(screen_texture, uv, 5.0).rgb;
			float density = 1.35 * h;
			float dry = clamp((curtain_t - drain_start) / 3.5, 0.0, 1.0);
			vec3 film_albedo = mix(albedo, dry_albedo, dry);
			vec3 colour = behind * exp(-sigma * density)
				+ film_albedo * (1.0 - exp(-2.4 * density)) * (0.35 + 0.65 * luminance(ambient)) * 1.6;
			vec3 normal = normalize(vec3(-grad * 70.0, 1.0));
			float spec = pow(max(dot(normal, normalize(vec3(-0.35, -0.55, 0.76))), 0.0), 36.0);
			colour += vec3(0.5, 0.42, 0.4) * 0.6 * spec * (0.35 + 0.65 * luminance(ambient)) * (1.0 - dry * 0.7);
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

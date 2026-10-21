// L11a: one texture and macro/pilot-pin function for the ground and blade roots. Ours, MIT.
// Extracted without retuning; grass-off captures must match the pre-L11 ground.
uniform sampler2D grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_m = 6.0;
uniform float anti_tiling = 1.0;
uniform float macro_amp = 0.25;
uniform float dry_amount = 0.45;
uniform vec2 pilot_xz = vec2(0.0);
uniform float pilot_pin_m = 35.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float vnoise(vec2 x) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Two fetches of the same tile at hashed offsets, blended by a slowly varying index (no visible grid of repeats).
vec3 untiled(vec2 uv) {
	vec2 gx = dFdx(uv);
	vec2 gy = dFdy(uv);
	float k = vnoise(uv * 1.2) * 8.0; // ~1.2 cycles per tile: repeat peak 0.92 -> 0.25 (0.6 cycles left 0.46)
	float i = floor(k);
	float f = fract(k);
	vec3 a = textureGrad(grass, uv + hash22(vec2(i, 17.0)), gx, gy).rgb;
	vec3 b = textureGrad(grass, uv + hash22(vec2(i + 1.0, 17.0)), gx, gy).rgb;
	return mix(a, b, smoothstep(0.2, 0.8, f - 0.1 * dot(a - b, vec3(1.0))));
}

// Large-scale tone in [−1, 1] and a dry-patch weight in [0, 1].
// LU-18: procedural octaves have no mip chain. Integrate unresolved cells toward their mean
// to prevent distant grazing-angle horizontal bands and shimmer; close detail stays unchanged.
float filtered_vnoise(vec2 p) {
	float footprint = max(length(dFdx(p)), length(dFdy(p)));
	return mix(vnoise(p), 0.5, smoothstep(0.25, 0.9, footprint));
}

vec2 macro(vec2 p) {
	// The spike's weights (report 01 §4): the 37 m octave carries the visible variation in the pilot's far band.
	float m = 0.5 * filtered_vnoise(p / 37.0) + 0.35 * filtered_vnoise(p / 160.0 + 17.0) + 0.15 * filtered_vnoise(p / 9.0 + 5.0);
	float dry = smoothstep(0.55, 0.85, filtered_vnoise(p / 60.0 + 3.0));
	return vec2(m * 2.0 - 1.0, dry);
}

vec3 rough_grass_colour(vec2 p) {
	vec2 uv = p / tile_m;
	vec3 base = anti_tiling > 0.5 ? untiled(uv) : texture(grass, uv).rgb;
	vec2 mc = macro(p);
	// Pin: near the station, subtract the macro value at the station itself, so the pilot's area keeps its L9a mean
	// while the variation around it stays (fading the amplitude instead flattened the whole 30-140 m band); the
	// variation itself ramps in over the first pilot_pin_m. Dry patches, one-sided, fade in from pilot_pin_m.
	float dist_pilot = distance(p, pilot_xz);
	float pin = smoothstep(pilot_pin_m, 4.0 * pilot_pin_m, dist_pilot);
	vec2 mc0 = macro(pilot_xz);
	float tone = 1.0 + macro_amp * (mc.x - mc0.x * (1.0 - pin)) * smoothstep(0.0, pilot_pin_m, dist_pilot);
	vec3 dry_tint = mix(vec3(1.0), vec3(1.18, 1.04, 0.80), dry_amount * mc.y * pin); // no dry patch in the pilot box
	return base * tone * dry_tint;
}

// Keep club mowing and taxi markings on both the ground and the near-grass blades.
// The same colour transform prevents an artificial contrast ring at the grass fade.
vec3 club_turf(vec3 grass_colour, vec2 p, bool enabled) {
	if (!enabled || abs(p.x) > 57.0 || p.y < -28.0 || p.y > -1.5) return grass_colour;
	float edge_noise = (vnoise(p / 3.7 + 19.0) - 0.5) * 0.75;
	vec2 apron_d = abs(p - vec2(0.0, -15.0));
	float apron = (1.0 - smoothstep(53.2 + edge_noise, 55.2 + edge_noise, apron_d.x))
		* (1.0 - smoothstep(11.0 + edge_noise, 13.0 + edge_noise, apron_d.y));
	float wide = 1.0 - smoothstep(0.85, 1.45, abs(p.y + 6.35) + edge_noise * 0.15);
	float ends = (1.0 - smoothstep(42.0, 44.0, abs(p.x))) * smoothstep(3.7, 5.8, abs(p.x));
	float links = (1.0 - smoothstep(1.15, 1.8, abs(abs(p.x) - 39.0)))
		* smoothstep(-9.8, -9.1, p.y) * (1.0 - smoothstep(-7.1, -6.4, p.y));
	float taxi = clamp(max(wide * ends, links), 0.0, 1.0);
	vec3 apron_colour = grass_colour * vec3(1.055, 1.065, 1.025);
	vec3 taxi_colour = grass_colour * vec3(0.955, 0.97, 0.91);
	vec3 result = mix(grass_colour, apron_colour, apron * 0.85);
	return mix(result, taxi_colour, taxi * (0.72 + 0.2 * vnoise(p / 1.8 + 7.0)));
}

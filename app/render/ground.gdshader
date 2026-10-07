// Ground (L2; LANDSCAPE-PLAN, investigation 02). Ours, MIT. The grass texture in world space (one tile every tile_m
// metres), matte, and the haze written as custom FOG: the same colour formula as the engine's fog and the sky's
// horizon, exponential amount 1 − e^(−βd), plus a rim fade to full haze between rim_start and rim_end so the 6 km
// edge of the ground can never show (realistic haze leaves 36 % contrast there).
// Landscape improvement phases 2 and 5 (docs/research/landscape-improvement-2026-10-07, reports 01 and 03):
// - anti-tiling: Inigo Quilez's "technique 3" idea, our own code: an index noise picks two hashed offsets of the same
//   tile and blends them (2 textureGrad fetches); Hoskins' "hash without sine" (MIT) instead of sin() hashes;
// - macro variation: value noise at 9, 37 and 160 m plus dry patches, pinned to its mean around the pilot station so
//   the near view keeps its L9a brightness;
// - a far-field patchwork of fields (green, straw, stubble, ploughed) beyond about 1 km, so raised views do not end in
//   one even green band.
// Phase 4 (report 04): the mown and runway surfaces use this same shader on their own plane (surface_kind 1 and 2).
// They first compute the rough grass exactly as the ground below does, then blend to mown turf inside a noisy border,
// so the edge is soft and irregular and never a colour seam. The runway adds filtered mowing stripes (view-dependent,
// as real stripes are) and worn touchdown zones. No TIME, no textures beyond the grass tile: every value is a pure
// function of position and view.
shader_type spatial;
render_mode cull_back;

#include "res://render/cloud_field.gdshaderinc"

// L15d: the same cumulus density as the sky, projected along the sun ray to a 1.5 km deck.
// Only direct sunlight is attenuated. Ambient light and the calibrated haze keep their energy.
global uniform vec2 cloud_drift_offset;
uniform float cloud_coverage = 0.35;
uniform float cloud_scale = 6.0;
uniform uint cloud_seed = 1253u;
uniform float cluster_strength = 0.0;
uniform float cloud_deck_m = 1500.0;
uniform float cloud_shadow_strength = 0.0;
varying float cloud_transmission;

uniform sampler2D grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_m = 6.0;
uniform vec3 haze_lin = vec3(0.584, 0.768, 0.846);
uniform vec3 sun_dir = vec3(0.0, 0.707, 0.707);
uniform vec3 sun_lin = vec3(3.14159);
uniform float sun_scatter = 0.0;
uniform float beta = 0.00017;
uniform float rim_start = 4800.0;
uniform float rim_end = 6000.0;
// L7 clear preset: inverse distance distributes the artificial rim closure over projected screen rows.
uniform bool rim_angular = false;
// Phase 2 (estimates tuned on the spike of report 01: luminance spread 9-14 levels, tile repeat <= 0.30).
uniform float anti_tiling = 1.0;
uniform float macro_amp = 0.25;
uniform float dry_amount = 0.45;
uniform vec2 pilot_xz = vec2(0.0);
uniform float pilot_pin_m = 35.0;
// Phase 5: the far-field patchwork.
uniform float fields_start_m = 700.0;
uniform float fields_full_m = 1300.0;
uniform float field_size_m = 230.0;
uniform float parcel_blend_m = 80.0;
uniform float parcel_strength = 0.6;        // of the crop factors below
uniform float fields_fade_start_m = 1800.0;  // the parcels fade out before the rim fade (L2: no step at the rim)
uniform float fields_fade_end_m = 3000.0;
// Phase 4: 0 rough, 1 mown, 2 runway; the surface's rectangle in render x/z (centre and half extents, m).
uniform int surface_kind = 0;
uniform vec2 rect_center = vec2(0.0);
uniform vec2 rect_half = vec2(1.0);
uniform float mown_value = 1.25;      // report 04: rough = 0.75-0.85 × mown; the top keeps the runway readable at 100 m+
uniform float mown_desat = 0.15;      // saturation -0.05...-0.10 at this grass colour
uniform float stripe_m = 1.5;         // one ride-on deck (1.2-1.8 m)
uniform float stripe_amp = 0.05;      // +-(3-6 %), below half the edge step
uniform float border_m = 0.6;         // noisy border, amplitude 0.3-0.8 m
uniform float wear = 0.45;            // touchdown wear weight, 10-30 m in from each threshold

varying vec3 world_pos;

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
vec2 macro(vec2 p) {
	// The spike's weights (report 01 §4): the 37 m octave carries the visible variation in the pilot's far band.
	float m = 0.5 * vnoise(p / 37.0) + 0.35 * vnoise(p / 160.0 + 17.0) + 0.15 * vnoise(p / 9.0 + 5.0);
	float dry = smoothstep(0.55, 0.85, vnoise(p / 60.0 + 3.0));
	return vec2(m * 2.0 - 1.0, dry);
}

// Far-field land cover: integer-hash Voronoi parcels, each a crop colour factor. Borders blend over parcel_blend_m
// (hard edges at 2-5 km alias into row steps and shimmer from altitude).
vec3 crop(vec2 id) {
	float h = hash12(id + 91.7);
	if (h < 0.34) return vec3(1.0);                    // pasture like the field
	if (h < 0.52) return vec3(0.86, 0.97, 0.80);       // lush, darker green
	if (h < 0.68) return vec3(1.45, 1.18, 0.78);       // ripe cereal / straw
	if (h < 0.82) return vec3(1.22, 1.04, 0.82);       // stubble
	if (h < 0.93) return vec3(0.98, 0.80, 0.64);       // ploughed earth
	return vec3(1.10, 1.06, 0.92);                     // young crop
}

vec3 parcel(vec2 p) {
	vec2 cell = floor(p / field_size_m);
	float d1 = 1e9;
	float d2 = 1e9;
	vec2 id1 = cell;
	vec2 id2 = cell;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = cell + vec2(float(x), float(y));
			vec2 site = (c + 0.15 + 0.7 * hash22(c)) * field_size_m;
			float d = distance(p, site);
			if (d < d1) {
				d2 = d1;
				id2 = id1;
				d1 = d;
				id1 = c;
			} else if (d < d2) {
				d2 = d;
				id2 = c;
			}
		}
	}
	return mix(crop(id2), crop(id1), 0.5 + 0.5 * smoothstep(0.0, parcel_blend_m, d2 - d1));
}

// A square wave of period 1 (+1, then -1) box-filtered over du: the exact mean via its triangle-wave integral.
float square_filtered(float u, float du) {
	du = max(du, 1e-4);
	float a = 0.5 - abs(fract(u + 0.5 * du) - 0.5);
	float b = 0.5 - abs(fract(u - 0.5 * du) - 0.5);
	return (a - b) / du;
}

// Mown turf over the rough colour, inside the surface's rectangle (Phase 4).
vec3 surface_colour(vec3 rough, vec2 p, vec3 view) {
	vec2 d = p - rect_center;
	vec2 q = abs(d) - rect_half;
	float sdf = max(q.x, q.y);
	float edge = border_m * (0.2 + 0.55 * vnoise(p / 3.5 + 41.0) + 0.25 * vnoise(p / 1.1 + 7.0));
	float fw = fwidth(sdf);
	float inside = 1.0 - smoothstep(-edge - 0.2 - fw, -edge + fw, sdf);
	float luma = dot(rough, vec3(0.2126, 0.7152, 0.0722));
	vec3 mown = mix(rough, vec3(luma), mown_desat) * mown_value;
	if (surface_kind == 2) {
		bool along_x = rect_half.x >= rect_half.y;
		float along = along_x ? d.x : d.y;
		float across = along_x ? d.y : d.x;
		float half_len = max(rect_half.x, rect_half.y);
		float half_wid = min(rect_half.x, rect_half.y);
		float u = across / (2.0 * stripe_m);
		float stripe = square_filtered(u, fwidth(u));
		vec2 axis = along_x ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
		float bend = dot(normalize(view.xz + vec2(1e-5)), axis);
		mown *= 1.0 + stripe_amp * stripe * bend;
		float from_end = half_len - abs(along);
		float zone = smoothstep(6.0, 12.0, from_end) * (1.0 - smoothstep(26.0, 34.0, from_end));
		float centre = 1.0 - smoothstep(0.12, 0.45, abs(across) / max(half_wid, 0.1));
		float w = wear * zone * centre * (0.3 + 0.7 * vnoise(p / 2.2 + 5.0));
		mown *= mix(vec3(1.0), vec3(1.12, 1.0, 0.78), w);
	}
	return mix(rough, mown, inside);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz / tile_m;
	vec3 base = anti_tiling > 0.5 ? untiled(uv) : texture(grass, uv).rgb;
	vec2 mc = macro(world_pos.xz);
	// Pin: near the station, subtract the macro value at the station itself, so the pilot's area keeps its L9a mean
	// while the variation around it stays (fading the amplitude instead flattened the whole 30-140 m band); the
	// variation itself ramps in over the first pilot_pin_m. Dry patches, one-sided, fade in from pilot_pin_m.
	float dist_pilot = distance(world_pos.xz, pilot_xz);
	float pin = smoothstep(pilot_pin_m, 4.0 * pilot_pin_m, dist_pilot);
	vec2 mc0 = macro(pilot_xz);
	float tone = 1.0 + macro_amp * (mc.x - mc0.x * (1.0 - pin)) * smoothstep(0.0, pilot_pin_m, dist_pilot);
	vec3 dry_tint = mix(vec3(1.0), vec3(1.18, 1.04, 0.80), dry_amount * mc.y * pin); // no dry patch in the pilot box
	vec3 col = base * tone * dry_tint;
	float far = smoothstep(fields_start_m, fields_full_m, dist_pilot) * (1.0 - smoothstep(fields_fade_start_m, fields_fade_end_m, dist_pilot));
	col *= mix(vec3(1.0), parcel(world_pos.xz), far * parcel_strength);
	vec3 to_frag = world_pos - CAMERA_POSITION_WORLD;
	float d = length(to_frag);
	vec3 v = to_frag / max(d, 1e-3);
	if (surface_kind > 0) {
		col = surface_colour(col, world_pos.xz, v);
	}
	cloud_transmission = 1.0;
	if (cloud_shadow_strength > 0.0 && cloud_coverage > 0.0 && sun_dir.y > 0.01) {
		vec2 deck = world_pos.xz + max(cloud_deck_m - world_pos.y, 0.0) * sun_dir.xz / sun_dir.y;
		float density = cloud_density(deck * (cloud_scale / cloud_deck_m) + cloud_drift_offset, cloud_seed, cloud_coverage, cluster_strength);
		cloud_transmission -= clamp(cloud_shadow_strength, 0.0, 1.0) * density * smoothstep(0.01, 0.1, sun_dir.y);
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	vec3 haze = haze_lin + sun_lin * pow(max(dot(v, sun_dir), 0.0), 8.0) * sun_scatter;
	float rim = rim_angular
		? 1.0 - smoothstep(1.0 / rim_end, 1.0 / rim_start, 1.0 / max(d, 1e-3))
		: smoothstep(rim_start, rim_end, d);
	FOG = vec4(haze, max(1.0 - exp(-beta * d), rim));
}

// Preserve this shader's existing Compatibility fallback: Lambert (no diffuse_burley render mode).
// LIGHT_COLOR includes PI; the renderer applies ALBEDO after accumulating diffuse light.
// Explicit Burley changes grazing views even with clouds disabled; see the zero-strength A/B proof.
void light() {
	float diffuse = max(dot(NORMAL, LIGHT), 0.0) * (1.0 / PI);
	float transmission = LIGHT_IS_DIRECTIONAL ? cloud_transmission : 1.0;
	DIFFUSE_LIGHT += LIGHT_COLOR * diffuse * ATTENUATION * transmission;
}

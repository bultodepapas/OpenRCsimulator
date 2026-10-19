// Sky background (L1a, L2; LANDSCAPE-PLAN, investigations 01 and 02). Ours, MIT.
// Gradient from the horizon haze to the zenith with weight 1 − (1 − y)^2.6 (Hosek-Wilkie fit at a 45° sun). The
// horizon is EXACTLY the colour the engine fogs distant objects toward (GLES3 fog_process: fog light colour + the
// sun's ×π scatter term), so far terrain melts into the sky with no seam. Below the horizon: pure haze. A 0.53° sun
// disc and halo. Clouds are periodic and deterministic; their drift is supplied from simulation time on the CPU.
// Godot's debanding. Never TIME (captures repeat; uniform changes refresh radiance).
//
// Colour space (read from the 4.7.2 GLES3 sky.glsl, line 250): Compatibility treats a sky shader's COLOR as sRGB
// and converts it with a cubic srgb_to_linear right after our code. So all maths here is linear (uniforms are linear,
// computed on the CPU) and the result is encoded with the exact inverse of that cubic: the engine gets our linear
// value back, the same number the ground's fog and the engine's object fog use.
shader_type sky;
render_mode use_debanding;
#include "res://render/cloud_field.gdshaderinc"
#include "res://render/cloud_relief.gdshaderinc"
uniform float cloud_relief_strength : hint_range(0.0, 1.0) = 1.0;

uniform vec3 zenith_lin = vec3(0.076, 0.138, 0.287);
uniform vec3 haze_lin = vec3(0.584, 0.768, 0.846); // fog_light_color.srgb_to_linear() * fog_light_energy
uniform vec3 sun_dir = vec3(0.0, 0.707, 0.707);    // toward the sun == the light's basis.z
uniform vec3 sun_lin = vec3(3.14159);              // light_color.srgb_to_linear() * light_energy * PI
uniform float sun_scatter = 0.0;                   // == Environment.fog_sun_scatter
uniform float gradient_curve = 2.6;
uniform bool disc_cloud_occlusion = false; // TOD: opt-in, legacy pixels unchanged
uniform vec3 disc_dir = vec3(0.0, 0.707, 0.707); // apparent disc may straddle the horizon
uniform float sun_radius = 0.0046251;              // rad: half of 0.53° (LIGHT0_SIZE defaults to 0)
// FW-22 time of day: the physical horizon lobe toward the brighter source (zero in the calibrated fixed-sun mode).
uniform vec3 lobe_lin = vec3(0.0);
uniform vec3 lobe_dir = vec3(1.0, 0.0, 0.0);
uniform float lobe_k = 8.0;
uniform float lobe_height = 1.5708;          // rad; the vertical e-folding of the lobe
// FW-MOON-06c: at twilight the sky shows both sources. A second lobe (the other source's arch or glow; zero = none)
// and a second light on the clouds: each light's weight in the clouds' directional shading (1, 0 = sun_dir alone,
// the calibrated day; both fade when only the sky lights the clouds, SkyState.cloud_light_weights).
uniform vec3 lobe2_lin = vec3(0.0);
uniform vec3 lobe2_dir = vec3(1.0, 0.0, 0.0);
uniform float lobe2_k = 8.0;
uniform float lobe2_height = 1.5708;
uniform vec3 light2_dir = vec3(0.0, 1.0, 0.0);
uniform float light1_weight = 1.0;
uniform float light2_weight = 0.0;
// FW-MOON-08a: the moon's aureole (SkyState.moon_aureole × Atmosphere.aureole_aerosol_factor; zero = none) and the
// V extinction per airmass of its path term (the stars' value).
uniform vec3 moon_aureole_lin = vec3(0.0);
uniform float moon_aureole_k = 0.2;
uniform float sun_disc = 1.0;                      // 0 when the light is the moon (FW-23)
// SUN-01 (docs/plans/sun.md; numbers in render/sun/sun_optics.gd). Defaults draw the L1a disc exactly: no limb
// darkening (0), no refraction flattening (1), no aerosol aureole (zero).
uniform float sun_limb = 0.0;
uniform float sun_squash = 1.0;                    // apparent / true vertical size of a low disc
uniform vec3 sun_aureole_lin = vec3(0.0);          // SunOptics.aureole_lin: sun_lin · 10^6.15 · nL/fc→sr⁻¹ · aerosols
uniform float sun_aureole_k = 0.2;                 // V extinction per airmass in the aureole's path term
const float SUN_LIMB_U = 0.93;                     // SunOptics.LIMB_U / LIMB_V (quadratic law near 550 nm)
const float SUN_LIMB_V = -0.23;
// FW-24 moon, photometric since FW-MOON-03: uniforms and disc in moon_disc.gdshaderinc; zero moon_lin = no moon.
#include "res://render/world/moon_disc.gdshaderinc"

// L4 fair-weather deck, now able to group into larger patches while keeping the old setting at zero strength.
uniform vec3 cloud_lin = vec3(0.9);         // lit cloud colour, linear
uniform float cloud_coverage = 0.35;        // 0 clear … 1 overcast
uniform float cloud_scale = 6.0;            // noise cells per unit of deck coordinate (dir.xz / dir.y)
uniform vec2 cloud_offset = vec2(0.0);      // drift in cells, wrapped to [0, CLOUD_FIELD_PERIOD) on the CPU from SIM time
uniform uint cloud_seed = 1u;
uniform float cluster_strength : hint_range(0.0, 1.0) = 0.0;
uniform float cirrus_strength : hint_range(0.0, 0.12) = 0.0; // maximum sky blend for the thin layer
uniform float cirrus_coverage : hint_range(0.0, 1.0) = 0.34;
uniform float silver_strength : hint_range(0.0, 1.0) = 0.0;
// Weather presets use up to eight independent 2D decks. The classic branch below remains the calibrated L4c path.
uniform bool layered_appearance = false;
uniform int appearance_layer_count = 0;
uniform vec4 appearance_layer_parameters[8]; // altitude m, metres per noise cell, coverage, density
uniform vec4 appearance_layer_motion[8]; // offset cells x/y, cluster strength, shape code
uniform int appearance_layer_seeds[8];
uniform float appearance_cloud_density = 1.0;

// FW-61/FW-22: the twilight arch toward the brighter source, azimuth exponent `lobe_k`, vertical e-folding
// `lobe_height` (radians): it hugs the horizon. Zero lobe_lin (the calibrated fixed sun) adds exactly nothing.
vec3 lobe_term(vec3 d) {
	float h = max(length(d.xz), 1e-4);
	float az = max(dot(d.xz / h, normalize(lobe_dir.xz + vec2(1e-6, 0.0))), 0.0);
	vec3 term = lobe_lin * pow(az, lobe_k) * exp(-max(asin(clamp(d.y, -1.0, 1.0)), 0.0) / lobe_height);
	if (dot(lobe2_lin, vec3(1.0)) > 0.0) {
		float az2 = max(dot(d.xz / h, normalize(lobe2_dir.xz + vec2(1e-6, 0.0))), 0.0);
		term += lobe2_lin * pow(az2, lobe2_k) * exp(-max(asin(clamp(d.y, -1.0, 1.0)), 0.0) / lobe2_height);
	}
	return term;
}

// FW-MOON-06c: the relief needs one light direction: the light with the larger weight. Its strength is the weights'
// difference, so it fades out where they are equal or where only the sky lights the clouds and never flips.
// Exactly sun_dir and 1 for the calibrated day.
vec3 relief_light() {
	return light2_weight > light1_weight ? light2_dir : sun_dir;
}

float relief_directionality() {
	return abs(light1_weight - light2_weight);
}

// FW-MOON-08a: Krisciunas & Schaefer's (1991) aerosol scattering around the moon: 6.2·10⁷·ρ⁻² near the moon (eq. 19),
// 10^(6.15 − ρ/40) farther out (eq. 21). The larger of the two within 30° joins them continuously at 8.4° (KS91 switch at
// 10° with a 28 % step); beyond 30° only eq. 21. The table's moonlit sky and horizon lobe already carry the moon's
// diffuse scattering, so only the forward peak is added: the term above its value at 45° (zero from 45° on, and at the
// zenith anchor whenever the moon is lower than 45°). Times the path term (1 − 10^(−0.4·k·X)) / (1 − 10^(−0.4·k))
// with X = (1 − 0.96·sin²Z)^−½ (eq. 3). Shown as the eye adapted to the moon sees it: the same local adaptation as the
// disc (moon_display_gamma; 1 = physical, by day), applied to the brightening over the sky behind it.
vec3 moon_aureole(vec3 d, vec3 background) {
	if (dot(moon_aureole_lin, vec3(1.0)) <= 0.0) {
		return vec3(0.0);
	}
	float rho = max(degrees(acos(clamp(dot(d, moon_dir), -1.0, 1.0))), degrees(moon_radius));
	if (rho >= 45.0) {
		return vec3(0.0);
	}
	float far_shape = pow(10.0, -rho / 40.0);
	float shape = (rho < 30.0 ? max(43.80 / (rho * rho), far_shape) : far_shape) - 0.07499; // 6.2e7 / 10^6.15 = 43.80; 10^(−45/40)
	float sin_z = min(length(d.xz), 1.0);
	float airmass = inversesqrt(1.0 - 0.96 * sin_z * sin_z);
	float path = (1.0 - pow(10.0, -0.4 * moon_aureole_k * airmass)) / (1.0 - pow(10.0, -0.4 * moon_aureole_k));
	vec3 a = moon_aureole_lin * shape * path;
	float la = dot(a, vec3(0.2126, 0.7152, 0.0722));
	float lb = max(dot(background, vec3(0.2126, 0.7152, 0.0722)), 1e-12);
	float shown = lb * (pow(1.0 + la / lb, moon_display_gamma) - 1.0);
	// A soft knee keeps the glow below the disc as shown. At the limb KS91 puts it at ~0.5 % of the disc's radiance;
	// shown with the disc's own γ that is 0.005^γ of the displayed disc (5 % at night), so the limb never washes out.
	// The bright core people see around the moon is mostly the eye's own straylight (the glare veil), not this.
	// FW-MOON-10: in an eclipse the disc as shown is the eclipsed one (moon_eclipse_dim; 1 otherwise, exact).
	float knee = pow(0.005, moon_display_gamma) * dot(moon_lin, vec3(0.2126, 0.7152, 0.0722)) * moon_display_scale * moon_eclipse_dim;
	shown = knee > 0.0 ? shown * knee / (knee + shown) : shown;
	return la > 0.0 ? a * (shown / la) : vec3(0.0);
}

// SUN-01: KS91's aerosol aureole around the sun (the moon_aureole law above), anchored to the sun's own illuminance
// rather than the zenith, flat inside 1° (the LDR disc cannot carry the ρ⁻² peak) and only above its 45° value (the
// sky table's lobe already holds the diffuse part). Compressed below 0.4 of the disc's mean radiance, under its
// limb-darkened edge, so a low, reddened disc stays distinct inside its glow; the eye's veil adds the rest.
vec3 sun_aureole(vec3 d, vec3 dir) {
	if (dot(sun_aureole_lin, vec3(1.0)) <= 0.0) {
		return vec3(0.0);
	}
	float rho = max(degrees(acos(clamp(dot(d, dir), -1.0, 1.0))), 1.0);
	if (rho >= 45.0) {
		return vec3(0.0);
	}
	float far_shape = pow(10.0, -rho / 40.0);
	float shape = (rho < 30.0 ? max(43.80 / (rho * rho), far_shape) : far_shape) - 0.07499;
	float sin_z = min(length(d.xz), 1.0);
	float airmass = inversesqrt(1.0 - 0.96 * sin_z * sin_z);
	vec3 a = sun_aureole_lin * shape * (1.0 - pow(10.0, -0.4 * sun_aureole_k * airmass));
	float la = dot(a, vec3(0.2126, 0.7152, 0.0722));
	float disc = 0.4 * (4.0 / PI) * dot(sun_lin, vec3(0.2126, 0.7152, 0.0722)); // SunOptics.AUREOLE_DISC_SHARE
	return a / (1.0 + la / max(disc, 1e-12));
}

// SUN-01: the disc's profile (0 outside, the L1a edge ramp) with refraction flattening along the local vertical and
// the photosphere's limb darkening, divided by its disc mean (1 − u/3 − v/2) so the calibrated brightness stays.
float sun_disc_profile(vec3 d, vec3 dir) {
	float c = dot(d, dir);
	vec3 o = d - dir * c;
	vec3 up_sky = vec3(0.0, 1.0, 0.0) - dir * dir.y;
	float up_len = length(up_sky);
	if (up_len > 1e-4) {
		up_sky /= up_len;
		o += up_sky * (dot(o, up_sky) * (1.0 / max(sun_squash, 0.1) - 1.0));
	}
	float ang = asin(clamp(length(o), 0.0, 1.0));
	if (c <= 0.0) {
		return 0.0;
	}
	float rr = min(ang / max(sun_radius, 1e-6), 1.0);
	float mu = sqrt(max(1.0 - rr * rr, 0.0));
	float law = (1.0 - SUN_LIMB_U * (1.0 - mu) - SUN_LIMB_V * (1.0 - mu * mu)) / (1.0 - SUN_LIMB_U / 3.0 - SUN_LIMB_V / 2.0);
	return (1.0 - smoothstep(0.9 * sun_radius, 1.1 * sun_radius, ang)) * mix(1.0, law, clamp(sun_limb, 0.0, 1.0));
}

vec3 haze(vec3 d) {
	return haze_lin + sun_lin * pow(max(dot(d, sun_dir), 0.0), 8.0) * sun_scatter + lobe_term(d);
}

// Exact inverse of the engine's srgb_to_linear(s) = s·(s·(0.305306011·s + 0.682171111) + 0.012522878):
// Newton's method from the engine's own linear_to_srgb approximation; 3 steps reach float precision.
vec3 encode_for_engine(vec3 x) {
	vec3 s = max(vec3(1.055) * pow(max(x, vec3(0.0)), vec3(0.416666667)) - vec3(0.055), vec3(0.0));
	for (int i = 0; i < 3; i++) {
		vec3 f = s * (s * (s * 0.305306011 + 0.682171111) + 0.012522878) - x;
		vec3 df = s * (s * 0.915918033 + 1.364342222) + 0.012522878;
		s -= f / df;
	}
	return s;
}

void sky() {
	float y = max(EYEDIR.y, 0.0);
	vec3 col = mix(haze(EYEDIR), zenith_lin, 1.0 - pow(1.0 - y, gradient_curve));
	// FW-MOON-01/03b: the disc stays out of the radiance cubemap (a sub-texel highlight in ambient and reflections);
	// reflection probes draw the background pass, so the lake still sees it.
	if (!AT_CUBEMAP_PASS) {
		col += moon_aureole(EYEDIR, col); // FW-MOON-08a: over the sky behind it, before the disc
		col += moon_disc(EYEDIR); // before the clouds, which hide it
	}
	if (!AT_CUBEMAP_PASS && sun_disc > 0.0) {
		// SUN-01, under the clouds. Faded out over the last 2° above the horizon, which must stay the engine's fog colour
		// (the ground and ridges fog toward haze() without it).
		col += sun_aureole(EYEDIR, disc_cloud_occlusion ? disc_dir : sun_dir) * smoothstep(0.0, 0.035, EYEDIR.y);
	}
	float density = 0.0;
	float cirrus_amount = 0.0;
	if (layered_appearance) {
		if (EYEDIR.y > 0.0 && appearance_layer_count > 0) {
			float horizon_fade = smoothstep(0.03, 0.25, EYEDIR.y);
			for (int order = 0; order < 8; order++) {
				int layer_index = appearance_layer_count - 1 - order; // upper decks first; the nearer low deck paints last
				if (layer_index < 0) {
					break;
				}
				vec4 layer = appearance_layer_parameters[layer_index];
				vec4 layer_motion = appearance_layer_motion[layer_index];
				uint layer_seed = uint(max(appearance_layer_seeds[layer_index], 0));
				vec2 deck = (EYEDIR.xz / max(EYEDIR.y, 0.02)) * (layer.x / max(layer.y, 1.0));
				vec2 cells = mod(deck + layer_motion.xy, float(CLOUD_FIELD_PERIOD));
				int shape = int(floor(layer_motion.w + 0.5));
				float body;
				if (shape == 1) {
					body = cloud_stretched_density(cells, layer_seed, layer.z, vec2(3.0, 51.0) / 64.0);
				} else if (shape == 2) {
					body = cloud_stretched_density(cells, layer_seed, layer.z, vec2(7.0, 45.0) / 64.0);
				} else {
					body = cloud_density(cells, layer_seed, layer.z, layer_motion.z);
				}
				if (shape == 3) { // low stratus: soften the mottling and keep a continuous near-horizon ceiling
					float ceiling = smoothstep(0.02, 0.13, EYEDIR.y) * smoothstep(0.52, 0.94, layer.z);
					body = max(body, 0.90 * ceiling);
				}
				float optical = clamp(layer.w, 0.0, 1.0) * clamp(appearance_cloud_density, 0.0, 1.0);
				float layer_horizon_fade = shape == 3 ? smoothstep(0.005, 0.11, EYEDIR.y) : horizon_fade;
				float tower_height = shape == 4 ? mix(0.68, 1.0, smoothstep(0.025, 0.52, EYEDIR.y)) : 1.0;
				float alpha = clamp(body * optical * layer_horizon_fade * tower_height, 0.0, 0.98);
				float lighting = 0.68 + 0.32 * (light1_weight * max(dot(EYEDIR, sun_dir), 0.0) + light2_weight * max(dot(EYEDIR, light2_dir), 0.0));
				float tower_shade = shape == 4 ? mix(0.60, 1.0, smoothstep(0.04, 0.48, EYEDIR.y)) : 1.0;
				// A broad, periodic low-frequency tone gives clouds real mass at field-view
				// elevations; the shared high-frequency field still controls their silhouette.
				float macro_tone = 1.0;
				if (shape == 3 || shape == 4 || shape == 5) {
					// Low stratus must vary across field-of-view, where the low deck projects
					// only a few base cells; towers keep broader kilometer-scale shading.
					float macro_divisor = shape == 3 ? 2.0 : (shape == 4 ? 8.0 : 16.0);
					int macro_period = int(float(CLOUD_FIELD_PERIOD) / macro_divisor);
					float macro_noise = cloud_field_value_noise(mod(cells, float(CLOUD_FIELD_PERIOD)) / macro_divisor,
						ivec2(macro_period), layer_seed + 32452843u);
					float macro = smoothstep(0.16, 0.84, macro_noise);
					if (shape == 4) {
						macro_tone = mix(0.42, 1.36, macro);
					} else if (shape == 3) {
						macro_tone = mix(0.40, 1.38, macro);
					} else {
						macro_tone = mix(0.64, 1.24, macro);
					}
				}
				vec3 layer_color = cloud_lin * mix(1.0, 0.82, body) * lighting * tower_shade * macro_tone;
				// Preserve the calibrated 2.5D relief on ordinary cloud decks. It stays
				// bounded, background-only, and out of the radiance cubemap pass.
				float relief_weight = clamp(cloud_relief_strength, 0.0, 1.0) * smoothstep(0.12, 0.40, EYEDIR.y) * relief_directionality();
				if (!AT_CUBEMAP_PASS && shape != 1 && shape != 2 && relief_weight > 0.0 && body > 0.0) {
					vec3 relief = cloud_relief(cells, body, EYEDIR, relief_light(), cloud_lin, layer_seed, layer.z, layer_motion.z);
					layer_color = mix(layer_color, relief * lighting * tower_shade * macro_tone, relief_weight);
				}
				col = mix(col, layer_color, alpha);
				density = 1.0 - (1.0 - density) * (1.0 - alpha);
			}
		}
	} else if (EYEDIR.y > 0.0 && cloud_coverage > 0.0) {
		vec2 deck = EYEDIR.xz / max(EYEDIR.y, 0.02);                    // flat layer
		vec2 cells = mod(deck * cloud_scale + cloud_offset, float(CLOUD_FIELD_PERIOD));
		float body = cloud_density(cells, cloud_seed, cloud_coverage, cluster_strength);
		density = body * smoothstep(0.03, 0.25, EYEDIR.y); // thin out into the horizon haze
		vec3 cloud_color = cloud_lin * mix(1.0, 0.82, density);
		// Background-only detail preserves the calibrated IBL. Fade relief before
		// the deck becomes subpixel at the horizon; coverage itself is unchanged.
		float relief_weight = clamp(cloud_relief_strength, 0.0, 1.0) * smoothstep(0.12, 0.40, EYEDIR.y) * relief_directionality();
		if (!AT_CUBEMAP_PASS && relief_weight > 0.0 && density > 0.0) {
			vec3 relief = cloud_relief(cells, body, EYEDIR, relief_light(), cloud_lin, cloud_seed, cloud_coverage, cluster_strength);
			cloud_color = mix(cloud_color, relief, relief_weight);
		}
		col = mix(col, cloud_color, density);

		// A higher, very thin deck: noise stretched along the horizon, with an exact 64-cell period.
		if (cirrus_strength > 0.0) {
			float cirrus = cloud_stretched_density(cells, cloud_seed + 15485863u, cirrus_coverage, vec2(3.0, 51.0) / 64.0)
				* smoothstep(0.02, 0.18, EYEDIR.y);
			cirrus_amount = clamp(cirrus * clamp(cirrus_strength, 0.0, 0.12), 0.0, 0.12);
			col = mix(col, cloud_lin * 1.04, cirrus_amount);
		}

		// A bounded forward-scatter edge on clouds close to the sun direction; never raises the deck by > 0.08.
		if (silver_strength > 0.0) {
			float cloud_edge = 4.0 * density * (1.0 - density);
			float forward_scatter = light1_weight * pow(max(dot(EYEDIR, sun_dir), 0.0), 24.0)
				+ light2_weight * pow(max(dot(EYEDIR, light2_dir), 0.0), 24.0);
			float silver = 0.08 * clamp(silver_strength, 0.0, 1.0) * cloud_edge * forward_scatter;
			col += cloud_lin * silver;
		}
	}
	vec3 disc_direction = disc_cloud_occlusion ? disc_dir : sun_dir;
	float ang = acos(clamp(dot(EYEDIR, disc_direction), -1.0, 1.0));
	float disc_shape = 1.0 - smoothstep(0.9 * sun_radius, 1.1 * sun_radius, ang);
	if (!AT_CUBEMAP_PASS && (sun_limb > 0.0 || sun_squash != 1.0)) {
		disc_shape = sun_disc_profile(EYEDIR, disc_direction); // SUN-01; the radiance cubemap keeps the L1a disc
	}
	vec3 solar = (sun_lin / PI) * (exp(-ang * 18.0) * 0.35 + 4.0 * disc_shape);
	if (disc_cloud_occlusion) {
		// Estimated optical thickness; use the same density as the visible deck.
		solar *= exp(-8.0 * (density + cirrus_amount)) * step(0.0, EYEDIR.y);
	}
	col += solar * sun_disc;
	COLOR = encode_for_engine(col);
}

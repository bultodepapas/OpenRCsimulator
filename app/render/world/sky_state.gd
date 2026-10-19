# FIELD-WORLD-PLAN FW-22/FW-23: time of day → the numbers the sky shader, the haze (engine fog and the ground's own
# fog), the directional light and the exposure use. Input: Ephemeris.sky(). Output: one Dictionary that
# render/atmosphere.gd reads instead of its fixed 45° constants.
#
# Physics from app/data/sky/sky_table.json (tools/world/sky_table.py): relative zenith, horizon haze, sunward horizon
# lobe, direct-sun and cloud-deck transmittance per sun elevation. They are ANCHORED at 45° to Spec.ATMOSPHERE's
# calibrated look (L1a/L1b/L2/L3), so the model only decides how colours change with the hour, never the day look.
# The moon lights the same atmosphere, scaled by its brightness relative to the sun (phase law below).
extends RefCounted

const TwilightPalette := preload("res://render/landscape_upgrade/twilight_palette.gd")
const Spec := preload("res://spec.gd")
const Frames := preload("res://render/frames.gd")
const Lunar := preload("res://render/world/lunar.gd")
const Ephemeris := preload("res://render/world/ephemeris.gd")

const TABLE_PATH := "res://data/sky/sky_table.json"
const ANCHOR_ELEVATION_DEG := 45.0
## Full moon vs sun illuminance: 10^(−0.4·(26.74 − 12.73)) (borrowed: apparent magnitudes −26.74 and −12.73).
const MOON_FULL_RATIO := 2.5e-6
## Moonlight drawn cooler than physical (it is slightly redder than sunlight): the Purkinje convention of night
## imagery, so moonlit scenes read as night (estimate, artistic, labeled). Tints the moonlit sky; the moon's direct
## light takes MOON_LIGHT_COLOR with the physical luminance.
const MOON_TINT := Vector3(0.62, 0.78, 1.0)
const MOON_LIGHT_COLOR := Color("#b4c8ff")
## Natural night-sky floor relative to the anchored day sky (borrowed: ~22 mag/arcsec² ≈ 1.7·10⁻⁴ cd/m² against a
## clear-day zenith of ~3,500 cd/m²).
const NIGHT_FLOOR := 5.0e-8
## Full-moon disc luminance relative to the anchored day zenith radiance (estimate: ~2,500 vs ~4,000 cd/m²).
const MOON_DISC := 0.6
## FW-MOON-03: the disc's base colour (linear-light reflectance tint; the lunar surface is slightly red).
const MOON_DISC_COLOR := Color(0.98, 0.96, 0.92)
## The earthlit side is 0.15 mag bluer in B−V than the sunlit side (Thejll et al. 2014): a luminance-neutral tint
## (estimate from that colour difference).
const EARTHSHINE_TINT := Vector3(0.926, 1.006, 1.157)
## The mean angular semidiameter, for hand-built skies without a place (tests).
const MOON_MEAN_RADIUS_RAD := 0.0045379
## FW-MOON-12 non-physical choices (the interface labels them): a larger disc (cinematic) and brighter moonlight
## (assist); the same factors as MoonConfig.LARGE_SIZE_FACTOR / BRIGHT_MOONLIGHT_FACTOR.
const MOON_LARGE_FACTOR := 2.0
const MOON_BRIGHT_FACTOR := 3.0
## Moon shadows: strength 0 → 1 as the direct share of the light rises from LOW to HIGH times the 45° sun's share
## (estimate; a full moon well up casts full shadows, a thin crescent none).
const MOON_SHADOW_SHARE_LOW := 0.15
const MOON_SHADOW_SHARE_HIGH := 0.5
## The sun's shadows are at full strength from this apparent elevation up (FW-MOON-06b, sun_shadow_strength).
const SUN_SHADOW_FULL_DEG := 0.5
## FW-MOON-06c cloud_light_weights: the day's direct share of the cloud light (the 0.8 / 0.2 split of `cloud`) and the
## smallest directional weight kept, also the smallest second lobe relative to the first (so a 10⁻⁶ moon leaves the
## day sky's uniforms exactly at (1, 0) and one lobe).
const CLOUD_DIRECT_SHARE_DAY := 0.8
const CLOUD_WEIGHT_FLOOR := 1e-4
## FW-MOON-08a: an aureole below this fraction of the zenith radiance is dropped (by day it is ~10⁻⁶).
const AUREOLE_FLOOR := 1e-4
## The eye's local adaptation to the disc (FW-MOON-03). At night the full moon is 10⁴–10⁵ times brighter than the scene
## the exposure serves, so a physical disc is a white blob and a crescent's earthshine a grey disc. When the lit full
## moon outside the atmosphere would exceed MOON_DISPLAY_PEAK on the display (radiance × exposure), the shader scales
## the disc so that moon lands there (the atmosphere then dims and reddens it as usual) and compresses its illumination (sunlit part vs earthshine) with exponent MOON_DISPLAY_GAMMA, reached
## once the excess is 100×: what a dark-adapted eye sees when it looks at the moon (estimate, labeled; the physical
## disc returns by day, where the excess is below 1).
## Tuned against Godot 4.7.2's AgX (allenwp curve; white 1.0 → AgX clip at 2.0): the mean full moon at 0.76 sRGB
## (maria 0.6, highlands 0.87, nothing clipped); a crescent's earthshine at ~0.035, fading to ~0.017 at quarter
## (docs/research/field-world/FW-MOON-05).
const MOON_DISPLAY_PEAK := 0.7
const MOON_DISPLAY_GAMMA := 0.55
## FW-MOON-05: the albedo map's projected-area mean linear luminance over the near side (NASA SVS lroc_color_2k,
## measured in docs/research/field-world/FW-MOON-05): texels divided by it average 1, so the textured disc keeps
## the phase law's brightness.
const MOON_ALBEDO_NEAR_SIDE_MEAN := 0.3967
## Scripted adaptation (auto-exposure is Forward+ only in 4.7): gain = (Y_anchor / Y)^p, limited. p < 1 compresses
## the 10^8 range from noon to moonless night into what a display shows. p = 0.84 maps the scene key to roughly
## sunset 0.6, blue hour 0.45, full-moon night 0.12 of noon; the cap leaves a moonless night near black, where stars
## and field lights carry the scene (estimates, tuned on captures).
const ADAPT_POWER := 0.84
const ADAPT_MAX_GAIN := 1.5e5
## Below this sun elevation the tonemapper is AgX (FW-26): Godot's AgX (allenwp curve: sigmoid toe, Reinhard-like
## shoulder) has no black point, unlike its ACES fit, which renders linear values under ~0.002 black, and it rolls off
## floodlights instead of clipping them. Day keeps ACES, chosen for readability by measurement in L1b.
const AGX_BELOW_SUN_DEG := -1.0

## Ambient light. Godot 4.7.2 Compatibility renders the sky's radiance cubemap already multiplied by the exposure
## (drivers/gles3/shaders/sky.glsl, cubemap pass), and scene.glsl decodes it as ambient and multiplies by the
## exposure again. At exposure 0.6 that is part of the calibrated day look; at a night exposure of ~10⁴ it makes
## every lit surface white. So time-of-day mode uses an ambient COLOUR instead: the sky's mix 0.4·zenith + 0.6·haze
## (estimate of the up-facing hemisphere average), times a per-channel constant that reproduces, at the 45° anchor,
## the ambient the engine effectively applies in the calibrated mode.
const AMBIENT_ZENITH_SHARE := 0.4

static var _rows: Array = []


static func rows() -> Array:
	if _rows.is_empty():
		var f := FileAccess.open(TABLE_PATH, FileAccess.READ)
		assert(f != null, "missing " + TABLE_PATH)
		var data: Dictionary = JSON.parse_string(f.get_as_text())
		assert(data.get("format", "") == "openrc-sky-table v1", "bad sky table format")
		_rows = data.rows
	return _rows


static func _v(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## The table row at an elevation, linearly interpolated (0.5° rows); clamped to the table's ends.
static func row(elevation_deg: float) -> Dictionary:
	var r := rows()
	var first: float = r[0].elevation_deg
	var step: float = float(r[1].elevation_deg) - first
	var x := clampf((elevation_deg - first) / step, 0.0, r.size() - 1.0)
	var i := mini(int(floorf(x)), r.size() - 2)
	var f := x - i
	var a: Dictionary = r[i]
	var b: Dictionary = r[i + 1]
	var out := {}
	for key: String in ["zenith", "haze", "lobe", "sun", "cloud"]:
		out[key] = _v(a[key]).lerp(_v(b[key]), f)
	out.lobe_k = lerpf(float(a.lobe_k), float(b.lobe_k), f)
	out.lobe_height_deg = lerpf(float(a.get("lobe_height_deg", 90.0)), float(b.get("lobe_height_deg", 90.0)), f)
	return out


static func _lin(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	return Vector3(l.r, l.g, l.b)


## Godot's linear_to_srgb (gles3 tonemap_inc.glsl), per channel.
static func _engine_linear_to_srgb(v: Vector3) -> Vector3:
	var out := Vector3.ZERO
	for i in 3:
		var c := maxf(v[i], 0.0)
		out[i] = 12.92 * c if c < 0.0031308 else 1.055 * pow(c, 1.0 / 2.4) - 0.055
	return out


static func _lum(v: Vector3) -> float:
	return 0.2126 * v.x + 0.7152 * v.y + 0.0722 * v.z


static func _ratio(num: Vector3, den: Vector3) -> Vector3:
	return Vector3(num.x / maxf(den.x, 1e-30), num.y / maxf(den.y, 1e-30), num.z / maxf(den.z, 1e-30))


## Unit vector toward (azimuth from north clockwise, elevation) in render axes.
static func direction(azimuth_deg: float, elevation_deg: float) -> Vector3:
	var az := deg_to_rad(azimuth_deg)
	var el := deg_to_rad(elevation_deg)
	return Frames.ned_to_render([cos(az) * cos(el), sin(az) * cos(el), -sin(el)]).normalized()


## Moon brightness relative to the full moon for a phase angle (degrees): Allen's magnitude law
## Δm = 0.026·|ψ| + 4·10⁻⁹·ψ⁴ (borrowed, Astrophysical Quantities; the same law as Krisciunas & Schaefer 1991).
static func moon_phase_flux(phase_angle_deg: float) -> float:
	var psi := absf(phase_angle_deg)
	return pow(10.0, -0.4 * (0.026 * psi + 4.0e-9 * pow(psi, 4.0)))


## FW-MOON-03: McEwen's lunar-Lambert weight L(α) (Icarus 92:298, 1991; α in degrees), clamped to [0, 1].
static func lunar_lambert_l(phase_angle_deg: float) -> float:
	var a := absf(phase_angle_deg)
	return clampf(1.0 - 0.019 * a + 2.42e-4 * a * a - 1.46e-6 * a * a * a, 0.0, 1.0)


## FW-MOON-03: the disc integral of the lunar-Lambert pattern relative to full moon (closed forms: Lommel-Seeliger
## 1 − sin(α/2)·tan(α/2)·ln cot(α/4), as in Jensen et al. 2001; Lambert sphere (sin α + (π − α)·cos α)/π at 2/3 of the
## full-disc value). Verified against numerical integration in test_world_moon_sky.gd.
static func lunar_lambert_integral(phase_angle_deg: float) -> float:
	var a := deg_to_rad(clampf(absf(phase_angle_deg), 0.0, 178.0))
	var l := lunar_lambert_l(phase_angle_deg)
	var lommel_seeliger := 1.0 if a < 1e-6 else 1.0 - sin(a / 2.0) * tan(a / 2.0) * log(1.0 / tan(a / 4.0))
	var lambert := (sin(a) + (PI - a) * cos(a)) / PI
	return l * lommel_seeliger + (1.0 - l) * (2.0 / 3.0) * lambert


## FW-MOON-05: rotation from render-frame directions to Moon-fixed coordinates (x toward 0° E on the equator, z north),
## for texturing the disc; identity without a Lunar state.
static func moon_render_to_body(lunar: Dictionary) -> Basis:
	if lunar.is_empty():
		return Basis.IDENTITY
	var m: PackedFloat64Array = lunar.body_to_ned # v_ned = M · v_body
	# Render (x east, y up, z south) → NED is N = −z, E = x, D = −y; so v_body = Mᵀ · (−z, x, −y).
	var column := func(ned: Array) -> Vector3:
		return Vector3(m[0] * ned[0] + m[3] * ned[1] + m[6] * ned[2], m[1] * ned[0] + m[4] * ned[1] + m[7] * ned[2],
			m[2] * ned[0] + m[5] * ned[1] + m[8] * ned[2])
	return Basis(column.call([0.0, 1.0, 0.0]), column.call([0.0, 0.0, -1.0]), column.call([-1.0, 0.0, 0.0]))


## FW-MOON-05: refraction squashes a low disc vertically: apparent/true vertical size = 1 + dR/dh at the centre's
## true elevation (Saemundsson's formula, as Ephemeris.refraction_deg; 0.86 on the horizon, 0.975 at 5°).
static func moon_squash(true_elevation_deg: float) -> float:
	if true_elevation_deg < -1.0:
		return 1.0
	var h := 0.01
	return 1.0 + (Ephemeris.refraction_deg(true_elevation_deg + h) - Ephemeris.refraction_deg(true_elevation_deg - h)) / (2.0 * h)


## FW-MOON-06b: the sun's shadow strength across the horizon: its disc's direct beam (the sky table's `sun` row)
## relative to the beam at SUN_SHADOW_FULL_DEG, clamped to [0, 1]. Full strength from that elevation up (every
## daytime, golden-hour and sunset scene is unchanged), zero from −0.5°, where the table's beam ends.
static func sun_shadow_strength(sun_elevation_deg: float) -> float:
	if sun_elevation_deg >= SUN_SHADOW_FULL_DEG:
		return 1.0
	return clampf(_lum(row(sun_elevation_deg).sun) / _lum(row(SUN_SHADOW_FULL_DEG).sun), 0.0, 1.0)


## FW-MOON-06c: how strongly the sun (x) and the moon (y) shade the clouds directionally, from the direct sunlit,
## direct moonlit and sky-lit parts of their light. A source's weight is its share of that light divided by the
## calibrated day's direct share (0.8). While the sun's disc is up (`sun_up` = sun_shadow_strength: 1 from 0.5°)
## the sun keeps weight 1, so every daytime, golden-hour and sunset sky is unchanged; as the disc sets, its weight
## blends into its measured share. Weights below CLOUD_WEIGHT_FLOOR are dropped; the sum never exceeds 1.
static func cloud_light_weights(sun_direct: float, moon_direct: float, sky_light: float, sun_up := 0.0) -> Vector2:
	var total := sun_direct + moon_direct + sky_light
	var w := Vector2(sun_direct, moon_direct) / total / CLOUD_DIRECT_SHARE_DAY if total > 0.0 else Vector2.ZERO
	w.x = 1.0 if sun_up >= 1.0 else lerpf(w.x, 1.0, clampf(sun_up, 0.0, 1.0))
	w = Vector2(w.x if w.x >= CLOUD_WEIGHT_FLOOR else 0.0, w.y if w.y >= CLOUD_WEIGHT_FLOOR else 0.0)
	return w / maxf(w.x + w.y, 1.0)


## FW-MOON-08a: the aureole's scale. Krisciunas & Schaefer (1991, PASP 103:1033) give the moon's scattered sky
## brightness as f(ρ)·I*·10^(−0.4·k·X_moon)·(1 − 10^(−0.4·k·X)), with a Rayleigh part 10^5.36·(1.06 + cos²ρ) (eq. 21)
## and an aerosol part 10^(6.15 − ρ/40), or 6.2·10⁷·ρ⁻² within 10° (eq. 19; ρ in degrees). This sky already draws the
## moonlit zenith (`moon_zenith`, render units), which KS91 puts at f(Z_moon)·I*·…·(1 − 10^(−0.4k)): the ratio fixes
## the render scale, and I* and the moon's extinction cancel. Returned: the aerosol part's coefficient,
## moon_zenith · 10^6.15 / f(Z_moon); the shader multiplies it by the angular shape and the path term.
static func moon_aureole(moon_zenith: Vector3, moon_elevation_deg: float) -> Vector3:
	var z := clampf(90.0 - moon_elevation_deg, 0.0, 180.0)
	var c := cos(deg_to_rad(z))
	var f := pow(10.0, 5.36) * (1.06 + c * c) + (pow(10.0, 6.15 - z / 40.0) if z >= 10.0 else 6.2e7 / maxf(z * z, 1.0))
	return moon_zenith * pow(10.0, 6.15) / f


## FW-MOON-03: the moon's photometric inputs. Real skies carry their place (Ephemeris.sky()), so Lunar supplies the
## exact phase, distance, sun direction and earthshine; hand-built test skies keep the original elongation phase.
static func _moon(sky: Dictionary) -> Dictionary:
	if sky.has("latitude_deg") and sky.has("jd"):
		var l := Lunar.at_jd(float(sky.jd), float(sky.latitude_deg), float(sky.longitude_deg))
		var sun_ned: PackedFloat64Array = l.sun_ned
		return {azimuth_deg = l.azimuth_deg, elevation_deg = l.elevation_deg, phase_angle_deg = l.phase_angle_deg,
			illuminated = l.illuminated, flux = l.flux, radius = deg_to_rad(l.radius_deg), earthshine = l.earthshine,
			sun_dir = Frames.ned_to_render([sun_ned[0], sun_ned[1], sun_ned[2]]).normalized(), lunar = l}
	var phase: float = sky.moon.phase_angle_deg
	return {azimuth_deg = sky.moon.azimuth_deg, elevation_deg = sky.moon.elevation_deg, phase_angle_deg = phase,
		illuminated = sky.moon.illuminated, flux = moon_phase_flux(phase), radius = MOON_MEAN_RADIUS_RAD,
		earthshine = 0.0, sun_dir = Vector3.ZERO, lunar = {}}


## Re-adapts to extra artificial irradiance (scene units, e.g. floodlights on the runway): the eye adapts to what it
## looks at, so a floodlit field lowers the exposure. Returns a copy of `state` with the new gain and exposure.
static func adapt(state: Dictionary, extra_irradiance: float) -> Dictionary:
	var out := state.duplicate()
	var y: float = float(state.adapt_y) + maxf(extra_irradiance, 0.0)
	out.gain = clampf(pow(float(state.adapt_y_anchor) / maxf(y, 1e-30), ADAPT_POWER), 1.0, ADAPT_MAX_GAIN)
	out.exposure = float(Spec.ATMOSPHERE.exposure) * out.gain
	out.artificial_irradiance = maxf(extra_irradiance, 0.0)
	return out


## The world's light and colour for a sky from Ephemeris.sky(). `moon_config`: MoonConfig choices (empty = defaults):
## "off" removes the moon's disc, light and sky glow; "large" doubles the disc; "bright" triples the moonlight.
static func state(sky: Dictionary, moon_config: Dictionary = {}) -> Dictionary:
	var a: Dictionary = Spec.ATMOSPHERE
	var anchor := row(ANCHOR_ELEVATION_DEG)
	var k_zenith := _ratio(_lin(a.zenith), anchor.zenith)
	var k_haze := _ratio(_lin(a.haze) * a.haze_energy, anchor.haze)
	var k_sun := _ratio(_lin(a.sun_color) * a.sun_energy, anchor.sun)

	var sun_el: float = sky.sun.elevation_deg
	var moon := _moon(sky)
	var moon_el: float = moon.elevation_deg
	var s := row(sun_el)
	var m := row(moon_el)
	# Moonlight: the phase law with the inverse-square distance (FW-MOON-03; Lunar.flux); FW-MOON-12 choices.
	var moon_on: bool = moon_config.get("moon", "real") != "off"
	var moon_k := MOON_FULL_RATIO * float(moon.flux) * (MOON_BRIGHT_FACTOR if moon_config.get("moonlight", "real") == "bright" else 1.0) \
		* (1.0 if moon_on else 0.0)
	# FW-MOON-10: an eclipse dims the moon's light and its sky by the shadow's transmission averaged over the disc.
	var eclipse: Dictionary = moon.lunar.get("eclipse", {}) if not moon.lunar.is_empty() else {}
	var eclipse_factor := Lunar.eclipse_disc_factor(eclipse)
	if eclipse_factor != Vector3.ONE:
		moon_k *= _lum(eclipse_factor)
	var tint := MOON_TINT * moon_k

	var floor_zenith := _lin(a.zenith) * NIGHT_FLOOR
	var zenith: Vector3 = k_zenith * (s.zenith + tint * m.zenith) + floor_zenith
	var haze: Vector3 = k_haze * (s.haze + tint * m.haze) + _lin(a.haze) * NIGHT_FLOOR

	# LU-13: luminance-preserving diffuse palette; astronomy/direct sun stay authoritative.
	zenith = TwilightPalette.diffuse(zenith, sun_el, TwilightPalette.ZENITH_TINT, 0.94)
	haze = TwilightPalette.diffuse(haze, sun_el, TwilightPalette.HAZE_TINT, 0.78)

	# One directional light: the brighter of sun and moon (the engine's fog scatter and the planar shadow follow it).
	var sun_rgb: Vector3 = k_sun * s.sun
	var moon_l := MOON_LIGHT_COLOR.srgb_to_linear()
	var moon_rgb: Vector3 = Vector3(moon_l.r, moon_l.g, moon_l.b) * _lum(k_sun * m.sun) * moon_k / _lum(Vector3(moon_l.r, moon_l.g, moon_l.b))
	var moon_lights := _lum(moon_rgb) > _lum(sun_rgb)
	var light_rgb: Vector3 = moon_rgb if moon_lights else sun_rgb
	var light_az: float = moon.azimuth_deg if moon_lights else sky.sun.azimuth_deg
	var light_el: float = moon_el if moon_lights else sun_el
	var energy := maxf(maxf(light_rgb.x, light_rgb.y), light_rgb.z)
	var light_color := Color(1, 1, 1)
	if energy > 0.0:
		var c := light_rgb / energy
		light_color = Color(c.x, c.y, c.z).linear_to_srgb()

	# The horizon lobe toward the brighter source (the twilight arch after sunset, the moon's glow at night).
	var sun_lobe: Vector3 = k_haze * s.lobe
	var moon_lobe: Vector3 = k_haze * m.lobe * tint
	var lobe_from_moon := _lum(moon_lobe) > _lum(sun_lobe)
	var lobe_az: float = moon.azimuth_deg if lobe_from_moon else sky.sun.azimuth_deg

	# Lit cloud: mostly the light reaching the deck (clouds stay lit after sunset), a little skylight.
	var cloud_rel: Vector3 = _ratio(s.cloud + tint * m.cloud, anchor.cloud)
	var cloud: Vector3 = _lin(a.cloud_color) * (cloud_rel * 0.8 + Vector3.ONE * 0.2 * _lum(zenith) / _lum(_lin(a.zenith)))
	# FW-MOON-06c: the sky shows both sources. The other source's lobe is drawn beside the brighter one, and each source
	# shades the clouds directionally in proportion to its directional share of their light (the 0.8 direct / 0.2 sky
	# split above): full shading by day, none in deep twilight when only the sky lights them, then the moon's.
	# Nothing in the sky flips when the light, the lobe or the cloud lighting passes between sun and moon.
	var other_lobe: Vector3 = sun_lobe if lobe_from_moon else moon_lobe
	if _lum(other_lobe) < CLOUD_WEIGHT_FLOOR * _lum(moon_lobe if lobe_from_moon else sun_lobe):
		other_lobe = Vector3.ZERO # invisible beside the other (a 10⁻⁶ moon by day): the day sky stays byte-identical
	var cloud_weights := cloud_light_weights(_lum(_ratio(s.cloud, anchor.cloud)) * 0.8,
		_lum(_ratio(tint * m.cloud, anchor.cloud)) * 0.8, 0.2 * _lum(zenith) / _lum(_lin(a.zenith)), sun_shadow_strength(sun_el))

	cloud = TwilightPalette.diffuse(cloud, sun_el, TwilightPalette.CLOUD_TINT, 0.30)

	# Ambient colour (see AMBIENT_ZENITH_SHARE): anchored to the engine's effective calibrated ambient.
	var mix_legacy := _lin(a.zenith) * AMBIENT_ZENITH_SHARE + _lin(a.haze) * (1.0 - AMBIENT_ZENITH_SHARE)
	var k_ambient := _ratio(_engine_linear_to_srgb(mix_legacy * float(a.exposure)), mix_legacy)
	var ambient: Vector3 = k_ambient * (zenith * AMBIENT_ZENITH_SHARE + haze * (1.0 - AMBIENT_ZENITH_SHARE))

	# Scripted adaptation from the scene's brightness: sky (with half the sunward lobe) plus direct light on the ground.
	var y_anchor := _lum(_lin(a.zenith)) + _lum(_lin(a.haze)) + 0.5 * _lum(k_haze * anchor.lobe) 		+ _lum(_lin(a.sun_color)) * sin(deg_to_rad(ANCHOR_ELEVATION_DEG))
	var lobe: Vector3 = moon_lobe if lobe_from_moon else sun_lobe
	var y := _lum(zenith) + _lum(haze) + 0.5 * _lum(lobe) + _lum(light_rgb) * maxf(sin(deg_to_rad(light_el)), 0.0)
	var gain := clampf(pow(y_anchor / maxf(y, 1e-30), ADAPT_POWER), 1.0, ADAPT_MAX_GAIN)

	# FW-MOON-03: the disc. Surface radiance, not the disc-integrated flux: K(α) restores the phase law; the colour is
	# the sky table's direct beam at the moon's elevation relative to the 45° anchor (the moon reddens like the sun).
	var phase: float = moon.phase_angle_deg
	# With the texture (real skies), the albedo map supplies the colour: the base keeps only MOON_DISC_COLOR's luminance.
	var base: Vector3 = Vector3.ONE * _lum(_lin(MOON_DISC_COLOR)) if not moon.lunar.is_empty() else _lin(MOON_DISC_COLOR)
	var moon_lin: Vector3 = base * MOON_DISC * _lum(_lin(a.zenith)) * _ratio(m.sun, anchor.sun) if moon_el > -1.0 and moon_on else Vector3.ZERO
	var sun_dir := direction(sky.sun.azimuth_deg, sun_el)
	# Shadows under the moon fade with the direct share of the light (a thin crescent's light is lost in the sky glow);
	# relative to that share for the anchored 45° sun. The sun keeps full-strength shadows while its disc is up, and
	# FW-MOON-06b fades them with its direct beam as the disc crosses the horizon (sun_shadow_strength), so the light
	# passes to the moon with no shadow on either side.
	var direct := _lum(light_rgb) * maxf(sin(deg_to_rad(light_el)), 0.0)
	var direct_anchor := _lum(_lin(a.sun_color)) * sin(deg_to_rad(ANCHOR_ELEVATION_DEG))
	var share := direct / maxf(direct + _lum(zenith) + _lum(haze), 1e-30)
	var share_anchor := direct_anchor / (direct_anchor + _lum(_lin(a.zenith)) + _lum(_lin(a.haze)))
	var shadow := smoothstep(MOON_SHADOW_SHARE_LOW, MOON_SHADOW_SHARE_HIGH, share / share_anchor) if moon_lights \
		else sun_shadow_strength(sun_el)
	# Reference: the unattenuated full moon (base × S0), so a low moon stays dimmer and redder than a high one.
	# The eye adapts to the moon as it is lit: in totality it opens to the dim copper disc; in partial phases the sunlit
	# part sets it and the umbra looks dark (FW-MOON-10).
	var excess := _lum(base) * MOON_DISC * _lum(_lin(a.zenith)) * float(a.exposure) * gain / MOON_DISPLAY_PEAK
	if eclipse_factor != Vector3.ONE:
		excess *= _lum(eclipse_factor)
	var display_scale := 1.0 / excess if excess > 1.0 else 1.0
	var display_gamma := lerpf(1.0, MOON_DISPLAY_GAMMA, smoothstep(0.0, log(100.0), log(maxf(excess, 1.0))))
	# FW-MOON-08a: the aureole, KS91's aerosol scattering around the moon, anchored to this sky's own moonlit zenith.
	var aureole := moon_aureole(k_zenith * tint * m.zenith, moon_el) if moon_el > -1.0 else Vector3.ZERO
	if eclipse_factor != Vector3.ONE: # FW-MOON-10: the glow scatters the eclipsed moon's light: copper in totality
		aureole *= eclipse_factor / maxf(_lum(eclipse_factor), 1e-30)
	if _lum(aureole) < AUREOLE_FLOOR * _lum(zenith):
		aureole = Vector3.ZERO # a 10⁻⁶ moon by day: invisible, and the day sky stays byte-identical

	return {
		sun_azimuth_deg = sky.sun.azimuth_deg, sun_elevation_deg = sun_el,
		moon_azimuth_deg = moon.azimuth_deg, moon_elevation_deg = moon_el,
		moon_illuminated = moon.illuminated,
		light_source = "moon" if moon_lights else "sun",
		light_dir = direction(light_az, light_el),
		light_elevation_deg = light_el,
		light_color = light_color,
		light_energy = energy,
		zenith_lin = zenith,
		haze_lin = haze,
		lobe_lin = lobe,
		lobe_dir = direction(lobe_az, 0.0),
		lobe_k = m.lobe_k if lobe_from_moon else s.lobe_k,
		lobe_height = deg_to_rad(m.lobe_height_deg if lobe_from_moon else s.lobe_height_deg),
		sky_lobe2_lin = other_lobe,
		sky_lobe2_dir = direction(sky.sun.azimuth_deg if lobe_from_moon else moon.azimuth_deg, 0.0),
		sky_lobe2_k = s.lobe_k if lobe_from_moon else m.lobe_k,
		sky_lobe2_height = deg_to_rad(s.lobe_height_deg if lobe_from_moon else m.lobe_height_deg),
		cloud_light2_dir = direction(sky.sun.azimuth_deg, sun_el) if moon_lights else direction(moon.azimuth_deg, moon_el),
		cloud_light1_weight = cloud_weights.y if moon_lights else cloud_weights.x,
		cloud_light2_weight = cloud_weights.x if moon_lights else cloud_weights.y,
		cloud_lin = cloud,
		ambient_lin = ambient,
		exposure = float(a.exposure) * gain,
		gain = gain,
		adapt_y = y,
		adapt_y_anchor = y_anchor,
		sun_dir = sun_dir,
		sun_disc = 1.0 if not moon_lights else 0.0,
		moon_dir = direction(moon.azimuth_deg, moon_el),
		moon_lin = moon_lin,
		moon_radius = float(moon.radius) * (MOON_LARGE_FACTOR if moon_config.get("size", "real") == "large" else 1.0),
		moon_sun_dir = moon.sun_dir if moon.sun_dir != Vector3.ZERO else sun_dir,
		moon_phase_angle_deg = phase,
		moon_phase_l = lunar_lambert_l(phase),
		moon_phase_k = moon_phase_flux(phase) / maxf(lunar_lambert_integral(phase), 1e-6),
		moon_earthshine = EARTHSHINE_TINT * float(moon.earthshine),
		moon_display_scale = display_scale,
		moon_display_gamma = display_gamma,
		moon_aureole_lin = aureole,
		moon_eclipse = eclipse_factor != Vector3.ONE,
		moon_eclipse_factor = eclipse_factor,
		moon_shadow_axis = Frames.ned_to_render(Array(eclipse.get("axis_ned", PackedFloat64Array([0.0, 0.0, 1.0])))),
		moon_shadow_offset = Frames.ned_to_render(Array(eclipse.get("offset_ned", PackedFloat64Array([0.0, 0.0, 0.0])))),
		moon_umbra_radius = float(eclipse.get("umbra_radius", 0.0)),
		moon_penumbra_radius = float(eclipse.get("penumbra_radius", 0.0)),
		moon_render_to_body = moon_render_to_body(moon.lunar),
		moon_squash = moon_squash(float(moon.lunar.true_elevation_deg)) if not moon.lunar.is_empty() else 1.0,
		moon_textured = not moon.lunar.is_empty(),
		moon_flux = moon.flux,
		lunar = moon.lunar,
		moon_config = moon_config.duplicate(),
		shadow_strength = shadow,
		lst_deg = sky.lst_deg,
		tonemapper = "agx" if sun_el < AGX_BELOW_SUN_DEG else "aces",
	}

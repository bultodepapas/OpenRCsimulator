# FIELD-WORLD-PLAN FW-22/FW-23: time of day → the numbers the sky shader, the haze (engine fog and the ground's own
# fog), the directional light and the exposure use. Input: Ephemeris.sky(). Output: one Dictionary that
# render/atmosphere.gd reads instead of its fixed 45° constants.
#
# Physics from app/data/sky/sky_table.json (tools/world/sky_table.py): relative zenith, horizon haze, sunward horizon
# lobe, direct-sun and cloud-deck transmittance per sun elevation. They are ANCHORED at 45° to Spec.ATMOSPHERE's
# calibrated look (L1a/L1b/L2/L3), so the model only decides how colours change with the hour, never the day look.
# The moon lights the same atmosphere, scaled by its brightness relative to the sun (phase law below).
extends RefCounted

const Spec := preload("res://spec.gd")
const Frames := preload("res://render/frames.gd")

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
## Δm = 0.026·|ψ| + 4·10⁻⁹·ψ⁴ (borrowed, Astrophysical Quantities).
static func moon_phase_flux(phase_angle_deg: float) -> float:
	var psi := absf(phase_angle_deg)
	return pow(10.0, -0.4 * (0.026 * psi + 4.0e-9 * pow(psi, 4.0)))


## Re-adapts to extra artificial irradiance (scene units, e.g. floodlights on the runway): the eye adapts to what it
## looks at, so a floodlit field lowers the exposure. Returns a copy of `state` with the new gain and exposure.
static func adapt(state: Dictionary, extra_irradiance: float) -> Dictionary:
	var out := state.duplicate()
	var y: float = float(state.adapt_y) + maxf(extra_irradiance, 0.0)
	out.gain = clampf(pow(float(state.adapt_y_anchor) / maxf(y, 1e-30), ADAPT_POWER), 1.0, ADAPT_MAX_GAIN)
	out.exposure = float(Spec.ATMOSPHERE.exposure) * out.gain
	out.artificial_irradiance = maxf(extra_irradiance, 0.0)
	return out


## The world's light and colour for a sky from Ephemeris.sky().
static func state(sky: Dictionary) -> Dictionary:
	var a: Dictionary = Spec.ATMOSPHERE
	var anchor := row(ANCHOR_ELEVATION_DEG)
	var k_zenith := _ratio(_lin(a.zenith), anchor.zenith)
	var k_haze := _ratio(_lin(a.haze) * a.haze_energy, anchor.haze)
	var k_sun := _ratio(_lin(a.sun_color) * a.sun_energy, anchor.sun)

	var sun_el: float = sky.sun.elevation_deg
	var moon_el: float = sky.moon.elevation_deg
	var s := row(sun_el)
	var m := row(moon_el)
	var moon_k := MOON_FULL_RATIO * moon_phase_flux(sky.moon.phase_angle_deg)
	var tint := MOON_TINT * moon_k

	var floor_zenith := _lin(a.zenith) * NIGHT_FLOOR
	var zenith: Vector3 = k_zenith * (s.zenith + tint * m.zenith) + floor_zenith
	var haze: Vector3 = k_haze * (s.haze + tint * m.haze) + _lin(a.haze) * NIGHT_FLOOR

	# One directional light: the brighter of sun and moon (the engine's fog scatter and the planar shadow follow it).
	var sun_rgb: Vector3 = k_sun * s.sun
	var moon_l := MOON_LIGHT_COLOR.srgb_to_linear()
	var moon_rgb: Vector3 = Vector3(moon_l.r, moon_l.g, moon_l.b) * _lum(k_sun * m.sun) * moon_k / _lum(Vector3(moon_l.r, moon_l.g, moon_l.b))
	var moon_lights := _lum(moon_rgb) > _lum(sun_rgb)
	var light_rgb: Vector3 = moon_rgb if moon_lights else sun_rgb
	var light_az: float = sky.moon.azimuth_deg if moon_lights else sky.sun.azimuth_deg
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
	var lobe_az: float = sky.moon.azimuth_deg if lobe_from_moon else sky.sun.azimuth_deg

	# Lit cloud: mostly the light reaching the deck (clouds stay lit after sunset), a little skylight.
	var cloud_rel: Vector3 = _ratio(s.cloud + tint * m.cloud, anchor.cloud)
	var cloud: Vector3 = _lin(a.cloud_color) * (cloud_rel * 0.8 + Vector3.ONE * 0.2 * _lum(zenith) / _lum(_lin(a.zenith)))

	# Ambient colour (see AMBIENT_ZENITH_SHARE): anchored to the engine's effective calibrated ambient.
	var mix_legacy := _lin(a.zenith) * AMBIENT_ZENITH_SHARE + _lin(a.haze) * (1.0 - AMBIENT_ZENITH_SHARE)
	var k_ambient := _ratio(_engine_linear_to_srgb(mix_legacy * float(a.exposure)), mix_legacy)
	var ambient: Vector3 = k_ambient * (zenith * AMBIENT_ZENITH_SHARE + haze * (1.0 - AMBIENT_ZENITH_SHARE))

	# Scripted adaptation from the scene's brightness: sky (with half the sunward lobe) plus direct light on the ground.
	var y_anchor := _lum(_lin(a.zenith)) + _lum(_lin(a.haze)) + 0.5 * _lum(k_haze * anchor.lobe) 		+ _lum(_lin(a.sun_color)) * sin(deg_to_rad(ANCHOR_ELEVATION_DEG))
	var lobe: Vector3 = moon_lobe if lobe_from_moon else sun_lobe
	var y := _lum(zenith) + _lum(haze) + 0.5 * _lum(lobe) + _lum(light_rgb) * maxf(sin(deg_to_rad(light_el)), 0.0)
	var gain := clampf(pow(y_anchor / maxf(y, 1e-30), ADAPT_POWER), 1.0, ADAPT_MAX_GAIN)

	return {
		sun_azimuth_deg = sky.sun.azimuth_deg, sun_elevation_deg = sun_el,
		moon_azimuth_deg = sky.moon.azimuth_deg, moon_elevation_deg = moon_el,
		moon_illuminated = sky.moon.illuminated,
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
		cloud_lin = cloud,
		ambient_lin = ambient,
		exposure = float(a.exposure) * gain,
		gain = gain,
		adapt_y = y,
		adapt_y_anchor = y_anchor,
		sun_dir = direction(sky.sun.azimuth_deg, sun_el),
		sun_disc = 1.0 if not moon_lights else 0.0,
		moon_dir = direction(sky.moon.azimuth_deg, moon_el),
		moon_lin = _lin(Color(0.98, 0.96, 0.92)) * (MOON_DISC * _lum(_lin(a.zenith)) * moon_phase_flux(sky.moon.phase_angle_deg)) \
			if moon_el > -1.0 else Vector3.ZERO,
		lst_deg = sky.lst_deg,
		tonemapper = "agx" if sun_el < AGX_BELOW_SUN_DEG else "aces",
	}

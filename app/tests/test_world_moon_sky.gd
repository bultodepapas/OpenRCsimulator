# FW-MOON-03: the moon in SkyState. The disc's lunar-Lambert normalisation reproduces the KS91 phase law when
# integrated over the disc (the same formula moon_disc.gdshaderinc evaluates per pixel); the disc size follows the
# distance; its colour reddens toward the horizon like the sun's direct beam; earthshine fades toward full moon;
# moon shadows fade with the phase; the sun and hand-built test skies keep their previous behaviour.
# Run: godot --headless --path . --script res://tests/test_world_moon_sky.gd
extends SceneTree

const Conditions := preload("res://render/world/conditions.gd")
const Ephemeris := preload("res://render/world/ephemeris.gd")
const Lunar := preload("res://render/world/lunar.gd")
const SkyState := preload("res://render/world/sky_state.gd")
const Atmosphere := preload("res://render/atmosphere.gd")

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


static func _lum(v: Vector3) -> float:
	return 0.2126 * v.x + 0.7152 * v.y + 0.0722 * v.z


func _state(args: Array) -> Dictionary:
	var c := Conditions.resolve(PackedStringArray(args))
	return SkyState.state(Ephemeris.sky(c.when))


## The shader's per-pixel pattern integrated over the disc (viewer on +z, sun at `phase` from the viewer), / π.
static func _disc_integral(phase_deg: float, n: int) -> float:
	var a := deg_to_rad(phase_deg)
	var sun := Vector3(sin(a), 0.0, cos(a))
	var l := SkyState.lunar_lambert_l(phase_deg)
	var k := SkyState.moon_phase_flux(phase_deg) / SkyState.lunar_lambert_integral(phase_deg)
	var total := 0.0
	for i in n:
		for j in n:
			var x := -1.0 + (i + 0.5) * 2.0 / n
			var y := -1.0 + (j + 0.5) * 2.0 / n
			var r2 := x * x + y * y
			if r2 >= 1.0:
				continue
			var mu := sqrt(1.0 - r2)
			var mu0 := maxf(Vector3(x, y, mu).dot(sun), 0.0)
			total += k * (2.0 * l * mu0 / maxf(mu0 + mu, 1e-4) + (1.0 - l) * mu0)
	return total * pow(2.0 / n, 2.0) / PI


func _initialize() -> void:
	# 1. Normalisation: K(α)·r integrated over the disc equals the KS91 phase law.
	for phase: float in [0.0, 30.0, 60.0, 90.0, 120.0, 150.0]:
		var got := _disc_integral(phase, 160)
		var want := SkyState.moon_phase_flux(phase)
		_check("disc integral follows KS91 at %d°" % phase, absf(got / want - 1.0) < 0.01, "%.5f vs %.5f" % [got, want])
	_check("L(0) = 1 (flat full moon)", SkyState.lunar_lambert_l(0.0) == 1.0)
	_check("L clamps to 0 at large phase", SkyState.lunar_lambert_l(130.0) == 0.0)

	# 2. Real skies at the reference field (40° N, 3.7° W, UTC+2).
	var full := _state(["--time=00:00", "--date=2026-12-24"])
	var harvest_low := _state(["--time=20:25", "--date=2026-09-26"])
	var harvest_high := _state(["--time=23:30", "--date=2026-09-26"])
	var crescent := _state(["--time=23:15", "--date=2026-06-18"])
	var quarter := _state(["--time=00:30", "--date=2026-06-23"])
	# The full moon near apogee that the night preset showed before FW-MOON-11 retargeted it (FW-MOON-00 audit).
	var apogee_night := _state(["--time=01:15", "--date=2026-06-30"])
	for pair: Array in [["full", full], ["harvest low", harvest_low], ["crescent", crescent], ["quarter", quarter]]:
		var st: Dictionary = pair[1]
		_check("%s: the moon lights the night" % pair[0], st.light_source == "moon", str(st.light_source))
		_check("%s: disc drawn" % pair[0], (st.moon_lin as Vector3).length() > 0.0)
		var l: Dictionary = st.lunar
		_check("%s: disc radius from the topocentric distance" % pair[0],
			absf(float(st.moon_radius) - asin(Lunar.MOON_RADIUS_KM / float(l.distance_km))) < 1e-9)
	_check("perigee full moon looks larger than the apogee full moon",
		float(full.moon_radius) / float(apogee_night.moon_radius) > 1.10, "%f / %f" % [full.moon_radius, apogee_night.moon_radius])
	_check("near full: phase normalisation about 1", absf(float(full.moon_phase_k) - 1.0) < 0.1, str(full.moon_phase_k))

	# 3. Colour: near the horizon the disc is red/orange; high up it is near white (sky table direct beam).
	var low: Vector3 = harvest_low.moon_lin
	var high: Vector3 = harvest_high.moon_lin
	_check("low moon is redder", low.x / low.z > 2.0 * high.x / high.z, "%s vs %s" % [low, high])
	_check("low moon is dimmer", low.y < high.y)

	# 4. Earthshine: brightest on the crescent, fading through quarter to almost nothing at full moon.
	var es_crescent := (crescent.moon_earthshine as Vector3).y
	var es_quarter := (quarter.moon_earthshine as Vector3).y
	var es_full := (full.moon_earthshine as Vector3).y
	_check("earthshine order crescent > quarter > full", es_crescent > es_quarter and es_quarter > es_full * 10.0,
		"%s %s %s" % [es_crescent, es_quarter, es_full])
	_check("earthshine stays faint (< 4e-4 of full sunlight)", es_crescent < 4e-4, str(es_crescent))
	_check("earthshine is bluish", (crescent.moon_earthshine as Vector3).z > (crescent.moon_earthshine as Vector3).x)

	# 5. Shadows: a high full moon casts them, a crescent's light is lost in the sky glow, the sun is unchanged.
	print("  shadow strength: full %.3f, harvest high %.3f, quarter %.3f, crescent %.3f" % [full.shadow_strength,
		harvest_high.shadow_strength, quarter.shadow_strength, crescent.shadow_strength])
	_check("high full moon: full shadows", float(full.shadow_strength) > 0.95, str(full.shadow_strength))
	_check("crescent: shadows faded", float(crescent.shadow_strength) < float(full.shadow_strength) * 0.5, str(crescent.shadow_strength))
	var noon := _state(["--time_of_day=noon"])
	var golden := _state(["--time_of_day=golden_hour"])
	_check("sun shadows unchanged (noon)", float(noon.shadow_strength) == 1.0)
	_check("sun shadows unchanged (golden hour)", float(golden.shadow_strength) == 1.0)
	Atmosphere.state = full
	_check("Atmosphere reports the moon's shadow strength in field-world mode",
		Atmosphere.shadow_strength() == float(full.shadow_strength))
	Atmosphere.state = {}
	_check("calibrated scene keeps full shadows", Atmosphere.shadow_strength() == 1.0)

	# 6. Local adaptation: at night the disc is scaled into display range and its illumination compressed; by day the
	# disc stays physical (a pale moon in the afternoon sky).
	var day_moon := _state(["--time=19:00", "--date=2026-06-21"])
	_check("afternoon moon is up and the sun lights the scene", float(day_moon.moon_elevation_deg) > 10.0 and day_moon.light_source == "sun")
	_check("day: physical disc", float(day_moon.moon_display_scale) == 1.0 and float(day_moon.moon_display_gamma) == 1.0,
		"%s %s" % [day_moon.moon_display_scale, day_moon.moon_display_gamma])
	_check("night: disc scaled into display range", float(full.moon_display_scale) < 0.1, str(full.moon_display_scale))
	_check("night: illumination compressed", absf(float(full.moon_display_gamma) - SkyState.MOON_DISPLAY_GAMMA) < 1e-6, str(full.moon_display_gamma))
	var beam: Vector3 = SkyState.row(float(full.moon_elevation_deg)).sun
	var beam_anchor: Vector3 = SkyState.row(SkyState.ANCHOR_ELEVATION_DEG).sun
	var transmit := _lum(Vector3(beam.x / beam_anchor.x, beam.y / beam_anchor.y, beam.z / beam_anchor.z))
	var full_display := _lum(full.moon_lin) * float(full.exposure) * float(full.moon_display_scale) / transmit
	_check("night: the unattenuated full moon lands at the display peak", absf(full_display - SkyState.MOON_DISPLAY_PEAK) < 1e-4, str(full_display))
	var low_display := _lum(harvest_low.moon_lin) * float(harvest_low.exposure) * float(harvest_low.moon_display_scale)
	var high_display := _lum(harvest_high.moon_lin) * float(harvest_high.exposure) * float(harvest_high.moon_display_scale)
	_check("a low moon stays dimmer on screen than a high one", low_display < 0.6 * high_display, "%f vs %f" % [low_display, high_display])

	# 7. FW-MOON-05 orientation: the render→Moon-fixed rotation sends the direction from the moon to the observer to
	# the sub-observer point (libration) and the direction to the sun to the sub-solar point.
	for pair: Array in [["full", full], ["crescent", crescent], ["quarter", quarter], ["southern", _state(["--date=2026-08-27",
			"--time=23:50", "--lat=-34.6037", "--lon=-58.3816", "--utc_offset=-3"])]]:
		var st: Dictionary = pair[1]
		var b: Basis = st.moon_render_to_body
		_check("%s: rotation is orthonormal" % pair[0], b.is_equal_approx(b.orthonormalized()) and absf(b.determinant() - 1.0) < 1e-5)
		var to_observer := b * (-(st.moon_dir as Vector3))
		var l: Dictionary = st.lunar
		_check("%s: observer direction lands on the libration point" % pair[0],
			absf(rad_to_deg(atan2(to_observer.y, to_observer.x)) - float(l.libration_lon_deg)) < 0.05
			and absf(rad_to_deg(asin(to_observer.z)) - float(l.libration_lat_deg)) < 0.05,
			"%s vs %s %s" % [to_observer, l.libration_lon_deg, l.libration_lat_deg])
		var to_sun := b * (st.moon_sun_dir as Vector3)
		_check("%s: sun direction lands on the sub-solar point" % pair[0],
			absf(rad_to_deg(atan2(to_sun.y, to_sun.x)) - float(l.subsolar_lon_deg)) < 0.05
			and absf(rad_to_deg(asin(to_sun.z)) - float(l.subsolar_lat_deg)) < 0.05)
		_check("%s: textured" % pair[0], bool(st.moon_textured))
	_check("squash on the horizon ~0.86 (Young: 5/6)", absf(SkyState.moon_squash(0.0) - 0.86) < 0.01, str(SkyState.moon_squash(0.0)))
	_check("squash at 5° ~0.975", absf(SkyState.moon_squash(5.0) - 0.975) < 0.01, str(SkyState.moon_squash(5.0)))
	_check("no squash high up", absf(SkyState.moon_squash(40.0) - 1.0) < 0.002, str(SkyState.moon_squash(40.0)))

	# 8. Hand-built skies (no place) keep the original moon path.
	var hand := SkyState.state({sun = {azimuth_deg = 225.0, elevation_deg = -20.0},
		moon = {azimuth_deg = 180.0, elevation_deg = 30.0, illuminated = 1.0, phase_angle_deg = 0.0}, lst_deg = 0.0})
	_check("hand-built sky: mean radius", float(hand.moon_radius) == SkyState.MOON_MEAN_RADIUS_RAD)
	_check("hand-built sky: no earthshine", (hand.moon_earthshine as Vector3) == Vector3.ZERO)
	_check("hand-built sky: original phase flux", is_equal_approx(float(hand.moon_flux), SkyState.moon_phase_flux(0.0)))
	_check("deterministic", str(_state(["--time=01:15", "--date=2026-06-30"])) == str(apogee_night)
		and str(_state(["--time_of_day=night"])) == str(_state(["--time_of_day=night"])))

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)

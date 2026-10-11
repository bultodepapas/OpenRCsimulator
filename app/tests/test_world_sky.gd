# FW-03/FW-21/FW-22/FW-23: conditions resolve to the right hour; the sky table is anchored to the calibrated 45° look;
# light, haze and exposure change with the hour as the physics says; no time keeps the legacy atmosphere untouched.
# Run: godot --headless --path . --script res://tests/test_world_sky.gd [-- --verbose]
extends SceneTree

const Spec := preload("res://spec.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const Conditions := preload("res://render/world/conditions.gd")
const Ephemeris := preload("res://render/world/ephemeris.gd")
const SkyState := preload("res://render/world/sky_state.gd")

var _failures := 0
var _count := 0
var _verbose := false


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _lin(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	return Vector3(l.r, l.g, l.b)


func _lum(v: Vector3) -> float:
	return 0.2126 * v.x + 0.7152 * v.y + 0.0722 * v.z


func _preset(name: String) -> Dictionary:
	var c := Conditions.resolve(PackedStringArray(["--time_of_day=" + name]))
	var sky := Ephemeris.sky(c.when)
	var st := SkyState.state(sky)
	if _verbose:
		print("%-12s %5.2f h  sun el %6.2f  moon el %6.2f (%.2f lit)  light %s %s %s  zenith %s haze %s lobe %s  gain %.0f  exposure %.2f" % [
			name, c.when.hour, sky.sun.elevation_deg, sky.moon.elevation_deg, sky.moon.illuminated, st.light_source,
			String.num_scientific(st.light_energy), st.light_color.to_html(false), String.num_scientific(_lum(st.zenith_lin)),
			String.num_scientific(_lum(st.haze_lin)), String.num_scientific(_lum(st.lobe_lin)), st.gain, st.exposure])
	return {conditions = c, sky = sky, state = st}


func _initialize() -> void:
	_verbose = OS.get_cmdline_user_args().has("--verbose")

	# No time chosen: the calibrated fixed sun, untouched.
	_check("no arguments → fixed sun", not Conditions.resolve(PackedStringArray()).time_of_day)
	_check("unknown preset → fixed sun", not Conditions.resolve(PackedStringArray(["--time_of_day=teatime"])).time_of_day)
	_check("bad clock → fixed sun", not Conditions.resolve(PackedStringArray(["--time=25h"])).time_of_day)
	Atmosphere.state = {}
	var a: Dictionary = Spec.ATMOSPHERE
	_check("legacy sun direction unchanged", Atmosphere.sun_direction() == SkyState.direction(a.sun_azimuth_deg, a.sun_elevation_deg))
	_check("legacy shadow direction is the sun direction at 45°", Atmosphere.shadow_direction() == Atmosphere.sun_direction())
	_check("legacy haze scatter unchanged", Atmosphere.sun_scatter() == a.sun_scatter)

	# Explicit clock and place.
	var c := Conditions.resolve(PackedStringArray(["--time=21:30", "--date=2026-08-12", "--lat=42.3", "--lon=-3.7", "--utc_offset=2"]))
	_check("explicit time parsed", c.time_of_day and is_equal_approx(c.when.hour, 21.5) and c.when.month == 8 and c.when.latitude_deg == 42.3, str(c))

	# Anchor: a sun exactly at 45° reproduces Spec.ATMOSPHERE (the day look is calibrated, the model gives only change).
	var anchor := SkyState.state({sun = {azimuth_deg = 225.0, elevation_deg = 45.0},
		moon = {azimuth_deg = 0.0, elevation_deg = -30.0, illuminated = 0.0, phase_angle_deg = 180.0}, lst_deg = 0.0})
	_check("anchor zenith = Spec zenith", (anchor.zenith_lin as Vector3).is_equal_approx(_lin(a.zenith) * (1.0 + SkyState.NIGHT_FLOOR)), str(anchor.zenith_lin))
	_check("anchor haze = Spec haze", (anchor.haze_lin as Vector3).distance_to(_lin(a.haze)) < 1e-5, str(anchor.haze_lin))
	_check("anchor light = Spec sun colour, energy 1", absf(anchor.light_energy - 1.0) < 1e-5
		and anchor.light_color.is_equal_approx(a.sun_color), "%s %f" % [anchor.light_color.to_html(), anchor.light_energy])
	_check("anchor exposure = Spec exposure", absf(anchor.exposure - a.exposure) < 1e-3, str(anchor.exposure))
	_check("anchor light is the sun", anchor.light_source == "sun")

	# The day through the presets.
	var noon := _preset("noon")
	var morning := _preset("morning")
	var golden := _preset("golden_hour")
	var sunset := _preset("sunset")
	var blue := _preset("blue_hour")
	var dawn := _preset("dawn")
	var night := _preset("night")
	var dark := _preset("night_dark")
	_check("noon is solar noon (~14:16 CEST at 3.7° W)", absf(noon.conditions.when.hour - 14.27) < 0.1, str(noon.conditions.when.hour))
	_check("noon sun ~73.4° high", absf(noon.sky.sun.elevation_deg - 73.4) < 0.2, str(noon.sky.sun.elevation_deg))
	_check("golden hour solved to 6°", absf(golden.sky.sun.elevation_deg - 6.0) < 0.02, str(golden.sky.sun.elevation_deg))
	_check("blue hour solved to −4°", absf(blue.sky.sun.elevation_deg + 4.0) < 0.02, str(blue.sky.sun.elevation_deg))
	_check("dawn is in the morning, blue hour in the evening", dawn.conditions.when.hour < 7.0 and blue.conditions.when.hour > 21.0)
	_check("morning sun in the east", morning.sky.sun.azimuth_deg > 45.0 and morning.sky.sun.azimuth_deg < 120.0, str(morning.sky.sun.azimuth_deg))
	_check("night preset: full moon (2026-06-29)", night.sky.moon.illuminated > 0.95, str(night.sky.moon.illuminated))
	_check("night_dark preset: new moon (2026-06-15)", dark.sky.moon.illuminated < 0.05, str(dark.sky.moon.illuminated))
	_check("night is astronomically dark", night.sky.sun.elevation_deg < -18.0 and dark.sky.sun.elevation_deg < -18.0)

	var lum_noon := _lum(noon.state.zenith_lin)
	_check("sunset light is red", sunset.state.light_color.r > 2.0 * sunset.state.light_color.b, sunset.state.light_color.to_html())
	_check("sunset light weaker than golden hour, weaker than noon",
		sunset.state.light_energy < golden.state.light_energy and golden.state.light_energy < noon.state.light_energy)
	_check("golden-hour haze warmer than noon haze",
		golden.state.haze_lin.x / golden.state.haze_lin.z > noon.state.haze_lin.x / noon.state.haze_lin.z)
	_check("blue hour: no direct sun", blue.state.light_source == "moon" or blue.state.light_energy < 1e-6)
	_check("blue hour sky ≥ 100× darker than noon, still blue", _lum(blue.state.zenith_lin) < lum_noon / 100.0
		and blue.state.zenith_lin.z > blue.state.zenith_lin.x)
	_check("blue hour twilight arch toward the sun", _lum(blue.state.lobe_lin) > _lum(blue.state.haze_lin))
	_check("exposure rises as light falls", noon.state.gain <= golden.state.gain and golden.state.gain < blue.state.gain
		and blue.state.gain <= dark.state.gain)
	_check("full-moon night lit by the moon", night.state.light_source == "moon" and night.state.light_energy > 0.0)
	_check("moonlight ~10⁻⁶ of noon sun", night.state.light_energy < noon.state.light_energy * 1e-5 and night.state.light_energy > noon.state.light_energy * 1e-8,
		"%s vs %s" % [String.num_scientific(night.state.light_energy), String.num_scientific(noon.state.light_energy)])
	_check("moonlit night brighter than moonless", _lum(night.state.zenith_lin) > 10.0 * _lum(dark.state.zenith_lin))
	_check("moonless night hits the adaptation limit", is_equal_approx(dark.state.gain, SkyState.ADAPT_MAX_GAIN))
	_check("moon disc drawn when up, not when down", (night.state.moon_lin as Vector3).length() > 0.0)
	_check("sun disc off while the moon lights", night.state.sun_disc == 0.0 and noon.state.sun_disc == 1.0)
	_check("AgX at night and in the blue hour, ACES by day and at sunset (L1b calibration)",
		night.state.tonemapper == "agx" and blue.state.tonemapper == "agx" and noon.state.tonemapper == "aces" and sunset.state.tonemapper == "aces")

	# Bounded planar shadow at a low sun.
	Atmosphere.state = sunset.state
	var sd := Atmosphere.shadow_direction()
	_check("low sun: shadow elevation held at 12°", absf(rad_to_deg(asin(sd.y)) - Atmosphere.SHADOW_MIN_ELEVATION_DEG) < 1e-4 and absf(sd.length() - 1.0) < 1e-5, str(sd))
	_check("time of day: engine fog scatter off (lobe drawn by sky and ground)", Atmosphere.sun_scatter() == 0.0)
	Atmosphere.state = {}

	# Determinism.
	_check("same conditions, same state", str(SkyState.state(Ephemeris.sky(night.conditions.when))) == str(night.state))
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)

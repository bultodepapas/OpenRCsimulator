# FW-MOON-12: moon choices. Validation refuses anything but a complete, known configuration; precedence is command
# line > environment > session > defaults; a phase choice moves the date to the nearest night with that phase at the
# same clock time; "off", "large" and "bright" change exactly the disc, its size and the moonlight.
# Run: godot --headless --path . --script res://tests/test_world_moon_config.gd
extends SceneTree

const MoonConfig := preload("res://environment/moon_config.gd")
const Conditions := preload("res://render/world/conditions.gd")
const Ephemeris := preload("res://render/world/ephemeris.gd")
const SkyState := preload("res://render/world/sky_state.gd")
const Preferences := preload("res://app_state/preferences.gd")

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	# Validation.
	_check("defaults validate", MoonConfig.validate(MoonConfig.defaults()).ok)
	var missing := MoonConfig.defaults()
	missing.erase("halo")
	_check("missing key refused", not MoonConfig.validate(missing).ok)
	var extra := MoonConfig.defaults()
	extra.colour = "pink"
	_check("extra key refused", not MoonConfig.validate(extra).ok)
	var bad := MoonConfig.defaults()
	bad.night_look = "neon"
	_check("unknown value refused", not MoonConfig.validate(bad).ok)
	var wrong_format := MoonConfig.defaults()
	wrong_format.format = "openrc-moon-config v0"
	_check("wrong format refused", not MoonConfig.validate(wrong_format).ok)
	_check("non-dictionary refused", not MoonConfig.validate("full").ok)
	_check("default is the real moon", MoonConfig.defaults().moon == "real" and MoonConfig.defaults().size == "real"
		and MoonConfig.defaults().moonlight == "real")

	# Precedence: defaults < session < command line (environment is the same mechanism, not changed here).
	MoonConfig.session_config = {}
	_check("no arguments: defaults", MoonConfig.resolve(PackedStringArray()) == MoonConfig.defaults())
	var saved := MoonConfig.defaults()
	saved.moon = "off"
	saved.size = "large"
	MoonConfig.session_config = saved
	var from_session := MoonConfig.resolve(PackedStringArray())
	_check("session applies", from_session.moon == "off" and from_session.size == "large")
	var cli := MoonConfig.resolve(PackedStringArray(["--moon=phase:first_quarter", "--moonlight=bright", "--night-look=camera"]))
	_check("command line wins", cli.moon == "phase" and cli.phase == "first_quarter" and cli.moonlight == "bright"
		and cli.night_look == "camera" and cli.size == "large", str(cli))
	var bad_cli := MoonConfig.resolve(PackedStringArray(["--moon=phase:gibbous", "--moon-size=huge"]))
	_check("bad command-line values keep the previous layer", bad_cli.moon == "off" and bad_cli.size == "large", str(bad_cli))
	var broken_session := MoonConfig.defaults()
	broken_session.halo = "rainbow"
	MoonConfig.session_config = broken_session
	_check("an invalid session is ignored as a whole", MoonConfig.resolve(PackedStringArray()) == MoonConfig.defaults())
	MoonConfig.session_config = {}

	# Phase choice: nearest night with that phase, same clock time, at most 15 days away.
	var base := {year = 2026, month = 6, day = 21, hour = 22.5, utc_offset_h = 2.0, latitude_deg = 40.0, longitude_deg = -3.7}
	var jd_base := Ephemeris.julian_day(2026, 6, 21, 22.5 - 2.0)
	for phase: String in MoonConfig.PHASES:
		var config := MoonConfig.defaults()
		config.moon = "phase"
		config.phase = phase
		var when := MoonConfig.apply_phase(base, config)
		var jd := Ephemeris.julian_day(int(when.year), int(when.month), int(when.day), float(when.hour) - 2.0)
		var age := MoonConfig.age_deg(jd)
		var error := absf(fposmod(age - float(MoonConfig.PHASE_ELONGATION[phase]) + 180.0, 360.0) - 180.0)
		_check("%s: age within 7° of the target" % phase, error <= 7.0, "age %.1f" % age)
		_check("%s: within 15 days, same clock" % phase, absf(jd - jd_base) <= 15.0 + 1e-6 and when.hour == 22.5,
			"%s" % [when])
		_check("%s: the name of that age is the phase" % phase, MoonConfig.phase_name(age) == phase, MoonConfig.phase_name(age))
	_check("real moon keeps the date", MoonConfig.apply_phase(base, MoonConfig.defaults()) == base)
	var full := MoonConfig.defaults()
	full.moon = "phase"
	var full_when := MoonConfig.apply_phase(base, full)
	_check("full moon after the 21 June first quarter is 29/30 June 2026", full_when.month == 6 and full_when.day in [29, 30], str(full_when))

	# Rendering effects at the full-moon night preset.
	var night := Conditions.resolve(PackedStringArray(["--time_of_day=night"]))
	var sky := Ephemeris.sky(night.when)
	var real := SkyState.state(sky, MoonConfig.defaults())
	var off_config := MoonConfig.defaults()
	off_config.moon = "off"
	var off := SkyState.state(sky, off_config)
	_check("off: no disc", (off.moon_lin as Vector3) == Vector3.ZERO)
	_check("off: no moonlight", float(off.light_energy) == 0.0 and off.light_source == "sun", "%s %s" % [off.light_energy, off.light_source])
	_check("off: darker sky (no moon glow)", (off.zenith_lin as Vector3).y < (real.zenith_lin as Vector3).y * 0.5)
	var large_config := MoonConfig.defaults()
	large_config.size = "large"
	var large := SkyState.state(sky, large_config)
	_check("large: twice the disc", is_equal_approx(float(large.moon_radius), 2.0 * float(real.moon_radius)))
	_check("large: same light", is_equal_approx(float(large.light_energy), float(real.light_energy)))
	var bright_config := MoonConfig.defaults()
	bright_config.moonlight = "bright"
	var bright := SkyState.state(sky, bright_config)
	_check("bright: three times the moonlight", is_equal_approx(float(bright.light_energy), 3.0 * float(real.light_energy)),
		"%s vs %s" % [bright.light_energy, real.light_energy])
	_check("the state records the choices", bright.moon_config == bright_config)
	_check("SkyState and MoonConfig agree on the factors", SkyState.MOON_LARGE_FACTOR == MoonConfig.LARGE_SIZE_FACTOR
		and SkyState.MOON_BRIGHT_FACTOR == MoonConfig.BRIGHT_MOONLIGHT_FACTOR)
	var implicit := SkyState.state(sky)
	var explicit := SkyState.state(sky, MoonConfig.defaults())
	implicit.erase("moon_config")
	explicit.erase("moon_config")
	_check("empty config renders like the defaults", str(implicit) == str(explicit))

	# [moon] preferences: an additive section. A saved choice loads back; an older file without it is the real moon; a
	# broken section recovers to the real moon with a note; an invalid choice is never written.
	var path := "user://test_world_moon_config_prefs.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var prefs := Preferences.load_from(path)
	_check("no file: the real moon", prefs.moon_config == MoonConfig.defaults())
	var chosen := MoonConfig.defaults()
	chosen.moon = "phase"
	chosen.phase = "waning_crescent"
	chosen.size = "large"
	prefs.moon_config = chosen
	_check("a valid choice saves", Preferences.save_to(path, prefs) == OK)
	_check("and loads back exactly", Preferences.load_from(path).moon_config == chosen)
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.erase_section("moon")
	cfg.save(path)
	_check("a file without [moon] gives the real moon", Preferences.load_from(path).moon_config == MoonConfig.defaults())
	cfg.set_value("moon", "config", {format = MoonConfig.FORMAT, moon = "purple"})
	cfg.save(path)
	var recovered := Preferences.load_from(path)
	_check("a broken [moon] recovers to the real moon with a note", recovered.moon_config == MoonConfig.defaults()
		and str(recovered.note).contains("moon"), str(recovered.note))
	var invalid := Preferences.load_from(path)
	invalid.moon_config = {moon = "purple"}
	_check("an invalid choice is never written", Preferences.save_to(path, invalid) == ERR_INVALID_DATA)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)

## Exercise the actual field-world resolver; no sky pixels or exposure are tested.
extends SceneTree

const Conditions := preload("res://render/world/conditions.gd")
const Ephemeris := preload("res://render/world/ephemeris.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	for key: String in ["OPENRC_TIME", "OPENRC_TIME_OF_DAY", "OPENRC_TIME_SCALE", "OPENRC_DATE",
			"OPENRC_LAT", "OPENRC_LON", "OPENRC_UTC_OFFSET"]:
		OS.unset_environment(key)
	Conditions.session_preset = ""
	OS.set_environment("OPENRC_TIME", "12:00")
	OS.set_environment("OPENRC_TIME_OF_DAY", "night")
	OS.set_environment("OPENRC_TIME_SCALE", "20")
	var inherited := Conditions.resolve(PackedStringArray(["--time_of_day=golden_hour", "--time_scale=0"]))
	_check("a nonempty inherited clock overrides a named preset", inherited.time_of_day \
		and inherited.preset == "" and is_equal_approx(inherited.when.hour, 12.0))
	for preset: String in ["morning", "afternoon", "golden_hour", "sunset", "blue_hour"]:
		var resolved := Conditions.resolve(PackedStringArray(["--time=", "--time_of_day=" + preset, "--time_scale=0"]))
		_check(preset + " survives the inherited clock and preset", resolved.time_of_day and resolved.preset == preset)
		_check(preset + " stays frozen despite inherited time scale", resolved.time_scale == 0.0)
		var sky := Ephemeris.sky(resolved.when)
		_check(preset + " resolves the source solar elevation", \
			absf(float(sky.sun.elevation_deg) - float(Conditions.PRESETS[preset].sun_elevation_deg)) < 0.01)
	var fixed := Conditions.resolve(PackedStringArray(["--time=", "--time_of_day=", "--time_scale=0"]))
	_check("explicit empty time arguments retain fixed Day in a fresh direct session", fixed == {"time_of_day": false})
	Conditions.session_preset = "morning"
	var home := Conditions.resolve(PackedStringArray(["--time=", "--time_of_day=", "--time_scale=0"]))
	_check("empty time arguments do not erase an existing Home session preset", home.time_of_day and home.preset == "morning")
	Conditions.session_preset = ""
	print("TRAILER_CAPTURE_TIME checks=", _checks, " failures=", _failures)
	quit(1 if _failures else 0)


func _check(label: String, condition: bool) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("FAIL: ", label)

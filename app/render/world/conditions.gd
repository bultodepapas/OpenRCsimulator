# FIELD-WORLD-PLAN FW-03: the conditions a world is built for. Today: the time of day.
# No time chosen (the default) keeps the calibrated fixed 45° sun of Spec.ATMOSPHERE: every existing capture, golden
# file and readability baseline stays byte-identical (decision D-4 until Gate FW-U).
#
# Choosing a time (precedence: command line, then environment, then the Home choice in `session_preset`):
#   --time_of_day=<preset> | OPENRC_TIME_OF_DAY   one of PRESETS below
#   --time=HH:MM           | OPENRC_TIME          local clock time on --date
#   --date=YYYY-MM-DD      | OPENRC_DATE          default REFERENCE date
#   --lat=<deg> --lon=<deg east> --utc_offset=<h> | OPENRC_LAT / OPENRC_LON / OPENRC_UTC_OFFSET
#   --time_scale=<x>     | OPENRC_TIME_SCALE     sky seconds per simulated second (FW-61; 0 = frozen, the default)
# The time is frozen by default (D-6); with a time scale the sky advances on simulation time, still deterministic.
extends RefCounted

const Ephemeris := preload("res://render/world/ephemeris.gd")

## Reference place and date (decision D-5, estimate): central Spain (40° N, 3.7° W) in summer time (UTC+2),
## midsummer 2026. Replace with the owner's club coordinates when known.
const REFERENCE := {year = 2026, month = 6, day = 21, utc_offset_h = 2.0, latitude_deg = 40.0, longitude_deg = -3.7}

## Presets as sun events, solved on their date at the reference place, so they stay right if the place changes.
## `event`: rising / setting (the sun crossing `sun_elevation_deg`), highest / lowest (solar noon / midnight).
## Moon dates (computed with Ephemeris; checked in test_world_conditions.gd): 2026-06-29 full moon, 2026-06-15 new.
const PRESETS := {
	dawn = {month = 6, day = 21, event = "rising", sun_elevation_deg = -4.0},
	sunrise = {month = 6, day = 21, event = "rising", sun_elevation_deg = 1.0},
	morning = {month = 6, day = 21, event = "rising", sun_elevation_deg = 25.0},
	noon = {month = 6, day = 21, event = "highest"},
	afternoon = {month = 6, day = 21, event = "setting", sun_elevation_deg = 35.0},
	golden_hour = {month = 6, day = 21, event = "setting", sun_elevation_deg = 6.0},
	sunset = {month = 6, day = 21, event = "setting", sun_elevation_deg = 0.5},
	blue_hour = {month = 6, day = 21, event = "setting", sun_elevation_deg = -4.0},
	night = {month = 6, day = 29, event = "lowest"},
	night_dark = {month = 6, day = 15, event = "lowest"},
}


## The Home choices (FW-27), in the order the Home button cycles; "day" is the calibrated fixed sun.
const HOME_CHOICES: Array[String] = ["day", "dawn", "golden_hour", "sunset", "blue_hour", "evening", "night", "night_dark"]
## English labels of the Home choices (translated by the interface).
const HOME_LABELS := {day = "Day", dawn = "Dawn", golden_hour = "Golden hour", sunset = "Sunset",
	blue_hour = "Blue hour", evening = "Evening, time passing", night = "Night, full moon", night_dark = "Night, no moon"}
## Flowing choices (FW-61): a start preset and a time scale. "evening": golden hour at ×20, so about four minutes of
## flight bring sunset, dusk with the club lights coming on, and the first stars (estimate of a fun pace).
const FLOWING := {evening = {preset = "golden_hour", time_scale = 20.0}}

## The interactive route's choice (app_root sets it from the saved preference before Home and Fly build their
## worlds). The direct route never reads preferences, so automation keeps its own arguments only.
static var session_preset := ""


## The next Home choice after `preset` (wraps; unknown values restart at "day").
static func next_home_choice(preset: String) -> String:
	var i := HOME_CHOICES.find(preset)
	return HOME_CHOICES[(i + 1) % HOME_CHOICES.size()]


## The conditions for this run: {time_of_day: false} (legacy fixed sun), or {time_of_day: true, preset, when}, where
## `when` is the Ephemeris.sky() input. Unknown values warn and fall back to the legacy sky.
static func resolve(args: PackedStringArray = OS.get_cmdline_user_args()) -> Dictionary:
	var opts := {}
	for arg: String in args:
		var kv := arg.trim_prefix("--").split("=", true, 1)
		if kv.size() == 2:
			opts[kv[0]] = kv[1]
	var get := func(key: String, env: String) -> String:
		return str(opts[key]) if opts.has(key) else OS.get_environment(env)
	var preset: String = get.call("time_of_day", "OPENRC_TIME_OF_DAY")
	var clock: String = get.call("time", "OPENRC_TIME")
	var scale_text: String = get.call("time_scale", "OPENRC_TIME_SCALE")
	var time_scale := 0.0
	if not scale_text.is_empty():
		if not scale_text.is_valid_float() or float(scale_text) < 0.0 or float(scale_text) > 3600.0:
			push_warning("Bad --time_scale '%s' (0–3600); time stays frozen" % scale_text)
		else:
			time_scale = float(scale_text)
	if preset.is_empty() and clock.is_empty():
		if FLOWING.has(session_preset):
			preset = FLOWING[session_preset].preset
			if scale_text.is_empty():
				time_scale = FLOWING[session_preset].time_scale
		elif PRESETS.has(session_preset):
			preset = session_preset
	if preset.is_empty() and clock.is_empty():
		return {time_of_day = false}
	var when := REFERENCE.duplicate()
	var date: String = get.call("date", "OPENRC_DATE")
	if not date.is_empty():
		var parts := date.split("-")
		if parts.size() != 3 or not (parts[0].is_valid_int() and parts[1].is_valid_int() and parts[2].is_valid_int()):
			push_warning("Bad --date '%s' (YYYY-MM-DD); using the fixed sun" % date)
			return {time_of_day = false}
		when.year = int(parts[0]); when.month = int(parts[1]); when.day = int(parts[2])
	for key: String in ["lat", "lon", "utc_offset"]:
		var value: String = get.call(key, "OPENRC_" + key.to_upper())
		if not value.is_empty():
			if not value.is_valid_float():
				push_warning("Bad --%s '%s'; using the fixed sun" % [key, value])
				return {time_of_day = false}
			when[{lat = "latitude_deg", lon = "longitude_deg", utc_offset = "utc_offset_h"}[key]] = float(value)
	if not clock.is_empty():
		var hm := clock.split(":")
		if hm.size() != 2 or not (hm[0].is_valid_int() and hm[1].is_valid_int()):
			push_warning("Bad --time '%s' (HH:MM); using the fixed sun" % clock)
			return {time_of_day = false}
		when.hour = int(hm[0]) + int(hm[1]) / 60.0
		return {time_of_day = true, preset = "", when = when, time_scale = time_scale}
	if not PRESETS.has(preset):
		push_warning("Unknown time of day '%s' (%s); using the fixed sun" % [preset, ", ".join(PRESETS.keys())])
		return {time_of_day = false}
	var p: Dictionary = PRESETS[preset]
	if date.is_empty():
		when.month = p.month
		when.day = p.day
	when.hour = solve_hour(when, p.event, float(p.get("sun_elevation_deg", 0.0)))
	return {time_of_day = true, preset = preset, when = when, time_scale = time_scale}


## Sun elevation (apparent, degrees) at a local hour on `when`'s date and place.
static func sun_elevation(when: Dictionary, hour: float) -> float:
	var jd := Ephemeris.julian_day(int(when.year), int(when.month), int(when.day), hour - float(when.utc_offset_h))
	var s := Ephemeris.sun(jd)
	var h := Ephemeris.horizontal(s.ra_deg, s.dec_deg, float(when.latitude_deg), float(when.longitude_deg), jd)
	return h.elevation_deg + Ephemeris.refraction_deg(h.elevation_deg)


## The local hour of a sun event on `when`'s date, to the minute (scan, then bisection to 1 s). Midnight events
## search from noon to noon, so "lowest" lands after midnight of the given evening.
static func solve_hour(when: Dictionary, event: String, elevation_deg: float) -> float:
	var start := 12.0 if event == "lowest" else 0.0
	var best_hour := start
	var best := INF if event == "lowest" else -INF
	for minute in range(0, 24 * 60, 2):
		var hour := start + minute / 60.0
		var el := sun_elevation(when, hour)
		if (event == "highest" and el > best) or (event == "lowest" and el < best):
			best = el
			best_hour = hour
	if event == "highest" or event == "lowest":
		return best_hour
	var rising := event == "rising"
	for minute in range(0, 24 * 60, 2):
		var h0 := minute / 60.0
		var h1 := (minute + 2) / 60.0
		var e0 := sun_elevation(when, h0) - elevation_deg
		var e1 := sun_elevation(when, h1) - elevation_deg
		if (rising and e0 < 0.0 and e1 >= 0.0) or (not rising and e0 > 0.0 and e1 <= 0.0):
			for i in 12:
				var mid := (h0 + h1) / 2.0
				var em := sun_elevation(when, mid) - elevation_deg
				if (em < 0.0) == (e0 < 0.0):
					h0 = mid
					e0 = em
				else:
					h1 = mid
			return (h0 + h1) / 2.0
	push_warning("The sun never reaches %.1f° (%s) on this date; using solar noon" % [elevation_deg, event])
	return solve_hour(when, "highest", 0.0)

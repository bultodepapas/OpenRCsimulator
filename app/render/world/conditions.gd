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
const Lunar := preload("res://render/world/lunar.gd")

## Reference place and date (decision D-5, estimate): central Spain (40° N, 3.7° W) in summer time (UTC+2),
## midsummer 2026. Replace with the owner's club coordinates when known.
const REFERENCE := {year = 2026, month = 6, day = 21, utc_offset_h = 2.0, latitude_deg = 40.0, longitude_deg = -3.7}

## Presets as sun events, solved on their date at the reference place, so they stay right if the place changes.
## `event`: rising / setting (the sun crossing `sun_elevation_deg`), highest / lowest (solar noon / midnight).
## Moon dates (computed with Ephemeris; checked in test_world_sky.gd): 2026-06-15 new moon.
## FW-MOON-11 moon events: "moon_view" searches forward from the preset's month/day for the first moment the moon meets
## the preset's constraints in front of the pilot (MOON_VIEW_* below); "moon_view_golden" returns golden hour (sun 6°,
## setting) of that day, the start of a flowing evening. At the reference place: Moonrise = the Harvest Moon,
## 2026-09-26 (rises due east at dusk); Night = 2026-09-27 22:00, the next night's 98 % moon 19° up in the east
## (docs/research/field-world/FW-MOON-11).
const PRESETS := {
	dawn = {month = 6, day = 21, event = "rising", sun_elevation_deg = -4.0},
	sunrise = {month = 6, day = 21, event = "rising", sun_elevation_deg = 1.0},
	morning = {month = 6, day = 21, event = "rising", sun_elevation_deg = 25.0},
	noon = {month = 6, day = 21, event = "highest"},
	afternoon = {month = 6, day = 21, event = "setting", sun_elevation_deg = 35.0},
	golden_hour = {month = 6, day = 21, event = "setting", sun_elevation_deg = 6.0},
	sunset = {month = 6, day = 21, event = "setting", sun_elevation_deg = 0.5},
	blue_hour = {month = 6, day = 21, event = "setting", sun_elevation_deg = -4.0},
	night = {month = 6, day = 21, event = "moon_view", view = "night"},
	night_dark = {month = 6, day = 15, event = "lowest"},
	moonrise = {month = 6, day = 21, event = "moon_view", view = "moonrise"},
	moonrise_golden = {month = 6, day = 21, event = "moon_view_golden", view = "moonrise"},
}
## Where the pilot looks: the default field's runway lies 15 m north of the pilot station, east-west, so the pilot
## faces north and follows the airplane east and west (estimate tied to the default field).
const PILOT_FORWARD_AZIMUTH_DEG := 0.0
const PILOT_VIEW_HALF_WIDTH_DEG := 100.0
## Moon-view constraints: sun elevation range, moon elevation range, minimum illuminated fraction, the local hours
## scanned each day and the scan step (minutes). Moonrise: the full moon just risen at dusk. Night: a full moon at a
## comfortable height in full darkness.
const MOON_VIEWS := {
	moonrise = {sun_min_deg = -4.0, sun_max_deg = -2.0, moon_min_deg = 0.5, moon_max_deg = 12.0, illuminated_min = 0.97,
		from_hour = 16.0, to_hour = 23.0, step_min = 10.0},
	night = {sun_min_deg = -90.0, sun_max_deg = -18.0, moon_min_deg = 18.0, moon_max_deg = 30.0, illuminated_min = 0.97,
		from_hour = 19.0, to_hour = 29.0, step_min = 20.0},
}
## Days searched forward (a little more than a year: every season's moon is reachable).
const MOON_VIEW_SEARCH_DAYS := 400
static var _moon_view_cache := {}


## The Home choices (FW-27), in the order the Home button cycles; "day" is the calibrated fixed sun.
const HOME_CHOICES: Array[String] = ["day", "dawn", "golden_hour", "sunset", "blue_hour", "evening", "moonrise", "night",
	"night_dark"]
## English labels of the Home choices (translated by the interface).
const HOME_LABELS := {day = "Day", dawn = "Dawn", golden_hour = "Golden hour", sunset = "Sunset",
	blue_hour = "Blue hour", evening = "Evening, time passing", moonrise = "Moonrise, time passing", night = "Night, full moon",
	night_dark = "Night, no moon"}
## Flowing choices (FW-61): a start preset and a time scale. "evening": golden hour at ×20, so about four minutes of
## flight bring sunset, dusk with the club lights coming on, and the first stars (estimate of a fun pace).
## FW-MOON-11 "moonrise": golden hour on the Moonrise date at ×20, so sunset, the orange full moon rising in front of the
## pilot and the moonlit night arrive within a few minutes of flight.
const FLOWING := {evening = {preset = "golden_hour", time_scale = 20.0}, moonrise = {preset = "moonrise_golden", time_scale = 20.0}}

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
	if str(p.event).begins_with("moon_view"):
		var found := solve_moon_view(when, str(p.view))
		if found.is_empty():
			push_warning("No %s moon within %d days of %04d-%02d-%02d here; using the fixed sun" % [p.view,
				MOON_VIEW_SEARCH_DAYS, when.year, when.month, when.day])
			return {time_of_day = false}
		when = found
		if p.event == "moon_view_golden":
			when.hour = solve_hour(when, "setting", 6.0)
		return {time_of_day = true, preset = preset, when = when, time_scale = time_scale}
	when.hour = solve_hour(when, p.event, float(p.get("sun_elevation_deg", 0.0)))
	return {time_of_day = true, preset = preset, when = when, time_scale = time_scale}


## FW-MOON-11: the first moment from `when`'s date (searching MOON_VIEW_SEARCH_DAYS forward) when the moon meets the
## MOON_VIEWS[view] constraints inside the pilot's view: a copy of `when` with that date and local hour, or {}.
## Deterministic (fixed scan grid); results are cached per place, date and view.
static func solve_moon_view(when: Dictionary, view: String) -> Dictionary:
	var key := str([view, when.year, when.month, when.day, when.utc_offset_h, when.latitude_deg, when.longitude_deg])
	if _moon_view_cache.has(key):
		return (_moon_view_cache[key] as Dictionary).duplicate()
	var c: Dictionary = MOON_VIEWS[view]
	var jd_day := Ephemeris.julian_day(int(when.year), int(when.month), int(when.day), 12.0)
	var steps := int(roundf((float(c.to_hour) - float(c.from_hour)) * 60.0 / float(c.step_min)))
	for d in MOON_VIEW_SEARCH_DAYS:
		var date := Lunar.calendar(jd_day + d)
		var probe := when.duplicate()
		probe.year = date.year
		probe.month = date.month
		probe.day = date.day
		for k in steps + 1:
			probe.hour = float(c.from_hour) + k * float(c.step_min) / 60.0
			var sky := Ephemeris.sky(probe)
			var sun_el: float = sky.sun.elevation_deg
			var moon: Dictionary = sky.moon
			var off_axis := absf(fposmod(float(moon.azimuth_deg) - PILOT_FORWARD_AZIMUTH_DEG + 180.0, 360.0) - 180.0)
			if sun_el >= float(c.sun_min_deg) and sun_el <= float(c.sun_max_deg) \
					and float(moon.elevation_deg) >= float(c.moon_min_deg) and float(moon.elevation_deg) <= float(c.moon_max_deg) \
					and float(moon.illuminated) >= float(c.illuminated_min) and off_axis <= PILOT_VIEW_HALF_WIDTH_DEG:
				# Hours past midnight belong to the next calendar day.
				var out := probe.duplicate()
				if out.hour >= 24.0:
					var next := Lunar.calendar(jd_day + d + 1)
					out.year = next.year
					out.month = next.month
					out.day = next.day
					out.hour -= 24.0
				_moon_view_cache[key] = out.duplicate()
				return out
	_moon_view_cache[key] = {}
	return {}


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

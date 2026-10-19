## FW-MOON-10/11: scans for total lunar eclipses and how the reference field sees them, to choose an eclipse event.
## For each total eclipse (umbral magnitude > 1) it prints greatest eclipse (UT, from 5-minute samples) and, at the
## reference field (Conditions' default place), the moon's elevation and azimuth and the sun's elevation there, and
## the minutes of totality the pilot can see: moon at least 10° up inside the pilot's view (Conditions'
## PILOT_FORWARD_AZIMUTH_DEG ± PILOT_VIEW_HALF_WIDTH_DEG) with the sun at or below −12° (nautical dark).
## Run from the repository root:
##   "$(app/get-godot.sh)" --headless --path app --script "$PWD/research/field-world/fw-moon-10/event_scan.gd" \
##     -- [--from=2026] [--years=8]
extends SceneTree

const Lunar := preload("res://render/world/lunar.gd")
const Ephemeris := preload("res://render/world/ephemeris.gd")
const Conditions := preload("res://render/world/conditions.gd")

const STEP_MIN := 5.0
const MOON_MIN_DEG := 10.0
const SUN_MAX_DEG := -12.0


func _initialize() -> void:
	var args := {}
	for argument: String in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		args[pair[0]] = pair[1] if pair.size() > 1 else "on"
	var from := int(args.get("from", "2026"))
	var years := int(args.get("years", "8"))
	var place: Dictionary = Conditions.resolve(PackedStringArray(["--date=%d-01-01" % from, "--time=00:00"])).when
	print("reference field: latitude %.4f, longitude %.4f; pilot faces %.0f° ± %.0f°" % [place.latitude_deg, place.longitude_deg,
		Conditions.PILOT_FORWARD_AZIMUTH_DEG, Conditions.PILOT_VIEW_HALF_WIDTH_DEG])
	print("| Greatest (UT) | Umbral magnitude | Moon elevation | Moon azimuth | Sun elevation | Totality seen from the field |")
	print("| --- | --- | --- | --- | --- | --- |")
	var jd := Ephemeris.julian_day(from, 1, 1, 0.0)
	var end := jd + 365.25 * years
	while jd < end:
		if _umbral(jd) < 0.5:
			jd += 1.0 / 24.0
			continue
		# An umbral eclipse: sample it every STEP_MIN for six hours around this hour.
		var best_jd := jd
		var best := -INF
		var seen := 0.0
		var t := jd - 3.0 / 24.0
		while t < jd + 3.0 / 24.0:
			var m := _umbral(t)
			if m > best:
				best = m
				best_jd = t
			if m > 1.0 and _visible(t, place):
				seen += STEP_MIN
			t += STEP_MIN / 1440.0
		if best > 1.0:
			var at := _look(best_jd, place)
			var cal := Lunar.calendar(best_jd)
			print("| %04d-%02d-%02d %s | %.2f | %.1f° | %.1f° | %.1f° | %.0f min |" % [cal.year, cal.month, cal.day,
				_hhmm(fposmod(best_jd + 0.5, 1.0) * 24.0), best, at.moon_el, at.moon_az, at.sun_el, seen])
		jd += 3.0 / 24.0 + 20.0 # past this eclipse and its season's other full moons
	quit(0)


static func _umbral(jd: float) -> float:
	return float(Lunar.at_jd(jd, 0.0, 0.0, true).eclipse.umbral_magnitude)


static func _look(jd: float, place: Dictionary) -> Dictionary:
	var cal := Lunar.calendar(jd)
	var sky := Ephemeris.sky({year = cal.year, month = cal.month, day = cal.day, hour = fposmod(jd + 0.5, 1.0) * 24.0,
		utc_offset_h = 0.0, latitude_deg = place.latitude_deg, longitude_deg = place.longitude_deg})
	return {moon_el = float(sky.moon.elevation_deg), moon_az = float(sky.moon.azimuth_deg), sun_el = float(sky.sun.elevation_deg)}


static func _visible(jd: float, place: Dictionary) -> bool:
	var at := _look(jd, place)
	var off_axis := absf(fposmod(at.moon_az - Conditions.PILOT_FORWARD_AZIMUTH_DEG + 180.0, 360.0) - 180.0)
	return at.moon_el >= MOON_MIN_DEG and at.sun_el <= SUN_MAX_DEG and off_axis <= Conditions.PILOT_VIEW_HALF_WIDTH_DEG


static func _hhmm(hours: float) -> String:
	var minutes := int(roundf(hours * 60.0))
	return "%02d:%02d" % [minutes / 60, minutes % 60]

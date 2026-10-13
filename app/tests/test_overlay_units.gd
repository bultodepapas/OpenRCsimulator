# HUD-01: overlay unit conversion and display rounding (render/overlays/units.gd), against exact definitions.
# Run: godot --headless --path . --script res://tests/test_overlay_units.gd
extends SceneTree

const Units := preload("res://render/overlays/units.gd")

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _near(a: float, b: float, tol := 1e-9) -> bool:
	return absf(a - b) <= tol


func _initialize() -> void:
	_check("10 m/s = 36 km/h", _near(Units.speed(10.0, "metric")[0], 36.0) and Units.speed(10.0, "metric")[1] == "km/h")
	_check("22.352 m/s = 50 mph exactly", _near(Units.speed(22.352, "imperial")[0], 50.0) and Units.speed(1.0, "imperial")[1] == "mph")
	_check("SI speed is m/s unchanged", _near(Units.speed(7.25, "si")[0], 7.25) and Units.speed(1.0, "si")[1] == "m/s")
	_check("30.48 m = 100 ft exactly", _near(Units.length(30.48, "imperial")[0], 100.0) and Units.length(1.0, "imperial")[1] == "ft")
	_check("metric and SI lengths stay in m", Units.length(3.0, "metric") == [3.0, "m"] and Units.length(3.0, "si") == [3.0, "m"])
	_check("1 m/s climb = 196.85 ft/min", _near(Units.vertical(1.0, "imperial")[0], 60.0 / 0.3048) and Units.vertical(1.0, "imperial")[1] == "ft/min")
	_check("metric vertical speed stays m/s", Units.vertical(-2.5, "metric") == [-2.5, "m/s"])

	_check("auto: English reads imperial", Units.resolve("auto", "en") == "imperial")
	_check("auto: Spanish reads metric", Units.resolve("auto", "es") == "metric")
	_check("explicit choice wins over language", Units.resolve("metric", "en") == "metric" and Units.resolve("si", "es") == "si")
	_check("unknown system falls back to the language rule", Units.resolve("furlongs", "es") == "metric")

	var cases := [
		[Units.format(Units.speed(10.0, "metric")), "36 km/h"],
		[Units.format(Units.speed(22.352, "imperial")), "50 mph"],
		[Units.format(Units.length(123.4, "metric")), "123 m"],
		[Units.format(Units.length(5.04, "metric")), "5.0 m"],
		[Units.format(Units.length(30.48, "imperial")), "100 ft"],
		[Units.format(Units.vertical(1.0, "imperial"), true), "+200 ft/min"],
		[Units.format(Units.vertical(-1.26, "metric"), true), "-1.3 m/s"],
		[Units.format(Units.vertical(1.26, "metric"), true), "+1.3 m/s"],
		[Units.format(Units.vertical(-0.04, "metric"), true), "0.0 m/s"],
		[Units.format(Units.vertical(0.02, "imperial"), true), "0 ft/min"],
		[Units.format(Units.speed(0.0, "si")), "0.0 m/s"],
		[Units.format(Units.length(NAN, "imperial")), "– ft"],
	]
	cases.append_array([
		[Units.angle(-0.3, 0), "0°"],
		[Units.angle(-0.04, 1), "0.0°"],
		[Units.angle(4.26, 1), "+4.3°"],
		[Units.angle(-1.0, 0), "-1°"],
		[Units.angle(12.0, 0, false), "12°"],
		[Units.angle(NAN, 1), "–°"],
	])
	for c: Array in cases:
		_check("format → %s" % c[1], c[0] == c[1], "got '%s'" % c[0])
	print("overlay units: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures else 0)

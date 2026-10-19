# FW-MOON-10: lunar eclipses. The shadow's transmission is 1 outside the penumbra, continuous at both edges, rising
# outward, red in the umbra (Ugolnikov et al. 2011's measured curves); the umbral contacts land on Espenak's partial
# and total durations; mid-totality brightness and colour are those of a real dark eclipse (Vital's 2022 measurement);
# SkyState dims the moonlight and its sky by the disc's transmission and the eye adapts to the eclipsed disc; a night
# without an eclipse is untouched.
# Run: godot --headless --path . --script res://tests/test_world_moon_eclipse.gd
extends SceneTree

const Lunar := preload("res://render/world/lunar.gd")
const Ephemeris := preload("res://render/world/ephemeris.gd")
const SkyState := preload("res://render/world/sky_state.gd")
const Conditions := preload("res://render/world/conditions.gd")

## Espenak, NASA GSFC "Lunar Eclipses: 2021-2030" (LEdecade2021): TD of greatest eclipse, umbral magnitude, partial and
## total durations (min), all from that page (checked 2026-10-19). ΔT = 69 s as the fixture.
const ESPENAK := [
	["2026-03-03", [11, 34, 52], 1.151, 207, 58],
	["2026-08-28", [4, 14, 4], 0.930, 198, 0],
	["2028-01-12", [4, 14, 13], 0.066, 56, 0],
	["2028-07-06", [18, 20, 57], 0.389, 141, 0],
	["2028-12-31", [16, 53, 15], 1.246, 209, 71],
	["2022-05-16", [4, 12, 42], 1.414, 207, 85],
]
## The duration tolerance follows the chord: Lunar's umbral magnitude is within 0.031 of Espenak's (FW-MOON-02), and a
## shallow eclipse's chord is short, so the same error moves its contacts more.
const DURATION_TOLERANCE_MIN := 5.0
const SHALLOW_DURATION_TOLERANCE_MIN := 12.0

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _magnitude(jd: float) -> float:
	return float(Lunar.at_jd(jd, 0.0, 0.0, true).eclipse.umbral_magnitude)


func _crossing(a: float, b: float, level: float) -> float:
	for i in 40:
		var m := (a + b) / 2.0
		if (_magnitude(a) - level) * (_magnitude(m) - level) <= 0.0:
			b = m
		else:
			a = m
	return (a + b) / 2.0


static func _greatest_jd(row: Array) -> float:
	var p := str(row[0]).split("-")
	var g: Array = row[1]
	return Ephemeris.julian_day(int(p[0]), int(p[1]), int(p[2]), float(g[0]) + g[1] / 60.0 + g[2] / 3600.0 - 69.0 / 3600.0)


func _initialize() -> void:
	# The transmission law.
	var u := 2.7
	var p := 3.9
	_check("outside the penumbra: full sunlight", Lunar.eclipse_transmission(p, u, p) == Vector3.ONE
		and Lunar.eclipse_transmission(5.0, u, p) == Vector3.ONE)
	var inner := Lunar.eclipse_transmission(p - 1e-6, u, p)
	_check("continuous at the penumbra's outer edge", (Vector3.ONE - inner).length() < 1e-3, str(inner))
	var a := Lunar.eclipse_transmission(u - 1e-6, u, p)
	var b := Lunar.eclipse_transmission(u + 1e-6, u, p)
	_check("continuous at the umbra's edge", (a - b).length() < 1e-3, "%s %s" % [a, b])
	var monotonic := true
	var previous := Lunar.eclipse_transmission(0.0, u, p)
	for i in range(1, 400):
		var t := Lunar.eclipse_transmission(p * i / 400.0, u, p)
		monotonic = monotonic and t.x >= previous.x and t.y >= previous.y and t.z >= previous.z
		previous = t
	_check("sunlight rises from the shadow's axis outward, every channel", monotonic)
	var deep := Lunar.eclipse_transmission(0.4 * u, u, p)
	_check("the umbra is red: R > G > B", deep.x > deep.y and deep.y > deep.z, str(deep))
	var at_062 := Lunar.eclipse_transmission(0.62 * u, u, p)
	_check("the umbra follows the measured 677/503 nm curves (u = 0.62: R ≈ 10^−3.64)", absf(log(at_062.x) / log(10.0) + 3.64) < 0.02,
		str(log(at_062.x) / log(10.0)))
	_check("half the solar disc shows mid-penumbra", absf(Lunar.eclipse_transmission((u + p) / 2.0, u, p).y - 0.5) < 1e-6)

	# Contacts against Espenak's durations.
	for row: Array in ESPENAK:
		var jd := _greatest_jd(row)
		var u1 := _crossing(jd - 4.0 / 24.0, jd, 0.0)
		var u4 := _crossing(jd, jd + 4.0 / 24.0, 0.0)
		var partial := (u4 - u1) * 1440.0
		var tolerance := SHALLOW_DURATION_TOLERANCE_MIN if float(row[2]) < 0.1 else DURATION_TOLERANCE_MIN
		_check("%s: partial phase %.0f min vs Espenak %d" % [row[0], partial, row[3]], absf(partial - float(row[3])) <= tolerance)
		if int(row[4]) > 0:
			var u2 := _crossing(jd - 2.0 / 24.0, jd, 1.0)
			var u3 := _crossing(jd, jd + 2.0 / 24.0, 1.0)
			var total := (u3 - u2) * 1440.0
			_check("%s: totality %.0f min vs Espenak %d" % [row[0], total, row[4]], absf(total - float(row[4])) <= DURATION_TOLERANCE_MIN)

	# Mid-totality: Vital et al. measured V = −0.8 ± 0.3 at the 2022-05-16 eclipse (Sky & Telescope); the umbra here is
	# the 2011 eclipse's air, so the tolerance is a Danjon step (±1 mag).
	var f2022 := Lunar.eclipse_disc_factor(Lunar.at_jd(_greatest_jd(ESPENAK[5]), 0.0, 0.0, true).eclipse)
	var v2022 := -12.73 - 2.5 * log(f2022.y) / log(10.0)
	print("  2022-05-16 mid-totality V %.2f (measured −0.8 ± 0.3); colour G/R %.2f B/R %.2f" % [v2022, f2022.y / f2022.x, f2022.z / f2022.x])
	_check("2022-05-16 mid-totality brightness within a Danjon step of the measurement", absf(v2022 + 0.8) <= 1.0, str(v2022))
	_check("totality is copper: G/R under 0.6, B/R under 0.3", f2022.y / f2022.x < 0.6 and f2022.z / f2022.x < 0.3)

	# SkyState: the eclipsed moon's light and sky dim, the eye adapts to the eclipsed disc.
	var east := ["--lat=30", "--lon=90", "--utc_offset=0", "--date=2028-12-31"]
	var totality := SkyState.state(Ephemeris.sky(Conditions.resolve(PackedStringArray(east + ["--time=16:52"])).when))
	var before := SkyState.state(Ephemeris.sky(Conditions.resolve(PackedStringArray(east + ["--time=13:30"])).when))
	_check("totality: the state carries the eclipse", totality.moon_eclipse and _lum(totality.moon_eclipse_factor) < 1e-3,
		str(totality.moon_eclipse_factor))
	_check("before the penumbra: no eclipse, factor exactly 1", not before.moon_eclipse and before.moon_eclipse_factor == Vector3.ONE)
	_check("totality: the moon no longer lights the field", float(totality.light_energy) < 1e-3 * float(before.light_energy),
		"%s vs %s" % [totality.light_energy, before.light_energy])
	_check("totality: the eye opens to the dim disc (less compression)", float(totality.moon_display_scale) > 10.0 * float(before.moon_display_scale),
		"%s vs %s" % [totality.moon_display_scale, before.moon_display_scale])
	var night := SkyState.state(Ephemeris.sky(Conditions.resolve(PackedStringArray(["--time_of_day=night"])).when))
	_check("an ordinary night: no eclipse uniforms", not night.moon_eclipse and night.moon_eclipse_factor == Vector3.ONE
		and float(night.moon_penumbra_radius) > 0.0)
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


static func _lum(v: Vector3) -> float:
	return 0.2126 * v.x + 0.7152 * v.y + 0.0722 * v.z

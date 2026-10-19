# FW-20: sun and moon positions against published worked examples (J. Meeus, Astronomical Algorithms, 2nd ed.),
# dated astronomical events, and the total solar eclipse of 2024-04-08 seen from Dallas (sun and moon must overlap).
# Run: godot --headless --path . --script res://tests/test_world_ephemeris.gd
extends SceneTree

const Ephemeris := preload("res://render/world/ephemeris.gd")
const EARTH_RADIUS_KM := 6378.14

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _near(label: String, got: float, want: float, tolerance: float) -> void:
	if OS.get_cmdline_user_args().has("--verbose"):
		print("%s: %+.6f off (±%.6f)" % [label, got - want, tolerance])
	_check(label, absf(got - want) <= tolerance, "got %.6f want %.6f ±%.6f" % [got, want, tolerance])


## Angular separation of two (azimuth, elevation) directions, degrees.
func _separation(a: Dictionary, b: Dictionary) -> float:
	var e1 := deg_to_rad(a.elevation_deg)
	var e2 := deg_to_rad(b.elevation_deg)
	var c := sin(e1) * sin(e2) + cos(e1) * cos(e2) * cos(deg_to_rad(a.azimuth_deg - b.azimuth_deg))
	return rad_to_deg(acos(clampf(c, -1.0, 1.0)))


func _initialize() -> void:
	# Julian Day (Meeus examples 7.a and the J2000 epoch).
	_near("JD of 1957-10-04.81 (Meeus 7.a)", Ephemeris.julian_day(1957, 10, 4, 0.81 * 24.0), 2436116.31, 1e-6)
	_near("JD of 2000-01-01 12h UT", Ephemeris.julian_day(2000, 1, 1, 12.0), 2451545.0, 1e-9)
	_near("JD of 1987-04-10 0h (Meeus 12.a)", Ephemeris.julian_day(1987, 4, 10, 0.0), 2446895.5, 1e-9)

	# Sidereal time (Meeus 12.a, 12.b).
	_near("GMST 1987-04-10 0h UT (Meeus 12.a)", Ephemeris.gmst_deg(2446895.5), 197.693195, 1e-5)
	_near("GMST 1987-04-10 19:21 UT (Meeus 12.b)", Ephemeris.gmst_deg(Ephemeris.julian_day(1987, 4, 10, 19.35)), 128.737873, 1e-5)

	# Sun, low accuracy (Meeus 25.a: 1992-10-13 0h TD; ΔT ≈ 59 s moves the sun < 0.001°).
	var s := Ephemeris.sun(2448908.5)
	_near("sun RA 1992-10-13 (Meeus 25.a)", s.ra_deg, 198.38083, 0.001)
	_near("sun dec 1992-10-13 (Meeus 25.a)", s.dec_deg, -7.78507, 0.001)
	_near("sun distance 1992-10-13 (Meeus 25.a)", s.distance_au, 0.99766, 0.00001)
	# Equinox 2024-03-20 03:06 UT and June solstice 2024-06-20 20:51 UT.
	_near("sun dec at the March 2024 equinox", Ephemeris.sun(Ephemeris.julian_day(2024, 3, 20, 3.1)).dec_deg, 0.0, 0.02)
	_near("sun dec at the June 2024 solstice", Ephemeris.sun(Ephemeris.julian_day(2024, 6, 20, 20.85)).dec_deg, 23.436, 0.01)

	# Moon (Meeus 47.a, 48.a: 1992-04-12 0h TD). Schlyter's series is good to a few arc-minutes.
	var m := Ephemeris.moon(2448724.5)
	_near("moon RA 1992-04-12 (Meeus 47.a)", m.ra_deg, 134.688470, 0.05)
	_near("moon dec 1992-04-12 (Meeus 47.a)", m.dec_deg, 13.768368, 0.05)
	_near("moon ecliptic longitude (Meeus 47.a)", m.longitude_deg, 133.162655, 0.05)
	_near("moon ecliptic latitude (Meeus 47.a)", m.latitude_deg, -3.229126, 0.02)
	_near("moon distance (Meeus 47.a)", m.distance_er, 368409.7 / EARTH_RADIUS_KM, 0.1)
	var phase := Ephemeris.sky({year = 1992, month = 4, day = 12, hour = 0.0, utc_offset_h = 0.0, latitude_deg = 0.0, longitude_deg = 0.0})
	_near("moon illuminated fraction 1992-04-12 (Meeus 48.a)", phase.moon.illuminated, 0.6786, 0.01)
	_check("moon waxing on 1992-04-12 (first quarter was 1992-04-10)", phase.moon.waxing)

	# Dated phases: full moon 2024-04-23 23:49 UT, new moon 2024-04-08 18:21 UT.
	var full := Ephemeris.sky({year = 2024, month = 4, day = 23, hour = 23.82, utc_offset_h = 0.0, latitude_deg = 40.0, longitude_deg = -3.7})
	_check("full moon 2024-04-23 is fully lit", full.moon.illuminated > 0.995, str(full.moon.illuminated))
	var new := Ephemeris.sky({year = 2024, month = 4, day = 8, hour = 18.35, utc_offset_h = 0.0, latitude_deg = 40.0, longitude_deg = -3.7})
	_check("new moon 2024-04-08 is dark", new.moon.illuminated < 0.005, str(new.moon.illuminated))

	# Total solar eclipse, Dallas (32.78° N, 96.80° W), mid-totality ~13:42 CDT (UTC−5): the topocentric moon covers the
	# sun. This checks sidereal time, horizontal coordinates and the lunar parallax together (without parallax ~0.8° off).
	var eclipse := Ephemeris.sky({year = 2024, month = 4, day = 8, hour = 13.70, utc_offset_h = -5.0, latitude_deg = 32.78, longitude_deg = -96.80})
	var separation := _separation(eclipse.sun, eclipse.moon)
	_near("Dallas eclipse: sun–moon separation", separation, 0.0, 0.25)
	_near("Dallas eclipse: sun elevation (published ~64°)", eclipse.sun.elevation_deg, 64.0, 1.5)

	# Local solar noon on the June 2024 solstice at 40° N, 0° E: the highest sun is due south at 90 − 40 + 23.44°.
	var best := {elevation_deg = -90.0, azimuth_deg = 0.0}
	for minute in range(11 * 60 + 30, 12 * 60 + 31):
		var at := Ephemeris.sky({year = 2024, month = 6, day = 20, hour = minute / 60.0, utc_offset_h = 0.0, latitude_deg = 40.0, longitude_deg = 0.0})
		if at.sun.elevation_deg > best.elevation_deg:
			best = at.sun
	_near("solstice noon elevation at 40° N", best.elevation_deg, 73.44, 0.05)
	_near("solstice noon azimuth at 40° N (south)", best.azimuth_deg, 180.0, 1.0)
	var morning := Ephemeris.sky({year = 2024, month = 6, day = 20, hour = 8.0, utc_offset_h = 0.0, latitude_deg = 40.0, longitude_deg = 0.0})
	var evening := Ephemeris.sky({year = 2024, month = 6, day = 20, hour = 16.0, utc_offset_h = 0.0, latitude_deg = 40.0, longitude_deg = 0.0})
	_check("morning sun in the east, evening sun in the west",
		morning.sun.azimuth_deg > 0.0 and morning.sun.azimuth_deg < 180.0 and evening.sun.azimuth_deg > 180.0,
		"%.1f / %.1f" % [morning.sun.azimuth_deg, evening.sun.azimuth_deg])
	var midnight := Ephemeris.sky({year = 2024, month = 6, day = 21, hour = 0.0, utc_offset_h = 0.0, latitude_deg = 40.0, longitude_deg = 0.0})
	_check("sun below the horizon at midnight", midnight.sun.elevation_deg < -20.0, str(midnight.sun.elevation_deg))

	# Refraction (Meeus 16): ~0.57° at the horizon, ~0 overhead, none far below.
	_near("refraction at the horizon", Ephemeris.refraction_deg(0.0), 0.48, 0.1)
	_check("refraction overhead is negligible", Ephemeris.refraction_deg(89.0) < 0.001)
	_check("no refraction far below the horizon", Ephemeris.refraction_deg(-5.0) == 0.0 and Ephemeris.refraction_deg(-3.0) == 0.0)
	# FW-MOON-06a: the apparent elevation is continuous and monotonic through the horizon (no 0.65° drop at −1°).
	_near("Saemundsson unchanged at −1°", Ephemeris.refraction_deg(-1.0), 0.6466, 0.001)
	_check("continuous at the taper start", absf(Ephemeris.refraction_deg(-1.0 - 1e-6) - Ephemeris.refraction_deg(-1.0)) < 1e-5)
	_check("continuous at the taper end", Ephemeris.refraction_deg(-3.0 + 1e-6) < 1e-5)
	var monotonic := true
	var largest := 0.0
	for i in 800:
		var h := -6.0 + 0.01 * i
		var step := (h + 0.01 + Ephemeris.refraction_deg(h + 0.01)) - (h + Ephemeris.refraction_deg(h))
		monotonic = monotonic and step > 0.0
		largest = maxf(largest, step)
	_check("apparent elevation rises monotonically from −6° to +2°, never faster than 1.4× the true", monotonic and largest < 0.014,
		"largest step %.5f°" % largest)
	var dusk_largest := 0.0
	var previous := 0.0
	for k in 240: # 2 h of sky time in 30 s steps around sunset (Madrid, 2026-09-26)
		var e := float(Ephemeris.sky({year = 2026, month = 9, day = 26, hour = 19.5 + k / 120.0, utc_offset_h = 2.0,
			latitude_deg = 40.0, longitude_deg = -3.7}).sun.elevation_deg)
		if k > 0:
			dusk_largest = maxf(dusk_largest, previous - e)
		previous = e
	_check("the setting sun never drops more than 0.15° per 30 s sky step", dusk_largest < 0.15, "%.3f°" % dusk_largest)

	# Same input, same bytes.
	var again := Ephemeris.sky({year = 2024, month = 4, day = 8, hour = 13.70, utc_offset_h = -5.0, latitude_deg = 32.78, longitude_deg = -96.80})
	_check("deterministic", str(again) == str(eclipse))
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)

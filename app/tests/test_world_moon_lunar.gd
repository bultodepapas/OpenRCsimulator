# FW-MOON-02: the Lunar state against NASA SVS 5587 (geocentric, 2026), JPL Horizons (topocentric, three sites,
# rise/transit/set), Espenak's eclipses and phase catalogue, and physical consistency checks. Fixture:
# tests/fixtures/moon_reference_v1.json from tools/world/moon_fixtures.py.
# Run: godot --headless --path . --script res://tests/test_world_moon_lunar.gd [-- --verbose]
extends SceneTree

const Ephemeris := preload("res://render/world/ephemeris.gd")
const Lunar := preload("res://render/world/lunar.gd")
const FIXTURE := "res://tests/fixtures/moon_reference_v1.json"

var _failures := 0
var _count := 0
var _verbose := OS.get_cmdline_user_args().has("--verbose")
var _worst := {}


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


## Checks |got - want| <= tolerance and tracks the worst error per `group` for the summary.
func _near(group: String, label: String, got: float, want: float, tolerance: float) -> void:
	var err := absf(got - want)
	_worst[group] = maxf(float(_worst.get(group, 0.0)), err)
	if _verbose:
		print("%s: %+.6f off (±%.6f)" % [label, got - want, tolerance])
	_check(label, err <= tolerance, "got %.6f want %.6f ±%.6f" % [got, want, tolerance])


static func _wrap(deg: float) -> float:
	return fposmod(deg + 180.0, 360.0) - 180.0


static func _jd_of(utc: String) -> float:
	var p := utc.split("T")
	var ymd := p[0].split("-")
	var hm := p[1].split(":")
	return Ephemeris.julian_day(int(ymd[0]), int(ymd[1]), int(ymd[2]), float(hm[0]) + float(hm[1]) / 60.0)


static func _separation_deg(az1: float, el1: float, az2: float, el2: float) -> float:
	var e1 := deg_to_rad(el1)
	var e2 := deg_to_rad(el2)
	var c := sin(e1) * sin(e2) + cos(e1) * cos(e2) * cos(deg_to_rad(az1 - az2))
	return rad_to_deg(acos(clampf(c, -1.0, 1.0)))


func _initialize() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	_check("fixture format", fixture.get("format", "") == "openrc-moon-reference v1")
	_consistency_with_ephemeris()
	_svs(fixture.svs)
	for site: String in fixture.horizons.sites:
		_horizons(site, fixture.horizons.sites[site])
	_eclipses(fixture.eclipses)
	_phases(fixture.phases)
	_physics()
	_orientation()
	_calendar_and_next_events()
	_cost()
	var names := _worst.keys()
	names.sort()
	for k: String in names:
		print("  worst %s: %.6f" % [k, _worst[k]])
	print("%d/%d lunar checks passed" % [_count - _failures, _count])
	quit(1 if _failures > 0 else 0)


## Lunar's vector parallax must agree with Ephemeris.sky()'s elevation-only formula (spherical Earth: the same thing).
func _consistency_with_ephemeris() -> void:
	for when: Dictionary in [
			{year = 2026, month = 6, day = 30, hour = 1.25, utc_offset_h = 2.0, latitude_deg = 40.0, longitude_deg = -3.7},
			{year = 2026, month = 9, day = 26, hour = 20.25, utc_offset_h = 2.0, latitude_deg = 40.0, longitude_deg = -3.7},
			{year = 2027, month = 3, day = 22, hour = 5.58, utc_offset_h = 0.0, latitude_deg = -34.6, longitude_deg = -58.4}]:
		var sky := Ephemeris.sky(when)
		var st := Lunar.state(when)
		_near("ephemeris_agreement_deg", "Lunar vs Ephemeris.sky direction %s" % [when],
			_separation_deg(st.azimuth_deg, st.elevation_deg, sky.moon.azimuth_deg, sky.moon.elevation_deg), 0.0, 0.01)
		_near("ephemeris_illuminated", "Lunar vs Ephemeris.sky illuminated", st.illuminated, sky.moon.illuminated, 0.003)


func _svs(svs: Dictionary) -> void:
	for row: Dictionary in svs.rows:
		var st := Lunar.at_jd(_jd_of(row.utc), 0.0, 0.0, true)
		var tag: String = row.utc
		_near("svs_illuminated", "SVS illuminated %s" % tag, st.illuminated, float(row.illuminated), 0.001)
		_near("svs_diameter_rel", "SVS diameter %s" % tag, 2.0 * st.radius_deg * 3600.0 / float(row.diameter_arcsec), 1.0, 0.004)
		_near("svs_sub_earth_deg", "SVS sub-Earth lon %s" % tag, _wrap(st.libration_lon_deg - float(row.sub_earth_lon_deg)), 0.0, 0.15)
		_near("svs_sub_earth_deg", "SVS sub-Earth lat %s" % tag, st.libration_lat_deg, float(row.sub_earth_lat_deg), 0.15)
		_near("svs_sub_solar_deg", "SVS sub-solar lon %s" % tag, _wrap(st.subsolar_lon_deg - float(row.sub_solar_lon_deg)), 0.0, 0.05)
		_near("svs_sub_solar_deg", "SVS sub-solar lat %s" % tag, st.subsolar_lat_deg, float(row.sub_solar_lat_deg), 0.05)


func _horizons(site: String, data: Dictionary) -> void:
	var lat := float(data.latitude_deg)
	var lon := float(data.longitude_deg)
	for o: Dictionary in data.observer:
		var st := Lunar.at_jd(float(o.jd_ut), lat, lon)
		var tag := "%s %.4f" % [site, float(o.jd_ut)]
		_near("horizons_position_arcmin", "Horizons position %s" % tag,
			_separation_deg(st.azimuth_deg, st.elevation_deg, float(o.azimuth_deg), float(o.elevation_deg)) * 60.0, 0.0, 5.0)
		_near("horizons_illuminated", "Horizons illuminated %s" % tag, st.illuminated, float(o.illuminated), 0.002)
		_near("horizons_phase_angle_deg", "Horizons phase angle %s" % tag, st.phase_angle_deg, float(o.phase_angle_deg), 0.2)
		_near("horizons_diameter_rel", "Horizons diameter %s" % tag, 2.0 * st.radius_deg * 3600.0 / float(o.diameter_arcsec), 1.0, 0.004)
		_near("horizons_distance_rel", "Horizons distance %s" % tag, st.distance_km / float(o.distance_km), 1.0, 0.004)
		_near("horizons_libration_deg", "Horizons sub-observer lon %s" % tag, _wrap(st.libration_lon_deg - float(o.sub_observer_lon_deg)), 0.0, 0.1)
		_near("horizons_libration_deg", "Horizons sub-observer lat %s" % tag, st.libration_lat_deg, float(o.sub_observer_lat_deg), 0.1)
		_near("horizons_axis_angle_deg", "Horizons north-pole angle %s" % tag, _wrap(st.axis_angle_deg - float(o.north_pole_angle_deg)), 0.0, 0.1)
	if not data.has("rts"):
		return
	for e: Dictionary in data.rts:
		var jd := _jd_of(e.utc)
		var c := Lunar.calendar(jd)
		var ev := Lunar.events({year = c.year, month = c.month, day = c.day, utc_offset_h = 0.0, latitude_deg = lat, longitude_deg = lon})
		var key: String = e.event + "_h"
		_check("Horizons %s %s %s found" % [site, e.event, e.utc], ev.has(key), str(ev))
		if ev.has(key):
			# Horizons prints whole minutes (1-minute search step): ±2.5 min covers its rounding plus Schlyter's error.
			_near("horizons_rts_min", "Horizons %s %s %s" % [site, e.event, e.utc], float(ev[key]) * 60.0, float(c.hour) * 60.0, 2.5)
		if e.event == "transit" and ev.has("transit_elevation_deg"):
			_near("horizons_transit_elevation_deg", "Horizons transit elevation %s %s" % [site, e.utc],
				float(ev.transit_elevation_deg), float(e.elevation_deg), 0.08)


func _eclipses(data: Dictionary) -> void:
	var delta_t := float(data.delta_t_s)
	for row: Array in data.rows:
		var ymd: PackedStringArray = str(row[0]).split("-")
		var hms: Array = row[1]
		var jd_ut := Ephemeris.julian_day(int(ymd[0]), int(ymd[1]), int(ymd[2]),
			float(hms[0]) + float(hms[1]) / 60.0 + (float(hms[2]) - delta_t) / 3600.0)
		# Greatest eclipse = closest approach of the moon to the shadow axis: search ±60 min at 15 s.
		var best_jd := jd_ut
		var best := INF
		for k in range(-240, 241):
			var jd := jd_ut + k * 15.0 / 86400.0
			var ecl: Dictionary = Lunar.at_jd(jd, 0.0, 0.0, true).eclipse
			var offset: PackedFloat64Array = ecl.offset_ned
			var rho := sqrt(offset[0] * offset[0] + offset[1] * offset[1] + offset[2] * offset[2])
			if rho < best:
				best = rho
				best_jd = jd
		var e: Dictionary = Lunar.at_jd(best_jd, 0.0, 0.0, true).eclipse
		_near("eclipse_greatest_min", "eclipse %s greatest time" % row[0], (best_jd - jd_ut) * 1440.0, 0.0, 6.0)
		if row[3] == null:
			_check("penumbral eclipse %s has no umbral phase" % row[0], float(e.umbral_magnitude) < 0.0, str(e.umbral_magnitude))
			_check("penumbral eclipse %s touches the penumbra" % row[0], float(e.penumbral_magnitude) > 0.0, str(e.penumbral_magnitude))
		else:
			_near("eclipse_umbral_magnitude", "eclipse %s umbral magnitude" % row[0], float(e.umbral_magnitude), float(row[3]), 0.05)
	# A full moon without an eclipse misses even the penumbra (2026-01-03 10:03 UT).
	_check("no eclipse at the 2026-01-03 full moon",
		float(Lunar.at_jd(_jd_of("2026-01-03T10:03"), 0.0, 0.0, true).eclipse.penumbral_magnitude) < 0.0)
	_check("no shadow at new moon",
		float(Lunar.at_jd(_jd_of("2026-01-18T19:52"), 0.0, 0.0, true).eclipse.umbral_magnitude) == Lunar.NO_ECLIPSE)


func _phases(data: Dictionary) -> void:
	for utc: String in data.rows.full:
		var jd := _jd_of(utc)
		var st := Lunar.at_jd(jd, 0.0, 0.0, true)
		_check("full moon %s illuminated" % utc, st.illuminated > 0.998, str(st.illuminated))
		_check("waxing before full moon %s" % utc, bool(Lunar.at_jd(jd - 2.0 / 24.0, 0.0, 0.0, true).waxing))
		_check("waning after full moon %s" % utc, not bool(Lunar.at_jd(jd + 2.0 / 24.0, 0.0, 0.0, true).waxing))
	for utc: String in data.rows.new:
		var st := Lunar.at_jd(_jd_of(utc), 0.0, 0.0, true)
		_check("new moon %s dark" % utc, st.illuminated < 0.002, str(st.illuminated))


func _physics() -> void:
	_near("physics", "flux at full", Lunar.phase_flux(0.0), 1.0, 1e-12)
	_near("physics", "flux at quarter (KS91: 10^(-0.4*2.6024))", Lunar.phase_flux(90.0), 0.09099, 0.0001)
	_check("flux falls with phase", Lunar.phase_flux(120.0) < Lunar.phase_flux(60.0))
	var perigee := pow(Lunar.MEAN_DISTANCE_KM / 363300.0, 2.0) / pow(Lunar.MEAN_DISTANCE_KM / 405500.0, 2.0)
	_near("physics", "perigee/apogee brightness (NSSDC distances)", perigee, 1.246, 0.001)
	_near("physics", "airmass at the zenith", Lunar.airmass(90.0), 1.0, 0.001)
	_near("physics", "airmass on the horizon (Kasten-Young 37.9)", Lunar.airmass(0.0), 37.92, 0.05)
	var new_moon := Lunar.at_jd(_jd_of("2026-01-18T19:52"), 0.0, 0.0, true)
	var quarter := Lunar.at_jd(_jd_of("2026-01-26T04:47"), 0.0, 0.0, true)
	var full := Lunar.at_jd(_jd_of("2026-01-03T10:03"), 0.0, 0.0, true)
	# Observed earthshine: 3.6e-6 ... 3.6e-4 of the full moon's surface brightness (Montañés-Rodríguez et al. 2007).
	_check("earthshine at new moon in the observed band", new_moon.earthshine > 3.6e-6 and new_moon.earthshine < 3.6e-4, str(new_moon.earthshine))
	_check("earthshine fades toward full moon", quarter.earthshine < new_moon.earthshine and full.earthshine < quarter.earthshine * 0.1)
	_near("physics", "full-Earth earthshine (0.434 x (6371/d)^2)", new_moon.earthshine, 0.434 * pow(6371.0 / 357000.0, 2.0), 3e-5)


## The frames must be rotations, and the moon must turn over for a southern observer.
func _orientation() -> void:
	var st := Lunar.state({year = 2026, month = 3, day = 3, hour = 0.08, utc_offset_h = 0.0, latitude_deg = 40.4168, longitude_deg = -3.7038})
	var m: PackedFloat64Array = st.body_to_ned
	var worst := 0.0
	for i in 3:
		for j in 3:
			var d := m[i * 3] * m[j * 3] + m[i * 3 + 1] * m[j * 3 + 1] + m[i * 3 + 2] * m[j * 3 + 2]
			worst = maxf(worst, absf(d - (1.0 if i == j else 0.0)))
	_check("body_to_ned is orthonormal", worst < 1e-12, str(worst))
	var det := m[0] * (m[4] * m[8] - m[5] * m[7]) - m[1] * (m[3] * m[8] - m[5] * m[6]) + m[2] * (m[3] * m[7] - m[4] * m[6])
	_near("orientation", "body_to_ned is a proper rotation", det, 1.0, 1e-12)
	_near("orientation", "sun_ned is a unit vector", Vector3(st.sun_ned[0], st.sun_ned[1], st.sun_ned[2]).length(), 1.0, 1e-9)
	# Lunar north on the picture: near transit it points up from Madrid (moon in the south) and down from Buenos Aires
	# (moon in the north), where the moon is seen "upside down".
	_check("lunar north is up from Madrid at transit", _north_up_cos(st) > 0.9, str(_north_up_cos(st)))
	var south := Lunar.state({year = 2026, month = 8, day = 27, hour = 3.17, utc_offset_h = 0.0, latitude_deg = -34.6037, longitude_deg = -58.3816})
	_check("lunar north is down from Buenos Aires at transit", _north_up_cos(south) < -0.9, str(_north_up_cos(south)))


## Cosine between lunar north and the zenith, both projected on the plane of the sky at the moon.
static func _north_up_cos(st: Dictionary) -> float:
	var m: PackedFloat64Array = st.body_to_ned
	var az := deg_to_rad(st.azimuth_deg)
	var el := deg_to_rad(st.true_elevation_deg)
	var view := Vector3(cos(az) * cos(el), sin(az) * cos(el), -sin(el))
	var north := Vector3(m[2], m[5], m[8]) # body z in NED
	var up := Vector3(0.0, 0.0, -1.0)
	var n := (north - view * north.dot(view)).normalized()
	var u := (up - view * up.dot(view)).normalized()
	return n.dot(u)


func _calendar_and_next_events() -> void:
	for date: Array in [[2026, 1, 1, 0.0], [2028, 2, 29, 13.5], [2026, 12, 31, 23.75], [1999, 12, 31, 12.0]]:
		var c := Lunar.calendar(Ephemeris.julian_day(date[0], date[1], date[2], date[3]))
		_check("calendar round trip %s" % [date], c.year == date[0] and c.month == date[1] and c.day == date[2]
			and absf(float(c.hour) - float(date[3])) < 1e-6, str(c))
	var madrid := {year = 2026, month = 3, day = 2, hour = 12.0, utc_offset_h = 0.0, latitude_deg = 40.4168, longitude_deg = -3.7038}
	var rise := Lunar.next_event(madrid, "rise")
	_check("next rise is the same day", rise.get("day", 0) == 2, str(rise))
	_near("next_event_min", "next rise after 12:00 (Horizons 17:15)", float(rise.get("hour", 0.0)) * 60.0, 17.25 * 60.0, 2.5)
	madrid.hour = 18.0
	var set := Lunar.next_event(madrid, "set")
	_check("next set rolls to the next day", set.get("day", 0) == 3, str(set))
	_near("next_event_min", "next set after 18:00 (Horizons 03-03 06:43)", float(set.get("hour", 0.0)) * 60.0, 6.0 * 60.0 + 43.0, 2.5)
	var year_end := {year = 2026, month = 12, day = 31, hour = 23.9, utc_offset_h = 1.0, latitude_deg = 40.0, longitude_deg = -3.7}
	var after: Dictionary = Lunar.next_event(year_end, "transit")
	_check("next transit crosses the year", after.get("year", 0) == 2027 and after.get("month", 0) == 1, str(after))


func _cost() -> void:
	var t0 := Time.get_ticks_usec()
	for i in 200:
		Lunar.at_jd(2461300.5 + i * 0.37, 40.0, -3.7)
	var per_call := float(Time.get_ticks_usec() - t0) / 200.0
	print("  Lunar.at_jd cost: %.1f us per call" % per_call)
	_check("Lunar.at_jd stays cheap enough for a 30 s flow step", per_call < 2000.0, str(per_call))

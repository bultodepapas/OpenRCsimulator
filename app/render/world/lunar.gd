# FW-MOON-02 (docs/plans/moon.md): everything about the moon the renderer needs, from a date, a time and a place.
# Plain 64-bit floats (no Vector3/Basis), converted to render types only at the boundary. Visual only: nothing in
# sim/ or physics/ reads it.
#
# Position: Ephemeris (Schlyter moon, NOAA sun) made rigorous with vectors: topocentric parallax from the observer on a
# spherical Earth, then the refraction Ephemeris.sky() uses. Orientation: the IAU WGCCRE 2009 lunar rotation model
# (Archinal et al. 2011, Table 2; the same terms as astronomy-engine RotationAxis, MIT) with IAU 1976 precession
# (Meeus eq. 21.2-21.4). Nutation (< 20") and TT-UT (~69 s, < 0.6' of lunar motion) are ignored.
# Photometry: Krisciunas & Schaefer (1991) phase law with inverse-square distance. Earthshine: the Earth's geometric
# albedo with a Lambert-sphere phase (the form of Palle et al. 2016, eq. 1). Eclipses: the geocentric shadow cones with
# the Earth's radius enlarged by 88 km of atmosphere (as astronomy-engine CalcShadow).
# Checked against NASA SVS 5587, JPL Horizons and Espenak: tests/test_world_moon_lunar.gd and
# docs/research/field-world/FW-MOON-02/README.md. Angles in degrees; azimuth from north, clockwise; NED = north, east,
# down; the Moon-fixed (body) frame has x toward the mean sub-Earth point (0° E), z toward the north pole.
extends RefCounted

const Ephemeris := preload("res://render/world/ephemeris.gd")

const MOON_RADIUS_KM := 1737.4 # NSSDC
const EARTH_EQUATORIAL_RADIUS_KM := 6378.14 # the observer's distance from the centre; Schlyter's distance unit
const EARTH_MEAN_RADIUS_KM := 6371.0
## The phase law's reference distance (NSSDC mean Earth-Moon distance).
const MEAN_DISTANCE_KM := 384400.0
const AU_KM := 149597870.7
const SUN_RADIUS_KM := 695700.0
## Earth's shadow-casting radius: 6371 km plus 88 km of opaque atmosphere (astronomy-engine CalcShadow).
const SHADOW_EARTH_RADIUS_KM := 6459.0
## Earth's geometric albedo (NSSDC Earth fact sheet): the earthshine at full Earth.
const EARTH_GEOMETRIC_ALBEDO := 0.434
## Magnitudes reported when the moon is on the sun's side of the Earth (no shadow can reach it).
const NO_ECLIPSE := -99.0


## The moon for a place and a moment. `when` is the Ephemeris.sky() input: {year, month, day, hour (local, decimal),
## utc_offset_h, latitude_deg, longitude_deg (east positive)}. `geocentric` puts the observer at the Earth's centre
## (no parallax, no refraction), the frame of NASA's tables.
static func state(when: Dictionary, geocentric := false) -> Dictionary:
	var jd := Ephemeris.julian_day(int(when.year), int(when.month), int(when.day), float(when.hour) - float(when.utc_offset_h))
	return at_jd(jd, float(when.latitude_deg), float(when.longitude_deg), geocentric)


## As state(), at a Julian Day (UT). Returns:
##   jd, azimuth_deg, elevation_deg (apparent, centre), true_elevation_deg, present (refracted upper limb above the
##   horizon), distance_km (topocentric), radius_deg (angular semidiameter), phase_angle_deg (Sun-Moon-observer),
##   illuminated (0-1), waxing, bright_limb_deg (position angle of the bright limb's midpoint from celestial north
##   through east, Meeus 48.5), parallactic_deg (Meeus 14.1), axis_angle_deg (the north pole's position angle from
##   the true-of-date celestial north), libration_lon_deg / libration_lat_deg (sub-observer point),
##   subsolar_lon_deg / subsolar_lat_deg, body_to_ned (PackedFloat64Array, 9, row-major: v_ned = M * v_body),
##   sun_ned (unit vector from the Moon toward the Sun, NED), airmass (Kasten-Young), flux (sunlit brightness
##   relative to the full moon at the mean distance), earthshine (earthlight / sunlight irradiance at the Moon), and
##   eclipse: {umbral_magnitude, penumbral_magnitude, axis_ned (unit, anti-solar), offset_ned (moon centre from the
##   shadow axis, in moon radii), umbra_radius, penumbra_radius (moon radii at the moon's distance)}.
static func at_jd(jd: float, latitude_deg: float, longitude_deg: float, geocentric := false) -> Dictionary:
	var s := Ephemeris.sun(jd)
	var sun_g := _vec(s.ra_deg, s.dec_deg, float(s.distance_au) * AU_KM)
	var m := Ephemeris.moon(jd)
	var moon_g := _vec(m.ra_deg, m.dec_deg, float(m.distance_er) * EARTH_EQUATORIAL_RADIUS_KM)
	var lst := fposmod(Ephemeris.gmst_deg(jd) + longitude_deg, 360.0)
	var observer := PackedFloat64Array([0.0, 0.0, 0.0]) if geocentric else _vec(lst, latitude_deg, EARTH_EQUATORIAL_RADIUS_KM)
	var moon_t := _sub(moon_g, observer)
	var distance := _norm(moon_t)
	var ra := fposmod(rad_to_deg(atan2(moon_t[1], moon_t[0])), 360.0)
	var dec := rad_to_deg(asin(moon_t[2] / distance))

	var to_ned := equatorial_to_ned(latitude_deg, lst)
	var dir_ned := apply(to_ned, _scale(moon_t, 1.0 / distance))
	var true_el := rad_to_deg(asin(clampf(-dir_ned[2], -1.0, 1.0)))
	var el := true_el if geocentric else true_el + Ephemeris.refraction_deg(true_el)
	var radius := rad_to_deg(asin(MOON_RADIUS_KM / distance))

	var to_sun := _sub(sun_g, moon_g)
	var to_observer := _scale(moon_t, -1.0)
	var phase := rad_to_deg(acos(clampf(_dot(to_sun, to_observer) / (_norm(to_sun) * distance), -1.0, 1.0)))

	# Bright limb (Meeus 48.5) and parallactic angle (Meeus 14.1), from the topocentric position.
	var a0 := deg_to_rad(s.ra_deg)
	var d0 := deg_to_rad(s.dec_deg)
	var a := deg_to_rad(ra)
	var d := deg_to_rad(dec)
	var chi := rad_to_deg(atan2(cos(d0) * sin(a0 - a), sin(d0) * cos(d) - cos(d0) * sin(d) * cos(a0 - a)))
	var hour_angle := deg_to_rad(lst - ra)
	var q := rad_to_deg(atan2(sin(hour_angle), tan(deg_to_rad(latitude_deg)) * cos(d) - sin(d) * cos(hour_angle)))

	# Orientation: Moon-fixed -> ICRF (IAU) -> mean equator of date (precession) -> horizon (NED).
	var pole := moon_pole(jd)
	var body_to_equatorial := _mul(precession(jd), pole.body_to_icrf)
	var equatorial_to_body := _transpose(body_to_equatorial)
	var sub_observer := _lon_lat(apply(equatorial_to_body, to_observer))
	var sub_solar := _lon_lat(apply(equatorial_to_body, to_sun))
	var pole_date := apply(precession(jd), _vec(pole.ra_deg, pole.dec_deg, 1.0))
	var pa := atan2(pole_date[1], pole_date[0])
	var pd := asin(clampf(pole_date[2], -1.0, 1.0))
	var axis_angle := rad_to_deg(atan2(cos(pd) * sin(pa - a), sin(pd) * cos(d) - cos(pd) * sin(d) * cos(pa - a)))

	# Earthshine: the Earth seen from the Moon has the phase angle of the geocentric sun-moon elongation.
	var earth_moon := _norm(moon_g)
	var beta := acos(clampf(_dot(sun_g, moon_g) / (_norm(sun_g) * earth_moon), -1.0, 1.0))
	var earth_phase_law := ((PI - beta) * cos(beta) + sin(beta)) / PI

	return {
		jd = jd,
		azimuth_deg = fposmod(rad_to_deg(atan2(dir_ned[1], dir_ned[0])), 360.0),
		elevation_deg = el,
		true_elevation_deg = true_el,
		present = el + radius > 0.0,
		distance_km = distance,
		radius_deg = radius,
		phase_angle_deg = phase,
		illuminated = (1.0 + cos(deg_to_rad(phase))) / 2.0,
		waxing = fposmod(float(m.longitude_deg) - float(s.longitude_deg), 360.0) < 180.0,
		bright_limb_deg = fposmod(chi, 360.0),
		parallactic_deg = q,
		axis_angle_deg = fposmod(axis_angle, 360.0),
		libration_lon_deg = sub_observer[0],
		libration_lat_deg = sub_observer[1],
		subsolar_lon_deg = sub_solar[0],
		subsolar_lat_deg = sub_solar[1],
		body_to_ned = _mul(to_ned, body_to_equatorial),
		sun_ned = apply(to_ned, _scale(to_sun, 1.0 / _norm(to_sun))),
		airmass = airmass(el),
		flux = phase_flux(phase) * pow(MEAN_DISTANCE_KM / distance, 2.0),
		earthshine = EARTH_GEOMETRIC_ALBEDO * earth_phase_law * pow(EARTH_MEAN_RADIUS_KM / earth_moon, 2.0),
		eclipse = _eclipse(sun_g, moon_g, to_ned),
	}


## Sunlit brightness relative to the full moon for a phase angle (Krisciunas & Schaefer 1991:
## m = -12.73 + 0.026|a| + 4e-9 a^4; the full-moon term already contains the opposition surge).
static func phase_flux(phase_angle_deg: float) -> float:
	var a := absf(phase_angle_deg)
	return pow(10.0, -0.4 * (0.026 * a + 4.0e-9 * pow(a, 4.0)))


## Relative air mass at an apparent elevation (Kasten & Young 1989); the horizon value (37.9) below it.
static func airmass(elevation_deg: float) -> float:
	var h := maxf(elevation_deg, 0.0)
	return 1.0 / (sin(deg_to_rad(h)) + 0.50572 * pow(h + 6.07995, -1.6364))


## The IAU WGCCRE 2009 lunar pole and prime meridian at a Julian Day (TT taken as UT):
## {ra_deg, dec_deg, w_deg, body_to_icrf (PackedFloat64Array, 9, row-major)}.
static func moon_pole(jd: float) -> Dictionary:
	var d := jd - Ephemeris.J2000
	var t := d / 36525.0
	var e := PackedFloat64Array()
	for row: Array in [[125.045, -0.0529921], [250.089, -0.1059842], [260.008, 13.0120009], [176.625, 13.3407154],
			[357.529, 0.9856003], [311.589, 26.4057084], [134.963, 13.0649930], [276.617, 0.3287146],
			[34.226, 1.7484877], [15.134, -0.1589763], [119.743, 0.0036096], [239.961, 0.1643573],
			[25.053, 12.9590088]]:
		e.append(deg_to_rad(float(row[0]) + float(row[1]) * d))
	var ra0 := 269.9949 + 0.0031 * t - 3.8787 * sin(e[0]) - 0.1204 * sin(e[1]) + 0.0700 * sin(e[2]) \
		- 0.0172 * sin(e[3]) + 0.0072 * sin(e[5]) - 0.0052 * sin(e[9]) + 0.0043 * sin(e[12])
	var dec0 := 66.5392 + 0.0130 * t + 1.5419 * cos(e[0]) + 0.0239 * cos(e[1]) - 0.0278 * cos(e[2]) \
		+ 0.0068 * cos(e[3]) - 0.0029 * cos(e[5]) + 0.0009 * cos(e[6]) + 0.0008 * cos(e[9]) - 0.0009 * cos(e[12])
	var w := 38.3213 + (13.17635815 - 1.4e-12 * d) * d + 3.5610 * sin(e[0]) + 0.1208 * sin(e[1]) \
		- 0.0642 * sin(e[2]) + 0.0158 * sin(e[3]) + 0.0252 * sin(e[4]) - 0.0066 * sin(e[5]) - 0.0047 * sin(e[6]) \
		- 0.0046 * sin(e[7]) + 0.0028 * sin(e[8]) + 0.0052 * sin(e[9]) + 0.0040 * sin(e[10]) + 0.0019 * sin(e[11]) \
		- 0.0044 * sin(e[12])
	var m := _mul(_rz(deg_to_rad(ra0 + 90.0)), _mul(_rx(deg_to_rad(90.0 - dec0)), _rz(deg_to_rad(w))))
	return {ra_deg = ra0, dec_deg = dec0, w_deg = fposmod(w, 360.0), body_to_icrf = m}


## IAU 1976 precession from the J2000 mean equator to the mean equator of date (Meeus eq. 21.2-21.4), row-major.
static func precession(jd: float) -> PackedFloat64Array:
	var t := (jd - Ephemeris.J2000) / 36525.0
	var zeta := deg_to_rad((2306.2181 * t + 0.30188 * t * t + 0.017998 * t * t * t) / 3600.0)
	var z := deg_to_rad((2306.2181 * t + 1.09468 * t * t + 0.018203 * t * t * t) / 3600.0)
	var theta := deg_to_rad((2004.3109 * t - 0.42665 * t * t - 0.041833 * t * t * t) / 3600.0)
	return _mul(_rz(z), _mul(_ry(-theta), _rz(zeta)))


## Rotation from equatorial coordinates of date (x toward the equinox, z toward the pole) to the local horizon
## (north, east, down) at a latitude and local sidereal time, row-major.
static func equatorial_to_ned(latitude_deg: float, lst_deg: float) -> PackedFloat64Array:
	var p := deg_to_rad(latitude_deg)
	# After Rz(-lst): x' = the equator on the meridian, y' = east, z' = the celestial pole.
	var horizon := PackedFloat64Array([-sin(p), 0.0, cos(p), 0.0, 1.0, 0.0, -cos(p), 0.0, -sin(p)])
	return _mul(horizon, _rz(-deg_to_rad(lst_deg)))


## Upper-limb rise and set (refracted, as JPL Horizons' TVH) and meridian transit on the local calendar day of
## `when`, in local decimal hours: {rise_h, set_h, transit_h, transit_elevation_deg}. A key is absent when the event
## does not happen that day (once a month, or near the poles). 10-minute scan, then bisection to ~0.1 s.
static func events(when: Dictionary) -> Dictionary:
	var start := Ephemeris.julian_day(int(when.year), int(when.month), int(when.day), -float(when.utc_offset_h))
	var lat := float(when.latitude_deg)
	var lon := float(when.longitude_deg)
	var out := {}
	var step := 10.0 / 1440.0
	var prev := _horizon_sample(start, lat, lon)
	for i in range(1, 145):
		var jd := start + i * step
		var cur := _horizon_sample(jd, lat, lon)
		if (prev.limb > 0.0) != (cur.limb > 0.0):
			var key := "rise_h" if cur.limb > 0.0 else "set_h"
			if not out.has(key):
				out[key] = (_bisect(jd - step, jd, lat, lon, "limb") - start) * 24.0
		# Transit: the topocentric hour angle crosses zero going west (not its +-180 wrap).
		if prev.hour_angle < 0.0 and cur.hour_angle >= 0.0 and cur.hour_angle - prev.hour_angle < 90.0 \
				and not out.has("transit_h"):
			var t := _bisect(jd - step, jd, lat, lon, "hour_angle")
			out.transit_h = (t - start) * 24.0
			out.transit_elevation_deg = float(at_jd(t, lat, lon).elevation_deg)
		prev = cur
	return out


## The first `kind` ("rise", "set" or "transit") after `when`, searching up to three days ahead: a copy of `when`
## with the event's local date and hour, or {} if none (possible near the poles).
static func next_event(when: Dictionary, kind: String) -> Dictionary:
	var jd_when := Ephemeris.julian_day(int(when.year), int(when.month), int(when.day), float(when.hour) - float(when.utc_offset_h))
	var day := calendar(jd_when + float(when.utc_offset_h) / 24.0)
	for offset in 4:
		var probe := when.duplicate()
		var c := calendar(Ephemeris.julian_day(int(day.year), int(day.month), int(day.day), 12.0) + offset)
		probe.year = c.year
		probe.month = c.month
		probe.day = c.day
		var ev := events(probe)
		var key := kind + "_h"
		if ev.has(key):
			var jd_event := Ephemeris.julian_day(int(c.year), int(c.month), int(c.day), float(ev[key]) - float(when.utc_offset_h))
			if jd_event > jd_when + 0.5 / 86400.0:
				probe.hour = float(ev[key])
				return probe
	return {}


## Gregorian calendar date of a Julian Day (Meeus ch. 7): {year, month, day, hour}. Pass a local JD for local dates.
static func calendar(jd: float) -> Dictionary:
	var z := floori(jd + 0.5)
	var f := jd + 0.5 - z
	var alpha := floori((z - 1867216.25) / 36524.25)
	var a := z + 1 + alpha - floori(alpha / 4.0)
	var b := a + 1524
	var c := floori((b - 122.1) / 365.25)
	var d := floori(365.25 * c)
	var e := floori((b - d) / 30.6001)
	var day := b - d - floori(30.6001 * e)
	var month := e - 1 if e < 14 else e - 13
	var year := c - 4716 if month > 2 else c - 4715
	return {year = year, month = month, day = day, hour = f * 24.0}


## The Earth's umbra and penumbra at the moon (geocentric cones; the observer does not matter).
static func _eclipse(sun_g: PackedFloat64Array, moon_g: PackedFloat64Array, to_ned: PackedFloat64Array) -> Dictionary:
	var sun_distance := _norm(sun_g)
	var axis := _scale(sun_g, -1.0 / sun_distance)
	var along := _dot(moon_g, axis)
	var offset := _sub(moon_g, _scale(axis, along))
	var rho := _norm(offset)
	var umbra := SHADOW_EARTH_RADIUS_KM - along * (SUN_RADIUS_KM - SHADOW_EARTH_RADIUS_KM) / sun_distance
	var penumbra := SHADOW_EARTH_RADIUS_KM + along * (SUN_RADIUS_KM + SHADOW_EARTH_RADIUS_KM) / sun_distance
	var behind := along > 0.0
	return {
		umbral_magnitude = (umbra + MOON_RADIUS_KM - rho) / (2.0 * MOON_RADIUS_KM) if behind else NO_ECLIPSE,
		penumbral_magnitude = (penumbra + MOON_RADIUS_KM - rho) / (2.0 * MOON_RADIUS_KM) if behind else NO_ECLIPSE,
		axis_ned = apply(to_ned, axis),
		offset_ned = apply(to_ned, _scale(offset, 1.0 / MOON_RADIUS_KM)),
		umbra_radius = umbra / MOON_RADIUS_KM,
		penumbra_radius = penumbra / MOON_RADIUS_KM,
	}


## FW-MOON-10: the sunlight reaching a point of the moon `d` moon radii from the shadow axis, per channel (R, G, B at
## about 612, 550 and 465 nm), relative to the uneclipsed moon. Umbra and penumbra radii are in moon radii.
## Penumbra: the visible fraction of the solar disc behind Earth's limb, which is nearly straight at the sun's size:
## f = (π − acos t + t·√(1 − t²)) / π with t = 2·(d − r_u)/(r_p − r_u) − 1 (solar limb darkening ignored).
## Umbra: refracted sunlight as Ugolnikov, Maslov & Korotkiy measured it during the deep 15 June 2011 eclipse (arXiv
## 1106.6178, Fig. 2, outer western umbra at 677 and 503 nm, read to about ±0.1 dex; the deepest 503 nm parts from
## their text, ~10⁻⁶), against u = d/r_u, interpolated in log brightness to each channel's wavelength. The larger of
## the two joins them continuously at the umbra's edge. One eclipse's air: real eclipses vary (Danjon L 0–4).
const UMBRA_U := [0.0, 0.18, 0.25, 0.41, 0.52, 0.62, 0.79, 0.9, 1.0]
const UMBRA_LOG_677 := [-3.74, -3.74, -3.80, -3.52, -3.40, -3.26, -2.82, -2.6, -2.0]
const UMBRA_LOG_503 := [-6.0, -5.6, -5.45, -5.1, -4.8, -4.3, -3.52, -2.9, -2.0]
## Each channel's weight on the 677 nm curve against the 503 nm one: (λ − 503)/(677 − 503).
const UMBRA_CHANNEL_W := [0.63, 0.27, -0.22]


static func eclipse_transmission(d: float, umbra: float, penumbra: float) -> Vector3:
	if d >= penumbra or penumbra <= umbra:
		return Vector3.ONE
	var t := clampf(2.0 * (d - umbra) / (penumbra - umbra) - 1.0, -1.0, 1.0)
	var visible := (PI - acos(t) + t * sqrt(maxf(1.0 - t * t, 0.0))) / PI
	var u := clampf(d / maxf(umbra, 1e-6), 0.0, 1.0)
	var i := 0
	while i < UMBRA_U.size() - 2 and u > float(UMBRA_U[i + 1]):
		i += 1
	var k := (u - float(UMBRA_U[i])) / (float(UMBRA_U[i + 1]) - float(UMBRA_U[i]))
	var l677 := lerpf(float(UMBRA_LOG_677[i]), float(UMBRA_LOG_677[i + 1]), k)
	var l503 := lerpf(float(UMBRA_LOG_503[i]), float(UMBRA_LOG_503[i + 1]), k)
	var out := Vector3.ZERO
	for c in 3:
		var w: float = UMBRA_CHANNEL_W[c]
		out[c] = maxf(visible, pow(10.0, l503 + w * (l677 - l503)))
	return out


## FW-MOON-10: the eclipse's transmission averaged over the moon's disc (area-weighted: the full moon is flat), per
## channel; (1, 1, 1) outside the penumbra. Points of the disc are taken in the plane across the shadow axis, which
## the line of sight nearly follows at an eclipse (the full moon is within a degree of the anti-solar point).
static func eclipse_disc_factor(eclipse: Dictionary) -> Vector3:
	if eclipse.is_empty() or float(eclipse.get("penumbral_magnitude", NO_ECLIPSE)) <= 0.0:
		return Vector3.ONE
	var offset: PackedFloat64Array = eclipse.offset_ned
	var o := _norm(offset)
	var umbra := float(eclipse.umbra_radius)
	var penumbra := float(eclipse.penumbra_radius)
	var total := Vector3.ZERO
	var weight := 0.0
	var rings := 24
	var spokes := 48
	for ri in rings:
		var r := (ri + 0.5) / rings
		for si in spokes:
			var phi := TAU * (si + 0.5) / spokes
			total += eclipse_transmission(sqrt(o * o + r * r + 2.0 * o * r * cos(phi)), umbra, penumbra) * r
			weight += r
	return total / weight


## Upper-limb elevation and wrapped topocentric hour angle (degrees) for event searches; cheaper than at_jd().
static func _horizon_sample(jd: float, lat: float, lon: float) -> Dictionary:
	var m := Ephemeris.moon(jd)
	var moon_g := _vec(m.ra_deg, m.dec_deg, float(m.distance_er) * EARTH_EQUATORIAL_RADIUS_KM)
	var lst := fposmod(Ephemeris.gmst_deg(jd) + lon, 360.0)
	var moon_t := _sub(moon_g, _vec(lst, lat, EARTH_EQUATORIAL_RADIUS_KM))
	var distance := _norm(moon_t)
	var dir_ned := apply(equatorial_to_ned(lat, lst), _scale(moon_t, 1.0 / distance))
	var true_el := rad_to_deg(asin(clampf(-dir_ned[2], -1.0, 1.0)))
	var ra := rad_to_deg(atan2(moon_t[1], moon_t[0]))
	return {
		limb = true_el + Ephemeris.refraction_deg(true_el) + rad_to_deg(asin(MOON_RADIUS_KM / distance)),
		hour_angle = fposmod(lst - ra + 180.0, 360.0) - 180.0,
	}


static func _bisect(lo: float, hi: float, lat: float, lon: float, key: String) -> float:
	var f_lo: float = _horizon_sample(lo, lat, lon)[key]
	for i in 36:
		var mid := (lo + hi) / 2.0
		var f_mid: float = _horizon_sample(mid, lat, lon)[key]
		if (f_mid > 0.0) == (f_lo > 0.0):
			lo = mid
			f_lo = f_mid
		else:
			hi = mid
	return (lo + hi) / 2.0


static func _vec(ra_deg: float, dec_deg: float, r: float) -> PackedFloat64Array:
	var a := deg_to_rad(ra_deg)
	var d := deg_to_rad(dec_deg)
	return PackedFloat64Array([r * cos(d) * cos(a), r * cos(d) * sin(a), r * sin(d)])


static func _lon_lat(v: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([rad_to_deg(atan2(v[1], v[0])), rad_to_deg(asin(clampf(v[2] / _norm(v), -1.0, 1.0)))])


static func _sub(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([a[0] - b[0], a[1] - b[1], a[2] - b[2]])


static func _scale(a: PackedFloat64Array, k: float) -> PackedFloat64Array:
	return PackedFloat64Array([a[0] * k, a[1] * k, a[2] * k])


static func _dot(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


static func _norm(a: PackedFloat64Array) -> float:
	return sqrt(_dot(a, a))


## Row-major 3x3 product a * b.
static func _mul(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(9)
	for i in 3:
		for j in 3:
			out[i * 3 + j] = a[i * 3] * b[j] + a[i * 3 + 1] * b[3 + j] + a[i * 3 + 2] * b[6 + j]
	return out


## Row-major 3x3 matrix times a vector.
static func apply(m: PackedFloat64Array, v: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([m[0] * v[0] + m[1] * v[1] + m[2] * v[2], m[3] * v[0] + m[4] * v[1] + m[5] * v[2],
		m[6] * v[0] + m[7] * v[1] + m[8] * v[2]])


static func _transpose(m: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([m[0], m[3], m[6], m[1], m[4], m[7], m[2], m[5], m[8]])


static func _rx(a: float) -> PackedFloat64Array:
	return PackedFloat64Array([1.0, 0.0, 0.0, 0.0, cos(a), -sin(a), 0.0, sin(a), cos(a)])


static func _ry(a: float) -> PackedFloat64Array:
	return PackedFloat64Array([cos(a), 0.0, sin(a), 0.0, 1.0, 0.0, -sin(a), 0.0, cos(a)])


static func _rz(a: float) -> PackedFloat64Array:
	return PackedFloat64Array([cos(a), -sin(a), 0.0, sin(a), cos(a), 0.0, 0.0, 0.0, 1.0])

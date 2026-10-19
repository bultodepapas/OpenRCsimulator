# FIELD-WORLD-PLAN FW-20: where the sun and the moon are, from a date, a time and a place. Plain 64-bit floats only
# (no Vector3/Basis), so the result is reproducible and precise enough to aim the light, the sky and the star field.
# Sun: the NOAA solar-calculator formulas (after J. Meeus, Astronomical Algorithms, 2nd ed., ch. 25, low accuracy).
# Moon: P. Schlyter's orbital elements with the 12 + 5 + 2 largest perturbation terms ("How to compute planetary
# positions"), about 2 arc-minutes, then the topocentric parallax (up to ~1° near the horizon).
# Sidereal time: Meeus eq. 12.4. Refraction: Bennett (Meeus eq. 16.4), applied to apparent elevations above −1°.
# Angles in degrees; azimuth from north, clockwise (east = 90°); elevation above the horizon.
# Visual only: nothing in sim/ or physics/ reads it.
extends RefCounted

const J2000 := 2451545.0


## Julian Day of a Gregorian calendar date at `hour_ut` hours of Universal Time (Meeus ch. 7).
static func julian_day(year: int, month: int, day: int, hour_ut: float) -> float:
	var y := year
	var m := month
	if m <= 2:
		y -= 1
		m += 12
	var a := floori(y / 100.0)
	var b := 2 - a + floori(a / 4.0)
	return floorf(365.25 * (y + 4716)) + floorf(30.6001 * (m + 1)) + day + b - 1524.5 + hour_ut / 24.0


## Greenwich mean sidereal time in degrees [0, 360) (Meeus eq. 12.4).
static func gmst_deg(jd: float) -> float:
	var t := (jd - J2000) / 36525.0
	return fposmod(280.46061837 + 360.98564736629 * (jd - J2000) + t * t * (0.000387933 - t / 38710000.0), 360.0)


## Mean obliquity of the ecliptic in degrees, with the NOAA nutation term in `omega_deg`.
static func _obliquity_deg(t: float, omega_deg: float) -> float:
	var seconds := 21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))
	return 23.0 + (26.0 + seconds / 60.0) / 60.0 + 0.00256 * cos(deg_to_rad(omega_deg))


## The sun's apparent geocentric position: {ra_deg, dec_deg, longitude_deg (ecliptic), distance_au (Meeus eq. 25.5)}.
static func sun(jd: float) -> Dictionary:
	var t := (jd - J2000) / 36525.0
	var l0 := fposmod(280.46646 + t * (36000.76983 + t * 0.0003032), 360.0)
	var m := deg_to_rad(357.52911 + t * (35999.05029 - 0.0001537 * t))
	var c := sin(m) * (1.914602 - t * (0.004817 + 0.000014 * t)) + sin(2.0 * m) * (0.019993 - 0.000101 * t) \
		+ sin(3.0 * m) * 0.000289
	var omega := 125.04 - 1934.136 * t
	var lambda := deg_to_rad(l0 + c - 0.00569 - 0.00478 * sin(deg_to_rad(omega)))
	var eps := deg_to_rad(_obliquity_deg(t, omega))
	var e := 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
	return {
		ra_deg = fposmod(rad_to_deg(atan2(cos(eps) * sin(lambda), cos(lambda))), 360.0),
		dec_deg = rad_to_deg(asin(sin(eps) * sin(lambda))),
		longitude_deg = fposmod(rad_to_deg(lambda), 360.0),
		distance_au = 1.000001018 * (1.0 - e * e) / (1.0 + e * cos(m + deg_to_rad(c))),
	}


## The moon's geocentric position: {ra_deg, dec_deg, longitude_deg, latitude_deg (ecliptic), distance_er (Earth radii)}.
static func moon(jd: float) -> Dictionary:
	var d := jd - 2451543.5 # Schlyter's day number: days since 2000 January 0.0 UT
	var n := 125.1228 - 0.0529538083 * d
	var inc := 5.1454
	var w := 318.0634 + 0.1643573223 * d
	var a := 60.2666
	var e := 0.054900
	var mm := fposmod(115.3654 + 13.0649929509 * d, 360.0)
	var ms := fposmod(356.0470 + 0.9856002585 * d, 360.0)
	var ws := 282.9404 + 4.70935e-5 * d
	# Kepler's equation by Newton iteration (degrees).
	var ecc_anomaly := mm + rad_to_deg(e * sin(deg_to_rad(mm)) * (1.0 + e * cos(deg_to_rad(mm))))
	for i in 8:
		var step := (ecc_anomaly - rad_to_deg(e * sin(deg_to_rad(ecc_anomaly))) - mm) / (1.0 - e * cos(deg_to_rad(ecc_anomaly)))
		ecc_anomaly -= step
		if absf(step) < 1e-9:
			break
	var er := deg_to_rad(ecc_anomaly)
	var xv := a * (cos(er) - e)
	var yv := a * sqrt(1.0 - e * e) * sin(er)
	var v := atan2(yv, xv)
	var r := sqrt(xv * xv + yv * yv)
	var nr := deg_to_rad(n)
	var vw := v + deg_to_rad(w)
	var ir := deg_to_rad(inc)
	var xh := r * (cos(nr) * cos(vw) - sin(nr) * sin(vw) * cos(ir))
	var yh := r * (sin(nr) * cos(vw) + cos(nr) * sin(vw) * cos(ir))
	var zh := r * sin(vw) * sin(ir)
	var lon := rad_to_deg(atan2(yh, xh))
	var lat := rad_to_deg(atan2(zh, sqrt(xh * xh + yh * yh)))
	# Perturbations (Schlyter): longitude 12 terms, latitude 5, distance 2.
	var ls := ms + ws
	var lm := mm + w + n
	var dd := deg_to_rad(lm - ls)
	var f := deg_to_rad(lm - n)
	var m_m := deg_to_rad(mm)
	var m_s := deg_to_rad(ms)
	lon += -1.274 * sin(m_m - 2.0 * dd) + 0.658 * sin(2.0 * dd) - 0.186 * sin(m_s) - 0.059 * sin(2.0 * m_m - 2.0 * dd) \
		- 0.057 * sin(m_m - 2.0 * dd + m_s) + 0.053 * sin(m_m + 2.0 * dd) + 0.046 * sin(2.0 * dd - m_s) \
		+ 0.041 * sin(m_m - m_s) - 0.035 * sin(dd) - 0.031 * sin(m_m + m_s) - 0.015 * sin(2.0 * f - 2.0 * dd) \
		+ 0.011 * sin(m_m - 4.0 * dd)
	lat += -0.173 * sin(f - 2.0 * dd) - 0.055 * sin(m_m - f - 2.0 * dd) - 0.046 * sin(m_m + f - 2.0 * dd) \
		+ 0.033 * sin(f + 2.0 * dd) + 0.017 * sin(2.0 * m_m + f)
	r += -0.58 * cos(m_m - 2.0 * dd) - 0.46 * cos(2.0 * dd)
	var eq := ecliptic_to_equatorial(lon, lat, 23.4393 - 3.563e-7 * d)
	return {ra_deg = eq.ra_deg, dec_deg = eq.dec_deg, longitude_deg = fposmod(lon, 360.0), latitude_deg = lat, distance_er = r}


## Ecliptic (longitude, latitude) to equatorial (right ascension, declination), degrees.
static func ecliptic_to_equatorial(lon_deg: float, lat_deg: float, obliquity_deg: float) -> Dictionary:
	var l := deg_to_rad(lon_deg)
	var b := deg_to_rad(lat_deg)
	var eps := deg_to_rad(obliquity_deg)
	var ra := atan2(sin(l) * cos(eps) - tan(b) * sin(eps), cos(l))
	var dec := asin(sin(b) * cos(eps) + cos(b) * sin(eps) * sin(l))
	return {ra_deg = fposmod(rad_to_deg(ra), 360.0), dec_deg = rad_to_deg(dec)}


## Geometric horizontal coordinates for an observer at (latitude, east longitude): {azimuth_deg, elevation_deg}.
static func horizontal(ra_deg: float, dec_deg: float, latitude_deg: float, longitude_deg: float, jd: float) -> Dictionary:
	var h := deg_to_rad(gmst_deg(jd) + longitude_deg - ra_deg)
	var dec := deg_to_rad(dec_deg)
	var lat := deg_to_rad(latitude_deg)
	var elevation := asin(sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(h))
	var azimuth := atan2(-cos(dec) * sin(h), sin(dec) * cos(lat) - cos(dec) * sin(lat) * cos(h))
	return {azimuth_deg = fposmod(rad_to_deg(azimuth), 360.0), elevation_deg = rad_to_deg(elevation)}


## Atmospheric refraction in degrees for a true elevation (Bennett, inverted form by Saemundsson, Meeus eq. 16.4).
## Below the horizon the value only has to keep the apparent elevation continuous (the formula diverges at −5.11°):
## FW-MOON-06a tapers it linearly from its −1° value (0.65°) to zero at REFRACTION_ZERO_DEG. A hard cut at −1° made
## the sun and the moon drop 0.65° in one sky step, and the twilight sky, ambient light and exposure jump ~26 %.
const REFRACTION_TAPER_DEG := -1.0
const REFRACTION_ZERO_DEG := -3.0


static func refraction_deg(elevation_deg: float) -> float:
	if elevation_deg <= REFRACTION_ZERO_DEG:
		return 0.0
	if elevation_deg < REFRACTION_TAPER_DEG:
		return _saemundsson(REFRACTION_TAPER_DEG) * (elevation_deg - REFRACTION_ZERO_DEG) / (REFRACTION_TAPER_DEG - REFRACTION_ZERO_DEG)
	return _saemundsson(elevation_deg)


static func _saemundsson(elevation_deg: float) -> float:
	return 1.02 / tan(deg_to_rad(elevation_deg + 10.3 / (elevation_deg + 5.11))) / 60.0


## The sky for a place and a moment. `when`: {year, month, day, hour (local, decimal), utc_offset_h, latitude_deg,
## longitude_deg (east positive)}. Returns {jd, lst_deg, sun: {azimuth_deg, elevation_deg},
## moon: {azimuth_deg, elevation_deg, illuminated (0–1), waxing, phase_angle_deg}, latitude_deg, longitude_deg}.
## Elevations are apparent (refracted).
static func sky(when: Dictionary) -> Dictionary:
	var jd := julian_day(int(when.year), int(when.month), int(when.day), float(when.hour) - float(when.utc_offset_h))
	var lat := float(when.latitude_deg)
	var lon := float(when.longitude_deg)
	var s := sun(jd)
	var sun_h := horizontal(s.ra_deg, s.dec_deg, lat, lon, jd)
	sun_h.elevation_deg += refraction_deg(sun_h.elevation_deg)
	var m := moon(jd)
	var moon_h := horizontal(m.ra_deg, m.dec_deg, lat, lon, jd)
	# Topocentric parallax: the moon is ~60 Earth radii away, so the observer sees it lower by asin(cos(alt) / r).
	moon_h.elevation_deg -= rad_to_deg(asin(cos(deg_to_rad(moon_h.elevation_deg)) / m.distance_er))
	moon_h.elevation_deg += refraction_deg(moon_h.elevation_deg)
	# Phase from the sun–moon elongation (the sun's distance is ~390× the moon's, so its parallax is ignored).
	var elongation := acos(cos(deg_to_rad(s.longitude_deg - m.longitude_deg)) * cos(deg_to_rad(m.latitude_deg)))
	var phase_angle := PI - elongation
	moon_h.illuminated = (1.0 + cos(phase_angle)) / 2.0
	moon_h.phase_angle_deg = rad_to_deg(phase_angle)
	moon_h.waxing = fposmod(m.longitude_deg - s.longitude_deg, 360.0) < 180.0
	# FW-MOON-03: the place travels with the sky, so SkyState can ask Lunar for the full moon state.
	return {jd = jd, lst_deg = fposmod(gmst_deg(jd) + lon, 360.0), sun = sun_h, moon = moon_h, latitude_deg = lat,
		longitude_deg = lon}

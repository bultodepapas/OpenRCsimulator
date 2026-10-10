# TOD-02b: float64 USNO approximate solar position in true-north NED coordinates.
extends RefCounted

const MIN_YEAR: int = 2000
const MAX_YEAR: int = 2100
const SECONDS_PER_DAY: float = 86400.0
const J2000: float = 2451545.0
const ZENITH_HORIZONTAL_EPSILON: float = 1.0e-14


static func evaluate(config: Dictionary) -> Dictionary:
	var errors: Array[String] = _input_errors(config)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}

	var date: String = str(config["date"])
	var year: int = int(date.substr(0, 4))
	var month: int = int(date.substr(5, 2))
	var day: int = int(date.substr(8, 2))
	var local_seconds: int = int(config["local_seconds"])
	var offset_minutes: int = int(config["utc_offset_minutes"])
	var latitude_deg: float = float(config["latitude_deg"])
	var longitude_deg: float = float(config["longitude_deg"])
	var julian_date: float = _julian_day_number(year, month, day) - 0.5
	julian_date += float(local_seconds - offset_minutes * 60) / SECONDS_PER_DAY

	# USNO approximate coordinates: apparent ecliptic longitude -> RA/Dec.
	var days_from_j2000: float = julian_date - J2000
	var mean_anomaly_deg: float = _wrap_degrees(357.529 + 0.98560028 * days_from_j2000)
	var mean_longitude_deg: float = _wrap_degrees(280.459 + 0.98564736 * days_from_j2000)
	var mean_anomaly: float = deg_to_rad(mean_anomaly_deg)
	var apparent_longitude_deg: float = _wrap_degrees(
		mean_longitude_deg + 1.915 * sin(mean_anomaly) + 0.020 * sin(2.0 * mean_anomaly)
	)
	var apparent_longitude: float = deg_to_rad(apparent_longitude_deg)
	var obliquity: float = deg_to_rad(23.439 - 0.00000036 * days_from_j2000)
	var right_ascension_deg: float = _wrap_degrees(rad_to_deg(atan2(
		cos(obliquity) * sin(apparent_longitude), cos(apparent_longitude)
	)))
	var declination_deg: float = rad_to_deg(asin(clampf(
		sin(obliquity) * sin(apparent_longitude), -1.0, 1.0
	)))

	# USNO equation of time is apparent solar time minus mean solar time.
	# Wrap the mean-longitude minus RA difference before converting degrees to hours.
	var equation_of_time_hours: float = _wrap_signed_degrees(mean_longitude_deg - right_ascension_deg) / 15.0
	var utc_day_fraction: float = julian_date + 0.5 - floor(julian_date + 0.5)
	var utc_hours: float = utc_day_fraction * 24.0
	var hour_angle_deg: float = _wrap_signed_degrees(
		15.0 * (utc_hours + longitude_deg / 15.0 + equation_of_time_hours - 12.0)
	)

	var latitude: float = deg_to_rad(latitude_deg)
	var declination: float = deg_to_rad(declination_deg)
	var hour_angle: float = deg_to_rad(hour_angle_deg)
	var north: float = sin(declination) * cos(latitude) - cos(declination) * cos(hour_angle) * sin(latitude)
	var east: float = -cos(declination) * sin(hour_angle)
	var up: float = sin(declination) * sin(latitude) + cos(declination) * cos(hour_angle) * cos(latitude)
	var magnitude: float = sqrt(north * north + east * east + up * up)
	if not is_finite(magnitude) or magnitude <= 0.0:
		return {"ok": false, "errors": ["solar direction was not finite"] as Array[String]}
	north /= magnitude
	east /= magnitude
	up /= magnitude
	var horizontal: float = sqrt(north * north + east * east)
	var azimuth_deg: float = 0.0
	if horizontal > ZENITH_HORIZONTAL_EPSILON:
		azimuth_deg = _wrap_degrees(rad_to_deg(atan2(east, north)))
	var elevation_deg: float = rad_to_deg(asin(clampf(up, -1.0, 1.0)))
	var direction_ned: Array[float] = [north, east, -up]
	return {
		"ok": true,
		"azimuth_deg": azimuth_deg,
		"elevation_deg": elevation_deg,
		"hour_angle_deg": hour_angle_deg,
		"direction_ned": direction_ned,
		"julian_date": julian_date,
		"errors": [] as Array[String],
	}


static func _input_errors(config: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for field: String in ["date", "local_seconds", "utc_offset_minutes", "latitude_deg", "longitude_deg"]:
		if not config.has(field):
			errors.append("solar config is missing '%s'" % field)
	if not errors.is_empty():
		return errors
	var date_value: Variant = config.get("date")
	if typeof(date_value) != TYPE_STRING or not _valid_date(str(date_value)):
		errors.append("solar date must be a valid Gregorian date from 2000-01-01 through 2100-12-31")
	var seconds_value: Variant = config.get("local_seconds")
	if not _integer_in_range(seconds_value, 0, 86399):
		errors.append("solar local_seconds must be an integer from 0 through 86399")
	var offset_value: Variant = config.get("utc_offset_minutes")
	if not _integer_in_range(offset_value, -720, 840):
		errors.append("solar utc_offset_minutes must be an integer from -720 through 840")
	var latitude_value: Variant = config.get("latitude_deg")
	if not _finite_number(latitude_value) or float(latitude_value) < -90.0 or float(latitude_value) > 90.0:
		errors.append("solar latitude_deg must be finite and between -90 and 90")
	var longitude_value: Variant = config.get("longitude_deg")
	if not _finite_number(longitude_value) or float(longitude_value) < -180.0 or float(longitude_value) > 180.0:
		errors.append("solar longitude_deg must be finite and between -180 and 180")
	return errors


static func _julian_day_number(year: int, month: int, day: int) -> float:
	var a: int = floori(float(14 - month) / 12.0)
	var adjusted_year: int = year + 4800 - a
	var adjusted_month: int = month + 12 * a - 3
	var day_number: int = day + floori(float(153 * adjusted_month + 2) / 5.0)
	day_number += 365 * adjusted_year + floori(float(adjusted_year) / 4.0)
	day_number -= floori(float(adjusted_year) / 100.0)
	day_number += floori(float(adjusted_year) / 400.0) - 32045
	return float(day_number)


static func _valid_date(value: String) -> bool:
	if value.length() != 10 or value.substr(4, 1) != "-" or value.substr(7, 1) != "-":
		return false
	var year_text: String = value.substr(0, 4)
	var month_text: String = value.substr(5, 2)
	var day_text: String = value.substr(8, 2)
	if not _digits_only(year_text) or not _digits_only(month_text) or not _digits_only(day_text):
		return false
	var year: int = int(year_text)
	var month: int = int(month_text)
	var day: int = int(day_text)
	if year < MIN_YEAR or year > MAX_YEAR or month < 1 or month > 12:
		return false
	var days_in_month: Array[int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if month == 2 and _is_leap_year(year):
		days_in_month[1] = 29
	return day >= 1 and day <= days_in_month[month - 1]


static func _is_leap_year(year: int) -> bool:
	return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)


static func _digits_only(value: String) -> bool:
	if value.is_empty():
		return false
	for index: int in value.length():
		var codepoint: int = value.unicode_at(index)
		if codepoint < 48 or codepoint > 57:
			return false
	return true


static func _finite_number(value: Variant) -> bool:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return false
	return is_finite(float(value))


static func _integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	if not _finite_number(value):
		return false
	var number: float = float(value)
	return number >= float(minimum) and number <= float(maximum) and floor(number) == number


static func _wrap_degrees(value: float) -> float:
	var wrapped: float = fposmod(value, 360.0)
	return wrapped if wrapped >= 0.0 else wrapped + 360.0


static func _wrap_signed_degrees(value: float) -> float:
	var wrapped: float = fposmod(value + 180.0, 360.0)
	if wrapped < 0.0:
		wrapped += 360.0
	return wrapped - 180.0

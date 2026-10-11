# TOD-02a: validated fixed-time lighting input and deterministic presets.
extends RefCounted

const SolarPosition: Script = preload("res://environment/solar_position.gd")
const FORMAT: String = "openrc-lighting v1"
const MIN_YEAR: int = 2000
const MAX_YEAR: int = 2100
const SECONDS_PER_DAY: int = 86400
const OFFSET_MINUTES_MIN: int = -720
const OFFSET_MINUTES_MAX: int = 840
const SEARCH_STEP_SECONDS: int = 600
const SEARCH_SAMPLES: int = 144
const DAWN_ELEVATION_DEG: float = -6.0
const SUNSET_ELEVATION_DEG: float = -0.8333
const NIGHT_ELEVATION_DEG: float = -18.0
const REQUIRED_FIELDS: Array[String] = [
	"format", "mode", "date", "local_seconds", "utc_offset_minutes",
	"latitude_deg", "longitude_deg", "location_name",
]
const INDIVIDUAL_ARGS: Array[String] = ["time-of-day", "date", "lighting"]
const DEFAULTS: Dictionary = {
	"format": FORMAT,
	"mode": "legacy",
	"date": "2026-03-20",
	"local_seconds": 43200,
	"utc_offset_minutes": 0,
	"latitude_deg": 0.0,
	"longitude_deg": 0.0,
	"location_name": "Reference field (synthetic)",
}


static func defaults() -> Dictionary:
	return DEFAULTS.duplicate(true)


static func validate(raw: Variant) -> Dictionary:
	var errors: Array[String] = []
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("lighting config must be an object")
		return _failure(errors)

	var source: Dictionary = raw
	for field: String in REQUIRED_FIELDS:
		if not source.has(field):
			errors.append("missing required field '%s'" % field)
	for key: Variant in source.keys():
		if typeof(key) != TYPE_STRING or not REQUIRED_FIELDS.has(str(key)):
			errors.append("unknown lighting config field '%s'" % str(key))

	var format_value: Variant = source.get("format", null)
	if typeof(format_value) != TYPE_STRING or str(format_value) != FORMAT:
		errors.append("format must be '%s'" % FORMAT)

	var mode_value: Variant = source.get("mode", null)
	if typeof(mode_value) != TYPE_STRING or not ["legacy", "astronomical"].has(str(mode_value)):
		errors.append("mode must be 'legacy' or 'astronomical'")

	var date_value: Variant = source.get("date", null)
	if typeof(date_value) != TYPE_STRING or not _valid_date(str(date_value)):
		errors.append("date must be a valid Gregorian date from 2000-01-01 through 2100-12-31")

	var seconds_value: Variant = source.get("local_seconds", null)
	if not _integer_in_range(seconds_value, 0, SECONDS_PER_DAY - 1):
		errors.append("local_seconds must be an integer from 0 through 86399")

	var offset_value: Variant = source.get("utc_offset_minutes", null)
	if not _integer_in_range(offset_value, OFFSET_MINUTES_MIN, OFFSET_MINUTES_MAX):
		errors.append("utc_offset_minutes must be an integer from -720 through 840")

	var latitude_value: Variant = source.get("latitude_deg", null)
	if not _finite_number(latitude_value) or float(latitude_value) < -90.0 or float(latitude_value) > 90.0:
		errors.append("latitude_deg must be finite and between -90 and 90")

	var longitude_value: Variant = source.get("longitude_deg", null)
	if not _finite_number(longitude_value) or float(longitude_value) < -180.0 or float(longitude_value) > 180.0:
		errors.append("longitude_deg must be finite and between -180 and 180")

	var location_value: Variant = source.get("location_name", null)
	if typeof(location_value) != TYPE_STRING or str(location_value).strip_edges().is_empty() or str(location_value).length() > 80:
		errors.append("location_name must contain 1 through 80 non-blank characters")

	if not errors.is_empty():
		return _failure(errors)

	var normalized: Dictionary = {
		"format": str(format_value),
		"mode": str(mode_value),
		"date": str(date_value),
		"local_seconds": int(seconds_value),
		"utc_offset_minutes": int(offset_value),
		"latitude_deg": float(latitude_value),
		"longitude_deg": float(longitude_value),
		"location_name": str(location_value),
	}
	return {"ok": true, "config": normalized, "errors": errors}


static func parse_time(text: String) -> int:
	var parts: PackedStringArray = text.split(":", true)
	if parts.size() != 2 and parts.size() != 3:
		return -1
	for part: String in parts:
		if part.length() != 2 or not _digits_only(part):
			return -1
	var hours: int = int(parts[0])
	var minutes: int = int(parts[1])
	var seconds: int = int(parts[2]) if parts.size() == 3 else 0
	if hours < 0 or hours > 23 or minutes < 0 or minutes > 59 or seconds < 0 or seconds > 59:
		return -1
	return hours * 3600 + minutes * 60 + seconds


static func format_time(seconds: int) -> String:
	if seconds < 0 or seconds >= SECONDS_PER_DAY:
		return ""
	var hours: int = seconds / 3600
	var minutes: int = (seconds % 3600) / 60
	var remainder: int = seconds % 60
	if remainder == 0:
		return "%02d:%02d" % [hours, minutes]
	return "%02d:%02d:%02d" % [hours, minutes, remainder]


static func from_args(args: Dictionary) -> Dictionary:
	var config: Dictionary = defaults()
	var errors: Array[String] = []
	var has_individual: bool = false
	for key: String in INDIVIDUAL_ARGS:
		if args.has(key):
			has_individual = true
	if args.has("lighting-config"):
		if has_individual:
			errors.append("--lighting-config cannot be combined with --time-of-day, --date, or --lighting")
			return _failure(errors)
		var path_value: Variant = args.get("lighting-config")
		if typeof(path_value) != TYPE_STRING or str(path_value).strip_edges().is_empty():
			errors.append("--lighting-config requires a JSON file path")
			return _failure(errors)
		return _load_config_file(str(path_value))

	var has_clock_override: bool = args.has("time-of-day") or args.has("date")
	var has_lighting: bool = args.has("lighting")
	if has_lighting:
		var lighting_value: Variant = args.get("lighting")
		if typeof(lighting_value) != TYPE_STRING or not ["legacy", "astronomical"].has(str(lighting_value)):
			errors.append("--lighting must be 'legacy' or 'astronomical'")
		else:
			config["mode"] = str(lighting_value)
	elif has_clock_override:
		config["mode"] = "astronomical"

	if has_clock_override and has_lighting and str(args.get("lighting")) == "legacy":
		errors.append("--lighting=legacy cannot be combined with --time-of-day or --date")

	if args.has("date"):
		var date_value: Variant = args.get("date")
		if typeof(date_value) != TYPE_STRING or not _valid_date(str(date_value)):
			errors.append("--date must be a valid Gregorian date from 2000-01-01 through 2100-12-31")
		else:
			config["date"] = str(date_value)

	if args.has("time-of-day"):
		var time_value: Variant = args.get("time-of-day")
		if typeof(time_value) != TYPE_STRING:
			errors.append("--time-of-day must use HH:MM or HH:MM:SS")
		else:
			var parsed_seconds: int = parse_time(str(time_value))
			if parsed_seconds < 0:
				errors.append("--time-of-day must use a valid HH:MM or HH:MM:SS time")
			else:
				config["local_seconds"] = parsed_seconds

	if not errors.is_empty():
		return _failure(errors)
	return validate(config)


static func preset(config: Dictionary, id: String) -> Dictionary:
	var validated: Dictionary = validate(config)
	if not bool(validated.get("ok", false)):
		return validated
	var resolved: Dictionary = (validated["config"] as Dictionary).duplicate(true)
	if id == "legacy":
		resolved["mode"] = "legacy"
		return _success(resolved)
	if not ["dawn", "noon", "sunset", "night"].has(id):
		return _failure(["unknown lighting preset '%s'" % id])
	resolved["mode"] = "astronomical"

	var event_seconds: int = -1
	match id:
		"dawn":
			event_seconds = _find_crossing(resolved, DAWN_ELEVATION_DEG, true)
			if event_seconds < 0:
				return _failure(["civil dawn (rising -6° solar-center elevation) does not occur on this local date"])
		"sunset":
			event_seconds = _find_crossing(resolved, SUNSET_ELEVATION_DEG, false)
			if event_seconds < 0:
				return _failure(["sunset (descending -0.8333° solar-center elevation) does not occur on this local date"])
		"noon":
			event_seconds = _find_upper_transit(resolved)
			if event_seconds < 0:
				return _failure(["solar upper transit could not be evaluated on this local date"])
		"night":
			event_seconds = _find_extremum(resolved, false)
			if event_seconds < 0:
				return _failure(["solar lower transit could not be evaluated on this local date"])
			var minimum: float = _solar_elevation(resolved, event_seconds)
			if not is_finite(minimum) or minimum >= NIGHT_ELEVATION_DEG:
				return _failure(["astronomical night does not occur: the solar center stays at or above -18° on this local date"])

	resolved["local_seconds"] = event_seconds
	return _success(resolved)


static func _load_config_file(path: String) -> Dictionary:
	var resolved_path: String = path
	if not path.is_absolute_path() and not path.begins_with("res://") and not path.begins_with("user://"):
		resolved_path = ProjectSettings.globalize_path("res://").path_join(path)
	if not FileAccess.file_exists(resolved_path):
		return _failure(["lighting config file does not exist: %s" % path])
	var file: FileAccess = FileAccess.open(resolved_path, FileAccess.READ)
	if file == null:
		return _failure(["lighting config file cannot be read: %s" % path])
	var parser: JSON = JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		return _failure(["lighting config JSON is invalid at line %d: %s" % [parser.get_error_line(), parser.get_error_message()]])
	return validate(parser.data)


static func _find_crossing(config: Dictionary, target_elevation: float, rising: bool) -> int:
	var previous_seconds: int = 0
	var previous_elevation: float = _solar_elevation(config, previous_seconds)
	if not is_finite(previous_elevation):
		return -1
	for index: int in range(1, SEARCH_SAMPLES + 1):
		var current_seconds: int = mini(index * SEARCH_STEP_SECONDS, 86399)
		if current_seconds <= previous_seconds:
			continue
		var current_elevation: float = _solar_elevation(config, current_seconds)
		if not is_finite(current_elevation):
			return -1
		var crosses_up: bool = previous_elevation <= target_elevation and current_elevation >= target_elevation
		var crosses_down: bool = previous_elevation >= target_elevation and current_elevation <= target_elevation
		if (rising and crosses_up and current_elevation > previous_elevation) or (not rising and crosses_down and current_elevation < previous_elevation):
			return _refine_crossing(config, previous_seconds, current_seconds, target_elevation, rising)
		previous_seconds = current_seconds
		previous_elevation = current_elevation
	return -1


static func _refine_crossing(config: Dictionary, low_seconds: int, high_seconds: int, target: float, rising: bool) -> int:
	var low_elevation: float = _solar_elevation(config, low_seconds)
	var high_elevation: float = _solar_elevation(config, high_seconds)
	for _iteration: int in 32:
		if high_seconds - low_seconds <= 1:
			break
		var middle_seconds: int = (low_seconds + high_seconds) / 2
		var middle_elevation: float = _solar_elevation(config, middle_seconds)
		if rising:
			if middle_elevation >= target:
				high_seconds = middle_seconds
				high_elevation = middle_elevation
			else:
				low_seconds = middle_seconds
				low_elevation = middle_elevation
		else:
			if middle_elevation <= target:
				high_seconds = middle_seconds
				high_elevation = middle_elevation
			else:
				low_seconds = middle_seconds
				low_elevation = middle_elevation
	return low_seconds if absf(low_elevation - target) <= absf(high_elevation - target) else high_seconds


static func _find_extremum(config: Dictionary, maximize: bool) -> int:
	var best_seconds: int = 0
	var best_elevation: float = _solar_elevation(config, best_seconds)
	if not is_finite(best_elevation):
		return -1
	var previous_seconds: int = 0
	for index: int in range(1, SEARCH_SAMPLES + 1):
		var current_seconds: int = mini(index * SEARCH_STEP_SECONDS, 86399)
		if current_seconds <= previous_seconds:
			continue
		var current_elevation: float = _solar_elevation(config, current_seconds)
		if not is_finite(current_elevation):
			return -1
		if (maximize and current_elevation > best_elevation) or (not maximize and current_elevation < best_elevation):
			best_seconds = current_seconds
			best_elevation = current_elevation
		previous_seconds = current_seconds
	var low_seconds: int = maxi(0, best_seconds - SEARCH_STEP_SECONDS)
	var high_seconds: int = mini(86399, best_seconds + SEARCH_STEP_SECONDS)
	return _refine_extremum(config, low_seconds, high_seconds, maximize)


static func _find_upper_transit(config: Dictionary) -> int:
	var previous_seconds: int = 0
	var previous_hour_angle: float = _solar_hour_angle(config, previous_seconds)
	if not is_finite(previous_hour_angle):
		return -1
	if absf(previous_hour_angle) <= 1.0e-10:
		return previous_seconds
	for index: int in range(1, SEARCH_SAMPLES + 1):
		var current_seconds: int = mini(index * SEARCH_STEP_SECONDS, 86399)
		if current_seconds <= previous_seconds:
			continue
		var current_hour_angle: float = _solar_hour_angle(config, current_seconds)
		if not is_finite(current_hour_angle):
			return -1
		if previous_hour_angle < 0.0 and current_hour_angle >= 0.0:
			return _refine_upper_transit(config, previous_seconds, current_seconds)
		previous_seconds = current_seconds
		previous_hour_angle = current_hour_angle
	return -1


static func _refine_upper_transit(config: Dictionary, low_seconds: int, high_seconds: int) -> int:
	var low_angle: float = _solar_hour_angle(config, low_seconds)
	var high_angle: float = _solar_hour_angle(config, high_seconds)
	for _iteration: int in 32:
		if high_seconds - low_seconds <= 1:
			break
		var middle_seconds: int = (low_seconds + high_seconds) / 2
		var middle_angle: float = _solar_hour_angle(config, middle_seconds)
		if not is_finite(middle_angle):
			return -1
		if middle_angle >= 0.0:
			high_seconds = middle_seconds
			high_angle = middle_angle
		else:
			low_seconds = middle_seconds
			low_angle = middle_angle
	return low_seconds if absf(low_angle) <= absf(high_angle) else high_seconds


static func _refine_extremum(config: Dictionary, low_seconds: int, high_seconds: int, maximize: bool) -> int:
	var low: float = float(low_seconds)
	var high: float = float(high_seconds)
	const GOLDEN: float = 0.6180339887498949
	var first: float = high - GOLDEN * (high - low)
	var second: float = low + GOLDEN * (high - low)
	var first_value: float = _solar_elevation(config, int(round(first)))
	var second_value: float = _solar_elevation(config, int(round(second)))
	for _iteration: int in 40:
		if high - low <= 1.0:
			break
		var keep_left: bool = first_value >= second_value if maximize else first_value <= second_value
		if keep_left:
			high = second
			second = first
			second_value = first_value
			first = high - GOLDEN * (high - low)
			first_value = _solar_elevation(config, int(round(first)))
		else:
			low = first
			first = second
			first_value = second_value
			second = low + GOLDEN * (high - low)
			second_value = _solar_elevation(config, int(round(second)))
		if not is_finite(first_value) or not is_finite(second_value):
			return -1
	var candidate_seconds: Array[int] = [low_seconds, high_seconds, clampi(int(round(low)), low_seconds, high_seconds), clampi(int(round(high)), low_seconds, high_seconds)]
	var best_seconds: int = candidate_seconds[0]
	var best_elevation: float = _solar_elevation(config, best_seconds)
	for candidate: int in candidate_seconds:
		var candidate_elevation: float = _solar_elevation(config, candidate)
		if (maximize and candidate_elevation > best_elevation) or (not maximize and candidate_elevation < best_elevation):
			best_seconds = candidate
			best_elevation = candidate_elevation
	return best_seconds


static func _solar_elevation(config: Dictionary, seconds: int) -> float:
	var candidate: Dictionary = config.duplicate()
	candidate["local_seconds"] = seconds
	var result: Dictionary = SolarPosition.evaluate(candidate)
	if not bool(result.get("ok", false)):
		return NAN
	return float(result["elevation_deg"])


static func _solar_hour_angle(config: Dictionary, seconds: int) -> float:
	var candidate: Dictionary = config.duplicate()
	candidate["local_seconds"] = seconds
	var result: Dictionary = SolarPosition.evaluate(candidate)
	if not bool(result.get("ok", false)):
		return NAN
	return float(result["hour_angle_deg"])


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


static func _success(config: Dictionary) -> Dictionary:
	return {"ok": true, "config": config.duplicate(true), "errors": [] as Array[String]}


static func _failure(errors: Array[String]) -> Dictionary:
	return {"ok": false, "config": {}, "errors": errors.duplicate()}

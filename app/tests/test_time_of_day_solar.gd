# TOD-02b: independent solar position oracles, UTC conversion and polar geometry.
extends SceneTree

const Config: Script = preload("res://environment/time_of_day_config.gd")
const SolarPosition: Script = preload("res://environment/solar_position.gd")

var _checks: int = 0
var _failures: int = 0


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	_check_independent_oracles()
	_check_utc_conversion()
	_check_calendar_and_poles()
	_check_seasons_and_direction()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check_independent_oracles() -> void:
	var fixture: Dictionary = _load_oracles()
	_check("independent oracle fixture loads", fixture.get("format", "") == "openrc-solar-oracles v1")
	for oracle: Dictionary in fixture.get("cases", []):
		var result: Dictionary = SolarPosition.evaluate(oracle["config"])
		var label: String = str(oracle["id"])
		_check("%s evaluates" % label, bool(result.get("ok", false)), str(result.get("errors", [])))
		if not bool(result.get("ok", false)):
			continue
		var expected_azimuth: float = float(oracle["expected_azimuth_deg"])
		var expected_elevation: float = float(oracle["expected_elevation_deg"])
		var angular_tolerance: float = float(oracle["angular_tolerance_deg"])
		var expected_direction: Array[float] = _direction(expected_azimuth, expected_elevation)
		var actual_direction: Array[float] = result["direction_ned"]
		var angular_error: float = _direction_error_deg(actual_direction, expected_direction)
		_check("%s direction matches published USNO table" % label, angular_error <= angular_tolerance, str(angular_error))
		_check("%s elevation agrees with rounded table" % label, absf(float(result["elevation_deg"]) - expected_elevation) <= 0.06,
			str(result["elevation_deg"]))
		if expected_elevation < 80.0:
			_check("%s azimuth agrees with rounded table" % label,
				_circular_error(float(result["azimuth_deg"]), expected_azimuth) <= 0.11, str(result["azimuth_deg"]))
		_check("%s returns a finite unit NED direction" % label, _is_unit_direction(actual_direction), str(actual_direction))

	var noon_case: Dictionary = fixture["cases"][0]
	var jd: float = float(SolarPosition.evaluate(noon_case["config"])["julian_date"])
	_check("UTC Julian date matches USNO calendar convention", absf(jd - 2460380.0) < 1.0e-10, str(jd))

	for event_oracle: Dictionary in fixture.get("event_cases", []):
		var event_config: Dictionary = event_oracle["config"]
		var noon: Dictionary = Config.preset(event_config, "noon")
		var event_label: String = str(event_oracle["id"])
		_check("%s resolves upper transit" % event_label, bool(noon.get("ok", false)), str(noon.get("errors", [])))
		if not bool(noon.get("ok", false)):
			continue
		var event_configured: Dictionary = noon["config"]
		var expected_seconds: int = int(event_oracle["expected_local_seconds"])
		_check("%s matches NOAA solar-noon table" % event_label,
			absf(float(event_configured["local_seconds"] - expected_seconds)) <= float(event_oracle["time_tolerance_seconds"]),
			str(event_configured["local_seconds"]))
		var position: Dictionary = SolarPosition.evaluate(event_configured)
		_check("%s resolves an hour-angle-zero upper transit" % event_label,
			absf(float(position["hour_angle_deg"])) < 0.003, str(position["hour_angle_deg"]))


func _check_utc_conversion() -> void:
	var defaults: Dictionary = Config.defaults()
	var utc_config: Dictionary = defaults.duplicate(true)
	utc_config.date = "2024-03-10"
	utc_config.local_seconds = 43200
	utc_config.latitude_deg = 0.0
	utc_config.longitude_deg = 45.0
	var offset_config: Dictionary = utc_config.duplicate(true)
	offset_config.local_seconds = 25200
	offset_config.utc_offset_minutes = -300
	var utc_position: Dictionary = SolarPosition.evaluate(utc_config)
	var offset_position: Dictionary = SolarPosition.evaluate(offset_config)
	_check("UTC offset and local clock describe the same Julian instant",
		utc_position.julian_date == offset_position.julian_date)
	_check("same instant produces bit-identical sun vector",
		utc_position.direction_ned == offset_position.direction_ned)

	var local_midnight: Dictionary = defaults.duplicate(true)
	local_midnight.date = "2024-03-10"
	local_midnight.local_seconds = 1800
	local_midnight.utc_offset_minutes = 180
	var previous_utc_day: Dictionary = local_midnight.duplicate(true)
	previous_utc_day.date = "2024-03-09"
	previous_utc_day.local_seconds = 77400
	previous_utc_day.utc_offset_minutes = 0
	var first_position: Dictionary = SolarPosition.evaluate(local_midnight)
	var second_position: Dictionary = SolarPosition.evaluate(previous_utc_day)
	_check("positive offset crosses to the previous UTC date",
		first_position.julian_date == second_position.julian_date)
	_check("date rollover preserves the celestial direction",
		first_position.direction_ned == second_position.direction_ned)


func _check_calendar_and_poles() -> void:
	var config: Dictionary = Config.defaults()
	config.date = "2000-02-29"
	_check("solar evaluator accepts Gregorian leap day", SolarPosition.evaluate(config).ok)
	config.date = "2100-02-29"
	_check("solar evaluator rejects non-leap century day", not SolarPosition.evaluate(config).ok)
	config = Config.defaults()
	config.latitude_deg = true
	_check("solar evaluator rejects a boolean latitude", not SolarPosition.evaluate(config).ok)
	config = Config.defaults()
	config.longitude_deg = INF
	_check("solar evaluator rejects an infinite longitude", not SolarPosition.evaluate(config).ok)
	config = Config.defaults()
	config.local_seconds = 86400
	_check("solar evaluator rejects an out-of-day clock value", not SolarPosition.evaluate(config).ok)

	var north_pole: Dictionary = Config.defaults()
	north_pole.date = "2024-06-21"
	north_pole.latitude_deg = 90.0
	north_pole.local_seconds = 43200
	var south_pole: Dictionary = north_pole.duplicate(true)
	south_pole.latitude_deg = -90.0
	var north_position: Dictionary = SolarPosition.evaluate(north_pole)
	var south_position: Dictionary = SolarPosition.evaluate(south_pole)
	_check("north pole returns finite sun direction", bool(north_position.ok) and _is_unit_direction(north_position.direction_ned))
	_check("south pole returns finite sun direction", bool(south_position.ok) and _is_unit_direction(south_position.direction_ned))
	_check("pole elevation follows solstice declination sign",
		float(north_position.elevation_deg) > 23.0 and float(south_position.elevation_deg) < -23.0,
		"north=%s south=%s" % [north_position.elevation_deg, south_position.elevation_deg])
	_check("opposite poles have opposite solstice altitude",
		absf(float(north_position.elevation_deg) + float(south_position.elevation_deg)) < 1.0e-8)


func _check_seasons_and_direction() -> void:
	var north: Dictionary = Config.defaults()
	north.date = "2024-06-21"
	north.latitude_deg = 40.0
	north.longitude_deg = -105.0
	north.utc_offset_minutes = -360
	var north_summer: Dictionary = Config.preset(north, "noon")
	north.date = "2024-12-21"
	var north_winter: Dictionary = Config.preset(north, "noon")
	var north_summer_position: Dictionary = SolarPosition.evaluate(north_summer.config)
	var north_winter_position: Dictionary = SolarPosition.evaluate(north_winter.config)
	_check("northern summer noon is higher than winter noon",
		float(north_summer_position.elevation_deg) > float(north_winter_position.elevation_deg) + 40.0)

	var south: Dictionary = Config.defaults()
	south.latitude_deg = -40.0
	south.longitude_deg = 105.0
	south.utc_offset_minutes = 420
	south.date = "2024-12-21"
	var south_summer: Dictionary = Config.preset(south, "noon")
	south.date = "2024-06-21"
	var south_winter: Dictionary = Config.preset(south, "noon")
	var south_summer_position: Dictionary = SolarPosition.evaluate(south_summer.config)
	var south_winter_position: Dictionary = SolarPosition.evaluate(south_winter.config)
	_check("southern summer noon is higher than winter noon",
		float(south_summer_position.elevation_deg) > float(south_winter_position.elevation_deg) + 40.0)

	var fixture: Dictionary = _load_oracles()
	var morning: Dictionary = SolarPosition.evaluate(fixture["cases"][1]["config"])
	var afternoon: Dictionary = SolarPosition.evaluate(fixture["cases"][0]["config"])
	var morning_direction: Array[float] = morning["direction_ned"]
	var afternoon_direction: Array[float] = afternoon["direction_ned"]
	_check("morning sun has an eastward NED component", morning_direction[1] > 0.0)
	_check("afternoon sun has a westward NED component", afternoon_direction[1] < 0.0)
	_check("azimuth/elevation and NED vector agree", _consistent_components(afternoon))

	var near_zenith: Dictionary = SolarPosition.evaluate(fixture["cases"][2]["config"])
	_check("near-zenith direction remains finite and normalized", _is_unit_direction(near_zenith["direction_ned"]))
	_check("near-zenith horizontal component is small", sqrt(
		near_zenith.direction_ned[0] * near_zenith.direction_ned[0]
		+ near_zenith.direction_ned[1] * near_zenith.direction_ned[1]
	) < 0.08)


func _load_oracles() -> Dictionary:
	var repo_root: String = ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()
	var path: String = repo_root.path_join("docs/research/time-of-day-investigations/TOD-02/solar-oracles.json")
	var parser: JSON = JSON.new()
	var parse_result: Error = parser.parse(FileAccess.get_file_as_string(path))
	if parse_result != OK or typeof(parser.data) != TYPE_DICTIONARY:
		printerr("solar oracle fixture could not be loaded: ", parser.get_error_message())
		return {}
	return parser.data


func _direction(azimuth_deg: float, elevation_deg: float) -> Array[float]:
	var azimuth: float = deg_to_rad(azimuth_deg)
	var elevation: float = deg_to_rad(elevation_deg)
	var horizontal: float = cos(elevation)
	return [horizontal * cos(azimuth), horizontal * sin(azimuth), -sin(elevation)]


func _direction_error_deg(first: Array[float], second: Array[float]) -> float:
	var dot: float = first[0] * second[0] + first[1] * second[1] + first[2] * second[2]
	return rad_to_deg(acos(clampf(dot, -1.0, 1.0)))


func _circular_error(first_deg: float, second_deg: float) -> float:
	var difference: float = fposmod(first_deg - second_deg + 180.0, 360.0)
	if difference < 0.0:
		difference += 360.0
	return absf(difference - 180.0)


func _is_unit_direction(direction: Array[float]) -> bool:
	if direction.size() != 3:
		return false
	for component: float in direction:
		if not is_finite(component):
			return false
	var squared_magnitude: float = direction[0] * direction[0] + direction[1] * direction[1] + direction[2] * direction[2]
	return absf(squared_magnitude - 1.0) <= 1.0e-14


func _consistent_components(result: Dictionary) -> bool:
	var direction: Array[float] = result["direction_ned"]
	var expected: Array[float] = _direction(float(result["azimuth_deg"]), float(result["elevation_deg"]))
	for index: int in 3:
		if absf(direction[index] - expected[index]) > 1.0e-14:
			return false
	return true

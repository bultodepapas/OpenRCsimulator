# TOD-02a: strict fixed-time config, CLI, calendar and preset contracts.
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
	_check_defaults_and_validation()
	_check_calendar_and_time()
	_check_cli()
	_check_presets()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check_defaults_and_validation() -> void:
	var defaults: Dictionary = Config.defaults()
	var validated: Dictionary = Config.validate(defaults)
	_check("explicit synthetic defaults validate", bool(validated.ok) and validated.config == defaults, str(validated.errors))
	_check("defaults retain legacy daylight and complete reference location",
		defaults.format == "openrc-lighting v1" and defaults.mode == "legacy"
		and defaults.date == "2026-03-20" and defaults.local_seconds == 43200
		and defaults.utc_offset_minutes == 0 and defaults.latitude_deg == 0.0
		and defaults.longitude_deg == 0.0 and defaults.location_name == "Reference field (synthetic)"
		and Config.DEFAULTS == defaults)
	var detached: Dictionary = validated.config
	defaults.latitude_deg = 45.0
	_check("validated config does not alias input", detached.latitude_deg == 0.0)
	_check("fresh defaults do not alias prior returns", Config.defaults().latitude_deg == 0.0)

	_check("leap day 2000 is valid", _with(defaults, "date", "2000-02-29").ok)
	_check("non-leap century 2100 is valid on final day", _with(defaults, "date", "2100-12-31").ok)
	_check("leap day 2100 is rejected", not _with(defaults, "date", "2100-02-29").ok)
	_check("calendar below range is rejected", not _with(defaults, "date", "1999-12-31").ok)
	_check("calendar above range is rejected", not _with(defaults, "date", "2101-01-01").ok)

	_check("latitude endpoints are inclusive",
		_with(defaults, "latitude_deg", -90.0).ok and _with(defaults, "latitude_deg", 90.0).ok)
	_check("longitude endpoints are inclusive",
		_with(defaults, "longitude_deg", -180.0).ok and _with(defaults, "longitude_deg", 180.0).ok)
	_check("UTC offset endpoints are inclusive",
		_with(defaults, "utc_offset_minutes", -720).ok and _with(defaults, "utc_offset_minutes", 840).ok)

	_expect_invalid("boolean local seconds", "local_seconds", true, "local_seconds")
	_expect_invalid("fractional local seconds", "local_seconds", 43200.5, "local_seconds")
	_expect_invalid("seconds past local day", "local_seconds", 86400, "local_seconds")
	_expect_invalid("boolean offset", "utc_offset_minutes", false, "utc_offset_minutes")
	_expect_invalid("offset outside range", "utc_offset_minutes", 841, "utc_offset_minutes")
	_expect_invalid("boolean latitude", "latitude_deg", true, "latitude_deg")
	_expect_invalid("NaN latitude", "latitude_deg", NAN, "latitude_deg")
	_expect_invalid("infinite longitude", "longitude_deg", INF, "longitude_deg")
	_expect_invalid("latitude outside range", "latitude_deg", 90.0001, "latitude_deg")
	_expect_invalid("longitude outside range", "longitude_deg", -180.0001, "longitude_deg")
	_expect_invalid("wrong mode type", "mode", 1, "mode")
	_expect_invalid("wrong format", "format", "openrc-lighting v2", "format")
	_expect_invalid("blank location name", "location_name", "   ", "location_name")
	_expect_invalid("wrong location name type", "location_name", 27, "location_name")
	var missing: Dictionary = Config.defaults()
	missing.erase("longitude_deg")
	_check("required location field cannot be omitted", not Config.validate(missing).ok)
	var unknown: Dictionary = Config.defaults()
	unknown["timezone"] = "UTC"
	_check("unknown field is rejected", not Config.validate(unknown).ok)
	_check("non-object config is rejected", not Config.validate([1, 2, 3]).ok)


func _check_calendar_and_time() -> void:
	_check("HH:MM parses", Config.parse_time("07:05") == 25500)
	_check("HH:MM:SS parses", Config.parse_time("23:59:59") == 86399)
	_check("midnight parses", Config.parse_time("00:00") == 0)
	_check("hour precision is rejected", Config.parse_time("7:05") == -1)
	_check("space is rejected", Config.parse_time(" 07:05") == -1)
	_check("hour 24 is rejected", Config.parse_time("24:00") == -1)
	_check("minute 60 is rejected", Config.parse_time("12:60") == -1)
	_check("second 60 is rejected", Config.parse_time("12:00:60") == -1)
	_check("non-digits are rejected", Config.parse_time("aa:bb") == -1)
	_check("minute-aligned time formats without seconds", Config.format_time(43200) == "12:00")
	_check("second time formats with seconds", Config.format_time(43205) == "12:00:05")
	_check("last second formats", Config.format_time(86399) == "23:59:59")
	_check("out-of-range format input is refused", Config.format_time(-1).is_empty() and Config.format_time(86400).is_empty())


func _check_cli() -> void:
	var no_args: Dictionary = Config.from_args({})
	_check("no CLI flags keep legacy default", bool(no_args.ok) and no_args.config.mode == "legacy", str(no_args.errors))
	var clock_args: Dictionary = Config.from_args({"time-of-day": "18:25:30", "date": "2024-12-31", "aircraft": "ignored-by-lighting"})
	_check("clock/date flags select astronomical mode implicitly",
		bool(clock_args.ok) and clock_args.config.mode == "astronomical"
		and clock_args.config.date == "2024-12-31" and clock_args.config.local_seconds == 66330, str(clock_args.errors))
	var explicit_astronomical: Dictionary = Config.from_args({"lighting": "astronomical", "time-of-day": "06:30"})
	_check("explicit astronomical mode combines with a clock", bool(explicit_astronomical.ok) and explicit_astronomical.config.local_seconds == 23400)
	var explicit_legacy: Dictionary = Config.from_args({"lighting": "legacy"})
	_check("explicit legacy mode is valid alone", bool(explicit_legacy.ok) and explicit_legacy.config.mode == "legacy")
	_check("legacy mode and date are rejected as ambiguous",
		not Config.from_args({"lighting": "legacy", "date": "2024-01-01"}).ok)
	_check("bad lighting mode is rejected", not Config.from_args({"lighting": "automatic"}).ok)
	_check("bad time flag is rejected", not Config.from_args({"time-of-day": "24:00"}).ok)
	_check("bad date flag is rejected", not Config.from_args({"date": "2024-02-30"}).ok)
	_check("config file cannot be mixed with individual flags",
		not Config.from_args({"lighting-config": "/tmp/unused.json", "time-of-day": "12:00"}).ok)
	_check("missing config file fails without creating it",
		not Config.from_args({"lighting-config": "/tmp/openrc-tod-no-such-config.json"}).ok
		and not FileAccess.file_exists("/tmp/openrc-tod-no-such-config.json"))

	var repo_root: String = ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()
	var fixture_path: String = repo_root.path_join("docs/research/time-of-day-investigations/TOD-02/lighting-config.json")
	var before: String = FileAccess.get_file_as_string(fixture_path)
	var json_data: Variant = JSON.parse_string(before)
	var direct_json: Dictionary = Config.validate(json_data)
	_check("JSON-parsed integer-valued numbers normalize through validate",
		bool(direct_json.ok) and typeof(direct_json.config.local_seconds) == TYPE_INT
		and typeof(direct_json.config.utc_offset_minutes) == TYPE_INT, str(direct_json.errors))
	var parsed_config: Dictionary = json_data
	var fractional_json: Dictionary = parsed_config.duplicate(true)
	fractional_json["local_seconds"] = 45248.5
	_check("JSON-parsed fractional clock value remains invalid", not Config.validate(fractional_json).ok)
	var file_result: Dictionary = Config.from_args({"lighting-config": fixture_path})
	var after: String = FileAccess.get_file_as_string(fixture_path)
	_check("complete config file supplies coordinate and fixed offset",
		bool(file_result.ok) and file_result.config.latitude_deg == -33.425
		and file_result.config.longitude_deg == -70.567 and file_result.config.utc_offset_minutes == -240,
		str(file_result.errors))
	_check("config input leaves source file byte content unchanged", before == after)


func _check_presets() -> void:
	var base: Dictionary = Config.defaults()
	var legacy: Dictionary = Config.preset(base, "legacy")
	_check("legacy preset validates and retains complete reference config",
		bool(legacy.ok) and legacy.config.mode == "legacy"
		and legacy.config.date == base.date and legacy.config.latitude_deg == base.latitude_deg
		and legacy.config.local_seconds == base.local_seconds)
	_check("unknown preset returns an error", not Config.preset(base, "midday-ish").ok)

	for event_id: String in ["dawn", "noon", "sunset", "night"]:
		var event: Dictionary = Config.preset(base, event_id)
		_check("%s preset resolves" % event_id, bool(event.ok), str(event.errors))
		if not bool(event.ok):
			continue
		var position: Dictionary = SolarPosition.evaluate(event.config)
		_check("%s preset evaluates in astronomical mode" % event_id,
			bool(position.ok) and event.config.mode == "astronomical", str(position.errors))
		match event_id:
			"dawn":
				_check("dawn reaches civil-twilight reference", absf(float(position.elevation_deg) + 6.0) < 0.002)
			"noon":
				_check("noon is upper transit near equinox", float(position.elevation_deg) > 89.5)
			"sunset":
				_check("sunset reaches conventional apparent-horizon reference", absf(float(position.elevation_deg) + 0.8333) < 0.002)
			"night":
				_check("night preset chooses astronomical darkness", float(position.elevation_deg) < -18.0)

	var polar_day: Dictionary = base.duplicate(true)
	polar_day.date = "2024-06-21"
	polar_day.latitude_deg = 90.0
	_check("polar summer has no civil dawn", not Config.preset(polar_day, "dawn").ok)
	_check("polar summer has no sunset crossing", not Config.preset(polar_day, "sunset").ok)
	_check("polar summer has no astronomical night", not Config.preset(polar_day, "night").ok)
	_check("upper transit remains available in polar summer", Config.preset(polar_day, "noon").ok)

	var polar_night: Dictionary = base.duplicate(true)
	polar_night.date = "2024-12-21"
	polar_night.latitude_deg = 90.0
	_check("polar winter night selects its darkest instant", Config.preset(polar_night, "night").ok)


func _with(base: Dictionary, key: String, value: Variant) -> Dictionary:
	var candidate: Dictionary = base.duplicate(true)
	candidate[key] = value
	return Config.validate(candidate)


func _expect_invalid(label: String, key: String, value: Variant, error_fragment: String) -> void:
	var result: Dictionary = _with(Config.defaults(), key, value)
	var found: bool = false
	for error: String in result.get("errors", []):
		if error_fragment in error:
			found = true
	_check("reject %s" % label, not bool(result.get("ok", false)) and found, str(result.get("errors", [])))

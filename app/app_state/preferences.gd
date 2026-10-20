# Player preferences (MENU-PLAN §8, UI-01d): a small versioned user://settings.cfg, read and written only by the
# interactive route. Automation (any `--` argument) never reads or writes it. Calibration stays in its own file.
# Every value is validated by type and range: ConfigFile returns whatever type the file holds, not the default's.
extends RefCounted

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Landscapes := preload("res://landscapes/catalog.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const Conditions := preload("res://render/world/conditions.gd")
const WeatherSettings := preload("res://physics/wind_config.gd")
const TimeOfDay := preload("res://environment/time_of_day_config.gd")
const OverlaySettings := preload("res://render/overlays/overlay_settings.gd")
const SkyConfig := preload("res://environment/sky_appearance_config.gd")
const FailureConfig := preload("res://failures/config.gd")
const MoonConfig := preload("res://environment/moon_config.gd")

const NIGHT_FIELD_LIGHTING_CHOICES: Array[String] = ["club", "airfield", "off"]
const NIGHT_DEFAULTS := {"field_lighting": "club", "campfire": false}
## FUEL-07: the start fills Home offers for finite-fuel aircraft (fractions of the tank).
const FUEL_FILLS := [1.0, 0.75, 0.5, 0.25]

const DEFAULT_PATH := "user://settings.cfg"
const SCHEMA := 5
const LIGHTING_SCHEMA := 4
const LEGACY_SCHEMA := 1
## Interface languages: code -> name in that language (never translated). English is the default and the source
## language of every text; others come from res://i18n/<code>.po. The order is the order the Home button cycles.
const LANGUAGES := { "en": "English", "es": "Español" }
## aircraft: the catalog ID Home offers to fly (UI-05); an ID that is no longer in the catalog falls back to the default.
const DEFAULTS := {
	language = "en",
	first_flight_hint_seen = false,
	# UI-16: Home may ask GitHub once a day whether a newer release is published ([updates] check in the file).
	check_updates = true,
	aircraft = Catalog.DEFAULT_ID,
	landscape = Landscapes.DEFAULT_ID,
	start_choice = "runway",
	# UI-32: additive [flight] keys, no schema change. Rotorcraft keep their own start ("runway" is the pad), so
	# browsing between classes never rewrites the airplane start; Home's battery/fuel choices persist after Fly.
	rotorcraft_start_choice = "runway",
	battery_mode = "pack",
	fuel_fill = 1.0,
	# The FW Home preset remains an additive schema-1 field; selecting astronomical lighting clears it to "day".
	time_of_day = "evening",
	# UI-06d: only fresh interactive preferences use gentle moving air; technical routes remain calm by default.
	weather_config = WeatherSettings.GENTLE_PRACTICE,
	latency_marker = true,
	# A separate, visual-only selection. Its default preserves the original fixed daylight image.
	lighting_config = TimeOfDay.DEFAULTS,
	lighting_invalid = false,
	# HUD-06: flight overlays ([hud] in the file). An additive section: older builds ignore it, no schema change.
	hud = OverlaySettings.DEFAULTS,
	# FW-71: compact presentation choices, kept outside flight physics and the existing weather schema.
	night_field_lighting = "club",
	night_campfire = false,
	# FW-78: additive visual selection. Old preferences retain the exact classic sky.
	sky_config = SkyConfig.DEFAULTS,
	# EM-09: optional injected failures are off until the player opts in.
	failure_config = {"probability_percent": 0, "include_catastrophic": false, "notify": true},
	# FW-MOON-12: visual-only moon choices ([moon] config). An additive section like [hud]: no schema change.
	moon_config = MoonConfig.DEFAULTS,
}


## Returns the preferences: the DEFAULTS keys plus `writable` (false for a file from a newer version, which must
## not be overwritten) and `note` (what happened to an unusable file, "" when all is well).
static func load_from(path: String) -> Dictionary:
	var prefs := DEFAULTS.duplicate(true)
	prefs.failure_config = FailureConfig.defaults()
	prefs.writable = true
	prefs.note = ""
	if not FileAccess.file_exists(path):
		return prefs
	var cfg := ConfigFile.new()
	var schema: Variant = cfg.get_value("meta", "schema", -1) if cfg.load(path) == OK else -1
	if typeof(schema) != TYPE_INT or schema < 1:
		# Unreadable or not ours: keep it for inspection, start from defaults.
		var backup := path + ".bad"
		DirAccess.remove_absolute(backup)
		var err := DirAccess.rename_absolute(path, backup)
		prefs.note = "settings file unreadable: %s" % ("kept as " + backup.get_file() if err == OK else "could not keep a copy (error %d)" % err)
		return prefs
	if schema > SCHEMA:
		prefs.writable = false
		prefs.note = "settings from a newer version (schema %d): read where valid, never overwritten" % schema
	var language: Variant = cfg.get_value("ui", "language", DEFAULTS.language)
	if typeof(language) == TYPE_STRING and LANGUAGES.has(language):
		prefs.language = language
	var hint_seen: Variant = cfg.get_value("ui", "first_flight_hint_seen", DEFAULTS.first_flight_hint_seen)
	if typeof(hint_seen) == TYPE_BOOL:
		prefs.first_flight_hint_seen = hint_seen
	var check_updates: Variant = cfg.get_value("updates", "check", DEFAULTS.check_updates)
	if typeof(check_updates) == TYPE_BOOL:
		prefs.check_updates = check_updates
	var aircraft: Variant = cfg.get_value("flight", "aircraft", DEFAULTS.aircraft)
	if typeof(aircraft) == TYPE_STRING and Catalog.has(aircraft):
		prefs.aircraft = aircraft
	var landscape: Variant = cfg.get_value("flight", "landscape", DEFAULTS.landscape)
	if typeof(landscape) == TYPE_STRING and Landscapes.has(landscape):
		prefs.landscape = landscape
	var start_choice: Variant = cfg.get_value("flight", "start_choice", DEFAULTS.start_choice)
	# Missing or invalid choices use the product default; explicit airborne choices remain valid.
	prefs.start_choice = "runway" if FlightSession.runway_aircraft_supported(prefs.aircraft) or Catalog.is_rotorcraft(prefs.aircraft) else "airborne"
	if typeof(start_choice) == TYPE_STRING:
		if start_choice == "airborne" or (start_choice == "runway" and (FlightSession.runway_aircraft_supported(prefs.aircraft) or Catalog.is_rotorcraft(prefs.aircraft))) \
				or (start_choice == FlightSession.START_HALF_POWER and FlightSession.half_power_start_supported(prefs.aircraft)):
			prefs.start_choice = start_choice
	var rotorcraft_start: Variant = cfg.get_value("flight", "rotorcraft_start_choice", DEFAULTS.rotorcraft_start_choice)
	if typeof(rotorcraft_start) == TYPE_STRING and rotorcraft_start in ["runway", "airborne"]:
		prefs.rotorcraft_start_choice = rotorcraft_start
	var battery_mode: Variant = cfg.get_value("flight", "battery_mode", DEFAULTS.battery_mode)
	if typeof(battery_mode) == TYPE_STRING and battery_mode in Catalog.BATTERY_MODES:
		prefs.battery_mode = battery_mode
	var fuel_fill: Variant = cfg.get_value("flight", "fuel_fill", DEFAULTS.fuel_fill)
	if typeof(fuel_fill) == TYPE_FLOAT and fuel_fill in FUEL_FILLS:
		prefs.fuel_fill = fuel_fill
	var latency_marker: Variant = cfg.get_value("flight", "latency_marker", DEFAULTS.latency_marker)
	if typeof(latency_marker) == TYPE_BOOL:
		prefs.latency_marker = latency_marker
	var time_of_day: Variant = cfg.get_value("flight", "time_of_day", DEFAULTS.time_of_day)
	if typeof(time_of_day) == TYPE_STRING and Conditions.HOME_CHOICES.has(time_of_day):
		prefs.time_of_day = time_of_day
	var weather: Variant = cfg.get_value("flight", "weather_config", DEFAULTS.weather_config)
	var checked_weather := WeatherSettings.validate(weather)
	if checked_weather.ok:
		prefs.weather_config = checked_weather.config.duplicate(true)
	if cfg.has_section("hud"):
		var hud := {}
		for key: String in ["preset", "visible", "units", "stick_mode"]:
			if cfg.has_section_key("hud", key):
				hud[key] = cfg.get_value("hud", key)
		prefs.hud = OverlaySettings.validate(hud)
	if cfg.has_section_key("flight", "lighting_config"):
		var lighting: Variant = cfg.get_value("flight", "lighting_config", null)
		var checked_lighting: Dictionary = TimeOfDay.validate(lighting)
		if checked_lighting.get("ok", false):
			prefs.lighting_config = checked_lighting.config.duplicate(true)
		else:
			prefs.lighting_invalid = true
			prefs.time_of_day = "day" # invalid explicit lighting always recovers to the documented legacy daylight
			prefs.note = _append_note(prefs.note, "invalid time-of-day settings; using legacy daylight")
	var raw_failure_config: Variant = cfg.get_value("failures", "config", FailureConfig.defaults())
	var checked_failure_config: Dictionary = FailureConfig.validate(raw_failure_config)
	if checked_failure_config.get("ok", false):
		prefs.failure_config = checked_failure_config.config.duplicate(true)
	else:
		prefs.note = _append_note(prefs.note, "invalid failure settings; using defaults")
	var night_field_lighting: Variant = cfg.get_value("night", "field_lighting", DEFAULTS.night_field_lighting)
	if cfg.has_section_key("sky", "config"):
		var checked_sky: Dictionary = SkyConfig.validate(cfg.get_value("sky", "config"))
		if checked_sky.ok:
			prefs.sky_config = checked_sky.config
		else:
			prefs.note = _append_note(prefs.note, "invalid sky settings; using classic clouds")
	if typeof(night_field_lighting) == TYPE_STRING and NIGHT_FIELD_LIGHTING_CHOICES.has(night_field_lighting):
		prefs.night_field_lighting = night_field_lighting
	var night_campfire: Variant = cfg.get_value("night", "campfire", DEFAULTS.night_campfire)
	if typeof(night_campfire) == TYPE_BOOL:
		prefs.night_campfire = night_campfire
	if cfg.has_section_key("moon", "config"):
		var checked_moon: Dictionary = MoonConfig.validate(cfg.get_value("moon", "config"))
		if checked_moon.ok:
			prefs.moon_config = checked_moon.config
		else:
			prefs.note = _append_note(prefs.note, "invalid moon settings; using the real moon")
	return prefs


static func save_to(path: String, prefs: Dictionary) -> Error:
	if not prefs.get("writable", true):
		return ERR_FILE_NO_PERMISSION
	if typeof(prefs.get("latency_marker", DEFAULTS.latency_marker)) != TYPE_BOOL:
		return ERR_INVALID_DATA
	if not prefs.get("rotorcraft_start_choice", DEFAULTS.rotorcraft_start_choice) in ["runway", "airborne"] \
			or not prefs.get("battery_mode", DEFAULTS.battery_mode) in Catalog.BATTERY_MODES \
			or not float(prefs.get("fuel_fill", DEFAULTS.fuel_fill)) in FUEL_FILLS:
		return ERR_INVALID_DATA
	var checked_weather := WeatherSettings.validate(prefs.get("weather_config", DEFAULTS.weather_config))
	if not checked_weather.ok:
		return ERR_INVALID_DATA
	var checked_lighting: Dictionary = TimeOfDay.validate(prefs.get("lighting_config", DEFAULTS.lighting_config))
	if not checked_lighting.get("ok", false):
		return ERR_INVALID_DATA
	var checked_night: Dictionary = validate_night_options({
		"field_lighting": prefs.get("night_field_lighting", DEFAULTS.night_field_lighting),
		"campfire": prefs.get("night_campfire", DEFAULTS.night_campfire),
	})
	if not checked_night.ok:
		return ERR_INVALID_DATA
	var time_of_day: Variant = prefs.get("time_of_day", DEFAULTS.time_of_day)
	var checked_sky: Dictionary = SkyConfig.validate(prefs.get("sky_config", SkyConfig.DEFAULTS))
	if not checked_sky.ok:
		return ERR_INVALID_DATA
	var checked_failures: Dictionary = FailureConfig.validate(
		prefs.get("failure_config", FailureConfig.defaults())
	)
	if not checked_failures.get("ok", false):
		return ERR_INVALID_DATA
	if typeof(time_of_day) != TYPE_STRING or not Conditions.HOME_CHOICES.has(time_of_day):
		return ERR_INVALID_DATA
	var checked_moon: Dictionary = MoonConfig.validate(prefs.get("moon_config", MoonConfig.DEFAULTS))
	if not checked_moon.ok:
		return ERR_INVALID_DATA
	var cfg := ConfigFile.new()
	var weather_schema: int = 5 if checked_weather.config.format == WeatherSettings.COLUMN_FORMAT else (3 if checked_weather.config.format == WeatherSettings.ATMOSPHERE_FORMAT \
		else (2 if checked_weather.config.format == WeatherSettings.TURBULENCE_FORMAT else LEGACY_SCHEMA))
	var schema: int = maxi(LIGHTING_SCHEMA, weather_schema) if checked_lighting.config != TimeOfDay.defaults() else weather_schema
	cfg.set_value("meta", "schema", schema)
	cfg.set_value("ui", "language", prefs.language)
	cfg.set_value("ui", "first_flight_hint_seen", prefs.get("first_flight_hint_seen", false))
	cfg.set_value("updates", "check", prefs.get("check_updates", DEFAULTS.check_updates))
	cfg.set_value("flight", "aircraft", prefs.get("aircraft", DEFAULTS.aircraft))
	cfg.set_value("flight", "landscape", prefs.get("landscape", DEFAULTS.landscape))
	cfg.set_value("flight", "start_choice", prefs.get("start_choice", DEFAULTS.start_choice))
	cfg.set_value("flight", "rotorcraft_start_choice", prefs.get("rotorcraft_start_choice", DEFAULTS.rotorcraft_start_choice))
	cfg.set_value("flight", "battery_mode", prefs.get("battery_mode", DEFAULTS.battery_mode))
	cfg.set_value("flight", "fuel_fill", float(prefs.get("fuel_fill", DEFAULTS.fuel_fill)))
	cfg.set_value("flight", "time_of_day", time_of_day)
	cfg.set_value("flight", "latency_marker", prefs.get("latency_marker", DEFAULTS.latency_marker))
	cfg.set_value("flight", "weather_config", checked_weather.config.duplicate(true))
	if checked_lighting.config != TimeOfDay.defaults():
		cfg.set_value("flight", "lighting_config", checked_lighting.config.duplicate(true))
	cfg.set_value("night", "field_lighting", checked_night.options.field_lighting)
	cfg.set_value("night", "campfire", checked_night.options.campfire)
	cfg.set_value("sky", "config", checked_sky.config)
	cfg.set_value("failures", "config", checked_failures.config.duplicate(true))
	cfg.set_value("moon", "config", checked_moon.config)
	var hud: Dictionary = OverlaySettings.validate(prefs.get("hud", DEFAULTS.hud))
	cfg.set_value("hud", "preset", hud.preset)
	cfg.set_value("hud", "visible", hud.visible)
	cfg.set_value("hud", "units", hud.units)
	cfg.set_value("hud", "stick_mode", hud.stick_mode)
	return cfg.save(path)


## Night options are visual-only. Keep their product values strict in preferences and direct CLI launches.
static func validate_night_options(raw: Variant) -> Dictionary:
	if not raw is Dictionary or raw.size() != 2 or not raw.has_all(["field_lighting", "campfire"]):
		return {ok = false, options = {}, errors = PackedStringArray(["night options must contain field_lighting and campfire only"])}
	if typeof(raw.field_lighting) != TYPE_STRING or not NIGHT_FIELD_LIGHTING_CHOICES.has(raw.field_lighting):
		return {ok = false, options = {}, errors = PackedStringArray(["field_lighting must be club, airfield or off"])}
	if typeof(raw.campfire) != TYPE_BOOL:
		return {ok = false, options = {}, errors = PackedStringArray(["campfire must be a boolean"])}
	return {ok = true, options = {"field_lighting": raw.field_lighting, "campfire": raw.campfire}, errors = PackedStringArray()}


## The direct route always starts from product defaults and never consults saved preferences.
static func night_options_from_args(args: Dictionary) -> Dictionary:
	var options: Dictionary = NIGHT_DEFAULTS.duplicate(true)
	if args.has("field-lighting"):
		var field_lighting: Variant = args.get("field-lighting")
		if typeof(field_lighting) != TYPE_STRING or not NIGHT_FIELD_LIGHTING_CHOICES.has(field_lighting):
			return {ok = false, options = {}, errors = PackedStringArray(["--field-lighting must be club, airfield or off"])}
		options.field_lighting = field_lighting
	if args.has("campfire"):
		var campfire: Variant = args.get("campfire")
		if typeof(campfire) != TYPE_STRING or campfire not in ["on", "off"]:
			return {ok = false, options = {}, errors = PackedStringArray(["--campfire must be on or off"])}
		options.campfire = campfire == "on"
	return validate_night_options(options)


static func _append_note(existing: String, addition: String) -> String:
	return addition if existing.is_empty() else existing + "; " + addition

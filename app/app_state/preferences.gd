# Player preferences (MENU-PLAN §8, UI-01d): a small versioned user://settings.cfg, read and written only by the
# interactive route. Automation (any `--` argument) never reads or writes it. Calibration stays in its own file.
# Every value is validated by type and range: ConfigFile returns whatever type the file holds, not the default's.
extends RefCounted

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const Conditions := preload("res://render/world/conditions.gd")
const WeatherSettings := preload("res://physics/wind_config.gd")
const TimeOfDay := preload("res://environment/time_of_day_config.gd")
const OverlaySettings := preload("res://render/overlays/overlay_settings.gd")

const DEFAULT_PATH := "user://settings.cfg"
const SCHEMA := 4
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
	start_choice = "runway",
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
}


## Returns the preferences: the DEFAULTS keys plus `writable` (false for a file from a newer version, which must
## not be overwritten) and `note` (what happened to an unusable file, "" when all is well).
static func load_from(path: String) -> Dictionary:
	var prefs := DEFAULTS.duplicate(true)
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
	var start_choice: Variant = cfg.get_value("flight", "start_choice", DEFAULTS.start_choice)
	# Existing explicit airborne choices remain valid, and unsupported aircraft never inherit the runway default.
	prefs.start_choice = "airborne"
	if typeof(start_choice) == TYPE_STRING:
		if start_choice == "airborne" or (start_choice == "runway" and FlightSession.runway_aircraft_supported(prefs.aircraft)) \
				or (start_choice == FlightSession.START_HALF_POWER and FlightSession.half_power_start_supported(prefs.aircraft)):
			prefs.start_choice = start_choice
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
	return prefs


static func save_to(path: String, prefs: Dictionary) -> Error:
	if not prefs.get("writable", true):
		return ERR_FILE_NO_PERMISSION
	if typeof(prefs.get("latency_marker", DEFAULTS.latency_marker)) != TYPE_BOOL:
		return ERR_INVALID_DATA
	var checked_weather := WeatherSettings.validate(prefs.get("weather_config", DEFAULTS.weather_config))
	if not checked_weather.ok:
		return ERR_INVALID_DATA
	var checked_lighting: Dictionary = TimeOfDay.validate(prefs.get("lighting_config", DEFAULTS.lighting_config))
	if not checked_lighting.get("ok", false):
		return ERR_INVALID_DATA
	var time_of_day: Variant = prefs.get("time_of_day", DEFAULTS.time_of_day)
	if typeof(time_of_day) != TYPE_STRING or not Conditions.HOME_CHOICES.has(time_of_day):
		return ERR_INVALID_DATA
	var cfg := ConfigFile.new()
	var weather_schema: int = 3 if checked_weather.config.format == WeatherSettings.ATMOSPHERE_FORMAT \
		else (2 if checked_weather.config.format == WeatherSettings.TURBULENCE_FORMAT else LEGACY_SCHEMA)
	var schema: int = SCHEMA if checked_lighting.config != TimeOfDay.defaults() else weather_schema
	cfg.set_value("meta", "schema", schema)
	cfg.set_value("ui", "language", prefs.language)
	cfg.set_value("ui", "first_flight_hint_seen", prefs.get("first_flight_hint_seen", false))
	cfg.set_value("updates", "check", prefs.get("check_updates", DEFAULTS.check_updates))
	cfg.set_value("flight", "aircraft", prefs.get("aircraft", DEFAULTS.aircraft))
	cfg.set_value("flight", "start_choice", prefs.get("start_choice", DEFAULTS.start_choice))
	cfg.set_value("flight", "time_of_day", time_of_day)
	cfg.set_value("flight", "latency_marker", prefs.get("latency_marker", DEFAULTS.latency_marker))
	cfg.set_value("flight", "weather_config", checked_weather.config.duplicate(true))
	if checked_lighting.config != TimeOfDay.defaults():
		cfg.set_value("flight", "lighting_config", checked_lighting.config.duplicate(true))
	var hud: Dictionary = OverlaySettings.validate(prefs.get("hud", DEFAULTS.hud))
	cfg.set_value("hud", "preset", hud.preset)
	cfg.set_value("hud", "visible", hud.visible)
	cfg.set_value("hud", "units", hud.units)
	cfg.set_value("hud", "stick_mode", hud.stick_mode)
	return cfg.save(path)


static func _append_note(existing: String, addition: String) -> String:
	return addition if existing.is_empty() else existing + "; " + addition

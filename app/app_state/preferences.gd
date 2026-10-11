# Player preferences (MENU-PLAN §8, UI-01d): a small versioned user://settings.cfg, read and written only by the
# interactive route. Automation (any `--` argument) never reads or writes it. Calibration stays in its own file.
# Every value is validated by type and range: ConfigFile returns whatever type the file holds, not the default's.
extends RefCounted

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Conditions := preload("res://render/world/conditions.gd")

const DEFAULT_PATH := "user://settings.cfg"
const SCHEMA := 1
## Interface languages: code -> name in that language (never translated). English is the default and the source
## language of every text; others come from res://i18n/<code>.po. The order is the order the Home button cycles.
const LANGUAGES := { "en": "English", "es": "Español" }
## aircraft: the catalog ID Home offers to fly (UI-05); an ID that is no longer in the catalog falls back to the default.
## time_of_day: the Home time choice (FIELD-WORLD-PLAN FW-27); "day" is the calibrated fixed sun. An additive key:
## older builds ignore it, so the schema stays 1.
const DEFAULTS := { language = "en", first_flight_hint_seen = false, aircraft = Catalog.DEFAULT_ID, start_choice = "airborne",
	time_of_day = "day" }


## Returns the preferences: the DEFAULTS keys plus `writable` (false for a file from a newer version, which must
## not be overwritten) and `note` (what happened to an unusable file, "" when all is well).
static func load_from(path: String) -> Dictionary:
	var prefs := DEFAULTS.duplicate()
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
	var aircraft: Variant = cfg.get_value("flight", "aircraft", DEFAULTS.aircraft)
	if typeof(aircraft) == TYPE_STRING and Catalog.has(aircraft):
		prefs.aircraft = aircraft
	var start_choice: Variant = cfg.get_value("flight", "start_choice", DEFAULTS.start_choice)
	if typeof(start_choice) == TYPE_STRING and start_choice == "runway" and prefs.aircraft == Catalog.DEFAULT_ID:
		prefs.start_choice = start_choice
	var time_of_day: Variant = cfg.get_value("flight", "time_of_day", DEFAULTS.time_of_day)
	if typeof(time_of_day) == TYPE_STRING and Conditions.HOME_CHOICES.has(time_of_day):
		prefs.time_of_day = time_of_day
	return prefs


static func save_to(path: String, prefs: Dictionary) -> Error:
	if not prefs.get("writable", true):
		return ERR_FILE_NO_PERMISSION
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "schema", SCHEMA)
	cfg.set_value("ui", "language", prefs.language)
	cfg.set_value("ui", "first_flight_hint_seen", prefs.get("first_flight_hint_seen", false))
	cfg.set_value("flight", "aircraft", prefs.get("aircraft", DEFAULTS.aircraft))
	cfg.set_value("flight", "start_choice", prefs.get("start_choice", DEFAULTS.start_choice))
	cfg.set_value("flight", "time_of_day", prefs.get("time_of_day", DEFAULTS.time_of_day))
	return cfg.save(path)

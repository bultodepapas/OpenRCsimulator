extends SceneTree

const Preferences := preload("res://app_state/preferences.gd")
const SkyConfig := preload("res://environment/sky_appearance_config.gd")
const TimeOfDay := preload("res://environment/time_of_day_config.gd")
const WeatherSettings := preload("res://physics/wind_config.gd")

const PREFS := "user://test_sky_preferences_additive.cfg"

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run()
	_reset()
	print("sky preferences checks=%d failures=%d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _run() -> void:
	_reset()
	var initial := Preferences.load_from(PREFS)
	_check("missing additive sky setting defaults to classic", initial.sky_config == SkyConfig.DEFAULTS)
	_check("missing setting does not make preferences invalid", initial.writable and initial.note.is_empty())

	var sky: Dictionary = SkyConfig.for_preset("distant_storm")
	sky.seed = 86420
	sky.motion = "aloft"
	sky.wind_aloft_speed_mps = 23.5
	sky.wind_aloft_from_deg = 248.0
	sky.flashes = "reduced"
	sky.thunder_volume = 0.35
	var lighting := TimeOfDay.defaults()
	lighting.mode = "astronomical"
	lighting.date = "2026-06-21"
	lighting.local_seconds = 18 * 3600 + 30 * 60
	lighting.utc_offset_minutes = -300
	lighting.latitude_deg = 4.7
	lighting.longitude_deg = -74.1
	lighting.location_name = "Bogota field"
	var lighting_result := TimeOfDay.validate(lighting)
	_check("independent astronomical lighting fixture is valid", lighting_result.ok)
	var prefs: Dictionary = initial.duplicate(true)
	prefs.sky_config = sky
	prefs.lighting_config = lighting_result.config
	prefs.time_of_day = "day"
	var weather_result := WeatherSettings.validate(prefs.weather_config)
	_check("default flight weather is valid", weather_result.ok)
	var saved_weather: Dictionary = weather_result.config.duplicate(true)
	_check("valid sky selection saves", Preferences.save_to(PREFS, prefs) == OK)

	var stored := ConfigFile.new()
	_check("saved preferences are readable", stored.load(PREFS) == OK)
	_check("sky config is additive under its own section", stored.get_value("sky", "config", {}) == sky)
	var loaded := Preferences.load_from(PREFS)
	_check("saved sky preset and transport round-trip", loaded.sky_config == sky)
	_check("saved astronomical lighting round-trips independently", loaded.lighting_config == lighting_result.config)
	_check("saved time-of-day choice stays separate", loaded.time_of_day == "day")
	_check("saved flight weather remains separate", loaded.weather_config == saved_weather)

	var invalid_save: Dictionary = prefs.duplicate(true)
	invalid_save.sky_config.format = "openrc-sky-appearance v2"
	_check("save rejects a corrupt sky config", Preferences.save_to(PREFS, invalid_save) == ERR_INVALID_DATA)
	_check("rejected save leaves the last valid sky selection intact", Preferences.load_from(PREFS).sky_config == sky)

	# A valid preferences file with one corrupt additive sky field must keep all other readable settings.
	stored = ConfigFile.new()
	_check("valid preferences still reload before corruption injection", stored.load(PREFS) == OK)
	var corrupt_sky: Dictionary = sky.duplicate(true)
	corrupt_sky["motion"] = "followwind"
	stored.set_value("sky", "config", corrupt_sky)
	_check("test writes a corrupt sky field into preferences", stored.save(PREFS) == OK)
	var recovered := Preferences.load_from(PREFS)
	_check("corrupt sky falls back to exact classic config", recovered.sky_config == SkyConfig.DEFAULTS)
	_check("corrupt sky is reported without discarding other values", recovered.note.contains("invalid sky settings")
		and recovered.writable and recovered.lighting_config == lighting_result.config
		and recovered.weather_config == saved_weather and recovered.time_of_day == "day")

	# Schema-1 preferences predate the additive [sky] section and must still open with classic clouds.
	var old := ConfigFile.new()
	old.set_value("meta", "schema", 1)
	old.set_value("ui", "language", "en")
	old.set_value("flight", "time_of_day", "evening")
	_check("schema-1 file fixture saves", old.save(PREFS) == OK)
	var old_loaded := Preferences.load_from(PREFS)
	_check("older preferences without sky field use classic defaults", old_loaded.sky_config == SkyConfig.DEFAULTS)
	_check("older preferences remain writable", old_loaded.writable and old_loaded.note.is_empty())


func _reset() -> void:
	for path: String in [PREFS, PREFS + ".bad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(label: String, passed: bool) -> void:
	_checks += 1
	if passed:
		return
	_failures += 1
	push_error("sky preferences: %s" % label)

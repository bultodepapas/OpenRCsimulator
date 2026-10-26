extends SceneTree

const DisplayPreferences := preload("res://app_state/display_preferences.gd")
const PREFS := "user://test_lighting_preferences.cfg"
const LEGACY_PREFS := "user://test_lighting_preferences_legacy.cfg"
const FUTURE_PREFS := "user://test_lighting_preferences_future.cfg"

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run()
	_reset()
	print("lighting preferences checks=%d failures=%d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _run() -> void:
	_reset()
	var defaults := DisplayPreferences.load_from(PREFS)
	_check("missing file uses global aircraft-lighting defaults",
		defaults.aircraft_lighting_quality == "standard"
		and defaults.aircraft_lighting_reduced_flashes == false
		and defaults.aircraft_lighting_show_vfx == true)
	_check("quality choices and config suffixes are public and stable",
		DisplayPreferences.LIGHTING_QUALITY_LEVELS == ["low", "standard", "high"]
		and DisplayPreferences.AIRCRAFT_LIGHTING_FILE_KEYS == {
			"aircraft_lighting_quality": "quality",
			"aircraft_lighting_reduced_flashes": "reduced_flashes",
			"aircraft_lighting_show_vfx": "show_vfx",
		})

	var old_caller := {
		"window_mode": "borderless",
		"ui_scale": 1.25,
		"opaque_panels": true,
		"reduced_motion": false,
	}
	var old_caller_result: Dictionary = DisplayPreferences.validate(old_caller)
	_check("older callers remain valid and receive lighting defaults",
		old_caller_result.ok
		and old_caller_result.config.aircraft_lighting_quality == "standard"
		and old_caller_result.config.aircraft_lighting_reduced_flashes == false
		and old_caller_result.config.aircraft_lighting_show_vfx == true)

	var legacy := ConfigFile.new()
	legacy.set_value("meta", "schema", 1)
	legacy.set_value("display", "window_mode", "borderless")
	legacy.set_value("display", "ui_scale", 1.25)
	legacy.set_value("accessibility", "opaque_panels", true)
	legacy.set_value("accessibility", "reduced_motion", false)
	_check("legacy schema-1 fixture saves", legacy.save(LEGACY_PREFS) == OK)
	var migrated := DisplayPreferences.load_from(LEGACY_PREFS)
	_check("old schema-1 files without the section use defaults",
		migrated.writable and migrated.note.is_empty()
		and migrated.window_mode == "borderless"
		and migrated.aircraft_lighting_quality == "standard"
		and migrated.aircraft_lighting_reduced_flashes == false
		and migrated.aircraft_lighting_show_vfx == true)

	var candidate: Dictionary = DisplayPreferences.DEFAULTS.duplicate(true)
	candidate.window_mode = "borderless"
	candidate.window_resolution = "1920x1080"
	candidate.max_fps = 120
	candidate.camera_fov = 70
	candidate.aircraft_lighting_quality = "high"
	candidate.aircraft_lighting_reduced_flashes = true
	candidate.aircraft_lighting_show_vfx = false
	_check("lighting preferences validate", DisplayPreferences.validate(candidate).ok)
	_check("lighting preferences save", DisplayPreferences.save_to(PREFS, candidate) == OK)
	var stored := ConfigFile.new()
	_check("saved lighting preferences are readable", stored.load(PREFS) == OK)
	_check("schema-1 keys are isolated in the aircraft-lighting section",
		stored.get_value("meta", "schema", -1) == 1
		and stored.get_value("aircraft_lighting", "quality", "") == "high"
		and stored.get_value("aircraft_lighting", "reduced_flashes", false) == true
		and stored.get_value("aircraft_lighting", "show_vfx", true) == false
		and not stored.has_section_key("graphics", "quality")
		and not stored.has_section_key("aircraft_lighting", "bloom"))
	var reloaded := DisplayPreferences.load_from(PREFS)
	_check("lighting choices round-trip",
		reloaded.aircraft_lighting_quality == "high"
		and reloaded.aircraft_lighting_reduced_flashes
		and not reloaded.aircraft_lighting_show_vfx)
	_check("lighting save preserves independent display and camera values",
		reloaded.window_mode == "borderless"
		and reloaded.window_resolution == "1920x1080"
		and reloaded.max_fps == 120
		and reloaded.camera_fov == 70)

	var invalid := ConfigFile.new()
	invalid.set_value("meta", "schema", 1)
	invalid.set_value("display", "window_mode", "borderless")
	invalid.set_value("graphics", "max_fps", 60)
	invalid.set_value("aircraft_lighting", "quality", "ultra")
	invalid.set_value("aircraft_lighting", "reduced_flashes", "true")
	invalid.set_value("aircraft_lighting", "show_vfx", false)
	_check("malformed lighting fixture saves", invalid.save(PREFS) == OK)
	var recovered := DisplayPreferences.load_from(PREFS)
	_check("bad enum and bool each fall back independently",
		recovered.aircraft_lighting_quality == "standard"
		and recovered.aircraft_lighting_reduced_flashes == false
		and recovered.aircraft_lighting_show_vfx == false
		and recovered.window_mode == "borderless"
		and recovered.max_fps == 60)
	_check("malformed lighting values add a recovery note",
		recovered.note.contains("quality") and recovered.note.contains("reduced_flashes"))

	var invalid_candidate: Dictionary = DisplayPreferences.DEFAULTS.duplicate(true)
	invalid_candidate.aircraft_lighting_quality = "ultra"
	_check("unsupported lighting quality is rejected", not DisplayPreferences.validate(invalid_candidate).ok)
	invalid_candidate.aircraft_lighting_quality = "low"
	invalid_candidate.aircraft_lighting_show_vfx = 1
	_check("non-boolean lighting values are rejected", not DisplayPreferences.validate(invalid_candidate).ok)

	var future_text := "[meta]\nschema=99\n[aircraft_lighting]\nquality=\"high\"\nreduced_flashes=true\nshow_vfx=false\n[graphics]\nmax_fps=60\n"
	var future_file := FileAccess.open(FUTURE_PREFS, FileAccess.WRITE)
	_check("future-schema fixture opens", future_file != null)
	if future_file != null:
		future_file.store_string(future_text)
		future_file.close()
	var future := DisplayPreferences.load_from(FUTURE_PREFS)
	_check("future-schema lighting values remain readable and protected",
		not future.writable and future.note.contains("newer version")
		and future.aircraft_lighting_quality == "high"
		and future.aircraft_lighting_reduced_flashes
		and not future.aircraft_lighting_show_vfx)
	var before_save := FileAccess.get_file_as_string(FUTURE_PREFS)
	_check("future-schema settings refuse overwrite and preserve bytes",
		DisplayPreferences.save_to(FUTURE_PREFS, candidate) == ERR_FILE_NO_PERMISSION
		and FileAccess.get_file_as_string(FUTURE_PREFS) == before_save)


func _reset() -> void:
	for path: String in [PREFS, LEGACY_PREFS, FUTURE_PREFS]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(label: String, passed: bool) -> void:
	_checks += 1
	if passed:
		return
	_failures += 1
	push_error("lighting preferences: %s" % label)

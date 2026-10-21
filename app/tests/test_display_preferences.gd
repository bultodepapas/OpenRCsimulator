extends SceneTree

const DisplayPreferences := preload("res://app_state/display_preferences.gd")
const PREFS := "user://test_display_preferences.cfg"

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run()
	_reset()
	print("display preferences checks=%d failures=%d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _run() -> void:
	_reset()
	var initial := DisplayPreferences.load_from(PREFS)
	_check("missing file loads display defaults", initial.window_mode == "windowed"
		and initial.window_resolution == "auto" and initial.max_fps == 0
		and initial.vsync_mode == "enabled" and initial.msaa_3d == 2)
	_check("missing file is writable without a warning", initial.writable and initial.note.is_empty())

	var old_candidate := {
		"window_mode": "borderless",
		"ui_scale": 1.25,
		"opaque_panels": true,
		"reduced_motion": false,
	}
	var old_candidate_result: Dictionary = DisplayPreferences.validate(old_candidate)
	_check("old caller shape remains valid and fills optional display defaults", old_candidate_result.ok
		and old_candidate_result.config.window_resolution == "auto"
		and old_candidate_result.config.max_fps == 0
		and old_candidate_result.config.vsync_mode == "enabled"
		and old_candidate_result.config.msaa_3d == 2)

	var legacy := ConfigFile.new()
	legacy.set_value("meta", "schema", 1)
	legacy.set_value("display", "window_mode", "borderless")
	legacy.set_value("display", "ui_scale", 1.25)
	legacy.set_value("accessibility", "opaque_panels", true)
	legacy.set_value("accessibility", "reduced_motion", false)
	legacy.set_value("audio", "menu_volume", 0.2)
	legacy.set_value("audio", "master_volume", 0.8)
	_check("schema-1 legacy fixture saves", legacy.save(PREFS) == OK)
	var migrated := DisplayPreferences.load_from(PREFS)
	_check("legacy file preserves existing display and accessibility choices", migrated.window_mode == "borderless"
		and migrated.ui_scale == 1.25 and migrated.opaque_panels and not migrated.reduced_motion)
	_check("legacy file receives defaults for every new optional control", migrated.window_resolution == "auto"
		and migrated.max_fps == 0 and migrated.vsync_mode == "enabled" and migrated.msaa_3d == 2)
	_check("legacy schema stays writable without a warning", migrated.writable and migrated.note.is_empty())
	_check("legacy settings rewrite succeeds with additive defaults", DisplayPreferences.save_to(PREFS, migrated) == OK)
	var rewritten := ConfigFile.new()
	_check("rewritten schema-1 file is readable", rewritten.load(PREFS) == OK)
	_check("additive defaults are persisted without a schema bump", rewritten.get_value("meta", "schema", -1) == 1
		and rewritten.get_value("display", "window_resolution", "") == "auto"
		and rewritten.get_value("graphics", "max_fps", -1) == 0
		and rewritten.get_value("graphics", "vsync_mode", "") == "enabled"
		and rewritten.get_value("graphics", "msaa_3d", -1) == 2)
	var rewritten_load := DisplayPreferences.load_from(PREFS)
	_check("legacy file migration round-trips existing and new values", rewritten_load.window_mode == "borderless"
		and rewritten_load.menu_volume == 0.2 and rewritten_load.master_volume == 0.8
		and rewritten_load.window_resolution == "auto" and rewritten_load.max_fps == 0
		and rewritten_load.vsync_mode == "enabled" and rewritten_load.msaa_3d == 2)

	for window_mode: String in DisplayPreferences.WINDOW_MODES:
		var candidate: Dictionary = DisplayPreferences.DEFAULTS.duplicate(true)
		candidate.window_mode = window_mode
		_check("window mode %s remains accepted" % window_mode, DisplayPreferences.validate(candidate).ok)
	for resolution: String in DisplayPreferences.WINDOW_RESOLUTIONS:
		var candidate: Dictionary = DisplayPreferences.DEFAULTS.duplicate(true)
		candidate.window_resolution = resolution
		_check("resolution %s is accepted" % resolution, DisplayPreferences.validate(candidate).ok)
	for max_fps: int in DisplayPreferences.MAX_FPS_VALUES:
		var candidate: Dictionary = DisplayPreferences.DEFAULTS.duplicate(true)
		candidate.max_fps = max_fps
		_check("frame limit %d is accepted" % max_fps, DisplayPreferences.validate(candidate).ok)
	for vsync_mode: String in DisplayPreferences.VSYNC_MODES:
		var candidate: Dictionary = DisplayPreferences.DEFAULTS.duplicate(true)
		candidate.vsync_mode = vsync_mode
		_check("vsync mode %s is accepted" % vsync_mode, DisplayPreferences.validate(candidate).ok)
	for msaa_3d: int in DisplayPreferences.MSAA_3D_VALUES:
		var candidate: Dictionary = DisplayPreferences.DEFAULTS.duplicate(true)
		candidate.msaa_3d = msaa_3d
		_check("MSAA mode %d is accepted" % msaa_3d, DisplayPreferences.validate(candidate).ok)

	var invalid_window_mode: Dictionary = DisplayPreferences.DEFAULTS.duplicate(true)
	invalid_window_mode.window_mode = "fullscreen"
	_check("unsupported window mode remains rejected", not DisplayPreferences.validate(invalid_window_mode).ok)
	var advanced: Dictionary = DisplayPreferences.DEFAULTS.duplicate(true)
	advanced.window_mode = "borderless"
	advanced.window_resolution = "3440x1440"
	advanced.max_fps = 165
	advanced.vsync_mode = "disabled"
	advanced.msaa_3d = 3
	_check("selected advanced preferences validate", DisplayPreferences.validate(advanced).ok)
	_check("selected advanced preferences save", DisplayPreferences.save_to(PREFS, advanced) == OK)
	var stored := ConfigFile.new()
	_check("saved advanced preferences are readable", stored.load(PREFS) == OK)
	_check("advanced controls are stored under display and graphics", stored.get_value("display", "window_resolution", "") == "3440x1440"
		and stored.get_value("graphics", "max_fps", -1) == 165
		and stored.get_value("graphics", "vsync_mode", "") == "disabled"
		and stored.get_value("graphics", "msaa_3d", -1) == 3)
	var advanced_load := DisplayPreferences.load_from(PREFS)
	_check("advanced display settings round-trip", advanced_load.window_mode == "borderless"
		and advanced_load.window_resolution == "3440x1440" and advanced_load.max_fps == 165
		and advanced_load.vsync_mode == "disabled" and advanced_load.msaa_3d == 3)

	var invalid_resolution: Dictionary = DisplayPreferences.DEFAULTS.duplicate(true)
	invalid_resolution.window_resolution = "1024x768"
	_check("unsupported resolution is rejected", not DisplayPreferences.validate(invalid_resolution).ok)
	var invalid_max_fps: Dictionary = DisplayPreferences.DEFAULTS.duplicate(true)
	invalid_max_fps.max_fps = 75
	_check("unsupported frame limit is rejected", not DisplayPreferences.validate(invalid_max_fps).ok)
	invalid_max_fps.max_fps = 60.0
	_check("non-integer frame limit is rejected", not DisplayPreferences.validate(invalid_max_fps).ok)
	var invalid_vsync: Dictionary = DisplayPreferences.DEFAULTS.duplicate(true)
	invalid_vsync.vsync_mode = "adaptive"
	_check("unsupported vsync mode is rejected", not DisplayPreferences.validate(invalid_vsync).ok)
	var invalid_msaa: Dictionary = DisplayPreferences.DEFAULTS.duplicate(true)
	invalid_msaa.msaa_3d = 4
	_check("unsupported MSAA mode is rejected", not DisplayPreferences.validate(invalid_msaa).ok)
	invalid_msaa.msaa_3d = 2.0
	_check("non-integer MSAA mode is rejected", not DisplayPreferences.validate(invalid_msaa).ok)
	_check("invalid values cannot overwrite a valid file", DisplayPreferences.save_to(PREFS, invalid_resolution) == ERR_INVALID_DATA
		and DisplayPreferences.load_from(PREFS).window_resolution == "3440x1440")

	var malformed := ConfigFile.new()
	malformed.set_value("meta", "schema", 1)
	malformed.set_value("display", "window_resolution", "1024x768")
	_check("invalid preference fixture saves", malformed.save(PREFS) == OK)
	var recovered := DisplayPreferences.load_from(PREFS)
	_check("invalid persisted values use defaults and report recovery", recovered.window_resolution == "auto"
		and recovered.note.contains("invalid display values were replaced with defaults") and recovered.writable)

	var future := ConfigFile.new()
	future.set_value("meta", "schema", DisplayPreferences.SCHEMA + 1)
	future.set_value("display", "window_resolution", "1920x1080")
	future.set_value("graphics", "max_fps", 120)
	_check("future-schema fixture saves", future.save(PREFS) == OK)
	var future_load := DisplayPreferences.load_from(PREFS)
	_check("future-schema settings remain readable but protected", not future_load.writable
		and future_load.note.contains("newer version") and future_load.window_resolution == "1920x1080"
		and future_load.max_fps == 120)
	_check("future-schema file cannot be overwritten", DisplayPreferences.save_to(PREFS, DisplayPreferences.DEFAULTS) == ERR_FILE_NO_PERMISSION)
	var preserved := ConfigFile.new()
	_check("future-schema file remains readable after rejected save", preserved.load(PREFS) == OK
		and preserved.get_value("meta", "schema", -1) == DisplayPreferences.SCHEMA + 1)


func _reset() -> void:
	for path: String in [PREFS, PREFS + ".bad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(label: String, passed: bool) -> void:
	_checks += 1
	if passed:
		return
	_failures += 1
	push_error("display preferences: %s" % label)

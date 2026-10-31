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
	_check("legacy reconstruction defaults to native", migrated.reconstruction == "native")
	_check("legacy sharpening preserves engine default", migrated.fsr2_sharpness == 0.9)
	for strength: float in [0.0, 0.35, 0.9, 1.0]:
		var candidate := DisplayPreferences.DEFAULTS.duplicate(true)
		candidate.fsr2_sharpness = strength
		_check("sharpness round trip: %s" % strength, DisplayPreferences.save_to(PREFS, candidate) == OK
			and is_equal_approx(DisplayPreferences.load_from(PREFS).fsr2_sharpness, strength))
	for invalid: Variant in [-0.1, 1.1, NAN, INF, "0.5", true, null]:
		var candidate := DisplayPreferences.DEFAULTS.duplicate(true)
		candidate.fsr2_sharpness = invalid
		_check("malformed sharpness rejected", not DisplayPreferences.validate(candidate).ok)
	for mode: String in DisplayPreferences.RECONSTRUCTION_MODES:
		var candidate: Dictionary = DisplayPreferences.DEFAULTS.duplicate(true)
		candidate.reconstruction = mode
		_check("reconstruction round trip: " + mode, DisplayPreferences.save_to(PREFS, candidate) == OK
			and DisplayPreferences.load_from(PREFS).reconstruction == mode)
	for bad_mode: Variant in ["fsr3", "", 2, null]:
		var candidate: Dictionary = DisplayPreferences.DEFAULTS.duplicate(true)
		candidate.reconstruction = bad_mode
		_check("invalid reconstruction rejected: " + str(bad_mode), not DisplayPreferences.validate(candidate).ok)
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
	malformed.set_value("display", "window_mode", "borderless")
	malformed.set_value("display", "ui_scale", 1.5)
	malformed.set_value("accessibility", "opaque_panels", true)
	malformed.set_value("audio", "master_volume", 0.3)
	_check("invalid preference fixture saves", malformed.save(PREFS) == OK)
	var recovered := DisplayPreferences.load_from(PREFS)
	_check("invalid persisted values use defaults and report recovery", recovered.window_resolution == "auto"
		and recovered.note.contains("invalid display values were replaced with defaults") and recovered.writable)
	_check("invalid value does not reset valid display, accessibility or audio choices",
		recovered.window_mode == "borderless" and recovered.ui_scale == 1.5
		and recovered.opaque_panels and recovered.master_volume == 0.3)
	var recovered_store := DisplayPreferences.new(PREFS)
	var changed: Dictionary = recovered_store.config.duplicate(true)
	changed.menu_volume = 0.6
	_check("saving an unrelated choice after recovery succeeds", recovered_store.save(changed) == OK)
	var recovered_again := DisplayPreferences.load_from(PREFS)
	_check("valid choices survive recovery and a later save", recovered_again.window_mode == "borderless"
		and recovered_again.ui_scale == 1.5 and recovered_again.opaque_panels
		and recovered_again.master_volume == 0.3 and recovered_again.menu_volume == 0.6)
	_independent_recovery()

	var future := ConfigFile.new()
	future.set_value("meta", "schema", DisplayPreferences.SCHEMA + 1)
	future.set_value("display", "window_resolution", "1920x1080")
	future.set_value("graphics", "max_fps", 120)
	future.set_value("graphics", "reconstruction", "future-renderer")
	_check("future-schema fixture saves", future.save(PREFS) == OK)
	var future_load := DisplayPreferences.load_from(PREFS)
	_check("future-schema settings remain readable but protected", not future_load.writable
		and future_load.note.contains("newer version") and future_load.window_resolution == "1920x1080"
		and future_load.max_fps == 120 and future_load.reconstruction == "native"
		and future_load.note.contains("invalid display values were replaced with defaults"))
	_check("future-schema file cannot be overwritten", DisplayPreferences.save_to(PREFS, DisplayPreferences.DEFAULTS) == ERR_FILE_NO_PERMISSION)
	var preserved := ConfigFile.new()
	_check("future-schema file remains readable after rejected save", preserved.load(PREFS) == OK
		and preserved.get_value("meta", "schema", -1) == DisplayPreferences.SCHEMA + 1)
	_bad_file_preservation()
	_exhausted_backup_slots()
	_relative_backup_symlink()


func _bad_file_preservation() -> void:
	_reset()
	var broken := "this is not [a config file\n"
	var file := FileAccess.open(PREFS, FileAccess.WRITE)
	file.store_string(broken)
	file.close()
	var store := DisplayPreferences.new(PREFS)
	_check("preserved unreadable display settings remain writable", store.writable and FileAccess.get_file_as_string(PREFS + ".bad") == broken
		and store.save(store.config) == OK)
	var second_bad := "[display]\nwindow_mode=\"borderless\"\n"
	file = FileAccess.open(PREFS, FileAccess.WRITE)
	file.store_string(second_bad)
	file.close()
	store = DisplayPreferences.new(PREFS)
	_check("second unreadable display settings preserve the first backup and receive a distinct backup",
		store.writable and FileAccess.file_exists(PREFS + ".bad") and FileAccess.file_exists(PREFS + ".bad.1")
		and FileAccess.get_file_as_string(PREFS + ".bad") == broken
		and FileAccess.get_file_as_string(PREFS + ".bad.1") == second_bad and not FileAccess.file_exists(PREFS))
	_check("second display recovery allows a new file", store.save(store.config) == OK)
	var third_bad := "[display]\nwindow_mode=\"windowed\"\n"
	file = FileAccess.open(PREFS, FileAccess.WRITE)
	file.store_string(third_bad)
	file.close()
	store = DisplayPreferences.new(PREFS)
	_check("third unreadable display settings preserve both earlier backups",
		store.writable and FileAccess.file_exists(PREFS + ".bad") and FileAccess.file_exists(PREFS + ".bad.1")
		and FileAccess.file_exists(PREFS + ".bad.2")
		and FileAccess.get_file_as_string(PREFS + ".bad") == broken
		and FileAccess.get_file_as_string(PREFS + ".bad.1") == second_bad
		and FileAccess.get_file_as_string(PREFS + ".bad.2") == third_bad and not FileAccess.file_exists(PREFS))
	_reset()
	var backup := ProjectSettings.globalize_path(PREFS + ".bad")
	_check("create blocked display backup directory", DirAccess.make_dir_absolute(backup) == OK)
	file = FileAccess.open(backup.path_join("marker"), FileAccess.WRITE)
	file.store_string("occupied")
	file.close()
	file = FileAccess.open(PREFS, FileAccess.WRITE)
	file.store_string(broken)
	file.close()
	store = DisplayPreferences.new(PREFS)
	_check("failed display backup protects the original", not store.writable and "will not be overwritten" in store.note
		and FileAccess.get_file_as_string(PREFS) == broken)
	var candidate: Dictionary = store.config.duplicate(true)
	candidate.opaque_panels = true
	_check("failed display backup refuses later saves", store.save(candidate) == ERR_FILE_NO_PERMISSION
		and candidate.opaque_panels and FileAccess.get_file_as_string(PREFS) == broken)
	DirAccess.remove_absolute(backup.path_join("marker"))
	DirAccess.remove_absolute(backup)


func _exhausted_backup_slots() -> void:
	# A separate directory contains all 1000 slots, without touching player settings.
	var root := "user://test_display_preferences_exhausted"
	var path := root.path_join("settings.cfg")
	_check("create exhausted-backup fixture directory", DirAccess.make_dir_recursive_absolute(root) == OK)
	for index in range(1000):
		var backup := path + ".bad" + ("" if index == 0 else ".%d" % index)
		var f := FileAccess.open(backup, FileAccess.WRITE)
		f.store_string("retained-%d" % index)
		f.close()
	var broken := "[display]\nwindow_mode=\"windowed\"\n"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(broken)
	f.close()
	var store := DisplayPreferences.new(path)
	_check("exhausted backup slots protect both original and retained files",
		not store.writable and FileAccess.file_exists(path) and FileAccess.get_file_as_string(path) == broken
		and FileAccess.get_file_as_string(path + ".bad") == "retained-0"
		and FileAccess.get_file_as_string(path + ".bad.999") == "retained-999")
	_check("exhausted backup slots refuse later saves", store.save(store.config) == ERR_FILE_NO_PERMISSION)
	for index in range(1000):
		DirAccess.remove_absolute(path + ".bad" + ("" if index == 0 else ".%d" % index))
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(root)


func _relative_backup_symlink() -> void:
	var relative_root := "../tmp/test_display_preferences_relative_%d" % OS.get_process_id()
	var root := DirAccess.open(".").get_current_dir().path_join(relative_root).simplify_path()
	_check("create relative-path fixture directory", DirAccess.make_dir_recursive_absolute(root) == OK)
	var absolute := root.path_join("settings.cfg")
	var relative := relative_root.path_join("settings.cfg")
	var backup := absolute + ".bad"
	var parent := DirAccess.open(root)
	DirAccess.remove_absolute(backup)
	DirAccess.remove_absolute(absolute + ".bad.1")
	var broken := "[display]\nwindow_mode=\"windowed\"\n"
	var f := FileAccess.open(relative, FileAccess.WRITE)
	if f == null:
		_check("relative-path fixture can be written", false)
	else:
		f.store_string(broken)
		f.close()
		if parent.create_link(root.path_join("missing-target"), backup) == OK:
			var store := DisplayPreferences.new(relative)
			_check("relative backup skips a dangling symlink", store.writable and parent.is_link("settings.cfg.bad")
				and FileAccess.file_exists(absolute + ".bad.1")
				and FileAccess.get_file_as_string(absolute + ".bad.1") == broken)
		else:
			print("skip relative backup symlink: this host cannot create symbolic links")
	DirAccess.remove_absolute(backup)
	DirAccess.remove_absolute(absolute + ".bad.1")
	DirAccess.remove_absolute(absolute)
	DirAccess.remove_absolute(root)


func _independent_recovery() -> void:
	var chosen: Dictionary = DisplayPreferences.DEFAULTS.duplicate(true)
	chosen.merge({"window_mode": "borderless", "window_resolution": "1920x1080", "ui_scale": 1.5,
		"max_fps": 120, "vsync_mode": "disabled", "msaa_3d": 1, "reconstruction": "fsr2_quality",
		"fsr2_sharpness": 0.4, "scene_detail": "high", "birds": "few", "opaque_panels": true,
		"reduced_motion": true, "menu_volume": 0.2, "master_volume": 0.3,
		"aircraft_lighting_quality": "high", "camera_fov": 60}, true)
	var cases := [
		["display", "window_mode", "fullscreen"], ["display", "window_resolution", "1024x768"],
		["display", "ui_scale", 1.13], ["graphics", "max_fps", 75],
		["graphics", "vsync_mode", "adaptive"], ["graphics", "msaa_3d", 4],
		["graphics", "reconstruction", "unknown"], ["graphics", "fsr2_sharpness", 2.0],
		["graphics", "scene_detail", "unknown"], ["graphics", "birds", "unknown"],
		["accessibility", "opaque_panels", "yes"], ["accessibility", "reduced_motion", "yes"],
		["audio", "menu_volume", -0.1], ["audio", "master_volume", 1.1],
	]
	for item: Array in cases:
		var section: String = item[0]
		var key: String = item[1]
		_check("write baseline for invalid " + key, DisplayPreferences.save_to(PREFS, chosen) == OK)
		var cfg := ConfigFile.new()
		var loaded_ok: bool = cfg.load(PREFS) == OK
		cfg.set_value(section, key, item[2])
		_check("write invalid " + key, loaded_ok and cfg.save(PREFS) == OK)
		var expected: Dictionary = chosen.duplicate(true)
		expected[key] = DisplayPreferences.DEFAULTS[key]
		var store := DisplayPreferences.new(PREFS)
		_check("only invalid " + key + " falls back", store.config == expected and store.writable
			and store.note.contains("invalid display values were replaced with defaults"))
		_check("recovered " + key + " persists with other choices", store.save(store.config) == OK
			and DisplayPreferences.new(PREFS).config == expected)
	_check("write baseline for multiple invalid values", DisplayPreferences.save_to(PREFS, chosen) == OK)
	var multiple := ConfigFile.new()
	var multiple_loaded: bool = multiple.load(PREFS) == OK
	multiple.set_value("display", "window_resolution", "1024x768")
	multiple.set_value("audio", "master_volume", 1.1)
	_check("write multiple invalid values", multiple_loaded and multiple.save(PREFS) == OK)
	var multiple_expected: Dictionary = chosen.duplicate(true)
	multiple_expected.window_resolution = DisplayPreferences.DEFAULTS.window_resolution
	multiple_expected.master_volume = DisplayPreferences.DEFAULTS.master_volume
	var multiple_store := DisplayPreferences.new(PREFS)
	_check("multiple invalid values recover without resetting other choices", multiple_store.config == multiple_expected)
	_check("multiple recovered values persist with other choices", multiple_store.save(multiple_store.config) == OK
		and DisplayPreferences.new(PREFS).config == multiple_expected)


func _reset() -> void:
	for path: String in [PREFS, PREFS + ".bad", PREFS + ".bad.1", PREFS + ".bad.2"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(label: String, passed: bool) -> void:
	_checks += 1
	if passed:
		return
	_failures += 1
	push_error("display preferences: %s" % label)

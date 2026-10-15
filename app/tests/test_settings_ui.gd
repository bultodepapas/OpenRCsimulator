# UI-24: display preferences validation, independent persistence and Settings preview recovery.
# Run: godot --headless --path . --script res://tests/test_settings_ui.gd
extends SceneTree

const DisplayPreferences := preload("res://app_state/display_preferences.gd")
const SettingsScreen := preload("res://ui/settings_screen.gd")
const ScreenTheme := preload("res://ui/ui_theme.gd")
const PREFS := "user://test_settings_ui_display.cfg"

var _failures := 0
var _presentations: Array[Dictionary] = []
var _languages: Array[String] = []
var _routes: Array[String] = []


func _initialize() -> void:
	_run()
	print("all Settings checks passed" if _failures == 0 else "%d Settings checks failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _run() -> void:
	_clean()
	var store := DisplayPreferences.new(PREFS)
	_check("fresh display settings use validated defaults", store.config == DisplayPreferences.DEFAULTS and store.writable)

	var candidate := DisplayPreferences.DEFAULTS.duplicate(true)
	candidate.window_mode = "borderless"
	candidate.ui_scale = 1.75
	candidate.opaque_panels = true
	_check("valid range and window mode accepted", DisplayPreferences.validate(candidate).ok)
	var malformed := candidate.duplicate(true)
	malformed.ui_scale = 0.99
	_check("scale below 100% rejected", not DisplayPreferences.validate(malformed).ok)
	malformed = candidate.duplicate(true)
	malformed.ui_scale = 2.05
	_check("scale outside the 5% steps rejected", not DisplayPreferences.validate(malformed).ok)
	malformed = candidate.duplicate(true)
	malformed.window_mode = "exclusive"
	_check("unknown window mode rejected", not DisplayPreferences.validate(malformed).ok)
	malformed = candidate.duplicate(true)
	malformed.reduced_motion = "yes"
	_check("wrong accessibility value type rejected", not DisplayPreferences.validate(malformed).ok)
	_check("invalid settings cannot be saved", DisplayPreferences.save_to(PREFS, malformed) == ERR_INVALID_DATA
		and not FileAccess.file_exists(PREFS))

	_check("valid settings save", store.save(candidate) == OK)
	var reloaded := DisplayPreferences.load_from(PREFS)
	_check("display preferences round-trip", reloaded.window_mode == "borderless"
		and is_equal_approx(reloaded.ui_scale, 1.75) and reloaded.opaque_panels and not reloaded.reduced_motion)
	var relaunched_store := DisplayPreferences.new(PREFS)
	_check("new store instance reloads saved values", relaunched_store.config.window_mode == "borderless"
		and is_equal_approx(relaunched_store.config.ui_scale, 1.75))
	var newer_contents := "[meta]\nschema=99\n[display]\nwindow_mode=\"windowed\"\n"
	_write(newer_contents)
	var newer := DisplayPreferences.load_from(PREFS)
	_check("newer settings file is read-only", not newer.writable and newer.window_mode == "windowed")
	_check("newer settings are never overwritten", DisplayPreferences.save_to(PREFS, candidate) == ERR_FILE_NO_PERMISSION
		and FileAccess.get_file_as_string(PREFS) == newer_contents)
	_clean()
	_write("not a valid ConfigFile")
	var broken := DisplayPreferences.load_from(PREFS)
	_check("unreadable settings are preserved for recovery", broken.window_mode == "windowed"
		and FileAccess.file_exists(PREFS + ".bad") and not FileAccess.file_exists(PREFS))
	_clean()
	store = DisplayPreferences.new(PREFS)

	ScreenTheme.text_scale = 1.5
	var settings := SettingsScreen.new(store, "en")
	settings.presentation_changed.connect(_capture_presentation)
	settings.language_changed.connect(_capture_language)
	settings.route_requested.connect(_capture_route)
	_check("Close receives initial keyboard focus", settings._close_button.focus_mode == Control.FOCUS_ALL)
	var all_rows_stack := true
	for row: BoxContainer in settings._rows:
		all_rows_stack = all_rows_stack and row.vertical
	_check("larger text stacks settings rows", all_rows_stack and not settings._rows.is_empty())
	root.add_child(settings)
	settings._window_mode_selected(1)
	_check("window change starts a 15-second trial", settings._trial_deadline_msec - Time.get_ticks_msec() > 14500
		and settings._trial_deadline_msec - Time.get_ticks_msec() <= 15000)
	settings._trial_deadline_msec = Time.get_ticks_msec() - 1
	settings._process(0.0)
	_check("expired preview emits the saved display configuration", not _presentations.is_empty()
		and _presentations.back() == store.config)
	_check("expired preview does not persist the tested window mode", DisplayPreferences.load_from(PREFS).window_mode == "windowed")

	settings._language_selected(1)
	_check("language applies immediately through the host signal", _languages == ["es"])
	settings._notification(NOTIFICATION_TRANSLATION_CHANGED)
	_check("locale refresh rebuilds status and window picker labels", settings._window_picker.get_item_text(0) == tr("Windowed")
		and settings._status.text != "")
	var controls: Button = settings.find_child("Controls", true, false) as Button
	var about: Button = settings.find_child("HelpAbout", true, false) as Button
	controls.pressed.emit()
	about.pressed.emit()
	_check("Controls and Help/About expose host routes", _routes == ["controls", "about"])

	settings._scale_selected(4)
	settings.keep_changes()
	_check("Keep persists accessibility and scale changes", is_equal_approx(DisplayPreferences.load_from(PREFS).ui_scale, 2.0))
	settings._opaque_toggled(true)
	settings._window_mode_selected(1)
	settings.close()
	_check("Back/close restores the last kept display configuration", _presentations.back() == store.config
		and DisplayPreferences.load_from(PREFS).window_mode == "windowed"
		and not DisplayPreferences.load_from(PREFS).opaque_panels)
	settings.queue_free()
	ScreenTheme.text_scale = 1.0
	_clean()


func _write(contents: String) -> void:
	var file := FileAccess.open(PREFS, FileAccess.WRITE)
	file.store_string(contents)
	file.close()


func _clean() -> void:
	for candidate in [PREFS, PREFS + ".bad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))


func _capture_presentation(config: Dictionary) -> void:
	_presentations.append(config.duplicate(true))


func _capture_language(language: String) -> void:
	_languages.append(language)


func _capture_route(route: String, _from: Control) -> void:
	_routes.append(route)


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])

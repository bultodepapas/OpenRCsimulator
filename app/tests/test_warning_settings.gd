extends SceneTree

const Settings := preload("res://render/overlays/overlay_settings.gd")
const Preferences := preload("res://app_state/preferences.gd")
const Manager := preload("res://render/overlays/overlay_manager.gd")
const Dialog := preload("res://ui/overlays_dialog.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const UiDriver := preload("res://tests/ui_driver.gd")
const PREFS := "user://test_warning_settings.cfg"

var checks := 0
var failures := 0
var _prefs_path := "user://test_warning_settings_%d.cfg" % OS.get_process_id()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_validation()
	_validation_cases()
	_preferences()
	_preferences_cases()
	await _dialog()
	await _dialog_cases()
	_reset()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_prefs_path))
	print("warning settings: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _validation() -> void:
	_check("legacy settings retain their exact shape", Settings.validate({}) == Settings.DEFAULTS)
	_check("warning defaults and limits are explicit", Settings.WARNING_DEFAULTS == {
		"warning_detail": true, "warning_limit": 3, "warning_navigation": true,
		"warning_energy": true, "warning_status": true, "warning_training": false,
		"warning_motion": "playful", "warning_sound": true, "warning_volume": 0.55, "warning_clear_sound": true,
	} and Settings.WARNING_LIMITS == [1, 3, 5])
	var choices := {"warning_detail": false, "warning_limit": 5, "warning_navigation": false,
		"warning_energy": false, "warning_status": false, "warning_training": true}
	for preset: String in ["pilot", "custom"]:
		var input := choices.duplicate()
		input.preset = preset
		input.visible = ["warnings"]
		var validated: Dictionary = Settings.validate(input)
		_check("all alert options validate with " + preset, choices.keys().all(
			func(key: String) -> bool: return validated.get(key) == choices[key]))
	var invalid := Settings.validate({"warning_detail": 1, "warning_limit": 3.0, "warning_navigation": "true",
		"warning_energy": 0, "warning_status": null, "warning_training": "false"})
	_check("wrong types are omitted", Settings.WARNING_DEFAULTS.keys().all(func(key: String) -> bool: return not invalid.has(key)))
	for invalid_limit in [-1, 0, 2, 4, 6, "3"]:
		_check("unsupported alert limit is omitted: " + str(invalid_limit), not Settings.validate({"warning_limit": invalid_limit}).has("warning_limit"))
	for limit: int in Settings.WARNING_LIMITS:
		_check("valid alert limit survives: " + str(limit), Settings.validate({"warning_limit": limit}).warning_limit == limit)


func _preferences() -> void:
	_reset()
	var prefs: Dictionary = Preferences.load_from(PREFS)
	_check("legacy HUD saves", Preferences.save_to(PREFS, prefs) == OK)
	var cfg := ConfigFile.new()
	_check("legacy preference fixture loads", cfg.load(PREFS) == OK)
	_check("legacy save does not add alert keys", Settings.WARNING_DEFAULTS.keys().all(
		func(key: String) -> bool: return not cfg.has_section_key("hud", key)))
	prefs.hud.merge({"warning_detail": false, "warning_limit": 1, "warning_navigation": false,
		"warning_energy": false, "warning_status": false, "warning_training": true})
	_check("alert choices save", Preferences.save_to(PREFS, prefs) == OK)
	_check("alert choices round-trip", Preferences.load_from(PREFS).hud == prefs.hud)
	cfg = ConfigFile.new()
	_check("saved alert fixture loads", cfg.load(PREFS) == OK)
	cfg.set_value("hud", "warning_limit", 2)
	cfg.set_value("hud", "warning_status", "true")
	_check("invalid alert fixture saves", cfg.save(PREFS) == OK)
	var recovered: Dictionary = Preferences.load_from(PREFS).hud
	_check("invalid saved fields are omitted without losing valid choices", not recovered.has("warning_limit")
		and not recovered.has("warning_status") and recovered.warning_training and not recovered.warning_detail)


func _dialog() -> void:
	var original_scale := UiTheme.text_scale
	var original_size := root.size
	TranslationServer.set_locale("en")
	UiTheme.text_scale = 1.0
	await process_frame
	root.size = Vector2i(1920, 1080)
	var manager: CanvasLayer = Manager.new({}, "en")
	root.add_child(manager)
	var changes: Array = []
	manager.settings_changed.connect(func(value: Dictionary) -> void: changes.append(value))
	var dialog: CanvasLayer = Dialog.new(manager)
	root.add_child(dialog)
	for i in 4: await process_frame
	_check("opening dialog never saves defaults", changes.is_empty() and manager.settings == Settings.DEFAULTS)
	_check("Alerts is appended without changing existing tab positions", dialog.tab_bar.tab_count == 6
		and dialog._pages[4].name == "OtherOverlaysPage" and dialog._pages[5].name == "AlertsPage")
	dialog.tab_bar.current_tab = 5
	for i in 4: await process_frame
	_check("single Warnings switch belongs to Alerts", dialog.switches.warnings.get_parent() == dialog._pages[5]
		and dialog.switches.warnings.is_visible_in_tree())
	_check("default alert controls match effective defaults", dialog.warning_limit_picker.selected == 1
		and dialog.warning_switches.warning_detail.button_pressed
		and dialog.warning_switches.warning_navigation.button_pressed
		and dialog.warning_switches.warning_energy.button_pressed
		and dialog.warning_switches.warning_status.button_pressed
		and not dialog.warning_switches.warning_training.button_pressed)
	var viewport := Rect2(Vector2.ZERO, Vector2(root.size))
	_check("1080p alert dialog and controls fit", viewport.encloses(dialog.dialog_panel.get_global_rect())
		and viewport.encloses(dialog.tab_bar.get_global_rect()) and viewport.encloses(dialog.done_button.get_global_rect()))
	manager.set_warning_option("warning_detail", true)
	manager.set_warning_option("warning_limit", 3)
	_check("effective default choices are no-ops", changes.is_empty() and manager.settings == Settings.DEFAULTS)
	dialog.warning_switches.warning_training.button_pressed = true
	dialog.warning_switches.warning_navigation.button_pressed = false
	dialog.warning_limit_picker.item_selected.emit(2)
	_check("alert controls update the manager", manager.settings.warning_training and not manager.settings.warning_navigation
		and manager.settings.warning_limit == 5 and dialog.warning_limit_picker.selected == 2)
	var saved: Dictionary = manager.settings.duplicate(true)
	var change_count: int = changes.size()
	manager.set_warning_option("warning_limit", 5)
	manager.set_warning_option("warning_limit", 2)
	manager.set_warning_option("warning_training", "true")
	manager.set_warning_option("unknown", true)
	_check("no-op and rejected edits keep settings and do not save", manager.settings == saved and changes.size() == change_count)
	dialog.switches.warnings.button_pressed = false
	_check("Warnings switch still hides the overlay", not manager.is_overlay_visible("warnings"))
	dialog.switches.warnings.button_pressed = true
	_check("Warnings switch restores the overlay", manager.is_overlay_visible("warnings"))
	var focused: Control = dialog.warning_switches.warning_training
	focused.grab_focus()
	await process_frame
	dialog.tab_bar.current_tab = 0
	await process_frame
	_check("hidden alert page leaves keyboard focus on tabs", focused.focus_mode == Control.FOCUS_NONE
		and root.gui_get_focus_owner() == dialog.tab_bar)
	dialog.queue_free()
	manager.queue_free()
	await process_frame

	TranslationServer.set_locale("es")
	UiTheme.text_scale = 2.0
	manager = Manager.new({}, "es")
	root.add_child(manager)
	dialog = Dialog.new(manager)
	root.add_child(dialog)
	dialog.tab_bar.current_tab = 5
	for i in 6: await process_frame
	var scroll: ScrollContainer = dialog.get("_scroll")
	_check("Spanish 200% keeps 1080p dialog and scroll reachable", viewport.encloses(dialog.dialog_panel.get_global_rect())
		and viewport.encloses(dialog.tab_bar.get_global_rect()) and viewport.encloses(dialog.done_button.get_global_rect())
		and scroll.size.y >= 60.0 and scroll.get_child(0).size.x <= scroll.size.x + 1.0)
	dialog.warning_switches.warning_training.grab_focus()
	for i in 3: await process_frame
	_check("Spanish 200% can focus the last alert option", root.gui_get_focus_owner() == dialog.warning_switches.warning_training)
	dialog.queue_free()
	manager.queue_free()
	await process_frame
	TranslationServer.set_locale("en")
	UiTheme.text_scale = original_scale
	root.size = original_size


func _reset() -> void:
	for path: String in [PREFS, PREFS + ".bad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		push_error("warning settings: " + label)


func _validation_cases() -> void:
	var legacy := Settings.validate({})
	_check("legacy settings keep their existing shape", legacy == Settings.DEFAULTS)
	for key: String in ["warning_motion", "warning_sound", "warning_volume", "warning_clear_sound"]:
		_check("legacy option stays implicit: " + key, not legacy.has(key))
	_check("feedback defaults are explicit at the consumer boundary",
		Settings.WARNING_DEFAULTS.warning_motion == "playful" and Settings.WARNING_DEFAULTS.warning_sound
		and Settings.WARNING_DEFAULTS.warning_volume == 0.55 and Settings.WARNING_DEFAULTS.warning_clear_sound)
	for motion: String in Settings.WARNING_MOTIONS:
		_check("valid motion " + motion, Settings.valid_warning_option("warning_motion", motion))
	for invalid: Variant in [null, "", "PLAYFUL", "animated", 1, true]:
		_check("invalid motion is rejected", not Settings.valid_warning_option("warning_motion", invalid))
	for value: Variant in [0, 0.0, 0.55, 1.0, 1]:
		_check("valid volume is accepted", Settings.valid_warning_option("warning_volume", value))
	for invalid: Variant in [null, true, "0.5", NAN, INF, -INF, -0.01, 1.01]:
		_check("invalid volume is rejected", not Settings.valid_warning_option("warning_volume", invalid))
	_check("existing alert booleans and integer limits remain validated",
		Settings.valid_warning_option("warning_detail", false)
		and Settings.valid_warning_option("warning_sound", true)
		and not Settings.valid_warning_option("warning_clear_sound", 1)
		and Settings.valid_warning_option("warning_limit", 3)
		and not Settings.valid_warning_option("warning_limit", 3.0)
		and not Settings.valid_warning_option("unknown", true))
	var checked := Settings.validate({preset = "pilot", warning_motion = "bad", warning_volume = INF,
		warning_sound = false, warning_clear_sound = "yes", warning_limit = 5})
	_check("invalid loaded options fall back independently", not checked.has("warning_motion")
		and not checked.has("warning_volume") and not checked.has("warning_clear_sound")
		and checked.warning_sound == false and checked.warning_limit == 5)


func _preferences_cases() -> void:
	var prefs := Preferences.load_from(_prefs_path)
	_check("missing preferences retain the legacy HUD shape", prefs.hud == Settings.DEFAULTS)
	prefs.hud = Settings.validate({preset = "pilot", warning_motion = "subtle", warning_sound = false,
		warning_volume = 0.37, warning_clear_sound = false, warning_navigation = false})
	_check("feedback preferences save", Preferences.save_to(_prefs_path, prefs) == OK)
	var loaded := Preferences.load_from(_prefs_path)
	_check("feedback preferences round trip", loaded.hud == prefs.hud)
	var file := ConfigFile.new()
	_check("saved settings can be read for corruption case", file.load(_prefs_path) == OK)
	file.set_value("hud", "warning_motion", "unknown")
	file.set_value("hud", "warning_volume", 1.5)
	file.set_value("hud", "warning_sound", "false")
	_check("corrupt fixture saves", file.save(_prefs_path) == OK)
	loaded = Preferences.load_from(_prefs_path)
	_check("invalid saved feedback falls back without harming valid options",
		not loaded.hud.has("warning_motion") and not loaded.hud.has("warning_volume")
		and not loaded.hud.has("warning_sound") and loaded.hud.warning_clear_sound == false
		and loaded.hud.warning_navigation == false)


func _dialog_cases() -> void:
	var previous_scale := UiTheme.text_scale
	var previous_size := root.size
	UiTheme.text_scale = 2.0
	root.size = Vector2i(1920, 1080)
	await process_frame
	var manager := Manager.new({}, "en")
	root.add_child(manager)
	var dialog := Dialog.new(manager)
	root.add_child(dialog)
	var ui := UiDriver.new(self)
	await ui.settle()
	dialog.tab_bar.current_tab = 5
	await ui.settle()
	_check("Alerts tab remains at index five", dialog._pages[5].name == "AlertsPage"
		and dialog._pages[5].visible)
	_check("feedback controls show defaults", dialog.warning_motion_picker.selected == 0
		and dialog.warning_switches.warning_sound.button_pressed
		and dialog.warning_switches.warning_clear_sound.button_pressed
		and is_equal_approx(dialog.warning_volume_slider.value, 0.55)
		and dialog.warning_volume_value.text == "55%")
	_check("volume slider has an accessible name and a bounded range",
		dialog.warning_volume_slider.accessibility_name == "Alert volume"
		and dialog.warning_volume_slider.min_value == 0.0 and dialog.warning_volume_slider.max_value == 1.0)
	dialog.warning_motion_picker.item_selected.emit(1)
	dialog.warning_switches.warning_sound.button_pressed = false
	dialog.warning_volume_slider.value = 0.28
	dialog.warning_switches.warning_clear_sound.button_pressed = false
	_check("feedback controls apply immediately", manager.settings.warning_motion == "subtle"
		and manager.settings.warning_sound == false and is_equal_approx(manager.settings.warning_volume, 0.28)
		and manager.settings.warning_clear_sound == false and dialog.warning_volume_value.text == "28%")
	var before: Dictionary = manager.settings.duplicate(true)
	var changes: Array = []
	manager.settings_changed.connect(func(value: Dictionary) -> void: changes.append(value))
	manager.set_warning_option("warning_motion", "invalid")
	manager.set_warning_option("warning_volume", NAN)
	manager.set_warning_option("warning_volume", 1.01)
	manager.set_warning_option("warning_sound", 1)
	manager.set_warning_option("warning_clear_sound", "false")
	_check("invalid direct edits preserve accepted settings without emitting", manager.settings == before and changes.is_empty())
	manager.set_warning_option("warning_motion", "off")
	manager.set_warning_option("warning_volume", 0.64)
	_check("external changes synchronize controls", dialog.warning_motion_picker.selected == 2
		and is_equal_approx(dialog.warning_volume_slider.value, 0.64) and dialog.warning_volume_value.text == "64%")
	_check("sound-off disables explicit audition", dialog.warning_test_button.disabled)
	manager.set_warning_option("warning_sound", true)
	var previews: Array[String] = []
	manager.alert_audio.preview_requested.connect(func(cue: String) -> void: previews.append(cue))
	before = manager.settings.duplicate(true)
	changes.clear()
	dialog.warning_test_button.pressed.emit()
	_check("Test sound auditions a caution without saving or creating a flight event", previews == ["caution"]
		and manager.settings == before and changes.is_empty())
	manager.set_warning_option("warning_volume", 0.0)
	_check("zero volume disables Test sound and retires playback", dialog.warning_test_button.disabled
		and not manager.alert_audio.audio_player().playing)
	manager.set_warning_option("warning_volume", 0.64)
	var scroll: ScrollContainer = dialog.get("_scroll")
	dialog.warning_motion_picker.grab_focus()
	await ui.settle()
	_check("motion selector receives focus at 200 percent text", root.gui_get_focus_owner() == dialog.warning_motion_picker)
	for control: Control in [dialog.warning_switches.warning_sound, dialog.warning_volume_slider,
			dialog.warning_test_button, dialog.warning_switches.warning_clear_sound]:
		await ui.tap(KEY_TAB)
		_check("Tab reaches " + control.name, root.gui_get_focus_owner() == control)
		_check("focused control is revealed in the scroll area: " + control.name,
			scroll.follow_focus and scroll.get_global_rect().has_point(control.get_global_rect().get_center()))
	dialog.queue_free()
	manager.queue_free()
	await ui.settle()
	await create_timer(0.25).timeout # release the explicit preview's Ogg playback on the audio mix thread
	UiTheme.text_scale = previous_scale
	root.size = previous_size


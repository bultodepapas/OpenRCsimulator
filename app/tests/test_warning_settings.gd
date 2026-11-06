extends SceneTree

const Settings := preload("res://render/overlays/overlay_settings.gd")
const Preferences := preload("res://app_state/preferences.gd")
const Manager := preload("res://render/overlays/overlay_manager.gd")
const Dialog := preload("res://ui/overlays_dialog.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const PREFS := "user://test_warning_settings.cfg"

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_validation()
	_preferences()
	await _dialog()
	_reset()
	print("warning settings: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _validation() -> void:
	_check("legacy settings retain their exact shape", Settings.validate({}) == Settings.DEFAULTS)
	_check("warning defaults and limits are explicit", Settings.WARNING_DEFAULTS == {
		"warning_detail": true, "warning_limit": 3, "warning_navigation": true,
		"warning_energy": true, "warning_status": true, "warning_training": false,
	} and Settings.WARNING_LIMITS == [1, 3, 5])
	var choices := {"warning_detail": false, "warning_limit": 5, "warning_navigation": false,
		"warning_energy": false, "warning_status": false, "warning_training": true}
	for preset: String in ["pilot", "custom"]:
		var input := choices.duplicate()
		input.preset = preset
		input.visible = ["warnings"]
		var validated: Dictionary = Settings.validate(input)
		_check("all alert options validate with " + preset, Settings.WARNING_DEFAULTS.keys().all(
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

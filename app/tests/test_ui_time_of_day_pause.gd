# TOD-08b: pause-only lighting edits, flight isolation, persistence and direct-route preference safety.
# Run: godot --headless --path . --audio-driver Dummy --script res://tests/test_ui_time_of_day_pause.gd
extends SceneTree

const Preferences := preload("res://app_state/preferences.gd")
const TimeOfDay := preload("res://environment/time_of_day_config.gd")
const UiDriver := preload("res://tests/ui_driver.gd")

const PREFS: String = "user://test_ui_time_of_day_pause.cfg"
const DIRECT_PREFS: String = "user://test_ui_time_of_day_pause_direct.cfg"
const SENTINEL: String = "leave direct-route preferences untouched\n"

var _failures: int = 0
var ui: RefCounted


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	ui = UiDriver.new(self)
	await _run()


func _run() -> void:
	TranslationServer.set_locale("en")
	_remove_prefs(PREFS)
	_remove_prefs(DIRECT_PREFS)
	await _interactive_pause_edit()
	await _direct_route_never_touches_preferences()
	_remove_prefs(PREFS)
	_remove_prefs(DIRECT_PREFS)
	print("all TOD-08b pause UI checks passed" if _failures == 0 else "%d TOD-08b pause UI checks failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _interactive_pause_edit() -> void:
	# This suite exercises the legacy/TOD paused editor, distinct from the flowing field-world Home preset.
	var fixture := Preferences.DEFAULTS.duplicate(true)
	fixture.time_of_day = "day"
	_check("write the explicit fixed-day editor fixture", Preferences.save_to(PREFS, fixture) == OK)
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	await ui.settle()
	_check("interactive route starts on Home", app.home != null and app.has_home)
	await ui.tap(KEY_ENTER)
	await create_timer(0.25).timeout
	var flight: Node = app.flight
	var session: Node = flight.session
	app.open_pause()
	await ui.settle()
	var initial_state: PackedFloat64Array = session.sim.state.duplicate()
	var initial_commands: Dictionary = session.commands.duplicate(true)
	var initial_tick: int = session.sim.tick
	_check("pause menu offers a dedicated Time of day action", app.pause_menu.time_of_day_button.name == "TimeOfDay"
		and app.pause_menu.time_of_day_button.text == "Time of day")
	await ui.tap(KEY_DOWN)
	_check("Down reaches Restart", ui.focus_name() == "Restart", ui.focus_name())
	await ui.tap(KEY_DOWN)
	_check("next Down reaches Time of day", ui.focus_name() == "TimeOfDay", ui.focus_name())
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("time editor opens over the still-paused flight", app.time_of_day_dialog != null
		and app.pause_menu != null and session.sim.paused and ui.focus_name() == "LightingMode", ui.focus_name())

	var dialog: CanvasLayer = app.time_of_day_dialog
	var controls: VBoxContainer = dialog.get("controls") as VBoxContainer
	var mode_picker: OptionButton = controls.find_child("LightingMode", true, false) as OptionButton
	var mode_popup: PopupMenu = mode_picker.get_popup()
	var initial_preset_picker: OptionButton = controls.find_child("TimePreset", true, false) as OptionButton
	_check("option popups use native windows only when supported",
		mode_popup.force_native == DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS)
		and initial_preset_picker.get_popup().force_native == DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS))
	var time_input: LineEdit = controls.find_child("ExactTime", true, false) as LineEdit
	var advanced_toggle: CheckButton = controls.find_child("AdvancedLocation", true, false) as CheckButton
	var apply_button: Button = dialog.get("apply_button") as Button
	var error_label: Label = dialog.get("error_label") as Label
	var focus_before_radio: String = ui.focus_name()
	await ui.joy_axis(JOY_AXIS_LEFT_X, 1.0)
	_check("radio axes cannot move focus in the pause editor", ui.focus_name() == focus_before_radio,
		"before=%s after=%s" % [focus_before_radio, ui.focus_name()])
	await _assert_modal_bounds(dialog, "en", Vector2i(800, 600))
	await _assert_modal_bounds(dialog, "es", Vector2i(800, 600))
	await _assert_modal_bounds(dialog, "en", Vector2i(1280, 720))
	await _assert_modal_bounds(dialog, "es", Vector2i(1280, 720))
	_check("Spanish modal title and actions are translated", (dialog.get("title_label") as Label).text == "Hora del día"
		and apply_button.text == "Aplicar" and (dialog.get("cancel_button") as Button).text == "Cancelar")
	TranslationServer.set_locale("en")
	root.size = Vector2i(800, 600)
	await ui.settle()
	mode_picker.select(1)
	mode_picker.item_selected.emit(1)
	advanced_toggle.grab_focus()
	await ui.tap(KEY_SPACE)
	var location_input: LineEdit = controls.find_child("LocationName", true, false) as LineEdit
	location_input.grab_focus()
	await ui.settle()
	var editor_scroll: ScrollContainer = dialog.find_child("TimeOfDayScroll", true, false) as ScrollContainer
	_check("keyboard focus scrolls the advanced location field into view at 800×600",
		editor_scroll.get_global_rect().encloses(location_input.get_global_rect()) and editor_scroll.scroll_vertical > 0,
		"scroll=%d field=%s" % [editor_scroll.scroll_vertical, str(location_input.get_global_rect())])
	root.size = Vector2i(1280, 720)
	await ui.settle()

	var night_draft: Dictionary = _select_night(controls)
	await ui.tap(KEY_ESCAPE)
	await ui.settle()
	_check("Esc cancels without resuming or changing lighting", app.time_of_day_dialog == null
		and app.pause_menu != null and session.sim.paused and session.sim.tick == initial_tick
		and session.sim.state == initial_state and flight.lighting_config == TimeOfDay.defaults()
		and _timeline_event_count(flight) == 0 and night_draft.mode == "astronomical")
	_check("Cancel restores focus to the pause action", ui.focus_name() == "TimeOfDay", ui.focus_name())

	await ui.tap(KEY_ENTER)
	await ui.settle()
	dialog = app.time_of_day_dialog
	controls = dialog.get("controls") as VBoxContainer
	mode_picker = controls.find_child("LightingMode", true, false) as OptionButton
	time_input = controls.find_child("ExactTime", true, false) as LineEdit
	apply_button = dialog.get("apply_button") as Button
	error_label = dialog.get("error_label") as Label
	mode_picker.select(1)
	mode_picker.item_selected.emit(1)
	time_input.text = "25:00"
	apply_button.grab_focus()
	await ui.tap(KEY_ENTER)
	_check("invalid local time leaves the editor open with an error", app.time_of_day_dialog != null
		and error_label.visible and session.sim.paused and session.sim.state == initial_state)
	app.call("_on_time_of_day_applied", {"invalid": true})
	_check("flight staging errors also keep the modal open", app.time_of_day_dialog != null and error_label.visible
		and session.sim.paused and flight.lighting_config == TimeOfDay.defaults()
		and session.sim.state == initial_state and session.commands == initial_commands)
	await ui.tap(KEY_ESCAPE)
	_check("Esc after an error still only cancels the draft", app.time_of_day_dialog == null
		and app.pause_menu != null and session.sim.paused and session.sim.tick == initial_tick)

	await ui.tap(KEY_ENTER)
	await ui.settle()
	dialog = app.time_of_day_dialog
	controls = dialog.get("controls") as VBoxContainer
	var preset_picker: OptionButton = controls.find_child("TimePreset", true, false) as OptionButton
	var preset_popup: PopupMenu = preset_picker.get_popup()
	_check("preset popup route starts on the lighting control", ui.focus_name() == "LightingMode", ui.focus_name())
	await ui.tap(KEY_TAB)
	_check("Tab reaches the time preset", ui.focus_name() == "TimePreset", ui.focus_name())
	await ui.tap(KEY_ENTER)
	_check("Enter opens the time preset list", preset_popup.visible)
	await ui.tap(KEY_ESCAPE)
	_check("Esc closes the preset list and keeps the editor paused", not preset_popup.visible
		and app.time_of_day_dialog == dialog and session.sim.paused)
	await ui.tap(KEY_ESCAPE)
	await ui.settle()
	_check("a second Esc cancels the editor but keeps Pause open", app.time_of_day_dialog == null
		and app.pause_menu != null and session.sim.paused)
	await ui.tap(KEY_ENTER)
	await ui.settle()
	dialog = app.time_of_day_dialog
	controls = dialog.get("controls") as VBoxContainer
	preset_picker = controls.find_child("TimePreset", true, false) as OptionButton
	preset_popup = preset_picker.get_popup()
	await ui.tap(KEY_TAB)
	await ui.tap(KEY_ENTER)
	for down_index: int in 5:
		await ui.tap(KEY_DOWN)
	_check("Down keys navigate the open preset list", preset_popup.visible)
	await ui.tap(KEY_ENTER)
	await ui.settle()
	var night_result: Dictionary = controls.call("read_draft")
	night_draft = night_result.config.duplicate(true) if night_result.get("ok", false) else {}
	_check("Enter applies the selected preset to the draft", night_result.get("ok", false)
		and night_draft.mode == "astronomical" and preset_picker.selected == 5, str(night_result))
	for tab_index: int in 5:
		await ui.tap(KEY_TAB)
	_check("preset mode change refreshes the keyboard focus chain", ui.focus_name() == "Apply", ui.focus_name())
	apply_button = dialog.get("apply_button") as Button
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("valid Apply changes lighting and leaves the pause menu held", app.time_of_day_dialog == null
		and app.pause_menu != null and session.sim.paused and session.holds.has("menu")
		and flight.lighting_config == night_draft
		and _timeline_event_count(flight) == 1)
	_check("Apply preserves tick, state and live controls", session.sim.tick == initial_tick
		and session.sim.state == initial_state and session.commands == initial_commands)
	_check("interactive Apply saves the configured start light", Preferences.load_from(PREFS).lighting_config == night_draft,
		str(Preferences.load_from(PREFS).lighting_config))
	_check("Apply returns focus to Time of day", ui.focus_name() == "TimeOfDay", ui.focus_name())

	app.restart_flight()
	_check("Restart reuses the applied start lighting", app.pause_menu == null and not session.sim.paused
		and session.sim.tick == 0 and flight.lighting_config == night_draft
		and _timeline_event_count(flight) == 0)
	app.open_pause()
	await ui.settle()
	app.end_flight()
	await ui.settle()
	_check("End flight returns Home with the accepted selection", app.flight == null and app.home != null
		and app.home.lighting_config == night_draft and app.home_scene.lighting_config == night_draft
		and Preferences.load_from(PREFS).lighting_config == night_draft)
	app.queue_free()
	await process_frame


func _direct_route_never_touches_preferences() -> void:
	var file: FileAccess = FileAccess.open(DIRECT_PREFS, FileAccess.WRITE)
	_check("direct-route sentinel fixture opens", file != null)
	if file != null:
		file.store_string(SENTINEL)
		file.close()
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray(["--quick-flight"])
	app.preferences_path = DIRECT_PREFS
	root.add_child(app)
	await ui.settle()
	app.open_pause()
	await ui.settle()
	app.open_time_of_day()
	await ui.settle()
	var dialog: CanvasLayer = app.time_of_day_dialog
	var controls: VBoxContainer = dialog.get("controls") as VBoxContainer
	var noon: Dictionary = _select_preset(controls, 3)
	var apply_button: Button = dialog.get("apply_button") as Button
	apply_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("direct CLI route applies lighting without Home", not app.has_home and app.time_of_day_dialog == null
		and app.pause_menu != null and app.flight.lighting_config == noon and app.flight.session.sim.paused)
	_check("direct route does not read or write the preference file", _read_text(DIRECT_PREFS) == SENTINEL
		and not FileAccess.file_exists(DIRECT_PREFS + ".bad"), _read_text(DIRECT_PREFS))
	app.queue_free()
	await process_frame


func _assert_modal_bounds(dialog: CanvasLayer, locale: String, size: Vector2i) -> void:
	TranslationServer.set_locale(locale)
	root.size = size
	await ui.settle()
	var panel: PanelContainer = dialog.find_child("TimeOfDayPanel", true, false) as PanelContainer
	var rect: Rect2 = panel.get_global_rect()
	var fits: bool = rect.position.x >= -1.0 and rect.position.y >= -1.0 \
		and rect.end.x <= float(size.x) + 1.0 and rect.end.y <= float(size.y) + 1.0
	_check("%s modal fits %d×%d" % [locale, size.x, size.y], fits, str(rect))


func _select_night(controls: VBoxContainer) -> Dictionary:
	return _select_preset(controls, 5)


func _select_preset(controls: VBoxContainer, preset_index: int) -> Dictionary:
	var mode_picker: OptionButton = controls.find_child("LightingMode", true, false) as OptionButton
	mode_picker.select(1)
	mode_picker.item_selected.emit(1)
	controls.call("_on_preset_selected", preset_index)
	var result: Dictionary = controls.call("read_draft")
	_check("time preset produces a valid draft", result.get("ok", false), str(result))
	return result.config.duplicate(true) if result.get("ok", false) else {}


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


func _timeline_event_count(flight: Node) -> int:
	var timeline: Dictionary = flight.get("_visual_timeline")
	var events: Array = timeline.get("events", [])
	return events.size()


func _remove_prefs(path: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".bad"))

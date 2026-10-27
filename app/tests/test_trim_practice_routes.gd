# D6-TRIM-01: Home → Trim practice → Apply → Fly. The draft is saved only on Apply, the Home flight receives the
# validated selection and the shell's session registry, and the dialog fits 1080p (primary) and 720p (fallback).
extends SceneTree

const OutOfTrim := preload("res://sim/out_of_trim.gd")
const Preferences := preload("res://app_state/preferences.gd")
const UiDriver := preload("res://tests/ui_driver.gd")

const PREFS := "user://test_trim_practice_settings.cfg"

var _failures := 0
var ui: RefCounted


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	ui = UiDriver.new(self)
	_run()


func _run() -> void:
	TranslationServer.set_locale("en")
	root.size = Vector2i(1920, 1080)
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	await ui.settle()
	root.size = Vector2i(1920, 1080) # AppRoot can restore the headless window's size during startup.
	await ui.settle()
	_check("Home summarizes trim practice as off", app.home.trim_practice_summary_label.text.contains("Next flight trim: Off"),
		app.home.trim_practice_summary_label.text)
	var practice := await _tab_until("NavPractice")
	_check("Home Practice tab is keyboard reachable", practice, ui.focus_name())
	await ui.tap(KEY_ENTER)
	await ui.settle()
	await ui.tap(KEY_DOWN) # Natural Random
	await ui.tap(KEY_DOWN) # Failure practice
	await ui.tap(KEY_DOWN) # Trim practice
	_check("Home keyboard path reaches Trim practice", ui.focus_name() == "TrimPractice", ui.focus_name())
	await ui.tap(KEY_ENTER)
	await ui.settle()
	var menu: CanvasLayer = app.trim_practice_menu
	_check("Home opens the trim practice screen", menu != null and app.screens.is_top("trim_practice"))
	if menu == null:
		await _finish(app)
		return
	_check("trim practice card fits 1920×1080", _card_fits_viewport(menu), _card_bounds_detail(menu))
	_check("trim practice starts on Apply", ui.focus_name() == "Apply", ui.focus_name())
	menu.enabled_check.button_pressed = true
	menu.intensity_spin.value = 70.0
	await ui.tap(KEY_ESCAPE)
	_check("Escape returns to Home", app.trim_practice_menu == null and app.screens.is_top("home"))
	_check("Cancel discards the draft", app.preferences.out_of_trim_config == OutOfTrim.defaults())

	app.open_trim_practice_settings(app.home.trim_practice_button)
	await ui.settle()
	menu = app.trim_practice_menu
	menu.enabled_check.button_pressed = true
	menu.intensity_spin.value = 70.0
	menu.every_flight_check.button_pressed = true
	root.size = Vector2i(1280, 720)
	await ui.settle()
	_check("trim practice card still fits the 1280×720 fallback", _card_fits_viewport(menu), _card_bounds_detail(menu))
	root.size = Vector2i(1920, 1080)
	await ui.settle()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	var saved := {"enabled": true, "intensity_percent": 70, "mode": OutOfTrim.MODE_EVERY_FLIGHT}
	_check("Apply returns to Home", app.trim_practice_menu == null and app.screens.is_top("home"))
	_check("Apply saves the choice", app.preferences.out_of_trim_config == saved, str(app.preferences.out_of_trim_config))
	_check("Apply persists the choice", Preferences.load_from(PREFS).out_of_trim_config == saved)
	_check("Home summarizes the next flight", app.home.trim_practice_summary_label.text.contains("70% out of trim · every flight"),
		app.home.trim_practice_summary_label.text)

	var fly := await _tab_until("Fly")
	_check("Fly is keyboard reachable", fly, ui.focus_name())
	await ui.tap(KEY_ENTER)
	await ui.settle()
	var main: Node = app.flight
	_check("the Home flight receives the saved selection", main != null and main.out_of_trim_config == saved)
	if main == null:
		await _finish(app)
		return
	_check("the Home flight shares the shell's session registry", is_same(main.out_of_trim_airframes, app._out_of_trim_airframes))
	var status: Dictionary = main.session.out_of_trim_status()
	_check("the flight flies an out-of-trim airframe", bool(status.get("active", false))
		and not OutOfTrim.is_zero(status.get("offset", PackedFloat64Array([0.0, 0.0, 0.0]))), str(status))
	await _finish(app)


func _finish(app: Node) -> void:
	await ui.close_app(app)
	ui = null
	for _frame in 10:
		await process_frame
	for path in [PREFS, PREFS + ".bad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("all trim practice route checks passed" if _failures == 0 else "%d failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _tab_until(target: String, max_presses := 32) -> bool:
	for _step in max_presses:
		if ui.focus_name() == target:
			return true
		await ui.tap(KEY_TAB)
	return ui.focus_name() == target


func _fits_viewport(control: Control) -> bool:
	var rect := control.get_global_rect()
	var viewport_rect: Rect2 = control.get_viewport().get_visible_rect()
	return rect.position.x >= viewport_rect.position.x and rect.position.y >= viewport_rect.position.y \
		and rect.end.x <= viewport_rect.end.x and rect.end.y <= viewport_rect.end.y


func _card_fits_viewport(layer: Node) -> bool:
	var cards: Array[Node] = layer.find_children("*", "PanelContainer", true, false)
	return not cards.is_empty() and _fits_viewport(cards[0] as Control)


func _card_bounds_detail(layer: Node) -> String:
	var cards: Array[Node] = layer.find_children("*", "PanelContainer", true, false)
	if cards.is_empty():
		return "no card; viewport=%s" % str(layer.get_viewport().get_visible_rect())
	return "%s viewport=%s" % [str((cards[0] as Control).get_global_rect()), str(layer.get_viewport().get_visible_rect())]

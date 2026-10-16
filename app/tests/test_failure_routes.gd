extends SceneTree

const AppRoot := preload("res://app_root.gd")
const FailureConfig := preload("res://failures/config.gd")
const FailureMenu := preload("res://ui/failures_menu.gd")
const Home := preload("res://ui/home.gd")
const PauseMenu := preload("res://ui/pause_menu.gd")
const Preferences := preload("res://app_state/preferences.gd")
const UiDriver := preload("res://tests/ui_driver.gd")

const PREFS := "user://test_failure_ui_settings.cfg"

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
	root.size = Vector2i(1280, 720)
	await process_frame
	var defaults := FailureConfig.defaults()
	_check("failure defaults are off, non-catastrophic and visible", defaults == {
		"probability_percent": 0, "include_catastrophic": false, "notify": true,
	})
	_check("failure validator accepts an integer percentage", FailureConfig.validate({
		"probability_percent": 100, "include_catastrophic": true, "notify": false,
	}).ok)
	_check("failure validator rejects a percentage outside the slider range",
		not FailureConfig.validate({"probability_percent": 101, "include_catastrophic": false, "notify": true}).ok)
	_check("failure validator rejects a floating percentage",
		not FailureConfig.validate({"probability_percent": 12.5, "include_catastrophic": false, "notify": true}).ok)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var invalid_file := ConfigFile.new()
	invalid_file.set_value("meta", "schema", Preferences.SCHEMA)
	invalid_file.set_value("failures", "config", {
		"probability_percent": "often", "include_catastrophic": false, "notify": true,
	})
	_check("write invalid preference fixture", invalid_file.save(PREFS) == OK)
	var recovered: Dictionary = Preferences.load_from(PREFS)
	_check("invalid failure preference recovers to defaults", recovered.failure_config == defaults
		and "invalid failure settings" in recovered.note)
	var invalid_save := Preferences.DEFAULTS.duplicate(true)
	invalid_save.failure_config = {"probability_percent": -1, "include_catastrophic": false, "notify": true}
	_check("preferences refuse to save invalid failure config", Preferences.save_to(PREFS, invalid_save) == ERR_INVALID_DATA)

	var round_trip := Preferences.DEFAULTS.duplicate(true)
	round_trip.writable = true
	round_trip.failure_config = {"probability_percent": 100, "include_catastrophic": true, "notify": false}
	_check("save valid failure preference", Preferences.save_to(PREFS, round_trip) == OK)
	var loaded: Dictionary = Preferences.load_from(PREFS)
	_check("failure preferences round-trip", loaded.failure_config == round_trip.failure_config)

	var home_probe: Control = Home.new()
	home_probe.set_aircraft("xcell-60-research")
	_check("rotorcraft Home disables failure settings", home_probe.failures_button.disabled)
	home_probe.free()
	for flag in ["--failures=100", "--catastrophic", "--failure-notices=false", "--failure-seed=23"]:
		_check("direct helicopter route rejects %s" % flag,
			AppRoot.failure_cli_options_unsupported_for_aircraft("xcell-60-research", PackedStringArray([flag])))
		_check("direct fixed-wing route keeps %s available" % flag,
			not AppRoot.failure_cli_options_unsupported_for_aircraft("jensen-ugly-stik-60", PackedStringArray([flag])))
	_check("helicopter route without failure options stays available",
		not AppRoot.failure_cli_options_unsupported_for_aircraft("xcell-60-research", PackedStringArray(["--aircraft=xcell-60-research"])))

	# Exercise the menu's actual controls before integrating it through Home and Pause.
	var standalone: CanvasLayer = FailureMenu.new(defaults)
	root.add_child(standalone)
	await ui.settle()
	_check("probability slider range is integer 0..100 and editable",
		standalone.probability_slider.min_value == 0.0 and standalone.probability_slider.max_value == 100.0
		and standalone.probability_slider.step == 1.0 and standalone.probability_slider.editable)
	_check("probability spin box range is integer 0..100 and editable",
		standalone.probability_spin.min_value == 0.0 and standalone.probability_spin.max_value == 100.0
		and standalone.probability_spin.step == 1.0 and standalone.probability_spin.editable)
	standalone.probability_slider.value = 100.0
	_check("slider updates percentage entry", int(standalone.probability_spin.value) == 100)
	standalone.probability_spin.value = 0.0
	_check("percentage entry updates slider", int(standalone.probability_slider.value) == 0)
	standalone.queue_free()
	await process_frame

	# Home -> Cancel and Home -> Apply: cancellation discards probability/category edits.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	await ui.settle()
	# AppRoot can restore the headless dummy window's 64×64 size during startup.
	root.size = Vector2i(1280, 720)
	await ui.settle()
	_check("Home exposes a disabled-by-default failure summary",
		app.home.failure_summary_label.text.contains("Next flight failures: Off"))
	var practice_reachable_from_home := await _tab_until("NavPractice")
	_check("Home Practice tab is keyboard reachable", practice_reachable_from_home, ui.focus_name())
	if not practice_reachable_from_home:
		await ui.close_app(app)
		ui = null
		for _frame in 10:
			await process_frame
		quit(1)
		return
	await ui.tap(KEY_ENTER) # Practice page
	await ui.settle()
	_check("Home failure summary fits the 1280×720 viewport", _fits_viewport(app.home.failure_summary_label),
		_bounds_detail(app.home.failure_summary_label))
	await ui.tap(KEY_DOWN) # Natural Random
	await ui.tap(KEY_DOWN) # Failure practice
	_check("Home keyboard path reaches Failure practice", ui.focus_name() == "Failures", ui.focus_name())
	await ui.tap(KEY_ENTER)
	await ui.settle()
	var menu: CanvasLayer = app.failure_menu
	_check("Home opens the Failure screen", menu != null and app.screens.is_top("failures"))
	if menu == null:
		await ui.close_app(app)
		quit(1)
		return
	_check("Home failure card fits the 1280×720 viewport", _card_fits_viewport(menu), _card_bounds_detail(menu))
	_check("Home keeps the standard notice explanation", not menu.current_flight_settings
		and "Turning notices off hides labels" in menu.notice_hint_label.text)
	_check("menu starts on Apply", ui.focus_name() == "Apply", ui.focus_name())
	menu.probability_spin.value = 82.0
	menu.catastrophic_check.button_pressed = true
	await ui.tap(KEY_ESCAPE)
	_check("Escape returns to Home", app.failure_menu == null and app.screens.is_top("home"))
	_check("Cancel discarded probability and category", app.preferences.failure_config == defaults)

	await ui.tap(KEY_ENTER)
	await ui.settle()
	menu = app.failure_menu
	menu.probability_spin.value = 100.0
	menu.catastrophic_check.button_pressed = true
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("Enter confirms and returns to Home", app.failure_menu == null and app.screens.is_top("home"))
	_check("Apply saves probability and catastrophe choice", app.preferences.failure_config == {
		"probability_percent": 100, "include_catastrophic": true, "notify": true,
	})
	_check("Home summarizes the next flight",
		app.home.failure_summary_label.text.contains("Next flight failures: 100% · Catastrophic enabled"))
	_check("Apply persisted failure preferences", Preferences.load_from(PREFS).failure_config == app.preferences.failure_config)

	# Normal fixed-wing Home route passes validated settings into Main before it enters the tree.
	var fly_reachable := await _tab_until("Fly")
	_check("Home Fly action is keyboard reachable after failure settings", fly_reachable, ui.focus_name())
	if not fly_reachable:
		await ui.close_app(app)
		ui = null
		for _frame in 10:
			await process_frame
		quit(1)
		return
	await ui.tap(KEY_ENTER)
	await ui.settle()
	var main: Node = app.flight
	_check("Home flight receives the saved failure configuration",
		main != null and main.failure_config == app.preferences.failure_config)
	_check("flight notices start from the saved preference", main != null and main.failure_notifications)
	if main == null:
		await ui.close_app(app)
		quit(1)
		return
	var scheduled_status: Dictionary = main.session.failure_status()
	_check("100% schedules an incident for this flight before it activates",
		bool(scheduled_status.get("selected", false)) and not bool(scheduled_status.get("active", false)))

	app.open_pause()
	await ui.settle()
	var pause: CanvasLayer = app.pause_menu
	_check("Pause shows next-flight failure settings", pause.failure_settings_button.visible
		and pause.failure_config_label.visible and "100%" in pause.failure_config_label.text)
	var dummy := FakeFailureSession.new()
	var incident_text: String = pause.active_failure_text(dummy, true)
	_check("Pause can render the current incident label and hint",
		"Current failure: Ailerons jammed." in incident_text and "Hint:" in incident_text)
	pause.failure_summary_label.text = incident_text
	pause.failure_summary_label.visible = true
	dummy.free()
	await ui.settle()
	_check("Pause failure summary fits the 1280×720 viewport",
		_fits_viewport(pause.failure_config_label) and _fits_viewport(pause.failure_summary_label),
		_bounds_detail(pause.failure_config_label) + " / " + _bounds_detail(pause.failure_summary_label))

	# All checkbox and percentage edits remain drafts until Apply.
	await ui.tap(KEY_DOWN) # Restart
	await ui.tap(KEY_DOWN) # Session options
	await ui.tap(KEY_ENTER)
	for step in 8:
		if ui.focus_name() == "Failures":
			break
		await ui.tap(KEY_DOWN)
	_check("failure settings are reachable inside Session options", ui.focus_name() == "Failures", ui.focus_name())
	await ui.tap(KEY_ENTER)
	await ui.settle()
	menu = app.failure_menu
	_check("Pause failure card fits the 1280×720 viewport", _card_fits_viewport(menu), _card_bounds_detail(menu))
	_check("Pause explains current-flight and next-flight setting scopes",
		menu.current_flight_settings and "Applying changes updates notices in this flight" in menu.notice_hint_label.text
		and "apply to the next flight" in menu.notice_hint_label.text)
	menu.probability_spin.value = 64.0
	menu.catastrophic_check.button_pressed = false
	menu.notify_check.button_pressed = false
	_check("Pause edits do not change notices before Apply", main.failure_notifications)
	_check("Pause edits leave preferences and active flight unchanged before Apply",
		app.preferences.failure_config.notify and main.failure_config.probability_percent == 100
		and main.failure_config.include_catastrophic)
	await ui.tap(KEY_ESCAPE)
	_check("Cancel discards notice, probability and category edits",
		main.failure_notifications and app.preferences.failure_config == {
			"probability_percent": 100, "include_catastrophic": true, "notify": true,
		})

	await ui.tap(KEY_ENTER) # focus returns to Failure settings when the editor is cancelled
	await ui.settle()
	menu = app.failure_menu
	menu.probability_spin.value = 64.0
	menu.catastrophic_check.button_pressed = false
	menu.notify_check.button_pressed = false
	await ui.tap(KEY_ENTER)
	_check("Pause Apply updates flight notices and saves next-flight configuration",
		app.preferences.failure_config == {
			"probability_percent": 64, "include_catastrophic": false, "notify": false,
		} and not main.failure_notifications and main.failure_config.probability_percent == 100
		and main.failure_config.include_catastrophic)
	_check("pause summary updates after Apply", "64%" in app.pause_menu.failure_config_label.text)
	app.end_flight()
	await ui.settle()
	_check("End returns to Home with applied next-flight preference", app.flight == null
		and app.home.failure_summary_label.text.contains("Next flight failures: 64% · Standard"))
	_check("End debrief reports a scheduled incident that did not activate",
		"Flight ended before the scheduled failure." in app.home.note_label.text)
	var practice_reachable := await _tab_until("NavPractice")
	_check("Home Practice page is keyboard reachable after flight end", practice_reachable, ui.focus_name())
	if not practice_reachable:
		await ui.close_app(app)
		ui = null
		for _frame in 10:
			await process_frame
		quit(1)
		return
	await ui.tap(KEY_ENTER) # Practice page contains the failure summary.
	await ui.settle()
	_check("Home failure debrief fits the 1280×720 viewport", _fits_viewport(app.home.note_label)
		and _fits_viewport(app.home.failure_summary_label),
		_bounds_detail(app.home.note_label) + " / " + _bounds_detail(app.home.failure_summary_label))
	fly_reachable = await _tab_until("Fly")
	_check("Next flight Fly action is keyboard reachable", fly_reachable, ui.focus_name())
	if not fly_reachable:
		await ui.close_app(app)
		ui = null
		for _frame in 10:
			await process_frame
		quit(1)
		return
	await ui.tap(KEY_ENTER)
	await ui.settle()
	var next_main: Node = app.flight
	_check("next Home flight gets the updated failure plan on a new Main instance",
		next_main != null and next_main != main and next_main.failure_config == app.preferences.failure_config)

	await ui.close_app(app)
	ui = null
	for _frame in 10:
		await process_frame
	for path in [PREFS, PREFS + ".bad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("all failure UI checks passed" if _failures == 0 else "%d failed" % _failures)
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


func _bounds_detail(control: Control) -> String:
	return "%s viewport=%s" % [str(control.get_global_rect()), str(control.get_viewport().get_visible_rect())]


func _card_fits_viewport(layer: Node) -> bool:
	if layer == null:
		return false
	var cards: Array[Node] = layer.find_children("*", "PanelContainer", true, false)
	return not cards.is_empty() and _fits_viewport(cards[0] as Control)


func _card_bounds_detail(layer: Node) -> String:
	if layer == null:
		return "no Failure screen"
	var cards: Array[Node] = layer.find_children("*", "PanelContainer", true, false)
	if cards.is_empty():
		return "no card; viewport=%s" % str(layer.get_viewport().get_visible_rect())
	return _bounds_detail(cards[0] as Control)


class FakeFailureSession extends Node:
	func failure_status() -> Dictionary:
		return {
			"active": true,
			"label": "Ailerons jammed.",
			"hint": "Keep adequate airspeed. Use gentle rudder inputs if effective; plan a wide approach.",
		}

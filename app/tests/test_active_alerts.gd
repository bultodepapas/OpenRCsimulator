## A21 §5: selected-alert snapshots, paused stack navigation and menu-device isolation.
extends SceneTree

const Manager := preload("res://render/overlays/overlay_manager.gd")
const Inspector := preload("res://ui/active_alerts.gd")
const Preferences := preload("res://app_state/preferences.gd")
const UiDriver := preload("res://tests/ui_driver.gd")
const UiInput := preload("res://ui/ui_input.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const PREFS := "user://test_active_alerts.cfg"

var checks := 0
var failures := 0
var ui: RefCounted


func _initialize() -> void:
	ui = UiDriver.new(self)
	_run.call_deferred()


func _check(label: String, result: bool, detail := "") -> void:
	checks += 1
	if not result:
		failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _sample(codes: PackedStringArray) -> Dictionary:
	return {warnings = codes, paused = true, telemetry = {time_s = 1.0, height_agl = 30.0,
		airspeed = 20.0, vertical_speed = 0.0, bank_deg = 0.0, load_factor = 1.0}}


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	TranslationServer.set_locale("en")
	await _manager_checks()
	await _layout_checks()
	await _route_checks()
	UiInput.isolate_joypads()
	TranslationServer.set_locale("en")
	print("active alerts: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _manager_checks() -> void:
	var manager := Manager.new({preset = "custom", visible = ["warnings"], warning_limit = 1,
		warning_navigation = false, warning_sound = false}, "en")
	root.add_child(manager)
	await process_frame
	_check("new flight has no sample", not manager.warning_snapshot().sampled)
	manager.refresh_numbers({})
	_check("no-physics observation is unavailable, not clear", not manager.warning_snapshot().sampled)
	manager.refresh_numbers(_sample(PackedStringArray()))
	_check("valid empty observation is clear", manager.warning_snapshot().sampled and manager.warning_snapshot().codes.is_empty())
	manager.refresh_numbers(_sample(PackedStringArray(["far", "low", "stall"])))
	_check("selection retains both prioritized dangers and filters navigation", manager.warning_snapshot().codes == PackedStringArray(["stall", "low"]))
	_check("cap one leaves one visible card and both selected codes", manager.frames.warnings.codes.size() == 2
		and manager.frames.warnings.chips.get_child_count() == 1 and manager.frames.warnings.summary.visible)
	var copy: Dictionary = manager.warning_snapshot()
	copy.codes.clear()
	_check("caller cannot mutate manager selection", manager.warning_snapshot().codes == PackedStringArray(["stall", "low"]))
	manager.visible = false
	manager.refresh_numbers(_sample(PackedStringArray(["low", "far"])))
	_check("hidden layer refreshes selection without relying on rail", manager.warning_snapshot().codes == PackedStringArray(["low"]))
	manager.set_warning_option("warning_navigation", true)
	_check("category changes reselect while hidden", manager.warning_snapshot().codes == PackedStringArray(["low", "far"]))
	manager.set_overlay_visible("warnings", false)
	_check("closed rail clears cards but not selected snapshot", manager.frames.warnings.codes.is_empty()
		and manager.warning_snapshot().codes == PackedStringArray(["low", "far"]))
	_check("inspection does not change configured cap", manager.settings.warning_limit == 1)
	manager.reset_flight()
	_check("reset makes prior sample unavailable", not manager.warning_snapshot().sampled and manager.warning_snapshot().codes.is_empty())
	manager.refresh_numbers(_sample(PackedStringArray(["low", "far"])))
	_check("same codes after reset produce a fresh selection", manager.warning_snapshot().sampled
		and manager.warning_snapshot().codes == PackedStringArray(["low", "far"]))
	manager.queue_free()
	await process_frame


func _layout_checks() -> void:
	var old_scale: float = UiTheme.text_scale
	var unavailable := Inspector.new()
	root.add_child(unavailable)
	await ui.settle()
	var unavailable_text := unavailable.find_child("AlertList", true, false).get_child(0) as Label
	_check("unavailable sample is distinct and focuses Close", unavailable.close_button.has_focus()
		and unavailable_text.text == "No alert sample is available yet.")
	unavailable.queue_free()
	await process_frame
	for locale: String in ["en", "es", "de", "fr", "it", "pt_BR", "ru", "ja", "zh_Hans"]:
		TranslationServer.set_locale(locale)
		for scale: float in [1.0, 2.0]:
			UiTheme.text_scale = scale
			var dialog := Inspector.new({sampled = true, codes = PackedStringArray(["stall", "low"])})
			root.add_child(dialog)
			await ui.settle()
			var scroll := dialog.find_child("AlertScroll", true, false) as ScrollContainer
			var first: Button = dialog.alert_buttons[0]
			var second: Button = dialog.alert_buttons[1]
			_check("%s %.0f%% initial focus and selected first row" % [locale, scale * 100],
				first.has_focus() and first.button_pressed)
			_check("%s %.0f%% alert title and explanation" % [locale, scale * 100],
				first.text.contains(TranslationServer.translate("STALL"))
				and first.text.contains(TranslationServer.translate("Ease angle of attack toward zero.")))
			_check("%s %.0f%% first row and Close fit" % [locale, scale * 100],
				scroll.get_global_rect().encloses(first.get_global_rect())
				and Rect2(Vector2.ZERO, Vector2(root.size)).encloses(dialog.close_button.get_global_rect()),
				str([scroll.get_global_rect(), first.get_global_rect(), dialog.close_button.get_global_rect()]))
			await ui.tap(KEY_DOWN)
			_check("%s %.0f%% keyboard selects second row" % [locale, scale * 100],
				second.has_focus() and second.button_pressed and not first.button_pressed,
				"focus=%s pressed=%s/%s neighbors=%s" % [ui.focus_name(), first.button_pressed, second.button_pressed, first.focus_neighbor_bottom])
			dialog.queue_free()
			await process_frame
	UiTheme.text_scale = old_scale
	TranslationServer.set_locale("en")


func _route_checks() -> void:
	var prefs: Dictionary = Preferences.DEFAULTS.duplicate(true)
	prefs.first_flight_hint_seen = true
	prefs.hud.warning_limit = 1
	Preferences.save_to(PREFS, prefs)
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	await ui.settle()
	await ui.tap(KEY_ENTER)
	var started: bool = await ui.wait_until(func() -> bool: return app.flight != null and app.flight.get("_overlays") != null)
	_check("real flight starts with overlay manager", started)
	if not started:
		await ui.close_app(app)
		return
	var flight: Node = app.flight
	var session: Node = flight.session
	app.open_pause()
	await ui.settle()
	flight.set_process(false) # keep the injected accepted sample fixed for this UI test
	var manager: CanvasLayer = flight.get("_overlays")
	manager.refresh_numbers(_sample(PackedStringArray(["low", "stall"])))
	var before_settings: Dictionary = manager.settings.duplicate(true)
	var before_prefs := FileAccess.get_file_as_bytes(PREFS)
	var tick: int = session.sim.tick
	var opener: Button = app.pause_menu.active_alerts_button
	_check("Pause offers review only with the manager", opener.visible and session.holds.has("menu") and session.sim.paused)
	opener.grab_focus()
	await ui.tap(KEY_ENTER)
	var dialog: CanvasLayer = app.screens.get_screen("active_alerts")
	_check("review opens on stack above Pause", dialog != null and app.screens.is_top("active_alerts")
		and not app.pause_menu.get_node("Screen")._active)
	if dialog != null:
		_check("cap one review includes both selected danger explanations", dialog.alert_buttons.size() == 2
			and dialog.alert_buttons[0].text.contains("STALL") and dialog.alert_buttons[1].text.contains("LOW ALTITUDE")
			and dialog.alert_buttons[1].text.contains("Fast sink near terrain."))
		TranslationServer.set_locale("es")
		_check("open snapshot retranslates alert titles and explanations", dialog.alert_buttons[0].text.contains(TranslationServer.translate("STALL"))
			and dialog.alert_buttons[1].text.contains(TranslationServer.translate("Fast sink near terrain.")))
		TranslationServer.set_locale("en")
		manager.refresh_numbers(_sample(PackedStringArray()))
		_check("open screen keeps its copied sample", dialog.alert_buttons.size() == 2 and dialog.alert_buttons[0].text.contains("STALL"))
		for key: Key in [KEY_R, KEY_T, KEY_P, KEY_F5]:
			await ui.tap(key)
		_check("flight shortcuts cannot act behind review", app.screens.is_top("active_alerts")
			and session.sim.tick == tick and session.holds.has("menu") and not flight.recorder.recording)
		await ui.tap(KEY_DOWN)
		_check("keyboard reaches second alert", dialog.alert_buttons[1].has_focus() and dialog.alert_buttons[1].button_pressed)
		await ui.tap(KEY_ESCAPE)
		_check("Escape returns to Pause and opener", app.screens.is_top("pause") and opener.has_focus()
			and session.holds.has("menu") and session.sim.paused)
		await ui.tap(KEY_ENTER)
		dialog = app.screens.get_screen("active_alerts")
		var empty: Label = dialog.find_child("AlertList", true, false).get_child(0) as Label
		_check("new review shows latest valid empty state and focuses Close", dialog.alert_buttons.is_empty()
			and empty.text == "No selected alerts in the latest sample." and dialog.close_button.has_focus())
		await ui.tap(KEY_ESCAPE)
	manager.refresh_numbers(_sample(PackedStringArray(["stall", "low"])))
	UiInput.set_gamepad(UiDriver.FAKE_DEVICE, {accept = {type = "button", button = JOY_BUTTON_X},
		back = {type = "button", button = JOY_BUTTON_Y}})
	await ui.joy_button(JOY_BUTTON_X)
	dialog = app.screens.get_screen("active_alerts")
	_check("selected pad with remapped Accept opens review", dialog != null and dialog.alert_buttons[0].has_focus())
	if dialog != null:
		await _other_pad(JOY_BUTTON_DPAD_DOWN)
		await _other_pad(JOY_BUTTON_Y)
		_check("other device cannot navigate or close", app.screens.is_top("active_alerts") and dialog.alert_buttons[0].has_focus())
		await ui.joy_button(JOY_BUTTON_DPAD_DOWN)
		_check("selected pad navigates", dialog.alert_buttons[1].has_focus() and dialog.alert_buttons[1].button_pressed)
		await ui.joy_button(JOY_BUTTON_Y)
		_check("selected pad remapped Back returns to opener", app.screens.is_top("pause") and opener.has_focus()
			and session.holds.has("menu") and session.sim.tick == tick)
	_check("review leaves cap and all settings unchanged", manager.settings == before_settings and manager.settings.warning_limit == 1)
	_check("review never writes saved preferences", FileAccess.get_file_as_bytes(PREFS) == before_prefs)
	await ui.close_app(app)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))


func _other_pad(button: JoyButton) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = UiDriver.FAKE_DEVICE - 1
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
	await ui.settle()

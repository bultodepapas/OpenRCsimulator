extends SceneTree

const FailureMenu := preload("res://ui/failures_menu.gd")
const FailureCatalog := preload("res://failures/catalog.gd")
const AircraftCatalog := preload("res://app_state/aircraft_catalog.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const AppRoot := preload("res://app_root.gd")
const PauseMenu := preload("res://ui/pause_menu.gd")
const UiDriver := preload("res://tests/ui_driver.gd")

const ORDINARY_IDS: Array[String] = [
	"roll_jam", "pitch_jam", "yaw_jam", "roll_bias", "pitch_bias", "roll_slow",
	"throttle_limit", "throttle_stuck",
]
const PREFS := "user://test_failure_availability_ui.cfg"

var _checks := 0
var _failures := 0
var _ui: RefCounted


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	_ui = UiDriver.new(self)
	await _run()
	print("Failure availability UI: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(label: String, condition: bool, detail: Variant = "") -> void:
	_checks += 1
	if condition:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s: %s" % [label, str(detail)])


func _electric_availability() -> Dictionary:
	var eligible := ORDINARY_IDS.duplicate()
	eligible.append("electric_drive_loss")
	eligible.append("radio_loss")
	return {
		"eligible_ids": eligible,
		"power_loss_ids": ["electric_drive_loss"],
		"power_loss_supported": true,
		"exclusion_reason": "",
	}


func _turbine_availability() -> Dictionary:
	var eligible := ORDINARY_IDS.duplicate()
	eligible.append("radio_loss")
	return {
		"eligible_ids": eligible,
		"power_loss_ids": [],
		"power_loss_supported": false,
		"exclusion_reason": "Turbine flameout and rotor rundown are not modeled.",
	}


func _event_texts(menu: CanvasLayer) -> PackedStringArray:
	var result := PackedStringArray()
	for child: Node in menu.availability_events_column.get_children():
		if child is Label:
			result.append((child as Label).text)
	return result


func _fits_viewport(control: Control) -> bool:
	var viewport_rect: Rect2 = control.get_viewport().get_visible_rect()
	var rect: Rect2 = control.get_global_rect()
	return rect.position.x >= viewport_rect.position.x and rect.position.y >= viewport_rect.position.y \
		and rect.end.x <= viewport_rect.end.x and rect.end.y <= viewport_rect.end.y


func _open_with_keyboard(menu: CanvasLayer) -> void:
	menu.availability_button.grab_focus()
	await _ui.settle()
	await _ui.tap(KEY_ENTER)
	await _ui.settle()


func _run() -> void:
	TranslationServer.set_locale("en")
	var config := {"probability_percent": 42, "include_catastrophic": false, "notify": true}
	var menu: CanvasLayer = FailureMenu.new(config, _electric_availability())
	menu.current_flight_settings = true
	root.add_child(menu)
	await _ui.settle()
	_check("existing settings constructor accepts optional availability", menu.get_draft_config() == config)
	_check("settings card fits the 1280x720 viewport", _fits_viewport(menu.settings_card), menu.settings_card.get_global_rect())
	_check("settings screen keeps the Apply default focus", _ui.focus_name() == "Apply", _ui.focus_name())
	var pause_hint_found := false
	for child: Node in menu.find_children("*", "Label", true, false):
		if child is Label and "Applying changes updates notices in this flight" in (child as Label).text:
			pause_hint_found = true
	_check("pause settings retain their current-flight notice semantics", pause_hint_found)
	await _open_with_keyboard(menu)
	_check("availability button opens the details screen by keyboard", menu.availability_card.visible and not menu.settings_card.visible)
	_check("details screen focuses its Back button", _ui.focus_name() == "AvailabilityBack", _ui.focus_name())
	_check("expanded details card fits the 1280x720 viewport", _fits_viewport(menu.availability_card), menu.availability_card.get_global_rect())
	_check("unsupported catastrophe is omitted from the default eligible list",
		_event_texts(menu).size() == 9 and not _event_texts(menu).has("Radio link lost."), _event_texts(menu))
	_check("supported electric source-loss label is shown", _event_texts(menu).has("Electric motor power lost."), _event_texts(menu))
	await _ui.tap(KEY_ESCAPE)
	_check("Escape from details returns to settings without cancelling", menu.settings_card.visible and not menu.availability_card.visible)
	_check("Back restores focus to the availability button", _ui.focus_name() == "AvailableFailures", _ui.focus_name())
	menu.catastrophic_check.button_pressed = true
	menu.probability_spin.value = 67.0
	await _open_with_keyboard(menu)
	_check("radio-loss label appears only when catastrophe is enabled", _event_texts(menu).has("Radio link lost."), _event_texts(menu))
	_check("ten supported rows appear in the bounded scroll area", menu.availability_events_column.get_child_count() == 10
		and menu.availability_scroll.get_global_rect().size.y >= 200.0
		and _fits_viewport(menu.availability_scroll))
	# A roomy dialog need not scroll. Exercise keyboard scrolling after shrinking the live window.
	root.size = Vector2i(960, 540)
	root.content_scale_size = root.size
	for frame in 6: await process_frame
	var scroll_max: float = menu.availability_scroll.get_v_scroll_bar().max_value
	var scroll_page: float = menu.availability_scroll.get_v_scroll_bar().page
	var scroll_bottom: float = maxf(0.0, scroll_max - scroll_page)
	_check("long eligible lists can scroll vertically", scroll_max > 0.0, scroll_max)
	await _ui.tap(KEY_TAB)
	_check("scroll list accepts keyboard focus", _ui.focus_name() == "AvailabilityScroll", _ui.focus_name())
	await _ui.tap(KEY_END)
	_check("End reaches the final available event from the top", is_equal_approx(menu.availability_scroll.scroll_vertical, scroll_bottom),
		{"scroll": menu.availability_scroll.scroll_vertical, "bottom": scroll_bottom, "max": scroll_max, "page": scroll_page})
	var final_event := menu.availability_events_column.get_child(9) as Label
	var final_rect: Rect2 = final_event.get_global_rect()
	var scroll_rect: Rect2 = menu.availability_scroll.get_global_rect()
	_check("End makes the last event visible in the scroll viewport",
		final_rect.position.y >= scroll_rect.position.y - 1.0 and final_rect.end.y <= scroll_rect.end.y + 1.0,
		{"event": final_rect, "scroll": scroll_rect})
	await _ui.tap(KEY_HOME)
	await _ui.tap(KEY_PAGEDOWN)
	_check("Page Down scrolls the focused list", menu.availability_scroll.scroll_vertical > 0.0,
		menu.availability_scroll.scroll_vertical)
	await _ui.tap(KEY_HOME)
	_check("Home returns the list to its first event", is_zero_approx(menu.availability_scroll.scroll_vertical),
		menu.availability_scroll.scroll_vertical)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	await _ui.settle()
	_check("expanded ten-row details still fit the 1280x720 viewport", _fits_viewport(menu.availability_card), menu.availability_card.get_global_rect())
	await _ui.tap(KEY_ESCAPE)
	_check("Back from scrolled details preserves the settings draft",
		menu.settings_card.visible and int(menu.probability_spin.value) == 67
		and menu.catastrophic_check.button_pressed and _ui.focus_name() == "AvailableFailures")
	menu.queue_free()
	await process_frame
	await process_frame

	var unavailable: CanvasLayer = FailureMenu.new(config)
	root.add_child(unavailable)
	await _ui.settle()
	await _open_with_keyboard(unavailable)
	_check("legacy constructor with blank availability reports unavailable", unavailable.availability_unavailable_label.visible
		and unavailable.availability_events_column.get_child_count() == 0)
	var cancelled := [false]
	unavailable.cancelled.connect(func() -> void: cancelled[0] = true)
	await _ui.tap(KEY_ESCAPE)
	_check("first Escape returns from details without cancelling", not cancelled[0] and unavailable.settings_card.visible)
	await _ui.tap(KEY_ESCAPE)
	_check("second Escape cancels from settings", cancelled[0])
	unavailable.queue_free()
	await process_frame
	await process_frame

	TranslationServer.set_locale("es")
	var turbine: CanvasLayer = FailureMenu.new(config, _turbine_availability())
	turbine.current_flight_settings = true
	root.add_child(turbine)
	await _ui.settle()
	_check("Spanish pause settings card fits the 1280x720 viewport", _fits_viewport(turbine.settings_card), turbine.settings_card.get_global_rect())
	await _open_with_keyboard(turbine)
	_check("Spanish source-loss exclusion reason is shown", turbine.source_loss_reason_label.visible
		and turbine.source_loss_reason_label.text == "No se modelan la pérdida de llama de la turbina ni la desaceleración del rotor.",
		turbine.source_loss_reason_label.text)
	_check("unsupported propulsion has no source-loss event label", not _event_texts(turbine).has("Engine combustion stopped.")
		and not _event_texts(turbine).has("Electric motor power lost."), _event_texts(turbine))
	_check("Spanish event labels are translated", _event_texts(turbine).has("Alerones trabados."), _event_texts(turbine))
	_check("Spanish list scrolling hint is translated",
		TranslationServer.translate("Focus the list, then use arrow keys or Page Up/Down to scroll.")
		== "Enfoca la lista y usa las flechas o RePág/AvPág para desplazarte.")
	_check("Spanish expanded details card fits the 1280x720 viewport", _fits_viewport(turbine.availability_card), turbine.availability_card.get_global_rect())
	turbine.queue_free()
	await process_frame
	await process_frame
	await _test_real_model_routes()


func _test_real_model_routes() -> void:
	TranslationServer.set_locale("en")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	await _ui.settle()
	var model_ids: PackedStringArray = AircraftCatalog.airplane_flyable_ids()
	_check("Home availability check covers every catalog airplane", model_ids.size() >= 8, model_ids.size())
	var selected_power_model: Dictionary = {}
	var selected_power_id := ""
	for aircraft_id: String in model_ids:
		var entry: Dictionary = AircraftCatalog.entry(aircraft_id)
		var loaded: Dictionary = AircraftData.load_file(str(entry.get("data", "")))
		_check(aircraft_id + " Home selection has validated model data", bool(loaded.get("ok", false)), loaded.get("errors", PackedStringArray()))
		if not bool(loaded.get("ok", false)):
			continue
		var expected: Dictionary = FailureCatalog.availability(loaded.model)
		if bool(expected.get("power_loss_supported", false)) and selected_power_model.is_empty():
			selected_power_model = loaded.model
			selected_power_id = aircraft_id
		app.home.set_aircraft(aircraft_id)
		app.open_failures_settings(app.home.failures_button)
		await _ui.settle()
		var menu: CanvasLayer = app.failure_menu
		_check(aircraft_id + " Home passes model-specific availability into settings",
			menu != null and menu.failure_availability == expected,
			menu.failure_availability if menu != null else "no FailureMenu")
		if menu == null:
			continue
		menu.availability_button.pressed.emit()
		await _ui.settle()
		var event_labels := _event_texts(menu)
		var power_ids: Array = expected.get("power_loss_ids", [])
		if not power_ids.is_empty():
			var power_definition: Dictionary = FailureCatalog.definition(str(power_ids[0]))
			_check(aircraft_id + " Home shows its supported source-loss event",
				event_labels.has(str(power_definition.get("label", ""))), event_labels)
			var other_power_label := "Electric motor power lost." if str(power_ids[0]) == "glow_fuel_cut" else "Engine combustion stopped."
			_check(aircraft_id + " Home hides the other propulsion family event",
				not event_labels.has(other_power_label), event_labels)
		else:
			var expected_reason := TranslationServer.translate(str(expected.get("exclusion_reason", "")))
			_check(aircraft_id + " Home explains unavailable source-loss behavior",
				menu.source_loss_reason_label.visible and menu.source_loss_reason_label.text == expected_reason,
				menu.source_loss_reason_label.text)
		app.close_failures_settings()
		await _ui.settle()

	if not selected_power_model.is_empty():
		_check("Pause source-loss check uses an aircraft different from current Home selection",
			app.home.aircraft_id != selected_power_id,
			{"home": app.home.aircraft_id, "accepted": selected_power_id})
		var accepted_session := FakeAcceptedSession.new()
		accepted_session.aircraft = {"ok": true, "model": selected_power_model}
		var accepted_flight := FakeAcceptedFlight.new()
		accepted_flight.aircraft_id = selected_power_id
		accepted_flight.session = accepted_session
		app.flight = accepted_flight
		var pause := PauseMenu.new()
		app.pause_menu = pause
		app.screens.push("pause", pause, app.home.failures_button)
		await _ui.settle()
		app.open_failures_settings(pause.failure_settings_button)
		await _ui.settle()
		var pause_menu: CanvasLayer = app.failure_menu
		var expected_pause: Dictionary = FailureCatalog.availability(selected_power_model)
		_check("Pause reads source-loss availability from the accepted session model",
			pause_menu != null and pause_menu.failure_availability == expected_pause
			and pause_menu.current_flight_settings,
			pause_menu.failure_availability if pause_menu != null else "no FailureMenu")
		if pause_menu != null:
			pause_menu.availability_button.pressed.emit()
			await _ui.settle()
			var expected_power_ids: Array = expected_pause.get("power_loss_ids", [])
			var expected_power: Dictionary = FailureCatalog.definition(str(expected_power_ids[0]))
			_check("Pause detail shows the accepted aircraft's source-loss event",
				_event_labels_has(pause_menu, str(expected_power.get("label", ""))), _event_texts(pause_menu))
			app.close_failures_settings()
			await _ui.settle()
		app.screens.pop()
		app.flight = null
		accepted_flight.free()
		await _ui.settle()
	else:
		_check("Pause source-loss verification found a supported power model", false)
	app.queue_free()
	await process_frame
	await process_frame
	for path in [PREFS, PREFS + ".bad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _event_labels_has(menu: CanvasLayer, label_text: String) -> bool:
	return _event_texts(menu).has(label_text)


class FakeAcceptedSession extends RefCounted:
	var aircraft: Dictionary = {}


class FakeAcceptedFlight extends Node:
	var aircraft_id := ""
	var session: Variant

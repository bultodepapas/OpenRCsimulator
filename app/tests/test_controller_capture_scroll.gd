extends SceneTree

const ControllerSetup := preload("res://ui/controller_setup.gd")
const Fixtures := preload("res://tests/test_jeti_setup.gd")
const ScreenTheme := preload("res://ui/ui_theme.gd")
const UiScale := preload("res://ui/ui_scale.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	InputMap.load_from_project_settings()
	_run.call_deferred()


func _run() -> void:
	# Product priority: 1080p, larger displays, then the compatibility fallback.
	for size in [Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160), Vector2i(1280, 720)]:
		root.size = size
		UiScale.apply(root)
		for locale in ["en", "es"]:
			TranslationServer.set_locale(locale)
			for scale in [1.0, 2.0]:
				ScreenTheme.text_scale = scale
				await _test_capture("%s %s text=%s" % [size, locale, scale])
	ScreenTheme.text_scale = 1.0
	TranslationServer.set_locale("en")
	print("Controller capture scroll: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _settle() -> void:
	for _frame in 4:
		await process_frame


func _check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label)


func _position_target(scroll: ScrollContainer, target: Button) -> int:
	target.grab_focus()
	await _settle()
	scroll.ensure_control_visible(target)
	await _settle()
	return scroll.scroll_vertical


func _check_position(tag: String, scroll: ScrollContainer, target: Button, before: int) -> void:
	_check(tag + " does not reset scroll (%d -> %d)" % [before, scroll.scroll_vertical], scroll.scroll_vertical > 0)
	_check(tag + " retains focus", root.gui_get_focus_owner() == target)
	_check(tag + " keeps row visible (%s in %s)" % [target.get_global_rect(), scroll.get_global_rect()], scroll.get_global_rect().grow(1.0).encloses(target.get_global_rect()))


func _button_event(button_index: int, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 5
	event.button_index = button_index
	event.pressed = pressed
	Input.parse_input_event(event)


func _escape() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_ESCAPE
	event.keycode = KEY_ESCAPE
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)


func _test_capture(tag: String) -> void:
	var store := Fixtures.FakeStore.new()
	var setup := ControllerSetup.new()
	setup.configure(Fixtures.FakeRegistry.new(), store, 5, -1)
	root.add_child(setup)
	await _settle()
	setup.select_section("buttons")
	await _settle()
	var scroll := setup.find_child("ControllerSetupScroll", true, false) as ScrollContainer
	var actions := ["camera_zoom_in", "camera_zoom_out", "camera_auto_zoom", "lights_cycle", "rates_toggle"]
	for index in actions.size():
		var action_id: String = actions[index]
		var target := setup.find_child("Remap_" + action_id, true, false) as Button
		var before := await _position_target(scroll, target)
		_check(tag + " lower action requires scrolling", before > 0)
		target.pressed.emit()
		_check(tag + " start does not navigate", scroll.scroll_vertical == before)
		await _settle()
		_check_position(tag + " start " + action_id, scroll, target, before)
		_button_event(100 + index, true)
		_button_event(100 + index, false)
		await _settle()
		_check(tag + " commits " + action_id, setup.current_profile().actions.get(action_id, {}).get("button", -1) == 100 + index)
		_check_position(tag + " accepted " + action_id, scroll, target, before)
	# A mouse wheel or scrollbar must remain usable while a row has focus.
	scroll.scroll_vertical = 0
	await _settle()
	_check(tag + " manual scrolling is not undone", scroll.scroll_vertical == 0)
	await _position_target(scroll, setup.find_child("Remap_rates_toggle", true, false) as Button)
	setup._queue_mapping_focus_visibility()
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	# parse_input_event consumes window pixels; the GUI uses the scaled canvas.
	wheel.position = root.get_final_transform() * scroll.get_global_rect().get_center()
	wheel.global_position = wheel.position
	Input.parse_input_event(wheel)
	Input.flush_buffered_events()
	_check(tag + " wheel cancels pending follow", not setup._mapping_focus_layout_pending)
	scroll.scroll_vertical = 0
	await _settle()
	_check(tag + " manual scroll wins over pending layout", scroll.scroll_vertical == 0)
	# A rejected duplicate and Escape both keep the edited row and prior binding.
	var target := setup.find_child("Remap_rates_toggle", true, false) as Button
	var before := await _position_target(scroll, target)
	target.pressed.emit()
	_button_event(100, true)
	_button_event(100, false)
	await _settle()
	_check(tag + " rejects conflict", setup.current_profile().actions.rates_toggle.button == 104 and not setup._is_capture_active())
	_check_position(tag + " rejected", scroll, target, before)
	target.pressed.emit()
	_escape()
	await _settle()
	_check(tag + " cancels capture", not setup._is_capture_active() and setup.current_profile().actions.rates_toggle.button == 104)
	_check_position(tag + " cancelled", scroll, target, before)
	var clear_button := setup.find_child("Clear_rates_toggle", true, false) as Button
	clear_button.grab_focus()
	await _settle()
	before = scroll.scroll_vertical
	clear_button.pressed.emit()
	await _settle()
	_check(tag + " clears binding", setup.current_profile().actions.rates_toggle.type == "unbound")
	_check_position(tag + " cleared", scroll, target, before)
	# Explicit navigation must still reset, expose filtered actions and cancel capture.
	target.pressed.emit()
	setup.select_section("profile")
	await _settle()
	_check(tag + " navigation cancels capture", not setup._is_capture_active() and scroll.scroll_vertical == 0)
	setup.action_filter.select(3)
	setup._on_action_filter_selected(3)
	setup._start_capture("rates_toggle", target)
	await _settle()
	_check(tag + " programmatic capture reveals hidden row", setup._selected_section == "buttons" and setup.action_filter.selected == 0 and target.is_visible_in_tree() and target.has_focus())
	_escape()
	# All AUX channels are populated so the last switch is below the fold.
	for index in 3:
		var aux_name: String = ["smoke", "flaps", "gear"][index]
		_check(tag + " installs " + aux_name, setup._commit_aux_binding(aux_name, {"type": "switch", "buttons": [20 + index * 3, 21 + index * 3, 22 + index * 3], "invert": false}))
	setup.select_section("aux")
	await _settle()
	target = setup.find_child("AuxSwitchCapture_gear_2", true, false) as Button
	before = await _position_target(scroll, target)
	_check(tag + " AUX requires scrolling", before > 0)
	target.pressed.emit()
	await _settle()
	_check_position(tag + " AUX start", scroll, target, before)
	_button_event(120, true)
	_button_event(120, false)
	await _settle()
	_check(tag + " AUX captured", setup.current_profile().aux.gear.buttons[2] == 120)
	_check_position(tag + " AUX accepted", scroll, target, before)
	target.pressed.emit()
	_button_event(20, true)
	_button_event(20, false)
	await _settle()
	_check(tag + " AUX rejects overlap", setup.current_profile().aux.gear.buttons[2] == 120)
	_check_position(tag + " AUX rejected", scroll, target, before)
	target.pressed.emit()
	_escape()
	await _settle()
	_check_position(tag + " AUX cancelled", scroll, target, before)
	_check(tag + " release tokens consumed", setup._capture_release_tokens.is_empty())
	_check(tag + " valid draft saves", setup._save_profile(false) and store.saved_count == 1)
	_check(tag + " saved mappings retained", store.last_saved_profile.actions.camera_zoom_in.button == 100 and store.last_saved_profile.aux.gear.buttons[2] == 120)
	setup.free()
	await _settle()

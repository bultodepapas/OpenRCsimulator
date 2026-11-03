extends SceneTree

const ControllerSetup := preload("res://ui/controller_setup.gd")
const ControllerProfile := preload("res://input/controller_profile.gd")
const ControllerActions := preload("res://input/controller_actions.gd")
const UiInput := preload("res://ui/ui_input.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const ScreenStack := preload("res://ui/screen_stack.gd")
const RadioCalibration := preload("res://ui/radio_calibration_setup.gd")

class FixtureRegistry extends RefCounted:
	signal devices_changed
	var devices: Array[Dictionary] = [{"id": 15, "name": "DualSense Wireless Controller with a deliberately long device name for layout verification", "kind": "gamepad", "known": true, "connected": true}]
	func get_devices() -> Array[Dictionary]: return devices.duplicate(true)
	func selected_device_id(_role: String) -> int: return 15

class FixtureStore extends RefCounted:
	func load_all() -> Dictionary: return {"ok": true, "profiles": [], "errors": []}
	func match_profile(_device: Dictionary, _devices: Array) -> Dictionary: return {}

class RadioRegistry extends RefCounted:
	signal devices_changed
	var devices: Array[Dictionary] = [{"id": 5, "name": "Fixture radio", "kind": "radio", "connected": true}]
	func get_devices() -> Array[Dictionary]: return devices.duplicate(true)
	func selected_device_id(role: String) -> int: return 5 if role == "flight" else -1
	func device_for_id(id: int) -> Dictionary: return devices[0].duplicate(true) if id == 5 else {}
	func connection_generation(id: int) -> int: return 1 if id == 5 else 0

var failures := 0
var checks := 0
var _axis_reads := 0
var _button_reads := 0
var _axis_value := 0.25
var _pressed_button := -1

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label)

func _settle() -> void:
	for frame in 5:
		await process_frame

func _joy(button: JoyButton, device := 15) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = device
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame
	await _settle()

func _visible_actions(setup: Node) -> PackedStringArray:
	var ids := PackedStringArray()
	for index in ControllerActions.ACTIONS.size():
		if (setup.action_grid.get_child(3 + index * 3) as Control).visible:
			ids.append(str(ControllerActions.ACTIONS[index].id))
	ids.sort()
	return ids

func _preview_axis(_device: int, _axis: int) -> float:
	_axis_reads += 1
	return _axis_value

func _preview_button(_device: int, button: int) -> bool:
	_button_reads += 1
	return button == _pressed_button

func _reset_reads() -> void:
	_axis_reads = 0
	_button_reads = 0

func _preview_tick(setup: Node) -> void:
	setup._preview_clock = 0.0
	setup._process(0.08)

func _test_preview_lifecycle() -> void:
	TranslationServer.set_locale("en")
	var host := Node.new()
	root.add_child(host)
	var screens := ScreenStack.new(host)
	var registry := RadioRegistry.new()
	var setup := ControllerSetup.new()
	setup.axis_preview_provider = _preview_axis
	setup.button_preview_provider = _preview_button
	setup.configure(registry, FixtureStore.new(), 5, -1)
	_check("preview fixture opens Controls", screens.push("controls", setup))
	await _settle()
	setup.set_process(false) # Tick explicitly below; input and device signals stay active.
	var profile: Dictionary = setup.current_profile()
	profile.aux = {
		"smoke": {"type": "axis", "axis": 4, "off": -1.0, "on": 1.0, "invert": false},
		"gear": {"type": "switch", "buttons": [20, 21, 22], "invert": false},
	}
	setup._set_draft_profile(profile)
	for section: String in ["devices", "profile", "buttons"]:
		setup.select_section(section)
		_reset_reads()
		_preview_tick(setup)
		_check(section + " does not poll hidden previews", _axis_reads == 0 and _button_reads == 0)
	_axis_value = 0.25
	_reset_reads()
	setup.select_section("axes")
	_check("opening axes immediately refreshes only flight axes", _axis_reads == 4 and _button_reads == 0
		and setup._preview_labels.roll.text.contains("+0.25"))
	_reset_reads()
	_preview_tick(setup)
	_check("axes periodic refresh excludes AUX", _axis_reads == 4 and _button_reads == 0)
	_axis_value = 0.60
	_pressed_button = 22
	_reset_reads()
	setup.select_section("aux")
	_check("opening AUX immediately refreshes only its assignments", _axis_reads == 1 and _button_reads == 3
		and setup._aux_controls.smoke.preview.text.contains("+0.60") and setup._aux_controls.gear.preview.text.contains("Button 22"))
	_reset_reads()
	_preview_tick(setup)
	_check("AUX periodic refresh excludes flight axes", _axis_reads == 1 and _button_reads == 3)
	setup.select_section("axes")
	var before: String = setup._preview_labels.roll.text
	var wizard := RadioCalibration.new()
	_check("calibration accepts the connected radio", wizard.configure(registry, 5, setup.current_profile()))
	setup.set_process(true)
	_check("calibration covers Controls", screens.push("radio_calibration", wizard) and not setup._screen.visible and setup.is_processing())
	setup.set_process(false)
	_axis_value = 0.75
	_reset_reads()
	_preview_tick(setup)
	_check("covered Controls does not poll or update its preview", _axis_reads == 0 and _button_reads == 0
		and setup._preview_labels.roll.text == before)
	screens.pop()
	_check("returning from calibration immediately refreshes the visible axes", setup._screen.visible
		and _axis_reads == 4 and _button_reads == 0 and setup._preview_labels.roll.text.contains("+0.75"))
	setup.visible = false
	_axis_value = 0.45
	_reset_reads()
	_preview_tick(setup)
	_check("hidden Controls layer does not poll", _axis_reads == 0 and _button_reads == 0)
	setup.visible = true
	_check("revealing the Controls layer immediately refreshes its current tab", _axis_reads == 4 and _button_reads == 0
		and setup._preview_labels.roll.text.contains("+0.45"))
	setup.select_section("buttons")
	var remap := setup.find_child("Remap_camera_cycle", true, false) as Button
	setup._start_capture("camera_cycle", remap)
	var pressed := InputEventJoypadButton.new()
	pressed.device = 5
	pressed.button_index = 100
	pressed.pressed = true
	setup._input(pressed)
	_check("capture still accepts the selected controller while preview polling is off", not setup._is_capture_active()
		and setup.current_profile().actions.get("camera_cycle", {}).get("button", -1) == 100)
	var released := pressed.duplicate() as InputEventJoypadButton
	released.pressed = false
	setup._input(released)
	_check("captured release is still consumed", setup._capture_release_tokens.is_empty())
	setup._start_capture("camera_previous", setup.find_child("Remap_camera_previous", true, false) as Button)
	registry.devices[0].connected = false
	registry.devices_changed.emit()
	_check("disconnect still cancels an active capture", not setup._is_capture_active()
		and setup.status_label.text.contains("disconnected"))
	registry.devices[0].connected = true
	registry.devices_changed.emit()
	setup.select_section("axes")
	var lost := RadioCalibration.new()
	var cancelled: Array[String] = []
	lost.cancelled.connect(func(reason: String) -> void: cancelled.append(reason))
	_check("second calibration starts while connected", lost.configure(registry, 5, setup.current_profile())
		and screens.push("radio_calibration", lost))
	registry.devices[0].connected = false
	_reset_reads()
	registry.devices_changed.emit()
	_check("disconnect still cancels covered calibration", cancelled.size() == 1 and not lost.connection_is_current())
	_reset_reads()
	screens.pop()
	_check("return after disconnect shows no stale axis or device polling", setup._preview_labels.roll.text.contains("—")
		and _axis_reads == 0 and _button_reads == 0)
	screens.pop()
	await _settle()
	host.free()

func _run() -> void:
	InputMap.load_from_project_settings()
	UiInput.set_gamepad(15)
	root.size = Vector2i(1280, 720)
	var registry := FixtureRegistry.new()
	var setup := ControllerSetup.new()
	setup.configure(registry, FixtureStore.new(), 15, 15)
	root.add_child(setup)
	await _settle()
	_check("first focus is the flight controller selector", setup.flight_device_picker.has_focus())
	var original: Dictionary = setup.current_profile()
	for locale in ["en", "es"]:
		TranslationServer.set_locale(locale)
		for section in ["devices", "profile", "axes", "aux", "buttons"]:
			setup.select_section(section, true)
			await _settle()
			var selected: Button = setup._section_buttons[section]
			_check("%s/%s selected section keeps the shared green marker on hover" % [locale, section],
				selected.button_pressed and selected.get_theme_stylebox("pressed").border_color == UiTheme.FOCUS
				and selected.get_theme_stylebox("hover_pressed").border_color == UiTheme.FOCUS)
			var view := Rect2(Vector2.ZERO, Vector2(root.size))
			var panel := setup._settings_panel.get_global_rect()
			var footer := (setup.find_child("ControllerSetupFooter", true, false) as Control).get_global_rect()
			var nav := (setup.find_child("ControllerSections", true, false) as Control).get_global_rect()
			_check("%s/%s panel and fixed controls fit 1280x720" % [locale, section], view.encloses(panel) and view.encloses(footer) and view.encloses(nav))
			_check("%s/%s focuses visible section content" % [locale, section], root.gui_get_focus_owner() != null and setup._section_pages[section].is_ancestor_of(root.gui_get_focus_owner()) and root.gui_get_focus_owner().is_visible_in_tree())
			for other in setup._section_pages:
				_check("%s/%s hidden section %s excludes focus" % [locale, section, other], setup._section_pages[other].visible == (section == other))
	_check("section changes retain the complete draft", setup.current_profile() == original)
	for dimensions in [Vector2i(960, 640), Vector2i(1920, 1080)]:
		root.size = dimensions
		for section in ["devices", "profile", "axes", "aux", "buttons"]:
			setup.select_section(section, true)
			await _settle()
			var view := Rect2(Vector2.ZERO, Vector2(root.size))
			_check("%s/%s keeps the panel and Save within the viewport" % [dimensions, section], view.encloses(setup._settings_panel.get_global_rect()) and view.encloses(setup.save_button.get_global_rect()))
		_check("%s axis layout adapts without squeezing preview values" % dimensions, setup._axis_columns.vertical == (dimensions.x < 1100))
	root.size = Vector2i(1920, 1080)
	setup.select_section("axes")
	await _settle()
	var preview_scroll := setup.find_child("ControllerSetupScroll", true, false) as ScrollContainer
	for channel: String in ["roll", "pitch", "yaw", "throttle"]:
		var value_label: Label = setup._preview_labels[channel]
		_check("1080p %s live value has readable width inside the panel" % channel,
			value_label.is_visible_in_tree() and value_label.size.x >= 300.0 and value_label.size.y >= 20.0
			and preview_scroll.get_global_rect().grow(1.0).encloses(value_label.get_global_rect()))
	root.size = Vector2i(1280, 720)
	setup.select_section("axes")
	await _settle()
	var scroll := setup.find_child("ControllerSetupScroll", true, false) as ScrollContainer
	_check("all four live meters fit beside their axis controls", scroll.get_global_rect().encloses(setup._preview_bars.throttle.get_global_rect()) and scroll.get_global_rect().encloses(setup._axis_controls.throttle.axis.get_global_rect()))
	_check("live preview names the mapped source axis", setup._preview_axis_labels.roll.text == "Eje %d" % int(original.roll.axis))
	var aux_preview_profile := original.duplicate(true)
	aux_preview_profile["aux"] = {
		"smoke": {"type": "axis", "axis": 4, "off": -1.0, "on": 1.0, "invert": false},
		"flaps": {"type": "button", "button": 20, "mode": "toggle_edge"},
		"gear": {"type": "button", "button": 21, "mode": "level"},
	}
	setup._set_draft_profile(aux_preview_profile)
	setup.select_section("aux")
	await _settle()
	_check("all three configured AUX editors fit at 1280x720 in Spanish", scroll.get_global_rect().encloses(setup._aux_controls.smoke.axis.get_global_rect()) and scroll.get_global_rect().encloses(setup._aux_controls.gear.button_mode.get_global_rect()))
	setup._set_draft_profile(original)
	setup.select_section("buttons")
	# Explicit UI membership catches a wrong category even when row counts agree.
	# Helicopter flight commands were added after the old 29-row fixture.
	var expected := [
		[],
		["restart_flight", "trim_left", "trim_right", "trim_up", "trim_down", "trim_yaw_left", "trim_yaw_right", "overlay_preset",
			"throttle_cut", "lights_cycle", "rates_toggle", "helicopter_arm", "helicopter_hold", "helicopter_mode", "helicopter_trainer"],
		["camera_cycle", "view_reset", "camera_previous", "camera_pilot", "camera_chase", "camera_orbit",
			"camera_zoom_in", "camera_zoom_out", "camera_auto_zoom"],
		["smoke_toggle", "flaps_up", "flaps_down", "flaps_cycle", "gear_toggle"],
		["accept", "back", "navigate_up", "navigate_down", "navigate_left", "navigate_right", "pause", "calibrate"],
	]
	for index in range(1, expected.size()):
		expected[0].append_array(expected[index])
	for index in expected.size():
		setup.action_filter.select(index)
		setup._on_action_filter_selected(index)
		var wanted := PackedStringArray(expected[index])
		wanted.sort()
		_check("category %d shows exactly the expected actions" % index, _visible_actions(setup) == wanted)
	_check("category filters preserve all bindings", setup.current_profile() == original)
	var remap := setup.find_child("Remap_camera_cycle", true, false) as Button
	setup._start_capture("camera_cycle", remap)
	_check("capture reveals a row hidden by the filter", remap.is_visible_in_tree() and setup.action_filter.selected == 0)
	await _settle()
	_check("listening status leaves Save accessible", Rect2(Vector2.ZERO, Vector2(root.size)).encloses(setup.save_button.get_global_rect()) and setup.status_label.visible)
	setup.select_section("aux")
	_check("switching sections cancels capture without changing bindings", setup._capturing_action.is_empty() and setup.current_profile() == original)
	setup._start_capture("camera_cycle", remap)
	setup.action_filter.select(3)
	setup._on_action_filter_selected(3)
	_check("changing the filter cancels capture", setup._capturing_action.is_empty())
	setup.select_section("devices")
	setup._section_buttons.devices.grab_focus()
	await _joy(JOY_BUTTON_DPAD_RIGHT, 16)
	_check("another controller cannot move section focus", setup._section_buttons.devices.has_focus())
	await _joy(JOY_BUTTON_DPAD_RIGHT)
	_check("selected gamepad moves to the next section button", setup._section_buttons.profile.has_focus())
	await _joy(JOY_BUTTON_A)
	_check("selected gamepad opens Profile", setup._selected_section == "profile" and setup._section_pages.profile.visible)
	await _joy(JOY_BUTTON_DPAD_DOWN)
	_check("D-pad enters visible profile controls", setup._section_pages.profile.is_ancestor_of(root.gui_get_focus_owner()))
	setup.select_section("buttons", true)
	for step in 15:
		if setup.save_button.has_focus(): break
		await _joy(JOY_BUTTON_DPAD_DOWN)
	_check("D-pad can reach pinned Save from the filtered action list", setup.save_button.has_focus())
	setup._set_status("Error: " + "A mapping needs attention. ".repeat(40), true)
	await _settle()
	_check("long validation feedback preserves the footer", Rect2(Vector2.ZERO, Vector2(root.size)).encloses(setup.save_button.get_global_rect()) and setup.status_label.tooltip_text.length() > 500)
	registry.devices.clear()
	registry.devices_changed.emit()
	setup.select_section("devices")
	await _settle()
	_check("empty-device guidance appears after disconnect", setup._empty_device_label.visible)
	_check("no flight commands or bindings were changed by navigation", setup.current_profile() == original)
	setup.free()
	UiInput.isolate_joypads()
	await _test_preview_lifecycle()
	print("Controller sections: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)

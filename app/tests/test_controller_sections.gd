extends SceneTree

const ControllerSetup := preload("res://ui/controller_setup.gd")
const ControllerProfile := preload("res://input/controller_profile.gd")
const ControllerActions := preload("res://input/controller_actions.gd")
const UiInput := preload("res://ui/ui_input.gd")

class FixtureRegistry extends RefCounted:
	signal devices_changed
	var devices: Array[Dictionary] = [{"id": 15, "name": "DualSense Wireless Controller with a deliberately long device name for layout verification", "kind": "gamepad", "known": true, "connected": true}]
	func get_devices() -> Array[Dictionary]: return devices.duplicate(true)
	func selected_device_id(_role: String) -> int: return 15

class FixtureStore extends RefCounted:
	func load_all() -> Dictionary: return {"ok": true, "profiles": [], "errors": []}
	func match_profile(_device: Dictionary, _devices: Array) -> Dictionary: return {}

var failures := 0
var checks := 0

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

func _visible_rows(setup: Node) -> int:
	var total := 0
	for index in ControllerActions.ACTIONS.size():
		if (setup.action_grid.get_child(3 + index * 3) as Control).visible:
			total += 1
	return total

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
	var expected := [29, 7, 9, 5, 8]
	for index in expected.size():
		setup.action_filter.select(index)
		setup._on_action_filter_selected(index)
		_check("category %d has the expected rows" % index, _visible_rows(setup) == expected[index])
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
	print("Controller sections: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)

extends SceneTree

const ControllerSetup := preload("res://ui/controller_setup.gd")
const ControllerActions := preload("res://input/controller_actions.gd")
const ControllerProfile := preload("res://input/controller_profile.gd")
const SmokeAux := preload("res://input/smoke_aux.gd")


class FakeRegistry extends RefCounted:
	signal devices_changed
	var devices: Array[Dictionary] = [
		{"id": 5, "name": "Aux test pad", "kind": "gamepad", "known": true, "connected": true},
	]
	var selections := {"flight": 5, "ui": -1}

	func get_devices() -> Array[Dictionary]:
		return devices.duplicate(true)

	func selected_device_id(role: String) -> int:
		return int(selections.get(role, -1))


class FakeStore extends RefCounted:
	func load_all() -> Dictionary:
		return {"ok": true, "profiles": [], "errors": []}

	func save_profile(candidate: Dictionary) -> Dictionary:
		return {"ok": false, "profile": {}, "error": "test save not expected"}

	func import_legacy_radio() -> Dictionary:
		return {"ok": true, "profiles": [], "errors": []}


var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var setup := ControllerSetup.new()
	setup.configure(FakeRegistry.new(), FakeStore.new(), 5, -1)
	root.add_child(setup)
	await process_frame
	await process_frame
	_test_clear_buttons(setup)
	_test_aux_mapping_editors(setup)
	_test_validation_feedback(setup)
	await _test_follow_focus(setup)
	setup.free()
	await process_frame
	print("all controller auxiliary setup checks passed" if failures == 0 else "%d controller auxiliary setup checks failed" % failures)
	quit(1 if failures > 0 else 0)


func _test_clear_buttons(setup) -> void:
	var back_clear := setup.find_child("Clear_back", true, false) as Button
	var pause_clear := setup.find_child("Clear_pause", true, false) as Button
	var optional_clear := setup.find_child("Clear_camera_previous", true, false) as Button
	_check("Back and Pause cannot be cleared", back_clear != null and back_clear.disabled and pause_clear != null and pause_clear.disabled)
	_check("unbound optional actions disable redundant Clear", optional_clear != null and optional_clear.disabled)
	setup._base_actions["camera_previous"] = {"type": "button", "button": JOY_BUTTON_MAX - 1}
	setup._draft_profile["actions"] = setup._base_actions.duplicate(true)
	setup._action_bindings = ControllerActions.effective_bindings(setup.current_profile())
	setup._update_action_controls()
	_check("assigned optional actions expose Clear", not optional_clear.disabled)
	setup.select_section("buttons")
	optional_clear.grab_focus()
	optional_clear.pressed.emit()
	_check("clearing a binding keeps gamepad focus on Remap and skips disabled Clear", optional_clear.focus_mode == Control.FOCUS_NONE and root.gui_get_focus_owner() == setup.find_child("Remap_camera_previous", true, false))
	var cleared: Dictionary = setup.current_profile()
	_check("Clear writes an explicit unbound action and passes profile binding validation", cleared.actions.camera_previous.type == "unbound" and ControllerActions.validate_profile_bindings(cleared).ok)


func _test_aux_mapping_editors(setup) -> void:
	_check("auxiliary help distinguishes input assignment from aircraft capability", setup.aux_help_label.text.contains("Availability depends on the selected aircraft") and setup.aux_help_label.text.contains("at least 0.5 travel"))
	var smoke_type := setup.find_child("AuxType_smoke", true, false) as OptionButton
	var smoke_axis := setup.find_child("AuxAxis_smoke", true, false) as SpinBox
	var smoke_off := setup.find_child("AuxOff_smoke", true, false) as SpinBox
	var smoke_on := setup.find_child("AuxOn_smoke", true, false) as SpinBox
	var smoke_invert := setup.find_child("AuxInvert_smoke", true, false) as CheckBox
	smoke_type.select(1)
	setup._on_aux_type_selected(1, "smoke")
	var profile: Dictionary = setup.current_profile()
	_check("Axis mode creates a valid unbound smoke input without colliding with AETR", profile.aux.smoke.type == "axis" and SmokeAux.valid_binding(profile.aux.smoke, SmokeAux.flight_axes(profile)))
	smoke_axis.value = 9.0
	smoke_off.value = 0.45
	smoke_on.value = -0.45
	profile = setup.current_profile()
	_check("Axis mapping supports axis 9, edited endpoints, and automatic inversion", profile.aux.smoke.axis == 9 and is_equal_approx(profile.aux.smoke.off, 0.45) and is_equal_approx(profile.aux.smoke.on, -0.45) and profile.aux.smoke.invert and SmokeAux.valid_binding(profile.aux.smoke, SmokeAux.flight_axes(profile)))
	smoke_invert.button_pressed = false
	profile = setup.current_profile()
	_check("Invert swaps axis endpoints and remains consistent with the runtime shape", not profile.aux.smoke.invert and profile.aux.smoke.off < profile.aux.smoke.on and SmokeAux.valid_binding(profile.aux.smoke, SmokeAux.flight_axes(profile)))
	setup._update_aux_preview()
	var smoke_preview := setup.find_child("AuxPreview_smoke", true, false) as Label
	_check("axis live preview identifies the selected auxiliary source axis", smoke_preview.text.contains("Axis 9") and smoke_preview.text.contains("request"))
	var flaps_type := setup.find_child("AuxType_flaps", true, false) as OptionButton
	flaps_type.select(1)
	setup._on_aux_type_selected(1, "flaps")
	profile = setup.current_profile()
	_check("Flaps axis picker allocates a source outside AETR and the smoke axis", profile.aux.flaps.type == "axis" and profile.aux.flaps.axis not in [profile.roll.axis, profile.pitch.axis, profile.yaw.axis, profile.throttle.axis, profile.aux.smoke.axis])
	var gear_type := setup.find_child("AuxType_gear", true, false) as OptionButton
	var gear_button := setup.find_child("AuxButton_gear", true, false) as SpinBox
	var gear_mode := setup.find_child("AuxButtonMode_gear", true, false) as OptionButton
	gear_type.select(2)
	setup._on_aux_type_selected(2, "gear")
	gear_button.value = float(SmokeAux.MAX_BUTTONS - 1)
	gear_mode.select(1)
	setup._on_aux_button_mode_selected(1, "gear")
	profile = setup.current_profile()
	_check("Gear button supports index 127 and toggle-on-press mode", profile.aux.gear.type == "button" and profile.aux.gear.button == SmokeAux.MAX_BUTTONS - 1 and profile.aux.gear.mode == "toggle_edge" and SmokeAux.valid_binding(profile.aux.gear))
	var gear_preview := setup.find_child("AuxPreview_gear", true, false) as Label
	_check("button live preview names the button, mode, and physical state", gear_preview.text.contains("Button 127") and gear_preview.text.contains("Toggle per press") and gear_preview.text.contains("Released"))
	gear_mode.select(0)
	setup._on_aux_button_mode_selected(0, "gear")
	profile = setup.current_profile()
	_check("button mode also supports maintained level behavior", profile.aux.gear.mode == "level" and SmokeAux.valid_binding(profile.aux.gear))
	gear_type.select(0)
	setup._on_aux_type_selected(0, "gear")
	smoke_type.select(0)
	setup._on_aux_type_selected(0, "smoke")
	profile = setup.current_profile()
	_check("Disabled cleanly removes optional channels from the draft", not profile.aux.has("smoke") and not profile.aux.has("gear") and profile.aux.has("flaps"))
	_check("draft auxiliary mappings pass the profile binding validator", ControllerActions.validate_profile_bindings(profile).ok)


func _test_follow_focus(setup) -> void:
	var target := setup.find_child("AuxType_gear", true, false) as Control
	var scroll := setup.find_child("ControllerSetupScroll", true, false) as ScrollContainer
	for _frame in 5:
		await process_frame
	setup.select_section("aux")
	await process_frame
	await process_frame
	target.grab_focus()
	await process_frame
	await process_frame
	var owner := get_root().gui_get_focus_owner()
	_check("auxiliary controls are reachable in their section with follow-focus", owner == target and target.is_visible_in_tree() and scroll.get_global_rect().intersects(target.get_global_rect()))


func _test_validation_feedback(setup) -> void:
	var invalid_profile: Dictionary = setup.current_profile()
	invalid_profile["aux"] = {
		"smoke": {"type": "axis", "axis": int(invalid_profile.roll.axis), "off": -1.0, "on": 1.0, "invert": false},
	}
	setup._set_draft_profile(invalid_profile)
	setup._save_profile()
	_check("Save explains when an AUX mapping overlaps a flight axis", setup.status_label.text.contains("aux.smoke is invalid or overlaps a flight axis"))

	var conflicting_profile: Dictionary = setup.current_profile()
	conflicting_profile["aux"] = {
		"smoke": {"type": "button", "button": JOY_BUTTON_RIGHT_STICK, "mode": "level"},
	}
	setup._set_draft_profile(conflicting_profile)
	setup._capturing_action = "camera_previous"
	var event := InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_RIGHT_STICK
	event.pressed = true
	setup._capture_binding(event)
	_check("Remap explains when an action conflicts with an AUX input", setup.status_label.text.contains("Action camera_previous conflicts with aux.smoke"))


func _check(label: String, condition: bool) -> void:
	if condition:
		print("ok   ", label)
	else:
		failures += 1
		printerr("FAIL ", label)

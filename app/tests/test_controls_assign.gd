extends SceneTree
# UI-15-UX-05/06: press-to-assign in controller_setup.gd. Flight-axis Detect (largest deviation, ambiguity, noise,
# inversion, throttle jitter, cancel paths, generation change), the capture overlay's lifecycle and timeout, conflict
# Swap / Replace / Cancel (atomic, disabled reasons), AUX "Move the control", search by input, reset scope, release
# consumption and the capture_finished / calibration_finished signals. Draft only: nothing is saved.

const ControllerSetup := preload("res://ui/controller_setup.gd")
const ControllerProfile := preload("res://input/controller_profile.gd")
const ControllerActions := preload("res://input/controller_actions.gd")

class FakeRegistry extends RefCounted:
	signal devices_changed
	var generation := 1
	var devices: Array[Dictionary] = [
		{"id": 7, "name": "Fixture pad", "raw_name": "Fixture pad", "kind": "gamepad", "known": true, "connected": true},
		{"id": 5, "name": "Fixture radio", "raw_name": "Fixture radio", "kind": "radio", "connected": true, "serial_number": "radio-5"},
	]
	func get_devices() -> Array[Dictionary]: return devices.duplicate(true)
	func selected_device_id(_role: String) -> int: return 7
	func device_for_id(id: int) -> Dictionary:
		for device in devices:
			if device.id == id: return device.duplicate(true)
		return {}
	func connection_generation(_id: int) -> int: return generation

class FakeStore extends RefCounted:
	var saved := 0
	func load_all() -> Dictionary: return {"ok": true, "profiles": [], "errors": []}
	func match_profile(_device: Dictionary, _devices: Array) -> Dictionary: return {}
	func save_profile(profile: Dictionary) -> Dictionary:
		saved += 1
		return {"ok": true, "profile": profile}

var checks := 0
var failures := 0
var raw := PackedFloat64Array()
var finished: Array = []
var calibrations: Array = []
var registry: FakeRegistry
var store: FakeStore

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, condition: bool, detail := "") -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label, " ", detail)

func _settle(frames := 3) -> void:
	for frame in frames:
		await process_frame

func _axis(_id: int, axis: int) -> float:
	return raw[axis] if axis >= 0 and axis < raw.size() else 0.0

func _button(_id: int, _button_index: int) -> bool:
	return false

func _open() -> Node:
	raw.resize(10)
	raw.fill(0.0)
	finished.clear()
	registry = FakeRegistry.new()
	store = FakeStore.new()
	var setup := ControllerSetup.new()
	setup.axis_preview_provider = _axis
	setup.button_preview_provider = _button
	setup.configure(registry, store, 7, 7)
	setup.capture_finished.connect(func(target: String, ok: bool, message: String) -> void: finished.append([target, ok, message]))
	setup.calibration_finished.connect(func(ok: bool, message: String) -> void: calibrations.append([ok, message]))
	root.add_child(setup)
	setup.set_process(false) # tests drive sampling and the countdown explicitly
	await _settle(5)
	return setup

func _close(setup: Node) -> void:
	setup.free()
	await process_frame

func _samples(setup: Node, count: int, delta := 0.1) -> void:
	for i in count:
		if setup._axis_detector == null:
			return
		setup._sample_axis_detect(delta)

func _with_actions(setup: Node, actions: Dictionary, aux: Dictionary = {}) -> void:
	var profile: Dictionary = setup.current_profile()
	profile["actions"] = actions
	if aux.is_empty():
		profile.erase("aux")
	else:
		profile["aux"] = aux
	setup._set_draft_profile(profile)

func _button_event(button: int, pressed: bool, device := 7) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = button as JoyButton
	event.pressed = pressed
	return event

func _key_event(key: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = pressed
	return event

func _dispatch(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame

func _run() -> void:
	TranslationServer.set_locale("en")
	root.size = Vector2i(1920, 1080)
	await _test_detection()
	await _test_detection_cancel_paths()
	await _test_overlay_and_timeout()
	await _test_conflicts()
	await _test_aux_move_the_control()
	await _test_search()
	await _test_reset()
	await _test_release_consumption()
	await _test_public_api_and_calibration_signals()
	print("Controls assign: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures > 0 else 0)


func _test_detection() -> void:
	var setup: Node = await _open()
	var before: Dictionary = setup.current_profile()
	_check("Flight axes rows offer Detect and keep the axis number in Advanced",
		(setup.find_child("AxisDetect_roll", true, false) as Button) != null and not setup._axis_controls.roll.axis.visible
		and setup.find_child("AxisSource_roll", true, false) != null)
	setup.axis_advanced_toggle.button_pressed = true
	_check("Advanced shows the axis SpinBoxes", setup._axis_controls.roll.axis.visible)
	setup.axis_advanced_toggle.button_pressed = false
	_check("Detect starts for a connected controller", setup.start_capture_for("axis:roll") and setup._detect_channel == "roll"
		and setup._selected_section == "axes" and setup._is_capture_active())
	_check("the Detect button keeps focus during detection", (setup._axis_detect_buttons.roll as Button).has_focus())
	# Noise under the direction threshold never leads and never ends detection.
	for i in 6:
		raw[6] = 0.05 if i % 2 == 0 else -0.05
		setup._sample_axis_detect(0.1)
	_check("a jittering axis neither wins nor ends detection", setup._axis_detector != null and setup._detect_preview_axis == -1)
	raw[6] = 0.0
	raw[4] = 0.9
	raw[5] = 0.15 # small sympathetic movement stays under the ambiguity threshold
	setup._sample_axis_detect(0.1)
	_check("the leading axis is previewed in the overlay and on the picture", setup._detect_preview_axis == 4
		and setup.capture_overlay.has_preview() and setup.workspace._capture_id == "axis:4")
	_check("nothing reaches the draft before the hold completes", setup.current_profile() == before)
	await _samples(setup, 3)
	var profile: Dictionary = setup.current_profile()
	_check("the largest deviation wins after the hold", int(profile.roll.axis) == 4 and not bool(profile.roll.invert), str(profile.roll))
	_check("detection reports success once", finished == [["axis:roll", true, ""]], str(finished))
	_check("the result is only a draft change", setup.has_unsaved_changes() and store.saved == 0)
	_check("the overlay closes and the picture highlight is released", not setup.capture_overlay.visible and setup.workspace._capture_id == "")
	raw[4] = 0.0
	raw[5] = 0.0
	# Inversion: pitch was asked to move BACK; the axis went negative.
	finished.clear()
	setup.start_capture_for("axis:pitch")
	raw[7] = -0.8
	await _samples(setup, 4)
	profile = setup.current_profile()
	_check("a detected axis that moved the other way is inverted", int(profile.pitch.axis) == 7 and bool(profile.pitch.invert), str(profile.pitch))
	_check("the inversion is explained", setup.status_label.text.contains("inverted"), setup.status_label.text)
	raw[7] = 0.0
	# Ambiguity: two axes past the sweep at once, and a second axis that moved earlier.
	before = setup.current_profile()
	finished.clear()
	setup.start_capture_for("axis:yaw")
	raw[8] = 0.8
	raw[9] = 0.8
	setup._sample_axis_detect(0.1)
	_check("two moving axes are rejected", not setup._is_capture_active() and setup.current_profile() == before
		and finished.size() == 1 and not finished[0][1] and str(finished[0][2]).contains("More than one axis"), str(finished))
	raw[8] = 0.0
	raw[9] = 0.0
	finished.clear()
	setup.start_capture_for("axis:yaw")
	raw[9] = 0.3
	setup._sample_axis_detect(0.1)
	raw[9] = 0.0
	raw[8] = 0.9
	await _samples(setup, 4)
	_check("an axis that moved during detection makes the result ambiguous", setup.current_profile() == before
		and finished.size() == 1 and not finished[0][1], str(finished))
	raw[8] = 0.0
	# A radio throttle jittering at its LOW endpoint never ends detection of another channel.
	raw[1] = -1.0
	finished.clear()
	setup.start_capture_for("axis:yaw")
	for i in 10:
		raw[1] = -1.0 if i % 2 == 0 else -0.96
		setup._sample_axis_detect(0.1)
	_check("throttle jitter at an endpoint keeps detection running", setup._axis_detector != null and finished.is_empty())
	raw[8] = 0.85
	await _samples(setup, 4)
	_check("detection then finishes on the moved stick", int(setup.current_profile().yaw.axis) == 8, str(setup.current_profile().yaw))
	raw[8] = 0.0
	# The throttle itself, held at FULL with jitter, completes.
	finished.clear()
	setup.start_capture_for("axis:throttle")
	for i in 4:
		raw[1] = 1.0 if i % 2 == 0 else 0.97
		setup._sample_axis_detect(0.1)
	_check("a throttle jittering at FULL is detected without inversion", int(setup.current_profile().throttle.axis) == 1
		and not bool(setup.current_profile().throttle.invert) and finished.size() == 1 and finished[0][1], str(finished))
	raw[1] = 0.0
	await _close(setup)


func _test_detection_cancel_paths() -> void:
	var setup: Node = await _open()
	var before: Dictionary = setup.current_profile()
	setup.start_capture_for("axis:roll")
	setup._input(_key_event(KEY_ESCAPE, true))
	_check("Escape cancels detection", not setup._is_capture_active() and setup.current_profile() == before
		and finished.size() == 1 and finished[0] == ["axis:roll", false, "Remapping cancelled."], str(finished))
	setup._input(_key_event(KEY_ESCAPE, false))
	_check("the Escape release is consumed", setup._capture_release_tokens.is_empty())
	finished.clear()
	setup.start_capture_for("axis:roll")
	setup._input(_button_event(JOY_BUTTON_B, true))
	_check("the profile's Back button cancels detection", not setup._is_capture_active() and finished.size() == 1 and not finished[0][1])
	_check("Back's release is pending consumption", setup._capture_release_tokens.size() == 1)
	setup._input(_button_event(JOY_BUTTON_B, false))
	_check("Back's release is consumed", setup._capture_release_tokens.is_empty())
	finished.clear()
	setup.start_capture_for("axis:roll")
	setup.select_section("buttons")
	_check("a section change cancels detection", not setup._is_capture_active() and finished.size() == 1 and not finished[0][1])
	finished.clear()
	setup.start_capture_for("axis:roll")
	setup.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check("focus loss cancels detection", not setup._is_capture_active() and finished.size() == 1
		and str(finished[0][2]).contains("lost focus"), str(finished))
	finished.clear()
	setup.start_capture_for("axis:roll")
	registry.generation = 2
	raw[4] = 0.9
	setup._sample_axis_detect(0.1)
	_check("a connection generation change cancels detection", not setup._is_capture_active()
		and setup.current_profile() == before and finished.size() == 1 and not finished[0][1], str(finished))
	raw[4] = 0.0
	finished.clear()
	setup.start_capture_for("axis:roll")
	registry.devices[0]["connected"] = false
	registry.devices_changed.emit()
	_check("device loss cancels detection", not setup._is_capture_active() and setup.current_profile() == before
		and finished.size() == 1 and str(finished[0][2]).contains("disconnected"), str(finished))
	_check("Detect cannot start without a connected controller", not setup.start_capture_for("axis:roll"))
	registry.devices[0]["connected"] = true
	registry.devices_changed.emit()
	await _close(setup)


func _test_overlay_and_timeout() -> void:
	var setup: Node = await _open()
	setup.select_section("buttons")
	await _settle()
	var remap := setup.find_child("Remap_camera_cycle", true, false) as Button
	_check("the overlay is hidden while idle", not setup.capture_overlay.visible)
	setup.start_capture_for("camera_cycle")
	_check("Remap shows the in-workspace overlay", setup.capture_overlay.is_capturing()
		and setup.capture_overlay.title_label.text == "Remap Cycle camera"
		and setup.capture_overlay.prompt_label.text.contains("Cycle camera"))
	_check("the overlay is part of the Controls screen, not a native window", setup._settings_panel.is_ancestor_of(setup.capture_overlay))
	_check("the cancel hint shows the Escape glyph", setup.capture_overlay.cancel_chips.get_child_count() >= 1)
	_check("the row keeps focus while listening", remap.has_focus())
	setup.capture_overlay.advance(3.0)
	_check("the countdown runs", absf(setup.capture_overlay.remaining() - (setup.CAPTURE_SECONDS - 3.0)) < 0.01)
	setup.capture_overlay.advance(setup.CAPTURE_SECONDS)
	_check("a timeout cancels the capture with a message", not setup._is_capture_active() and not setup.capture_overlay.visible
		and finished.size() == 1 and str(finished[0][2]).contains("No input"), str(finished))
	setup.capture_overlay.advance(20.0)
	_check("a finished countdown reports once", finished.size() == 1)
	finished.clear()
	setup.start_capture_for("camera_cycle")
	setup.capture_overlay.cancel_button.pressed.emit()
	_check("the pointer Cancel cancels", not setup._is_capture_active() and finished.size() == 1 and not finished[0][1])
	finished.clear()
	setup.start_capture_for("camera_cycle")
	setup.start_capture_for("view_reset")
	_check("a new capture ends the previous one with one report", finished.size() == 1 and finished[0][0] == "camera_cycle"
		and setup._capturing_action == "view_reset")
	setup._cancel_capture()
	await _close(setup)


func _test_conflicts() -> void:
	var setup: Node = await _open()
	setup.select_section("buttons")
	await _settle()
	_with_actions(setup, {"camera_cycle": {"type": "button", "button": 20}, "view_reset": {"type": "button", "button": 21}})
	var before: Dictionary = setup.current_profile()
	var remap := setup.find_child("Remap_camera_cycle", true, false) as Button
	setup.start_capture_for("camera_cycle")
	setup._input(_button_event(21, true))
	setup._input(_button_event(21, false))
	var overlay: Control = setup.capture_overlay
	_check("a conflicting press asks Swap / Replace / Cancel", overlay.is_conflict() and not setup._is_capture_active())
	_check("the question names the other action", overlay.prompt_label.text.contains("Reset view"), overlay.prompt_label.text)
	_check("nothing changes while the question is open", setup.current_profile() == before)
	_check("Cancel is focused and focus stays inside the choices", overlay.conflict_cancel_button.has_focus()
		and overlay.conflict_cancel_button.focus_neighbor_bottom == overlay.conflict_cancel_button.get_path_to(overlay.conflict_cancel_button))
	_check("Save waits for the answer", not setup._save_profile(false) and store.saved == 0)
	_check("no capture report before the answer", finished.is_empty())
	overlay.swap_button.pressed.emit()
	var profile: Dictionary = setup.current_profile()
	_check("Swap exchanges both bindings atomically", int(profile.actions.camera_cycle.button) == 21 and int(profile.actions.view_reset.button) == 20
		and ControllerActions.validate_profile_bindings(profile).ok, str(profile.actions))
	_check("Swap reports success once and returns focus to the row", finished == [["camera_cycle", true, ""]] and remap.has_focus(), str(finished))
	_with_actions(setup, {"camera_cycle": {"type": "button", "button": 20}, "view_reset": {"type": "button", "button": 21}})
	finished.clear()
	setup.start_capture_for("camera_cycle")
	setup._input(_button_event(21, true))
	setup._input(_button_event(21, false))
	overlay.replace_button.pressed.emit()
	profile = setup.current_profile()
	_check("Replace leaves the other action without a control", int(profile.actions.camera_cycle.button) == 21
		and str(profile.actions.view_reset.type) == "unbound" and finished.size() == 1 and finished[0][1])
	_with_actions(setup, {"camera_cycle": {"type": "button", "button": 20}, "view_reset": {"type": "button", "button": 21}})
	before = setup.current_profile()
	finished.clear()
	setup.start_capture_for("camera_cycle")
	setup._input(_button_event(21, true))
	setup._input(_button_event(21, false))
	overlay.conflict_cancel_button.pressed.emit()
	_check("Cancel keeps the draft and reports the attempt", setup.current_profile() == before and finished.size() == 1
		and not finished[0][1] and str(finished[0][2]).contains("Binding was not changed"), str(finished))
	_check("Cancel restores the former rejection feedback", setup.status_label.text.contains("Binding was not changed") and remap.has_focus())
	# Back/Pause keep a control: Replace is disabled with a reason; Swap without a previous control is disabled too.
	_with_actions(setup, {"camera_cycle": {"type": "unbound"}, "pause": {"type": "button", "button": 22}})
	before = setup.current_profile()
	finished.clear()
	setup.start_capture_for("camera_cycle")
	setup._input(_button_event(22, true))
	setup._input(_button_event(22, false))
	_check("Replace is disabled for Pause with its reason", overlay.is_conflict() and overlay.replace_button.disabled
		and overlay.replace_button.tooltip_text.contains("must always keep a control"), overlay.replace_button.tooltip_text)
	_check("Swap is disabled when the action has nothing to give", overlay.swap_button.disabled
		and overlay.swap_button.tooltip_text.contains("no control to give"), overlay.swap_button.tooltip_text)
	_check("disabled choices list their reasons and only Cancel takes focus", overlay.conflict_reasons.visible
		and overlay.swap_button.focus_mode == Control.FOCUS_NONE and overlay.replace_button.focus_mode == Control.FOCUS_NONE)
	overlay.replace_button.pressed.emit()
	_check("a disabled choice cannot be taken", overlay.is_conflict() and setup.current_profile() == before)
	setup.request_close() # Back / Escape answers Cancel without closing Controls
	_check("Back answers the question with Cancel", not overlay.visible and setup.current_profile() == before
		and finished.size() == 1 and not finished[0][1])
	# Swap with an extra channel: the AUX button takes the action's previous button.
	_with_actions(setup, {"camera_previous": {"type": "button", "button": 23}}, {"smoke": {"type": "button", "button": 15, "mode": "level"}})
	finished.clear()
	setup.start_capture_for("camera_previous")
	setup._input(_button_event(15, true))
	setup._input(_button_event(15, false))
	_check("an extra channel conflict is offered by name", overlay.is_conflict() and overlay.prompt_label.text.contains("Smoke"))
	overlay.swap_button.pressed.emit()
	profile = setup.current_profile()
	_check("Swap with an extra channel moves its button atomically", int(profile.actions.camera_previous.button) == 15
		and int(profile.aux.smoke.button) == 23 and ControllerActions.validate_profile_bindings(profile).ok, str(profile))
	_with_actions(setup, {"camera_previous": {"type": "button", "button": 23}}, {"smoke": {"type": "button", "button": 15, "mode": "level"}})
	setup.start_capture_for("camera_previous")
	setup._input(_button_event(15, true))
	setup._input(_button_event(15, false))
	overlay.replace_button.pressed.emit()
	profile = setup.current_profile()
	_check("Replace removes the extra channel's assignment", int(profile.actions.camera_previous.button) == 15 and not profile.get("aux", {}).has("smoke"), str(profile))
	# Flight axes: Swap exchanges the two channels' axes; Replace is not possible.
	setup.select_section("axes")
	var roll_axis := int(setup.current_profile().roll.axis)
	var pitch_axis := int(setup.current_profile().pitch.axis)
	finished.clear()
	setup.start_capture_for("axis:roll")
	raw[pitch_axis] = 0.9
	await _samples(setup, 4)
	raw[pitch_axis] = 0.0
	_check("Detect on another channel's axis asks", overlay.is_conflict() and overlay.replace_button.disabled
		and overlay.replace_button.tooltip_text.contains("own axis"), overlay.replace_button.tooltip_text)
	overlay.swap_button.pressed.emit()
	profile = setup.current_profile()
	_check("Swap exchanges the flight channels' axes", int(profile.roll.axis) == pitch_axis and int(profile.pitch.axis) == roll_axis
		and finished == [["axis:roll", true, ""]], str([profile.roll.axis, profile.pitch.axis, finished]))
	await _close(setup)


func _test_aux_move_the_control() -> void:
	var setup: Node = await _open()
	var profile: Dictionary = setup.current_profile()
	profile["aux"] = {"smoke": {"type": "axis", "axis": 6, "off": -1.0, "on": 1.0, "invert": false}}
	setup._set_draft_profile(profile)
	setup.select_section("aux")
	await _settle()
	_check("Extra channels offer Move the control and keep endpoints in Advanced",
		setup._aux_controls.smoke.detect.is_visible_in_tree() and not setup._aux_controls.smoke.off.is_visible_in_tree())
	raw[5] = -1.0
	_check("Move the control starts with an OFF confirmation", setup.start_capture_for("aux:smoke")
		and setup._axis_capture_dialog != null and setup.capture_overlay.is_capturing())
	_check("the OFF step is confirmed in the overlay, not a native window", not setup._axis_capture_dialog.visible
		and setup.capture_overlay.confirm_button.visible and setup.capture_overlay.confirm_button.has_focus())
	setup.capture_overlay.advance(20.0)
	_check("the countdown waits for the OFF confirmation", setup._is_capture_active())
	setup.capture_overlay.confirm_button.pressed.emit()
	_check("after OFF the row's button has focus again", not setup.capture_overlay.confirm_button.visible
		and (setup._aux_controls.smoke.detect as Button).has_focus())
	raw[5] = 1.0
	for i in 3:
		if setup._axis_capture != null: setup._sample_axis_capture(0.1)
	_check("the overlay asks to return to OFF", setup.capture_overlay.prompt_label.text.contains("OFF"))
	raw[5] = -1.0
	for i in 3:
		if setup._axis_capture != null: setup._sample_axis_capture(0.1)
	var smoke: Dictionary = setup.current_profile().aux.smoke
	_check("the channel gets the moved axis and its measured endpoints", int(smoke.axis) == 5 and is_equal_approx(float(smoke.off), -1.0)
		and is_equal_approx(float(smoke.on), 1.0) and not bool(smoke.invert), str(smoke))
	_check("Move the control reports success", finished.size() == 1 and finished[0] == ["aux:smoke", true, ""], str(finished))
	finished.clear()
	setup.start_capture_for("aux:smoke")
	setup._axis_capture_dialog.canceled.emit()
	_check("cancelling the OFF confirmation reports once", not setup._is_capture_active() and finished.size() == 1 and not finished[0][1])
	_check("a button-type channel has no capture slot", not setup.start_capture_for("aux:flaps"))
	await _close(setup)


func _test_search() -> void:
	var setup: Node = await _open()
	_with_actions(setup, {"camera_cycle": {"type": "button", "button": 20}, "helicopter_arm": {"type": "button", "button": 24}},
		{"smoke": {"type": "button", "button": 15, "mode": "level"}})
	setup.set_process(true) # the found row follows focus through the screen's layout pass
	await _settle(4) # let the screen's initial focus pass run first
	setup.select_section("buttons")
	await _settle()
	_check("Buttons offers Find control", setup.find_actions_button.is_visible_in_tree())
	setup.find_actions_button.pressed.emit()
	_check("Find listens through the capture overlay", setup._finding and setup.capture_overlay.is_capturing())
	setup._input(_button_event(20, true))
	setup._input(_button_event(20, false))
	await _settle()
	var remap := setup.find_child("Remap_camera_cycle", true, false) as Button
	_check("a found action row is focused and named", remap.has_focus() and setup.status_label.text.contains("Cycle camera")
		and finished == [["find", true, ""]], str([setup.status_label.text, finished]))
	setup.action_filter.select(2) # Camera
	setup._on_action_filter_selected(2)
	finished.clear()
	setup.start_capture_for("find")
	setup._input(_button_event(24, true))
	setup._input(_button_event(24, false))
	await _settle()
	var heli := setup.find_child("Remap_helicopter_arm", true, false) as Button
	_check("another vehicle's row is revealed and focused", setup.show_all_vehicle_actions.button_pressed and setup.action_filter.selected == 0
		and heli.is_visible_in_tree() and heli.has_focus())
	var scroll := setup.find_child("ControllerSetupScroll", true, false) as ScrollContainer
	_check("the found row is scrolled into view", scroll.get_global_rect().grow(1.0).encloses(heli.get_global_rect()),
		str([scroll.get_global_rect(), heli.get_global_rect()]))
	finished.clear()
	setup.start_capture_for("find")
	setup._input(_button_event(30, true))
	setup._input(_button_event(30, false))
	_check("an unassigned control says so", finished.size() == 1 and not finished[0][1] and str(finished[0][2]).contains("not assigned"), str(finished))
	setup.select_section("aux")
	await _settle()
	finished.clear()
	setup.find_aux_button.pressed.emit()
	setup._input(_button_event(15, true))
	setup._input(_button_event(15, false))
	await _settle()
	_check("from Extra channels the AUX row is found first", setup._selected_section == "aux"
		and (setup._aux_controls.smoke.type as Control).has_focus() and finished == [["find", true, ""]], str(finished))
	setup.select_section("buttons")
	finished.clear()
	setup.start_capture_for("find")
	var motion := InputEventJoypadMotion.new()
	motion.device = 7
	motion.axis = int(setup.current_profile().roll.axis) as JoyAxis
	motion.axis_value = 0.9
	setup._input(motion)
	await _settle()
	_check("moving a flight stick finds its channel", setup._selected_section == "axes"
		and (setup._axis_detect_buttons.roll as Control).has_focus(), str(setup._selected_section))
	motion.axis_value = 0.0
	setup._input(motion)
	_check("the stick's return is consumed", setup._capture_release_tokens.is_empty())
	await _close(setup)


func _test_reset() -> void:
	var setup: Node = await _open()
	_with_actions(setup, {"camera_cycle": {"type": "button", "button": 20}, "accept": {"type": "button", "button": 21},
		"trim_left": {"type": "button", "button": 22}})
	setup.select_section("buttons")
	await _settle()
	setup.action_filter.select(2) # Camera
	setup._on_action_filter_selected(2)
	_check("the category reset names the category", setup.reset_category_button.visible and setup.reset_category_button.text == "Reset Camera")
	setup.reset_category_button.pressed.emit()
	_check("reset asks first", setup.reset_dialog != null and setup.reset_dialog.visible
		and setup.current_profile().actions.has("camera_cycle"))
	setup.reset_dialog.confirmed.emit()
	var actions: Dictionary = setup.current_profile().actions
	_check("a category reset restores only that category", not actions.has("camera_cycle") and int(actions.accept.button) == 21
		and int(actions.trim_left.button) == 22, str(actions))
	_check("the default control is back for the reset row", int(setup._action_bindings.camera_cycle.button) == JOY_BUTTON_Y)
	setup.action_filter.select(0)
	setup._on_action_filter_selected(0)
	_check("All has no separate category reset", not setup.reset_category_button.visible)
	_check("reset all restores every action", setup.reset_actions(0) and setup.current_profile().actions.is_empty())
	_check("Back and Pause keep a control after reset", str(setup._action_bindings.back.type) != "unbound"
		and str(setup._action_bindings.pause.type) != "unbound")
	_check("reset stays in the draft", setup.has_unsaved_changes() and store.saved == 0)
	# A radio resets to the safe radio map and keeps its navigation lock.
	var radio := ControllerProfile.defaults("radio", "radio_custom")
	radio["actions"] = {"camera_cycle": {"type": "button", "button": 9}}
	setup._set_draft_profile(radio)
	_check("a radio resets to the safe radio map", setup.reset_actions(0)
		and int(setup.current_profile().actions.back.physical_keycode) == KEY_BACKSPACE
		and int(setup.current_profile().actions.pause.physical_keycode) == KEY_ESCAPE
		and str(setup.current_profile().actions.camera_cycle.type) == "unbound", str(setup.current_profile().actions))
	await _close(setup)


func _test_release_consumption() -> void:
	var setup: Node = await _open()
	setup.set_process(true)
	await _settle(4) # let the screen's initial focus pass run first
	_with_actions(setup, {"camera_cycle": {"type": "button", "button": 20}, "view_reset": {"type": "button", "button": 21},
		"overlay_preset": {"type": "key", "physical_keycode": KEY_ENTER}})
	setup.select_section("buttons")
	await _settle()
	var remap := setup.find_child("Remap_camera_cycle", true, false) as Button
	remap.grab_focus()
	setup.start_capture_for("camera_cycle")
	# The confirming press opens the question; neither it nor its release may activate the focused Cancel.
	await _dispatch(_button_event(21, true))
	_check("the confirming press opens the question", setup.capture_overlay.is_conflict())
	await _dispatch(_button_event(21, false))
	_check("its release never activates the focused choice", setup.capture_overlay.is_conflict() and finished.is_empty())
	await _dispatch(_key_event(KEY_ESCAPE, true))
	await _dispatch(_key_event(KEY_ESCAPE, false))
	_check("Escape answers Cancel and its release is consumed", not setup.capture_overlay.visible
		and setup._capture_release_tokens.is_empty() and finished.size() == 1)
	# Find with the keyboard's accept key: the found row's Remap must not start a capture.
	finished.clear()
	setup.start_capture_for("find")
	await _dispatch(_key_event(KEY_ENTER, true))
	await _dispatch(_key_event(KEY_ENTER, false))
	var found := setup.find_child("Remap_overlay_preset", true, false) as Button
	_check("the find key press never activates the focused row", found.has_focus() and not setup._is_capture_active()
		and finished == [["find", true, ""]], str(finished))
	await _close(setup)


func _test_public_api_and_calibration_signals() -> void:
	var setup: Node = await _open()
	_check("an unknown target cannot start", not setup.start_capture_for("no_such_action"))
	_check("an action target starts Remap", setup.start_capture_for("restart_flight") and setup._capturing_action == "restart_flight")
	setup._cancel_capture()
	calibrations.clear()
	_check("a calibration for another controller is refused", not setup.apply_calibration_draft({}, 5, 1))
	_check("calibration_finished reports the refusal", calibrations.size() == 1 and not calibrations[0][0]
		and str(calibrations[0][1]).contains("connection changed"), str(calibrations))
	setup.calibration_cancelled("Calibration cancelled. The draft is unchanged.")
	_check("calibration_cancelled sets the status and reports", setup.status_label.text == "Calibration cancelled. The draft is unchanged."
		and calibrations.size() == 2 and calibrations[1] == [false, "Calibration cancelled. The draft is unchanged."])
	# A radio: navigation rows stay locked to the calibrated sticks.
	var radio := ControllerProfile.defaults("radio", "radio_custom")
	setup._set_draft_profile(radio)
	_check("a locked radio navigation row cannot start", not setup.start_capture_for("navigate_up"))
	# The Keyboard is read-only.
	(setup.workspace.card_for(-1) as Button).pressed.emit()
	await _settle()
	_check("the Keyboard has nothing to capture", not setup.start_capture_for("camera_cycle") and not setup.start_capture_for("find"))
	await _close(setup)

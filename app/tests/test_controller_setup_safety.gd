extends SceneTree

const ControllerSetup := preload("res://ui/controller_setup.gd")
const ControllerProfile := preload("res://input/controller_profile.gd")
const ControllerActions := preload("res://input/controller_actions.gd")
const UiInput := preload("res://ui/ui_input.gd")

class FakeRegistry extends RefCounted:
	signal devices_changed
	var devices: Array[Dictionary] = []
	var selected := {"flight": 15, "ui": 16}
	func get_devices() -> Array[Dictionary]:
		return devices.duplicate(true)
	func selected_device_id(role: String) -> int:
		return int(selected.get(role, -1))

class FakeStore extends RefCounted:
	var profiles: Array[Dictionary] = []
	var saved: Array[Dictionary] = []
	var recovery_errors: Array[String] = []
	func load_all() -> Dictionary:
		return {"ok": true, "profiles": profiles.duplicate(true), "errors": recovery_errors.duplicate()}
	func match_profile(_device: Dictionary, _devices: Array) -> Dictionary:
		return {}
	func save_profile(profile: Dictionary) -> Dictionary:
		saved.append(profile.duplicate(true))
		return {"ok": true, "profile": profile.duplicate(true)}

class InputProbe extends Node:
	var releases: Array[String] = []
	var close_count := 0
	var saved_count := 0
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and not (event as InputEventKey).pressed:
			releases.append("key:%d" % (event as InputEventKey).physical_keycode)
		elif event is InputEventJoypadButton and not (event as InputEventJoypadButton).pressed:
			releases.append("button:%d:%d" % [event.device, event.button_index])
		elif event is InputEventJoypadMotion:
			releases.append("axis:%d:%+.2f" % [event.device, (event as InputEventJoypadMotion).axis_value])
	func on_closed() -> void:
		close_count += 1
	func on_saved(_profile: Dictionary) -> void:
		saved_count += 1

var failures := 0
var registry: FakeRegistry
var store: FakeStore
var rejection_calls := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("ok   ", label)
	else:
		failures += 1
		printerr("FAIL ", label, " ", detail)

func _new_setup() -> ControllerSetup:
	var profile_a := ControllerProfile.defaults("gamepad", "mode2")
	profile_a["name"] = "Profile A"
	var profile_b := ControllerProfile.defaults("gamepad", "mode1")
	profile_b["name"] = "Profile B"
	store = FakeStore.new()
	store.profiles = [profile_a, profile_b]
	registry = FakeRegistry.new()
	registry.devices = [
		{"id": 15, "name": "Flight A", "kind": "gamepad", "known": true, "connected": true, "profile_id": profile_a.profile_id},
		{"id": 16, "name": "Flight B", "kind": "gamepad", "known": true, "connected": true, "profile_id": profile_b.profile_id},
	]
	var setup := ControllerSetup.new()
	setup.configure(registry, store, 15, 16)
	root.add_child(setup)
	await process_frame
	await process_frame
	return setup

func _button_event(device: int, button: JoyButton, pressed: bool) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = button
	event.pressed = pressed
	return event

func _key_event(key: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	return event

func _key_event_with_codes(physical_key: Key, logical_key: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = logical_key
	event.physical_keycode = physical_key
	event.pressed = pressed
	return event

func _axis_event(device: int, axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = axis
	event.axis_value = value
	return event

func _dispatch(event: InputEvent) -> void:
	Input.parse_input_event(event)
	await process_frame
	await process_frame

func _item_index(picker: OptionButton, item_id: int) -> int:
	for index in picker.item_count:
		if picker.get_item_id(index) == item_id:
			return index
	return -1

func _reject_save(_candidate: Dictionary, _flight_device_id: int, _ui_device_id: int) -> Dictionary:
	rejection_calls += 1
	return {"ok": false, "error": "unsupported aircraft"}

func _run() -> void:
	InputMap.load_from_project_settings()
	UiInput.isolate_joypads()
	var probe := InputProbe.new()
	root.add_child(probe)
	var setup := await _new_setup()
	store.recovery_errors = ["Recovered from rollback"]
	setup._load_profiles()
	_check("successful recovery still displays its warning", setup.status_label.text.contains("Recovered from rollback"))
	store.recovery_errors.clear()
	setup.close_requested.connect(probe.on_closed)
	setup.profile_saved.connect(probe.on_saved)
	await process_frame
	_check("initial focus lands on the flight controller choice", setup.flight_device_picker.has_focus(), str(root.gui_get_focus_owner()))
	var remap := setup.find_child("Remap_accept", true, false) as Button
	setup._start_capture("accept", remap)
	await _dispatch(_button_event(15, JOY_BUTTON_X, true))
	_check("captured joypad press does not escape to unhandled input", probe.releases.is_empty(), str(probe.releases))
	await _dispatch(_button_event(15, JOY_BUTTON_X, false))
	_check("matching joypad release is consumed after capture ends", probe.releases.is_empty(), str(probe.releases))

	setup._start_capture("camera_cycle", remap)
	await _dispatch(_key_event(KEY_Q, true))
	await _dispatch(_key_event(KEY_Q, false))
	_check("matching keyboard release is consumed after capture ends", probe.releases.is_empty(), str(probe.releases))
	setup._start_capture("camera_cycle", remap)
	var physical_press := _key_event_with_codes(KEY_Q, KEY_Q, true)
	var layout_changed_release := _key_event_with_codes(KEY_Q, KEY_A, false)
	setup._input(physical_press)
	setup._input(layout_changed_release)
	_check("matching release stays consumed when the logical keycode changes",
		setup._event_release_token(physical_press) == setup._event_release_token(layout_changed_release)
		and not setup._capture_release_tokens.has(setup._event_release_token(physical_press)))
	setup._start_capture("camera_cycle", remap)
	await _dispatch(_axis_event(15, JOY_AXIS_TRIGGER_RIGHT, 0.8))
	await _dispatch(_axis_event(15, JOY_AXIS_TRIGGER_RIGHT, 0.0))
	_check("captured axis stays consumed until it returns to neutral", probe.releases.is_empty(), str(probe.releases))

	setup._start_capture("camera_cycle", remap)
	await _dispatch(_key_event(KEY_ESCAPE, true))
	_check("Escape cancels remapping without closing the screen", str(setup._capturing_action).is_empty() and probe.close_count == 0)
	await _dispatch(_key_event(KEY_ESCAPE, false))
	_check("Escape release stays inside remapping recovery", probe.releases.is_empty(), str(probe.releases))

	setup._start_capture("accept", remap)
	var second_device_index := _item_index(setup.flight_device_picker, 16)
	setup._on_flight_device_selected(second_device_index)
	_check("changing flight controller cancels its pending capture", str(setup._capturing_action).is_empty(), str(setup._capturing_action))
	await _dispatch(_button_event(16, JOY_BUTTON_Y, true))
	_check("new device cannot finish capture started for the old device", not setup._base_actions.has("accept"), str(setup._base_actions))

	var first_device_index := _item_index(setup.flight_device_picker, 15)
	setup._on_flight_device_selected(first_device_index)
	setup._on_axis_changed(8.0, "roll", "axis")
	setup.profile_name_edit.text = "Unsaved A"
	var profile_b_index := _item_index(setup.profile_picker, 1)
	setup._on_profile_selected(profile_b_index)
	var profile_a_index := _item_index(setup.profile_picker, 0)
	setup._on_profile_selected(profile_a_index)
	_check("switching profiles preserves unsaved channel edits", int(setup.current_profile().roll.axis) == 8, str(setup.current_profile().roll))
	_check("switching profiles preserves unsaved name edits", setup.profile_name_edit.text == "Unsaved A", setup.profile_name_edit.text)
	setup._on_flight_device_selected(second_device_index)
	setup._on_flight_device_selected(first_device_index)
	_check("switching devices preserves unsaved channel edits", int(setup.current_profile().roll.axis) == 8, str(setup.current_profile().roll))
	_check("switching devices preserves unsaved name edits", setup.profile_name_edit.text == "Unsaved A", setup.profile_name_edit.text)

	var aux_profile := ControllerProfile.defaults("gamepad", "mode2")
	aux_profile["aux"] = {"smoke": {"type": "button", "button": JOY_BUTTON_DPAD_LEFT, "mode": "level"}}
	var inherited := ControllerActions.effective_bindings(aux_profile)
	_check("AUX suppresses only a colliding inherited flight action", str(inherited.trim_left.type) == "unbound", str(inherited.trim_left))
	aux_profile["actions"] = {"trim_left": {"type": "button", "button": JOY_BUTTON_DPAD_LEFT}}
	var explicit := ControllerActions.effective_bindings(aux_profile)
	var explicit_validation := ControllerActions.validate_profile_bindings(aux_profile)
	_check("explicit action remains visible and is rejected on AUX conflict",
		str(explicit.trim_left.type) == "button" and not bool(explicit_validation.ok), str(explicit_validation.errors))

	setup._start_capture("accept", remap)
	registry.devices[0]["connected"] = false
	registry.devices_changed.emit()
	_check("disconnecting the captured controller cancels remapping", str(setup._capturing_action).is_empty(), str(setup._capturing_action))
	registry.devices[0]["connected"] = true
	registry.devices_changed.emit()

	setup.save_and_apply = Callable(self, "_reject_save")
	setup.profile_name_edit.text = "Unsaved A"
	setup._save_profile()
	_check("runtime rejection leaves profile setup open", rejection_calls == 1 and probe.close_count == 0 and probe.saved_count == 0)
	_check("runtime rejection does not fall through to storage", store.saved.is_empty(), str(store.saved.size()))
	_check("runtime rejection preserves the editable draft", setup.profile_name_edit.text == "Unsaved A", setup.profile_name_edit.text)

	setup.select_section("profile")
	setup.preset_picker.grab_focus()
	setup.preset_picker.show_popup()
	await process_frame
	_check("gamepad preset popup is open while focused", setup.preset_picker.get_popup().visible)
	await _dispatch(_key_event(KEY_ESCAPE, true))
	_check("Escape dismisses the focused option popup without closing setup",
		not setup.preset_picker.get_popup().visible and probe.close_count == 0)
	await _dispatch(_key_event(KEY_ESCAPE, false))

	setup._start_capture("accept", remap)
	setup._save_profile()
	_check("Save does not persist an in-progress remap", rejection_calls == 1 and store.saved.is_empty() and not str(setup._capturing_action).is_empty())
	var cancel_button := setup.find_child("Cancel", true, false) as Button
	cancel_button.pressed.emit()
	_check("Cancel exits and discards while capture is active", str(setup._capturing_action).is_empty() and probe.close_count == 1 and store.saved.is_empty())

	setup.queue_free()
	probe.queue_free()
	await process_frame
	print("controller setup audit passed" if failures == 0 else "%d controller setup audit checks failed" % failures)
	quit(1 if failures > 0 else 0)

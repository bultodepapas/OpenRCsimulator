extends SceneTree
# UI-15-UX-07: the Setup assistant wired into controller_setup.gd through setup_assistant_bridge.gd. Opening keeps
# the Controls screen inactive, the bridge edits only the draft (kind, preset, Reverse, bindings), a capture started
# by the assistant shows the screen's own overlay and reports back, calibration results reach the assistant, Back
# steps the assistant, Cancel restores the draft and Save uses the transactional Save. Nothing touches real devices.

const ControllerSetup := preload("res://ui/controller_setup.gd")
const ControllerProfile := preload("res://input/controller_profile.gd")

class FakeRegistry extends RefCounted:
	signal devices_changed
	var generation := 1
	var devices: Array[Dictionary] = [
		{"id": 7, "name": "Fixture pad", "raw_name": "Fixture pad", "kind": "gamepad", "known": true, "connected": true, "guid": "pad"},
		{"id": 5, "name": "Fixture radio", "raw_name": "Fixture radio", "kind": "radio", "connected": true, "guid": "radio"},
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
var calibration_requests := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, condition: bool, detail := "") -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label, " ", detail)
	else:
		print("ok   ", label)


func _settle(frames := 3) -> void:
	for frame in frames:
		await process_frame


func _axis(_id: int, axis: int) -> float:
	return raw[axis] if axis >= 0 and axis < raw.size() else 0.0


func _button(_id: int, button: int) -> bool:
	return button == 3


func _open(device_id := 7) -> Node:
	raw.resize(10)
	raw.fill(0.0)
	var setup := ControllerSetup.new()
	setup.axis_preview_provider = _axis
	setup.button_preview_provider = _button
	setup.configure(FakeRegistry.new(), FakeStore.new(), device_id, 7)
	setup.calibration_requested.connect(func() -> void: calibration_requests += 1)
	root.add_child(setup)
	await _settle(5)
	return setup


func _run() -> void:
	TranslationServer.set_locale("en")
	root.size = Vector2i(1920, 1080)
	await _test_open_and_cancel()
	await _test_bridge_edits()
	await _test_capture_round_trip()
	await _test_calibration_round_trip()
	await _test_save()
	await _test_review_findings()
	print("setup assistant wiring: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _test_open_and_cancel() -> void:
	var setup := await _open()
	var button: Button = setup.setup_assistant_button
	_check("the Devices page offers Set up this device for a connected controller", button != null and button.visible and not button.disabled)
	var before: Dictionary = setup.current_profile()
	_check("opening the assistant succeeds", setup.open_setup_assistant())
	await _settle()
	_check("a second open is refused while one is open", not setup.open_setup_assistant())
	_check("the Controls surface is inactive under the assistant", not setup._screen.visible)
	var assistant: CanvasLayer = setup._assistant
	_check("the assistant is mounted above Controls", is_instance_valid(assistant) and assistant.layer > setup.layer)
	setup._assistant_bridge.set_channel_inverted("roll", not bool(before.roll.get("invert", false)))
	_check("a bridge edit changes the draft", bool(setup.current_profile().roll.invert) != bool(before.roll.get("invert", false)))
	setup.request_close() # Back on the first step cancels the assistant
	await _settle()
	_check("Back on the first step closes the assistant", not is_instance_valid(setup._assistant))
	_check("cancelling restores the draft as it was", setup.current_profile() == before, str(setup.current_profile().roll))
	_check("the Controls surface is active again", setup._screen.visible)
	_check("focus returns to Set up this device", setup.get_viewport().gui_get_focus_owner() == button)
	setup.free()
	await process_frame


func _test_bridge_edits() -> void:
	var setup := await _open()
	setup.open_setup_assistant()
	await _settle()
	var bridge: RefCounted = setup._assistant_bridge
	var info: Dictionary = bridge.device_info()
	_check("device_info names the selected device and its draft kind", str(info.display_name) == "Fixture pad" and str(info.get("profile_kind", "")) == "gamepad")
	_check("vehicle capabilities follow the screen's", bridge.vehicle_capabilities() == setup.action_capabilities)
	_check("a gamepad preset applies through the screen's preset path", bridge.apply_preset("mode1") and str(setup.current_profile().get("preset", "")) == "mode1")
	_check("an unknown preset is refused with a reason", not bridge.apply_preset("nonsense") and not bridge.last_error().is_empty())
	raw[int(setup.current_profile().roll.axis)] = 1.0
	var sample: Dictionary = bridge.preview()
	_check("preview returns conditioned flight values and held buttons", float(sample.roll) > 0.5 and 3 in sample.buttons, str(sample))
	_check("preview arrays are fresh each poll", not is_same(sample.buttons, bridge.preview().buttons))
	_check("binding_for reads effective action bindings", str(bridge.binding_for("pause").get("type", "")) != "unbound")
	_check("binding_for reads AUX channels with the aux: prefix", str(bridge.binding_for("aux:arm").get("type", "")) == "unbound")
	_check("a recognised gamepad keeps its kind, with a reason", not bridge.set_profile_kind("radio")
		and str(setup.current_profile().kind) == "gamepad" and not bridge.last_error().is_empty())
	setup._assistant.cancel()
	await _settle()
	setup.free()
	await process_frame
	setup = await _open(5)
	setup.open_setup_assistant()
	await _settle()
	bridge = setup._assistant_bridge
	_check("an unrecognised device switches kind through the screen's kind path",
		bridge.set_profile_kind("joystick") and str(setup.current_profile().kind) == "joystick")
	_check("asking for the current kind succeeds without changes", bridge.set_profile_kind("joystick"))
	setup._assistant.cancel()
	await _settle()
	setup.free()
	await process_frame


func _test_capture_round_trip() -> void:
	var setup := await _open()
	setup.open_setup_assistant()
	await _settle()
	var bridge: RefCounted = setup._assistant_bridge
	var assistant: CanvasLayer = setup._assistant
	_check("capture starts the screen's own capture", bridge.capture("camera_cycle"))
	_check("the assistant hides while the screen captures for it", not assistant.visible and setup._screen.visible)
	setup._cancel_capture()
	await _settle()
	_check("the capture result brings the assistant back", assistant.visible and not setup._screen.visible)
	_check("an unknown capture id is refused with a reason", not bridge.capture("not_an_action") and not bridge.last_error().is_empty())
	assistant.cancel()
	await _settle()
	setup.free()
	await process_frame


func _test_calibration_round_trip() -> void:
	var setup := await _open(5)
	_check("an uncalibrated radio is reported as needing setup", setup._device_needs_setup())
	setup.open_setup_assistant()
	await _settle()
	var requests := calibration_requests
	_check("request_calibration asks the owner to open calibration", setup._assistant_bridge.request_calibration() and calibration_requests == requests + 1)
	setup.calibration_cancelled("Calibration cancelled. The draft is unchanged.")
	await _settle()
	_check("a cancelled calibration keeps Controls inactive under the assistant", is_instance_valid(setup._assistant) and not setup._screen.visible)
	setup._assistant.cancel()
	await _settle()
	setup.free()
	await process_frame


func _test_save() -> void:
	var setup := await _open()
	setup.open_setup_assistant()
	await _settle()
	var bridge: RefCounted = setup._assistant_bridge
	bridge.set_channel_inverted("pitch", true)
	_check("Save uses the transactional Save and keeps Controls open", bridge.save() and setup.profile_store.saved == 1 and setup.is_inside_tree())
	_check("after Save the draft is clean", not setup.has_unsaved_changes())
	setup._assistant.cancel()
	await _settle()
	setup.free()
	await process_frame


## Good Enemy review, 2026-11-12: calibration is refused (never left waiting) for non-radios, Reverse means
## "opposite to the correct setup" (Mode 2 throttle is inverted by its preset but shows Reverse OFF), a radio's
## Reverse is locked to its calibration, and Cancel restores the menu device as well as the profile.
func _test_review_findings() -> void:
	var setup := await _open(5)
	setup.open_setup_assistant()
	await _settle()
	var bridge: RefCounted = setup._assistant_bridge
	bridge.set_profile_kind("joystick")
	var requests := calibration_requests
	_check("a joystick's calibration request is refused with a reason, never left waiting",
		not bridge.request_calibration() and calibration_requests == requests and not bridge.last_error().is_empty())
	setup._assistant.cancel()
	await _settle()
	setup.free()
	await process_frame

	setup = await _open(5)
	setup.open_setup_assistant()
	await _settle()
	bridge = setup._assistant_bridge
	var radio_before: bool = bool(setup.current_profile().roll.get("invert", false))
	bridge.set_channel_inverted("roll", true)
	var sample: Dictionary = bridge.preview()
	_check("a radio's Reverse is locked to its calibration", bool(setup.current_profile().roll.get("invert", false)) == radio_before
		and not bool(sample.get("reverse_available", true)) and not bool(sample.inverted.roll))
	setup._assistant.cancel()
	await _settle()
	setup.free()
	await process_frame

	setup = await _open()
	setup.open_setup_assistant()
	await _settle()
	bridge = setup._assistant_bridge
	bridge.apply_preset("mode2")
	sample = bridge.preview()
	var raw_throttle_invert: bool = bool(setup.current_profile().throttle.get("invert", false))
	_check("Reverse starts OFF on every channel of a fresh gamepad preset, whatever its raw invert flags",
		not sample.inverted.roll and not sample.inverted.pitch and not sample.inverted.yaw and not sample.inverted.throttle,
		"raw throttle invert %s" % raw_throttle_invert)
	bridge.set_channel_inverted("throttle", true)
	_check("Reverse ON flips the preset's throttle direction", bool(setup.current_profile().throttle.invert) != raw_throttle_invert
		and bool(bridge.preview().inverted.throttle))
	bridge.set_channel_inverted("throttle", false)
	_check("Reverse OFF returns to the preset's direction", bool(setup.current_profile().throttle.invert) == raw_throttle_invert)
	var ui_before: int = setup._draft_ui_device_id
	setup._draft_ui_device_id = -1 # what invalidated radio menu evidence does to the menu device
	setup._assistant.cancel()
	await _settle()
	_check("Cancel restores the menu device too", setup._draft_ui_device_id == ui_before)
	setup.free()
	await process_frame

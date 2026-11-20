extends SceneTree
# UI-15-ETX-01 (docs/plans/edgetx-airplane-controls.md): the Setup assistant's switch check on the EdgeTX airplane
# preset. A recognized EdgeTX radio opened from an airplane starts from that preset; an unbound gear/flaps/smoke
# channel learns whichever control moves (an axis switch measured OFF→ON→OFF, or a button pressed after OFF); a
# control where the OpenRC layout puts the function gets its channel and switch name; flaps opt in to aircraft
# detents; other presets keep their typed Extra channel captures. Synthetic samples and events; draft only.

const ControllerSetup := preload("res://ui/controller_setup.gd")
const ControllerProfile := preload("res://input/controller_profile.gd")
const RADIO_ID := 5

class FakeRegistry extends RefCounted:
	signal devices_changed
	var devices: Array[Dictionary] = [
		{"id": 5, "name": "RadioMaster TX16S Joystick", "raw_name": "RadioMaster TX16S Joystick", "kind": "radio",
			"connected": true, "vendor_id": "4617", "product_id": "20308", "guid": "edgetx-fixture"},
	]
	func get_devices() -> Array[Dictionary]: return devices.duplicate(true)
	func selected_device_id(_role: String) -> int: return 5
	func device_for_id(id: int) -> Dictionary:
		for device in devices:
			if device.id == id: return device.duplicate(true)
		return {}
	func connection_generation(_id: int) -> int: return 1

class FakeStore extends RefCounted:
	func load_all() -> Dictionary: return {"ok": true, "profiles": [], "errors": []}
	func match_profile(_device: Dictionary, _devices: Array) -> Dictionary: return {}
	func save_profile(profile: Dictionary) -> Dictionary: return {"ok": true, "profile": profile}

var checks := 0
var failures := 0
var raw := PackedFloat64Array()
var finished: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, condition: bool, detail := "") -> void:
	checks += 1
	if not condition:
		failures += 1
	print("%s %s %s" % ["ok  " if condition else "FAIL", label, detail])


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
	raw[2] = -1.0 # radio throttle at LOW
	finished.clear()
	var setup := ControllerSetup.new()
	setup.axis_preview_provider = _axis
	setup.button_preview_provider = _button
	setup.configure(FakeRegistry.new(), FakeStore.new(), RADIO_ID, RADIO_ID)
	setup.capture_finished.connect(func(target: String, ok: bool, message: String) -> void: finished.append([target, ok, message]))
	root.add_child(setup)
	setup.set_process(false)
	await _settle(5)
	return setup


func _learn_axis(setup: Node, id: String, axis: int) -> bool:
	raw[axis] = -1.0
	if not setup.start_capture_for(id):
		return false
	setup.capture_overlay.confirm_button.pressed.emit()
	raw[axis] = 1.0
	for i in 3:
		if setup._axis_capture != null: setup._sample_axis_capture(0.1)
	raw[axis] = -1.0
	for i in 3:
		if setup._axis_capture != null: setup._sample_axis_capture(0.1)
	return not setup._is_capture_active()


func _button_event(button: int, pressed: bool) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = RADIO_ID
	event.button_index = button as JoyButton
	event.pressed = pressed
	return event


func _run() -> void:
	TranslationServer.set_locale("en")
	root.size = Vector2i(1920, 1080)
	var setup: Node = await _open()
	var profile: Dictionary = setup.current_profile()
	_check("a recognized EdgeTX radio opened from an airplane starts from the airplane preset",
		str(profile.get("preset", "")) == ControllerProfile.EDGETX_AIRPLANE_PRESET and str(profile.get("kind", "")) == "radio",
		str(profile.get("preset", "")))
	_check("gear learns the CH5 axis switch", _learn_axis(setup, "aux:gear", 4))
	var gear: Dictionary = setup.current_profile().get("aux", {}).get("gear", {})
	_check("gear: axis 4 named CH5 · SD, OFF measured low", int(gear.get("axis", -1)) == 4 and int(gear.get("channel", 0)) == 5
		and str(gear.get("label", "")) == "SD" and float(gear.get("off", 0.0)) < float(gear.get("on", 0.0)), str(gear))
	var arm: Dictionary = setup.current_profile().get("aux", {}).get("arm", {})
	_check("phase 2: the quad arms from the same CH5 axis with its own endpoints (high end only)", int(arm.get("axis", -1)) == 4
		and float(arm.get("off", 9.0)) == 0.0 and float(arm.get("on", 9.0)) == 1.0, str(arm))
	_check("flaps learn the CH6 axis switch", _learn_axis(setup, "aux:flaps", 5))
	var flaps: Dictionary = setup.current_profile().get("aux", {}).get("flaps", {})
	_check("flaps: CH6 · SA and aircraft detents", int(flaps.get("channel", 0)) == 6 and str(flaps.get("label", "")) == "SA"
		and str(flaps.get("detents", "")) == "aircraft", str(flaps))
	var mode: Dictionary = setup.current_profile().get("aux", {}).get("flight_mode", {})
	_check("phase 2: the quad's flight mode shares the CH6 axis", int(mode.get("axis", -1)) == 5
		and float(mode.get("off", 9.0)) == -1.0 and float(mode.get("on", 9.0)) == 1.0, str(mode))
	# Smoke on a button channel: Classic CH10 is joystick button 2 (SDL button 1), pressed when the switch is ON.
	_check("smoke starts the switch check", setup.start_capture_for("aux:smoke"))
	setup.capture_overlay.confirm_button.pressed.emit()
	setup._input(_button_event(1, true))
	var smoke: Dictionary = setup.current_profile().get("aux", {}).get("smoke", {})
	_check("smoke: a button pressed after OFF becomes a level button named CH10 · SE",
		str(smoke.get("type", "")) == "button" and int(smoke.get("button", -1)) == 1 and str(smoke.get("mode", "")) == "level"
		and int(smoke.get("channel", 0)) == 10 and str(smoke.get("label", "")) == "SE", str(smoke))
	_check("each learned function reports success once", finished.size() == 3 and finished.all(func(entry: Array) -> bool: return entry[1]), str(finished))
	setup._input(_button_event(1, false))
	_check("the draft with all three switches validates", ControllerProfile.validate(setup.current_profile()).ok,
		str(ControllerProfile.validate(setup.current_profile()).get("errors", [])))
	# A control away from the layout's channel is bound but not named (the radio's own mixer may differ).
	var cleared: Dictionary = setup.current_profile()
	cleared.aux.erase("gear")
	setup._set_draft_profile(cleared)
	_check("gear relearns on another axis", _learn_axis(setup, "aux:gear", 7))
	gear = setup.current_profile().get("aux", {}).get("gear", {})
	_check("an axis outside the layout's channel gets no channel or switch name", int(gear.get("axis", -1)) == 7
		and not gear.has("channel") and not gear.has("label"), str(gear))
	# An existing FPV profile keeps its arm switch; the learned gear only adds the airplane meaning.
	var fpv: Dictionary = ControllerProfile.defaults("radio", ControllerProfile.EDGETX_FPV_PRESET)
	var current: Dictionary = setup.current_profile()
	for key in ["profile_id", "name", "roll", "pitch", "yaw", "throttle"]:
		fpv[key] = current[key]
	fpv.aux["arm"] = {"type": "axis", "axis": 7, "invert": false, "off": 0.0, "on": 1.0}
	setup._set_draft_profile(fpv)
	_check("an FPV profile learns the airplane gear", _learn_axis(setup, "aux:gear", 4))
	var kept: Dictionary = setup.current_profile().get("aux", {})
	_check("its own arm binding is never moved", int(kept.get("arm", {}).get("axis", -1)) == 7 and int(kept.get("gear", {}).get("axis", -1)) == 4,
		str(kept))
	# Other presets keep the typed captures: an unbound channel has no capture slot there.
	var custom: Dictionary = setup.current_profile()
	custom["preset"] = "radio_custom"
	custom.aux.erase("smoke")
	setup._set_draft_profile(custom)
	_check("radio custom keeps no capture for an unbound channel", not setup.start_capture_for("aux:smoke"))
	setup.free()
	await process_frame
	print("edgetx switch check: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)

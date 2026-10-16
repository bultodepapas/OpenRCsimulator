extends SceneTree

const Adapter := preload("res://render/rotor/hx700_controller_input.gd")
const ControllerProfile := preload("res://input/controller_profile.gd")
const ControllerService := preload("res://input/controller_service.gd")

const DT := 1.0 / 60.0
var _checks := 0
var _failures := 0


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var observations: Array = [
		{"id": 10, "guid": "gamesir-xinput", "name": "Xbox One Controller", "raw_name": "Xbox One Controller", "known": true, "kind": "gamepad", "vendor_id": 1118, "product_id": 767},
		{"id": 12, "guid": "generic-stick", "name": "Generic USB Joystick", "known": false, "kind": "joystick"},
	]
	var axes: Dictionary = {}
	var focus := {"value": true}
	var adapter = Adapter.new()
	adapter.service.store = ControllerService.Store.new("user://hx700_inspection_input_test_missing.cfg", "user://hx700_inspection_input_test_legacy_missing.cfg")
	adapter.service.enumerate_devices = func() -> Array: return observations
	adapter.service.allow_automatic_selection = func() -> bool: return true
	adapter.read_axis = func(_device_id: int, axis: int) -> float: return float(axes.get(axis, 0.0))
	adapter.read_button = func(_device_id: int, _button: int) -> bool: return false
	adapter.focus_reader = func() -> bool: return bool(focus.value)
	root.add_child(adapter)
	await process_frame
	_check("normal startup automatically selects a known pad", adapter.selected_id() == 10)
	_check("the adapter owns one ControllerService session", adapter.service.session == adapter and adapter.service.registry.get_devices().size() == 2)
	_check("hardware control starts disabled", not adapter.enabled)
	adapter.radio.confirmed_gamepad_connection = func(_id: int) -> bool: return true

	# Mode 2 uses mapped channels exactly once, ignores the observed resting noise
	# inside the default 0.08 deadzone, and seeds collective from the current pose.
	axes[0] = 1.0
	axes[1] = 0.033
	axes[2] = 1.0
	axes[3] = -1.0
	_check("Mode 2 enables from current collective pose", adapter.enable(5.0))
	var mode2 := adapter.sample(DT, false)
	_check("verified live gamepad becomes active without a neutral dwell", mode2.active)
	_check("Mode 2 maps collective/roll/pitch/tail through RcInput once", absf(mode2.inputs[1] - 10.0) < 1e-10 and absf(mode2.inputs[2] + 10.0) < 1e-10 and absf(mode2.inputs[3] - 20.0) < 1e-10, str(mode2.inputs))
	_check("resting throttle noise does not move the seeded collective", absf(mode2.inputs[0] - 5.0) < 1e-10, str(mode2.inputs))

	# A paused tick still reads the controller but cannot integrate its rate throttle.
	var held_collective := float(mode2.inputs[0])
	axes[1] = -1.0
	var paused := adapter.sample(1.0, true)
	_check("paused input holds every view command", not paused.active and paused.inputs == mode2.inputs, str(paused.inputs))
	var moving := adapter.sample(DT, false)
	_check("unpaused Mode 2 rate input moves collective from its seed", moving.active and moving.inputs[0] > held_collective, str(moving.inputs))
	adapter.disable()
	var disabled_pose := adapter.sample(DT, false)
	_check("disabled input holds pose and stops the rate integrator", not disabled_pose.active and disabled_pose.inputs == moving.inputs, str(disabled_pose.inputs))

	# A customized Mode 1 profile keeps identity, inversion and calibration.
	var mode1: Dictionary = ControllerProfile.defaults("gamepad", "mode1")
	mode1["roll"]["invert"] = true
	mode1["roll"]["min"] = -0.9
	var mode1_id := str(mode1.profile_id)
	var gamepad_info: Dictionary = adapter.service.registry.device_for_id(10)
	_check("Mode 1 profile applies", adapter.apply_controller_selection(10, gamepad_info, mode1, false))
	_check("profile identity, channel mapping, inversion and calibration are preserved", adapter.radio.profile.profile_id == mode1_id and int(adapter.radio.profile.throttle.axis) == 3 and bool(adapter.radio.profile.roll.invert) and is_equal_approx(float(adapter.radio.profile.roll.min), -0.9))
	adapter.radio.confirmed_gamepad_connection = func(_id: int) -> bool: return true
	axes[0] = 0.0
	axes[1] = 0.0
	axes[2] = -0.9
	axes[3] = -1.0
	_check("Mode 1 can be explicitly enabled from the current pose", adapter.enable(0.0))
	var mode1_sample := adapter.sample(DT, false)
	_check("Mode 1 channel direction and throttle axis reach HX degrees", mode1_sample.active and absf(mode1_sample.inputs[1] - 10.0) < 1e-9 and mode1_sample.inputs[0] > 0.0, str(mode1_sample.inputs))
	adapter.disable()

	# Radio absolute throttle requires a selected-device low event after enabling.
	observations.append({"id": 11, "guid": "edgetx", "name": "EdgeTX RadioMaster TX16S", "raw_name": "EdgeTX RadioMaster TX16S", "known": false, "kind": "radio", "vendor_id": 0x1209, "product_id": 0x4f54})
	adapter.service.refresh()
	_check("explicit radio selection", adapter.select_device(11) and adapter.selected_id() == 11)
	_check("radio profile is retained as a radio profile", adapter.radio.connected and adapter.radio.profile.kind == "radio")
	_check("radio starts at the view pose", adapter.enable(4.5))
	var wrong_event := InputEventJoypadMotion.new()
	wrong_event.device = 10
	wrong_event.axis = JOY_AXIS_LEFT_Y
	wrong_event.axis_value = -1.0
	_check("another device's axis event is ignored", not adapter.handle_event(wrong_event) and not adapter.radio.has_axis_sample(adapter.radio.profile.throttle.axis))
	var waiting := adapter.sample(DT, false)
	_check("radio remains unarmed and holds pose until fresh low throttle evidence", not waiting.active and absf(waiting.inputs[0] - 4.5) < 1e-10, str(waiting.inputs))
	axes[2] = -1.0
	var low_event := InputEventJoypadMotion.new()
	low_event.device = 11
	low_event.axis = JOY_AXIS_RIGHT_X
	low_event.axis_value = -1.0
	_check("selected radio throttle event reaches RcInput", adapter.handle_event(low_event))
	var radio_active := adapter.sample(DT, false)
	_check("fresh radio low throttle arms the configured profile", radio_active.active and absf(radio_active.inputs[0] + 13.0) < 1e-10, str(radio_active.inputs))
	adapter.disable()

	# Unknown controls are selectable for identification, but cannot move the model
	# without a configured profile. Fixed-wing trigger throttle is also refused.
	_check("unconfigured generic joystick cannot be enabled", adapter.select_device(12) and not adapter.enable(3.0))
	var rejected := adapter.sample(0.0, true)
	_check("failed enable status is available without losing the view pose", not rejected.ok and rejected.inputs[0] == 3.0 and "perfil" in rejected.status.to_lower(), rejected.status)
	var trigger: Dictionary = ControllerProfile.defaults("gamepad", "trigger_absolute")
	_check("fixed-wing trigger throttle is rejected", not adapter.controller_profile_rejection(trigger).is_empty())
	_check("empty profile is rejected", not adapter.controller_profile_rejection({}).is_empty())

	# Hotplug cannot retake flight ownership; loss interrupts once, and reconnect
	# requires an explicit device selection before input can be re-enabled.
	var interruption_count := {"value": 0}
	adapter.interrupted.connect(func(_reason: String) -> void: interruption_count.value += 1)
	_check("return to known pad is explicit", adapter.select_device(10))
	adapter.radio.confirmed_gamepad_connection = func(_id: int) -> bool: return true
	_check("known pad re-enables explicitly", adapter.enable(3.0))
	observations.erase(observations[0])
	adapter.service.refresh()
	_check("selected disconnect disables input, clears RcInput and emits interruption", not adapter.enabled and not adapter.radio.connected and interruption_count.value == 1)
	observations.append({"id": 10, "guid": "gamesir-xinput", "name": "Xbox One Controller", "raw_name": "Xbox One Controller", "known": true, "kind": "gamepad", "vendor_id": 1118, "product_id": 767})
	adapter.service.refresh()
	_check("reconnected device is not automatically selected", adapter.selected_id() == -1 and not adapter.enabled)
	_check("manual re-selection restores a disabled profile", adapter.select_device(10) and not adapter.enabled)
	adapter.radio.confirmed_gamepad_connection = func(_id: int) -> bool: return true
	_check("explicit re-enable after reconnect works", adapter.enable(3.0))

	# Focus loss retains the demanded pose, emits an interruption and never
	# automatically re-enables when focus returns.
	var before_focus := float(adapter.sample(DT, false).inputs[0])
	focus.value = false
	var lost_focus := adapter.sample(DT, false)
	_check("focus loss interrupts active controls while preserving pose", not lost_focus.active and not adapter.enabled and interruption_count.value == 2 and absf(lost_focus.inputs[0] - before_focus) < 1e-10)
	var focus_status := str(lost_focus.status)
	var idle_after_focus := adapter.sample(DT, false)
	_check("disabled sampling preserves the focus-loss explanation", idle_after_focus.status == focus_status)
	focus.value = true
	var recovered := adapter.sample(DT, false)
	_check("focus recovery does not take input until explicit enable", not recovered.active and not adapter.enabled)
	_check("explicit re-enable after focus recovery works", adapter.enable(before_focus))
	var before_invalid_dt := float(adapter._held_inputs[0])
	var invalid_dt := adapter.sample(-0.1, false)
	_check("invalid dt is rejected without motion", not invalid_dt.ok and invalid_dt.inputs[0] == before_invalid_dt)

	adapter.disable()
	root.remove_child(adapter)
	adapter.queue_free()
	await process_frame
	print("HX-700 inspection controller: %d/%d checks passed" % [_checks - _failures, _checks])
	quit(1 if _failures else 0)

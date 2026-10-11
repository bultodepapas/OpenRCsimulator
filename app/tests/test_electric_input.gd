# EL1e product-path check: the real main scene with an explicitly selected synthetic electric Stik.
# Invoke once per setup with: -- --electric-demo=4s (or 6s). No physical radio is required.
extends SceneTree

const FAKE_DEVICE: int = 15
const PROPULSION: Script = preload("res://physics/propulsion.gd")
const FLIGHT_SESSION: Script = preload("res://sim/flight_session.gd")

var _failures: int = 0
var _checks: int = 0
var _main: Node3D
var _session: Node


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL ", label, " ", detail)


func _motion(axis: int, value: float) -> void:
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.device = FAKE_DEVICE
	event.axis = axis as JoyAxis
	event.axis_value = value
	Input.parse_input_event(event)


func _key_state(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _key_tap(code: Key) -> void:
	_key_state(code, true)
	_key_state(code, false)


func _panel_has(value: String) -> bool:
	var panel: Label = _main.get("_panel") as Label
	return panel != null and value in panel.text


## Tick-counted waits avoid wall-clock assumptions and refresh the text panel after simulation callbacks.
func _settle() -> void:
	for _index: int in 4:
		await physics_frame
	await process_frame
	await process_frame


func _initialize() -> void:
	var demo: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--electric-demo="):
			demo = argument.trim_prefix("--electric-demo=")
	if demo.is_empty():
		_run_default_session_checks()
		return
	if demo not in ["4s", "6s"]:
		printerr("EL1e electric input requires --electric-demo=4s or --electric-demo=6s")
		quit(2)
		return
	_run(demo)


## The ordinary app suite has no CLI user args; keep useful coverage for both installed electric data files there.
func _run_default_session_checks() -> void:
	for demo: String in ["4s", "6s"]:
		var session: Node = FLIGHT_SESSION.new()
		session.call("setup", "res://data/aircraft/synthetic_stik_electric_%s.json" % demo)
		var aircraft_value: Variant = session.get("aircraft")
		var aircraft: Dictionary = aircraft_value if aircraft_value is Dictionary else {}
		var model_value: Variant = aircraft.get("model", {})
		var model: Dictionary = model_value if model_value is Dictionary else {}
		var propulsion_value: Variant = model.get("propulsion", {})
		var propulsion: Dictionary = propulsion_value if propulsion_value is Dictionary else {}
		var sim: Node = session.get("sim") as Node
		_check("%s data starts a coupled electric flight" % demo,
			session.call("is_flyable") and session.call("shaft_is_coupled")
			and PROPULSION.is_electric(propulsion))
		var initial_rpm: float = float(sim.get("aux")[0])
		session.set("engine_running", false)
		var stopped: Dictionary = session.call("electrical_state")
		_check("%s disabled source has zero current" % demo, stopped.get("ok", false)
			and float(stopped.get("motor_current_a", NAN)) == 0.0
			and float(stopped.get("battery_current_a", NAN)) == 0.0)
		session.call("reset")
		_check("%s reset restores powered trim" % demo, bool(session.get("engine_running"))
			and absf(float(sim.get("aux")[0]) - initial_rpm) < 0.01)
		session.free()
	print("EL1e electric session defaults: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _run(demo: String) -> void:
	_main = load("res://main.tscn").instantiate() as Node3D
	root.add_child(_main)
	await _settle()
	_session = _main.get("session") as Node
	if _session == null:
		_check("main scene created the electric flight session", false)
		quit(1)
		return

	var aircraft_value: Variant = _session.get("aircraft")
	var aircraft: Dictionary = aircraft_value if aircraft_value is Dictionary else {}
	var model_value: Variant = aircraft.get("model", {})
	var model: Dictionary = model_value if model_value is Dictionary else {}
	var propulsion_value: Variant = model.get("propulsion", {})
	var propulsion: Dictionary = propulsion_value if propulsion_value is Dictionary else {}
	var path: String = str(_session.get("aircraft_path"))
	var sim: Node = _session.get("sim") as Node
	_check("explicit demo selected its synthetic electric Stik data", path.ends_with("synthetic_stik_electric_%s.json" % demo)
		and aircraft.get("ok", false) and PROPULSION.is_electric(propulsion), path)
	_check("direct route starts on keyboard", not _session.get("radio").connected and _panel_has("input: keyboard"))
	_check("trimmed electric flight is runnable", _session.call("is_flyable") and not sim.get("paused"))
	_check("electric demo does not attach combustion audio", _main.get("_engine_audio") == null)
	if not aircraft.get("ok", false) or not PROPULSION.is_electric(propulsion):
		quit(1)
		return

	var profile_path: String = "user://test_electric_input_%s.cfg" % demo
	DirAccess.remove_absolute(ProjectSettings.globalize_path(profile_path))
	_session.set("profiles_path", profile_path)
	_session.set("device_info", func(_device: int) -> Dictionary:
		return {"guid": "el1e-fake", "name": "Fake EdgeTX", "vendor_id": 0x1209, "product_id": 0x4f54})
	Input.joy_connection_changed.emit(FAKE_DEVICE, true)
	await _settle()
	var radio: Object = _session.get("radio")
	_check("fake radio connects without querying a physical device", radio.get("connected")
		and radio.get("device_id") == FAKE_DEVICE)
	_check("untouched throttle stays SAFE", not radio.get("armed") and float(_session.get("commands").throttle) == 0.0)

	var zero: Dictionary = _session.call("electrical_state")
	_check("safe zero duty draws zero motor and battery current", zero.get("ok", false)
		and float(zero.get("duty", NAN)) == 0.0 and float(zero.get("motor_current_a", NAN)) == 0.0
		and float(zero.get("battery_current_a", NAN)) == 0.0, str(zero))
	_motion(2, 1.0)
	await _settle()
	_check("high throttle on connection stays unarmed and at zero duty", not radio.get("armed")
		and float(_session.get("commands").throttle) == 0.0
		and float(_session.call("electrical_state").duty) == 0.0)
	_motion(2, -1.0)
	await _settle()
	_check("a fresh low-throttle event arms the radio", radio.get("armed") and _panel_has("ARMED"))
	_motion(2, 1.0)
	await _settle()
	var full: Dictionary = _session.call("electrical_state")
	_check("armed full throttle reaches the motor and bus", float(_session.get("commands").throttle) == 1.0
		and float(sim.get("inputs")[3]) == 1.0 and float(full.get("duty", NAN)) == 1.0
		and float(full.get("motor_current_a", NAN)) > 0.0 and float(full.get("battery_current_a", NAN)) > 0.0,
		str(full))

	Input.joy_connection_changed.emit(FAKE_DEVICE, false)
	await _settle()
	_check("unplug pauses and selects the keyboard", sim.get("paused") and not radio.get("connected")
		and _panel_has("PAUSED (radio disconnected)"))
	_check("unplug commands zero duty", float(sim.get("inputs")[3]) == 0.0
		and float(_session.call("electrical_state").battery_current_a) == 0.0)
	var frozen: Dictionary = _session.call("checkpoint")
	var frozen_tick: int = int(sim.get("tick"))
	var frozen_continuous: PackedFloat64Array = sim.get("continuous").duplicate()
	var frozen_aux: PackedFloat64Array = sim.get("aux").duplicate()
	await _settle()
	_check("pause freezes the complete aircraft and rotor state", int(sim.get("tick")) == frozen_tick
		and sim.get("continuous") == frozen_continuous and sim.get("aux") == frozen_aux
		and var_to_bytes(_session.call("checkpoint")) == var_to_bytes(frozen))

	_key_tap(KEY_P)
	await _settle()
	_check("P resumes into keyboard input", not sim.get("paused") and not radio.get("connected")
		and _panel_has("input: keyboard"))
	_key_state(KEY_W, true)
	await _settle()
	var keyboard_throttle: float = float(_session.get("commands").throttle)
	_key_state(KEY_W, false)
	await _settle()
	_check("keyboard throttle command reaches the electric ESC", keyboard_throttle > 0.0
		and float(sim.get("inputs")[3]) > 0.0)

	_key_tap(KEY_R)
	await _settle()
	var start: Dictionary = _session.get("start")
	_check("R resets the powered trimmed electric flight", not sim.get("paused") and int(sim.get("tick")) <= 8
		and bool(_session.get("engine_running"))
		and absf(float(_session.get("commands").throttle) - float(start.get("throttle", NAN))) < 1e-12
		and absf(float(sim.get("aux")[0]) - float(start.get("rpm", NAN))) < 0.01)
	_check("reset keeps keyboard selection", not radio.get("connected") and _panel_has("input: keyboard"))
	Input.joy_connection_changed.emit(FAKE_DEVICE, true)
	await _settle()
	_check("reconnect with retained high throttle remains SAFE", radio.get("connected") and not radio.get("armed")
		and float(_session.call("electrical_state").duty) == 0.0 and float(_session.call("electrical_state").battery_current_a) == 0.0)
	_motion(2, -1.0)
	await _settle()
	_check("reconnected radio requires and accepts a fresh low event", radio.get("armed"))
	Input.joy_connection_changed.emit(FAKE_DEVICE, false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(profile_path))
	print("EL1e electric input %s: %d checks, %d failed" % [demo, _checks, _failures])
	quit(1 if _failures > 0 else 0)

extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Profile := preload("res://input/controller_profile.gd")
const UiDriver := preload("res://tests/ui_driver.gd")
const AVANTI_DATA := "res://data/aircraft/sebart_avanti_s_a200.json"
const AVANTI_ID := "sebart-avanti-s-a200-p100rx"
const RADIO_ID := 42

class FlightHarness extends "res://main.gd":
	func _ready() -> void:
		pass

	func _process(_delta: float) -> void:
		pass

	func _physics_process(_delta: float) -> void:
		pass

var checks := 0
var failures := 0
var ui: RefCounted


func _check(label: String, passed: bool, detail := "") -> void:
	checks += 1
	if passed:
		print("ok   ", label)
	else:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func _initialize() -> void:
	ui = UiDriver.new(self)
	await _run()
	print("retractable gear input: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _run() -> void:
	var session := Session.new()
	session.setup(AVANTI_DATA, AVANTI_ID)
	session.sim.set_paused(false)
	var flight: Node3D = FlightHarness.new()
	flight.set("session", session)
	flight.set_process(false)
	flight.set_physics_process(false)
	flight.set_process_input(true)
	flight.set_process_unhandled_input(true)
	root.add_child(flight)
	flight.set_process(false)
	flight.set_physics_process(false)
	_check("Vantage Jet fixture exposes retractable landing gear", session.gear_is_retractable()
		and bool(session.gear_state().available) and not bool(session.gear_state().target_down))

	await ui.tap(KEY_G)
	_step_gear_command(session)
	_check("G sends the landing gear down command through unhandled input", bool(session.gear_state().target_down))
	await ui.tap(KEY_G)
	_step_gear_command(session)
	_check("a second G press sends the landing gear up command", not bool(session.gear_state().target_down))

	var brake_press := _key_event(KEY_B, true)
	Input.parse_input_event(brake_press)
	await ui.settle()
	session.sim.inputs = session.call("_inputs")
	_check("holding B applies the wheel brakes", is_equal_approx(float(session.gear_state().brake), 1.0))
	session.sim.set_paused(true)
	Input.parse_input_event(_key_event(KEY_B, false))
	await ui.settle()
	session.sim.inputs = session.call("_inputs")
	_check("releasing B clears the brakes while paused", is_equal_approx(float(session.gear_state().brake), 0.0))
	session.sim.set_paused(false)

	var profile: Dictionary = Profile.defaults("radio", "radio_custom")
	profile["aux"] = {"gear": {"type": "button", "button": 7, "mode": "level"}}
	_check("radio fixture accepts a dedicated gear AUX binding", Profile.validate(profile).ok)
	session.radio.connect_device(RADIO_ID, {"known": false, "name": "EdgeTX gear test"}, profile)
	session.radio.on_button(RADIO_ID, 7, false)
	session._physics_process(0.0)
	_step_gear_command(session)
	_check("gear AUX low commands gear down", float(session.radio.auxiliary_amount("gear")) == 0.0
		and bool(session.gear_state().target_down))
	var aux_target: bool = bool(session.gear_state().target_down)
	await ui.tap(KEY_G)
	_check("G does not override an assigned gear AUX input", bool(session.gear_state().target_down) == aux_target
		and str(flight.get("_note")).contains("AUX"))

	# A maintained switch owns the same gear request as an axis or button AUX.
	profile.aux.gear = {"type": "switch", "buttons": [7, 8], "invert": false}
	_check("radio fixture accepts a maintained gear switch", Profile.validate(profile).ok)
	session.radio.connect_device(RADIO_ID, {"known": false, "name": "EdgeTX gear test"}, profile)
	var held := {7: false, 8: true}
	session.read_axis = func(_id: int, _axis: int) -> float: return 0.0
	session.read_button = func(_id: int, button: int) -> bool: return bool(held.get(button, false))
	session._poll_controller() # baseline at the up position
	held[7] = true
	held[8] = false
	session.radio.on_button(RADIO_ID, 8, false)
	session.radio.on_button(RADIO_ID, 7, true)
	session._poll_controller() # deliberate down position arms the switch
	held[7] = false
	held[8] = true
	session.radio.on_button(RADIO_ID, 7, false)
	session.radio.on_button(RADIO_ID, 8, true)
	session._physics_process(0.0)
	_step_gear_command(session)
	_check("maintained gear switch commands up", session.radio.auxiliary_amount("gear") == 1.0
		and not bool(session.gear_state().target_down))

	await ui.tap(KEY_G)
	_step_gear_command(session)
	_check("G leaves switch-owned gear up and explains AUX ownership", not bool(session.gear_state().target_down)
		and str(flight.get("_note")).contains("AUX"))
	# Sample the unchanged physical switch again, so the controller action has an independent starting state.
	session._physics_process(0.0)
	_step_gear_command(session)
	flight.call("controller_action", "gear_toggle")
	_step_gear_command(session)
	_check("controller gear action leaves switch-owned gear up and explains AUX ownership", not bool(session.gear_state().target_down)
		and str(flight.get("_note")).contains("AUX"))

	held[7] = true
	held[8] = false
	session.radio.on_button(RADIO_ID, 8, false)
	session.radio.on_button(RADIO_ID, 7, true)
	session._physics_process(0.0)
	_step_gear_command(session)
	_check("maintained switch still commands gear down", session.radio.auxiliary_amount("gear") == 0.0
		and bool(session.gear_state().target_down))

	root.remove_child(flight)
	flight.free()
	# Main._exit_tree() already freed the injected, unattached session on removal.


func _key_event(key: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	return event


func _step_gear_command(session: Node) -> void:
	session.sim.inputs = session.call("_inputs")
	session.sim.step()

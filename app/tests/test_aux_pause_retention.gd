# External audit A6 F2: an ordinary pause, menu or focus hold must not change bound flap/gear targets while the
# transmitter switches stay where they were. The hold clears the radio channels' arming (by design: smoke stops at
# the boundary), and an unarmed channel reports 0.0. That means "no valid command yet", not "retract flaps / gear
# down"; the session keeps the last accepted targets until fresh OFF evidence re-arms the channel.
# The audit's probe reproduced flaps 1 -> 0 and gear up -> down across pause_menu with both axes held at +1.
# Run: godot --headless --path . --script res://tests/test_aux_pause_retention.gd
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Profile := preload("res://input/controller_profile.gd")
const AVANTI_DATA := "res://data/aircraft/sebart_avanti_s_a200.json"
const AVANTI_ID := "sebart-avanti-s-a200-p100rx"
const RADIO_ID := 42
const FLAP_AXIS := 4
const GEAR_AXIS := 5
const GEAR_BUTTON := 7

var checks := 0
var failures := 0
var axes := {}
var buttons := {}


func check(label: String, ok: bool, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func _initialize() -> void:
	axis_bindings()
	button_binding()
	print("AUX pause retention: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func new_session(aux: Dictionary) -> Session:
	var session: Session = Session.new()
	session.setup(AVANTI_DATA, AVANTI_ID)
	session.sim.set_paused(false)
	var profile: Dictionary = Profile.defaults("radio", "radio_custom")
	profile["aux"] = aux
	check("profile with bound AUX is valid", Profile.validate(profile).ok, str(Profile.validate(profile)))
	session.radio.connect_device(RADIO_ID, {"known": false, "name": "EdgeTX AUX pause test"}, profile)
	axes = {}
	buttons = {}
	session.read_axis = func(_id: int, axis: int) -> float: return float(axes.get(axis, 0.0))
	session.read_button = func(_id: int, button: int) -> bool: return bool(buttons.get(button, false))
	return session


## Move an axis like a transmitter: an event, then the next accepted tick samples it.
func move(session: Session, axis: int, value: float) -> void:
	axes[axis] = value
	session.radio.on_motion(RADIO_ID, axis, value)


func press(session: Session, button: int, pressed: bool) -> void:
	buttons[button] = pressed
	session.radio.on_button(RADIO_ID, button, pressed)


## One accepted tick of the live input path, then the inputs the kernel will use.
func tick(session: Session) -> void:
	session._physics_process(0.0)
	session.sim.inputs = session.call("_inputs")


func flaps(session: Session) -> float:
	return float(session.get("_flap_requested"))


## The pilot's gear request (what the input path decided this tick).
func gear_down(session: Session) -> bool:
	return bool(session.get("_gear_requested_down"))


## The kernel inputs for the next tick carry exactly the requests.
func kernel_inputs_match(session: Session) -> bool:
	var inputs: PackedFloat64Array = session.sim.inputs
	return inputs[session.flap_input_index()] == flaps(session) and inputs[4] == (1.0 if gear_down(session) else 0.0)


## The accepted gear target lives in the simulation state; it follows the request when a tick is accepted.
func accepted_gear_down(session: Session) -> bool:
	session.sim.step()
	return bool(session.gear_state().target_down)


## Pause, menu and focus holds as the app applies them: hold, input sampled (not integrated) while held, release.
func hold_cycle(session: Session, reason: String) -> void:
	session.hold(reason)
	session._physics_process(0.0)
	session._physics_process(0.0)
	session.release(reason)
	session.resume()


func axis_bindings() -> void:
	var session := new_session({
		"flaps": {"type": "axis", "axis": FLAP_AXIS, "invert": false, "off": -1.0, "on": 1.0},
		"gear": {"type": "axis", "axis": GEAR_AXIS, "invert": false, "off": -1.0, "on": 1.0},
	})
	check("the Avanti has flaps and retractable gear", session.flaps_available() and session.gear_is_retractable())
	# Arm both channels with fresh OFF evidence, then command full flaps and gear up.
	move(session, FLAP_AXIS, -1.0)
	move(session, GEAR_AXIS, -1.0)
	tick(session)
	check("OFF arms both channels: flaps retracted, gear down", flaps(session) == 0.0 and gear_down(session)
		and session.radio.auxiliary_request_valid("flaps") and session.radio.auxiliary_request_valid("gear"))
	move(session, FLAP_AXIS, 1.0)
	move(session, GEAR_AXIS, 1.0)
	tick(session)
	check("switches ON command full flaps and gear up", flaps(session) == 1.0 and not gear_down(session)
		and kernel_inputs_match(session))

	for reason: String in ["pause_menu", "menu", "focus"]:
		hold_cycle(session, reason)
		check("after a %s hold the unarmed channels are not valid commands" % reason,
			not session.radio.auxiliary_request_valid("flaps") and not session.radio.auxiliary_request_valid("gear")
			and session.radio.auxiliary_amount("flaps") == 0.0)
		var tick_before: int = session.sim.tick
		tick(session)
		session.sim.step()
		tick(session)
		check("unchanged high switches keep full flaps and gear up across %s (audit: flaps 1->0, gear up->down)" % reason,
			flaps(session) == 1.0 and not gear_down(session) and kernel_inputs_match(session)
			and not bool(session.gear_state().target_down)
			and session.sim.tick == tick_before + 1 and not session.sim.paused, "flaps %s down %s" % [flaps(session), gear_down(session)])

	# A deliberate OFF re-arms and commands; ON again commands.
	move(session, FLAP_AXIS, -1.0)
	move(session, GEAR_AXIS, -1.0)
	tick(session)
	check("fresh OFF after the pause re-arms and retracts flaps / lowers gear", flaps(session) == 0.0 and gear_down(session)
		and kernel_inputs_match(session) and accepted_gear_down(session))
	tick(session)
	move(session, FLAP_AXIS, 1.0)
	move(session, GEAR_AXIS, 1.0)
	tick(session)
	check("then ON commands full flaps and gear up again", flaps(session) == 1.0 and not gear_down(session))

	# An intermediate flap stage and the gear-down state also survive a pause unchanged.
	move(session, FLAP_AXIS, 0.0)
	move(session, GEAR_AXIS, -1.0)
	tick(session)
	var half: float = flaps(session)
	check("a centred flap axis requests an intermediate stage", half > 0.0 and half < 1.0 and gear_down(session), str(half))
	hold_cycle(session, "pause_menu")
	tick(session)
	check("an intermediate flap stage and gear down are kept across a pause", flaps(session) == half and gear_down(session)
		and kernel_inputs_match(session) and accepted_gear_down(session))
	tick(session)

	# Physical actuators keep moving toward the retained targets after the pause; they do not jump.
	var flap_aux: float = session.sim.aux[session.flap_aux_index()]
	for i in 3:
		session.sim.step()
		tick(session)
	var flap_aux_after: float = session.sim.aux[session.flap_aux_index()]
	check("the flap actuator stays continuous (no step change across the resumed ticks)",
		is_finite(flap_aux_after) and absf(flap_aux_after - flap_aux) < 0.25, "%s -> %s" % [flap_aux, flap_aux_after])
	session.free()


func button_binding() -> void:
	var session := new_session({"gear": {"type": "button", "button": GEAR_BUTTON, "mode": "level"}})
	press(session, GEAR_BUTTON, false)
	tick(session)
	press(session, GEAR_BUTTON, true)
	tick(session)
	check("a level gear button held ON commands gear up", not gear_down(session))
	hold_cycle(session, "pause_menu")
	tick(session)
	check("a button held through the pause keeps gear up", not gear_down(session) and not session.radio.auxiliary_request_valid("gear"))
	press(session, GEAR_BUTTON, false)
	tick(session)
	check("releasing the button re-arms and lowers the gear", gear_down(session) and session.radio.auxiliary_request_valid("gear")
		and accepted_gear_down(session))
	session.free()

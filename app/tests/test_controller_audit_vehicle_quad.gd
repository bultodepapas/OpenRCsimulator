# CTRL-01: the real quad adapter feeds the sampled controller and controlled
# plant. Synthetic input establishes software behavior, not device qualification.
extends SceneTree

const PilotInput := preload("res://input/multirotor_input.gd")
const Profile := preload("res://input/controller_profile.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const Fixtures := preload("res://tests/mr_fixtures.gd")
const Activity := preload("res://vehicles/multirotor/multirotor_scene.gd")
const DT := 1.0 / 240.0

class StubSession extends Node:
	var prepared := true

class FocusActivity extends Activity:
	var held_reason := ""
	func _ready() -> void: pass
	func _hold(reason: String) -> void: held_reason = reason

var failures := 0
var checks := 0
var axes := {}
var keys := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0, arm = false, mode = false}
var verifier := true


func check(label: String, ok: bool) -> void:
	checks += 1
	print("%s %s" % ["ok  " if ok else "FAIL", label])
	if not ok: failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _pilot() -> RefCounted:
	var input := PilotInput.new()
	input.read_axis = func(_id: int, axis: int) -> float: return float(axes.get(axis, 0.0))
	input.read_button = func(_id: int, _button: int) -> bool: return false
	input.read_keys = func() -> Dictionary: return keys.duplicate()
	return input


func _tick(sim: Node, input: RefCounted) -> Dictionary:
	var sample: Dictionary = input.sample(DT, true)
	Fixtures.run(sim, sample.pilot, 1)
	return sample


func _toggle(sim: Node, input: RefCounted) -> void:
	keys.arm = false
	_tick(sim, input)
	keys.arm = true
	_tick(sim, input)


func _raw_source(kind: String, inverted: bool) -> void:
	var low := 1.0 if inverted else -1.0
	var high := -low
	keys.arm = false
	axes = {0: 0.0, 1: 0.0, 2: low, 3: 0.0}
	var profile := Profile.defaults(kind, "radio_custom")
	profile.throttle.invert = inverted
	var input := _pilot()
	input.connect_device(0, {name = "Synthetic raw", kind = kind}, profile)
	var h: Dictionary = Fixtures.install(root, Fixtures.lab())
	var sim: Node = h.sim
	var message: String = Fixtures.reset(sim, h.plant.initial_frame(Fixtures.body(20.0)), FC.neutral_input())
	check("%s inverted=%s plant prepared" % [kind, inverted], h.ok and message.is_empty())
	var s := _tick(sim, input)
	check("no-event low poll is unready and OFF is not evidence", not s.ready and sim.modes[FC.MODE_OFF_OBSERVED] == 0)
	_toggle(sim, input)
	axes[2] = high
	s = _tick(sim, input)
	check("no-event arm and full poll cannot drive motors", not s.ready and s.pilot[FC.IN_THROTTLE] == 0.0 \
		and sim.modes[FC.MODE_MOTOR] == FC.MOTOR_DISARMED and sim.aux[FC.AUX_COMMAND] == 0.0)
	input.radio.on_motion(0, 2, high)
	s = _tick(sim, input)
	axes[2] = low
	s = _tick(sim, input)
	check("high event followed only by a low poll stays unready", not s.ready and sim.modes[FC.MODE_OFF_OBSERVED] == 0)
	input.radio.on_motion(0, 2, low)
	s = _tick(sim, input)
	check("fresh low becomes ready but earlier unready OFF cannot arm", s.ready and sim.modes[FC.MODE_MOTOR] == FC.MOTOR_DISARMED \
		and sim.modes[FC.MODE_OFF_OBSERVED] == 0)
	_toggle(sim, input) # OFF after readiness
	_toggle(sim, input) # ON after that OFF
	check("ready OFF then ON at low throttle arms", sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED)
	axes[2] = high
	s = _tick(sim, input)
	check("after proper arming full throttle reaches the controller", s.ready and sim.aux[FC.AUX_COLLECTIVE] > 0.99)
	input.on_connection_changed(0, false)
	input.connect_device(0, {name = "Synthetic raw", kind = kind}, profile)
	axes[2] = low
	s = _tick(sim, input)
	check("reconnect discards prior-generation low evidence and motor authority", not s.ready \
		and sim.modes[FC.MODE_MOTOR] == FC.MOTOR_DISARMED and sim.modes[FC.MODE_OFF_OBSERVED] == 0)
	input.radio.on_motion(0, 2, low)
	s = _tick(sim, input)
	check("new generation requires a new low event", s.ready)
	input.use_profile(profile)
	s = _tick(sim, input)
	check("profile change discards the old low evidence", not s.ready)
	check("controlled ticks did not fault", str(sim.fault_reason).is_empty())
	sim.free()


func _focus_and_pad() -> void:
	keys.arm = false
	axes = {0: 0.0, 1: 0.0, 2: -1.0, 3: 0.0}
	var activity := FocusActivity.new()
	activity.session = StubSession.new()
	activity.hud = CanvasLayer.new()
	root.add_child(activity)
	activity.input = _pilot()
	var profile := Profile.defaults("radio", "radio_custom")
	activity.input.connect_device(0, {name = "Synthetic radio", kind = "radio"}, profile)
	activity.input.radio.on_motion(0, 2, -1.0)
	check("radio is ready before focus loss", activity.input.sample(DT, true).ready)
	activity._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check("focus loss holds and discards raw low evidence", not activity.held_reason.is_empty() \
		and not activity.input.sample(DT, false).ready)
	activity.input.radio.on_motion(0, 2, -1.0)
	check("a fresh low event permits radio readiness after focus", activity.input.sample(DT, false).ready)
	activity.session.free()
	activity.hud.free()
	activity.free()

	var pad := _pilot()
	pad.radio.confirmed_gamepad_connection = func(_id: int) -> bool: return verifier
	axes = {}
	pad.connect_device(1, {name = "Synthetic pad", kind = "gamepad", known = true})
	check("a verified standardized pad is ready from neutral polling", pad.sample(DT, false).ready)
	verifier = false
	check("revoking the live verifier drops readiness on hold", not pad.sample(DT, false).ready)
	verifier = true
	check("re-verification restores the trusted pad path", pad.sample(DT, false).ready)


func _run() -> void:
	for kind in ["radio", "joystick"]:
		for inverted in [false, true]:
			_raw_source(kind, inverted)
	_focus_and_pad()
	print("vehicle quad audit: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

# Audit reproduction for pinned cfb5acd5; see the audit README for observed results.
# The assertions describe the CURRENT problematic behavior, so a passing script reproduces it.
# Run only in an isolated checkout/profile after the normal Godot resource import.
extends SceneTree

const PilotInput := preload("res://input/multirotor_input.gd")
const Profile := preload("res://input/controller_profile.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const Fixtures := preload("res://tests/mr_fixtures.gd")
const DT := 1.0 / 240.0

var axes := {}
var buttons := {}
var keys := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0, arm = false, mode = false}
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, condition: bool) -> void:
	checks += 1
	print("%s %s" % ["ok  " if condition else "FAIL", label])
	if not condition:
		failures += 1


func pilot() -> RefCounted:
	var result := PilotInput.new()
	result.read_axis = func(_id: int, axis: int) -> float: return float(axes.get(axis, 0.0))
	result.read_button = func(_id: int, button: int) -> bool: return bool(buttons.get(button, false))
	result.read_keys = func() -> Dictionary: return keys.duplicate()
	return result


func tick(sim: Node, input: RefCounted) -> Dictionary:
	var sample: Dictionary = input.sample(DT, true)
	check("controlled tick accepted", Fixtures.run(sim, sample.pilot, 1))
	return sample


func fixture() -> Dictionary:
	var result: Dictionary = Fixtures.install(root, Fixtures.lab())
	if not result.ok:
		check("fixture installs", false)
		return {}
	var error: String = Fixtures.reset(result.sim, result.plant.initial_frame(Fixtures.body(20.0)), FC.neutral_input())
	check("fixture resets at 20 m", error.is_empty())
	return result


func switch_pause_cut() -> void:
	keys = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0, arm = false, mode = false}
	axes = {0: 0.0, 1: 0.0, 2: -1.0, 3: 0.0}
	buttons = {20: false}
	var profile := Profile.defaults("radio", "radio_custom")
	profile.aux = {"arm": {"type": "button", "button": 20, "mode": "level"}}
	check("radio Arm AUX profile validates", Profile.validate(profile).ok)
	var input := pilot()
	input.connect_device(0, {name = "Synthetic radio", kind = "radio"}, profile)
	var f := fixture()
	if f.is_empty(): return
	var sim: Node = f.sim
	input.radio.on_motion(0, 2, -1.0)
	input.radio.on_button(0, 20, false)
	tick(sim, input)
	buttons[20] = true
	input.radio.on_button(0, 20, true)
	tick(sim, input)
	check("radio AUX switch arms before hold", sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED)
	var held: Dictionary = input.sample(DT, false) # A normal paused poll. No focus or source change.
	check("radio remains ready during ordinary hold", held.ready)
	var resumed := tick(sim, input) # Switch remains physically ON.
	check("first resumed sample is ready but reports arm OFF", resumed.ready and resumed.pilot[FC.IN_ARM] == 0.0)
	check("first resumed airborne tick disarms", sim.modes[FC.MODE_MOTOR] == FC.MOTOR_DISARMED)
	sim.free()


func keyboard_pause_control() -> void:
	keys = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0, arm = false, mode = false}
	var input := pilot()
	var f := fixture()
	if f.is_empty(): return
	var sim: Node = f.sim
	tick(sim, input)
	keys.arm = true
	tick(sim, input)
	check("keyboard toggle arms before hold", sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED)
	keys.arm = false
	input.sample(DT, false)
	var resumed := tick(sim, input)
	check("keyboard toggle survives the same hold", resumed.pilot[FC.IN_ARM] == 1.0 and sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED)
	sim.free()


func mode_button_arms() -> void:
	keys = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0, arm = false, mode = false}
	axes = {}
	buttons = {PilotInput.ARM_BUTTON: false}
	var profile := Profile.defaults("gamepad", "mode2")
	profile.aux = {"flight_mode": {"type": "button", "button": PilotInput.ARM_BUTTON, "mode": "level"}}
	check("flight mode on LB is accepted by profile validation", Profile.validate(profile).ok)
	var input := pilot()
	input.radio.confirmed_gamepad_connection = func(_id: int) -> bool: return true
	input.connect_device(1, {name = "Synthetic gamepad", known = true}, profile)
	var f := fixture()
	if f.is_empty(): return
	var sim: Node = f.sim
	input.radio.on_button(1, PilotInput.ARM_BUTTON, false)
	tick(sim, input) # ready OFF; also enables the flight mode AUX after physical release evidence
	buttons[PilotInput.ARM_BUTTON] = true
	input.radio.on_button(1, PilotInput.ARM_BUTTON, true)
	var pressed := tick(sim, input)
	check("LB selects Acro through Flight mode AUX", pressed.pilot[FC.IN_MODE] == float(FC.FLIGHT_ACRO))
	check("same LB press also arms the motor", pressed.pilot[FC.IN_ARM] == 1.0 and sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED)
	buttons[PilotInput.ARM_BUTTON] = false
	input.radio.on_button(1, PilotInput.ARM_BUTTON, false)
	tick(sim, input)
	buttons[PilotInput.ARM_BUTTON] = true
	input.radio.on_button(1, PilotInput.ARM_BUTTON, true)
	pressed = tick(sim, input)
	check("next LB mode press also disarms the motor", pressed.pilot[FC.IN_ARM] == 0.0 and sim.modes[FC.MODE_MOTOR] == FC.MOTOR_DISARMED)
	sim.free()


func _run() -> void:
	switch_pause_cut()
	keyboard_pause_control()
	mode_button_arms()
	print("quad input repro: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

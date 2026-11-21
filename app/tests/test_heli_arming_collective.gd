## A36 R8-G01: arming requires zero blade pitch within one degree both at the collective stick (premix pickup) and in
## the collective actually commanded to the rotor (postmix: trainer feedback, trim and clipped swash servos). The R8
## witness had premix +0.9 deg but +1.84 deg sent to the rotor and armed; it is now refused. Stock X-Cell, 100 m start.
extends SceneTree

const Session := preload("res://sim/helicopter_flight_session.gd")
const Lifecycle := preload("res://physics/rotorcraft/lifecycle.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	_run.call_deferred()


func check(label: String, passed: bool, detail: Variant = "") -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL %s — %s" % [label, str(detail)])


func _input(s: Node, throttle: float) -> void:
	s.commands = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = throttle}
	s.sim.inputs = PackedFloat64Array([0.0, 0.0, 0.0, throttle])


func _run() -> void:
	var s: Node = Session.new()
	s.physics_enabled = false
	s.input_enabled = false
	root.add_child(s)
	check("setup stock X-Cell", s.setup())
	s.set_start_altitude(100.0)
	check("airborne reference start", s.reset() and s.is_flyable())
	if failures > 0:
		_finish(s)
		return
	var model: Dictionary = s.aircraft.context.electronics_model
	var positive: Dictionary = Lifecycle.collective_for_pitch(model, "normal", deg_to_rad(0.9))
	check("+0.9 deg collective inverts on the authored curve", positive.ok)
	s.toggle_motor_arm() # the reference start is armed; disarm into hold
	check("disarmed in hold", not s.power.armed and s.zero_drive_hold)
	_input(s, float(positive.collective))
	# Negative control: at rest the trainer adds nothing, so premix and postmix are both +0.9 deg and arming is allowed.
	var stationary_post := rad_to_deg(s.commanded_collective_pitch())
	check("at rest the commanded collective equals the stick pickup", absf(stationary_post - 0.9) < 1.0e-9
		and absf(rad_to_deg(s.collective_pitch()) - 0.9) < 1.0e-9, stationary_post)
	check("arming is allowed when both are within one degree", s.toggle_motor_arm() and s.power.armed)
	s.toggle_motor_arm()
	# R8 witness: body rates p = -3, q = +3 rad/s; trainer feedback with clipped servos sends +1.84 deg to the rotor.
	var body: PackedFloat64Array = s.sim.state.duplicate()
	body[10] = -3.0
	body[11] = 3.0
	check("constructed body rates are accepted by a kernel reset", s.sim.reset(body) and s.zero_drive_hold and not s.power.armed)
	var premix := rad_to_deg(s.collective_pitch())
	var postmix := rad_to_deg(s.commanded_collective_pitch())
	# 1.8379 deg in the R8 record; 1.8517 deg since R5-F01 allocates the trim inside the clipped servo triple.
	check("witness: stick pickup +0.9 deg, rotor command above one degree", absf(premix - 0.9) < 1.0e-9
		and postmix > 1.8 and postmix < 1.9, [premix, postmix])
	check("arming is refused while the rotor would see more than one degree", not s.toggle_motor_arm() and not s.power.armed
		and str(s.pause_reason).contains("1 degree"), s.pause_reason)
	_finish(s)


func _finish(s: Node) -> void:
	s.free()
	print("heli arming collective: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)

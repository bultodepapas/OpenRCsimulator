# DR-19e (docs/plans/drone-racing.md §19): turtle mode, the crash flip. Requested while disarmed, it engages on the
# arming edge; the motors on the side opposite the stick spin in reverse (the quad flips toward the stick) and stop
# once the body's up axis is past horizontal; a request in flight is ignored; the flip neither breaks props nor ends the
# flight; one arm cycle consumes the input's request. Expected signs follow from the hub geometry (FRD) and the declared
# law constants, not from the implementation's own results.
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Plant := preload("res://physics/multirotor/controlled_plant.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const Session := preload("res://sim/multirotor/session.gd")
const Input_ := preload("res://input/multirotor_input.gd")
const Fixtures := preload("res://tests/mr_fixtures.gd")

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_flips()
	_in_flight()
	_input_request()
	print("turtle mode: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _up(s: Node) -> float:
	var q := RB._att(s.sim.state)
	return 1.0 - 2.0 * (q[1] * q[1] + q[2] * q[2]) # world-up component of the body's up axis


func _pilot(roll: float, pitch: float, arm: int, mode: int) -> PackedFloat64Array:
	return Fixtures.pilot(roll, pitch, 0.0, 0.0, arm, mode)


## A graded session lying upside down on flat ground, settled and disarmed.
func _inverted() -> Node:
	var s: Node = Session.new()
	root.add_child(s)
	s.prepare({}, {crash_model = "graded", start = "air", altitude_m = 0.15})
	var env: Dictionary = s.checkpoint()
	var state: PackedFloat64Array = env.kernel.state.duplicate()
	var q := M.q_from_euler(0.3, 0.0, PI)
	for k in 4:
		state[RB.ATT + k] = q[k]
	env.kernel.state = state
	env.kernel.previous = state.duplicate()
	var continuous: PackedFloat64Array = env.kernel.continuous.duplicate()
	for i in 4:
		continuous[i] = 0.0
	env.kernel.continuous = continuous
	s.restore_checkpoint(env)
	s.resume()
	for i in 240:
		s.tick_once(_pilot(0.0, 0.0, 0, FC.FLIGHT_ANGLE))
	return s


## Which side of the quad is low in the world: hub heights weighted by body hub · body stick (-pitch, roll).
func _pivot_side(s: Node, hubs: Array, roll: float, pitch: float) -> String:
	var q := RB._att(s.sim.state)
	# The hub heights weighted by how far each hub lies toward the stick: negative when the stick side is low.
	var tilt := 0.0
	for hub: PackedFloat64Array in hubs:
		var world := M.q_rotate(q, hub)
		var height: float = -(s.sim.state[RB.POS + 2] + world[2])
		tilt += (hub[0] * -pitch + hub[1] * roll) * height
	return "stick side low" if tilt < 0.0 else "stick side high (%.5f)" % tilt


func _commands(s: Node) -> PackedFloat64Array:
	return s.sim.aux.slice(FC.AUX_COMMAND, FC.AUX_COMMAND + 4)


func _flips() -> void:
	var hubs: Array = []
	for stick: Array in [[1.0, 0.0], [0.0, -1.0], [-0.7, 0.7], [0.0, 0.5]]:
		var label := "stick roll %.1f pitch %.1f" % [float(stick[0]), float(stick[1])]
		var s := _inverted()
		hubs = s.plant.config.hubs if hubs.is_empty() else hubs
		var settled := _up(s)
		s.tick_once(_pilot(0.0, 0.0, 0, FC.FLIGHT_TURTLE))
		s.tick_once(_pilot(0.0, 0.0, 1, FC.FLIGHT_TURTLE))
		var engaged: bool = s.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED and s.sim.modes[FC.MODE_FLIGHT] == FC.FLIGHT_TURTLE
		_check(label + ": settled inverted, turtle engages on the arming edge", settled < -0.8 and engaged)
		_check(label + ": a centred stick spins nothing", _commands(s) == PackedFloat64Array([0.0, 0.0, 0.0, 0.0]))
		s.tick_once(_pilot(float(stick[0]), float(stick[1]), 1, FC.FLIGHT_TURTLE))
		var cmds := _commands(s)
		# The side opposite the stick (FRD x forward, y right; stick vector (-pitch, roll)) runs in reverse.
		var signs_ok := true
		var full := float(stick[0]) * float(stick[0]) + float(stick[1]) * float(stick[1]) >= 0.99
		for i in 4:
			var hub: PackedFloat64Array = hubs[i]
			var lifts: bool = hub[0] * -float(stick[1]) + hub[1] * float(stick[0]) < 0.0
			signs_ok = signs_ok and (cmds[i] < 0.0 if lifts else cmds[i] == 0.0)
			if full and lifts:
				signs_ok = signs_ok and absf(cmds[i] + FC.TURTLE_MAX_COMMAND) < 1.0e-12
		_check(label + ": the motors opposite the stick reverse (full stick: the declared maximum)", signs_ok, str(cmds))
		var flipped_at := -1
		var reversed := false
		var pivot := ""
		for i in 720:
			s.tick_once(_pilot(float(stick[0]), float(stick[1]), 1, FC.FLIGHT_TURTLE))
			for k in 4:
				reversed = reversed or s.sim.continuous[k] < 0.0
			if pivot.is_empty() and absf(_up(s)) < 0.2:
				pivot = _pivot_side(s, hubs, float(stick[0]), float(stick[1]))
			if flipped_at < 0 and _up(s) > 0.9:
				flipped_at = i
		# Measured, not the controller's formula: halfway over, the quad pivots on its edge on the stick side (that side
		# stays low in the world) and the opposite side is up in the air: it flips toward the stick, as a crash flip does.
		_check(label + ": halfway over, the quad stands on its stick-side edge", pivot == "stick side low", pivot)
		var health: PackedFloat64Array = s.sim.continuous.slice(Plant.C_HEALTH, Plant.C_HEALTH + 4)
		_check(label + ": the props spin backwards and the quad lands upright within 1 s", reversed and flipped_at >= 0
			and flipped_at < 240 and _up(s) > 0.95, "%d ticks, final up %.3f" % [flipped_at, _up(s)])
		_check(label + ": upright, the motors stop with the stick still held", _commands(s) == PackedFloat64Array([0.0, 0.0, 0.0, 0.0]))
		_check(label + ": the flip ends no flight and breaks no prop", s.crash.is_empty() and s.fault_reason.is_empty()
			and health == PackedFloat64Array([1.0, 1.0, 1.0, 1.0]), str(s.crash) + " " + str(health))
		if stick == [1.0, 0.0]:
			# Turtle holds until a disarm; the next arm in Angle flies normally.
			s.tick_once(_pilot(0.0, 0.0, 1, FC.FLIGHT_ANGLE))
			var held: bool = s.sim.modes[FC.MODE_FLIGHT] == FC.FLIGHT_TURTLE
			s.tick_once(_pilot(0.0, 0.0, 0, FC.FLIGHT_ANGLE))
			s.tick_once(_pilot(0.0, 0.0, 1, FC.FLIGHT_ANGLE))
			_check("turtle holds while armed; after a disarm the next arm flies in Angle", held
				and s.sim.modes[FC.MODE_FLIGHT] == FC.FLIGHT_ANGLE and s.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED)
		s.free()
	# Inside the deadband nothing spins.
	var d := _inverted()
	d.tick_once(_pilot(0.0, 0.0, 0, FC.FLIGHT_TURTLE))
	d.tick_once(_pilot(0.0, 0.0, 1, FC.FLIGHT_TURTLE))
	for i in 60:
		d.tick_once(_pilot(0.8 * FC.TURTLE_DEADBAND, 0.0, 1, FC.FLIGHT_TURTLE))
	_check("a stick inside the deadband spins nothing", _commands(d) == PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
		and _up(d) < -0.8)
	d.free()


func _in_flight() -> void:
	var f: Node = Session.new()
	root.add_child(f)
	f.prepare({}, {crash_model = "graded", start = "air", altitude_m = 20.0})
	f.resume()
	f.tick_once(_pilot(0.0, 0.0, 0, FC.FLIGHT_ANGLE))
	f.tick_once(_pilot(0.0, 0.0, 1, FC.FLIGHT_ANGLE))
	var reversed := false
	for i in 24:
		f.tick_once(Fixtures.pilot(1.0, 0.0, 0.0, 0.4, 1, FC.FLIGHT_TURTLE))
		for k in 4:
			reversed = reversed or f.sim.continuous[k] < 0.0
	_check("a turtle request in flight is ignored (the mode stays Angle, no prop reverses)",
		f.sim.modes[FC.MODE_FLIGHT] == FC.FLIGHT_ANGLE and f.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED and not reversed)
	f.free()


func _input_request() -> void:
	var input: RefCounted = Input_.new()
	var keys := {}
	input.read_keys = func() -> Dictionary: return keys.duplicate()
	input.use_keyboard()
	_press(input, keys, "turtle")
	var sample: Dictionary = input.sample(1.0 / 240.0, true)
	_check("the turtle key toggles the request into the pilot input", input.turtle_requested()
		and int(sample.pilot[FC.IN_MODE]) == FC.FLIGHT_TURTLE and str(sample.raw.mode) == "turtle")
	_press(input, keys, "arm")
	var kept: bool = input.turtle_requested()
	_press(input, keys, "arm")
	sample = input.sample(1.0 / 240.0, true)
	_check("one arm cycle consumes the request: after the disarm the pilot flies the previous mode", kept
		and not input.turtle_requested() and int(sample.pilot[FC.IN_MODE]) == input.flight_mode()
		and input.flight_mode() != FC.FLIGHT_TURTLE)
	# After a crash the quad is usually still armed: the request waits (the pilot's mode keeps flying, so the mode
	# toggle still works) and survives the disarm; the next arming edge engages it, and that arm cycle consumes it.
	var flying: int = input.flight_mode()
	_press(input, keys, "arm")
	_press(input, keys, "turtle")
	sample = input.sample(1.0 / 240.0, true)
	var waits: bool = input.turtle_requested() and int(sample.pilot[FC.IN_MODE]) == flying and str(sample.raw.mode) != "turtle"
	_press(input, keys, "arm")
	sample = input.sample(1.0 / 240.0, true)
	var survives: bool = input.turtle_requested() and int(sample.pilot[FC.IN_MODE]) == FC.FLIGHT_TURTLE
	_press(input, keys, "arm")
	sample = input.sample(1.0 / 240.0, true)
	var engaged: bool = int(sample.pilot[FC.IN_MODE]) == FC.FLIGHT_TURTLE
	_press(input, keys, "arm")
	_check("a request made while armed waits for the disarm, engages on the next arm and is consumed by that cycle",
		waits and survives and engaged and not input.turtle_requested() and input.flight_mode() == flying,
		"%s %s %s" % [waits, survives, engaged])
	_press(input, keys, "turtle")
	input.reset_for_restart()
	_check("a pad restart clears the request", not input.turtle_requested())
	# Audit: with the controller's motor state reported (the activity does after each tick), a refused arm (high
	# throttle, an arm block) leaves the request pending; the next arm the controller accepts consumes it.
	_press(input, keys, "turtle")
	_press(input, keys, "arm") # the arming edge: the controller refuses it
	input.note_motor_state(false)
	_press(input, keys, "arm")
	input.note_motor_state(false)
	sample = input.sample(1.0 / 240.0, true)
	var pending: bool = input.turtle_requested() and int(sample.pilot[FC.IN_MODE]) == FC.FLIGHT_TURTLE
	_press(input, keys, "arm") # accepted: the controller arms in turtle
	input.note_motor_state(true)
	_press(input, keys, "arm")
	input.note_motor_state(false)
	_check("a refused arm keeps the turtle request; an accepted arm cycle consumes it", pending
		and not input.turtle_requested() and input.flight_mode() != FC.FLIGHT_TURTLE)


## One key press and release (two integrating samples); the reader returns a copy of `keys`.
func _press(input: RefCounted, keys: Dictionary, key: String) -> void:
	keys[key] = true
	input.sample(1.0 / 240.0, true)
	keys.erase(key)
	input.sample(1.0 / 240.0, true)

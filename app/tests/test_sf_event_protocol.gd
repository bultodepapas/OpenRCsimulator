# SF-04: one event protocol. A VehicleModel declares a boundary and the kernel locates it (physics/event_step.gd);
# a step_policy may return {state, events}; the kernel validates and records located events with the tick.
# Known answers: a value falling at a constant rate crosses zero at an analytic time.
extends SceneTree

const Sim := preload("res://sim/simulation.gd")
const VehicleModel := preload("res://sim/vehicle_model.gd")
const RB := preload("res://physics/rigid_body.gd")
const RK := preload("res://physics/integrator.gd")
const M := preload("res://physics/math3d.gd")
const EventStep := preload("res://physics/event_step.gd")
const Adapter := preload("res://physics/rotorcraft/simulation_step_adapter.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const AircraftCatalog := preload("res://app_state/aircraft_catalog.gd")

const FIXED_BUS := "res://data/aircraft/synthetic_stik_electric_4s.json"
const BATTERY := "res://data/aircraft/synthetic_stik_electric_4s_battery.json"
const RATE := 240.0 # the declared value falls by this much per second while positive

var _count := 0
var _failures := 0
var _signalled: Array = []


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_declared_event()
	_policy_results()
	_contract_shape()
	_simulation_configuration_guards()
	_adapter_contract()
	_electric_routes()
	_glow_route()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _level_state() -> PackedFloat64Array:
	return RB.make_state(M.v3(0.0, 0.0, -50.0), M.v3(15.0, 0.0, 0.0), M.q_identity(), M.v3(0.0, 0.0, 0.0))


## A body with no loads and one continuous value x: x' = -RATE until it rests at exactly zero. Negative trial
## values are the locator's continuation, so the derivative stays -RATE there and the trial map is linear.
func _falling_model() -> VehicleModel:
	var m := VehicleModel.new()
	m.continuous_size = 1
	m.stage = func(_body: PackedFloat64Array, continuous: PackedFloat64Array, _t: float) -> Dictionary:
		return {loads = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]),
			derivative = PackedFloat64Array([0.0 if continuous[0] == 0.0 else -RATE]),
			rotor_momentum = PackedFloat64Array([0.0, 0.0, 0.0])}
	m.events = [{type = "zero", index = RB.SIZE, transition = func(state: PackedFloat64Array, index: int) -> PackedFloat64Array:
		var out := state.duplicate()
		out[RB.RATE + 2] += 1.0 # a visible discrete change: yaw rate jumps at the boundary
		out[index] = 0.0
		return out}]
	return m


func _new_sim(model: VehicleModel, x0: float) -> Node:
	var sim: Node = Sim.new()
	root.add_child(sim)
	sim.set_model(model)
	sim.aux = PackedFloat64Array()
	sim.continuous = PackedFloat64Array([x0])
	sim.events_located.connect(func(tick: int, events: Array[Dictionary]) -> void: _signalled.append([tick, events.duplicate(true)]))
	return sim


func _declared_event() -> void:
	var sim: Node = _new_sim(_falling_model(), 0.0)
	var dt: float = sim.dt()
	sim.continuous = PackedFloat64Array([0.5 * RATE * dt]) # crosses zero halfway through the first tick
	_check("declared-event model resets", sim.reset(_level_state()), sim.fault_reason)
	_check("reset clears the event record", sim.last_events.is_empty())
	sim.step()
	_check("tick accepted", sim.fault_reason.is_empty() and sim.tick == 1, sim.fault_reason)
	_check("one event located", sim.last_events.size() == 1 and sim.last_events[0].type == "zero")
	var at: float = float(sim.last_events[0].time_s) if sim.last_events.size() == 1 else NAN
	_check("event time is the analytic crossing within the locator tolerance", absf(at - 0.5 * dt) <= 1e-9, "at %.15f expected %.15f" % [at, 0.5 * dt])
	_check("boundary value is exactly zero after the transition", sim.continuous[0] == 0.0)
	_check("transition applied at the boundary", sim.state[RB.RATE + 2] == 1.0)
	_check("events_located emitted once with the tick", _signalled.size() == 1 and _signalled[0][0] == 1 and _signalled[0][1][0].type == "zero")
	sim.step()
	_check("quiet tick clears the record and emits nothing", sim.last_events.is_empty() and _signalled.size() == 1 and sim.continuous[0] == 0.0)
	var snapshot: Dictionary = sim.checkpoint()
	_check("checkpoint excludes the diagnostic event record", not snapshot.is_empty() and not snapshot.has("last_events"))
	# Replay determinism: a second kernel with the same inputs reproduces states and events exactly.
	_signalled.clear()
	var twin: Node = _new_sim(_falling_model(), 0.5 * RATE * dt)
	_check("twin resets", twin.reset(_level_state()))
	twin.step()
	twin.step()
	_check("twin replays the same bytes and events", twin.state.to_byte_array() == sim.state.to_byte_array()
		and twin.continuous.to_byte_array() == sim.continuous.to_byte_array() and _signalled.size() == 1
		and float(_signalled[0][1][0].time_s) == at)
	sim.free()
	twin.free()


func _policy_results() -> void:
	var sim: Node = Sim.new()
	root.add_child(sim)
	var m := VehicleModel.new()
	m.continuous_size = 1
	m.block_loads = func(_b: PackedFloat64Array, _c: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	m.block_derivative = func(_b: PackedFloat64Array, _c: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		return PackedFloat64Array([0.0])
	var reported: Dictionary = {events = []}
	m.step_policy = func(combined: PackedFloat64Array, t: float, dt: float, f: Callable, k1: PackedFloat64Array) -> Variant:
		return {state = RK.rk4_step_at(combined, t, dt, f, k1), events = reported.events}
	sim.set_model(m)
	sim.aux = PackedFloat64Array()
	sim.continuous = PackedFloat64Array([1.0])
	_check("policy model resets", sim.reset(_level_state()), sim.fault_reason)
	var dt: float = sim.dt()
	reported.events = [{type = "tag", time_s = dt}]
	sim.step()
	_check("policy events at the tick end are recorded", sim.fault_reason.is_empty() and sim.last_events.size() == 1 and sim.last_events[0].type == "tag")
	var committed: PackedByteArray = sim.state.to_byte_array()
	reported.events = [{type = "late", time_s = 10.0 * dt}]
	sim.step()
	_check("an event outside the tick window faults the tick", sim.fault_reason.contains("malformed events"), sim.fault_reason)
	_check("the faulted tick rolled back", sim.tick == 1 and sim.state.to_byte_array() == committed and sim.last_events.size() == 1 and sim.last_events[0].type == "tag")
	reported.events = [{type = "", time_s = 0.5 * dt}]
	_check("reset clears the fault and the record", sim.reset(_level_state()) and sim.last_events.is_empty())
	sim.step()
	_check("an event without a type faults the tick", sim.fault_reason.contains("malformed events"))
	m.step_policy = func(_combined: PackedFloat64Array, _t: float, _dt: float, _f: Callable, _k1: PackedFloat64Array) -> Variant:
		return {events = []}
	_check("reset again", sim.reset(_level_state()))
	sim.step()
	_check("a policy result without a state faults the tick", sim.fault_reason.contains("no state"), sim.fault_reason)
	sim.free()


func _contract_shape() -> void:
	var m: VehicleModel = _falling_model()
	_check("declared event validates", VehicleModel.validate(m).ok, VehicleModel.validate(m).message)
	m.step_policy = func(c: PackedFloat64Array, _t: float, _dt: float, _f: Callable, _k1: PackedFloat64Array) -> Variant: return c
	_check("a declared event with a step_policy is refused", not VehicleModel.validate(m).ok)
	m.step_policy = Callable()
	m.events.append(m.events[0].duplicate())
	_check("two declared events are refused: compose them in a policy", not VehicleModel.validate(m).ok)
	m = _falling_model()
	m.events[0].index = 12
	_check("a body index is refused", not VehicleModel.validate(m).ok)
	m = _falling_model()
	m.events[0].erase("transition")
	_check("a missing transition is refused", not VehicleModel.validate(m).ok)
	m = _falling_model()
	m.events[0].index = RB.SIZE + 1
	var sim: Node = _new_sim(m, 1.0)
	_check("an index beyond the continuous block is refused at reset", not sim.reset(_level_state()))
	sim.free()
	m = _falling_model()
	m.substeps = func(_body: PackedFloat64Array, _continuous: PackedFloat64Array, _at: float) -> int: return 1
	m.substeps_joint = func(_body: PackedFloat64Array, _continuous: PackedFloat64Array, _at: float,
			_current_joint: Dictionary) -> int: return 1
	var both_substep_callbacks: Dictionary = VehicleModel.validate(m)
	_check("a model cannot select both substep callback forms", not both_substep_callbacks.ok
		and both_substep_callbacks.message.contains("at most one of substeps"), both_substep_callbacks.message)
	var no_joint_stage := VehicleModel.new()
	no_joint_stage.continuous_size = 1
	no_joint_stage.block_loads = func(_body: PackedFloat64Array, _continuous: PackedFloat64Array, _at: float) -> PackedFloat64Array:
		return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	no_joint_stage.block_derivative = func(_body: PackedFloat64Array, _continuous: PackedFloat64Array, _at: float) -> PackedFloat64Array:
		return PackedFloat64Array([0.0])
	no_joint_stage.substeps_joint = func(_body: PackedFloat64Array, _continuous: PackedFloat64Array, _at: float,
			_current_joint: Dictionary) -> int: return 1
	var missing_joint_stage: Dictionary = VehicleModel.validate(no_joint_stage)
	_check("a joint substep callback requires the joint stage evaluator", not missing_joint_stage.ok
		and missing_joint_stage.message.contains("requires a joint stage evaluator"), missing_joint_stage.message)


func _joint_substep_model() -> VehicleModel:
	var model := VehicleModel.new()
	model.continuous_size = -1
	model.stage = func(_body: PackedFloat64Array, _continuous: PackedFloat64Array, _at: float) -> Dictionary:
		return {loads = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]),
			derivative = PackedFloat64Array([0.0]), rotor_momentum = PackedFloat64Array([0.0, 0.0, 0.0])}
	model.substeps_joint = func(_body: PackedFloat64Array, _continuous: PackedFloat64Array, _at: float,
			_current_joint: Dictionary) -> int: return 1
	return model


func _simulation_configuration_guards() -> void:
	var no_continuous := Sim.new()
	var no_continuous_model := _joint_substep_model()
	_check("joint substep model installs before live layout is known", no_continuous.set_model(no_continuous_model))
	no_continuous.continuous = PackedFloat64Array()
	var empty_layout: Dictionary = no_continuous.prepare_reset(_level_state())
	_check("simulation configuration rejects joint substeps without continuous state",
		not no_continuous._configuration_is_valid() and not empty_layout.get("ok", false),
		str(empty_layout.get("message", "")))
	no_continuous.free()

	var no_stage := Sim.new()
	var no_stage_model := _joint_substep_model()
	_check("joint substep model with a stage installs", no_stage.set_model(no_stage_model))
	no_stage.continuous = PackedFloat64Array([0.0])
	no_stage_model.stage = Callable()
	no_stage_model.block_loads = func(_body: PackedFloat64Array, _continuous: PackedFloat64Array, _at: float) -> PackedFloat64Array:
		return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	no_stage_model.block_derivative = func(_body: PackedFloat64Array, _continuous: PackedFloat64Array, _at: float) -> PackedFloat64Array:
		return PackedFloat64Array([0.0])
	var missing_live_stage: Dictionary = no_stage.prepare_reset(_level_state())
	_check("simulation configuration rejects joint substeps after the joint stage is removed",
		not no_stage._configuration_is_valid() and not missing_live_stage.get("ok", false),
		str(missing_live_stage.get("message", "")))
	no_stage.free()

	var both_callbacks := Sim.new()
	var both_callbacks_model := _joint_substep_model()
	_check("joint substep model installs before callback mutation", both_callbacks.set_model(both_callbacks_model))
	both_callbacks.continuous = PackedFloat64Array([0.0])
	both_callbacks_model.substeps = func(_body: PackedFloat64Array, _continuous: PackedFloat64Array, _at: float) -> int: return 1
	var duplicate_selectors: Dictionary = both_callbacks.prepare_reset(_level_state())
	_check("simulation configuration rejects both substep callback forms after model mutation",
		not both_callbacks._configuration_is_valid() and not duplicate_selectors.get("ok", false),
		str(duplicate_selectors.get("message", "")))
	both_callbacks.free()


func _adapter_contract() -> void:
	# The rotorcraft adapter keeps its own predictor but reports its events: a rotor at 1 rad/s decelerating at
	# 480 rad/s² stops a little after the tick starts; the located stop is inside the tick.
	var state := PackedFloat64Array()
	state.resize(RB.SIZE + 6)
	state[RB.ATT] = 1.0
	state[13] = 1.0
	var derivative := func(s: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		var d := PackedFloat64Array()
		d.resize(s.size())
		d[13] = -480.0 if s[13] > 0.0 else 0.0
		return d
	var result: Variant = Adapter.step(state, 2.0, 1.0 / 240.0, derivative, derivative.call(state, 2.0))
	_check("adapter returns a dictionary with state and events", result is Dictionary and result.has("state") and result.has("events"))
	if result is Dictionary:
		_check("adapter located the stop inside the tick", result.events.size() == 1 and result.events[0].type == "rotor_stop"
			and float(result.events[0].time_s) >= 2.0 and float(result.events[0].time_s) <= 2.0 + 1.0 / 240.0 and result.state[13] == 0.0,
			str(result.events))


func _electric_session(path: String) -> Node:
	var session: Node = FlightSession.new()
	session.input_enabled = false
	session.physics_enabled = false
	session.setup(path)
	root.add_child(session)
	return session


func _electric_routes() -> void:
	var fixed: Node = _electric_session(FIXED_BUS)
	_check("fixed-bus electric fixture flies", fixed.is_flyable(), fixed.pause_reason)
	if fixed.is_flyable():
		fixed.reset()
		var model: VehicleModel = fixed.sim.model
		_check("fixed-bus route declares the rotor stop and owns no step policy", model.events.size() == 1
			and model.events[0].type == "rotor_stop" and not model.step_policy.is_valid())
		# A windmilling propeller never stops in the airstream: hold the airframe still with the source off and a
		# slow rotor, so friction brings the shaft to rest inside a tick.
		var index: int = int(model.events[0].index)
		_bring_to_rest(fixed, index - RB.SIZE)
		var located: Dictionary = _run_until_event(fixed, 480)
		_check("source off at rest: the kernel locates the rotor stop", not located.is_empty() and located.type == "rotor_stop", str(located))
		if not located.is_empty():
			_check("rotor stop time lies inside its tick", float(located.time_s) <= fixed.sim.time() and float(located.time_s) >= fixed.sim.time() - fixed.sim.dt())
			_check("rotor rests at exactly zero after the stop", fixed.sim.continuous[index - RB.SIZE] == 0.0)
	fixed.free()
	var battery: Node = _electric_session(BATTERY)
	_check("finite-battery fixture flies", battery.is_flyable(), battery.pause_reason)
	if battery.is_flyable():
		battery.reset()
		var model: VehicleModel = battery.sim.model
		_check("battery route keeps its composed policy and declares no kernel event", model.step_policy.is_valid() and model.events.is_empty())
		_bring_to_rest(battery, battery._rotor_index())
		var located: Dictionary = _run_until_event(battery, 480)
		_check("source off at rest: the composed policy reports the rotor stop", not located.is_empty() and located.type == "rotor_stop", str(located))
	battery.free()


## Source off, airframe held still, shaft slowed to a crawl: the only remaining torque is friction.
func _bring_to_rest(session: Node, rotor_offset: int) -> void:
	session.engine_running = false
	var body: PackedFloat64Array = session.sim.state.duplicate()
	for i in 3:
		body[RB.VEL + i] = 0.0
		body[RB.RATE + i] = 0.0
	session.sim.state = body
	session.sim.previous = body.duplicate()
	session.sim.continuous[rotor_offset] = 30.0
	session.sim.aux[0] = 30.0


func _run_until_event(session: Node, max_ticks: int) -> Dictionary:
	for _i in max_ticks:
		session.sim.step()
		if not session.sim.fault_reason.is_empty():
			return {}
		if not session.sim.last_events.is_empty():
			return session.sim.last_events[0]
	return {}


func _glow_route() -> void:
	var entry: Dictionary = AircraftCatalog.entry("stik-glow-55ax-2t")
	if entry.is_empty():
		_check("glow fixture present", false)
		return
	var session: Node = _electric_session(str(entry.data))
	_check("glow Stik flies", session.is_flyable(), session.pause_reason)
	if session.is_flyable():
		session.reset()
		for _i in 24:
			session.sim.step()
		# The cut command edits state between ticks; an in-tick stop is the tank running dry.
		session.sim.continuous[1] = session.aircraft.model.propulsion.glow.unusable_fuel_kg + 1.0e-7 # usable kg above residue
		var located: Dictionary = _run_until_event(session, 240)
		var types: Array = []
		for event in session.sim.last_events:
			types.append(event.type)
		_check("the tank running dry is located as a fuel_exhausted boundary and a glow_stopped transition",
			types.has("fuel_exhausted") and types.has("glow_stopped") and session.glow_state().get("stop_reason", "") == "fuel_exhausted",
			str(session.sim.last_events) + " " + str(session.glow_state().get("stop_reason", "")))
	session.free()

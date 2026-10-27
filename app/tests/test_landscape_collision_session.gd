extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
const RB := preload("res://physics/rigid_body.gd")
const Recorder := preload("res://sim/recorder.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	_test_soft_impulse_trace_and_checkpoint()
	_test_terminal_toi_and_reset()
	_test_no_hit_parity()
	print("landscape collision session: %d checks, %d failures" % [checks, failures])	
	quit(1 if failures > 0 else 0)


func _test_soft_impulse_trace_and_checkpoint() -> void:
	var world := _lamp_world(5.0)
	var session := _new_session(world)
	if session == null:
		return
	var recorder := Recorder.new(session.sim)
	recorder.start(session.trace_meta())
	_set_state(session, _state(4.90, 0.0, -4.0, 8.0, 0.0, 0.0))
	session.sim.set_paused(false)
	session.sim.step()
	var event = session.last_scenery_event()
	_check("subterminal fixture produces a nonfatal scenery event", event != null and not event.terminal
		and event.response_status == "dissipative_impulse")
	_check("frangible impulse reverses the incoming normal motion", event != null
		and session.sim.state[RB.VEL] < 0.0 and session.crash.is_empty())
	_check("nonfatal pose stops at TOI instead of the integrated endpoint", session.sim.state[RB.POS] < 4.933334)
	_check("trace records the accepted post-impulse state", recorder.trace.row_count() == 2
		and recorder.trace.value(1, "north_m") == session.sim.state[RB.POS]
		and recorder.trace.value(1, "u_mps") == session.sim.state[RB.VEL])
	var checkpoint: Dictionary = session.checkpoint()
	_check("configured collision world upgrades checkpoint identity to v7", checkpoint.get("format") == "openrc-flight-checkpoint v7"
		and checkpoint.get("collision_world_identity", "") == world.identity)
	var trace_state: PackedFloat64Array = session.sim.state.duplicate()
	_check("matching v7 checkpoint restores collision-enabled state", session.restore_checkpoint(checkpoint)
		and session.sim.state == trace_state and session.last_scenery_event() == null)
	_check("collision world cannot be removed after the flight advances", not session.set_collision_world({})
		and session.collision_world().identity == world.identity)
	var receiver := _new_session(_lamp_world(6.0))
	if receiver != null:
		var before := var_to_bytes(receiver.sim.checkpoint())
		_check("different obstacle identity rejects restore without mutating simulation",
			not receiver.restore_checkpoint(checkpoint) and var_to_bytes(receiver.sim.checkpoint()) == before)
		receiver.free()
	recorder.detach()
	session.reset()
	_check("reset clears transient nonfatal contact state but keeps world identity",
		session.start_error.is_empty() and session.last_scenery_event() == null and session.collision_world().identity == world.identity)
	session.free()


func _test_terminal_toi_and_reset() -> void:
	var session := _new_session(_lamp_world(5.0))
	if session == null:
		return
	_set_state(session, _state(0.0, 0.0, -4.0, 2400.0, 0.0, 0.0))
	session.sim.set_paused(false)
	session.sim.step()
	var impact = session.crash.get("impact")
	_check("hard high-speed fixture routes through scenery crash presentation",
		impact != null and impact.trigger == "scenery" and session.sim.paused)
	_check("crash state is rewound to the first thin-pole contact",
		absf(session.sim.state[RB.POS] - 4.93) < 0.02 and session.sim.state[RB.POS] < 5.0)
	_check("terminal impact retains contact pose and normal", impact != null
		and impact.detected_state[RB.POS] < 5.0 and impact.normal_ned.size() == 3)
	session.reset()
	_check("reset clears terminal event and keeps the installed world",
		session.start_error.is_empty() and session.crash.is_empty() and session.last_scenery_event() == null
		and session.collision_world().identity == CollisionWorld.build(
			{pilot = {north = 0.0, east = 0.0, down = 0.0}, objects = []}, {groups = []},
			{fixtures = [{id = "lamp", type = "flood", north = 5.0, east = 0.0, height = 8.0}]}).world.identity)
	session.free()


func _test_no_hit_parity() -> void:
	var legacy := _new_session({})
	var enabled := _new_session(_lamp_world(1000.0))
	if legacy == null or enabled == null:
		if legacy != null:
			legacy.free()
		if enabled != null:
			enabled.free()
		return
	_check("no-world checkpoint keeps the legacy version family", legacy.checkpoint().get("format", "").ends_with("v1")
		or legacy.checkpoint().get("format", "").ends_with("v6"))
	var state := _state(0.0, 0.0, -50.0, 30.0, 1.0, 0.0)
	_set_state(legacy, state)
	_set_state(enabled, state)
	legacy.sim.set_paused(false)
	enabled.sim.set_paused(false)
	legacy.sim.step()
	enabled.sim.step()
	_check("no-hit contact world preserves exact simulation state", var_to_bytes(legacy.sim.state) == var_to_bytes(enabled.sim.state))
	_check("no-hit world emits no transient event", enabled.last_scenery_event() == null and enabled.crash.is_empty())
	legacy.free()
	enabled.free()


func _new_session(world: Dictionary) -> Node:
	var session: Node = FlightSession.new()
	session.setup()
	root.add_child(session)
	session.input_enabled = false
	var aircraft: Dictionary = session.aircraft
	aircraft.model.crash_hull = PackedFloat64Array([0.0, 0.0, 0.0])
	session.aircraft = aircraft
	session.sim.continuous = PackedFloat64Array()
	# Body-only fixture, but a transactional session reset re-stages the aircraft's continuous wheel slots;
	# zero block evaluators keep that reset candidate valid instead of refused and rolled back.
	session.sim.model.block_loads = func(_body: PackedFloat64Array, _extra: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	session.sim.model.block_derivative = func(_body: PackedFloat64Array, extra: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		var rates := PackedFloat64Array()
		rates.resize(extra.size())
		return rates
	session.sim.model.stage = Callable()
	session.sim.model.stage_rotor_momentum = Callable()
	session.sim.model.block_aux = Callable()
	session.sim.model.step_policy = Callable()
	session.sim.model.pre_tick = func(aux: PackedFloat64Array, _inputs: PackedFloat64Array, _dt: float) -> PackedFloat64Array:
		return aux
	session.sim.model.rotor_momentum = func(_aux: PackedFloat64Array) -> PackedFloat64Array:
		return PackedFloat64Array()
	session.sim.model.loads = func(_state: PackedFloat64Array, _time_s: float) -> PackedFloat64Array:
		return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	session.sim.reset(session.sim.state.duplicate())
	if not world.is_empty() and not session.set_collision_world(world):
		_check("collision world installs at tick-zero boundary", false)
		session.free()
		return null
	_check("session remains flyable with scalar collision world", session.is_flyable())
	return session


func _lamp_world(north: float) -> Dictionary:
	var result: Dictionary = CollisionWorld.build(
		{pilot = {north = 0.0, east = 0.0, down = 0.0}, objects = []}, {groups = []},
		{fixtures = [{id = "lamp", type = "flood", north = north, east = 0.0, height = 8.0}]})
	_check("synthetic lamp collision world builds", result.ok)
	return result.world


func _set_state(session: Node, state: PackedFloat64Array) -> void:
	session.sim.state = state.duplicate()
	session.sim.previous = state.duplicate()
	session.sim.inputs = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])


func _state(north: float, east: float, down: float, vn: float, ve: float, vd: float) -> PackedFloat64Array:
	return RB.make_state(PackedFloat64Array([north, east, down]), PackedFloat64Array([vn, ve, vd]),
		PackedFloat64Array([1.0, 0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]))


func _check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label)
	else:
		print("ok ", label)


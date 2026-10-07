# E0b5: experimental axial-speed lag. No production aircraft enables it.
extends SceneTree

const Fixture = preload("res://tests/test_wash_profile.gd")
const AD = preload("res://physics/aircraft_data.gd")
const Flight = preload("res://sim/flight_session.gd")
const Sim = preload("res://sim/simulation.gd")
const W = preload("res://physics/wash_transport.gd")
const S = preload("res://physics/slipstream.gd")
const Air = preload("res://physics/air_data.gd")
const Prop = preload("res://physics/propulsion.gd")
const RB = preload("res://physics/rigid_body.gd")
const Catalog = preload("res://app_state/aircraft_catalog.gd")
var checks: int = 0
var failures: int = 0


static func raw_fixture() -> Dictionary:
	var raw: Dictionary = Fixture.combined_raw()
	raw.propulsion.propeller.slipstream.transport_speed_floor = {
		value = 1.0, unit = "m/s", kind = "estimated",
		source = "E0b5 zero-flow decay regularizer; not measured Stik transport speed"}
	return raw


static func configure(flight: Node) -> bool:
	flight.setup()
	flight.input_enabled = false
	if not flight._apply(AD.validate_and_derive(raw_fixture())):
		return false
	flight.reset()
	return flight.is_flyable()


func check(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	print(("ok " if ok else "FAIL ") + label + " " + detail)
	if not ok:
		failures += 1


func _initialize() -> void:
	var data: Dictionary = AD.validate_and_derive(raw_fixture())
	check("provenanced transport fixture accepted", data.ok, str(data.errors))
	if not data.ok:
		quit(1)
		return
	_validation()
	for speed: float in [0.0, 15.0]:
		_response(data.model, speed)
	_session_checks()
	_refinement()
	for id: String in Catalog.ids():
		var legacy: Node = Flight.new()
		legacy.setup(Catalog.entry(id).data)
		check(id + " production keeps empty continuous state", legacy.sim.continuous.is_empty())
		legacy.free()
	print("E0b5 transport: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _validation() -> void:
	for mutation: int in 6:
		var raw: Dictionary = raw_fixture()
		var ss: Dictionary = raw.propulsion.propeller.slipstream
		match mutation:
			0: ss.transport_speed_floor.value = 0.0
			1: ss.transport_speed_floor.value = NAN
			2: ss.transport_speed_floor.unit = "s"
			3: ss.transport_speed_floor.erase("source")
			4: ss.swirl_factor.value = 0.1
			5: ss.erase("edge_fraction")
		check("invalid transport configuration %d rejected" % mutation, not AD.validate_and_derive(raw).ok)


func _response(model: Dictionary, speed: float) -> void:
	var prop: Dictionary = model.propulsion
	var v: PackedFloat64Array = PackedFloat64Array([speed, 0, 0])
	var rpm: float = prop.max_rpm
	var target: PackedFloat64Array = W.target(v, rpm, prop, 1.225)
	var sim: Node = Sim.new()
	sim.gravity = 0.0
	sim.continuous = PackedFloat64Array([0, 0, 0])
	sim.continuous_loads = func(_s: PackedFloat64Array, _z: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		return PackedFloat64Array([0, 0, 0, 0, 0, 0])
	sim.continuous_derivative = func(_s: PackedFloat64Array, z: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		return W.derivative(v, rpm, prop, 1.225, z)
	sim.reset(PackedFloat64Array([0, 0, -100, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0]))
	var tau: PackedFloat64Array = PackedFloat64Array()
	for piece: Dictionary in prop.slipstream.pieces:
		tau.append((float(piece.root[0]) - float(prop.slipstream.hub[0])) / target[1])
	var crossing: PackedFloat64Array = PackedFloat64Array([0, 0, 0])
	var worst: float = 0.0
	for tick: int in 120:
		var before: PackedFloat64Array = sim.continuous.duplicate()
		sim.step()
		for i: int in tau.size():
			var expected: float = target[0] * (1.0 - exp(-sim.time()/tau[i]))
			worst = maxf(worst, absf(sim.continuous[i]-expected)/target[0])
			var threshold: float = target[0]*(1.0-exp(-1.0))
			if crossing[i] == 0.0 and sim.continuous[i] >= threshold:
				crossing[i] = sim.time()-sim.dt()+sim.dt()*(threshold-before[i])/(sim.continuous[i]-before[i])
	check("fixed %.0f m/s speed step matches exponential" % speed, worst < 2e-6, "worst relative error " + String.num_scientific(worst))
	for i: int in tau.size():
		check("piece %d at %.0f m/s reaches 63.2%% at distance/disc-speed ±5%%" % [i, speed],
			absf(crossing[i]/tau[i]-1.0) < 0.05, "tau %.6f s; measured %.6f s" % [tau[i], crossing[i]])
	sim.free()


func _session_checks() -> void:
	var flight: Node = Flight.new()
	check("transport session trims and starts", configure(flight))
	var initial: PackedFloat64Array = flight.sim.continuous.duplicate()
	check("reset settles each piece; public body/CSV remains 13 values", initial.size() == 3 and flight.sim.state.size() == RB.SIZE
		and initial == flight._settled_wash(flight.sim.state, flight.sim.aux))
	var s: PackedFloat64Array = flight.sim.state
	var quasi: PackedFloat64Array = preload("res://physics/dynamics.gd").loads(s, flight.aircraft.model,
		flight._deflections(flight.sim.aux), flight.sim.aux[0], 1.225, PackedFloat64Array([0, 0, 0]),
		flight.sim.aux[flight.downwash_index()])
	check("settled lag reproduces quasi-static loads exactly", quasi.to_byte_array() == flight._wash_loads(s, initial, 0.0).to_byte_array())
	var empty_wash: PackedFloat64Array = PackedFloat64Array([0, 0, 0])
	check("stage wash state changes actual tail loads", quasi != flight._wash_loads(s, empty_wash, 0.0))
	var stages: Array = []
	var real_loads: Callable = flight.sim.continuous_loads
	flight.sim.continuous = empty_wash
	flight.sim.reset(s)
	flight.sim.continuous_loads = func(body: PackedFloat64Array, z: PackedFloat64Array, t: float) -> PackedFloat64Array:
		stages.append(z.duplicate())
		return real_loads.call(body, z, t)
	flight.sim.step()
	check("real session loads see changing lag at all RK stages", stages.size() == 4 and stages[0] != stages[1] and stages[1] != stages[2] and stages[2] != stages[3])
	flight.sim.continuous_loads = real_loads
	var cp: Dictionary = flight.checkpoint()
	for tick: int in 60:
		flight.sim.step()
	var expected: PackedByteArray = _bits(flight)
	check("nonsettled transport checkpoint accepted", flight.restore_checkpoint(cp))
	for tick: int in 60:
		flight.sim.step()
	check("mid-lag checkpoint replay is byte-exact", expected == _bits(flight))
	flight.reset()
	check("reset removes prior lag history", flight.sim.continuous == initial)
	for malformed: PackedFloat64Array in [PackedFloat64Array(), PackedFloat64Array([0, 0])]:
		flight.sim.continuous = malformed
		check("reset refuses transport layout mismatch without indexing pieces", not flight.sim.reset(s)
			and flight.sim.continuous == initial)
		flight.reset()
	check("trace identifies continuous transport separately", flight.trace_meta().propwash_model == "tail-slipstream-axial-transport-v1")
	# Stopped source must decay, not erase its residual immediately or hold it forever.
	flight.engine_running = false
	flight.sim.step()
	check("engine stop leaves finite decaying wash", flight.sim.continuous[0] > 0 and flight.sim.continuous[0] < initial[0])
	var model: Dictionary = flight.aircraft.model
	var air: Dictionary = Air.compute(s, PackedFloat64Array([0, 0, 0]), 1.225)
	var d: Dictionary = flight._deflections(flight.sim.aux)
	var residual: PackedFloat64Array = S.loads(s, air, d, model, 0.0, 1.225, 0.3, initial)
	check("stopped-source residual still reaches tail loads", residual != PackedFloat64Array([0, 0, 0, 0, 0, 0]))
	var reverse: PackedFloat64Array = PackedFloat64Array([-20, 0, 0])
	check("reverse flow cuts source and residual occupancy", W.target(reverse, model.propulsion.max_rpm, model.propulsion, 1.225)[0] == 0.0
		and S.loads(s, {v_air = reverse}, d, model, model.propulsion.max_rpm, 1.225, 0.3, initial) == PackedFloat64Array([0, 0, 0, 0, 0, 0]))
	check("zero-flow stopped source decays using finite floor", W.target(PackedFloat64Array([0, 0, 0]), 0.0, model.propulsion, 1.225) == PackedFloat64Array([0, 1]))
	var field: Dictionary = preload("res://data/field_loader.gd").load_from().field
	var spot: Dictionary = preload("res://physics/ground_start.gd").threshold(field)
	flight.set_field(field)
	check("runway reset initializes settled transport", flight.reset_on_runway(spot.north, spot.east, spot.heading)
		and flight.sim.continuous == flight._settled_wash(flight.sim.state, flight.sim.aux))
	check("switch back to production drops continuous layout", flight._apply(AD.load_file(Flight.Scenarios.AIRCRAFT)))
	flight.reset()
	check("production reset has no lag state", flight.sim.continuous.is_empty() and flight.is_flyable())
	flight.free()


func _bits(flight: Node) -> PackedByteArray:
	return flight.sim.state.to_byte_array()+flight.sim.continuous.to_byte_array()+flight.sim.aux.to_byte_array()+flight.sim.last_loads.to_byte_array()


func _run_refinement(hz: int) -> PackedFloat64Array:
	Engine.physics_ticks_per_second = hz
	var flight: Node = Flight.new()
	configure(flight)
	# Isolate the body/wash coupling: RPM, servos, downwash and anchors are held. These pre-existing
	# sampled subsystems have their own lower-order error; they must not mask this coupling's order.
	flight.sim.pre_step = func(a: PackedFloat64Array, _u: PackedFloat64Array, _dt: float) -> PackedFloat64Array: return a
	flight.sim.continuous = PackedFloat64Array([0, 0, 0])
	flight.sim.reset(flight.sim.state)
	for tick: int in roundi(hz/5.0):
		flight.sim.step()
	var result: PackedFloat64Array = flight.sim.state.duplicate()
	result.append_array(flight.sim.continuous)
	if not flight.sim.fault_reason.is_empty():
		result.fill(NAN)
	flight.free()
	return result


func _refinement() -> void:
	var hz_before: int = Engine.physics_ticks_per_second
	var a: PackedFloat64Array = _run_refinement(60)
	var b: PackedFloat64Array = _run_refinement(120)
	var c: PackedFloat64Array = _run_refinement(240)
	var reference: PackedFloat64Array = _run_refinement(960)
	Engine.physics_ticks_per_second = hz_before
	var errors: Array[float] = []
	for result: PackedFloat64Array in [a, b, c]:
		var error: float = 0.0
		for i: int in result.size():
			error = maxf(error, absf(result[i]-reference[i]))
		errors.append(error)
	check("real body/wash coupling converges at fourth order with sampled inputs held",
		errors[0]/errors[1] > 10.0 and errors[1]/errors[2] > 10.0,
		"errors %s; ratios %.2f %.2f" % [errors, errors[0]/errors[1], errors[1]/errors[2]])

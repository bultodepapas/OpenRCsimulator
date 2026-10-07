# Gate P: the GDScript implementation remains the numerical oracle.
extends SceneTree
const Native := preload("res://tests/gate_p/adapter.gd")
const Oracle := preload("res://physics/slipstream.gd")
const Flight := preload("res://sim/flight_session.gd")
const Sim := preload("res://sim/simulation.gd")
const Air := preload("res://physics/air_data.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Policy := preload("res://tests/replay_policy.gd")
const Propulsion := preload("res://physics/propulsion.gd")
var checks: int = 0
var failures: int = 0
var exact: int = 0
var worst: float = 0.0
var nonzero: int = 0
# Mixed absolute/relative scale: max(1 N or N*m, |reference component|).
# Native arithmetic preserves order; a small libm difference is allowed across toolchains.
const LOAD_TOLERANCE: float = 1e-12

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures == 1:
			printerr("FIRST FAILURE: ", label)

func compare(label: String, state: PackedFloat64Array, velocity: PackedFloat64Array,
		d: Dictionary, model: Dictionary, rpm: float, rho: float) -> void:
	var air: Dictionary = {v_air = velocity}
	var expected: PackedFloat64Array = Oracle.loads(state, air, d, model, rpm, rho)
	var actual: PackedFloat64Array = Native.loads(state, air, d, model, rpm, rho)
	if expected != PackedFloat64Array([0, 0, 0, 0, 0, 0]):
		nonzero += 1
	var ok: bool = actual.size() == 6
	if actual.to_byte_array() == expected.to_byte_array():
		exact += 1
	if ok:
		for i in 6:
			var error: float = INF
			if is_finite(actual[i]) and is_finite(expected[i]):
				error = absf(actual[i] - expected[i]) / maxf(1.0, absf(expected[i]))
			worst = maxf(worst, error)
			ok = ok and error <= LOAD_TOLERANCE
	if not ok and failures == 0:
		printerr("first load mismatch: ", label, " expected=", expected, " actual=", actual)
	check(label, ok)

func _initialize() -> void:
	if not Native.available():
		printerr("native backend could not load")
		quit(1)
		return
	var flight: Node = Flight.new()
	flight.setup("res://data/aircraft/p51d_mustang_120.json")
	var original: Dictionary = flight.aircraft.model.duplicate(true)
	var state: PackedFloat64Array = flight.sim.state.duplicate()
	var d: Dictionary = {elevator = 0.0, rudder = 0.0, aileron_left = 0.0, aileron_right = 0.0}
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 728114
	for sample in 10000:
		var model: Dictionary = original.duplicate(true)
		var velocity: PackedFloat64Array = M.v3(rng.randf_range(-45, 70), rng.randf_range(-20, 20), rng.randf_range(-30, 30))
		if sample % 2 == 0:
			velocity = M.v3(rng.randf_range(0, 30), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		for axis in 3:
			state[RB.RATE+axis] = rng.randf_range(-8, 8)
		d.elevator = rng.randf_range(-0.8, 0.8)
		d.rudder = rng.randf_range(-0.8, 0.8)
		# Live edits prove the native boundary does not retain stale geometry/configuration.
		model.cg_le[0] += rng.randf_range(-0.2, 0.2)
		model.surfaces.horizontal.incidence += rng.randf_range(-0.2, 0.2)
		model.propulsion.slipstream.wash_factor[0] *= rng.randf_range(0.5, 1.5)
		model.propulsion.slipstream.swirl_factor *= rng.randf_range(0.0, 2.0)
		var rpm: float = rng.randf_range(0, 7000)
		compare("random case %d" % sample, state, velocity, d, model, rpm, rng.randf_range(0.5, 1.5))
	for rpm in [0.0, Propulsion.STOPPED_RPM - 1e-8, Propulsion.STOPPED_RPM, 1000.0, 5000.0]:
		for velocity in [M.v3(0, 0, 0), M.v3(0, 0, 1), M.v3(-30, 0, 0), M.v3(30, 0, 0)]:
			compare("zero/reverse/stopped edge", state, velocity, d, original, rpm, Air.RHO_SEA_LEVEL)
	var no_axis: Dictionary = original.duplicate(true)
	no_axis.propulsion.erase("axis")
	compare("implicit straight shaft", state, M.v3(20, 0, 0), d, no_axis, 5000.0, Air.RHO_SEA_LEVEL)
	check("nonzero wash cases actually exercised", nonzero > 1000)
	var v: PackedFloat64Array = M.v3(20, 0, 0)
	var tq_full: PackedFloat64Array = Propulsion.thrust_torque(v, 5000, original.propulsion, Air.RHO_SEA_LEVEL)
	var tq: PackedFloat64Array = PackedFloat64Array([tq_full[0], tq_full[1]])
	var bad_velocity: PackedFloat64Array = M.v3(NAN, 0.0, 0.0)
	var refusal: PackedFloat64Array = Native.loads(state, {v_air = bad_velocity}, d, original, 5000.0, Air.RHO_SEA_LEVEL)
	var refusal_ok: bool = refusal.size() == 6
	if refusal_ok:
		for component in refusal:
			refusal_ok = refusal_ok and not is_finite(component)
	check("adapter maps native refusal to six non-finite loads", refusal_ok)
	var valid_boundary: PackedFloat64Array = Native.backend.tail_loads(state, v, d, original, tq, Air.RHO_SEA_LEVEL)
	var valid_boundary_ok: bool = valid_boundary.size() == 6
	if valid_boundary_ok:
		for component in valid_boundary:
			valid_boundary_ok = valid_boundary_ok and is_finite(component)
	check("valid native boundary returns six finite loads", valid_boundary_ok)
	for bad_state in [PackedFloat64Array(), PackedFloat64Array([NAN]), state.slice(0, 12)]:
		check("malformed state refused", Native.backend.tail_loads(bad_state, v, d, original, tq, Air.RHO_SEA_LEVEL).is_empty())
	var bad_state_nonfinite: PackedFloat64Array = state.duplicate()
	bad_state_nonfinite[RB.RATE] = NAN
	check("non-finite state refused", Native.backend.tail_loads(bad_state_nonfinite, v, d, original, tq, Air.RHO_SEA_LEVEL).is_empty())
	check("non-finite velocity refused", Native.backend.tail_loads(state, bad_velocity, d, original, tq, Air.RHO_SEA_LEVEL).is_empty())
	check("malformed velocity refused", Native.backend.tail_loads(state, PackedFloat64Array([20.0, 0.0]), d, original, tq, Air.RHO_SEA_LEVEL).is_empty())
	var bad_torque: PackedFloat64Array = PackedFloat64Array([tq[0], INF])
	check("non-finite thrust/torque refused", Native.backend.tail_loads(state, v, d, original, bad_torque, Air.RHO_SEA_LEVEL).is_empty())
	check("malformed thrust/torque refused", Native.backend.tail_loads(state, v, d, original, PackedFloat64Array([tq[0]]), Air.RHO_SEA_LEVEL).is_empty())
	var bad_deflections: Dictionary = d.duplicate(true)
	bad_deflections.elevator = NAN
	check("non-finite deflection refused", Native.backend.tail_loads(state, v, bad_deflections, original, tq, Air.RHO_SEA_LEVEL).is_empty())
	for rho in [0.0, -1.0, NAN, INF]:
		check("invalid density refused", Native.backend.tail_loads(state, v, d, original, tq, rho).is_empty())
	for field in ["cg_le", "surfaces", "propulsion"]:
		var bad: Dictionary = original.duplicate(true)
		bad.erase(field)
		check("missing model field refused: " + field, Native.backend.tail_loads(state, v, d, bad, tq, Air.RHO_SEA_LEVEL).is_empty())
	var bad_model: Dictionary = original.duplicate(true)
	bad_model.cg_le = PackedFloat64Array([NAN, original.cg_le[1], original.cg_le[2]])
	check("non-finite model vector refused", Native.backend.tail_loads(state, v, d, bad_model, tq, Air.RHO_SEA_LEVEL).is_empty())
	bad_model = original.duplicate(true)
	var bad_propulsion: Dictionary = bad_model.propulsion
	var bad_slipstream: Dictionary = bad_propulsion.slipstream
	bad_slipstream.wash_factor = PackedFloat64Array([bad_slipstream.wash_factor[0]])
	bad_propulsion.slipstream = bad_slipstream
	bad_model.propulsion = bad_propulsion
	check("malformed nested model array refused", Native.backend.tail_loads(state, v, d, bad_model, tq, Air.RHO_SEA_LEVEL).is_empty())
	bad_model = original.duplicate(true)
	bad_propulsion = bad_model.propulsion
	bad_slipstream = bad_propulsion.slipstream
	var bad_pieces: Array = bad_slipstream.pieces
	var bad_piece: Dictionary = bad_pieces[0]
	bad_piece.root = PackedFloat64Array([0.0, 0.0])
	bad_pieces[0] = bad_piece
	bad_slipstream.pieces = bad_pieces
	bad_propulsion.slipstream = bad_slipstream
	bad_model.propulsion = bad_propulsion
	check("malformed piece geometry refused", Native.backend.tail_loads(state, v, d, bad_model, tq, Air.RHO_SEA_LEVEL).is_empty())
	bad_model = original.duplicate(true)
	bad_propulsion = bad_model.propulsion
	bad_slipstream = bad_propulsion.slipstream
	bad_pieces = bad_slipstream.pieces
	bad_piece = bad_pieces[0]
	bad_piece.span_dir = PackedFloat64Array([NAN, bad_piece.span_dir[1], bad_piece.span_dir[2]])
	bad_pieces[0] = bad_piece
	bad_slipstream.pieces = bad_pieces
	bad_propulsion.slipstream = bad_slipstream
	bad_model.propulsion = bad_propulsion
	check("non-finite piece geometry refused", Native.backend.tail_loads(state, v, d, bad_model, tq, Air.RHO_SEA_LEVEL).is_empty())
	var refusal_sim: Node = Sim.new()
	root.add_child(refusal_sim)
	refusal_sim.mass = original.mass_kg
	refusal_sim.inertia = original.inertia.duplicate()
	var transaction_state: PackedFloat64Array = state.duplicate()
	var transaction_reset_ok: bool = refusal_sim.reset(transaction_state)
	check("refusal transaction starts from a valid reset", transaction_reset_ok)
	if transaction_reset_ok:
		var state_before: PackedFloat64Array = refusal_sim.state.duplicate()
		var previous_before: PackedFloat64Array = refusal_sim.previous.duplicate()
		var aux_before: PackedFloat64Array = refusal_sim.aux.duplicate()
		var inputs_before: PackedFloat64Array = refusal_sim.inputs.duplicate()
		var loads_before: PackedFloat64Array = refusal_sim.last_loads.duplicate()
		var tick_before: int = refusal_sim.tick
		var emissions: Array[int] = [0]
		refusal_sim.stepped.connect(func(_tick, _time, _state, _loads, _inputs, _aux): emissions[0] += 1)
		refusal_sim.loads = func(_s: PackedFloat64Array, _time: float) -> PackedFloat64Array:
			return Native.loads(state, {v_air = bad_velocity}, d, original, 5000.0, Air.RHO_SEA_LEVEL)
		refusal_sim.step()
		check("adapter refusal faults and rolls back the simulation tick",
			refusal_sim.paused and not refusal_sim.fault_reason.is_empty() and refusal_sim.tick == tick_before
			and refusal_sim.state == state_before and refusal_sim.previous == previous_before
			and refusal_sim.aux == aux_before and refusal_sim.inputs == inputs_before
			and refusal_sim.last_loads == loads_before and emissions[0] == 0)
	refusal_sim.free()
	var report: Dictionary = {policy = Policy.descriptor(), checks = checks, failures = failures, exact_load_cases = exact, nonzero_load_cases = nonzero,
		max_scaled_load_error = worst, load_tolerance = LOAD_TOLERANCE, godot = Engine.get_version_info()}
	var output: String = OS.get_environment("OPENRC_GATE_P_REPORT")
	if not output.is_empty():
		var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	print("Gate P kernel: ", report)
	flight.free()
	quit(1 if failures else 0)

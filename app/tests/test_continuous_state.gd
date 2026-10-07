# E0b5 / H8: continuous auxiliary state participates in the same RK4 stages as the rigid body.
extends SceneTree

const Sim := preload("res://sim/simulation.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	print(("ok   " if ok else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))
	if not ok:
		_failures += 1


func _initial(velocity := 0.0) -> PackedFloat64Array:
	return RB.make_state(M.v3(0.0, 0.0, 0.0), M.v3(velocity, 0.0, 0.0), M.q_identity(), M.v3(0.0, 0.0, 0.0))


func _zero_loads(_body: PackedFloat64Array, _z: PackedFloat64Array, _t: float) -> PackedFloat64Array:
	return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])


func _zero_derivative(_body: PackedFloat64Array, z: PackedFloat64Array, _t: float) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	result.resize(z.size())
	return result


func _new_sim(initial_z := 0.0, initial_u := 1.0) -> Node:
	var sim: Node = Sim.new()
	sim.gravity = 0.0
	sim.continuous = PackedFloat64Array([initial_z])
	sim.aux = PackedFloat64Array([2.0])
	sim.modes = PackedInt64Array([1])
	sim.continuous_loads = _zero_loads
	sim.continuous_derivative = _zero_derivative
	sim.reset(_initial(initial_u))
	return sim


func _same(left: Variant, right: Variant) -> bool:
	return var_to_bytes(left) == var_to_bytes(right)


func _snapshot_matches(sim: Node, snapshot: Dictionary) -> bool:
	return sim.checkpoint().is_empty() == false and _same(sim.checkpoint(), snapshot)


func _coupled_sim() -> Node:
	var sim: Node = Sim.new()
	sim.gravity = 0.0
	sim.continuous = PackedFloat64Array([0.0])
	# Unit-mass oscillator: u' = z, z' = -u. Position, velocity and z have exact values
	# sin(t), cos(t) and -sin(t) from x(0)=0, u(0)=1, z(0)=0.
	sim.continuous_loads = func(_body: PackedFloat64Array, z: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		return PackedFloat64Array([z[0], 0.0, 0.0, 0.0, 0.0, 0.0])
	sim.continuous_derivative = func(body: PackedFloat64Array, _z: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		return PackedFloat64Array([-body[RB.VEL]])
	sim.reset(_initial(1.0))
	return sim


func _coupled_error(hz: int) -> float:
	Engine.physics_ticks_per_second = hz
	var sim := _coupled_sim()
	for _tick in hz:
		sim.step()
	var error := maxf(absf(sim.state[RB.POS] - sin(1.0)), absf(sim.state[RB.VEL] - cos(1.0)))
	error = maxf(error, absf(sim.continuous[0] + sin(1.0)))
	if sim.tick != hz or not sim.fault_reason.is_empty():
		error = INF
	sim.free()
	return error


func _test_stage_time() -> void:
	var sim: Node = Sim.new()
	sim.gravity = 0.0
	sim.continuous = PackedFloat64Array([0.25])
	var load_times: Array[float] = []
	var derivative_times: Array[float] = []
	sim.continuous_loads = func(_body: PackedFloat64Array, _z: PackedFloat64Array, t: float) -> PackedFloat64Array:
		load_times.append(t)
		return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	sim.continuous_derivative = func(_body: PackedFloat64Array, _z: PackedFloat64Array, t: float) -> PackedFloat64Array:
		derivative_times.append(t)
		return PackedFloat64Array([0.0])
	sim.reset(_initial())
	sim.step()
	load_times.clear()
	derivative_times.clear()
	var start_time: float = sim.time()
	var h: float = sim.dt()
	sim.step()
	var expected := [start_time, start_time + h / 2.0, start_time + h / 2.0, start_time + h]
	_check("continuous loads receive absolute RK stage times", load_times == expected, str(load_times))
	_check("continuous derivative receives the same absolute stage times", derivative_times == expected, str(derivative_times))
	sim.free()


func _failure_sim(fail_call: int, malformed: bool) -> Node:
	var sim: Node = Sim.new()
	sim.gravity = 0.0
	sim.continuous = PackedFloat64Array([0.0])
	sim.aux = PackedFloat64Array([2.0])
	sim.modes = PackedInt64Array([1])
	sim.inputs = PackedFloat64Array([0.4, 0.0, 0.0, 0.0])
	sim.continuous_loads = _zero_loads
	var calls := [0]
	sim.pre_step = func(a: PackedFloat64Array, _inputs: PackedFloat64Array, _dt: float) -> PackedFloat64Array:
		sim.modes[0] = 0
		sim.stop_at_tick = 42
		return PackedFloat64Array([a[0] + 1.0])
	sim.continuous_derivative = func(_body: PackedFloat64Array, _z: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		calls[0] += 1
		if calls[0] == fail_call:
			return PackedFloat64Array() if malformed else PackedFloat64Array([NAN])
		return PackedFloat64Array([0.0])
	# Reset commits the nondefault input, aux and mode so the failure must restore all of them.
	sim.reset(_initial())
	return sim


func _test_derivative_failures() -> void:
	for malformed in [true, false]:
		for stage in range(1, 5):
			var sim := _failure_sim(stage, malformed)
			var before: Dictionary = sim.checkpoint()
			sim.step()
			var label := "malformed" if malformed else "nonfinite"
			_check("%s continuous derivative at stage %d rolls back body, continuous, aux and modes" % [label, stage],
				_simulation_matches(sim, before) and sim.paused and sim.fault_reason.contains("continuous derivative"), sim.fault_reason)
			sim.free()


func _load_failure_sim(fail_call: int, malformed: bool) -> Node:
	var sim: Node = Sim.new()
	sim.gravity = 0.0
	sim.continuous = PackedFloat64Array([0.0])
	sim.aux = PackedFloat64Array([2.0])
	sim.modes = PackedInt64Array([1])
	sim.inputs = PackedFloat64Array([0.4, 0.0, 0.0, 0.0])
	var calls := [0]
	var armed := [false]
	sim.continuous_loads = func(_body: PackedFloat64Array, _z: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		if not armed[0]:
			return _zero_loads(_body, _z, _t)
		calls[0] += 1
		if calls[0] == fail_call:
			return PackedFloat64Array() if malformed else PackedFloat64Array([NAN, 0.0, 0.0, 0.0, 0.0, 0.0])
		return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	sim.continuous_derivative = _zero_derivative
	sim.pre_step = func(a: PackedFloat64Array, _inputs: PackedFloat64Array, _dt: float) -> PackedFloat64Array:
		sim.modes[0] = 0
		sim.stop_at_tick = 42
		return PackedFloat64Array([a[0] + 1.0])
	# Reset evaluates loads once. Arm the injected fault only after the valid boundary is recorded.
	sim.reset(_initial())
	armed[0] = true
	calls[0] = 0
	return sim


func _test_load_failures() -> void:
	for malformed in [true, false]:
		for stage in range(1, 5):
			var sim := _load_failure_sim(stage, malformed)
			var before: Dictionary = sim.checkpoint()
			sim.step()
			var label := "malformed" if malformed else "nonfinite"
			_check("%s continuous loads at k%d roll back body, continuous, aux and modes" % [label, stage],
				_simulation_matches(sim, before) and sim.paused and sim.fault_reason.contains("loads"), sim.fault_reason)
			sim.free()


func _test_pre_step_failures() -> void:
	for malformed in [true, false]:
		var sim: Node = Sim.new()
		sim.gravity = 0.0
		sim.continuous = PackedFloat64Array([0.0])
		sim.aux = PackedFloat64Array([2.0])
		sim.modes = PackedInt64Array([1])
		sim.inputs = PackedFloat64Array([0.4, 0.0, 0.0, 0.0])
		sim.continuous_loads = _zero_loads
		sim.continuous_derivative = _zero_derivative
		sim.pre_step = func(_a: PackedFloat64Array, _inputs: PackedFloat64Array, _dt: float) -> PackedFloat64Array:
			sim.modes[0] = 0
			sim.stop_at_tick = 42
			return PackedFloat64Array() if malformed else PackedFloat64Array([NAN])
		sim.reset(_initial())
		var before: Dictionary = sim.checkpoint()
		sim.step()
		var label := "malformed" if malformed else "nonfinite"
		_check("%s pre-step output rolls back body, continuous, aux and modes" % label,
			_simulation_matches(sim, before) and sim.paused and sim.fault_reason.contains("pre-step"), sim.fault_reason)
		sim.free()


func _simulation_matches(sim: Node, snapshot: Dictionary) -> bool:
	if sim.tick != snapshot.tick or sim.stop_at_tick != snapshot.stop_at_tick:
		return false
	for key in ["state", "previous", "continuous", "aux", "inputs", "modes", "last_loads"]:
		if not _same(sim.get(key), snapshot[key]):
			return false
	return true


func _overflow_state_sim(invalid_stage: int) -> Node:
	Engine.physics_ticks_per_second = 1
	var sim := _new_sim(1.5e308, 0.0)
	var calls := [0]
	sim.continuous_derivative = func(_body: PackedFloat64Array, _z: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		calls[0] += 1
		var huge := 1.0e308
		if invalid_stage == 2 and calls[0] == 1:
			return PackedFloat64Array([huge])
		if invalid_stage == 3 and calls[0] == 2:
			return PackedFloat64Array([huge])
		if invalid_stage == 4 and calls[0] == 3:
			return PackedFloat64Array([huge])
		return PackedFloat64Array([0.0])
	return sim


func _test_state_failures() -> void:
	# A nonfinite tick-boundary value is rejected before it can enter k1.
	var boundary := _new_sim()
	var boundary_before: Dictionary = boundary.checkpoint()
	boundary.continuous[0] = NAN
	boundary.step()
	_check("nonfinite continuous boundary state is rolled back with aux and modes",
		_simulation_matches(boundary, boundary_before) and boundary.paused and boundary.fault_reason.contains("state"), boundary.fault_reason)
	boundary.free()

	# Finite derivatives can still overflow a later RK intermediate; fault at each reachable later stage.
	for stage in [2, 3, 4]:
		var sim := _overflow_state_sim(stage)
		var before: Dictionary = sim.checkpoint()
		sim.step()
		_check("nonfinite continuous intermediate at k%d rolls back the tick" % stage,
			_simulation_matches(sim, before) and sim.paused and sim.fault_reason.contains("RK stage state"), sim.fault_reason)
		sim.free()


func _test_checkpoint_and_reset() -> void:
	Engine.physics_ticks_per_second = 240
	var sim := _coupled_sim()
	sim.aux = PackedFloat64Array([3.0])
	sim.modes = PackedInt64Array([1])
	sim.pre_step = func(a: PackedFloat64Array, inputs: PackedFloat64Array, dt: float) -> PackedFloat64Array:
		return PackedFloat64Array([a[0] + inputs[0] * dt])
	sim.reset(_initial(1.0))
	for i in 12:
		sim.inputs[0] = float(i + 1) / 20.0
		sim.step()
	var cp: Dictionary = sim.checkpoint()
	_check("continuous state is present in exact checkpoint", cp.has("continuous") and cp.continuous == sim.continuous)
	var encoded: PackedByteArray = var_to_bytes(cp)
	var decoded: Dictionary = bytes_to_var(encoded)
	_check("native checkpoint encoding preserves continuous state exactly", _same(decoded, cp))
	var detached: Dictionary = sim.checkpoint()
	detached.continuous[0] += 1.0
	_check("checkpoint continuous array is detached", sim.continuous != detached.continuous)

	var expected: Dictionary = {}
	for i in 20:
		sim.inputs[0] = float((i % 7) - 3) / 10.0
		sim.step()
	expected = sim.checkpoint()
	_check("continuous flight reaches a replay boundary", not expected.is_empty())
	_check("restore accepts a matching continuous layout", sim.restore_checkpoint(decoded))
	sim.set_paused(false)
	for i in 20:
		sim.inputs[0] = float((i % 7) - 3) / 10.0
		sim.step()
	_check("mid-lag checkpoint continuation is bit-exact", _same(sim.checkpoint(), expected))

	var bad_missing: Dictionary = decoded.duplicate(true)
	bad_missing.erase("continuous")
	var bad_type: Dictionary = decoded.duplicate(true)
	bad_type.continuous = "wash"
	var bad_nonfinite: Dictionary = decoded.duplicate(true)
	bad_nonfinite.continuous = PackedFloat64Array([NAN])
	var bad_size: Dictionary = decoded.duplicate(true)
	bad_size.continuous = PackedFloat64Array([0.0, 1.0])
	for entry in [["missing", bad_missing], ["wrong type", bad_type], ["nonfinite", bad_nonfinite], ["wrong size", bad_size]]:
		var current: Dictionary = sim.checkpoint()
		_check("checkpoint rejects %s continuous data atomically" % entry[0],
			not sim.restore_checkpoint(entry[1]) and _simulation_matches(sim, current))

	# Reset's caller supplies the new run's initial continuous state before reset(), matching FlightSession's contract.
	sim.continuous = PackedFloat64Array([0.375])
	_check("reset accepts a caller-initialized continuous state", sim.reset(_initial(2.0)) and sim.tick == 0
		and sim.state[RB.VEL] == 2.0 and sim.previous == sim.state and sim.continuous == PackedFloat64Array([0.375]))
	var reset_before: Dictionary = sim.checkpoint()
	sim.continuous[0] = NAN
	_check("reset rejects nonfinite continuous state and restores the prior boundary",
		not sim.reset(_initial()) and _simulation_matches(sim, reset_before) and sim.paused)
	_check("valid reset clears the continuous-state fault", sim.reset(_initial()) and sim.fault_reason.is_empty())
	sim.free()


func _test_fixed_layout() -> void:
	var sim := _new_sim()
	var before: Dictionary = sim.checkpoint()
	sim.continuous.append(0.25)
	_check("checkpoint refuses a changed continuous layout", sim.checkpoint().is_empty())
	sim.step()
	_check("mid-run continuous layout change faults and restores the fixed layout",
		_simulation_matches(sim, before) and sim.paused and sim.fault_reason.contains("auxiliary state"), sim.fault_reason)

	# A deliberate reset is the run boundary where a new fixed layout may be installed.
	sim.continuous = PackedFloat64Array([0.1, 0.2])
	sim.continuous_loads = _zero_loads
	sim.continuous_derivative = _zero_derivative
	_check("reset establishes a new continuous layout for a new run", sim.reset(_initial()) and sim.continuous.size() == 2)
	sim.step()
	_check("the new fixed layout advances after reset", sim.tick == 1 and sim.fault_reason.is_empty() and sim.continuous.size() == 2)
	sim.free()


func _initialize() -> void:
	var original_hz: int = Engine.physics_ticks_per_second
	_test_stage_time()
	_test_derivative_failures()
	_test_load_failures()
	_test_pre_step_failures()
	_test_state_failures()
	_test_checkpoint_and_reset()
	_test_fixed_layout()
	var errors: Array[float] = [_coupled_error(4), _coupled_error(8), _coupled_error(16)]
	var ratio_a: float = errors[0] / errors[1]
	var ratio_b: float = errors[1] / errors[2]
	_check("bidirectionally coupled body and z converge at fourth order",
		ratio_a > 14.0 and ratio_a < 18.0 and ratio_b > 14.0 and ratio_b < 18.0,
		"errors=%s ratios=%.5f,%.5f" % [str(errors), ratio_a, ratio_b])
	Engine.physics_ticks_per_second = original_hz
	print("continuous state: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)

extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Sim := preload("res://sim/simulation.gd")
const EffectiveMass := preload("res://physics/effective_mass.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_test_scalar_quaternion_component()
	_test_late_projection_rollback()
	print("R05-B independent review fixture: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _check(label: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: %s %s" % [label, detail])
	else:
		print("PASS: %s" % label)


func _test_scalar_quaternion_component() -> void:
	var q := M.q_from_euler(PI * 0.5, 0.0, 0.0)
	var q3_nonzero: bool = absf(q[3]) > 0.5
	var n_body := PackedFloat64Array([0.0, 1.0, 0.0])
	var n_world: PackedFloat64Array = M.q_rotate(q, n_body)
	var properties := {
		mass_kg = 4.0,
		cg_body_m = PackedFloat64Array([0.5, 0.0, 0.0]),
		inertia = PackedFloat64Array([2.0, 3.0, 4.0, 0.0, 0.0, 0.0]),
		inverse = PackedFloat64Array([0.5, 1.0 / 3.0, 0.25, 0.0, 0.0, 0.0]),
	}
	var actual: Dictionary = EffectiveMass.at_point_properties(q, PackedFloat64Array([1.0, 0.0, 0.0]), n_world, properties)
	# Independent scalar evaluation in body axes: r_C=(0.5,0,0), n=(0,1,0),
	# |r_C × n|² / Izz = 0.25 / 4, then add 1/m.
	var expected: float = 1.0 / (1.0 / 4.0 + 0.25 / 4.0)
	_check("fixture quaternion has nonzero yaw component", q3_nonzero, str(q))
	_check("valid q[3] yaw and rotated normal are accepted", bool(actual.get("ok", false)), str(actual))
	_check("rotated normal recovers independently computed effective mass",
		bool(actual.get("ok", false)) and absf(float(actual.effective_mass_kg) - expected) < 1.0e-12,
		str("actual=", actual, " expected=", expected, " q=", q, " normal=", n_world))


func _test_late_projection_rollback() -> void:
	var simulation: Node = Sim.new()
	root.add_child(simulation)
	simulation.mass = 4.0
	simulation.gravity = 0.0
	simulation.inertia = PackedFloat64Array([2.0, 3.0, 4.0, 0.0, 0.0, 0.0])
	simulation.continuous = PackedFloat64Array([0.0])
	simulation.model.block_loads = func(_body: PackedFloat64Array, _z: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	simulation.model.block_derivative = func(_body: PackedFloat64Array, _z: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		return PackedFloat64Array([1.0])
	var fail_projection := [false]
	simulation.model.block_aux = func(extra: PackedFloat64Array, _sampled: PackedFloat64Array) -> PackedFloat64Array:
		return PackedFloat64Array([NAN]) if fail_projection[0] else PackedFloat64Array([extra[0]])
	var initial := RB.make_state(M.v3(0.0, 0.0, -10.0), M.v3(0.0, 0.0, 0.0), M.q_identity(), M.v3(0.0, 0.0, 0.0))
	_check("simulation reset establishes a valid joint boundary", simulation.reset(initial), str(simulation.fault_reason))
	simulation.inputs = PackedFloat64Array([0.2, -0.1, 0.3, 0.0])
	simulation.modes = PackedInt64Array([4, 9])
	simulation.stop_at_tick = 25
	# Re-reset after choosing the non-default transactional fields so they enter the valid snapshot.
	_check("configured transaction reset succeeds", simulation.reset(initial), str(simulation.fault_reason))
	var before := _transaction_bytes(simulation)
	var hook_calls: Array = []
	var pending := [false]
	var fault_count := [0]
	var step_count := [0]
	var fault_listener := func(_reason: String) -> void:
		fault_count[0] += 1
		pending[0] = false
	var step_listener := func(_tick: int, _time: float, _state: PackedFloat64Array, _loads: PackedFloat64Array,
			_inputs: PackedFloat64Array, _aux: PackedFloat64Array) -> void:
		step_count[0] += 1
		pending[0] = false
	simulation.faulted.connect(fault_listener)
	simulation.stepped.connect(step_listener)
	simulation.model.post_tick_joint = func(previous_body: PackedFloat64Array, candidate_body: PackedFloat64Array,
			next_tick: int, previous_continuous: PackedFloat64Array,
			candidate_continuous: PackedFloat64Array) -> PackedFloat64Array:
			hook_calls.append({previous = previous_body, candidate = candidate_body, tick = next_tick,
				previous_z = previous_continuous, candidate_z = candidate_continuous})
			pending[0] = true
			var contacted := candidate_body.duplicate()
			contacted[RB.POS] += 0.5
			return contacted
	fail_projection[0] = true
	simulation.step()
	var callback_saw_integrated_extra: bool = hook_calls.size() == 1 \
		and absf(float(hook_calls[0].tick) - 1.0) < 1.0e-12 \
		and hook_calls[0].previous_z.size() == 1 and hook_calls[0].candidate_z.size() == 1 \
		and hook_calls[0].candidate_z[0] > hook_calls[0].previous_z[0]
	_check("joint contact callback receives both integrated continuous endpoints", callback_saw_integrated_extra, str(hook_calls))
	_check("late auxiliary projection failure is fail-closed", not str(simulation.fault_reason).is_empty() and simulation.paused)
	_check("no contact body or continuous tail commits after projection failure",
		_transaction_bytes(simulation) == before, "tick=%s state=%s continuous=%s" % [simulation.tick, simulation.state, simulation.continuous])
	_check("fault emits once and stepped emits no candidate tick", fault_count[0] == 1 and step_count[0] == 0,
		"faults=%d steps=%d" % [fault_count[0], step_count[0]])
	_check("owner can clear staged contact bookkeeping on fault", not pending[0])

	# Explicit recovery: reset with a valid projection, then prove one candidate can publish atomically.
	fail_projection[0] = false
	_check("explicit reset clears sticky failure", simulation.reset(initial) and simulation.fault_reason.is_empty(), str(simulation.fault_reason))
	simulation.step()
	_check("valid retry publishes one complete tick", simulation.tick == 1 and step_count[0] == 2
		and simulation.continuous[0] > 0.0 and simulation.state[RB.POS] > initial[RB.POS]
		and simulation.fault_reason.is_empty() and not pending[0],
		str("tick=", simulation.tick, " steps=", step_count[0], " pos=", simulation.state[RB.POS],
			" z=", simulation.continuous[0]))
	simulation.queue_free()


func _transaction_bytes(simulation: Node) -> PackedByteArray:
	var fields: Array = []
	for key in ["state", "previous", "continuous", "aux", "inputs", "modes", "last_loads", "tick", "stop_at_tick",
			"mass", "gravity", "inertia", "_inertia_inv", "_inertia_cache", "_last_valid_state", "_last_valid_previous",
			"_last_valid_continuous", "_last_valid_aux", "_last_valid_inputs", "_last_valid_modes", "_last_valid_loads",
			"_last_valid_tick", "_last_valid_stop", "_last_valid_mass", "_last_valid_gravity", "_last_valid_inertia"]:
		fields.append(simulation.get(key))
	return var_to_bytes(fields)

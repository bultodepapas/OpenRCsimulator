# H8-R1: a checkpoint must be restorable, continuable and rejected without partial mutation.
extends SceneTree
const Sim := preload("res://sim/simulation.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
var checks: int = 0
var failures: int = 0


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func initial() -> PackedFloat64Array:
	return RB.make_state(M.v3(0, 0, -100), M.v3(1, 0, 0), M.q_identity(), M.v3(0, 0, 0))


# Include rollback history and derived caches, even when checkpoint() correctly refuses the owner.
func raw(sim: Node) -> PackedByteArray:
	var values: Array = []
	for field in ["state", "previous", "continuous", "aux", "inputs", "modes", "last_loads", "tick", "stop_at_tick", "mass", "gravity", "inertia", "paused", "fault_reason", "_fixed_dt", "_inertia_inv", "_inertia_cache", "_last_valid_state", "_last_valid_previous", "_last_valid_continuous", "_last_valid_aux", "_last_valid_inputs", "_last_valid_modes", "_last_valid_loads", "_last_valid_tick", "_last_valid_stop", "_last_valid_mass", "_last_valid_gravity", "_last_valid_inertia"]:
		values.append(sim.get(field))
	return var_to_bytes(values)


func rejects(sim: Node, candidate: Dictionary, label: String) -> void:
	var before: PackedByteArray = raw(sim)
	var signals: Array[int] = [0]
	var on_pause: Callable = func(_paused: bool) -> void: signals[0] += 1
	var on_fault: Callable = func(_reason: String) -> void: signals[0] += 1
	sim.paused_changed.connect(on_pause)
	sim.faulted.connect(on_fault)
	check(label + " preflight", not sim.can_restore_checkpoint(candidate) and raw(sim) == before)
	check(label + " restore", not sim.restore_checkpoint(candidate) and raw(sim) == before and signals[0] == 0)
	sim.paused_changed.disconnect(on_pause)
	sim.faulted.disconnect(on_fault)


func configured(coupled: bool) -> Node:
	var sim: Node = Sim.new()
	sim.gravity = 0.0
	sim.aux = PackedFloat64Array([12.0, 0.125])
	sim.modes = PackedInt64Array([1, 7])
	if coupled:
		sim.continuous = PackedFloat64Array([0.0])
		sim.continuous_loads = func(_body: PackedFloat64Array, z: PackedFloat64Array, t: float) -> PackedFloat64Array:
			return PackedFloat64Array([z[0] + t, 0, 0, 0, 0, 0])
		sim.continuous_derivative = func(body: PackedFloat64Array, _z: PackedFloat64Array, t: float) -> PackedFloat64Array:
			return PackedFloat64Array([-body[RB.VEL] + t])
	else:
		sim.loads = func(_body: PackedFloat64Array, t: float) -> PackedFloat64Array:
			return PackedFloat64Array([t, 0, 0, 0, 0, 0])
	return sim


func fresh_continuation(coupled: bool) -> void:
	var source: Node = configured(coupled)
	check("source reset", source.reset(initial()))
	for i in 20:
		source.step()
	var cp: Dictionary = source.checkpoint()
	for i in 20:
		source.step()
	var expected: PackedByteArray = var_to_bytes(source.checkpoint())
	var fresh: Node = configured(coupled) # deliberately never reset
	var samples: Array[int] = [0]
	var on_step: Callable = func(_tick: int, _t: float, _s: PackedFloat64Array, _l: PackedFloat64Array, _i: PackedFloat64Array, _a: PackedFloat64Array) -> void: samples[0] += 1
	fresh.stepped.connect(on_step)
	check("fresh preflight", fresh.can_restore_checkpoint(cp))
	check("fresh restore", fresh.restore_checkpoint(bytes_to_var(var_to_bytes(cp))))
	check("restore pauses without emitting a tick", fresh.paused and samples[0] == 0)
	check("complete boundary survives native round trip", var_to_bytes(fresh.checkpoint()) == var_to_bytes(cp))
	for i in 20:
		fresh.step()
	check("fresh continuation is exact", var_to_bytes(fresh.checkpoint()) == expected and fresh.tick == 40 and fresh.fault_reason.is_empty() and samples[0] == 20)
	fresh.free()
	source.free()


func boundary_rejection() -> void:
	var sim: Node = configured(true)
	sim.reset(initial())
	sim.step()
	var cp: Dictionary = sim.checkpoint()
	for at in [-1, 9223372036854775807, 9223372036854775806, 9007199254740992, 1 << 60, 1.5, "1", true]:
		var bad: Dictionary = cp.duplicate(true)
		bad.tick = at
		rejects(sim, bad, "invalid clock " + str(at))
	for step in [0.0, -1.0, NAN, INF, 1.0 / 120.0, 1, "0.004"]:
		var bad: Dictionary = cp.duplicate(true)
		bad.dt = step
		rejects(sim, bad, "invalid timestep " + str(step))
	for field in ["state", "previous", "continuous", "aux", "inputs", "last_loads"]:
		for value in [NAN, INF, -INF]:
			var bad: Dictionary = cp.duplicate(true)
			bad[field][0] = value
			rejects(sim, bad, field + " nonfinite " + str(value))
	for field in cp:
		var bad: Dictionary = cp.duplicate(true)
		bad.erase(field)
		rejects(sim, bad, "missing " + str(field))
	# Producer validation must match consumer validation, without normalizing or repairing the source.
	for entry in [["tick", -1], ["tick", 9223372036854775807], ["tick", 9007199254740992], ["stop_at_tick", -2], ["_fixed_dt", 0.1]]:
		var old: Variant = sim.get(entry[0])
		sim.set(entry[0], entry[1])
		var before: PackedByteArray = raw(sim)
		check("producer refuses " + str(entry[0]), sim.checkpoint().is_empty() and raw(sim) == before)
		sim.set(entry[0], old)
	for field in ["state", "previous"]:
		var old: PackedFloat64Array = sim.get(field).duplicate()
		var changed: PackedFloat64Array = old.duplicate()
		changed[RB.ATT] = 2.0
		sim.set(field, changed)
		var before: PackedByteArray = raw(sim)
		check("producer refuses unnormalized " + field, sim.checkpoint().is_empty() and raw(sim) == before)
		sim.set(field, old)
	var old_inertia: PackedFloat64Array = sim.inertia.duplicate()
	# Computed subnormal: the engine's decimal literal parser rounds 1e-310 to zero.
	for tensor in [PackedFloat64Array([1e-300 * 1e-10, 1, 1, 0, 0, 0]), PackedFloat64Array([1e-293, 1e308, 1, 31622776.601683788, 0, 0])]:
		sim.inertia = tensor
		var bad: Dictionary = cp.duplicate(true)
		bad.inertia = tensor.duplicate()
		check("inverse overflow fixture is finite SPD", sim._configuration_is_valid())
		rejects(sim, bad, "nonfinite derived inverse")
		var before: PackedByteArray = raw(sim)
		check("producer refuses nonfinite inverse", sim.checkpoint().is_empty() and raw(sim) == before)
	sim.inertia = old_inertia
	# Failed recovery cannot clear a sticky fault or replace its last committed rollback state.
	sim.fault_reason = "injected fault"
	sim.set_paused(true)
	var bad: Dictionary = cp.duplicate(true)
	bad.tick = -1
	rejects(sim, bad, "faulted owner")
	check("valid explicit recovery", sim.restore_checkpoint(cp) and sim.fault_reason.is_empty() and sim.paused)
	sim.step()
	check("recovered owner advances", sim.tick == cp.tick + 1 and sim.fault_reason.is_empty())
	sim.free()


func _initialize() -> void:
	var hz: int = Engine.physics_ticks_per_second
	for rate in [120, 240, 480]:
		Engine.physics_ticks_per_second = rate
		for coupled in [false, true]:
			fresh_continuation(coupled)
	Engine.physics_ticks_per_second = hz
	boundary_rejection()
	print("H8-R1 checkpoint integrity: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

# SF-01: the VehicleModel contract (sim/vehicle_model.gd) and the kernel's use of it (sim/simulation.gd).
# Known answers only: a zero-load model is free fall, so the kernel's arithmetic is checked against g·t.
extends SceneTree

const Sim := preload("res://sim/simulation.gd")
const VehicleModel := preload("res://sim/vehicle_model.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _level_state() -> PackedFloat64Array:
	return RB.make_state(M.v3(0.0, 0.0, -50.0), M.v3(15.0, 0.0, 0.0), M.q_identity(), M.v3(0.0, 0.0, 0.0))


func _initialize() -> void:
	_contract_shape()
	_kernel_installation()
	_declared_layout()
	_active_evaluator_guards()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _contract_shape() -> void:
	var m := VehicleModel.new()
	_check("default model is valid", VehicleModel.validate(m).ok, str(VehicleModel.validate(m).message))
	m.input_size = 0
	_check("input_size 0 is rejected", not VehicleModel.validate(m).ok)
	m.input_size = 5
	_check("input_size 5 is accepted: the kernel no longer hard-codes 4 or 6", VehicleModel.validate(m).ok)
	m.aux_size = -2
	_check("aux_size below -1 is rejected", not VehicleModel.validate(m).ok)
	m.aux_size = -1
	m.post_tick = func(_p: PackedFloat64Array, c: PackedFloat64Array, _n: int) -> PackedFloat64Array: return c
	m.post_tick_joint = func(_p: PackedFloat64Array, c: PackedFloat64Array, _n: int, _pc: PackedFloat64Array, _cc: PackedFloat64Array) -> PackedFloat64Array: return c
	_check("post_tick and post_tick_joint together are rejected", not VehicleModel.validate(m).ok)
	m.post_tick_joint = Callable()
	_check("one post-tick filter is accepted", VehicleModel.validate(m).ok)
	m.loads = Callable()
	_check("no loads, stage or block route is rejected", not VehicleModel.validate(m).ok)
	m.stage = func(_b: PackedFloat64Array, _c: PackedFloat64Array, _t: float) -> Dictionary: return {}
	_check("a joint stage route satisfies the evaluator requirement", VehicleModel.validate(m).ok and m.uses_joint_stage())
	_check("null is rejected", not VehicleModel.validate(null).ok)
	_check("a plain RefCounted is rejected", not VehicleModel.validate(RefCounted.new()).ok)


func _kernel_installation() -> void:
	var sim: Node = Sim.new()
	root.add_child(sim)
	var good := VehicleModel.new()
	good.input_size = 5
	good.identity = { vehicle = "test" }
	_check("set_model accepts a valid model", sim.set_model(good) and sim.model == good)
	var bad := VehicleModel.new()
	bad.input_size = 0
	_check("set_model refuses an invalid model and keeps the current one", not sim.set_model(bad) and sim.model == good)
	_check("set_model refuses a non-model object", not sim.set_model(RefCounted.new()) and sim.model == good)
	# SF-03 alias cleanup: the pre-SF-01 per-callback properties are gone; evaluators live only on `model`.
	var retired: bool = true
	for legacy: String in ["loads", "input_size", "pre_step", "post_step", "post_step_joint", "rotor_momentum",
			"continuous_loads", "continuous_derivative", "continuous_evaluate", "continuous_rotor_momentum",
			"continuous_aux", "continuous_step"]:
		retired = retired and sim.get(legacy) == null
	_check("kernel exposes no compatibility properties", retired)
	# Five inputs and a zero-load model: free fall, w = g·t exactly for RK4 on a constant derivative.
	good.input_size = 5
	sim.inputs = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0])
	sim.aux = PackedFloat64Array()
	_check("reset accepts five inputs", sim.reset(_level_state()), sim.fault_reason)
	for _i in 240:
		sim.step()
	var expected_w: float = sim.gravity * 240.0 * sim.dt()
	_check("zero-load model falls at g·t after one second", sim.fault_reason.is_empty() and absf(sim.state[RB.VEL + 2] - expected_w) < 1e-9,
		"w %.12f expected %.12f" % [sim.state[RB.VEL + 2], expected_w])
	_check("forward speed is unchanged in free fall", absf(sim.state[RB.VEL] - 15.0) < 1e-12)
	var snapshot: Dictionary = sim.checkpoint()
	_check("checkpoint with five inputs restores", not snapshot.is_empty() and sim.can_restore_checkpoint(snapshot))
	sim.free()


func _active_evaluator_guards() -> void:
	var sim := Sim.new()
	var model := VehicleModel.new()
	var calls := [0]
	model.stage = func(_body: PackedFloat64Array, extra: PackedFloat64Array, _t: float) -> Dictionary:
		calls[0] += 1
		var derivative := PackedFloat64Array()
		derivative.resize(extra.size())
		return {loads = PackedFloat64Array([1.0, 0.0, 0.0, 0.0, 0.0, 0.0]),
			derivative = derivative, rotor_momentum = M.v3(0.0, 0.0, 0.0)}
	_check("joint model installs before its live layout is known", sim.set_model(model))
	for size in [-1, 0]:
		model.continuous_size = size
		var candidate := sim.prepare_reset(_level_state())
		_check("empty joint layout is refused before a zero-load fallback (%d)" % size,
			not candidate.ok and calls[0] == 0)
	# The same evaluator is supported once it has a continuous block.
	model.continuous_size = 1
	sim.continuous = PackedFloat64Array([0.0])
	sim.gravity = 0.0
	_check("joint evaluator with a continuous block resets", sim.reset(_level_state()))
	sim.step()
	_check("supported joint evaluator applies its force at all four RK stages",
		sim.fault_reason.is_empty() and calls[0] == 5 and absf(sim.state[RB.VEL] - (15.0 + sim.dt())) < 1e-12)
	sim.free()

	# Mutable callbacks must also be guarded at restore and step, not only installation.
	for missing_loads in [false, true]:
		sim = Sim.new()
		_check("body-only model resets before callback mutation", sim.reset(_level_state()))
		var snapshot := sim.checkpoint()
		if missing_loads:
			sim.model.loads = Callable()
		else:
			sim.model.stage = model.stage
		_check("restore refuses an unusable active evaluator (%s)" % missing_loads,
			not sim.can_restore_checkpoint(snapshot) and not sim.restore_checkpoint(snapshot))
		sim.step()
		_check("invalid evaluator faults without advancing the body (%s)" % missing_loads,
			not sim.fault_reason.is_empty() and sim.tick == 0
			and sim.state.to_byte_array() == snapshot.state.to_byte_array())
		sim.free()


func _declared_layout() -> void:
	var sim: Node = Sim.new()
	root.add_child(sim)
	var m := VehicleModel.new()
	m.aux_size = 2
	_check("model with declared aux layout installs", sim.set_model(m))
	sim.aux = PackedFloat64Array([0.0])
	var candidate: Dictionary = sim.prepare_reset(_level_state())
	_check("reset refuses aux that disagrees with the declared layout", not candidate.ok and str(candidate.message).contains("declared layout"), str(candidate.message))
	sim.aux = PackedFloat64Array([0.0, 0.0])
	_check("reset accepts aux matching the declared layout", sim.reset(_level_state()), sim.fault_reason)
	sim.step()
	var snapshot: Dictionary = sim.checkpoint()
	_check("checkpoint is produced", not snapshot.is_empty())
	m.aux_size = 3
	_check("restore refuses a checkpoint that disagrees with the declared layout", not sim.can_restore_checkpoint(snapshot))
	m.aux_size = -1
	_check("undeclared size keeps the H8 rule: arrays fix the layout", sim.can_restore_checkpoint(snapshot))
	m.continuous_size = 1
	sim.continuous = PackedFloat64Array()
	candidate = sim.prepare_reset(_level_state())
	_check("declared continuous size without a continuous array is refused at reset", not candidate.ok)
	sim.free()

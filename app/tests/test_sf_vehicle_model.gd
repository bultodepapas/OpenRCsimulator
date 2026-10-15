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
	# Compatibility properties forward to the installed model under their pre-SF-01 names.
	var marker := func(_s: PackedFloat64Array, _t: float) -> PackedFloat64Array: return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	sim.loads = marker
	sim.input_size = 6
	sim.set("continuous_step", Callable())
	_check("sim.loads forwards to model.loads", good.loads == marker and sim.loads == marker)
	_check("sim.input_size forwards to model.input_size", good.input_size == 6 and sim.input_size == 6)
	_check("Object.set on a compatibility property reaches the model", not good.step_policy.is_valid())
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

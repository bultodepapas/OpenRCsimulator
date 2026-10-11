# EL2a-P3 scratch: stage callbacks reuse the verified inertia inverse without changing
# direct-call or mid-step public-inertia behavior.
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Sim := preload("res://sim/simulation.gd")

var _checks := 0
var _failures := 0
var _sim: Node
var _signed_zero_sim: Node
var _stage_calls := 0
var _mutate_during_step := false
var _mutate_call := -1
var _initial_inertia := PackedFloat64Array()
var _mutated_inertia := PackedFloat64Array()
var _initial_inverse := PackedFloat64Array()


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	print(("ok   " if ok else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))
	if not ok:
		_failures += 1


func _same(left: Variant, right: Variant) -> bool:
	return var_to_bytes(left) == var_to_bytes(right)


func _initialize() -> void:
	_sim = Sim.new()
	_sim.set_physics_process(false)
	root.add_child(_sim)
	_initial_inertia = PackedFloat64Array([2.7, 3.1, 4.3, 0.08, -0.05, 0.11])
	_mutated_inertia = PackedFloat64Array([3.4, 2.9, 5.1, -0.07, 0.09, 0.04])
	_sim.inertia = _initial_inertia.duplicate()
	_sim.continuous = PackedFloat64Array([0.0])
	_sim.continuous_evaluate = Callable(self, "_joint_evaluation")

	var unprimed: PackedFloat64Array = _sim._inertia_inverse_for_callback()
	_check("unprimed direct callback equals a fresh inverse", _same(unprimed, RB.inertia_inverse(_sim.inertia)))
	_check("unprimed callback leaves the tick cache untouched", _sim._inertia_cache.is_empty())

	var reset_ok: bool = _sim.reset(RB.make_state(M.v3(0.0, 0.0, -20.0), M.v3(15.0, 0.0, 0.0),
		M.q_identity(), M.v3(0.0, 0.0, 0.0)))
	_check("simulation reset succeeds with coupled callback", reset_ok, str(_sim.fault_reason))
	_initial_inverse = RB.inertia_inverse(_initial_inertia)
	_check("reset seeds the same exact inverse", _same(_sim._inertia_inv, _initial_inverse))
	_check("matching inertia returns the exact cached inverse",
		_same(_sim._inertia_inverse_for_callback(), _initial_inverse))
	var returned_inverse: PackedFloat64Array = _sim._inertia_inverse_for_callback()
	returned_inverse[0] = -999.0
	_check("mutating callback return does not mutate the cached inverse", _same(_sim._inertia_inv, _initial_inverse))
	_check("cached inverse remains reusable after return mutation",
		_same(_sim._inertia_inverse_for_callback(), _initial_inverse))

	_mutate_during_step = true
	_mutate_call = _stage_calls + 2 # the next call is k1; the following call is k2
	_sim.step()
	_check("the stage callback mutated public inertia", _same(_sim.inertia, _mutated_inertia))
	_check("mid-step mutation does not replace the body's tick inverse",
		_same(_sim._inertia_inv, _initial_inverse))
	_check("first step still commits", _sim.tick == 1, str(_sim.fault_reason))

	_mutate_during_step = false
	_check("out-of-step query after mutation equals a fresh inverse",
		_same(_sim._inertia_inverse_for_callback(), RB.inertia_inverse(_mutated_inertia)))
	_check("out-of-step query leaves the body tick inverse unchanged",
		_same(_sim._inertia_inv, _initial_inverse))
	_sim.step()
	_check("next tick refreshes the inverse for the new inertia",
		_same(_sim._inertia_inv, RB.inertia_inverse(_mutated_inertia)))
	_check("next tick remains valid", _sim.fault_reason.is_empty(), str(_sim.fault_reason))
	_check_signed_zero_mutation()
	_sim.set_paused(true)
	_signed_zero_sim.set_paused(true)

	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _joint_evaluation(_body: PackedFloat64Array, _continuous: PackedFloat64Array,
		_time_s: float) -> Dictionary:
	_stage_calls += 1
	if _mutate_during_step and _stage_calls == _mutate_call:
		_sim.inertia = _mutated_inertia.duplicate()
	var actual: PackedFloat64Array = _sim._inertia_inverse_for_callback()
	var expected: PackedFloat64Array = RB.inertia_inverse(_sim.inertia)
	_check("stage callback matches direct inversion at call %d" % _stage_calls, _same(actual, expected))
	if _mutate_during_step and _stage_calls == _mutate_call:
		_check("same-tick public mutation preserves body cache", _same(_sim._inertia_inv, _initial_inverse))
	return {
		"loads": PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]),
		"derivative": PackedFloat64Array([0.0]),
		"rotor_momentum": PackedFloat64Array([0.0, 0.0, 0.0]),
	}


func _check_signed_zero_mutation() -> void:
	_signed_zero_sim = Sim.new()
	_signed_zero_sim.set_physics_process(false)
	root.add_child(_signed_zero_sim)
	_signed_zero_sim.inertia = PackedFloat64Array([2.0, 3.0, 4.0, 0.0, 0.0, 0.0])
	var reset_ok: bool = _signed_zero_sim.reset(RB.make_state(M.v3(0.0, 0.0, -20.0), M.v3(15.0, 0.0, 0.0),
		M.q_identity(), M.v3(0.0, 0.0, 0.0)))
	_check("signed-zero fixture resets", reset_ok, str(_signed_zero_sim.fault_reason))
	# Numeric equality considers these arrays equal; byte identity must still detect the sign bit.
	var negative_zero_bytes := PackedByteArray([0, 0, 0, 0, 0, 0, 0, 128])
	var negative_zero: float = negative_zero_bytes.decode_double(0)
	_signed_zero_sim.inertia[3] = negative_zero
	_check("signed-zero mutation remains numerically equal to the cache",
		_signed_zero_sim._same_array(_signed_zero_sim.inertia, _signed_zero_sim._inertia_cache))
	_check("signed-zero mutation changes the source bytes",
		_signed_zero_sim.inertia.to_byte_array() != _signed_zero_sim._inertia_cache_bytes)
	# Make a valid but unmistakably stale cached result so this assertion proves the fallback ran.
	_signed_zero_sim._inertia_inv[0] = 999.0
	var actual: PackedFloat64Array = _signed_zero_sim._inertia_inverse_for_callback()
	var expected: PackedFloat64Array = RB.inertia_inverse(_signed_zero_sim.inertia)
	_check("signed-zero-only mutation falls back to exact direct inversion", _same(actual, expected))
	_check("signed-zero fallback does not rewrite the tick cache", _same(_signed_zero_sim._inertia_inv[0], 999.0))
	_check("signed-zero result differs from sentinel cache", actual[0] != 999.0)
	var checkpoint: Dictionary = _signed_zero_sim.checkpoint()
	var restored: bool = _signed_zero_sim.restore_checkpoint(checkpoint)
	_check("checkpoint restore succeeds after signed-zero cache fallback", restored,
		str(_signed_zero_sim.fault_reason))
	_check("restore snapshots exact current inertia bytes",
		_signed_zero_sim._inertia_cache_bytes == _signed_zero_sim.inertia.to_byte_array())
	_signed_zero_sim._inertia_inv[0] = 999.0
	_signed_zero_sim.inertia[3] = 0.0
	var restored_actual: PackedFloat64Array = _signed_zero_sim._inertia_inverse_for_callback()
	var restored_expected: PackedFloat64Array = RB.inertia_inverse(_signed_zero_sim.inertia)
	_check("callback detects signed-zero change after restore", _same(restored_actual, restored_expected))
	_check("post-restore signed-zero fallback leaves cached inverse untouched",
		_same(_signed_zero_sim._inertia_inv[0], 999.0))

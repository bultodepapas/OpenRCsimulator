# EL2a-P3 scratch diagnostic only; run outside the production test registry.
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Sim := preload("res://sim/simulation.gd")

const ITERATIONS := 100000
const ROUNDS := 4

var _sim: Node
var _inertia := PackedFloat64Array([2.7, 3.1, 4.3, 0.08, -0.05, 0.11])
var _checks := 0.0


func _initialize() -> void:
	_sim = Sim.new()
	root.add_child(_sim)
	_sim.inertia = _inertia.duplicate()
	var reset_ok: bool = _sim.reset(RB.make_state(M.v3(0.0, 0.0, -20.0), M.v3(15.0, 0.0, 0.0),
		M.q_identity(), M.v3(0.0, 0.0, 0.0)))
	if not reset_ok:
		push_error("benchmark fixture reset failed: " + str(_sim.fault_reason))
		quit(1)
		return
	_sim.set_paused(true)
	var expected: PackedFloat64Array = RB.inertia_inverse(_inertia)
	if var_to_bytes(expected) != var_to_bytes(_sim._inertia_inverse_for_callback()):
		push_error("cache output differs from direct inversion")
		quit(1)
		return
	for round_index in ROUNDS:
		var direct_first := round_index % 2 == 0
		var direct_usec := 0
		var cache_usec := 0
		if direct_first:
			direct_usec = _measure_direct()
			cache_usec = _measure_cache()
		else:
			cache_usec = _measure_cache()
			direct_usec = _measure_direct()
		print("round=%d order=%s direct_us=%d cache_us=%d ratio=%.4f" % [
			round_index + 1,
			"direct/cache" if direct_first else "cache/direct",
			direct_usec,
			cache_usec,
			float(cache_usec) / maxf(1.0, float(direct_usec)),
		])
	var final_direct: PackedFloat64Array = RB.inertia_inverse(_inertia)
	var final_cache: PackedFloat64Array = _sim._inertia_inverse_for_callback()
	if var_to_bytes(final_direct) != var_to_bytes(final_cache):
		push_error("cache output differs from direct inversion after timing")
		quit(1)
		return
	print("checksum=" + str(_checks))
	quit()


func _measure_direct() -> int:
	var start := Time.get_ticks_usec()
	var total := 0.0
	for i in ITERATIONS:
		var result: PackedFloat64Array = RB.inertia_inverse(_inertia)
		total += result[i % result.size()]
	_checks += total
	return Time.get_ticks_usec() - start


func _measure_cache() -> int:
	var start := Time.get_ticks_usec()
	var total := 0.0
	for i in ITERATIONS:
		var result: PackedFloat64Array = _sim._inertia_inverse_for_callback()
		total += result[i % result.size()]
	_checks += total
	return Time.get_ticks_usec() - start

# EL2a-P3 component diagnostic. The same script runs against both source snapshots.
extends SceneTree
const Supply: Script = preload("res://physics/electric_supply.gd")
const ITERATIONS: int = 300000

func _initialize() -> void:
	var pack: Dictionary = {"ocv_points": PackedFloat64Array([0.0, 10.0, 0.5, 12.0, 1.0, 14.0]),
		"capacity_ah": 3.0, "resistance_ohm": 0.08, "auxiliary_current_a": 0.4}
	var motor: Dictionary = {"kv_rpm_per_volt": 600.0, "resistance_ohm": 0.2, "no_load_current_a": 1.0}
	var points: Array[PackedFloat64Array] = []
	var results: Array[Dictionary] = []
	for i: int in 120:
		var point := PackedFloat64Array([float(i % 40) * 200.0, float(i % 5) * 0.25, float(i % 3) * 0.5])
		var evaluated: Dictionary = Supply.evaluate_dynamics(point[0], point[1], point[2], pack, motor)
		if not evaluated.get("ok", false):
			print("invalid diagnostic fixture: " + str(evaluated))
			quit(1)
			return
		points.append(point)
		results.append(evaluated)
	var checksum: float = 0.0
	var started: int = Time.get_ticks_usec()
	for i: int in ITERATIONS:
		var point: PackedFloat64Array = points[i % points.size()]
		var result: Dictionary = Supply.evaluate_dynamics(point[0], point[1], point[2], pack, motor)
		checksum += float(result.shaft_torque_nm)
	var elapsed: int = Time.get_ticks_usec() - started
	print(JSON.stringify({"format": "openrc-el2a-p3-supply-cost-v1", "iterations": ITERATIONS,
		"fixture_count": points.size(), "fixture_bytes_sha256": _sha(var_to_bytes(results)),
		"checksum_bytes_sha256": _sha(var_to_bytes(checksum)), "loop_wall_us": elapsed}))
	quit()

func _sha(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

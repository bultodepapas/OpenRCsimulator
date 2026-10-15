extends SceneTree
const Before = preload("res://../research/rc-monster-truck/monster-car-2/rcv42/baseline_batch.gd")
const Candidate = preload("res://../research/rc-monster-truck/monster-car-2/rcv42/candidate_batch.gd")
const Prealloc = preload("res://../research/rc-monster-truck/monster-car-2/rcv42/prealloc_batch.gd")
const ROUNDS = 5
const ITERATIONS = 6000
var output := ""
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	var implementations := [Before, Prealloc, Candidate]
	var coordinates := PackedFloat64Array()
	for i in 14: coordinates.append_array(PackedFloat64Array([i * 0.15, i * -0.12]))
	var sample := {"height_m": 0.2, "normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]), "mu": 0.82, "rolling": 1.0}
	var road := func(_n: float, _e: float) -> Variant: return sample
	for count in [0, 2, 8, 14, 28]:
		if not _compare(implementations, road, coordinates.slice(0, count)): return
	for bad_coords in [PackedFloat64Array([1]), PackedFloat64Array([NAN, 0]), PackedFloat64Array([0, INF]), PackedFloat64Array([-INF, 0])]:
		if not _compare(implementations, road, bad_coords): return
	if not _compare(implementations, Callable(), coordinates): return
	var values: Array = [null, false, 4, "road", [], PackedFloat64Array(), {}]
	for key in ["height_m", "normal_ned", "mu", "rolling"]:
		var missing := sample.duplicate(true)
		missing.erase(key)
		values.append(missing)
	for normal in [null, [], PackedFloat32Array([0, 0, -1]), PackedFloat64Array(), PackedFloat64Array([0, -1]), PackedFloat64Array([0, 0, -1, 0]), PackedFloat64Array([0, 0, 0])]:
		var item := sample.duplicate(true)
		item.normal_ned = normal
		values.append(item)
	for axis in 3:
		for invalid in [NAN, INF, -INF, 1.0e308]:
			var item := sample.duplicate(true)
			item.normal_ned[axis] = invalid
			values.append(item)
	for z in [-1.0 - 1.00001e-5, -1.0 - 0.99999e-5, -1.0, -1.0 + 0.99999e-5, -1.0 + 1.00001e-5]:
		var item := sample.duplicate(true)
		item.normal_ned = PackedFloat64Array([0.0, 0.0, z])
		values.append(item)
	for key in ["height_m", "mu", "rolling"]:
		for value in [NAN, INF, -INF, -0.0, -1.0, 0.0, 0, 1.0, 1.0e308]:
			var item := sample.duplicate(true)
			item[key] = value
			values.append(item)
	for value in values:
		var bad_road := func(_n: float, _e: float) -> Variant: return value
		if not _compare(implementations, bad_road, coordinates): return
	var rng := RandomNumberGenerator.new()
	rng.seed = 4201
	for i in 2000:
		var normal := PackedFloat64Array([rng.randf_range(-1, 1), rng.randf_range(-1, 1), -1])
		var length := sqrt(normal[0]*normal[0] + normal[1]*normal[1] + normal[2]*normal[2])
		for axis in 3: normal[axis] /= length
		var item := {"height_m": rng.randf_range(-20, 20), "normal_ned": normal, "mu": rng.randf(), "rolling": rng.randf()}
		var varied_road := func(_n: float, _e: float) -> Variant: return item
		if not _compare(implementations, varied_road, coordinates): return
	var rounds: Array = []
	for implementation in implementations:
		for i in 200: implementation._sample_road_batch(road, coordinates)
	for round_index in ROUNDS:
		var order := [0, 1, 2] if round_index % 2 == 0 else [2, 1, 0]
		var row := {}
		for index in order:
			var implementation = implementations[index]
			var start := Time.get_ticks_usec()
			for i in ITERATIONS: implementation._sample_road_batch(road, coordinates)
			row[["baseline", "preallocation", "fused"][index]] = float(Time.get_ticks_usec() - start) / ITERATIONS
		rounds.append(row)
	var report := {"complete": true, "checks": checks, "rounds_us_per_14_sample_batch": rounds, "iterations": ITERATIONS,
		"engine": Engine.get_version_info().string, "scope": "Warm alternating component batches; callback returns one existing dictionary, isolating validation and packing."}
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	file.close()
	print(JSON.stringify(report))
	quit()

func _compare(implementations: Array, road: Callable, coordinates: PackedFloat64Array) -> bool:
	var expected: PackedByteArray = var_to_bytes(Before._sample_road_batch(road, coordinates))
	for implementation in implementations.slice(1):
		checks += 1
		if var_to_bytes(implementation._sample_road_batch(road, coordinates)) != expected:
			push_error("batch mismatch at case %d" % checks)
			quit(1)
			return false
	return true

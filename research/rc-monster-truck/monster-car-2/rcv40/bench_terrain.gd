## Bit-exact terrain sampler comparison and paired microbenchmark; source-only harness.
## Run from app with --output=<json-path> [--candidate=res://physics/ground_terrain.gd].
extends SceneTree
const FieldLoader := preload("res://data/field_loader.gd")
const GroundSurfaces := preload("res://physics/ground_surfaces.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const AirfieldCourse := preload("res://physics/ground_vehicle/airfield_course.gd")
const BASELINE_PATH := "res://../research/rc-monster-truck/monster-car-2/rcv40/baseline_terrain.gd"
const DEFAULT_CANDIDATE_PATH := "res://physics/ground_terrain.gd"
const EPSILON := 0.000001
const EDGE_DELTAS := [-0.5, -EPSILON, -0.0, 0.0, EPSILON, 0.5]
const RANDOM_SEED := 4072026
const RANDOM_CASES := 2048
const BENCH_POINTS := 1024
const BENCH_REPEATS := 3
const BENCH_ROUNDS := 5
const WARMUP_CALLS := 200
var _differences: Array[String] = []
var _compared := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var output_path := ""
	var candidate_path := DEFAULT_CANDIDATE_PATH
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output_path = argument.trim_prefix("--output=")
		elif argument.begins_with("--candidate="):
			candidate_path = argument.trim_prefix("--candidate=")
	if output_path.is_empty():
		_fail("--output=<json-path> is required")
		return
	var baseline: Script = load(BASELINE_PATH)
	var candidate: Script = load(candidate_path)
	if baseline == null or candidate == null:
		_fail("could not load baseline or candidate terrain script")
		return
	var field_result: Dictionary = FieldLoader.load_from()
	var surface_result: Dictionary = GroundSurfaces.load_table()
	var lake_result: Dictionary = LakeLoader.load_from()
	if not field_result.get("ok", false) or not surface_result.get("ok", false) or not lake_result.get("ok", false):
		_fail("default field, surface table, or lake failed to load")
		return
	var dry_result: Dictionary = AirfieldCourse.build(field_result, surface_result)
	var lake_course_result: Dictionary = AirfieldCourse.build(field_result, surface_result, lake_result.lake)
	if not dry_result.get("ok", false) or not lake_course_result.get("ok", false):
		_fail("default airfield course did not build: %s / %s" % [dry_result.get("errors", []), lake_course_result.get("errors", [])])
		return
	var field: Dictionary = field_result.field
	var dry_course: Dictionary = dry_result.course
	var lake_course: Dictionary = lake_course_result.course
	var default_table: PackedFloat64Array = dry_course.surface_rects
	var lake: Dictionary = lake_result.lake
	var suites := _surface_suites(default_table)
	var suite_counts := {}
	var suite_inputs := {}
	for suite: Dictionary in suites:
		var table: PackedFloat64Array = suite.table
		var points: Array[PackedFloat64Array] = _suite_points(table, int(suite.random_cases), int(suite.seed))
		var label: String = str(suite.name)
		suite_counts[label] = points.size()
		suite_inputs[label] = {"table": table, "table_sha256": _sha256(table.to_byte_array()),
			"input_sha256": _input_hash(table, points)}
		_compare_suite(baseline, candidate, label, table, points)
	var lake_points: Array[PackedFloat64Array] = _lake_points(lake, _seeded_points(default_table, 256, RANDOM_SEED + 1))
	_compare_lake(baseline, candidate, default_table, lake, lake_points)
	var validation_cases := _compare_invalid_inputs(baseline, candidate, default_table)
	var tape := _seeded_points(default_table, BENCH_POINTS, RANDOM_SEED + 2)
	var timings := _benchmark(baseline, candidate, default_table, tape)
	var report := {
		"format": "openrc-rcv40-terrain-sampler-benchmark-v1",
		"engine": Engine.get_version_info().string,
		"debug_build": OS.is_debug_build(),
		"processor": OS.get_processor_name(),
		"field_id": str(field.get("id", "")),
		"course_identity": dry_result.identity,
		"course_source_manifest": dry_course.get("source_manifest", {}),
		"lake_identity": str(lake.get("identity", "")),
		"baseline_path": BASELINE_PATH,
		"candidate_path": candidate_path,
		"source_sha256": {"baseline": FileAccess.get_sha256(BASELINE_PATH),
			"production": FileAccess.get_sha256(DEFAULT_CANDIDATE_PATH),
			"candidate": FileAccess.get_sha256(candidate_path),
			"harness": FileAccess.get_sha256(get_script().resource_path)},
		"suite_case_counts": suite_counts,
		"suite_inputs": suite_inputs,
		"lake_public_case_count": lake_points.size(),
		"invalid_public_case_count": validation_cases,
		"bit_comparisons": _compared,
		"differences": _differences,
		"benchmark": timings,
		"benchmark_tape_sha256": _input_hash(default_table, tape),
		"benchmark_tape_north_east_m": _points_for_json(tape),
		"benchmark_table": default_table,
		"complete": _differences.is_empty(),
	}
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		_fail("cannot open output file (error %d)" % FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(report, "  ", true, true) + "\n")
	file.close()
	print(JSON.stringify({"ok": _differences.is_empty(), "output": output_path,
		"bit_comparisons": _compared, "differences": _differences.size(), "benchmark": timings}, "  ", true, true))
	quit(0 if _differences.is_empty() else 1)

func _surface_suites(default_table: PackedFloat64Array) -> Array[Dictionary]:
	var nested := PackedFloat64Array([
		-4.0, 4.0, -4.0, 4.0, 0.8, 2.5,
		-8.0, 8.0, -8.0, 8.0, 0.7, 5.0,
		-16.0, 16.0, -16.0, 16.0, 0.7, 6.0,
		-INF, INF, -INF, INF, 0.7, 7.5,
	])
	var tiny := PackedFloat64Array([
		-0.000000004, 0.000000004, -0.000000003, 0.000000003, 0.8, 2.5,
		-INF, INF, -INF, INF, 0.7, 7.5,
	])
	var touching := PackedFloat64Array([
		-10.0, 0.0, -5.0, 5.0, 0.8, 2.5,
		0.0, 10.0, -5.0, 5.0, 0.7, 5.0,
		-INF, INF, -INF, INF, 0.7, 7.5,
	])
	var mutated := nested.duplicate()
	mutated[4] = 0.65
	mutated[5] = 8.25
	return [
		{"name": "default_course", "table": default_table, "random_cases": RANDOM_CASES, "seed": RANDOM_SEED},
		{"name": "empty_table", "table": PackedFloat64Array(), "random_cases": 128, "seed": RANDOM_SEED + 10},
		{"name": "nested_precedence_overlap", "table": nested, "random_cases": 256, "seed": RANDOM_SEED + 20},
		{"name": "tiny_rectangles", "table": tiny, "random_cases": 256, "seed": RANDOM_SEED + 30},
		{"name": "touching_edges", "table": touching, "random_cases": 256, "seed": RANDOM_SEED + 40},
		{"name": "mutated_valid_table", "table": mutated, "random_cases": 256, "seed": RANDOM_SEED + 50},
	]

func _suite_points(table: PackedFloat64Array, random_count: int, seed: int) -> Array[PackedFloat64Array]:
	var points: Array[PackedFloat64Array] = []
	var rows: int = table.size() / 6
	for row in range(maxi(rows - 1, 0)):
		var i: int = row * 6
		var n0: float = table[i]
		var n1: float = table[i + 1]
		var e0: float = table[i + 2]
		var e1: float = table[i + 3]
		var north_cross := [n0 - 0.5, n0 - EPSILON, n0, n0 + EPSILON, (n0 + n1) * 0.5, n1 - EPSILON, n1, n1 + EPSILON, n1 + 0.5]
		var east_cross := [e0 - 0.5, e0 - EPSILON, e0, e0 + EPSILON, (e0 + e1) * 0.5, e1 - EPSILON, e1, e1 + EPSILON, e1 + 0.5]
		for delta: float in EDGE_DELTAS:
			for cross: float in east_cross:
				_add_point(points, n0 + delta, cross)
				_add_point(points, n1 + delta, cross)
			for cross: float in north_cross:
				_add_point(points, cross, e0 + delta)
				_add_point(points, cross, e1 + delta)
		_add_point(points, (n0 + n1) * 0.5, (e0 + e1) * 0.5)
	for first in range(maxi(rows - 1, 0)):
		for second in range(first + 1, rows - 1):
			var a: int = first * 6
			var b: int = second * 6
			var low_n: float = maxf(table[a], table[b])
			var high_n: float = minf(table[a + 1], table[b + 1])
			var low_e: float = maxf(table[a + 2], table[b + 2])
			var high_e: float = minf(table[a + 3], table[b + 3])
			if low_n < high_n and low_e < high_e:
				_add_point(points, (low_n + high_n) * 0.5, (low_e + high_e) * 0.5)
	_add_point(points, -0.0, -0.0)
	_add_point(points, 0.0, 0.0)
	points.append_array(_seeded_points(table, random_count, seed))
	return points

func _seeded_points(table: PackedFloat64Array, count: int, seed: int) -> Array[PackedFloat64Array]:
	var bounds := _finite_bounds(table)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var points: Array[PackedFloat64Array] = []
	for _index in count:
		_add_point(points, rng.randf_range(bounds[0], bounds[1]), rng.randf_range(bounds[2], bounds[3]))
	return points

func _finite_bounds(table: PackedFloat64Array) -> PackedFloat64Array:
	var n0 := INF
	var n1 := -INF
	var e0 := INF
	var e1 := -INF
	for row in range(maxi(table.size() / 6 - 1, 0)):
		var i: int = row * 6
		n0 = minf(n0, table[i])
		n1 = maxf(n1, table[i + 1])
		e0 = minf(e0, table[i + 2])
		e1 = maxf(e1, table[i + 3])
	if not is_finite(n0):
		return PackedFloat64Array([-100.0, 100.0, -100.0, 100.0])
	return PackedFloat64Array([n0, n1, e0, e1])

func _compare_suite(baseline: Script, candidate: Script, label: String,
		table: PackedFloat64Array, points: Array[PackedFloat64Array]) -> void:
	for index in points.size():
		var point: PackedFloat64Array = points[index]
		var n: float = point[0]
		var e: float = point[1]
		_compare_bits("%s[%d].inner" % [label, index], _inner(baseline, n, e, table), _inner(candidate, n, e, table))
		_compare_bits("%s[%d].validated" % [label, index], _sample_validated(baseline, n, e, table),
			_sample_validated(candidate, n, e, table))
		_compare_bits("%s[%d].public" % [label, index], _sample(baseline, n, e, table), _sample(candidate, n, e, table))

func _compare_lake(baseline: Script, candidate: Script, table: PackedFloat64Array,
		lake: Dictionary, points: Array[PackedFloat64Array]) -> void:
	for index in points.size():
		var point: PackedFloat64Array = points[index]
		var n: float = point[0]
		var e: float = point[1]
		_compare_bits("lake[%d].validated" % index, _sample_validated(baseline, n, e, table, lake),
			_sample_validated(candidate, n, e, table, lake))
		_compare_bits("lake[%d].public" % index, _sample(baseline, n, e, table, lake),
			_sample(candidate, n, e, table, lake))
		_compare_bits("lake[%d].empty_surface" % index,
			_sample(baseline, n, e, PackedFloat64Array(), lake),
			_sample(candidate, n, e, PackedFloat64Array(), lake))

func _lake_points(lake: Dictionary, seeded: Array[PackedFloat64Array]) -> Array[PackedFloat64Array]:
	var points := seeded.duplicate()
	for key in ["shoreline_ne", "bank_ne"]:
		var polygon: PackedFloat64Array = lake.get(key, PackedFloat64Array())
		for index in range(0, polygon.size(), 2):
			var n: float = polygon[index]
			var e: float = polygon[index + 1]
			for delta: float in EDGE_DELTAS:
				_add_point(points, n + delta, e)
				_add_point(points, n, e + delta)
	return points

func _compare_invalid_inputs(baseline: Script, candidate: Script,
		valid_table: PackedFloat64Array) -> int:
	var malformed := [
		PackedFloat64Array([1.0, 2.0, 3.0]),
		PackedFloat64Array([0.0, 1.0, 0.0, 1.0, 0.8, 2.5]),
		PackedFloat64Array([0.0, 1.0, 0.0, 1.0, 0.8, 2.5, 0.0, 1.0, 0.0, 1.0, 0.7, 7.5]),
		PackedFloat64Array([-INF, INF, -INF, INF, 0.8, NAN]),
	]
	var count := 0
	for table: PackedFloat64Array in malformed:
		_compare_nan("malformed[%d]" % count, _sample(baseline, 1.0, 2.0, table), _sample(candidate, 1.0, 2.0, table))
		count += 1
	for bad: float in [NAN, INF, -INF]:
		for coordinate in [0, 1]:
			var n: float = bad if coordinate == 0 else 1.0
			var e: float = bad if coordinate == 1 else 2.0
			_compare_nan("nonfinite[%d,%d].public" % [coordinate, count], _sample(baseline, n, e, valid_table),
				_sample(candidate, n, e, valid_table))
			_compare_nan("nonfinite[%d,%d].validated" % [coordinate, count],
				_sample_validated(baseline, n, e, valid_table), _sample_validated(candidate, n, e, valid_table))
			count += 1
	return count

func _benchmark(baseline: Script, candidate: Script, table: PackedFloat64Array,
		tape: Array[PackedFloat64Array]) -> Dictionary:
	for index in WARMUP_CALLS:
		var point: PackedFloat64Array = tape[index % tape.size()]
		_inner(baseline, point[0], point[1], table)
		_inner(candidate, point[0], point[1], table)
	var baseline_us := PackedFloat64Array()
	var candidate_us := PackedFloat64Array()
	var order: Array[String] = []
	for round_index in BENCH_ROUNDS:
		var baseline_first: bool = round_index % 2 == 0
		if baseline_first:
			baseline_us.append(_time_pass(baseline, table, tape))
			candidate_us.append(_time_pass(candidate, table, tape))
			order.append("baseline,candidate")
		else:
			candidate_us.append(_time_pass(candidate, table, tape))
			baseline_us.append(_time_pass(baseline, table, tape))
			order.append("candidate,baseline")
	return {"warmup_calls_each": WARMUP_CALLS, "rounds_each": BENCH_ROUNDS,
		"points_per_pass": tape.size(), "repeats_per_pass": BENCH_REPEATS,
		"calls_per_timed_pass": tape.size() * BENCH_REPEATS, "order_by_round": order,
		"baseline_elapsed_us": baseline_us, "candidate_elapsed_us": candidate_us,
		"baseline_median_us": _median(baseline_us), "candidate_median_us": _median(candidate_us),
		"candidate_over_baseline": _median(candidate_us) / maxf(_median(baseline_us), 0.000001)}

func _time_pass(script: Script, table: PackedFloat64Array, tape: Array[PackedFloat64Array]) -> float:
	var sink := 0.0
	var started := Time.get_ticks_usec()
	for _repeat in BENCH_REPEATS:
		for point: PackedFloat64Array in tape:
			var result: Variant = _inner(script, point[0], point[1], table)
			if typeof(result) == TYPE_PACKED_FLOAT64_ARRAY:
				sink += float(result[0])
	var elapsed := float(Time.get_ticks_usec() - started)
	if sink == INF:
		push_warning("unreachable sampler checksum overflow")
	return elapsed

func _inner(script: Script, north: float, east: float, table: PackedFloat64Array) -> Variant:
	return script.call("_sample_microrelief_validated", north, east, table)

func _sample(script: Script, north: float, east: float, table: PackedFloat64Array,
		lake: Dictionary = {}) -> Variant:
	return script.call("sample", north, east, table, lake)

func _sample_validated(script: Script, north: float, east: float,
		table: PackedFloat64Array, lake: Dictionary = {}) -> Variant:
	return script.call("sample_validated", north, east, table, lake)

func _compare_bits(label: String, left: Variant, right: Variant) -> void:
	_compared += 1
	if typeof(left) != TYPE_PACKED_FLOAT64_ARRAY or typeof(right) != TYPE_PACKED_FLOAT64_ARRAY \
			or left.to_byte_array() != right.to_byte_array():
		if _differences.size() < 20:
			_differences.append(label + " differs: %s / %s" % [str(left), str(right)])

func _compare_nan(label: String, left: Variant, right: Variant) -> void:
	_compared += 1
	if not _is_nan_triplet(left) or not _is_nan_triplet(right):
		if _differences.size() < 20:
			_differences.append(label + " did not fail closed to three NaNs")

func _is_nan_triplet(value: Variant) -> bool:
	if typeof(value) != TYPE_PACKED_FLOAT64_ARRAY or value.size() != 3:
		return false
	return is_nan(value[0]) and is_nan(value[1]) and is_nan(value[2])

func _input_hash(table: PackedFloat64Array, points: Array[PackedFloat64Array]) -> String:
	var hash := HashingContext.new()
	if hash.start(HashingContext.HASH_SHA256) != OK:
		return ""
	hash.update(table.to_byte_array())
	for point: PackedFloat64Array in points:
		hash.update(point.to_byte_array())
	return hash.finish().hex_encode()

func _sha256(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	if hash.start(HashingContext.HASH_SHA256) != OK:
		return ""
	hash.update(bytes)
	return hash.finish().hex_encode()

func _median(values: PackedFloat64Array) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]

func _points_for_json(points: Array[PackedFloat64Array]) -> Array:
	var result: Array = []
	for point: PackedFloat64Array in points:
		result.append([point[0], point[1]])
	return result

func _add_point(points: Array[PackedFloat64Array], north: float, east: float) -> void:
	points.append(PackedFloat64Array([north, east]))

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

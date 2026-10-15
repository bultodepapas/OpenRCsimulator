## Bit-exact airfield-track sampler comparison and paired microbenchmark.
## Run from app with --output=<json-path or directory> [--candidate=res://physics/ground_vehicle/airfield_track.gd].
extends SceneTree

const BASELINE_PATH := "res://../research/rc-monster-truck/monster-car-2/rcv40/baseline_track.gd"
const DEFAULT_CANDIDATE_PATH := "res://physics/ground_vehicle/airfield_track.gd"
const TRACK_DATA_PATH := "res://data/ground_vehicle/airfield_track.json"
const EPSILON := 0.000001
const GRID_STEP := 0.5
const SEEDED_CASES := 2048
const BENCH_POINTS := 3000
const WARMUP_CALLS := 200
const BENCH_ROUNDS := 5
const EDGE_DELTAS := [-EPSILON, 0.0, EPSILON]
var _differences: Array[String] = []
var _difference_count := 0
var _comparisons := 0
func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var output_path := ""
	var candidate_path := DEFAULT_CANDIDATE_PATH
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output_path = argument.trim_prefix("--output=")
		elif argument.begins_with("--candidate="): candidate_path = argument.trim_prefix("--candidate=")
	if output_path.is_empty(): _fail("--output=<json-path or directory> is required"); return
	if output_path == "." or output_path.ends_with("/") or output_path.ends_with("\\"):
		output_path = output_path.path_join("rcv40_track_bench.json")
	var baseline: Script = load(BASELINE_PATH)
	var candidate: Script = load(candidate_path)
	if baseline == null or candidate == null: _fail("could not load baseline or candidate track script"); return
	var loaded: Dictionary = baseline.call("load_default")
	if not bool(loaded.get("ok", false)): _fail("default track failed to load: " + str(loaded.get("errors", []))); return
	var track: Dictionary = loaded.track
	var cases := _geometry_cases(track)
	var counts := {}
	var hashes := {}
	for test_case: Dictionary in cases:
		var geometry: Dictionary = test_case.track
		if not bool(baseline.call("valid", geometry)) or not bool(candidate.call("valid", geometry)):
			_fail("invalid geometry case: " + str(test_case.name)); return
		var points := _test_points(geometry, SEEDED_CASES, 4072026 + int(test_case.seed_offset))
		counts[test_case.name] = points.size()
		hashes[test_case.name] = _input_hash(points)
		_compare_case(baseline, candidate, str(test_case.name), geometry, points)
	var empty_points: Array[PackedFloat64Array] = [PackedFloat64Array([-0.0, -0.0]),
		PackedFloat64Array([0.0, 0.0]), PackedFloat64Array([NAN, 0.0]),
		PackedFloat64Array([0.0, INF]), PackedFloat64Array([-INF, INF]), PackedFloat64Array([45.0, -10.0])]
	_compare_case(baseline, candidate, "empty_track_stable", {}, empty_points)
	counts["empty_track_stable"] = empty_points.size()
	hashes["empty_track_stable"] = _input_hash(empty_points)
	var inside := _inside_lane_points(track, BENCH_POINTS, 4072126)
	var mixed := _global_mixed_points(track, BENCH_POINTS, 4072127)
	var benchmark := {"inside_course_lane": _benchmark_case(baseline, candidate, track, inside),
		"global_mixed": _benchmark_case(baseline, candidate, track, mixed)}
	var report := {"format": "openrc-rcv40-track-sampler-benchmark-v1", "engine": Engine.get_version_info().string,
		"debug_build": OS.is_debug_build(), "processor": OS.get_processor_name(), "track_id": str(track.id),
		"track_data_sha256": str(loaded.sha256), "baseline_path": BASELINE_PATH, "candidate_path": candidate_path,
		"source_sha256": {"baseline": FileAccess.get_sha256(BASELINE_PATH), "candidate": FileAccess.get_sha256(candidate_path),
			"production": FileAccess.get_sha256(DEFAULT_CANDIDATE_PATH), "track_data": FileAccess.get_sha256(TRACK_DATA_PATH),
			"harness": FileAccess.get_sha256(get_script().resource_path)},
		"exact_result_encoding": "var_to_bytes(Dictionary)", "exact_comparisons": _comparisons,
		"difference_count": _difference_count, "differences": _differences, "case_point_counts": counts,
		"case_input_sha256": hashes, "benchmark": benchmark,
		"benchmark_input_sha256": {"inside_course_lane": _input_hash(inside), "global_mixed": _input_hash(mixed)},
		"complete": _difference_count == 0}
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null: _fail("cannot open output file (error %d)" % FileAccess.get_open_error()); return
	file.store_string(JSON.stringify(report, "  ", true, true) + "\n")
	file.close()
	print(JSON.stringify({"ok": _difference_count == 0, "output": output_path, "exact_comparisons": _comparisons,
		"difference_count": _difference_count, "benchmark": benchmark}, "  ", true, true))
	quit(0 if _difference_count == 0 else 1)
func _geometry_cases(track: Dictionary) -> Array[Dictionary]:
	var shifted: Dictionary = track.duplicate(true)
	shifted.center_north_m = float(shifted.center_north_m) + 0.375
	shifted.center_east_m = float(shifted.center_east_m) - 0.25
	shifted.half_straight_m = 11.25
	shifted.radius_m = 6.75
	shifted.lane_width_m = 2.8
	shifted.shoulder_m = 1.1
	shifted.technical_width_m = 4.2
	var access: Dictionary = shifted.access
	access.north_min_m = float(access.north_min_m) + 0.5
	access.north_max_m = float(access.north_max_m) + 0.5
	access.east_m = float(access.east_m) + 0.25
	access.width_m = 3.1
	var shaped: Dictionary = track.duplicate(true)
	for group in ["ramps", "rollers"]:
		for feature: Dictionary in shaped[group]:
			feature.east_m = float(feature.east_m) + 0.25
			feature.north_m = float(feature.north_m) - 0.125
			feature.approach_m = float(feature.approach_m) + 0.2
			feature.descent_m = float(feature.descent_m) + 0.3
			feature.width_m = float(feature.width_m) - 0.2
	var no_jumps: Dictionary = track.duplicate(true)
	no_jumps.ramps = []; no_jumps.rollers = []
	return [{"name": "default", "track": track, "seed_offset": 0},
		{"name": "shifted_valid_geometry", "track": shifted, "seed_offset": 10},
		{"name": "modified_valid_features", "track": shaped, "seed_offset": 20},
		{"name": "valid_no_jumps", "track": no_jumps, "seed_offset": 30}]
func _test_points(track: Dictionary, random_count: int, seed: int) -> Array[PackedFloat64Array]:
	var points: Array[PackedFloat64Array] = []
	var nc := float(track.center_north_m); var ec := float(track.center_east_m)
	var half := float(track.lane_width_m) * 0.5; var shoulder := float(track.shoulder_m)
	var access: Dictionary = track.access
	var ne := float(track.radius_m) + half + shoulder + 2.0
	var n0 := minf(nc - ne, float(access.north_min_m) - shoulder - 2.0)
	var n1 := maxf(nc + ne, float(access.north_max_m) + shoulder + 2.0)
	var ee := float(track.half_straight_m) + float(track.radius_m) + half + shoulder + 2.0
	var e0 := minf(ec - ee, float(access.east_m) - float(access.width_m) * 0.5 - shoulder - 2.0)
	var e1 := maxf(ec + ee, float(access.east_m) + float(access.width_m) * 0.5 + shoulder + 2.0)
	for ni in range(int(ceil((n1 - n0) / GRID_STEP)) + 1):
		for ei in range(int(ceil((e1 - e0) / GRID_STEP)) + 1):
			_add_point(points, minf(n0 + float(ni) * GRID_STEP, n1), minf(e0 + float(ei) * GRID_STEP, e1))
	_add_ring_edges(points, track); _add_feature_edges(points, track)
	_add_point(points, -0.0, -0.0); _add_point(points, 0.0, 0.0)
	points.append_array(_seeded_points(track, random_count, seed))
	return points
func _add_ring_edges(points: Array[PackedFloat64Array], track: Dictionary) -> void:
	var nc := float(track.center_north_m); var ec := float(track.center_east_m)
	var length := float(track.half_straight_m); var radius := float(track.radius_m)
	var half := float(track.lane_width_m) * 0.5; var shoulder := float(track.shoulder_m)
	for lateral: float in [-half - shoulder, -half, half, half + shoulder]:
		for delta: float in EDGE_DELTAS:
			var r := maxf(radius + lateral + delta, 0.001)
			for index in 25:
				var east := ec - length + 2.0 * length * float(index) / 24.0
				_add_point(points, nc - r, east); _add_point(points, nc + r, east)
			for side: float in [-1.0, 1.0]:
				for index in 33:
					var angle := -PI * 0.5 + PI * float(index) / 32.0
					_add_point(points, nc + r * sin(angle), ec + side * (length + r * cos(angle)))
func _add_feature_edges(points: Array[PackedFloat64Array], track: Dictionary) -> void:
	var sh := float(track.shoulder_m); var nc := float(track.center_north_m); var ec := float(track.center_east_m)
	var tn := float(track.technical_width_m) * 0.5; var te := float(track.half_straight_m) + float(track.radius_m)
	for dn: float in _band_edges(tn, sh):
		for de in [0.0, -te, te, -te - sh, te + sh]: _add_point(points, nc + dn, ec + float(de))
	for de: float in _band_edges(te, sh):
		for dn in [0.0, -tn, tn, -tn - sh, tn + sh]: _add_point(points, nc + float(dn), ec + de)
	var access: Dictionary = track.access
	var an := (float(access.north_min_m) + float(access.north_max_m)) * 0.5
	var ah := (float(access.north_max_m) - float(access.north_min_m)) * 0.5
	for dn: float in _band_edges(ah, sh):
		for de: float in _band_edges(float(access.width_m) * 0.5, sh): _add_point(points, an + dn, float(access.east_m) + de)
	for group in ["ramps", "rollers"]:
		for ramp: Dictionary in track[group]:
			var along := [-float(ramp.deck_m) * 0.5 - float(ramp.approach_m), -float(ramp.deck_m) * 0.5,
				0.0, float(ramp.deck_m) * 0.5, float(ramp.deck_m) * 0.5 + float(ramp.descent_m)]
			for offset: float in along:
				for delta: float in EDGE_DELTAS:
					for dn: float in _band_edges(float(ramp.width_m) * 0.5, sh):
						_add_point(points, float(ramp.north_m) + dn, float(ramp.east_m) + offset + delta)
					_add_point(points, float(ramp.north_m), float(ramp.east_m) + offset + delta)

func _band_edges(half: float, shoulder: float) -> Array[float]:
	var result: Array[float] = []
	for edge: float in [-half, half, -half - shoulder, half + shoulder]:
		for delta: float in EDGE_DELTAS: result.append(edge + delta)
	return result

func _seeded_points(track: Dictionary, count: int, seed: int) -> Array[PackedFloat64Array]:
	var rng := RandomNumberGenerator.new(); rng.seed = seed
	var points: Array[PackedFloat64Array] = []
	for _index in count:
		_add_point(points, rng.randf_range(float(track.center_north_m) - 30.0, float(track.center_north_m) + 30.0),
			rng.randf_range(float(track.center_east_m) - 35.0, float(track.center_east_m) + 35.0))
	return points

func _inside_lane_points(track: Dictionary, count: int, seed: int) -> Array[PackedFloat64Array]:
	var rng := RandomNumberGenerator.new(); rng.seed = seed
	var points: Array[PackedFloat64Array] = []
	var length := float(track.half_straight_m); var radius := float(track.radius_m)
	for _index in count: points.append(_loop_point(track, rng.randf_range(0.0, 4.0 * length + 2.0 * PI * radius)))
	return points

func _loop_point(track: Dictionary, distance: float) -> PackedFloat64Array:
	var length := float(track.half_straight_m); var radius := float(track.radius_m)
	var nc := float(track.center_north_m); var ec := float(track.center_east_m)
	var d := fposmod(distance, 4.0 * length + 2.0 * PI * radius)
	if d < 2.0 * length: return PackedFloat64Array([nc - radius, ec - length + d])
	d -= 2.0 * length
	var angle: float
	if d < PI * radius:
		angle = -PI * 0.5 + d / radius
		return PackedFloat64Array([nc + radius * sin(angle), ec + length + radius * cos(angle)])
	d -= PI * radius
	if d < 2.0 * length: return PackedFloat64Array([nc + radius, ec + length - d])
	d -= 2.0 * length; angle = PI * 0.5 - d / radius
	return PackedFloat64Array([nc + radius * sin(angle), ec - length - radius * cos(angle)])

func _global_mixed_points(track: Dictionary, count: int, seed: int) -> Array[PackedFloat64Array]:
	var rng := RandomNumberGenerator.new(); rng.seed = seed
	var points: Array[PackedFloat64Array] = []; var access: Dictionary = track.access
	for index in count:
		if index % 3 == 0: _add_point(points, rng.randf_range(0.0, 80.0), rng.randf_range(-40.0, 40.0))
		elif index % 3 == 1: _add_point(points, rng.randf_range(float(track.center_north_m) - 12.0, float(track.center_north_m) + 12.0), rng.randf_range(float(track.center_east_m) - 24.0, float(track.center_east_m) + 24.0))
		else: _add_point(points, rng.randf_range(float(access.north_min_m) - 4.0, float(access.north_max_m) + 8.0), rng.randf_range(float(access.east_m) - 8.0, float(access.east_m) + 8.0))
	return points

func _compare_case(base: Script, candidate: Script, label: String, track: Dictionary, points: Array[PackedFloat64Array]) -> void:
	for index in points.size():
		var p: PackedFloat64Array = points[index]
		var left: Variant = base.call("sample", track, p[0], p[1]); var right: Variant = candidate.call("sample", track, p[0], p[1])
		_comparisons += 1
		if var_to_bytes(left) != var_to_bytes(right):
			_difference_count += 1
			if _differences.size() < 25:
				_differences.append(JSON.stringify({"case": label, "index": index, "north": p[0], "east": p[1],
					"baseline": left, "candidate": right, "baseline_bytes": var_to_bytes(left).hex_encode(),
					"candidate_bytes": var_to_bytes(right).hex_encode()}, "", true, true))

func _benchmark_case(base: Script, candidate: Script, track: Dictionary, points: Array[PackedFloat64Array]) -> Dictionary:
	for i in WARMUP_CALLS:
		var p: PackedFloat64Array = points[i % points.size()]; _sample(base, track, p); _sample(candidate, track, p)
	var bt := PackedFloat64Array(); var ct := PackedFloat64Array(); var order: Array[String] = []
	for r in BENCH_ROUNDS:
		if r % 2 == 0: bt.append(_time_pass(base, track, points)); ct.append(_time_pass(candidate, track, points)); order.append("baseline,candidate")
		else: ct.append(_time_pass(candidate, track, points)); bt.append(_time_pass(base, track, points)); order.append("candidate,baseline")
	var bm := _median(bt); var cm := _median(ct)
	return {"warmup_calls_each": WARMUP_CALLS, "rounds_each": BENCH_ROUNDS, "points_per_pass": points.size(),
		"calls_per_timed_pass": points.size(), "order_by_round": order, "baseline_elapsed_us": bt,
		"candidate_elapsed_us": ct, "baseline_median_us": bm, "candidate_median_us": cm,
		"candidate_over_baseline": cm / maxf(bm, 0.000001)}

func _time_pass(script: Script, track: Dictionary, points: Array[PackedFloat64Array]) -> float:
	var checksum := 0.0; var started := Time.get_ticks_usec()
	for p: PackedFloat64Array in points:
		var result: Dictionary = _sample(script, track, p)
		checksum += float(result.height_m) + float(result.dn) + float(result.de) + float(result.coverage)
		if str(result.feature_id) == "__never__": checksum += 1.0
	var elapsed := float(Time.get_ticks_usec() - started)
	if checksum == INF: push_warning("track sampler checksum overflow")
	return elapsed

func _sample(script: Script, track: Dictionary, p: PackedFloat64Array) -> Dictionary:
	return script.call("sample", track, p[0], p[1])

func _input_hash(points: Array[PackedFloat64Array]) -> String:
	var hash := HashingContext.new()
	if hash.start(HashingContext.HASH_SHA256) != OK: return ""
	for p: PackedFloat64Array in points: hash.update(p.to_byte_array())
	return hash.finish().hex_encode()

func _median(values: PackedFloat64Array) -> float:
	var sorted := values.duplicate(); sorted.sort(); return sorted[sorted.size() / 2]

func _add_point(points: Array[PackedFloat64Array], n: float, e: float) -> void:
	points.append(PackedFloat64Array([n, e]))

func _fail(message: String) -> void:
	push_error(message); quit(1)

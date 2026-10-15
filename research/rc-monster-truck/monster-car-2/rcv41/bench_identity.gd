## Compare artifact identity semantics and paired lookup cost; never run this from app/test.sh.
## Run from app with --output=<json-path> [--candidate=res://../tmp/rcv41/candidate_dynamics.gd].
extends SceneTree

const BASELINE_PATH := "res://../research/rc-monster-truck/monster-car-2/rcv41/baseline_artifacts.gd"
const DEFAULT_CANDIDATE_PATH := "res://physics/ground_vehicle/vehicle_dynamics.gd"
const DEFAULT_SESSION_CANDIDATE_PATH := "res://sim/ground_vehicle/session.gd"
const SOURCE_PATHS := [
	"res://physics/ground_vehicle/nitro_dynamics.gd",
	"res://physics/ground_vehicle/vehicle_dynamics.gd",
]
const CACHE_ENTRY_LIMIT := 2
const CACHE_BYTE_LIMIT := 262144
const VALIDATION_SEED := 4102026
const BENCH_CALLS := 200
const BENCH_WARMUP := 20
const BENCH_ROUNDS := 5

var _failures: Array[String] = []
var _artifact_case_count := 0
var _validation_case_count := 0
var _bench_sink := 0
var _output_path := ""

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var candidate_path := DEFAULT_CANDIDATE_PATH
	var session_candidate_path := DEFAULT_SESSION_CANDIDATE_PATH
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output_path = argument.trim_prefix("--output=")
		elif argument.begins_with("--candidate="):
			candidate_path = argument.trim_prefix("--candidate=")
		elif argument.begins_with("--session-candidate="):
			session_candidate_path = argument.trim_prefix("--session-candidate=")
	if _output_path.is_empty():
		_fail("--output=<json-path> is required")
		return
	var baseline: Script = load(BASELINE_PATH)
	var candidate: Script = load(candidate_path)
	var session_baseline_script: Script = load("res://../research/rc-monster-truck/monster-car-2/rcv41/baseline_session.gd")
	var session_candidate_script: Script = load(session_candidate_path)
	if baseline == null or candidate == null or session_baseline_script == null or session_candidate_script == null:
		_fail("could not load baseline, candidate, or Session validator script")
		return
	var session_baseline: Object = session_baseline_script.new()
	var session_candidate: Object = session_candidate_script.new()
	var fixture_root := "res://../tmp/rcv41/identity-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var absolute_root := ProjectSettings.globalize_path(fixture_root)
	if DirAccess.make_dir_recursive_absolute(absolute_root) != OK:
		_fail("could not create isolated fixture directory")
		return
	var fixtures := _run_artifact_cases(baseline, candidate, fixture_root)
	var validation := _run_validation_cases(baseline, candidate, session_baseline, session_candidate)
	var cache := _check_cache(candidate)
	_check_cache_result("final", cache)
	for source_path: String in SOURCE_PATHS:
		fixtures.append(_compare_artifact("benchmark_precheck:%s" % source_path,
			baseline, candidate, source_path))
	var benchmark := _benchmark(baseline, candidate)
	var complete := _failures.is_empty()
	var report := {
		"format": "openrc-rcv41-artifact-identity-benchmark-v1",
		"engine": Engine.get_version_info().get("string", ""),
		"debug_build": OS.is_debug_build(),
		"processor": OS.get_processor_name(),
		"baseline_path": BASELINE_PATH,
		"candidate_path": candidate_path,
		"session_candidate_path": session_candidate_path,
		"source_sha256": {
			"baseline": FileAccess.get_sha256(BASELINE_PATH),
			"production": FileAccess.get_sha256(DEFAULT_CANDIDATE_PATH),
			"candidate": FileAccess.get_sha256(candidate_path),
			"session_production": FileAccess.get_sha256(DEFAULT_SESSION_CANDIDATE_PATH),
			"session_candidate": FileAccess.get_sha256(session_candidate_path),
			"harness": FileAccess.get_sha256(get_script().resource_path),
			"nitro_source": FileAccess.get_sha256(SOURCE_PATHS[0]),
			"body_source": FileAccess.get_sha256(SOURCE_PATHS[1]),
		},
		"fixture_root": fixture_root,
		"artifact_case_count": _artifact_case_count,
		"artifact_cases": fixtures,
		"sha256_validation_case_count": _validation_case_count,
		"sha256_validation_cases": validation.vehicle_dynamics,
		"session_validation_case_count": validation.session.size(),
		"session_validation_cases": validation.session,
		"cache_bounds": cache,
		"benchmark": benchmark,
		"failures": _failures,
		"complete": complete,
	}
	var output := FileAccess.open(_output_path, FileAccess.WRITE)
	if output == null:
		_fail("cannot open output file (error %d)" % FileAccess.get_open_error())
		return
	output.store_string(JSON.stringify(report, "  ", true, true) + "\n")
	output.close()
	print(JSON.stringify({"ok": complete, "output": _output_path,
		"artifact_cases": _artifact_case_count, "validation_cases": _validation_case_count,
		"cache_bounds": cache, "benchmark": benchmark, "failures": _failures}, "  ", true, true))
	session_baseline.free()
	session_candidate.free()
	quit(0 if complete else 1)

func _run_artifact_cases(baseline: Script, candidate: Script, root: String) -> Array[Dictionary]:
	var cases: Array[Dictionary] = []
	var empty_path := root.path_join("empty.gd")
	_write_bytes(empty_path, PackedByteArray())
	cases.append(_compare_artifact("empty_existing", baseline, candidate, empty_path))
	var missing_path := root.path_join("missing.gd")
	cases.append(_compare_artifact("missing_without_remap", baseline, candidate, missing_path))
	var binary_path := root.path_join("arbitrary_binary.gd")
	_write_bytes(binary_path, PackedByteArray([0, 255, 128, 10, 13, 0, 65, 0xFE]))
	cases.append(_compare_artifact("arbitrary_binary", baseline, candidate, binary_path))
	var rewrite_path := root.path_join("same_length_rewrite.gd")
	_write_bytes(rewrite_path, PackedByteArray([0, 1, 2, 3, 4, 5, 6, 7]))
	cases.append(_compare_artifact("same_length_before", baseline, candidate, rewrite_path))
	var rewrite_mtime_before := FileAccess.get_modified_time(rewrite_path)
	_write_bytes(rewrite_path, PackedByteArray([7, 6, 5, 4, 3, 2, 1, 0]))
	cases.append(_compare_artifact("same_length_after", baseline, candidate, rewrite_path))
	cases.append({"name": "same_length_mtime_observation",
		"mtime_equal": rewrite_mtime_before == FileAccess.get_modified_time(rewrite_path)})
	var truncate_path := root.path_join("truncate.gd")
	_write_bytes(truncate_path, PackedByteArray([10, 20, 30, 40, 50, 60]))
	cases.append(_compare_artifact("truncate_before", baseline, candidate, truncate_path))
	_write_bytes(truncate_path, PackedByteArray([10, 20]))
	cases.append(_compare_artifact("truncate_after", baseline, candidate, truncate_path))
	var delete_path := root.path_join("delete_recreate.gd")
	_write_bytes(delete_path, PackedByteArray([11, 22, 33, 44]))
	cases.append(_compare_artifact("delete_before", baseline, candidate, delete_path))
	var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(delete_path))
	if remove_error != OK:
		_fail("fixture delete failed: %s" % delete_path)
	cases.append(_compare_artifact("deleted", baseline, candidate, delete_path))
	_write_bytes(delete_path, PackedByteArray([44, 33, 22, 11]))
	cases.append(_compare_artifact("recreated", baseline, candidate, delete_path))
	var at_limit_path := root.path_join("at_cache_limit.gd")
	_write_bytes(at_limit_path, _patterned_bytes(CACHE_BYTE_LIMIT, 31))
	cases.append(_compare_artifact("exactly_256_kibibytes", baseline, candidate, at_limit_path))
	cases.append({"name": "cache_after_exact_limit", "cache_bounds": _check_cache_result("exact_limit", _check_cache(candidate))})
	var over_limit_path := root.path_join("over_cache_limit.gd")
	_write_bytes(over_limit_path, _patterned_bytes(CACHE_BYTE_LIMIT + 1, 37))
	cases.append(_compare_artifact("over_256_kibibytes", baseline, candidate, over_limit_path))
	cases.append({"name": "cache_after_over_limit", "cache_bounds": _check_cache_result("over_limit", _check_cache(candidate))})
	for index in 3:
		var eviction_path := root.path_join("eviction_%d.gd" % index)
		_write_bytes(eviction_path, PackedByteArray([index, index + 1, 255 - index]))
		cases.append(_compare_artifact("cache_eviction_%d" % index, baseline, candidate, eviction_path))
	cases.append({"name": "cache_after_eviction_sequence", "cache_bounds": _check_cache_result("eviction", _check_cache(candidate))})
	var remap_target := root.path_join("fallback_payload.gdc")
	_write_bytes(remap_target, PackedByteArray([0, 128, 255, 1, 2, 0]))
	var remap_source := root.path_join("remap_fallback.gd")
	_save_remap(remap_source + ".remap", remap_target)
	cases.append(_compare_artifact("valid_remap_fallback", baseline, candidate, remap_source))
	_write_bytes(remap_target, PackedByteArray([2, 128, 255, 1, 0, 0]))
	cases.append(_compare_artifact("remap_payload_same_length_rewrite", baseline, candidate, remap_source))
	var second_target := root.path_join("redirected_payload.gdc")
	_write_bytes(second_target, PackedByteArray([64, 32, 16, 8, 4, 2]))
	_save_remap(remap_source + ".remap", second_target)
	cases.append(_compare_artifact("remap_target_redirected", baseline, candidate, remap_source))
	_write_bytes(remap_source, PackedByteArray([65, 66, 67]))
	cases.append(_compare_artifact("source_takes_precedence_over_remap", baseline, candidate, remap_source))
	var bad_target_source := root.path_join("remap_bad_target.gd")
	_save_remap(bad_target_source + ".remap", "user://not-a-res-target.gdc")
	cases.append(_compare_artifact("malformed_remap_target", baseline, candidate, bad_target_source))
	var nonstring_target_source := root.path_join("remap_nonstring_target.gd")
	_save_remap(nonstring_target_source + ".remap", 17)
	cases.append(_compare_artifact("nonstring_remap_target", baseline, candidate, nonstring_target_source))
	var absent_target_source := root.path_join("remap_missing_target.gd")
	_save_remap(absent_target_source + ".remap", root.path_join("does_not_exist.gdc"))
	cases.append(_compare_artifact("missing_remap_target", baseline, candidate, absent_target_source))
	return cases

func _compare_artifact(label: String, baseline: Script, candidate: Script, path: String) -> Dictionary:
	_artifact_case_count += 1
	var expected: Variant = baseline.call("_reference_implementation_artifact", path)
	var actual: Variant = candidate.call("_reference_implementation_artifact", path)
	var exact := var_to_bytes(expected) == var_to_bytes(actual)
	if not exact:
		_fail("artifact result differs: %s" % label)
	return {"name": label, "path": path, "exact": exact,
		"baseline": expected, "candidate": actual}

func _run_validation_cases(baseline: Script, candidate: Script,
		session_baseline: Object, session_candidate: Object) -> Dictionary:
	var cases: Array[Dictionary] = []
	var digest := "0123456789abcdef".repeat(4)
	cases.append_array([
		{"name": "valid_lowercase", "value": digest, "expected": true},
		{"name": "empty", "value": "", "expected": false},
		{"name": "too_short", "value": digest.substr(1), "expected": false},
		{"name": "too_long", "value": digest + "0", "expected": false},
		{"name": "uppercase", "value": "ABCDEF0123456789".repeat(4), "expected": false},
		{"name": "prefix_lowercase", "value": "0x" + digest.substr(2), "expected": false},
		{"name": "prefix_uppercase", "value": "0X" + digest.substr(2), "expected": false},
		{"name": "leading_plus", "value": "+" + digest.substr(1), "expected": false},
		{"name": "leading_minus", "value": "-" + digest.substr(1), "expected": false},
		{"name": "leading_space", "value": " " + digest.substr(1), "expected": false},
		{"name": "trailing_tab", "value": digest.substr(0, 63) + "\t", "expected": false},
		{"name": "embedded_newline", "value": digest.substr(0, 32) + "\n" + digest.substr(33), "expected": false},
		{"name": "fullwidth_digit", "value": "１" + digest.substr(1), "expected": false},
		{"name": "unicode_letter", "value": "Ａ" + digest.substr(1), "expected": false},
		{"name": "string_name_type", "value": StringName(digest), "expected": false},
		{"name": "boolean_type", "value": true, "expected": false},
		{"name": "integer_type", "value": 64, "expected": false},
		{"name": "null_type", "value": null, "expected": false},
	])
	var rng := RandomNumberGenerator.new()
	rng.seed = VALIDATION_SEED
	const alphabet := "0123456789abcdef"
	for index in 32:
		var generated := ""
		for _digit in 64:
			generated += alphabet.substr(rng.randi_range(0, alphabet.length() - 1), 1)
		cases.append({"name": "seeded_valid_%d" % index, "value": generated, "expected": true})
		var bad_index := rng.randi_range(0, 63)
		var malformed := generated.substr(0, bad_index) + "g" + generated.substr(bad_index + 1)
		cases.append({"name": "seeded_malformed_%d" % index, "value": malformed, "expected": false})
	var results: Array[Dictionary] = []
	var session_results: Array[Dictionary] = []
	for test_case: Dictionary in cases:
		_validation_case_count += 1
		var value: Variant = test_case.value
		var expected_value: bool = bool(test_case.expected)
		var old_result: bool = bool(baseline.call("_sha256_is_valid", value))
		var new_result: bool = bool(candidate.call("_sha256_is_valid", value))
		var exact := old_result == new_result and old_result == expected_value
		if not exact:
			_fail("SHA validator mismatch: %s" % str(test_case.name))
		results.append({"name": test_case.name, "expected": expected_value,
			"baseline": old_result, "candidate": new_result, "exact": exact})
		for allow_empty in [false, true]:
			var session_expected: bool = old_result or (typeof(value) == TYPE_STRING \
				and str(value).is_empty() and allow_empty)
			var old_session: bool = bool(session_baseline.call("_sha256_field_is_valid", value, allow_empty))
			var new_session: bool = bool(session_candidate.call("_sha256_field_is_valid", value, allow_empty))
			var session_exact: bool = old_session == new_session and old_session == session_expected
			if not session_exact:
				_fail("Session SHA validator mismatch: %s allow_empty=%s" % [str(test_case.name), str(allow_empty)])
			session_results.append({"name": test_case.name, "allow_empty": allow_empty,
				"expected": session_expected, "baseline": old_session,
				"candidate": new_session, "exact": session_exact})
	return {"vehicle_dynamics": results, "session": session_results}

func _check_cache(candidate: Script) -> Dictionary:
	var cache_value: Variant = candidate.get("_artifact_content_cache")
	if typeof(cache_value) != TYPE_DICTIONARY:
		return {"available": false, "ok": false, "reason": "candidate exposes no readable cache property"}
	var sizes := {}
	var okay: bool = cache_value.size() <= CACHE_ENTRY_LIMIT
	for key: Variant in cache_value:
		var entry: Variant = cache_value[key]
		if typeof(entry) != TYPE_DICTIONARY:
			okay = false
			continue
		var bytes: Variant = entry.get("bytes")
		if typeof(bytes) != TYPE_PACKED_BYTE_ARRAY:
			okay = false
			continue
		sizes[str(key)] = bytes.size()
		if bytes.size() > CACHE_BYTE_LIMIT:
			okay = false
	return {"available": true, "ok": okay, "entry_count": cache_value.size(),
		"entry_byte_sizes": sizes, "entry_limit": CACHE_ENTRY_LIMIT, "byte_limit": CACHE_BYTE_LIMIT}

func _check_cache_result(label: String, cache: Dictionary) -> Dictionary:
	if not bool(cache.get("available", false)) or not bool(cache.get("ok", false)):
		_fail("artifact content cache exceeds its declared bounds at %s" % label)
	return cache

func _benchmark(baseline: Script, candidate: Script) -> Dictionary:
	for _index in BENCH_WARMUP:
		_call_artifact_pair(baseline, 1)
		_call_artifact_pair(candidate, 1)
	var baseline_times := PackedInt64Array()
	var candidate_times := PackedInt64Array()
	var order: Array[String] = []
	for round_index in BENCH_ROUNDS:
		if round_index % 2 == 0:
			baseline_times.append(_time_artifact_pair(baseline))
			candidate_times.append(_time_artifact_pair(candidate))
			order.append("baseline,candidate")
		else:
			candidate_times.append(_time_artifact_pair(candidate))
			baseline_times.append(_time_artifact_pair(baseline))
			order.append("candidate,baseline")
	return {"warmup_pair_calls_each": BENCH_WARMUP, "rounds_each": BENCH_ROUNDS,
		"calls_per_pair": BENCH_CALLS, "artifact_calls_per_pair": BENCH_CALLS * SOURCE_PATHS.size(),
		"order_by_round": order, "baseline_elapsed_us": baseline_times,
		"candidate_elapsed_us": candidate_times, "sink": _bench_sink}

func _time_artifact_pair(script: Script) -> int:
	var started := Time.get_ticks_usec()
	_call_artifact_pair(script)
	return Time.get_ticks_usec() - started

func _call_artifact_pair(script: Script, count: int = BENCH_CALLS) -> void:
	for _index in count:
		for source_path: String in SOURCE_PATHS:
			var result: Dictionary = script.call("_reference_implementation_artifact", source_path)
			_bench_sink += str(result.get("sha256", "")).length()

func _patterned_bytes(size: int, seed: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(size)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for index in size:
		bytes[index] = rng.randi_range(0, 255)
	return bytes

func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("could not write fixture: %s" % path)
		return
	file.store_buffer(bytes)
	file.close()

func _save_remap(path: String, target: Variant) -> void:
	var remap := ConfigFile.new()
	remap.set_value("remap", "path", target)
	if remap.save(path) != OK:
		_fail("could not save remap fixture: %s" % path)

func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)
	quit(1)

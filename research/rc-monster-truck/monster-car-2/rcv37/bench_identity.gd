## Compare source-artifact hashing strategies used by Nitro's live identity guard.
## This is an offline microbenchmark; it does not alter runtime physics or identity code.
extends SceneTree

const VehicleDynamics := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")

const NITRO_SOURCE_PATH := "res://physics/ground_vehicle/nitro_dynamics.gd"
const BODY_SOURCE_PATH := "res://physics/ground_vehicle/vehicle_dynamics.gd"
const REMAP_TARGET_PATH := NITRO_SOURCE_PATH
const PAIR_TRIALS := 5
const CALLS_PER_TRIAL := 40
const WARMUP_CALLS := 10

var _fixture_remap_path := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var output_path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			if not output_path.is_empty():
				_fail("--output may be supplied only once")
				return
			output_path = argument.trim_prefix("--output=")
	if output_path.is_empty():
		_fail("--output=<absolute-json-path> is required")
		return

	var fixture := _make_remap_fixture()
	if not bool(fixture.get("ok", false)):
		_fail("could not stage temporary remap semantic fixture: " + str(fixture.get("error", "unknown error")))
		return
	var remap_source_path := str(fixture.source_path)
	var missing_source_path := str(fixture.missing_path)

	var nitro_reference := VehicleDynamics._reference_implementation_artifact(NITRO_SOURCE_PATH)
	var body_reference := VehicleDynamics._reference_implementation_artifact(BODY_SOURCE_PATH)
	var nitro_candidate := _single_open_artifact(NITRO_SOURCE_PATH)
	var body_candidate := _single_open_artifact(BODY_SOURCE_PATH)
	var missing_reference := VehicleDynamics._reference_implementation_artifact(missing_source_path)
	var missing_candidate := _single_open_artifact(missing_source_path)
	var remap_reference := VehicleDynamics._reference_implementation_artifact(remap_source_path)
	var remap_candidate := _single_open_artifact(remap_source_path)
	var semantics_match: bool = _same_artifact(nitro_reference, nitro_candidate) \
		and _same_artifact(body_reference, body_candidate) \
		and _same_artifact(missing_reference, missing_candidate) \
		and _same_artifact(remap_reference, remap_candidate) \
		and str(nitro_reference.get("kind", "")) == "gdscript_source" \
		and str(body_reference.get("kind", "")) == "gdscript_source" \
		and str(missing_reference.get("kind", "")) == "" \
		and str(remap_reference.get("kind", "")) == "gdscript_remapped_bytecode"
	if not semantics_match:
		_cleanup_remap_fixture()
		_fail("candidate did not preserve source, missing, and remapped artifact semantics")
		return

	var path_results: Array[Dictionary] = []
	path_results.append(_benchmark_path("nitro_adapter", NITRO_SOURCE_PATH, nitro_reference))
	path_results.append(_benchmark_path("body_adapter", BODY_SOURCE_PATH, body_reference))
	var cleanup_error := _cleanup_remap_fixture()
	var path_results_complete: bool = path_results.size() == 2
	for result: Dictionary in path_results:
		path_results_complete = path_results_complete and not result.has("error")
	var report := {
		"format": "openrc-rcv37-identity-hash-microbench-v1",
		"complete": path_results_complete and cleanup_error.is_empty() and semantics_match,
		"engine": Engine.get_version_info().string,
		"debug_build": OS.is_debug_build(),
		"processor": OS.get_processor_name(),
		"logical_processors": OS.get_processor_count(),
		"scope": "Paired same-process source artifact hashing comparison: current VehicleDynamics._reference_implementation_artifact versus one open/get_buffer/HashingContext pass. No simulation ticks or runtime changes.",
		"candidate": "open once, read the complete file into a PackedByteArray, hash with HashingContext; on source open/hash failure, preserve the existing .remap ConfigFile fallback.",
		"pair_trials": PAIR_TRIALS,
		"calls_per_method_per_trial_per_source": CALLS_PER_TRIAL,
		"warmup_calls_per_method_per_source": WARMUP_CALLS,
		"semantic_cases": {
			"nitro_source": {"path": NITRO_SOURCE_PATH, "reference": nitro_reference, "candidate": nitro_candidate},
			"body_source": {"path": BODY_SOURCE_PATH, "reference": body_reference, "candidate": body_candidate},
			"missing_source_without_remap": {"path": missing_source_path,
				"reference": missing_reference, "candidate": missing_candidate},
			"remapped_target_fallback": {"synthetic_source_path": remap_source_path,
				"target_path": REMAP_TARGET_PATH, "reference": remap_reference,
				"candidate": remap_candidate},
		},
		"semantic_match": semantics_match,
		"results": path_results,
		"temporary_remap_fixture_cleanup_error": cleanup_error,
		"vehicle_dynamics_source_sha256": FileAccess.get_sha256(BODY_SOURCE_PATH),
		"benchmark_script_sha256": FileAccess.get_sha256(
			"res://../research/rc-monster-truck/monster-car-2/rcv37/bench_identity.gd"),
	}
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		_cleanup_remap_fixture()
		_fail("cannot open benchmark output (error %d)" % FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(report, "  ", true, true) + "\n")
	file.close()
	print(JSON.stringify({
		"ok": bool(report.complete) and semantics_match,
		"output": output_path,
		"semantic_match": semantics_match,
		"results": path_results,
	}, "  ", true, true))
	quit(0 if bool(report.complete) else 1)


func _benchmark_path(case_name: String, source_path: String, expected: Dictionary) -> Dictionary:
	var warm_reference := _reference_batch(source_path, WARMUP_CALLS)
	var warm_candidate := _single_open_batch(source_path, WARMUP_CALLS)
	if not _same_artifact(warm_reference.artifact, expected) \
			or not _same_artifact(warm_candidate.artifact, expected):
		return {"case": case_name, "error": "warmup artifact changed or mismatched"}

	var reference_trials := PackedFloat64Array()
	var candidate_trials := PackedFloat64Array()
	for trial in PAIR_TRIALS:
		var reference_elapsed := 0.0
		var candidate_elapsed := 0.0
		var reference_result: Dictionary = {}
		var candidate_result: Dictionary = {}
		if trial % 2 == 0:
			reference_result = _reference_batch(source_path, CALLS_PER_TRIAL)
			reference_elapsed = float(reference_result.elapsed_us) / CALLS_PER_TRIAL
			candidate_result = _single_open_batch(source_path, CALLS_PER_TRIAL)
			candidate_elapsed = float(candidate_result.elapsed_us) / CALLS_PER_TRIAL
		else:
			candidate_result = _single_open_batch(source_path, CALLS_PER_TRIAL)
			candidate_elapsed = float(candidate_result.elapsed_us) / CALLS_PER_TRIAL
			reference_result = _reference_batch(source_path, CALLS_PER_TRIAL)
			reference_elapsed = float(reference_result.elapsed_us) / CALLS_PER_TRIAL
		if not _same_artifact(reference_result.artifact, expected) \
				or not _same_artifact(candidate_result.artifact, expected):
			return {"case": case_name, "error": "timed artifact hash or kind changed"}
		reference_trials.append(reference_elapsed)
		candidate_trials.append(candidate_elapsed)
	var reference_summary := _summary(reference_trials)
	var candidate_summary := _summary(candidate_trials)
	return {
		"case": case_name,
		"path": source_path,
		"artifact": expected,
		"calls_per_method_per_trial": CALLS_PER_TRIAL,
		"paired_trial_order": "reference-first on even trials; candidate-first on odd trials",
		"reference_us_per_call": reference_summary,
		"single_open_us_per_call": candidate_summary,
		"median_speedup_percent": 100.0 * (1.0 - float(candidate_summary.median_us) / float(reference_summary.median_us)),
		"reference_trial_us_per_call": reference_trials,
		"single_open_trial_us_per_call": candidate_trials,
	}


func _reference_batch(path: String, calls: int) -> Dictionary:
	var started := Time.get_ticks_usec()
	var artifact: Dictionary = {}
	for _index in calls:
		artifact = VehicleDynamics._reference_implementation_artifact(path)
	return {"elapsed_us": Time.get_ticks_usec() - started, "artifact": artifact}


func _single_open_batch(path: String, calls: int) -> Dictionary:
	var started := Time.get_ticks_usec()
	var artifact: Dictionary = {}
	for _index in calls:
		artifact = _single_open_artifact(path)
	return {"elapsed_us": Time.get_ticks_usec() - started, "artifact": artifact}


func _single_open_artifact(source_path: String) -> Dictionary:
	var source_sha256 := _hash_with_one_open(source_path)
	if _digest_is_valid(source_sha256):
		return {"sha256": source_sha256, "kind": "gdscript_source"}
	var remap_path := source_path + ".remap"
	if not FileAccess.file_exists(remap_path):
		return {"sha256": "", "kind": ""}
	var remap := ConfigFile.new()
	if remap.load(remap_path) != OK:
		return {"sha256": "", "kind": ""}
	var target_value: Variant = remap.get_value("remap", "path", "")
	if typeof(target_value) != TYPE_STRING or not str(target_value).begins_with("res://"):
		return {"sha256": "", "kind": ""}
	var bytecode_sha256 := _hash_with_one_open(str(target_value))
	if not _digest_is_valid(bytecode_sha256):
		return {"sha256": "", "kind": ""}
	return {"sha256": bytecode_sha256, "kind": "gdscript_remapped_bytecode"}


func _hash_with_one_open(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var expected_length := file.get_length()
	if expected_length < 0:
		file.close()
		return ""
	var bytes := file.get_buffer(expected_length)
	file.close()
	if bytes.size() != expected_length:
		return ""
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK or hashing.update(bytes) != OK:
		return ""
	return hashing.finish().hex_encode()


func _make_remap_fixture() -> Dictionary:
	var nonce := str(Time.get_ticks_usec())
	var source_path := "user://rcv37_identity_remap_%s.gd" % nonce
	var remap_path := source_path + ".remap"
	var missing_path := "user://rcv37_identity_missing_%s.gd" % nonce
	if FileAccess.file_exists(source_path) or FileAccess.file_exists(remap_path) \
			or FileAccess.file_exists(missing_path):
		return {"ok": false, "error": "unique temporary probe path already exists"}
	var config := ConfigFile.new()
	config.set_value("remap", "path", REMAP_TARGET_PATH)
	_fixture_remap_path = remap_path
	if config.save(remap_path) != OK:
		return {"ok": false, "error": "ConfigFile could not write the temporary user:// remap"}
	return {"ok": true, "source_path": source_path, "remap_path": remap_path,
		"missing_path": missing_path}


func _cleanup_remap_fixture() -> String:
	if _fixture_remap_path.is_empty():
		return ""
	var absolute_path := ProjectSettings.globalize_path(_fixture_remap_path)
	var error := DirAccess.remove_absolute(absolute_path)
	_fixture_remap_path = ""
	return "" if error == OK else "could not remove temporary remap fixture (error %d)" % error


func _same_artifact(left: Dictionary, right: Dictionary) -> bool:
	return str(left.get("sha256", "")) == str(right.get("sha256", "")) \
		and str(left.get("kind", "")) == str(right.get("kind", ""))


func _digest_is_valid(value: String) -> bool:
	if value.length() != 64 or value.to_lower() != value:
		return false
	for character in value:
		if not str(character) in "0123456789abcdef":
			return false
	return true


func _summary(values: PackedFloat64Array) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value in sorted:
		total += value
	return {
		"samples": sorted.size(),
		"mean_us": total / float(sorted.size()),
		"median_us": sorted[sorted.size() / 2],
		"minimum_us": sorted[0],
		"maximum_us": sorted[-1],
	}


func _fail(message: String) -> void:
	_cleanup_remap_fixture()
	push_error(message)
	quit(1)

## RCV-37: compare the exact pre-optimization voice with the candidate and benchmark both.
## Run from the repository root with Godot --headless --path app --script
## res://../research/rc-monster-truck/monster-car-2/rcv37/bench_audio.gd -- --output=<json path>
extends SceneTree

const CANDIDATE_SCRIPT := preload("res://audio/nitro_voice.gd")
const VOICE_PATH := "res://audio/nitro_voice.gd"
const BASELINE_PATH := "res://../research/rc-monster-truck/monster-car-2/rcv37/baseline_voice.gd"
const HARNESS_PATH := "res://../research/rc-monster-truck/monster-car-2/rcv37/bench_audio.gd"
const BASELINE_EXPECTED_SHA256 := "90c6b09ead74def34d7485d319e27a6f0e1469bd7527b283619639f601351ce5"
const BLOCK_SIZES := [-1, 0, 1, 2, 3, 7, 31, 127, 128, 255, 256, 511, 512, 1023, 1024, 2047, 2048, 4095, 4096, 4097]
const INTERNAL_STATE_FIELDS: Array[StringName] = [
	&"phase_cycles", &"current_rpm", &"last_clutch_level", &"last_skid_level",
	&"last_transient_level", &"_target_rpm", &"_target_throttle", &"_current_throttle",
	&"_fuel_flow", &"_fuel_kg", &"_engine_running", &"_enabled", &"_paused",
	&"_clutch_slip", &"_clutch_engagement", &"_clutch_torque_nm", &"_wheel_drive_torque_nm",
	&"_grounded_skid", &"_gate", &"_transient", &"_noise_state", &"_skid_noise",
]
const BENCH_RUNS: int = 7
const BENCH_WARMUP_BLOCKS: int = 8
const BENCH_BLOCK_COUNT: int = 24
const BENCH_BLOCK_FRAMES: int = 4096


func _initialize() -> void:
	var baseline_sha256: String = FileAccess.get_sha256(BASELINE_PATH)
	if baseline_sha256 != BASELINE_EXPECTED_SHA256:
		var hash_failure := {
			"benchmark": "RCV-37 nitro voice exact parity and warm throughput",
			"complete": false,
			"parity_complete": false,
			"parity_passed": false,
			"failure": "baseline voice snapshot hash changed",
			"expected_baseline_sha256": BASELINE_EXPECTED_SHA256,
			"baseline_sha256": baseline_sha256,
			"candidate_sha256": FileAccess.get_sha256(VOICE_PATH),
			"harness_sha256": FileAccess.get_sha256(HARNESS_PATH),
		}
		var wrote_failure: bool = _emit_report(hash_failure)
		quit(1 if wrote_failure else 2)
		return
	var baseline_script: Script = load(BASELINE_PATH) as Script
	if baseline_script == null:
		var load_failure := {
			"benchmark": "RCV-37 nitro voice exact parity and warm throughput",
			"complete": false,
			"parity_complete": false,
			"parity_passed": false,
			"failure": "could not load baseline voice",
			"baseline_path": BASELINE_PATH,
			"baseline_sha256": baseline_sha256,
			"candidate_sha256": FileAccess.get_sha256(VOICE_PATH),
			"harness_sha256": FileAccess.get_sha256(HARNESS_PATH),
		}
		var wrote_failure: bool = _emit_report(load_failure)
		quit(1 if wrote_failure else 2)
		return
	var parity: Dictionary = _run_parity(baseline_script)
	var report := {
		"benchmark": "RCV-37 nitro voice exact parity and warm throughput",
		"complete": false,
		"parity_complete": parity.get("parity_complete", false),
		"parity_passed": parity.get("passed", false),
		"godot": Engine.get_version_info().string,
		"baseline_sha256": baseline_sha256,
		"candidate_sha256": FileAccess.get_sha256(VOICE_PATH),
		"harness_sha256": FileAccess.get_sha256(HARNESS_PATH),
		"parity_results": parity,
		"timing_method": "Seven paired runs; each voice receives eight untimed 4096-frame warm-up blocks, then 24 timed 4096-frame blocks. Pair execution order alternates.",
	}
	if not parity.get("passed", false):
		var wrote_parity_failure: bool = _emit_report(report)
		quit(1 if wrote_parity_failure else 2)
		return
	report["benchmark_results"] = _run_benchmark(baseline_script)
	report["complete"] = true
	var wrote_report: bool = _emit_report(report)
	quit(0 if wrote_report else 2)


func _output_path() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			return argument.trim_prefix("--output=")
	return ""


func _emit_report(report: Dictionary) -> bool:
	var rendered: String = JSON.stringify(report, "\t")
	var output_path: String = _output_path()
	if output_path.is_empty():
		print(rendered)
		return true
	var file: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		printerr("could not write JSON report to %s (error %d)" % [output_path, FileAccess.get_open_error()])
		print(rendered)
		return false
	file.store_string(rendered + "\n")
	file.close()
	print("wrote %s" % output_path)
	return true


func _run_parity(baseline_script: Script) -> Dictionary:
	var baseline: Object = baseline_script.new()
	var candidate: Object = CANDIDATE_SCRIPT.new()
	var events: Array[Dictionary] = _parity_events()
	var compared_blocks: int = 0
	var compared_frames: int = 0
	var saw_positive_clutch: bool = false
	var saw_negative_clutch: bool = false
	var saw_grounded_skid: bool = false
	var saw_rpm_transient: bool = false
	for event_index in events.size():
		var event: Dictionary = events[event_index]
		baseline.call("observe", event["telemetry"], event["controls"], event["paused"], event["enabled"])
		candidate.call("observe", event["telemetry"], event["controls"], event["paused"], event["enabled"])
		for requested_frames in BLOCK_SIZES:
			var baseline_pcm: PackedVector2Array = baseline.call("render", requested_frames)
			var candidate_pcm: PackedVector2Array = candidate.call("render", requested_frames)
			if baseline_pcm.size() != candidate_pcm.size():
				return _parity_failure("output size differs at event %d, request %d" % [event_index, requested_frames], compared_blocks)
			if baseline_pcm.to_byte_array() != candidate_pcm.to_byte_array():
				return _parity_failure("PCM bytes differ at event %d, request %d" % [event_index, requested_frames], compared_blocks)
			var state_difference: String = _state_difference(baseline, candidate)
			if not state_difference.is_empty():
				return _parity_failure("state differs after event %d, request %d: %s" % [event_index, requested_frames, state_difference], compared_blocks)
			if event["paused"] or not event["enabled"]:
				if not _is_silent(baseline_pcm) or not _is_silent(candidate_pcm):
					return _parity_failure("paused/disabled output was not silent at event %d" % event_index, compared_blocks)
			if event_index == 2 and requested_frames > 0 and float(candidate.get("_transient")) > 0.0:
				saw_rpm_transient = true
			if event_index == 3 and float(candidate.get("last_clutch_level")) > 0.0:
				saw_positive_clutch = true
			if event_index == 4 and float(candidate.get("last_clutch_level")) > 0.0:
				saw_negative_clutch = true
			if event_index == 3 and float(candidate.get("last_skid_level")) > 0.0:
				saw_grounded_skid = true
			compared_blocks += 1
			compared_frames += baseline_pcm.size()
	if not saw_positive_clutch or not saw_negative_clutch or not saw_grounded_skid or not saw_rpm_transient:
		return _parity_failure("coverage stimulus did not activate transient, both clutch signs, and grounded skid", compared_blocks)
	return {
		"passed": true,
		"parity_complete": true,
		"compared_blocks": compared_blocks,
		"compared_frames": compared_frames,
		"requested_block_sizes": BLOCK_SIZES,
		"compared_internal_fields": INTERNAL_STATE_FIELDS.size(),
		"coverage": {
			"engine_start_stop": true,
			"fuel_empty": true,
			"pause_resume": true,
			"disabled": true,
			"positive_and_negative_clutch_slip": true,
			"grounded_skid": true,
			"rpm_transient": true,
			"nested_and_top_level_nitro_telemetry": true,
		}
	}


func _parity_failure(message: String, blocks_compared: int) -> Dictionary:
	printerr("FAIL exact voice comparison after %d blocks: %s" % [blocks_compared, message])
	return {"passed": false, "parity_complete": false, "compared_blocks": blocks_compared, "failure": message}


func _state_difference(baseline: Object, candidate: Object) -> String:
	for field in INTERNAL_STATE_FIELDS:
		var expected: Variant = baseline.get(field)
		var actual: Variant = candidate.get(field)
		if expected != actual:
			return "%s baseline=%s candidate=%s" % [String(field), str(expected), str(actual)]
	return ""


func _is_silent(pcm: PackedVector2Array) -> bool:
	for sample in pcm:
		if sample.x != 0.0 or sample.y != 0.0:
			return false
	return true


func _parity_events() -> Array[Dictionary]:
	var no_contacts := PackedByteArray()
	var no_slip := PackedFloat64Array()
	var skid_contacts := PackedByteArray([1, 0, 1, 1])
	var skid_speeds := PackedFloat64Array([0.72, 0.0, 2.9, 1.15])
	var skid_ratios := PackedFloat64Array([0.19, 0.0, 0.61, 0.38])
	return [
		_event({"engine_running": false, "engine_rpm": 0.0, "fuel_kg": 0.0, "fuel_flow_kg_per_s": 0.0}, {"throttle": 0.0}, no_contacts, no_slip, no_slip, false, true, false),
		_event({"engine_running": true, "engine_rpm": 3700.0, "fuel_kg": 0.075, "fuel_flow_kg_per_s": 0.00004, "throttle_fraction": 0.06}, {"throttle_fraction": 0.06}, no_contacts, no_slip, no_slip, false, true, true),
		_event({"engine_running": true, "engine_rpm": 16400.0, "fuel_kg": 0.071, "fuel_flow_kg_per_s": 0.00031, "throttle_fraction": 0.68}, {"throttle_fraction": 0.68}, no_contacts, no_slip, no_slip, false, true, true),
		_event({"engine_running": true, "engine_rpm": 24800.0, "fuel_kg": 0.064, "fuel_flow_kg_per_s": 0.00043, "throttle_fraction": 0.82, "clutch_slip": 0.82, "clutch_engagement": 0.73, "clutch_torque_nm": 2.35, "wheel_drive_torque_nm": 11.4}, {"throttle_fraction": 0.82}, skid_contacts, skid_speeds, skid_ratios, false, true, true),
		_event({"engine_running": true, "engine_rpm": 18600.0, "fuel_kg": 0.059, "fuel_flow_kg_per_s": 0.00005, "throttle_fraction": 0.0, "clutch_slip": -0.76, "clutch_engagement": 0.48, "clutch_torque_nm": -1.9, "wheel_drive_torque_nm": -8.6}, {"throttle_fraction": 0.0, "brake": 0.84}, skid_contacts, skid_speeds, skid_ratios, false, true, false),
		_event({"engine_running": true, "engine_rpm": 18600.0, "fuel_kg": 0.059, "fuel_flow_kg_per_s": 0.00005, "throttle_fraction": 0.0, "clutch_slip": -0.76, "clutch_engagement": 0.48, "clutch_torque_nm": -1.9, "wheel_drive_torque_nm": -8.6}, {"throttle_fraction": 0.0, "brake": 0.84}, skid_contacts, skid_speeds, skid_ratios, true, true, true),
		_event({"engine_running": true, "engine_rpm": 27100.0, "fuel_kg": 0.051, "fuel_flow_kg_per_s": 0.00022, "throttle_fraction": 0.34, "clutch_slip": -0.36, "clutch_engagement": 0.22, "clutch_torque_nm": -0.55, "wheel_drive_torque_nm": -4.1}, {"throttle_fraction": 0.34}, skid_contacts, skid_speeds, skid_ratios, false, true, true),
		_event({"engine_running": false, "engine_rpm": 0.0, "fuel_kg": 0.0, "fuel_flow_kg_per_s": 0.0, "throttle_fraction": 0.0}, {"throttle_fraction": 0.0}, skid_contacts, skid_speeds, skid_ratios, false, true, true),
		_event({"engine_running": false, "engine_rpm": 7600.0, "fuel_kg": 0.032, "fuel_flow_kg_per_s": 0.0, "throttle_fraction": 0.51}, {"throttle_fraction": 0.51}, skid_contacts, skid_speeds, skid_ratios, false, true, true),
		_event({"engine_running": true, "engine_rpm": 6800.0, "fuel_kg": 0.032, "fuel_flow_kg_per_s": 0.00007, "throttle_fraction": 0.0}, {"throttle_fraction": 0.0}, no_contacts, no_slip, no_slip, false, false, true),
		_event({"engine_running": true, "engine_rpm": 9200.0, "fuel_kg": 0.031, "fuel_flow_kg_per_s": 0.00011, "throttle_fraction": 0.19}, {"throttle_fraction": 0.19}, no_contacts, no_slip, no_slip, false, true, true),
	]


func _event(nitro: Dictionary, controls: Dictionary, contacts: PackedByteArray, speed_slip: PackedFloat64Array, ratio_slip: PackedFloat64Array, paused: bool, enabled: bool, nested: bool) -> Dictionary:
	var telemetry: Dictionary = {"nitro": nitro.duplicate(true)} if nested else nitro.duplicate(true)
	telemetry["wheel_in_contact"] = contacts.duplicate()
	telemetry["wheel_slip_speed_m_per_s"] = speed_slip.duplicate()
	telemetry["wheel_slip_ratio"] = ratio_slip.duplicate()
	return {
		"telemetry": telemetry,
		"controls": controls.duplicate(true),
		"paused": paused,
		"enabled": enabled,
	}


func _run_benchmark(baseline_script: Script) -> Dictionary:
	var baseline_times: Array[int] = []
	var candidate_times: Array[int] = []
	var baseline_checksum: float = 0.0
	var candidate_checksum: float = 0.0
	for run_index in BENCH_RUNS:
		var baseline: Object = _new_bench_voice(baseline_script)
		var candidate: Object = _new_bench_voice(CANDIDATE_SCRIPT)
		for _warm_block in BENCH_WARMUP_BLOCKS:
			baseline.call("render", BENCH_BLOCK_FRAMES)
			candidate.call("render", BENCH_BLOCK_FRAMES)
		var baseline_result: Dictionary
		var candidate_result: Dictionary
		if run_index % 2 == 0:
			baseline_result = _measure_voice(baseline)
			candidate_result = _measure_voice(candidate)
		else:
			candidate_result = _measure_voice(candidate)
			baseline_result = _measure_voice(baseline)
		baseline_times.append(baseline_result["elapsed_usec"])
		candidate_times.append(candidate_result["elapsed_usec"])
		baseline_checksum += baseline_result["checksum"]
		candidate_checksum += candidate_result["checksum"]
	var frames_per_run: int = BENCH_BLOCK_COUNT * BENCH_BLOCK_FRAMES
	var baseline_median_usec: float = _median(baseline_times)
	var candidate_median_usec: float = _median(candidate_times)
	return {
		"runs": BENCH_RUNS,
		"warmup_blocks_per_run": BENCH_WARMUP_BLOCKS,
		"timed_blocks_per_run": BENCH_BLOCK_COUNT,
		"frames_per_run": frames_per_run,
		"block_frames": BENCH_BLOCK_FRAMES,
		"baseline_median_usec": baseline_median_usec,
		"candidate_median_usec": candidate_median_usec,
		"baseline_samples_per_second": float(frames_per_run) * 1000000.0 / baseline_median_usec,
		"candidate_samples_per_second": float(frames_per_run) * 1000000.0 / candidate_median_usec,
		"candidate_throughput_change_percent": 100.0 * (baseline_median_usec / candidate_median_usec - 1.0),
		"baseline_checksum": baseline_checksum,
		"candidate_checksum": candidate_checksum,
		"execution_order": "baseline-first on even runs, candidate-first on odd runs",
	}


func _new_bench_voice(voice_script: Script) -> Object:
	var voice: Object = voice_script.new()
	var telemetry := {
		"nitro": {
			"engine_running": true,
			"engine_rpm": 28200.0,
			"fuel_kg": 0.057,
			"fuel_flow_kg_per_s": 0.00041,
			"throttle_fraction": 0.77,
			"clutch_slip": 0.53,
			"clutch_engagement": 0.81,
			"clutch_torque_nm": 2.1,
			"wheel_drive_torque_nm": 10.8,
		},
		"wheel_in_contact": PackedByteArray([1, 0, 1, 1]),
		"wheel_slip_speed_m_per_s": PackedFloat64Array([0.9, 0.0, 2.5, 1.1]),
		"wheel_slip_ratio": PackedFloat64Array([0.2, 0.0, 0.49, 0.31]),
	}
	voice.call("observe", telemetry, {"throttle_fraction": 0.77}, false, true)
	return voice


func _measure_voice(voice: Object) -> Dictionary:
	var last_pcm := PackedVector2Array()
	var started_usec: int = Time.get_ticks_usec()
	for _block in BENCH_BLOCK_COUNT:
		last_pcm = voice.call("render", BENCH_BLOCK_FRAMES)
	var elapsed_usec: int = Time.get_ticks_usec() - started_usec
	var checksum: float = 0.0
	if not last_pcm.is_empty():
		checksum = last_pcm[0].x + last_pcm[last_pcm.size() - 1].y
	return {"elapsed_usec": elapsed_usec, "checksum": checksum}


func _median(samples: Array[int]) -> float:
	var sorted: Array[int] = samples.duplicate()
	sorted.sort()
	return float(sorted[sorted.size() / 2])

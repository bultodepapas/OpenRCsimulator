# EL2a-P1 whole-session propulsion performance probe. This measures software cost only;
# the synthetic electric packs are not measured hardware or Timber data.
# Run from the repository root:
# .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script "$PWD/research/propulsion/el2a-p1/bench.gd" -- --out=C:/Temp/openrc-el2a-p1-bench.json
extends SceneTree

const FlightSession: Script = preload("res://sim/flight_session.gd")

const TICK_HZ: int = 240
const WARMUP_TICKS: int = 240
const TICKS_PER_BATCH: int = 120
const DEFAULT_BATCHES: int = 12

const CASES: Array[Dictionary] = [
	{"id": "synthetic_stik_electric_4s", "family": "electric", "pack": "4S", "supply": "fixed_voltage",
		"path": "res://data/aircraft/synthetic_stik_electric_4s.json"},
	{"id": "synthetic_stik_electric_6s", "family": "electric", "pack": "6S", "supply": "fixed_voltage",
		"path": "res://data/aircraft/synthetic_stik_electric_6s.json"},
	{"id": "synthetic_stik_electric_4s_battery", "family": "electric", "pack": "4S", "supply": "dynamic_battery",
		"path": "res://data/aircraft/synthetic_stik_electric_4s_battery.json"},
	{"id": "synthetic_stik_electric_6s_battery", "family": "electric", "pack": "6S", "supply": "dynamic_battery",
		"path": "res://data/aircraft/synthetic_stik_electric_6s_battery.json"},
	{"id": "jensen_ugly_stik_60", "family": "legacy_control", "pack": "combustion", "supply": "nitro",
		"path": "res://data/aircraft/jensen_ugly_stik_60.json"},
	{"id": "p51d_mustang_120", "family": "legacy_control", "pack": "combustion", "supply": "nitro",
		"path": "res://data/aircraft/p51d_mustang_120.json"},
]

var _output_path: String = ""
var _batch_count: int = DEFAULT_BATCHES
var _failures: int = 0


func _initialize() -> void:
	if not _parse_args():
		quit(2)
		return
	Engine.physics_ticks_per_second = TICK_HZ
	var report: Dictionary = {
		"format": "openrc-el2a-p1-performance-bench-v1",
		"type": "whole_session_physics_tick_cost",
		"machine": {
			"os": OS.get_name(),
			"architecture": Engine.get_architecture_name(),
			"processor": OS.get_processor_name(),
			"logical_cpu_count": OS.get_processor_count(),
			"godot": Engine.get_version_info(),
		},
		"tick_hz": TICK_HZ,
		"warmup_ticks": WARMUP_TICKS,
		"ticks_per_batch": TICKS_PER_BATCH,
		"batch_count": _batch_count,
		"timer": "Time.get_ticks_usec around exactly 120 direct FlightSession.sim.step calls; restore, checks, checkpoint serialization, and hashing are outside the timer.",
		"checkpoint_encoding": "var_to_bytes(FlightSession.checkpoint()) native Variant bytes; each batch reports complete lowercase hex and SHA-256.",
		"trajectory_fingerprint": "Separate replay from the common warm checkpoint; SHA-256 rolls the complete native FlightSession checkpoint bytes at the initial boundary and after every replay tick.",
		"cases": [],
		"failures": [],
	}
	for case_value in CASES:
		var case: Dictionary = case_value
		for mode: String in ["powered", "coast"]:
			var result: Dictionary = _benchmark_case(case, mode)
			if not result.get("ok", false):
				_failures += 1
				report.failures.append({"case": case.id, "mode": mode, "message": result.get("error", "unknown failure")})
			report.cases.append(result)
			print("EL2a-P1 bench ", case.id, " / ", mode, " / median ",
				result.get("median_us_per_tick", -1.0), " µs/tick / ok=", result.get("ok", false))
	var successes: int = 0
	var successful_batches: int = 0
	for case_result_value in report.cases:
		var case_result: Dictionary = case_result_value
		if case_result.get("ok", false):
			successes += 1
		successful_batches += int(case_result.get("completed_batch_count", case_result.get("batches", []).size()))
	report["case_count"] = report.cases.size()
	report["success_count"] = successes
	report["failure_count"] = _failures
	report["successful_batch_count"] = successful_batches
	if not _write_report(report):
		_failures += 1
	print("EL2a-P1 performance probe: ", report.cases.size(), " cases, ", _failures, " failures")
	quit(1 if _failures > 0 else 0)


func _parse_args() -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_output_path = arg.trim_prefix("--out=")
		elif arg.begins_with("--batches="):
			var batch_text: String = arg.trim_prefix("--batches=")
			if not batch_text.is_valid_int():
				printerr("--batches must be a whole number from 1 to 1000")
				return false
			var parsed: int = int(batch_text)
			if parsed <= 0 or parsed > 1000:
				printerr("--batches must be a whole number from 1 to 1000")
				return false
			_batch_count = parsed
		else:
			printerr("unknown argument: ", arg)
			return false
	if _output_path.is_empty():
		printerr("usage: Godot --headless --path app --script research/propulsion/el2a-p1/bench.gd -- --out=ABSOLUTE_PATH [--batches=12]")
		return false
	if not _output_path.is_absolute_path():
		printerr("--out must be an absolute path")
		return false
	if FileAccess.file_exists(_output_path) or DirAccess.dir_exists_absolute(_output_path):
		printerr("refusing to overwrite existing benchmark output: ", _output_path)
		return false
	return true


func _benchmark_case(case: Dictionary, mode: String) -> Dictionary:
	var session: Node = FlightSession.new()
	session.setup(str(case.path))
	root.add_child(session)
	session.input_enabled = false
	session.set_start_altitude(150.0)
	session.reset()
	if not session.is_flyable():
		var setup_error: String = "flight setup refused: " + str(session.start_error if not session.start_error.is_empty() else session.pause_reason)
		session.free()
		return _failed_case(case, mode, setup_error)
	if mode == "coast":
		session.engine_running = false

	var warmup_completed: int = _advance_checked(session, WARMUP_TICKS)
	if warmup_completed != WARMUP_TICKS:
		var warmup_error: String = "warm-up stopped after %d/%d ticks: %s" % [warmup_completed, WARMUP_TICKS, session.sim.fault_reason]
		session.free()
		return _failed_case(case, mode, warmup_error)
	var seed_checkpoint: Dictionary = session.checkpoint()
	if seed_checkpoint.is_empty():
		session.free()
		return _failed_case(case, mode, "FlightSession returned an empty warm checkpoint")
	var seed_bytes: PackedByteArray = var_to_bytes(seed_checkpoint)
	var seed_hex: String = seed_bytes.hex_encode()
	var seed_sha256: String = _sha256(seed_bytes)
	var batches: Array[Dictionary] = []
	var timings: Array[float] = []
	var expected_endpoint_hex: String = ""
	var deterministic_batches: bool = true
	var batch_failure: String = ""
	for batch_index: int in _batch_count:
		if not session.restore_checkpoint(seed_checkpoint):
			batch_failure = "warm checkpoint restore refused before batch %d" % batch_index
			break
		var restored_bytes: PackedByteArray = var_to_bytes(session.checkpoint())
		if restored_bytes != seed_bytes:
			batch_failure = "warm checkpoint native bytes changed after restore before batch %d" % batch_index
			break
		var start_tick: int = int(session.sim.tick)
		var started_usec: int = Time.get_ticks_usec()
		for tick_index: int in TICKS_PER_BATCH:
			session.sim.step()
		var elapsed_usec: int = Time.get_ticks_usec() - started_usec
		var completed_ticks: int = int(session.sim.tick) - start_tick
		var fault: String = str(session.sim.fault_reason)
		if completed_ticks <= 0 or completed_ticks != TICKS_PER_BATCH or not fault.is_empty():
			batch_failure = "batch %d completed %d/%d ticks; fault='%s'" % [batch_index, completed_ticks, TICKS_PER_BATCH, fault]
			break
		if elapsed_usec <= 0:
			batch_failure = "batch %d timer returned a non-positive duration" % batch_index
			break
		var endpoint_checkpoint: Dictionary = session.checkpoint()
		if endpoint_checkpoint.is_empty():
			batch_failure = "FlightSession returned an empty endpoint checkpoint in batch %d" % batch_index
			break
		var endpoint_bytes: PackedByteArray = var_to_bytes(endpoint_checkpoint)
		var endpoint_hex: String = endpoint_bytes.hex_encode()
		if expected_endpoint_hex.is_empty():
			expected_endpoint_hex = endpoint_hex
		elif expected_endpoint_hex != endpoint_hex:
			deterministic_batches = false
		batches.append({
			"index": batch_index,
			"completed_ticks": completed_ticks,
			"elapsed_us": elapsed_usec,
			"us_per_tick": float(elapsed_usec) / float(TICKS_PER_BATCH),
			"checkpoint_bytes": endpoint_bytes.size(),
			"checkpoint_native_hex": endpoint_hex,
			"checkpoint_sha256": _sha256(endpoint_bytes),
		})
		timings.append(float(elapsed_usec) / float(TICKS_PER_BATCH))
	if not batch_failure.is_empty():
		session.free()
		return _failed_case(case, mode, batch_failure, {
			"batch_count": _batch_count,
			"completed_batch_count": batches.size(),
			"ticks_per_batch": TICKS_PER_BATCH,
			"warmup_ticks": WARMUP_TICKS,
			"seed_checkpoint_bytes": seed_bytes.size(),
			"seed_checkpoint_native_hex": seed_hex,
			"seed_checkpoint_sha256": seed_sha256,
			"batches": batches,
		})
	if not deterministic_batches:
		batch_failure = "endpoint checkpoint bytes differ across batches restored from one seed"
		session.free()
		var failed: Dictionary = _failed_case(case, mode, batch_failure)
		failed["batch_count"] = _batch_count
		failed["completed_batch_count"] = batches.size()
		failed["ticks_per_batch"] = TICKS_PER_BATCH
		failed["warmup_ticks"] = WARMUP_TICKS
		failed["seed_checkpoint_bytes"] = seed_bytes.size()
		failed["batches"] = batches
		failed["seed_checkpoint_native_hex"] = seed_hex
		failed["seed_checkpoint_sha256"] = seed_sha256
		return failed

	var replay: Dictionary = _trajectory_fingerprint(session, seed_checkpoint, seed_bytes, expected_endpoint_hex)
	session.free()
	if not replay.get("ok", false):
		return _failed_case(case, mode, str(replay.get("error", "trajectory replay failed")), {
			"batch_count": _batch_count,
			"completed_batch_count": batches.size(),
			"ticks_per_batch": TICKS_PER_BATCH,
			"warmup_ticks": WARMUP_TICKS,
			"seed_checkpoint_bytes": seed_bytes.size(),
			"seed_checkpoint_native_hex": seed_hex,
			"seed_checkpoint_sha256": seed_sha256,
			"batches": batches,
			"trajectory_fingerprint": replay,
		})
	var result: Dictionary = {
		"ok": true,
		"type": case.family,
		"id": case.id,
		"family": case.family,
		"pack": case.pack,
		"supply": case.supply,
		"aircraft_path": case.path,
		"mode": mode,
		"engine_running": mode == "powered",
		"batch_count": _batch_count,
		"ticks_per_batch": TICKS_PER_BATCH,
		"warmup_ticks": WARMUP_TICKS,
		"seed_checkpoint_bytes": seed_bytes.size(),
		"seed_checkpoint_native_hex": seed_hex,
		"seed_checkpoint_sha256": seed_sha256,
		"median_us_per_tick": _median(timings),
		"p95_us_per_tick": _percentile(timings, 0.95),
		"min_us_per_tick": _minimum(timings),
		"max_us_per_tick": _maximum(timings),
		"batch_checkpoint_bytes_identical": deterministic_batches,
		"completed_batch_count": batches.size(),
		"batches": batches,
		"trajectory_fingerprint": replay,
	}
	return result


func _advance_checked(session: Node, tick_count: int) -> int:
	var initial_tick: int = int(session.sim.tick)
	for _tick_index: int in tick_count:
		session.sim.step()
		if not str(session.sim.fault_reason).is_empty():
			break
	return int(session.sim.tick) - initial_tick


func _trajectory_fingerprint(session: Node, seed_checkpoint: Dictionary, seed_bytes: PackedByteArray,
		expected_endpoint_hex: String) -> Dictionary:
	if not session.restore_checkpoint(seed_checkpoint):
		return {"ok": false, "error": "warm checkpoint restore refused before trajectory replay"}
	var restored_bytes: PackedByteArray = var_to_bytes(session.checkpoint())
	if restored_bytes != seed_bytes:
		return {"ok": false, "error": "warm checkpoint native bytes changed before trajectory replay"}
	var digest: HashingContext = HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(seed_bytes)
	var completed: int = 0
	for _tick_index: int in TICKS_PER_BATCH:
		session.sim.step()
		if not str(session.sim.fault_reason).is_empty():
			return {"ok": false, "error": "trajectory replay fault after %d ticks: %s" % [completed, session.sim.fault_reason]}
		var checkpoint: Dictionary = session.checkpoint()
		if checkpoint.is_empty():
			return {"ok": false, "error": "trajectory replay returned an empty checkpoint after %d ticks" % (completed + 1)}
		digest.update(var_to_bytes(checkpoint))
		completed += 1
	var endpoint_bytes: PackedByteArray = var_to_bytes(session.checkpoint())
	var endpoint_hex: String = endpoint_bytes.hex_encode()
	if completed <= 0 or completed != TICKS_PER_BATCH or endpoint_hex != expected_endpoint_hex:
		return {"ok": false, "error": "trajectory replay endpoint differs from timed batch endpoint"}
	return {
		"ok": true,
		"ticks": completed,
		"includes_initial_checkpoint": true,
		"sha256": digest.finish().hex_encode(),
		"endpoint_checkpoint_sha256": _sha256(endpoint_bytes),
	}


func _failed_case(case: Dictionary, mode: String, message: String, details: Dictionary = {}) -> Dictionary:
	printerr("EL2a-P1 bench failed ", case.get("id", "unknown"), " / ", mode, ": ", message)
	var result: Dictionary = {
		"ok": false,
		"type": case.get("family", "unknown"),
		"id": case.get("id", "unknown"),
		"family": case.get("family", "unknown"),
		"pack": case.get("pack", "unknown"),
		"supply": case.get("supply", "unknown"),
		"mode": mode,
		"error": message,
	}
	for key: Variant in details:
		result[key] = details[key]
	return result


func _median(values: Array[float]) -> float:
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	var middle: int = sorted.size() >> 1
	if sorted.size() % 2 == 1:
		return sorted[middle]
	return 0.5 * (sorted[middle - 1] + sorted[middle])


func _percentile(values: Array[float], fraction: float) -> float:
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	var index: int = clampi(ceili(fraction * float(sorted.size())) - 1, 0, sorted.size() - 1)
	return sorted[index]


func _minimum(values: Array[float]) -> float:
	var result: float = INF
	for value: float in values:
		result = minf(result, value)
	return 0.0 if values.is_empty() else result


func _maximum(values: Array[float]) -> float:
	var result: float = -INF
	for value: float in values:
		result = maxf(result, value)
	return 0.0 if values.is_empty() else result


func _sha256(bytes: PackedByteArray) -> String:
	var digest: HashingContext = HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	return digest.finish().hex_encode()


func _write_report(report: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(_output_path, FileAccess.WRITE)
	if file == null:
		printerr("cannot write benchmark output '%s' (error %d)" % [_output_path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		printerr("write failed for benchmark output '%s' (error %d)" % [_output_path, write_error])
		return false
	print("wrote ", _output_path)
	return true

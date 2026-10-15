## Interleaved whole-session comparison; only road validation and packing differ.
## No quantization, cross-query caches, bypassed guards or altered physics settings.
extends SceneTree

const Session = preload("res://sim/ground_vehicle/session.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const BaselineSession = preload("res://../research/rc-monster-truck/monster-car-2/rcv42/baseline_session.gd")
const Schedule = preload("res://../research/rc-monster-truck/monster-car-2/rcv41/bench_session.gd")
const ROUNDS := 3
const WARMUP := 60
const TICKS := 960
var output := ""

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	if output.is_empty():
		_fail("--output=<json-path> required")
		return
	var field: Dictionary = FieldLoader.load_from()
	var runs: Array[Dictionary] = []
	for round_index in ROUNDS:
		var before := BaselineSession.new()
		var after := Session.new()
		for session in [before, after]:
			if not session.prepare_airfield(field, {}, {}, "monster-car-2") or not session.reset("track_start"):
				_fail("could not prepare paired session")
				return
		for session in [before, after]:
			if not session.tick_once(Schedule.NEUTRAL) or not session.resume():
				_fail("could not resume paired session")
				return
		var before_times := PackedFloat64Array()
		var after_times := PackedFloat64Array()
		var trajectory := HashingContext.new()
		trajectory.start(HashingContext.HASH_SHA256)
		for tick_index in WARMUP + TICKS:
			var controls := _controls(tick_index)
			# Alternate which implementation receives the warmer caches/scheduler slot.
			var order: Array = [before, after] if (tick_index + round_index) % 2 == 0 else [after, before]
			for session in order:
				var start := Time.get_ticks_usec()
				var ok: bool = session.tick_once(controls)
				var elapsed := Time.get_ticks_usec() - start
				if not ok:
					_fail(session.fault_reason)
					return
				if tick_index >= WARMUP:
					if session == before: before_times.append(elapsed)
					else: after_times.append(elapsed)
			var before_bytes: PackedByteArray = before.state_snapshot().to_byte_array()
			if before_bytes != after.state_snapshot().to_byte_array() \
					or var_to_bytes(before.telemetry_snapshot()) != var_to_bytes(after.telemetry_snapshot()):
				_fail("state/telemetry mismatch at tick %d" % tick_index)
				return
			trajectory.update(before_bytes)
		if before.control_tape_snapshot().to_byte_array() != after.control_tape_snapshot().to_byte_array() \
				or var_to_bytes(before.event_tape_snapshot()) != var_to_bytes(after.event_tape_snapshot()) \
				or before.checkpoint().checkpoint_sha256 != after.checkpoint().checkpoint_sha256:
			_fail("control tape, events or checkpoint mismatch")
			return
		runs.append({"round": round_index, "baseline": _summary(before_times), "candidate": _summary(after_times),
			"baseline_tick_us": before_times, "candidate_tick_us": after_times,
			"trajectory_sha256": trajectory.finish().hex_encode(),
			"checkpoint_sha256": before.checkpoint().checkpoint_sha256})
		before.free()
		after.free()
	var report := {"complete": runs.size() == ROUNDS, "engine": Engine.get_version_info().string,
		"processor": OS.get_processor_name(), "rounds": runs, "measured_ticks_per_round": TICKS,
		"exact_state_and_telemetry_ticks": (WARMUP + TICKS) * ROUNDS,
		"scope": "Paired production Sessions; baseline uses the retained pre-RCV42 body evaluator; candidate changes road validation and packing only, with the same current identity checks. Every tick retains all source checks. Tick order alternates; snapshots and comparisons are outside timing.",
		"source_sha256": {
			"session": FileAccess.get_sha256("res://sim/ground_vehicle/session.gd"),
			"dynamics": FileAccess.get_sha256("res://physics/ground_vehicle/vehicle_dynamics.gd"),
			"nitro": FileAccess.get_sha256("res://physics/ground_vehicle/nitro_dynamics.gd"),
			"baseline_body": FileAccess.get_sha256("res://../research/rc-monster-truck/monster-car-2/rcv42/baseline_vehicle_dynamics.gd"),
			"baseline_session": FileAccess.get_sha256("res://../research/rc-monster-truck/monster-car-2/rcv42/baseline_session.gd"),
			"harness": FileAccess.get_sha256(get_script().resource_path)}}
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		_fail("could not write report")
		return
	file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	file.close()
	for run in runs: print("RCV42 paired round: ", JSON.stringify({"baseline": run.baseline, "candidate": run.candidate}))
	quit(0)

func _controls(tick_index: int) -> Dictionary:
	if tick_index < WARMUP: return Schedule.NEUTRAL.duplicate()
	var index := tick_index - WARMUP
	for phase: Dictionary in Schedule.MEASURED_PHASES:
		if index < int(phase.ticks):
			return {"throttle": phase.throttle, "steering": phase.steering, "brake": phase.brake,
				"reverse": false, "armed": true}
		index -= int(phase.ticks)
	return Schedule.NEUTRAL.duplicate()

func _summary(values: PackedFloat64Array) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value in values: total += value
	return {"mean_us": total / values.size(), "median_us": sorted[sorted.size() / 2],
		"p95_us": sorted[int(ceil((sorted.size() - 1) * 0.95))], "samples": values.size()}

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

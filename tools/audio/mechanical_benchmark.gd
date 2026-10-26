extends SceneTree

## Bounded Dummy-driver benchmark of MechanicalAudio.update_sound().
## Usage: godot --headless --audio-driver Dummy --path app --script <repo>/tools/audio/mechanical_benchmark.gd -- --out=<absolute-report.json> [--iterations=10000] [--warmup=1000] [--observe-accepted]
## The snapshots and scene fixtures are built before timing. This measures the
## update call only; --observe-accepted additionally times one accepted endpoint
## capture per update separately. It excludes FlightAudio snapshot/signal costs
## and does not reproduce the production ticks/render ratio or native mixing.
const MechanicalAudio := preload("res://audio/mechanical_audio.gd")
const AUDIO_SOURCE: String = "res://audio/mechanical_audio.gd"
const MOTION_SOURCE: String = "res://audio/mechanical_motion.gd"
const DEFAULT_ITERATIONS: int = 10000
const DEFAULT_WARMUP: int = 1000
const MAX_ITERATIONS: int = 100000
const MAX_WARMUP: int = 100000
const SERVO_ANGLES: Array[float] = [1.0, -0.5, 0.75, -0.75]
const SERVO_IDS: Array[String] = ["aileron", "elevator", "rudder", "flap"]

var _output_path: String = ""
var _iterations: int = DEFAULT_ITERATIONS
var _warmup: int = DEFAULT_WARMUP
var _observe_accepted := false
var _capture_refusals := 0
var _rig: Node3D
var _camera: Camera3D
var _listener: AudioListener3D
var _audio: Node3D
var _listener_setting_before: bool = false


func _initialize() -> void:
	if not _parse_args():
		quit(2)
		return
	call_deferred("_run")


func _parse_args() -> bool:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_output_path = argument.trim_prefix("--out=").strip_edges()
		elif argument == "--observe-accepted":
			_observe_accepted = true
		elif argument.begins_with("--iterations="):
			var parsed_iterations: int = argument.trim_prefix("--iterations=").to_int()
			if parsed_iterations <= 0 or parsed_iterations > MAX_ITERATIONS:
				printerr("--iterations must be between 1 and %d" % MAX_ITERATIONS)
				return false
			_iterations = parsed_iterations
		elif argument.begins_with("--warmup="):
			var parsed_warmup: int = argument.trim_prefix("--warmup=").to_int()
			if parsed_warmup < 0 or parsed_warmup > MAX_WARMUP:
				printerr("--warmup must be between 0 and %d" % MAX_WARMUP)
				return false
			_warmup = parsed_warmup
	if _output_path.is_empty() or not _output_path.is_absolute_path():
		printerr("Usage: -- --out=<absolute-report.json> [--iterations=10000] [--warmup=1000] [--observe-accepted]")
		return false
	if FileAccess.file_exists(_output_path):
		printerr("Refusing to overwrite existing report: " + _output_path)
		return false
	var parent_directory: String = _output_path.get_base_dir()
	var make_dir: Error = DirAccess.make_dir_recursive_absolute(parent_directory)
	if make_dir != OK and not DirAccess.dir_exists_absolute(parent_directory):
		printerr("Could not create report directory: " + parent_directory)
		return false
	return true


func _run() -> void:
	var driver: String = AudioServer.get_driver_name()
	if driver.to_upper() != "DUMMY":
		printerr("mechanical_benchmark requires --audio-driver Dummy; actual driver is " + driver)
		quit(2)
		return
	var bus_count_before: int = AudioServer.bus_count
	_listener_setting_before = root.audio_listener_enable_3d
	root.audio_listener_enable_3d = true
	_rig = Node3D.new()
	_rig.name = "MechanicalAudioBenchmarkRig"
	root.add_child(_rig)
	_camera = Camera3D.new()
	_camera.name = "MechanicalAudioBenchmarkCamera"
	_rig.add_child(_camera)
	_camera.make_current()
	_listener = AudioListener3D.new()
	_camera.add_child(_listener)
	_listener.make_current()
	_audio = MechanicalAudio.new() as Node3D
	if _audio == null:
		printerr("MechanicalAudio did not construct a Node3D")
		_cleanup()
		quit(2)
		return
	_rig.add_child(_audio)
	_audio.configure(_rig, &"Master", {servo_type = "standard", servo_level = 0.75, retract_type = "electric"})
	_audio.set_accepted_tick_observation(_observe_accepted)
	await process_frame
	var setup_diagnostics: Dictionary = _audio.diagnostics()
	if not setup_diagnostics.get("missing_assets", []).is_empty():
		printerr("Installed mechanical audio assets did not load: %s" % str(setup_diagnostics.missing_assets))
		var failed_report: Dictionary = _base_report(driver)
		failed_report["error"] = "installed mechanical assets are missing"
		failed_report["setup_diagnostics"] = setup_diagnostics
		_cleanup()
		failed_report["quality_checks"] = {"scene_bus_count_restored": AudioServer.bus_count == bus_count_before}
		_write_report(failed_report)
		quit(1)
		return

	var results: Array[Dictionary] = []
	for scenario: Dictionary in _build_scenarios():
		results.append(_run_scenario(scenario))
	var final_diagnostics: Dictionary = _audio.diagnostics()
	var report: Dictionary = _base_report(driver)
	report["setup_diagnostics"] = setup_diagnostics
	report["timing"] = {
		"clock": "Time.get_ticks_usec() around update_sound only",
		"units": "microseconds per update call",
		"normalized_per_call": true,
		"snapshot_and_fixture_generation_timed": false,
		"diagnostics_timed": false,
		"native_mix_qualified": false,
		"timer_call_overhead_included": true,
		"percentile_rule": "nearest-rank (ceil(0.95*N)-1)",
		"accepted_capture_timed_separately": _observe_accepted,
		"accepted_calls_per_render_update": 1 if _observe_accepted else 0,
	}
	report["iterations_per_scenario"] = _iterations
	report["warmup_calls_per_scenario"] = _warmup
	report["results"] = results
	report["final_diagnostics"] = final_diagnostics
	report["accepted_capture_refusals"] = _capture_refusals
	var voices_bounded: bool = int(final_diagnostics.get("motion_voice_count", 0)) <= 6 \
		and int(final_diagnostics.get("event_voice_count", 0)) <= 2
	for result: Dictionary in results:
		voices_bounded = voices_bounded and int(result.get("motion_voice_count_after_measurement", 0)) <= 6 \
			and int(result.get("event_voice_count_after_measurement", 0)) <= 2
	_cleanup()
	var bus_count_restored: bool = AudioServer.bus_count == bus_count_before
	report["quality_checks"] = {
		"driver_is_dummy": driver.to_upper() == "DUMMY",
		"installed_assets_loaded": true,
		"voice_pools_within_runtime_limits": voices_bounded,
		"scene_bus_count_restored": bus_count_restored,
		"accepted_captures_valid": _capture_refusals == 0,
	}
	_write_report(report)
	print(JSON.stringify(report))
	quit(0 if voices_bounded and bus_count_restored and _capture_refusals == 0 else 1)


func _build_scenarios() -> Array[Dictionary]:
	var distant_positions: Array[Vector3] = [
		Vector3(0.0, 0.0, 100.0), Vector3(2.0, 1.0, 100.0),
		Vector3(-2.0, -1.0, 100.0), Vector3(0.0, 2.0, 100.0),
	]
	return [
		{"name": "quiet_idle", "delta_s": 1.0 / 60.0,
			"snapshot": _snapshot(0, 0.0, 0.0, Vector3.ZERO, false, false)},
		{"name": "nearby_moving_4_servos_plus_gear", "delta_s": 1.0 / 60.0,
			"snapshot": _snapshot(0, 0.0, 0.2, Vector3.ZERO, true, false)},
		{"name": "paused", "delta_s": 1.0 / 60.0,
			"snapshot": _snapshot(0, 8.0, 0.5, Vector3.ZERO, false, true)},
		{"name": "distant", "delta_s": 1.0 / 60.0,
			"snapshot": _snapshot(0, 0.0, 0.2, Vector3.ZERO, false, false, distant_positions)},
		{"name": "repeated_accepted_tick", "delta_s": 0.0,
			"snapshot": _snapshot(101, 1.0, 0.7, Vector3.ZERO, true, false),
			"prime_snapshot": _snapshot(100, 0.0, 0.2, Vector3.ZERO, false, false)},
	]


func _snapshot(tick: int, angle: float, extension: float, listener_position: Vector3,
		target_down: bool, paused: bool, positions: Array[Vector3] = []) -> Dictionary:
	var channels: Array[Dictionary] = []
	for index: int in SERVO_IDS.size():
		var source_position: Vector3 = positions[index] if index < positions.size() \
			else Vector3(float(index - 1), 0.0, 0.0)
		channels.append({"id": SERVO_IDS[index], "angle_deg": angle, "position": source_position})
	var gear_position: Vector3 = positions[0] if not positions.is_empty() else Vector3.ZERO
	return {
		"tick": tick,
		"tick_rate": 240.0,
		"paused": paused,
		"listener": listener_position,
		"engine_mask": 1.0,
		"channels": channels,
		"gear": {"available": true, "extension": extension, "target_down": target_down,
			"status": "down" if extension >= 0.999999 else "up" if extension <= 0.000001 else "moving",
			"position": gear_position},
	}


func _run_scenario(scenario: Dictionary) -> Dictionary:
	var name: String = str(scenario.name)
	var delta: float = float(scenario.delta_s)
	var snapshot: Dictionary = scenario.snapshot
	_audio.reset()
	if _observe_accepted:
		_audio.observe_accepted(scenario.get("prime_snapshot", snapshot))
	if scenario.has("prime_snapshot"):
		_audio.update_sound(scenario.prime_snapshot, delta)
		if _observe_accepted: _audio.observe_accepted(snapshot)
		_audio.update_sound(snapshot, delta)
	for index: int in _warmup:
		_prepare_sample(name, snapshot, index)
		if _observe_accepted: _audio.observe_accepted(snapshot)
		_audio.update_sound(snapshot, delta)
	var after_warmup: Dictionary = _audio.diagnostics()
	var object_count_before: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var samples: PackedInt64Array = PackedInt64Array()
	samples.resize(_iterations)
	var capture_samples := PackedInt64Array()
	if _observe_accepted: capture_samples.resize(_iterations)
	for index: int in _iterations:
		_prepare_sample(name, snapshot, index + _warmup)
		if _observe_accepted:
			var capture_start := Time.get_ticks_usec()
			var captured: bool = _audio.observe_accepted(snapshot)
			capture_samples[index] = Time.get_ticks_usec() - capture_start
			if not captured: _capture_refusals += 1
		var start_usec: int = Time.get_ticks_usec()
		_audio.update_sound(snapshot, delta)
		samples[index] = Time.get_ticks_usec() - start_usec
	var object_count_after: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var after_measurement: Dictionary = _audio.diagnostics()
	samples.sort()
	var median: float = _median_usec(samples)
	var p95_index: int = clampi(int(ceil(0.95 * float(samples.size()))) - 1, 0, samples.size() - 1)
	var p95: int = int(samples[p95_index])
	var maximum: int = int(samples[samples.size() - 1])
	var result := {
		"name": name,
		"iterations": _iterations,
		"warmup_calls": _warmup,
		"delta_s": delta,
		"median_usec_per_update": median,
		"p95_usec_per_update": p95,
		"max_usec_per_update": maximum,
		"min_usec_per_update": int(samples[0]),
		"mean_usec_per_update": _mean_usec(samples),
		"normalized_per_call": true,
		"snapshot_generation_timed": false,
		"voice_counts_after_warmup": _voice_counts(after_warmup),
		"motion_voice_count_after_measurement": int(after_measurement.get("motion_voice_count", 0)),
		"event_voice_count_after_measurement": int(after_measurement.get("event_voice_count", 0)),
		"active_motion_voices_after_measurement": int(after_measurement.get("active_motion_voices", 0)),
		"playing_event_voices_after_measurement": int(after_measurement.get("playing_event_voices", 0)),
		"motion_voice_growth_during_measurement": int(after_measurement.get("motion_voice_count", 0))
			- int(after_warmup.get("motion_voice_count", 0)),
		"event_voice_growth_during_measurement": int(after_measurement.get("event_voice_count", 0))
			- int(after_warmup.get("event_voice_count", 0)),
		"godot_object_count_before_measurement": object_count_before,
		"godot_object_count_after_measurement": object_count_after,
		"godot_object_count_delta": object_count_after - object_count_before,
		"per_call_allocation_counter_available": false,
	}
	if _observe_accepted:
		capture_samples.sort()
		result["accepted_capture"] = {
			"calls": capture_samples.size(), "units": "microseconds per observe_accepted call",
			"median_usec": _median_usec(capture_samples), "p95_usec": int(capture_samples[p95_index]),
			"max_usec": int(capture_samples[-1]), "mean_usec": _mean_usec(capture_samples),
			"snapshot_generation_timed": false, "includes_adapter_and_signal_dispatch": false,
			"pending_events_after_measurement": after_measurement.accepted_pending_event_count,
			"observed_events_during_measurement": after_measurement.accepted_events_observed - after_warmup.accepted_events_observed,
			"overflow_during_measurement": after_measurement.accepted_events_overflowed - after_warmup.accepted_events_overflowed,
		}
	return result


func _prepare_sample(name: String, snapshot: Dictionary, iteration: int) -> void:
	if name == "repeated_accepted_tick":
		return
	snapshot["tick"] = int(snapshot.tick) + 1
	if name != "nearby_moving_4_servos_plus_gear":
		return
	var moving_phase: bool = iteration % 2 == 0
	var channels: Array = snapshot.channels
	for index: int in channels.size():
		var channel: Dictionary = channels[index]
		channel["angle_deg"] = SERVO_ANGLES[index] if moving_phase else 0.0
	var gear: Dictionary = snapshot.gear
	gear["extension"] = 0.75 if moving_phase else 0.25
	gear["target_down"] = moving_phase
	gear["status"] = "moving"


func _voice_counts(diagnostics: Dictionary) -> Dictionary:
	return {
		"motion": int(diagnostics.get("motion_voice_count", 0)),
		"event": int(diagnostics.get("event_voice_count", 0)),
		"active_motion": int(diagnostics.get("active_motion_voices", 0)),
		"playing_events": int(diagnostics.get("playing_event_voices", 0)),
	}


func _median_usec(samples: PackedInt64Array) -> float:
	var middle: int = samples.size() / 2
	if samples.size() % 2 == 1:
		return float(samples[middle])
	return (float(samples[middle - 1]) + float(samples[middle])) * 0.5


func _mean_usec(samples: PackedInt64Array) -> float:
	var total: float = 0.0
	for sample: int in samples:
		total += float(sample)
	return total / float(samples.size()) if not samples.is_empty() else 0.0


func _base_report(driver: String) -> Dictionary:
	return {
		"format": "openrc-mechanical-audio-benchmark-v1",
		"scope": "Direct MechanicalAudio.update_sound() microbenchmark using the installed audio bank. Not a native mixer or whole-flight qualification.",
		"accepted_tick_observation": _observe_accepted,
		"godot": Engine.get_version_info().string,
		"engine_hash": Engine.get_version_info().hash,
		"driver": driver,
		"native_mix_qualified": false,
		"os": OS.get_name(),
		"processor": OS.get_processor_name(),
		"source_sha256": _source_hashes(),
	}


func _source_hashes() -> Dictionary:
	var benchmark_path: String = get_script().resource_path
	return {
		"app/audio/mechanical_audio.gd": FileAccess.get_sha256(AUDIO_SOURCE),
		"app/audio/mechanical_motion.gd": FileAccess.get_sha256(MOTION_SOURCE),
		"tools/audio/mechanical_benchmark.gd": FileAccess.get_sha256(benchmark_path),
	}


func _write_report(report: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(_output_path, FileAccess.WRITE)
	if file == null:
		printerr("Could not write benchmark report: " + _output_path)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()


func _cleanup() -> void:
	if is_instance_valid(_audio):
		if is_instance_valid(_audio.get_parent()):
			_audio.get_parent().remove_child(_audio)
		_audio.free()
	if is_instance_valid(_rig):
		if _rig.get_parent() == root:
			root.remove_child(_rig)
		_rig.free()
	root.audio_listener_enable_3d = _listener_setting_before

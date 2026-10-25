extends SceneTree

## AUD-16 staged presentation bench. It drives MechanicalAudio directly with
## accepted-position-shaped snapshots; it does not instantiate FlightAudio or a
## live flight. Captures are native Godot mixer output, not human listening.
const AUDIO_SCRIPT_PATH: String = "res://audio/mechanical_audio.gd"
const ASSET_DIR: String = "res://assets/audio/mechanical/"
const SERVO_TYPES: Array[String] = ["standard", "high_torque"]
const RETRACT_TYPES: Array[String] = ["electric", "pneumatic"]
const DEFAULT_FPS: int = 60
const RMS_FLOOR: float = 1e-12
const CLIP_LIMIT_DBFS: float = -0.9

var _output_dir: String = ""
var _expected_driver: String = "WASAPI"
var _fps: int = DEFAULT_FPS
var _audio_script: Script
var _rig: Node3D
var _camera: Camera3D
var _listener: AudioListener3D
var _audio: Node
var _capture: AudioEffectCapture
var _capture_bus_index: int = -1
var _stage_samples: PackedVector2Array = PackedVector2Array()
var _stage_sum_squares: float = 0.0
var _stage_peak: float = 0.0
var _stage_frames: int = 0
var _stage_discarded: int = 0
var _invalid_sample: bool = false
var _stage_results: Array[Dictionary] = []
var _asset_receipts: Array[Dictionary] = []
var _update_times_usec: Array[int] = []
var _overall_update_times_usec: Array[int] = []
var _overall_peak: float = 0.0
var _overall_sum_squares: float = 0.0
var _overall_frames: int = 0
var _overall_discarded: int = 0
var _overall_invalid_sample: bool = false
var _wav_failures: Array[String] = []
var _bus_count_start: int = 0


func _initialize() -> void:
	_parse_args()
	call_deferred("_run")


func _parse_args() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_output_dir = argument.trim_prefix("--out=")
		elif argument.begins_with("--fps="):
			var parsed: int = argument.trim_prefix("--fps=").to_int()
			if parsed > 0:
				_fps = parsed
		elif argument.begins_with("--require-driver="):
			_expected_driver = argument.trim_prefix("--require-driver=").strip_edges()


func _run() -> void:
	if not _valid_output_directory():
		quit(2)
		return
	if _fps not in [30, 60, 144]:
		printerr("mechanical_probe supports --fps=30, 60, or 144")
		quit(2)
		return
	Engine.max_fps = _fps
	var actual_driver: String = AudioServer.get_driver_name()
	if actual_driver.to_upper() == "DUMMY" or (not _expected_driver.is_empty()
		and actual_driver.to_upper() != _expected_driver.to_upper()):
		printerr("Requested native driver %s; actual driver is %s" % [_expected_driver, actual_driver])
		quit(2)
		return
	_audio_script = load(AUDIO_SCRIPT_PATH) as Script
	if _audio_script == null:
		printerr("MechanicalAudio script did not load: " + AUDIO_SCRIPT_PATH)
		quit(2)
		return
	if not _load_asset_matrix():
		printerr("Required real mechanical WAV resources did not load; see the asset receipts in the report.")
		_write_early_report(actual_driver)
		quit(1)
		return

	_bus_count_start = AudioServer.bus_count
	root.audio_listener_enable_3d = true
	_rig = Node3D.new()
	_rig.name = "MechanicalAudioStagedProbe"
	root.add_child(_rig)
	_camera = Camera3D.new()
	_camera.name = "MechanicalAudioListenerCamera"
	_rig.add_child(_camera)
	_camera.make_current()
	_listener = AudioListener3D.new()
	_camera.add_child(_listener)
	_listener.make_current()
	_audio = _audio_script.new() as Node
	if _audio == null:
		printerr("MechanicalAudio did not construct a Node")
		_cleanup()
		quit(2)
		return
	_rig.add_child(_audio)
	_capture_bus_index = AudioServer.get_bus_index(&"Master")
	if _capture_bus_index < 0:
		printerr("Master audio bus is missing")
		_cleanup()
		quit(2)
		return
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 1.0
	AudioServer.add_bus_effect(_capture_bus_index, _capture)
	await process_frame

	for servo_type: String in SERVO_TYPES:
		for retract_type: String in RETRACT_TYPES:
			var config: Dictionary = {servo_type = servo_type, servo_level = 0.75, retract_type = retract_type}
			_audio.call("configure", _rig, &"Master", config)
			var setup: Dictionary = _audio.call("diagnostics")
			if not setup.get("missing_assets", []).is_empty():
				_wav_failures.append("%s/%s missing runtime assets: %s" % [servo_type, retract_type, setup.missing_assets])
			for stage_spec: Dictionary in _stage_schedule():
				_audio.call("reset")
				var result: Dictionary = await _run_stage(servo_type, retract_type, config, stage_spec)
				_stage_results.append(result)
				if not result.get("wav_saved", false):
					_wav_failures.append(str(result.get("wav_path", "stage WAV")))
				if int(result.get("discarded_frames", 0)) > 0:
					_overall_discarded += int(result.discarded_frames)

	var final_diagnostics: Dictionary = _audio.call("diagnostics")
	var captured_seconds: float = float(_overall_frames) / maxf(float(AudioServer.get_mix_rate()), 1.0)
	var wall_seconds: float = 0.0
	for stage: Dictionary in _stage_results:
		wall_seconds += float(stage.get("wall_seconds", 0.0))
	var total_peak_dbfs: float = linear_to_db(maxf(_overall_peak, RMS_FLOOR))
	var total_rms_dbfs: float = _rms_dbfs(_overall_sum_squares, _overall_frames)
	var no_clipping: bool = total_peak_dbfs < CLIP_LIMIT_DBFS
	var finite_signal: bool = not _overall_invalid_sample and _overall_frames > 0
	var signal_present: bool = _overall_peak > RMS_FLOOR
	var pooling_bounded: bool = int(final_diagnostics.get("motion_voice_count", 0)) <= 6 \
		and int(final_diagnostics.get("event_voice_count", 0)) <= 2
	for stage: Dictionary in _stage_results:
		pooling_bounded = pooling_bounded and int(stage.get("max_motion_voice_count", 0)) <= 6 \
			and int(stage.get("max_event_voice_count", 0)) <= 2 \
			and not bool(stage.get("timed_out", false))
	_cleanup()
	await create_timer(0.1).timeout
	var bus_count_after_cleanup: int = AudioServer.bus_count
	var report: Dictionary = {
		"format": "openrc-mechanical-audio-staged-probe-v1",
		"scope": "Staged MechanicalAudio playback with the real installed WAV resources through the actual Godot native mixer. Synthetic accepted-position-shaped snapshots; no FlightAudio, live flight, soundscape engine voice, human listening, speaker calibration or target-device qualification.",
		"godot": Engine.get_version_info().string,
		"driver": actual_driver,
		"required_driver": _expected_driver,
		"display_driver": DisplayServer.get_name(),
		"requested_fps": _fps,
		"mix_rate_hz": AudioServer.get_mix_rate(),
		"capture_bus": "Master",
		"capture_after_master_effects": true,
		"captured_frames": _overall_frames,
		"captured_seconds": captured_seconds,
		"scripted_wall_seconds": wall_seconds,
		"total_rms_dbfs": total_rms_dbfs,
		"total_peak_dbfs": total_peak_dbfs,
		"discarded_frames": _overall_discarded,
		"update_count": _overall_update_times_usec.size(),
		"update_p50_usec": _percentile_usec(_overall_update_times_usec, 0.50),
		"update_p95_usec": _percentile_usec(_overall_update_times_usec, 0.95),
		"update_max_usec": _maximum_usec(_overall_update_times_usec),
		"asset_receipts": _asset_receipts,
		"asset_manifest_sha256": _sha256_resource(ASSET_DIR + "manifest.json"),
		"profile_matrix": _profile_matrix(),
		"engine_mask_cases": [0.0, 0.5, 1.0],
		"voice_pool_limits": {"motion": 6, "event": 2},
		"final_voice_diagnostics": final_diagnostics,
		"stage_results": _stage_results,
		"cleanup_bus_count_start": _bus_count_start,
		"cleanup_bus_count_after": bus_count_after_cleanup,
		"quality_checks": {
			"actual_driver_matches_required": _expected_driver.is_empty() or actual_driver.to_upper() == _expected_driver.to_upper(),
			"real_assets_loaded": _wav_failures.is_empty(),
			"finite_signal": finite_signal,
			"signal_present": signal_present,
			"peak_below_dbfs": CLIP_LIMIT_DBFS,
			"no_clipping": no_clipping,
			"no_capture_discards": _overall_discarded == 0,
			"bus_count_restored": bus_count_after_cleanup == _bus_count_start,
			"voice_pool_bounded": pooling_bounded,
			"all_stage_wavs_saved": _wav_failures.is_empty(),
			"wav_failures": _wav_failures,
		},
	}
	var report_file: FileAccess = FileAccess.open(_output_dir.path_join("report.json"), FileAccess.WRITE)
	if report_file != null:
		report_file.store_string(JSON.stringify(report, "\t"))
		report_file.close()
	print(JSON.stringify(report))
	var passed: bool = actual_driver.to_upper() == _expected_driver.to_upper() \
		and _wav_failures.is_empty() and finite_signal and signal_present and no_clipping \
		and _overall_discarded == 0 and pooling_bounded and bus_count_after_cleanup == _bus_count_start \
		and report_file != null
	quit(0 if passed else 1)


func _stage_schedule() -> Array[Dictionary]:
	return [
		{name = "idle", mode = "idle", seconds = 0.75, engine_mask = 1.0},
		{name = "servo_small_slow", mode = "servo_small_slow", seconds = 1.0, engine_mask = 1.0},
		{name = "servo_large_fast", mode = "servo_large_fast", seconds = 1.0, engine_mask = 1.0},
		{name = "simultaneous_servos", mode = "simultaneous", seconds = 1.0, engine_mask = 1.0},
		{name = "gear_extension_reversal_interruption_endpoint", mode = "gear_sequence", seconds = 2.3, engine_mask = 1.0},
		{name = "near_far_listener_camera_motion", mode = "near_far", seconds = 1.6, engine_mask = 1.0},
		{name = "engine_mask_0", mode = "servo_small_slow", seconds = 0.8, engine_mask = 0.0},
		{name = "engine_mask_05", mode = "servo_small_slow", seconds = 0.8, engine_mask = 0.5},
		{name = "engine_mask_1", mode = "servo_small_slow", seconds = 0.8, engine_mask = 1.0},
		{name = "pause_reset_rewind_detach_reattach_configure", mode = "lifecycle", seconds = 2.2, engine_mask = 1.0},
	]


func _run_stage(servo_type: String, retract_type: String, config: Dictionary,
		stage_spec: Dictionary) -> Dictionary:
	var profile_name: String = servo_type + "_" + retract_type
	var stage_name: String = str(stage_spec.name)
	var profile_dir: String = _output_dir.path_join(profile_name)
	var make_dir: Error = DirAccess.make_dir_recursive_absolute(profile_dir)
	if make_dir != OK and not DirAccess.dir_exists_absolute(profile_dir):
		return {"name": stage_name, "profile": profile_name, "wav_saved": false,
			"wav_path": profile_dir, "error": "could not create profile output directory"}
	var record: Dictionary = {
		"name": stage_name,
		"profile": profile_name,
		"mode": str(stage_spec.mode),
		"scripted_engine_mask": float(stage_spec.engine_mask),
		"capture_bus": "Master",
		"frames": 0,
		"sum_squares": 0.0,
		"peak": 0.0,
		"discarded_frames": 0,
		"update_times_usec": [],
		"max_motion_voice_count": 0,
		"max_event_voice_count": 0,
		"max_active_motion_voices": 0,
		"max_playing_event_voices": 0,
		"events_played_start": int(_audio.call("diagnostics").get("events_played", 0)),
		"events_dropped_start": int(_audio.call("diagnostics").get("events_dropped", 0)),
		"far_culled_events_start": int(_audio.call("diagnostics").get("far_culled_events", 0)),
		"far_culled_motion_start": int(_audio.call("diagnostics").get("far_culled_motion_updates", 0)),
		"stale_tick_resets_start": int(_audio.call("diagnostics").get("stale_tick_resets", 0)),
	}
	_stage_samples = PackedVector2Array()
	_stage_sum_squares = 0.0
	_stage_peak = 0.0
	_stage_frames = 0
	_stage_discarded = 0
	_update_times_usec = []
	_invalid_sample = false
	if _capture.get_frames_available() > 0:
		_capture.get_buffer(_capture.get_frames_available())
	var discarded_before: int = _capture.get_discarded_frames()
	var lifecycle_reset_done: bool = false
	var lifecycle_detached: bool = false
	var lifecycle_configured: bool = false
	var last_update_usec: int = Time.get_ticks_usec()
	var stage_start_usec: int = last_update_usec
	var elapsed: float = 0.0
	var wall_timeout_usec: int = int(float(stage_spec.seconds) * 1000000.0 * 2.0) + 3000000
	var mode: String = str(stage_spec.mode)
	while elapsed < float(stage_spec.seconds):
		await process_frame
		var now_usec: int = Time.get_ticks_usec()
		if now_usec - stage_start_usec > wall_timeout_usec:
			record["timed_out"] = true
			break
		elapsed = float(now_usec - stage_start_usec) / 1000000.0
		var delta: float = clampf(float(now_usec - last_update_usec) / 1000000.0, 0.0, 0.1)
		if delta <= 0.0:
			delta = 1.0 / float(_fps)
		last_update_usec = now_usec
		if mode == "lifecycle":
			if elapsed >= 0.52 and not lifecycle_reset_done:
				_audio.call("reset")
				lifecycle_reset_done = true
			if elapsed >= 1.25 and not lifecycle_detached and not lifecycle_configured:
				_rig.remove_child(_audio)
				lifecycle_detached = true
			if elapsed >= 1.42 and lifecycle_detached and not lifecycle_configured:
				_rig.add_child(_audio)
				_audio.call("configure", _rig, &"Master", config)
				lifecycle_detached = false
				lifecycle_configured = true
		if lifecycle_detached:
			_drain_capture()
			continue
		var stage_state: Dictionary = _stage_snapshot(mode, elapsed, int(stage_start_usec / 1000),
			float(stage_spec.engine_mask))
		_camera.position = stage_state.listener
		var update_start: int = Time.get_ticks_usec()
		_audio.call("update_sound", stage_state, delta)
		var update_usec: int = Time.get_ticks_usec() - update_start
		_update_times_usec.append(update_usec)
		_overall_update_times_usec.append(update_usec)
		var diagnostics: Dictionary = _audio.call("diagnostics")
		record["update_count"] = int(record.get("update_count", 0)) + 1
		record["max_motion_voice_count"] = maxi(int(record.max_motion_voice_count),
			int(diagnostics.get("motion_voice_count", 0)))
		record["max_event_voice_count"] = maxi(int(record.max_event_voice_count),
			int(diagnostics.get("event_voice_count", 0)))
		record["max_active_motion_voices"] = maxi(int(record.max_active_motion_voices),
			int(diagnostics.get("active_motion_voices", 0)))
		record["max_playing_event_voices"] = maxi(int(record.max_playing_event_voices),
			int(diagnostics.get("playing_event_voices", 0)))
		_drain_capture(record)
	var discarded_after: int = _capture.get_discarded_frames()
	_stage_discarded += maxi(0, discarded_after - discarded_before)
	var wav_path: String = profile_dir.path_join(stage_name + ".wav")
	var wav_error: Error = _save_wav(wav_path, _stage_samples)
	var diag_end: Dictionary = _audio.call("diagnostics")
	var times: Array[int] = _update_times_usec.duplicate()
	times.sort()
	var result: Dictionary = {
		"name": stage_name,
		"profile": profile_name,
		"mode": mode,
		"scripted_engine_mask": float(stage_spec.engine_mask),
		"wall_seconds": elapsed,
		"mix_rate_hz": AudioServer.get_mix_rate(),
		"frames": _stage_frames,
		"captured_seconds": float(_stage_frames) / maxf(float(AudioServer.get_mix_rate()), 1.0),
		"rms_dbfs": _rms_dbfs(_stage_sum_squares, _stage_frames),
		"peak_dbfs": linear_to_db(maxf(_stage_peak, RMS_FLOOR)),
		"discarded_frames": _stage_discarded,
		"update_count": times.size(),
		"update_p50_usec": _percentile_usec(times, 0.50),
		"update_p95_usec": _percentile_usec(times, 0.95),
		"update_max_usec": _maximum_usec(times),
		"max_motion_voice_count": int(record.max_motion_voice_count),
		"max_event_voice_count": int(record.max_event_voice_count),
		"max_active_motion_voices": int(record.max_active_motion_voices),
		"max_playing_event_voices": int(record.max_playing_event_voices),
		"events_played": int(diag_end.get("events_played", 0)) - int(record.events_played_start),
		"events_dropped": int(diag_end.get("events_dropped", 0)) - int(record.events_dropped_start),
		"far_culled_events": int(diag_end.get("far_culled_events", 0)) - int(record.far_culled_events_start),
		"far_culled_motion_updates": int(diag_end.get("far_culled_motion_updates", 0)) - int(record.far_culled_motion_start),
		"stale_tick_resets": int(diag_end.get("stale_tick_resets", 0)) - int(record.stale_tick_resets_start),
		"lifecycle_reset_ran": lifecycle_reset_done,
		"lifecycle_detach_reattach_ran": lifecycle_configured,
		"wav_path": wav_path,
		"wav_saved": wav_error == OK,
		"timed_out": bool(record.get("timed_out", false)),
	}
	return result


func _stage_snapshot(mode: String, elapsed: float, tick_origin_ms: int, engine_mask: float) -> Dictionary:
	var angle: float = 0.0
	var extension: float = 0.0
	var target_down: bool = false
	var listener_position: Vector3 = Vector3.ZERO
	var paused: bool = false
	var local_time: float = elapsed
	var tick: int = 100000 + int(floor(local_time * 240.0))
	match mode:
		"servo_small_slow":
			angle = 8.0 * clampf(elapsed / 0.72, 0.0, 1.0)
		"servo_large_fast":
			angle = 90.0 * clampf((elapsed - 0.12) / 0.2, 0.0, 1.0)
		"simultaneous":
			angle = 24.0 * clampf(elapsed / 0.42, 0.0, 1.0)
		"gear_sequence":
			if elapsed < 0.25:
				target_down = true # command alone, no accepted movement
			elif elapsed < 0.78:
				target_down = true
				extension = lerpf(0.0, 0.78, (elapsed - 0.25) / 0.53)
			elif elapsed < 1.02:
				target_down = false
				extension = lerpf(0.78, 0.48, (elapsed - 0.78) / 0.24)
			elif elapsed < 1.3:
				target_down = false # interruption/hold
				extension = 0.48
			elif elapsed < 1.92:
				target_down = true
				extension = lerpf(0.48, 1.0, (elapsed - 1.3) / 0.62)
			else:
				target_down = true
				extension = 1.0
		"near_far":
			angle = 20.0 * clampf(elapsed / 1.25, 0.0, 1.0)
			if elapsed >= 0.48 and elapsed < 1.0:
				listener_position = Vector3(0.0, 0.0, 100.0)
		"lifecycle":
			if elapsed < 0.26:
				angle = 18.0 * clampf(elapsed / 0.26, 0.0, 1.0)
			elif elapsed < 0.52:
				angle = 18.0
				paused = true
			elif elapsed < 0.9:
				angle = 0.0
				extension = 0.0
			elif elapsed < 1.25:
				tick = 2 + int(floor((elapsed - 0.9) * 240.0)) # explicit rewind segment
				angle = -12.0 * clampf((elapsed - 0.9) / 0.35, 0.0, 1.0)
			elif elapsed < 1.42:
				angle = -12.0
			else:
				angle = 15.0 * clampf((elapsed - 1.42) / 0.5, 0.0, 1.0)
	return {
		"tick": tick,
		"tick_rate": 240.0,
		"paused": paused,
		"listener": listener_position,
		"engine_mask": engine_mask,
		"channels": [
			{id = "aileron", angle_deg = angle, position = Vector3(1.0, 0.0, 0.0)},
			{id = "elevator", angle_deg = -angle * 0.55, position = Vector3(0.0, 1.0, 0.0)},
			{id = "rudder", angle_deg = angle * 0.3, position = Vector3(0.0, 0.0, 1.0)},
			{id = "flap", angle_deg = angle * 0.7, position = Vector3(-1.0, 0.0, 0.0)},
		],
		"gear": {available = true, extension = extension, target_down = target_down,
			status = "down" if extension >= 0.999999 else "up" if extension <= 0.000001 else "moving",
			position = Vector3.ZERO},
	}


func _load_asset_matrix() -> bool:
	var all_valid: bool = true
	for servo_type: String in SERVO_TYPES:
		for retract_type: String in RETRACT_TYPES:
			for relative_path: String in _asset_paths(servo_type, retract_type):
				var path: String = ASSET_DIR + relative_path
				var exists: bool = ResourceLoader.exists(path)
				var stream: AudioStreamWAV = ResourceLoader.load(path) as AudioStreamWAV if exists else null
				var valid: bool = stream != null and not stream.data.is_empty() and stream.mix_rate > 0 \
					and stream.format == AudioStreamWAV.FORMAT_16_BITS
				var digest: String = _sha256_resource(path) if exists else ""
				_asset_receipts.append({path = path, exists = exists, loaded_pcm16 = valid,
					bytes = stream.data.size() if stream != null else 0,
					mix_rate_hz = stream.mix_rate if stream != null else 0,
					seconds = stream.get_length() if stream != null else 0.0,
					sha256 = digest})
				all_valid = all_valid and valid
	return all_valid


func _asset_paths(servo_type: String, retract_type: String) -> Array[String]:
	var paths: Array[String] = [
		"servo_%s_loop.wav" % servo_type,
		"servo_%s_start.wav" % servo_type,
		"servo_%s_start_02.wav" % servo_type,
		"servo_%s_stop.wav" % servo_type,
		"servo_%s_stop_02.wav" % servo_type,
	]
	if retract_type == "electric":
		paths.append_array(["retract_electric_loop.wav", "retract_electric_start.wav", "retract_electric_lock.wav"])
	else:
		paths.append_array(["retract_pneumatic_loop.wav", "retract_pneumatic_hiss.wav",
			"retract_pneumatic_valve.wav", "retract_pneumatic_lock.wav"])
	return paths


func _profile_matrix() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for servo_type: String in SERVO_TYPES:
		for retract_type: String in RETRACT_TYPES:
			result.append({servo_type = servo_type, servo_level = 0.75, retract_type = retract_type})
	return result


func _drain_capture(record: Dictionary = {}) -> void:
	var available: int = _capture.get_frames_available()
	if available <= 0:
		return
	var samples: PackedVector2Array = _capture.get_buffer(available)
	for sample: Vector2 in samples:
		var clean: Vector2 = sample
		if not is_finite(clean.x) or not is_finite(clean.y):
			_invalid_sample = true
			_overall_invalid_sample = true
			clean = Vector2.ZERO
		_stage_samples.append(clean)
		_stage_frames += 1
		var squared: float = clean.length_squared()
		_stage_sum_squares += squared
		_stage_peak = maxf(_stage_peak, maxf(absf(clean.x), absf(clean.y)))
		_overall_sum_squares += squared
		_overall_peak = maxf(_overall_peak, maxf(absf(clean.x), absf(clean.y)))
		_overall_frames += 1
	if not record.is_empty():
		record["frames"] = _stage_frames
		record["sum_squares"] = _stage_sum_squares
		record["peak"] = _stage_peak


func _save_wav(path: String, samples: PackedVector2Array) -> Error:
	if samples.is_empty():
		return ERR_FILE_CORRUPT
	var wav := AudioStreamWAV.new()
	wav.mix_rate = AudioServer.get_mix_rate()
	wav.stereo = true
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	var data := PackedByteArray()
	data.resize(samples.size() * 4)
	for index: int in samples.size():
		data.encode_s16(index * 4, clampi(roundi(samples[index].x * 32767.0), -32768, 32767))
		data.encode_s16(index * 4 + 2, clampi(roundi(samples[index].y * 32767.0), -32768, 32767))
	wav.data = data
	return wav.save_to_wav(path)


func _rms_dbfs(sum_squares: float, frames: int) -> float:
	var rms: float = sqrt(maxf(sum_squares, 0.0) / maxf(float(frames) * 2.0, 1.0))
	return linear_to_db(maxf(rms, RMS_FLOOR))


func _percentile_usec(times: Array[int], percentile: float) -> int:
	if times.is_empty():
		return 0
	var ordered: Array[int] = times.duplicate()
	ordered.sort()
	var index: int = clampi(ceili(float(ordered.size()) * percentile) - 1, 0, ordered.size() - 1)
	return ordered[index]


func _maximum_usec(times: Array[int]) -> int:
	var maximum: int = 0
	for value: int in times:
		maximum = maxi(maximum, value)
	return maximum


func _sha256_resource(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK or context.update(FileAccess.get_file_as_bytes(path)) != OK:
		return ""
	return context.finish().hex_encode()


func _valid_output_directory() -> bool:
	if _output_dir.is_empty() or not _output_dir.is_absolute_path():
		printerr("Usage: -- --out=<new absolute directory under repository tmp/> [--fps=30|60|144] [--require-driver=WASAPI]")
		return false
	var repo_root: String = ProjectSettings.globalize_path("res://").simplify_path().get_base_dir()
	var candidate: String = _output_dir.simplify_path()
	var tmp_root: String = repo_root.path_join("tmp").simplify_path()
	if OS.get_name() == "Windows":
		var prefix_windows: String = tmp_root.replace("/", "\\").to_lower() + "\\"
		var candidate_windows: String = candidate.replace("/", "\\").to_lower()
		if not candidate_windows.begins_with(prefix_windows):
			printerr("Audio captures must stay under the ignored repository tmp/ directory")
			return false
	elif not candidate.begins_with(tmp_root + "/"):
		printerr("Audio captures must stay under the ignored repository tmp/ directory")
		return false
	if DirAccess.dir_exists_absolute(candidate):
		var existing := DirAccess.open(candidate)
		if existing == null or not existing.get_files().is_empty() or not existing.get_directories().is_empty():
			printerr("Output directory must be new and empty: " + candidate)
			return false
	else:
		var error: Error = DirAccess.make_dir_recursive_absolute(candidate)
		if error != OK:
			printerr("Could not create output directory: " + candidate)
			return false
	_output_dir = candidate
	return true


func _write_early_report(driver: String) -> void:
	var report: Dictionary = {"format": "openrc-mechanical-audio-staged-probe-v1",
		"scope": "Staged presentation signal probe; no live FlightAudio integration or listening claim.",
		"driver": driver, "asset_receipts": _asset_receipts, "quality_checks": {"required_assets_loaded": false}}
	var file := FileAccess.open(_output_dir.path_join("report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print(JSON.stringify(report))


func _cleanup() -> void:
	if _capture != null and _capture_bus_index >= 0:
		var last_index: int = AudioServer.get_bus_effect_count(_capture_bus_index) - 1
		if last_index >= 0 and AudioServer.get_bus_effect(_capture_bus_index, last_index) == _capture:
			AudioServer.remove_bus_effect(_capture_bus_index, last_index)
	if is_instance_valid(_audio):
		if is_instance_valid(_audio.get_parent()):
			_audio.get_parent().remove_child(_audio)
		_audio.free()
	if is_instance_valid(_rig):
		if _rig.get_parent() == root:
			root.remove_child(_rig)
		_rig.free()

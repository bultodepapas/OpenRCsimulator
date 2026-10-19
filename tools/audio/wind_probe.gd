## AUD-14 presentation-only soundscape bench. It stages wind values around one
## windsock cue; there is no aircraft, flight model, or claim of a real flight.
## Usage: godot --headless --path app --audio-driver WASAPI --script ../tools/audio/wind_probe.gd -- --fps=60 --out=<absolute-prefix>
extends SceneTree

const SoundscapeScript = preload("res://audio/soundscape.gd")
const SOURCE_MANIFEST_PATH: String = "res://assets/audio/soundscape/recorded/manifest.json"
const FABRIC_RUNTIME_PATH: String = "res://assets/audio/soundscape/recorded/windsock_fabric.wav"
const STAGE_SECONDS: float = 3.0
const SETTLED_IGNORE_SECONDS: float = 0.5
const RMS_FLOOR_LINEAR: float = 1e-12
const STAGE_NAMES: Array[String] = [
	"calm",
	"light_3mps",
	"strong_12mps",
	"gust_direction_reversal",
	"paused",
	"resume_near_windsock",
	"fabric_cutoff_over_55m",
]

var _output_prefix: String = ""
var _fps: int = 60
var _samples: PackedVector2Array = PackedVector2Array()
var _update_times_usec: Array[int] = []
var _stages: Array[Dictionary] = []
var _capture: AudioEffectCapture
var _fabric_capture: AudioEffectCapture
var _fabric_probe_bus_name: StringName = &""
var _camera: Camera3D
var _soundscape: Node
var _fabric_player: AudioStreamPlayer3D
var _start_usec: int = 0
var _last_frame_usec: int = 0
var _elapsed_s: float = 0.0
var _dropped_previous: int = 0
var _fabric_dropped_previous: int = 0
var _invalid_audio_sample: bool = false


func _initialize() -> void:
	_parse_args()
	Engine.max_fps = _fps
	_run.call_deferred()


func _parse_args() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_output_prefix = argument.trim_prefix("--out=")
		elif argument.begins_with("--fps"):
			var value: String = argument.trim_prefix("--fps").trim_prefix("=")
			var parsed: int = value.to_int()
			if parsed > 0:
				_fps = parsed


func _run() -> void:
	if _output_prefix.is_empty() or not _output_prefix.is_absolute_path():
		printerr("Usage: -- --fps=30|60|144 --out=<absolute-prefix>")
		quit(2)
		return
	if not [30, 60, 144].has(_fps):
		printerr("wind_probe supports --fps30, --fps60, or --fps144")
		quit(2)
		return
	var output_directory: String = _output_prefix.get_base_dir()
	if not DirAccess.dir_exists_absolute(output_directory):
		var make_directory: Error = DirAccess.make_dir_recursive_absolute(output_directory)
		if make_directory != OK:
			printerr("Could not create output directory: " + output_directory)
			quit(2)
			return
	Engine.max_fps = _fps
	if AudioServer.get_driver_name().to_upper() != "WASAPI":
		printerr("Native WASAPI is required; actual driver is " + AudioServer.get_driver_name())
		quit(2)
		return

	var buses_before: int = AudioServer.bus_count
	root.audio_listener_enable_3d = true
	var rig: Node3D = Node3D.new()
	rig.name = "WindAudioPresentationBench"
	root.add_child(rig)
	_camera = Camera3D.new()
	_camera.name = "CurrentAudioListenerCamera"
	_camera.position = Vector3(0.0, 7.0, 14.0)
	rig.add_child(_camera)
	_camera.make_current()
	var listener: AudioListener3D = AudioListener3D.new()
	_camera.add_child(listener)
	listener.make_current()
	_soundscape = SoundscapeScript.new()
	_soundscape.name = "RecordedWindSoundscape"
	rig.add_child(_soundscape)
	await process_frame

	# This minimal field has one audio windsock cue and no tree objects or wildlife.
	var field: Dictionary = {
		"pilot": {"east": 0.0, "north": 0.0, "down": 0.0},
		"objects": [],
		"flight_cues": [{"id": "windsock", "type": "windsock", "east": 0.0, "north": 0.0, "pole_height": 3.0}],
	}
	_soundscape.configure(field, "electric_prop", 4102026)
	if _soundscape.voices.size() != SoundscapeScript.MAX_VOICES:
		printerr("Soundscape did not build its presentation voices")
		_cleanup(rig, null, -1)
		quit(1)
		return
	if _soundscape.fabric_audio == null:
		printerr("Recorded windsock fabric player was not constructed")
		_cleanup(rig, null, -1)
		quit(1)
		return
	_fabric_player = _soundscape.fabric_audio.player as AudioStreamPlayer3D
	if _fabric_player == null or _fabric_player.stream == null:
		printerr("Recorded windsock fabric stream did not load")
		_cleanup(rig, null, -1)
		quit(1)
		return
	if _soundscape.voices[3].stream == null or _soundscape.voices[4].stream == null:
		printerr("Recorded wind streams did not load")
		_cleanup(rig, null, -1)
		quit(1)
		return
	if not _setup_fabric_capture(_soundscape.environment_bus()):
		printerr("Could not create the isolated fabric capture bus")
		_cleanup(rig, null, -1)
		quit(1)
		return

	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 1.0
	var master_index: int = AudioServer.get_bus_index(&"Master")
	if master_index < 0:
		printerr("Master bus is missing")
		_cleanup(rig, null, -1)
		quit(1)
		return
	AudioServer.add_bus_effect(master_index, _capture)
	for _index: int in STAGE_NAMES.size():
		_stages.append({
			"name": STAGE_NAMES[_index], "frames": 0, "sum_squares": 0.0,
			"peak": 0.0, "settled_frames": 0, "settled_sum_squares": 0.0,
			"settled_peak": 0.0,
			"fabric_frames": 0, "fabric_sum_squares": 0.0, "fabric_peak": 0.0,
			"fabric_settled_frames": 0, "fabric_settled_sum_squares": 0.0,
			"fabric_settled_peak": 0.0, "fabric_discarded_frames": 0,
			"update_count": 0, "discarded_frames": 0, "wind_min_mps": INF,
			"wind_max_mps": 0.0, "listener_distance_m": 0.0,
			"fabric_paused": false, "fabric_playing": false,
			"fabric_stream_paused": false,
			"fabric_volume_db": -80.0, "fabric_gain_linear": 0.0,
			"soundscape_gain": 0.0, "wind_low_target": 0.0,
			"wind_high_target": 0.0, "inflation": 0.0,
			"stage_start_s": null, "stage_end_s": null,
		})
	_start_usec = Time.get_ticks_usec()
	_last_frame_usec = _start_usec
	var current_stage: int = -1
	while _elapsed_s < STAGE_SECONDS * STAGE_NAMES.size():
		await process_frame
		var now_usec: int = Time.get_ticks_usec()
		_elapsed_s = float(now_usec - _start_usec) / 1000000.0
		var next_stage: int = mini(floori(_elapsed_s / STAGE_SECONDS), STAGE_NAMES.size() - 1)
		if next_stage != current_stage:
			if current_stage >= 0:
				var ended: Dictionary = _stages[current_stage]
				ended["stage_end_s"] = _elapsed_s
				_stages[current_stage] = ended
			current_stage = next_stage
			var started: Dictionary = _stages[current_stage]
			started["stage_start_s"] = _elapsed_s
			_stages[current_stage] = started
		var stage_elapsed: float = _elapsed_s - float(current_stage) * STAGE_SECONDS
		var state: Dictionary = _stage_state(current_stage, stage_elapsed)
		_camera.position = state["camera_position"]
		var dt: float = clampf(float(now_usec - _last_frame_usec) / 1000000.0, 0.0, 0.1)
		if dt <= 0.0:
			dt = 1.0 / float(_fps)
		_last_frame_usec = now_usec
		_soundscape.update_sound(_snapshot(state), dt)
		_update_times_usec.append(int(_soundscape.last_update_usec))
		var record: Dictionary = _stages[current_stage]
		record["update_count"] = int(record["update_count"]) + 1
		var settled: bool = stage_elapsed >= SETTLED_IGNORE_SECONDS
		var available: int = _capture.get_frames_available()
		if available > 0:
			var captured: PackedVector2Array = _capture.get_buffer(available)
			var measured: Dictionary = _measure_buffer(captured)
			var clean_samples: PackedVector2Array = measured["clean_samples"]
			_samples.append_array(clean_samples)
			_record_buffer_metrics(record, measured, "", settled)
		var dropped_now: int = _capture.get_discarded_frames()
		record["discarded_frames"] = int(record["discarded_frames"]) + maxi(0, dropped_now - _dropped_previous)
		_dropped_previous = dropped_now
		var fabric_available: int = _fabric_capture.get_frames_available()
		if fabric_available > 0:
			var fabric_buffer: PackedVector2Array = _fabric_capture.get_buffer(fabric_available)
			_record_buffer_metrics(record, _measure_buffer(fabric_buffer), "fabric_", settled)
		var fabric_dropped_now: int = _fabric_capture.get_discarded_frames()
		record["fabric_discarded_frames"] = int(record["fabric_discarded_frames"]) + \
			maxi(0, fabric_dropped_now - _fabric_dropped_previous)
		_fabric_dropped_previous = fabric_dropped_now
		record["wind_min_mps"] = minf(float(record["wind_min_mps"]), float(state["wind_speed"]))
		record["wind_max_mps"] = maxf(float(record["wind_max_mps"]), float(state["wind_speed"]))
		record["listener_distance_m"] = _fabric_player.global_position.distance_to(_camera.global_position)
		record["fabric_paused"] = _fabric_player.stream_paused
		record["fabric_stream_paused"] = _fabric_player.stream_paused
		record["fabric_playing"] = _fabric_player.playing
		record["fabric_volume_db"] = _fabric_player.volume_db
		record["fabric_gain_linear"] = db_to_linear(_fabric_player.volume_db)
		record["soundscape_gain"] = _soundscape.gain
		record["wind_low_target"] = float(_soundscape.last_targets.get("wind_low", 0.0))
		record["wind_high_target"] = float(_soundscape.last_targets.get("wind_high", 0.0))
		record["inflation"] = float(state["windsock_inflation"])
		_stages[current_stage] = record
	if current_stage >= 0:
		var ended: Dictionary = _stages[current_stage]
		ended["stage_end_s"] = _elapsed_s
		_stages[current_stage] = ended

	var discarded_frames: int = _capture.get_discarded_frames()
	var fabric_discarded_frames: int = _fabric_capture.get_discarded_frames()
	var peak: float = 0.0
	var sum_squares: float = 0.0
	var fabric_peak: float = 0.0
	var fabric_sum_squares: float = 0.0
	var fabric_frames_total: int = 0
	for record: Dictionary in _stages:
		var frames: int = int(record["frames"])
		var stage_sum: float = float(record["sum_squares"])
		var stage_peak: float = float(record["peak"])
		sum_squares += stage_sum
		peak = maxf(peak, stage_peak)
		var stage_fabric_frames: int = int(record["fabric_frames"])
		var stage_fabric_sum: float = float(record["fabric_sum_squares"])
		var stage_fabric_peak: float = float(record["fabric_peak"])
		fabric_frames_total += stage_fabric_frames
		fabric_sum_squares += stage_fabric_sum
		fabric_peak = maxf(fabric_peak, stage_fabric_peak)
		record["rms_dbfs"] = _rms_dbfs(stage_sum, frames)
		record["peak_dbfs"] = linear_to_db(maxf(stage_peak, 1e-12))
		var settled_frames: int = int(record["settled_frames"])
		record["settled_rms_dbfs"] = _rms_dbfs(float(record["settled_sum_squares"]), settled_frames)
		record["settled_peak_dbfs"] = linear_to_db(maxf(float(record["settled_peak"]), 1e-12))
		record["fabric_rms_dbfs"] = _rms_dbfs(stage_fabric_sum, stage_fabric_frames)
		record["fabric_peak_dbfs"] = linear_to_db(maxf(stage_fabric_peak, 1e-12))
		var fabric_settled_frames: int = int(record["fabric_settled_frames"])
		record["fabric_settled_rms_dbfs"] = _rms_dbfs(float(record["fabric_settled_sum_squares"]),
			fabric_settled_frames)
		record["fabric_settled_peak_dbfs"] = linear_to_db(maxf(float(record["fabric_settled_peak"]), 1e-12))
		record["captured_seconds"] = float(frames) / float(AudioServer.get_mix_rate())
		record["settled_captured_frames"] = settled_frames
		record["fabric_captured_frames"] = stage_fabric_frames
		record["fabric_settled_captured_frames"] = fabric_settled_frames
		record["fabric_captured_seconds"] = float(stage_fabric_frames) / float(AudioServer.get_mix_rate())
		for key: String in ["sum_squares", "peak", "settled_sum_squares", "settled_peak",
			"fabric_sum_squares", "fabric_peak", "fabric_settled_sum_squares", "fabric_settled_peak",
			"frames", "settled_frames", "fabric_frames", "fabric_settled_frames"]:
			record.erase(key)
	var run_wall_seconds: float = float(Time.get_ticks_usec() - _start_usec) / 1000000.0
	var saved_wav: Error = _save_wav(_output_prefix + ".wav")
	var timings: Array[int] = _update_times_usec.duplicate()
	timings.sort()
	var update_max_usec: int = timings[-1] if not timings.is_empty() else 0
	var p95_index: int = clampi(ceili(float(timings.size()) * 0.95) - 1, 0, maxi(timings.size() - 1, 0))
	var update_p95_usec: int = timings[p95_index] if not timings.is_empty() else 0
	var old_bus_names: Array[StringName] = _owned_bus_names()
	_cleanup(rig, _capture, master_index)
	# Native playback releases streams on the mixer thread after stop/removal.
	# Let it drain before SceneTree teardown so exit diagnostics are meaningful.
	await create_timer(0.25).timeout
	var missing_buses: Array[String] = []
	for bus_name: StringName in old_bus_names:
		if AudioServer.get_bus_index(bus_name) >= 0:
			missing_buses.append(String(bus_name))
	var buses_clean: bool = AudioServer.bus_count == buses_before and missing_buses.is_empty()
	var peak_dbfs: float = linear_to_db(maxf(peak, 1e-12))
	var fabric_peak_dbfs: float = linear_to_db(maxf(fabric_peak, 1e-12))
	var paused_stage_confirmed: bool = bool(_stages[4].get("fabric_stream_paused", false))
	var near_fabric_rms_dbfs: float = float(_stages[5].get("fabric_settled_rms_dbfs", -120.0))
	var far_fabric_rms_dbfs: float = float(_stages[6].get("fabric_settled_rms_dbfs", -120.0))
	var cutoff_delta_db: float = clampf(near_fabric_rms_dbfs - far_fabric_rms_dbfs, 0.0, 240.0)
	var source_manifest_sha256: String = _sha256_resource(SOURCE_MANIFEST_PATH)
	var fabric_runtime_sha256: String = _sha256_resource(FABRIC_RUNTIME_PATH)
	var clipping_limit_dbfs: float = -0.9
	var no_clipping: bool = peak_dbfs < clipping_limit_dbfs and fabric_peak_dbfs < clipping_limit_dbfs
	var finite_audio: bool = not _invalid_audio_sample
	var report: Dictionary = {
		"format": "openrc-audio-windsock-presentation-v1",
		"note": "Staged presentation values in a minimal field audio rig; no aircraft or flight simulation. Captured mix is not speaker listening, acoustic calibration, or a device latency measurement. RMS values floor silence at -240 dBFS.",
		"godot": Engine.get_version_info().string,
		"driver": AudioServer.get_driver_name(),
		"display": DisplayServer.get_name(),
		"requested_fps": _fps,
		"measured_update_count": _update_times_usec.size(),
		"wall_run_seconds": run_wall_seconds,
		"measured_update_wall_fps": float(_update_times_usec.size()) / maxf(run_wall_seconds, 1e-9),
		"mix_rate": AudioServer.get_mix_rate(),
		"capture_bus": "Master",
		"captured_frames": _samples.size(),
		"captured_seconds": float(_samples.size()) / float(AudioServer.get_mix_rate()),
		"discarded_frames": discarded_frames,
		"peak_dbfs": peak_dbfs,
		"rms_dbfs": _rms_dbfs(sum_squares, _samples.size()),
		"isolated_fabric_peak_dbfs": fabric_peak_dbfs,
		"isolated_fabric_rms_dbfs": _rms_dbfs(fabric_sum_squares, fabric_frames_total),
		"soundscape_update_max_usec": update_max_usec,
		"soundscape_update_p95_usec": update_p95_usec,
		"driver_latency_estimate_s": AudioServer.get_output_latency(),
		"settled_ignore_seconds": SETTLED_IGNORE_SECONDS,
		"rms_floor_dbfs": -240.0,
		"source_manifest_path": SOURCE_MANIFEST_PATH,
		"source_manifest_sha256": source_manifest_sha256,
		"fabric_runtime_path": FABRIC_RUNTIME_PATH,
		"fabric_runtime_sha256": fabric_runtime_sha256,
		"quality_checks": {
			"finite_audio": finite_audio,
			"no_clipping_at_or_above_dbfs": clipping_limit_dbfs,
			"no_clipping": no_clipping,
			"paused_stage_stream_paused": paused_stage_confirmed,
			"near_to_far_fabric_cutoff_delta_db": cutoff_delta_db,
			"fabric_distance_cutoff_confirmed_at_40db": cutoff_delta_db >= 40.0,
		},
		"stage_results": _stages,
		"bus_cleanup": {"count_before": buses_before, "count_after": AudioServer.bus_count,
			"missing_bus_indexes": missing_buses, "clean": buses_clean},
		"wav_saved": saved_wav == OK,
	}
	var report_file: FileAccess = FileAccess.open(_output_prefix + ".json", FileAccess.WRITE)
	if report_file != null:
		report_file.store_string(JSON.stringify(report, "\t"))
		report_file.close()
	else:
		printerr("Could not write report: " + _output_prefix + ".json")
	print(JSON.stringify(report))
	if saved_wav != OK or report_file == null or _samples.is_empty() or discarded_frames != 0 \
			or fabric_discarded_frames != 0 or not buses_clean or not finite_audio or not no_clipping \
			or not paused_stage_confirmed:
		quit(1)
	else:
		quit(0)


func _snapshot(state: Dictionary) -> Dictionary:
	return {
		"rpm": 0.0,
		"max_rpm": 12000.0,
		"load": 0.0,
		"throttle": 0.0,
		"running": false,
		"blades": 2,
		"airspeed": 0.0,
		"wind_speed": float(state["wind_speed"]),
		"wind_direction": state["wind_direction"],
		"source": Vector3.ZERO,
		"listener": _camera.global_position,
		"source_velocity": Vector3.ZERO,
		"sound_speed": 343.0,
		"paused": bool(state["paused"]),
		"sun_elevation": 45.0,
		"temperature_c": 15.0,
		"pressure_pa": 101325.0,
		"humidity_molar_pct": 50.0,
		"time": _elapsed_s,
		"fabric_source": Vector3(1.5, 3.0, 0.0),
		"windsock_inflation": float(state["windsock_inflation"]),
	}


func _stage_state(stage: int, stage_elapsed_s: float) -> Dictionary:
	var state: Dictionary = {
		"wind_speed": 0.0,
		"wind_direction": Vector3.RIGHT,
		"windsock_inflation": 0.0,
		"paused": false,
		"camera_position": Vector3(0.0, 7.0, 14.0),
	}
	match stage:
		0:
			pass
		1:
			state["wind_speed"] = 3.0
			state["windsock_inflation"] = 0.22
		2:
			state["wind_speed"] = 12.0
			state["windsock_inflation"] = 1.0
		3:
			if stage_elapsed_s < 0.6:
				state["wind_speed"] = lerpf(12.0, 15.0, stage_elapsed_s / 0.6)
				state["windsock_inflation"] = 0.9
			elif stage_elapsed_s < 1.25:
				state["wind_speed"] = 15.0
				state["windsock_inflation"] = 1.0
			elif stage_elapsed_s < 1.6:
				state["wind_speed"] = lerpf(15.0, 0.0, (stage_elapsed_s - 1.25) / 0.35)
				state["windsock_inflation"] = 0.25
			elif stage_elapsed_s < 2.1:
				state["wind_speed"] = lerpf(0.0, 10.0, (stage_elapsed_s - 1.6) / 0.5)
				state["wind_direction"] = Vector3.LEFT
				state["windsock_inflation"] = 0.65
			else:
				state["wind_speed"] = 10.0
				state["wind_direction"] = Vector3.LEFT
				state["windsock_inflation"] = 0.75
		4:
			state["wind_speed"] = 12.0
			state["windsock_inflation"] = 1.0
			state["paused"] = true
		5:
			state["wind_speed"] = 8.0
			state["windsock_inflation"] = 0.85
			state["camera_position"] = Vector3(1.5, 4.0, 1.0)
		6:
			state["wind_speed"] = 12.0
			state["windsock_inflation"] = 1.0
			state["camera_position"] = Vector3(0.0, 4.0, 70.0)
	return state


func _save_wav(path: String) -> Error:
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.mix_rate = AudioServer.get_mix_rate()
	wav.stereo = true
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	var data: PackedByteArray = PackedByteArray()
	data.resize(_samples.size() * 4)
	for index: int in _samples.size():
		data.encode_s16(index * 4, clampi(roundi(_samples[index].x * 32767.0), -32768, 32767))
		data.encode_s16(index * 4 + 2, clampi(roundi(_samples[index].y * 32767.0), -32768, 32767))
	wav.data = data
	return wav.save_to_wav(path)


func _setup_fabric_capture(environment_bus_name: StringName) -> bool:
	var environment_index: int = AudioServer.get_bus_index(environment_bus_name)
	if environment_index < 0:
		return false
	AudioServer.add_bus()
	var index: int = AudioServer.bus_count - 1
	_fabric_probe_bus_name = StringName("OpenRC Windsock Probe %d" % _soundscape.get_instance_id())
	AudioServer.set_bus_name(index, _fabric_probe_bus_name)
	AudioServer.set_bus_send(index, environment_bus_name)
	_fabric_capture = AudioEffectCapture.new()
	_fabric_capture.buffer_length = 1.0
	AudioServer.add_bus_effect(index, _fabric_capture)
	_fabric_player.bus = _fabric_probe_bus_name
	return true


func _measure_buffer(samples: PackedVector2Array) -> Dictionary:
	var clean_samples: PackedVector2Array = PackedVector2Array()
	clean_samples.resize(samples.size())
	var sum_squares: float = 0.0
	var peak: float = 0.0
	for index: int in samples.size():
		var frame: Vector2 = samples[index]
		if not is_finite(frame.x) or not is_finite(frame.y):
			_invalid_audio_sample = true
			frame = Vector2.ZERO
		clean_samples[index] = frame
		sum_squares += frame.length_squared()
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
	return {"clean_samples": clean_samples, "sum_squares": sum_squares, "peak": peak}


func _record_buffer_metrics(record: Dictionary, measured: Dictionary, prefix: String, settled: bool) -> void:
	var samples: PackedVector2Array = measured["clean_samples"]
	var frame_count_key: String = prefix + "frames"
	var sum_key: String = prefix + "sum_squares"
	var peak_key: String = prefix + "peak"
	record[frame_count_key] = int(record[frame_count_key]) + samples.size()
	record[sum_key] = float(record[sum_key]) + float(measured["sum_squares"])
	record[peak_key] = maxf(float(record[peak_key]), float(measured["peak"]))
	if settled:
		var settled_frames_key: String = prefix + "settled_frames"
		var settled_sum_key: String = prefix + "settled_sum_squares"
		var settled_peak_key: String = prefix + "settled_peak"
		record[settled_frames_key] = int(record[settled_frames_key]) + samples.size()
		record[settled_sum_key] = float(record[settled_sum_key]) + float(measured["sum_squares"])
		record[settled_peak_key] = maxf(float(record[settled_peak_key]), float(measured["peak"]))


func _sha256_resource(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var context: HashingContext = HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK or context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode()


func _rms_dbfs(sum_squares: float, frames: int) -> float:
	var rms: float = sqrt(maxf(sum_squares, 0.0) / maxf(float(frames) * 2.0, 1.0))
	return linear_to_db(maxf(rms, RMS_FLOOR_LINEAR))


func _owned_bus_names() -> Array[StringName]:
	if _soundscape == null:
		return []
	var suffix: String = " %d" % _soundscape.get_instance_id()
	return [
		_soundscape.output_bus(),
		StringName(str(SoundscapeScript.AIRCRAFT_BUS) + suffix),
		_soundscape.environment_bus(),
	]


func _cleanup(rig: Node3D, capture_effect: AudioEffectCapture, master_index: int) -> void:
	if capture_effect != null and master_index >= 0:
		var effect_index: int = AudioServer.get_bus_effect_count(master_index) - 1
		if effect_index >= 0 and AudioServer.get_bus_effect(master_index, effect_index) == capture_effect:
			AudioServer.remove_bus_effect(master_index, effect_index)
	if _soundscape != null and is_instance_valid(_soundscape):
		if _soundscape.fabric_audio != null:
			_soundscape.fabric_audio.stop()
		if not _fabric_probe_bus_name.is_empty():
			var probe_index: int = AudioServer.get_bus_index(_fabric_probe_bus_name)
			if probe_index >= 0:
				AudioServer.set_bus_send(probe_index, &"Master")
		rig.remove_child(_soundscape)
		_soundscape.free()
	if not _fabric_probe_bus_name.is_empty():
		var probe_index: int = AudioServer.get_bus_index(_fabric_probe_bus_name)
		if probe_index > 0:
			AudioServer.remove_bus(probe_index)
		_fabric_probe_bus_name = &""
	if _camera != null and is_instance_valid(_camera):
		rig.remove_child(_camera)
		_camera.free()
	if rig != null and is_instance_valid(rig):
		root.remove_child(rig)
		rig.free()

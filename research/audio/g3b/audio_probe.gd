extends SceneTree

const Sound := preload("res://render/engine_sound.gd")
const WARMUP_SECONDS := 1.5
const STEADY_SECONDS := 10.0
const RESPONSE_SECONDS := 2.0
const START_RPM := 6000.0
const STEP_RPM := 24000.0
const MAX_RPM := 30000.0
const TARGET_SECONDS := 0.05
const CAPTURE_BUFFER_SECONDS := 1.0
const RESPONSE_WINDOW := 1024
const RESPONSE_HOP := 256
const RESPONSE_RATIO := 3.0

var _fps_requested := 30
var _driver_label := ""
var _out_path := ""
var _player: AudioStreamPlayer3D
var _playback: AudioStreamGeneratorPlayback
var _capture: AudioEffectCapture
var _mix_rate := 0
var _capacity_frames := 0
var _phase := 0.0
var _capture_chunks: Array[PackedVector2Array] = []
var _captured_count := 0
var _samples := PackedVector2Array()
var _capture_discarded_start := 0
var _capture_discarded_end := 0
var _steady_skips_start := 0
var _steady_skips_end := 0
var _steady_max_queued := 0
var _steady_min_queued := 0
var _steady_update_calls := 0
var _steady_update_cpu_us := 0
var _steady_next_mix_min := 1.0e30
var _steady_next_mix_max := 0.0
var _steady_since_mix_min := 1.0e30
var _steady_since_mix_max := 0.0
var _steady_actual_seconds := 0.0
var _steady_reported_target_frames := -1
var _player_has_target_frames := false
var _step_sample_index := -1
var _step_request_usec := 0
var _step_update_usec := 0
var _step_next_mix_seconds := -1.0
var _step_since_mix_seconds := -1.0
var _step_output_latency_seconds := -1.0
var _response_actual_seconds := 0.0
var _failure := ""


func _initialize() -> void:
	_parse_user_args()
	Engine.max_fps = _fps_requested
	_run_probe()


func _parse_user_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fps="):
			_fps_requested = int(arg.trim_prefix("--fps="))
		elif arg.begins_with("--driver="):
			_driver_label = arg.trim_prefix("--driver=")
		elif arg.begins_with("--out="):
			_out_path = arg.trim_prefix("--out=")
	if not [30, 60, 144].has(_fps_requested):
		_failure = "--fps must be 30, 60, or 144"


func _run_probe() -> void:
	# SceneTree scripts enter their first frame after _initialize; wait before
	# creating AudioStreamPlayer3D so its play() call has a live parent.
	await process_frame
	if not _failure.is_empty():
		_finish_with_failure()
		return

	_mix_rate = AudioServer.get_mix_rate()
	get_root().audio_listener_enable_3d = true
	var bus_index := AudioServer.get_bus_count()
	AudioServer.add_bus(bus_index)
	AudioServer.set_bus_name(bus_index, "ProbeCapture")
	AudioServer.set_bus_send(bus_index, "Master")
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = CAPTURE_BUFFER_SECONDS
	AudioServer.add_bus_effect(bus_index, _capture)
	# Capture happens on ProbeCapture before it sends to the deliberately muted
	# Master bus, so a WASAPI run cannot play the probe through the speakers.
	AudioServer.set_bus_mute(0, true)

	var source_root := Node3D.new()
	source_root.name = "AudioProbeRoot"
	source_root.position = Vector3(0.0, 0.0, -1.0)
	get_root().add_child(source_root)
	await process_frame
	var camera := Camera3D.new()
	camera.name = "AudioProbeCamera"
	get_root().add_child(camera)
	camera.make_current()
	var listener := AudioListener3D.new()
	listener.name = "AudioProbeListener"
	get_root().add_child(listener)
	listener.make_current()
	_player = Sound.create(source_root)
	_player.bus = "ProbeCapture"
	for property_info in _player.get_property_list():
		if property_info.name == "target_frames":
			_player_has_target_frames = true
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
	if _playback == null:
		_failure = "AudioStreamGeneratorPlayback unavailable"
		_finish_with_failure()
		return

	# At startup the generator is empty, so this free-frame count is its real
	# capacity (Godot rounds the configured duration to a power of two).
	await process_frame
	await process_frame
	_capacity_frames = _playback.get_frames_available()
	if _capacity_frames <= 0:
		_failure = "generator reported no initial free frames"
		_finish_with_failure()
		return
	_capture_discarded_start = _capture.get_discarded_frames()

	await _run_interval(WARMUP_SECONDS, START_RPM, false)
	_steady_skips_start = _playback.get_skips()
	_steady_max_queued = 0
	_steady_min_queued = _capacity_frames
	var steady_start_usec := Time.get_ticks_usec()
	await _run_interval(STEADY_SECONDS, START_RPM, true)
	_steady_actual_seconds = float(Time.get_ticks_usec() - steady_start_usec) / 1000000.0
	_steady_skips_end = _playback.get_skips()

	# Drain before switching RPM. The request timestamp starts before the next
	# process_frame; the first update records its capture boundary immediately
	# before Sound.update applies the new RPM.
	_drain_capture()
	_step_request_usec = Time.get_ticks_usec()
	var response_start_usec := _step_request_usec
	await _run_interval(RESPONSE_SECONDS, STEP_RPM, false)
	_response_actual_seconds = float(Time.get_ticks_usec() - response_start_usec) / 1000000.0
	_drain_capture()
	_capture_discarded_end = _capture.get_discarded_frames()
	_player.stop()
	_flatten_capture()
	var report := _build_report()
	_write_report(report)
	quit(0)


func _run_interval(duration_s: float, rpm: float, measure_steady: bool) -> void:
	var start_usec := Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - start_usec) / 1000000.0 < duration_s:
		await process_frame
		_drain_capture()
		if rpm == STEP_RPM and _step_update_usec == 0:
			_step_sample_index = _captured_count
			_step_update_usec = Time.get_ticks_usec()
			_step_next_mix_seconds = AudioServer.get_time_to_next_mix()
			_step_since_mix_seconds = AudioServer.get_time_since_last_mix()
			_step_output_latency_seconds = AudioServer.get_output_latency()
		var update_start_usec := Time.get_ticks_usec()
		_phase = Sound.update(_player, _phase, rpm, MAX_RPM)
		var update_elapsed_usec := Time.get_ticks_usec() - update_start_usec
		if measure_steady:
			if _player_has_target_frames:
				_steady_reported_target_frames = int(_player.get("target_frames"))
			_steady_update_calls += 1
			_steady_update_cpu_us += update_elapsed_usec
			var next_mix := AudioServer.get_time_to_next_mix()
			var since_mix := AudioServer.get_time_since_last_mix()
			_steady_next_mix_min = minf(_steady_next_mix_min, next_mix)
			_steady_next_mix_max = maxf(_steady_next_mix_max, next_mix)
			_steady_since_mix_min = minf(_steady_since_mix_min, since_mix)
			_steady_since_mix_max = maxf(_steady_since_mix_max, since_mix)
			var queued := _capacity_frames - _playback.get_frames_available()
			_steady_max_queued = maxi(_steady_max_queued, queued)
			_steady_min_queued = mini(_steady_min_queued, queued)


func _drain_capture() -> void:
	var available: int = _capture.get_frames_available()
	if available <= 0:
		return
	var block := _capture.get_buffer(available)
	if block.size() > 0:
		_capture_chunks.append(block)
		_captured_count += block.size()


func _flatten_capture() -> void:
	# Keep capture collection cheap while the audio mixer is running; flattening
	# these bounded chunks happens only after both measurement windows finish.
	_samples.resize(_captured_count)
	var offset := 0
	for block in _capture_chunks:
		for frame in block:
			_samples[offset] = frame
			offset += 1
	_capture_chunks.clear()


func _goertzel_power(start: int, count: int, frequency: float) -> float:
	var omega := TAU * frequency / float(_mix_rate)
	var coefficient := 2.0 * cos(omega)
	var s1 := 0.0
	var s2 := 0.0
	for offset in count:
		var frame := _samples[start + offset]
		var mono := 0.5 * (frame.x + frame.y)
		var s0 := mono + coefficient * s1 - s2
		s2 = s1
		s1 = s0
	return maxf(0.0, s1 * s1 + s2 * s2 - coefficient * s1 * s2)


func _analyze_response() -> Dictionary:
	var available_end := _samples.size() - RESPONSE_WINDOW
	if _step_sample_index < 0 or available_end <= _step_sample_index:
		return {ok = false, reason = "insufficient captured audio around RPM step"}
	var start_at := maxi(0, _step_sample_index - RESPONSE_WINDOW)
	var pre_step_ratio_max := 0.0
	var step_detection_sample := -1
	var max_post_step_ratio := 0.0
	var cursor := start_at
	while cursor <= available_end:
		var center := cursor + RESPONSE_WINDOW / 2
		var p100 := _goertzel_power(cursor, RESPONSE_WINDOW, 100.0)
		var p400 := _goertzel_power(cursor, RESPONSE_WINDOW, 400.0)
		var ratio := p400 / maxf(p100, 1e-18)
		if center < _step_sample_index:
			pre_step_ratio_max = maxf(pre_step_ratio_max, ratio)
		elif center >= _step_sample_index:
			max_post_step_ratio = maxf(max_post_step_ratio, ratio)
			if step_detection_sample < 0 and ratio >= RESPONSE_RATIO:
				step_detection_sample = center
		cursor += RESPONSE_HOP
	var response_ms := -1.0
	if step_detection_sample >= 0:
		response_ms = 1000.0 * float(step_detection_sample - _step_sample_index) / float(_mix_rate)
	var request_to_update_ms := 1000.0 * float(_step_update_usec - _step_request_usec) / 1000000.0
	var end_to_end_ms := response_ms + request_to_update_ms
	var output_latency_ms := 1000.0 * _step_output_latency_seconds
	return {
		ok = step_detection_sample >= 0,
		response_ms = response_ms,
		bound_ms = 70.0,
		adapter_within_bound = response_ms >= 0.0 and response_ms <= 70.0,
		request_to_update_ms = request_to_update_ms,
		end_to_end_ms = end_to_end_ms,
		end_to_end_within_bound = response_ms >= 0.0 and end_to_end_ms <= 70.0,
		estimated_output_path_ms = end_to_end_ms + output_latency_ms,
		estimated_output_path_within_bound = response_ms >= 0.0 and end_to_end_ms + output_latency_ms <= 70.0,
		threshold_power_ratio = RESPONSE_RATIO,
		pre_step_400_to_100_power_ratio_max = pre_step_ratio_max,
		post_step_400_to_100_power_ratio_max = max_post_step_ratio,
		window_frames = RESPONSE_WINDOW,
		hop_frames = RESPONSE_HOP,
		step_capture_sample_index = _step_sample_index,
		detected_capture_sample_index = step_detection_sample,
		mix_rate_hz = _mix_rate,
		update_time_to_next_mix_seconds = _step_next_mix_seconds,
		update_time_since_last_mix_seconds = _step_since_mix_seconds,
		output_latency_at_update_seconds = _step_output_latency_seconds,
	}


func _source_hashes() -> Dictionary:
	var hashes := {}
	for path in ["res://render/engine_sound.gd", "res://render/engine_audio.gd", "res://render/engine_voice.gd"]:
		if FileAccess.file_exists(path):
			hashes[path] = FileAccess.get_sha256(path)
	return hashes


func _build_report() -> Dictionary:
	var native_target_frames := int(ceil(Sound.MIX_RATE * TARGET_SECONDS))
	var effective_target_frames := _steady_reported_target_frames if _steady_reported_target_frames >= 0 else _capacity_frames
	var response := _analyze_response()
	var capture_levels := _capture_level_metrics()
	var steady_cpu_ms := float(_steady_update_cpu_us) / 1000.0
	var skips_delta := _steady_skips_end - _steady_skips_start
	var output_latency_seconds := AudioServer.get_output_latency()
	return {
		source_sha256 = _source_hashes(),
		probe = "g3b-audio-runtime",
		status = "ok" if _failure.is_empty() else "failed",
		failure = _failure,
		interpretation = "Mixer capture only; this does not measure hardware output latency or subjective audibility.",
		fps_requested = _fps_requested,
		audio_driver_requested = _requested_audio_driver(),
		audio_driver_runtime = AudioServer.get_driver_name(),
		mix_rate_hz = _mix_rate,
		project_output_latency_setting_ms = ProjectSettings.get_setting("audio/driver/output_latency", 15),
		audio_server_output_latency_seconds = output_latency_seconds,
		audio_server_output_latency_ms = output_latency_seconds * 1000.0,
		steady_time_to_next_mix_min_seconds = _steady_next_mix_min,
		steady_time_to_next_mix_max_seconds = _steady_next_mix_max,
		steady_time_since_last_mix_min_seconds = _steady_since_mix_min,
		steady_time_since_last_mix_max_seconds = _steady_since_mix_max,
		generator_mix_rate_hz = Sound.MIX_RATE,
		generator_initial_free_frames = _capacity_frames,
		generator_capacity_inferred_frames = _capacity_frames,
		steady_seconds = _steady_actual_seconds,
		steady_queue_target_frames = effective_target_frames,
		steady_queue_target_ms = 1000.0 * float(effective_target_frames) / Sound.MIX_RATE,
		steady_queue_native_50ms_limit_frames = native_target_frames,
		steady_queue_max_frames = _steady_max_queued,
		steady_queue_min_frames = _steady_min_queued,
		steady_queue_max_ms = 1000.0 * float(_steady_max_queued) / Sound.MIX_RATE,
		steady_queue_within_target = _steady_max_queued <= effective_target_frames,
		steady_queue_within_native_50ms_limit = _steady_max_queued <= native_target_frames,
		steady_update_calls = _steady_update_calls,
		steady_update_cpu_ms = steady_cpu_ms,
		steady_update_cpu_ms_per_audio_second = steady_cpu_ms / maxf(_steady_actual_seconds, 1e-6),
		steady_skips_start = _steady_skips_start,
		steady_skips_end = _steady_skips_end,
		steady_skips_delta = skips_delta,
		captured_frames = _captured_count,
		capture_peak_linear = capture_levels.peak,
		capture_rms_linear = capture_levels.rms,
		capture_discarded_frames = _capture_discarded_end - _capture_discarded_start,
		rpm_step = {
			from_rpm = START_RPM,
			to_rpm = STEP_RPM,
			from_fundamental_hz = START_RPM / 60.0,
			to_fundamental_hz = STEP_RPM / 60.0,
			request_to_end_seconds = _response_actual_seconds,
			first_update_request_delay_ms = 1000.0 * float(_step_update_usec - _step_request_usec) / 1000000.0,
			response = response,
		},
	}


func _requested_audio_driver() -> String:
	if not _driver_label.is_empty():
		return _driver_label
	var args := OS.get_cmdline_args()
	for i in args.size():
		if args[i] == "--audio-driver" and i + 1 < args.size():
			return str(args[i + 1])
		if args[i].begins_with("--audio-driver="):
			return args[i].trim_prefix("--audio-driver=")
	return "default"


func _capture_level_metrics() -> Dictionary:
	var peak := 0.0
	var sum_squares := 0.0
	var sample_count := 0
	for frame in _samples:
		peak = maxf(peak, absf(frame.x))
		peak = maxf(peak, absf(frame.y))
		sum_squares += frame.x * frame.x + frame.y * frame.y
		sample_count += 2
	return {
		peak = peak,
		rms = sqrt(sum_squares / float(maxi(sample_count, 1))),
	}


func _write_report(report: Dictionary) -> void:
	var json := JSON.stringify(report, "\t", true)
	print(json)
	if _out_path.is_empty():
		return
	var file := FileAccess.open(_out_path, FileAccess.WRITE)
	if file == null:
		printerr("Could not write audio probe report: ", _out_path, " (", FileAccess.get_open_error(), ")")
		return
	file.store_string(json + "\n")
	file.close()


func _finish_with_failure() -> void:
	var report := {
		probe = "g3b-audio-runtime",
		status = "failed",
		failure = _failure,
		interpretation = "Mixer capture only; this does not measure hardware output latency or subjective audibility.",
		fps_requested = _fps_requested,
	}
	_write_report(report)
	quit(1)

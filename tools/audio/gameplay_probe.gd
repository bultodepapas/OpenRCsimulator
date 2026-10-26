## AUD-04: actual flight scene + native mixer capture. No synthetic aircraft trajectory.
## godot --path app --script ../tools/audio/gameplay_probe.gd -- --fps=60 --out=<absolute prefix>
extends SceneTree

var args: Dictionary = {}
var samples: PackedVector2Array = PackedVector2Array()
var timings: Array[int] = []
var events: Array[Dictionary] = []
var capture: AudioEffectCapture
var scene: Node3D
var elapsed: float = 0.0
var stage: int = -1
var peak: float = 0.0
var invalid_sample: bool = false
var position_min: float = INF
var position_max: float = 0.0
var dropped: int = 0
var pilot_doppler_min: float = 1.0
var pilot_doppler_max: float = 1.0
var pilot_distance_min: float = INF
var wildlife_events: Array[Dictionary] = []
var wildlife_serial: int = 0
var focus_resumes: int = 0
var focus_resume_pending: bool = false
var mechanical_samples: Array[Dictionary] = []
var next_mechanical_sample_s: float = 0.0
var mechanical_timings: Array[int] = []


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
		args[pair[0]] = pair[1] if pair.size() > 1 else true
	Engine.max_fps = int(args.get("fps", 60))
	_run.call_deferred()


func _run() -> void:
	if not args.has("out"):
		printerr("--out=<absolute prefix> is required")
		quit(1)
		return
	var duration: float = float(args.get("duration", 20.0))
	if not is_finite(duration) or duration <= 0.0:
		printerr("--duration must be finite and positive")
		quit(1)
		return
	var probe_sha256: String = _probe_sha256()
	if probe_sha256.is_empty():
		printerr("Could not hash gameplay_probe.gd")
		quit(1)
		return
	var driver: String = AudioServer.get_driver_name()
	if driver.to_upper() == "DUMMY":
		printerr("gameplay_probe requires a native audio driver; actual driver is Dummy")
		quit(2)
		return
	scene = load("res://main.tscn").instantiate()
	root.title = "OpenRC Audio Review"
	root.add_child(scene)
	root.focus_exited.connect(func() -> void: focus_resume_pending = true)
	var adapter: Node = scene.get("_soundscape_audio")
	if adapter == null:
		printerr("probe requires soundscape=on and a physics flight")
		quit(1)
		return
	# This is an automated player input tape through the real session input sampler.
	scene.session.read_raw = _controls
	var capture_bus_index: int = AudioServer.get_bus_index(adapter.soundscape.output_bus())
	if capture_bus_index < 0:
		printerr("probe could not find the soundscape output bus")
		root.remove_child(scene)
		scene.free()
		quit(1)
		return
	capture = AudioEffectCapture.new()
	capture.buffer_length = 1.0
	var capture_initial_pushed: int = capture.get_pushed_frames()
	var capture_initial_discarded: int = capture.get_discarded_frames()
	# The new effect's mixer buffer is initialized only after attachment.
	var capture_initial_available: int = 0
	var start_usec: int = Time.get_ticks_usec()
	AudioServer.add_bus_effect(capture_bus_index, capture)
	while elapsed < duration:
		await process_frame
		elapsed = float(Time.get_ticks_usec() - start_usec) / 1000000.0
		# Opt-in automated review only: explicitly resume a focus pause, never a fault,
		# crash, held session, or the intentional pause in the transition tape.
		if focus_resume_pending:
			focus_resume_pending = false
			if args.has("resume-focus") and stage != 3 and scene.session.sim.paused \
					and scene.session.holds.is_empty() and scene.session.crash.is_empty() \
					and scene.session.pause_reason.is_empty() and scene.session.sim.fault_reason.is_empty():
				scene.session.resume()
				focus_resumes += 1
		var next_stage: int = _stage_at(elapsed)
		if next_stage != stage:
			stage = next_stage
			if stage == 3:
				scene.session.sim.set_paused(true)
			elif stage == 4:
				scene.session.sim.set_paused(false)
			elif stage == 5:
				var key: InputEventKey = InputEventKey.new()
				key.keycode = KEY_C
				key.physical_keycode = KEY_C
				key.pressed = true
				scene._unhandled_input(key)
			elif stage == 6:
				scene.session.reset()
			events.append({wall_s = elapsed, stage = stage, tick = scene.session.sim.tick,
				rpm = scene.session.sim.aux[0], paused = scene.session.sim.paused})
		var available: int = capture.get_frames_available()
		var buffer: PackedVector2Array = capture.get_buffer(available) if available > 0 else PackedVector2Array()
		if adapter.soundscape.wildlife.serial > wildlife_serial:
			wildlife_serial = adapter.soundscape.wildlife.serial
			var animal_event: Dictionary = adapter.soundscape.wildlife.last_event.duplicate()
			animal_event.wall_s = elapsed
			wildlife_events.append(animal_event)
		samples.append_array(buffer)
		if elapsed > 1.0:
			timings.append(adapter.last_update_usec)
			mechanical_timings.append(adapter.last_mechanical_update_usec)
		if args.has("mechanical-review") and elapsed >= next_mechanical_sample_s:
			next_mechanical_sample_s = elapsed + 0.1
			mechanical_samples.append({wall_s = elapsed, stage = stage, tick = scene.session.sim.tick,
				rpm = scene.session.sim.aux[0], running = scene.session.propulsion_source_running(),
				paused = scene.session.sim.paused, engine_family = adapter.soundscape.voice_profile.get("family", ""),
				mechanical = adapter.mechanical_audio.diagnostics()})
		var distance: float = scene._airplane.root.global_position.distance_to(scene._camera.global_position)
		if elapsed > 0.25:
			position_min = minf(position_min, distance)
			position_max = maxf(position_max, distance)
			if stage < 5:
				pilot_distance_min = minf(pilot_distance_min, distance)
				pilot_doppler_min = minf(pilot_doppler_min, adapter.soundscape.last_doppler)
				pilot_doppler_max = maxf(pilot_doppler_max, adapter.soundscape.last_doppler)
	var pending_frames_at_stop: int = capture.get_frames_available()
	if pending_frames_at_stop > 0:
		samples.append_array(capture.get_buffer(pending_frames_at_stop))
	var capture_bus_effect_count: int = AudioServer.get_bus_effect_count(capture_bus_index)
	var capture_effect_removed: bool = false
	for effect_index: int in range(capture_bus_effect_count - 1, -1, -1):
		if AudioServer.get_bus_effect(capture_bus_index, effect_index) == capture:
			AudioServer.remove_bus_effect(capture_bus_index, effect_index)
			capture_effect_removed = true
			break
	var final_available_before_flush: int = capture.get_frames_available()
	var flushed_frames: int = 0
	if final_available_before_flush > 0:
		flushed_frames = capture.get_buffer(final_available_before_flush).size()
	var final_available_after_flush: int = capture.get_frames_available()
	var capture_final_pushed: int = capture.get_pushed_frames()
	var capture_final_discarded: int = capture.get_discarded_frames()
	var pushed_frames: int = maxi(0, capture_final_pushed - capture_initial_pushed)
	dropped = maxi(0, capture_final_discarded - capture_initial_discarded)
	var output: String = str(args.out)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + ".png")
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.mix_rate = int(AudioServer.get_mix_rate())
	wav.stereo = true
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(samples.size() * 4)
	var square_sum: float = 0.0
	for i: int in samples.size():
		var frame: Vector2 = samples[i]
		if not is_finite(frame.x) or not is_finite(frame.y):
			invalid_sample = true
			frame = Vector2.ZERO
		bytes.encode_s16(i * 4, clampi(roundi(frame.x * 32767.0), -32768, 32767))
		bytes.encode_s16(i * 4 + 2, clampi(roundi(frame.y * 32767.0), -32768, 32767))
		square_sum += frame.length_squared()
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
	wav.data = bytes
	var saved: Error = wav.save_to_wav(output + ".wav")
	var report: Dictionary = {
		format = "openrc-audio-gameplay-v1", godot = Engine.get_version_info().string,
		arguments = args, project_path = ProjectSettings.globalize_path("res://"),
		audio_sources_sha256 = {
			adapter = FileAccess.get_sha256("res://audio/flight_audio.gd"),
			mixer = FileAccess.get_sha256("res://audio/soundscape.gd"),
			model = FileAccess.get_sha256("res://audio/soundscape_model.gd"),
			wildlife = FileAccess.get_sha256("res://audio/wildlife.gd"),
			mechanical = FileAccess.get_sha256("res://audio/mechanical_audio.gd"),
			mechanical_motion = FileAccess.get_sha256("res://audio/mechanical_motion.gd"),
		},
		probe_sha256 = probe_sha256,
		driver = driver, display = DisplayServer.get_name(), requested_fps = Engine.max_fps,
		aircraft = scene.aircraft_id, frames = samples.size(), mix_rate = wav.mix_rate,
		captured_seconds = float(samples.size()) / wav.mix_rate, peak_dbfs = linear_to_db(maxf(peak, 1e-12)),
		capture_wall_seconds = elapsed,
		capture_effect_removed = capture_effect_removed,
		finite_samples = not invalid_sample,
		capture_bookkeeping = {
			buffer_length_frames = capture.get_buffer_length_frames(),
			initial = {pushed_frames = capture_initial_pushed, discarded_frames = capture_initial_discarded,
				available_frames = capture_initial_available},
			final = {pushed_frames = capture_final_pushed, discarded_frames = capture_final_discarded,
				available_frames_before_flush = final_available_before_flush,
				flushed_frames = flushed_frames,
				available_frames_after_flush = final_available_after_flush},
			pushed_frames = pushed_frames,
			recorded_frames = samples.size(),
			flushed_frames = flushed_frames,
			truncated_frames = 0,
			overflow_discarded_frames = dropped,
			unaccounted_pushed_frames = pushed_frames - samples.size() - flushed_frames - final_available_after_flush,
		},
		rms_dbfs = linear_to_db(sqrt(square_sum / maxf(samples.size() * 2.0, 1.0))),
		discarded_frames = dropped, soundscape_update_p95_us = _percentile_usec(timings, 0.95),
		soundscape_update_max_us = _maximum_usec(timings), soundscape_timing_sample_count = timings.size(),
		driver_latency_estimate_s = AudioServer.get_output_latency(),
		distance_min_m = position_min, distance_max_m = position_max, voices = adapter.soundscape.voices.size(),
		pilot_doppler_min = pilot_doppler_min, pilot_doppler_max = pilot_doppler_max, pilot_distance_min_m = pilot_distance_min,
		events = events, wav_saved = saved == OK,
		wildlife_events = wildlife_events, wildlife_activity = adapter.soundscape.wildlife_presence,
		final_tick = scene.session.sim.tick, final_paused = scene.session.sim.paused,
		final_pause_reason = scene.session.pause_reason, focus_resumes = focus_resumes,
		mechanical_samples = mechanical_samples,
		mechanical_update_p95_us = _percentile_usec(mechanical_timings, 0.95),
		mechanical_update_max_us = _maximum_usec(mechanical_timings),
		mechanical_timing_sample_count = mechanical_timings.size(),
		note = "Actual physics flight with automated controls. Mixer capture is not speaker listening, acoustic validation, or device latency measurement.",
	}
	var file: FileAccess = FileAccess.open(output + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print(JSON.stringify(report))
	root.remove_child(scene)
	scene.free()
	await process_frame
	var bookkeeping_balanced: bool = pushed_frames == samples.size() + flushed_frames \
		+ final_available_after_flush
	quit(0 if saved == OK and dropped == 0 and not invalid_sample \
		and peak < db_to_linear(-0.9) and peak > 0.0001 \
		and capture_effect_removed and bookkeeping_balanced else 1)


func _stage_at(time_s: float) -> int:
	if args.has("wildlife-review"):
		return 0 # real trimmed flight, fixed pilot view; leave space for the field to be heard
	if time_s < 4.0: return 0
	if time_s < 7.0: return 1
	if time_s < 10.0: return 2
	if time_s < 11.0: return 3
	if time_s < 13.0: return 4
	if time_s < 15.0: return 5
	return 6


func _controls() -> Dictionary:
	var throttle: float = 0.0 # keyboard rate command, not a normalized stick position
	if stage == 1: throttle = 1.0
	elif stage == 2: throttle = -1.0
	var correction: float = 0.04 * sin(elapsed * 5.0) if args.has("mechanical-review") else 0.0
	return {roll = 0.0, pitch = correction, yaw = correction * 0.5, throttle = throttle}


func _probe_sha256() -> String:
	var repo_root: String = ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	return FileAccess.get_sha256(repo_root.path_join("tools/audio/gameplay_probe.gd"))


func _percentile_usec(values: Array[int], percentile: float) -> int:
	if values.is_empty():
		return 0
	var ordered: Array[int] = values.duplicate()
	ordered.sort()
	var index: int = clampi(ceili(float(ordered.size()) * percentile) - 1, 0, ordered.size() - 1)
	return ordered[index]


func _maximum_usec(values: Array[int]) -> int:
	var result: int = 0
	for value: int in values:
		result = maxi(result, value)
	return result

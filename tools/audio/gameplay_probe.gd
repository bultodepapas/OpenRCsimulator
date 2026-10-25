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
	capture = AudioEffectCapture.new()
	capture.buffer_length = 1.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index(adapter.soundscape.output_bus()), capture)
	var duration: float = float(args.get("duration", 20.0))
	var start_usec: int = Time.get_ticks_usec()
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
		var buffer: PackedVector2Array = capture.get_buffer(capture.get_frames_available())
		if adapter.soundscape.wildlife.serial > wildlife_serial:
			wildlife_serial = adapter.soundscape.wildlife.serial
			var animal_event: Dictionary = adapter.soundscape.wildlife.last_event.duplicate()
			animal_event.wall_s = elapsed
			wildlife_events.append(animal_event)
		for frame: Vector2 in buffer:
			peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
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
	dropped = capture.get_discarded_frames()
	timings.sort()
	mechanical_timings.sort()
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
		bytes.encode_s16(i * 4, clampi(roundi(samples[i].x * 32767.0), -32768, 32767))
		bytes.encode_s16(i * 4 + 2, clampi(roundi(samples[i].y * 32767.0), -32768, 32767))
		square_sum += samples[i].length_squared()
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
		driver = AudioServer.get_driver_name(), display = DisplayServer.get_name(), requested_fps = Engine.max_fps,
		aircraft = scene.aircraft_id, frames = samples.size(), mix_rate = wav.mix_rate,
		captured_seconds = float(samples.size()) / wav.mix_rate, peak_dbfs = linear_to_db(maxf(peak, 1e-12)),
		capture_wall_seconds = elapsed,
		rms_dbfs = linear_to_db(sqrt(square_sum / maxf(samples.size() * 2.0, 1.0))),
		discarded_frames = dropped, soundscape_update_p95_us = timings[int(timings.size() * 0.95)],
		soundscape_update_max_us = timings[-1], driver_latency_estimate_s = AudioServer.get_output_latency(),
		distance_min_m = position_min, distance_max_m = position_max, voices = adapter.soundscape.voices.size(),
		pilot_doppler_min = pilot_doppler_min, pilot_doppler_max = pilot_doppler_max, pilot_distance_min_m = pilot_distance_min,
		events = events, wav_saved = saved == OK,
		wildlife_events = wildlife_events, wildlife_activity = adapter.soundscape.wildlife_presence,
		final_tick = scene.session.sim.tick, final_paused = scene.session.sim.paused,
		final_pause_reason = scene.session.pause_reason, focus_resumes = focus_resumes,
		mechanical_samples = mechanical_samples,
		mechanical_update_p95_us = mechanical_timings[int(mechanical_timings.size() * 0.95)],
		mechanical_update_max_us = mechanical_timings[-1],
		note = "Actual physics flight with automated controls. Mixer capture is not speaker listening, acoustic validation, or device latency measurement.",
	}
	var file: FileAccess = FileAccess.open(output + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print(JSON.stringify(report))
	root.remove_child(scene)
	scene.free()
	await process_frame
	quit(0 if saved == OK and dropped == 0 and peak < db_to_linear(-0.9) and peak > 0.0001 else 1)


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

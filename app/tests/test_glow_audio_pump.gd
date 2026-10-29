extends SceneTree

const GlowAudioPump := preload("res://audio/glow_audio_pump.gd")
const GlowVoice := preload("res://audio/glow_voice.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_revision_phase_continuity()
	await _test_worker_queue_and_lifecycle()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_revision_phase_continuity() -> void:
	var telemetry: Dictionary = {
		"family": "glow_2t",
		"rpm": 5430.0,
		"max_rpm": 10000.0,
		"running": true,
		"firing_fraction": 1.0,
		"load": 0.7,
		"throttle": 0.7,
		"blade_count": 2,
		"phase_revolutions": 0.25,
		"opportunity_count": 12,
		"fire_count": 12,
		"firing_accumulator": 0.0,
		"fuel_kg": 0.1,
		"not_audio_telemetry": "discarded",
	}
	var voice: Variant = GlowVoice.new()
	voice.reset()
	var first_block: Dictionary = GlowAudioPump.snapshot_for_render(telemetry, 1, -1, 64)
	_check("a new revision keeps its accepted physical phase anchor",
		first_block.get("phase_revolutions", -1.0) == 0.25 and first_block.get("audio_queue_frames", -1) == 64)
	_check("pump render snapshot excludes unrelated application data",
		not GlowAudioPump._detached_telemetry(telemetry).has("not_audio_telemetry"))
	voice.render_telemetry(first_block, 256)
	var phase_before_stall: float = voice.phase
	var stall_frames: int = int(GlowVoice.RATE * 0.6)
	var rendered_frames := 0
	while rendered_frames < stall_frames:
		var block_frames: int = mini(256, stall_frames - rendered_frames)
		var repeated: Dictionary = GlowAudioPump.snapshot_for_render(telemetry, 1, 1, 400)
		if rendered_frames == 0:
			_check("unchanged telemetry revision drops stale physical phase counters",
				not repeated.has("phase_revolutions") and not repeated.has("opportunity_count") \
				and not repeated.has("fire_count") and not repeated.has("firing_accumulator") \
				and not repeated.has("audio_queue_frames"))
		voice.render_telemetry(repeated, block_frames)
		rendered_frames += block_frames
	var actual_advance: float = fposmod(voice.phase - phase_before_stall, 1.0)
	var expected_advance: float = fposmod(float(telemetry.rpm) / 60.0 * float(stall_frames) / GlowVoice.RATE, 1.0)
	_check("repeated telemetry advances oscillator through a 0.6 s main-thread stall",
		absf(actual_advance - expected_advance) < 0.001,
		"actual=%.6f expected=%.6f" % [actual_advance, expected_advance])


func _test_worker_queue_and_lifecycle() -> void:
	var master_bus: int = AudioServer.get_bus_index("Master")
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 2.0
	AudioServer.add_bus_effect(master_bus, capture)
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = GlowVoice.RATE
	generator.buffer_length = 0.2
	var player := AudioStreamPlayer.new()
	player.stream = generator
	player.bus = "Master"
	root.add_child(player)
	player.play()
	# Match production: start, pause, then obtain playback so the initial queue stays intact.
	player.stream_paused = true
	var playback := player.get_stream_playback() as AudioStreamGeneratorPlayback
	var telemetry: Dictionary = {
		"family": "glow_4t", "rpm": 6200.0, "max_rpm": 10000.0, "running": true,
		"firing_fraction": 0.8, "load": 0.65, "throttle": 0.65, "blade_count": 2,
		"phase_revolutions": 0.5, "opportunity_count": 22, "fire_count": 17, "firing_accumulator": 0.2,
	}
	var pump = GlowAudioPump.new()
	_check("active AudioStreamGeneratorPlayback is available for the worker", playback != null)
	if playback == null:
		root.remove_child(player)
		player.free()
		AudioServer.remove_bus_effect(master_bus, AudioServer.get_bus_effect_count(master_bus) - 1)
		pump.reset()
		return
	_check("pump starts a worker or reports its bounded synchronous fallback", pump.start(playback, telemetry))
	_check("pump refuses a duplicate start while its playback is active", not pump.start(playback, telemetry))
	var primed := await _wait_for_primed(pump, 120)
	var stats: Dictionary = pump.stats()
	_check("worker fills the queue before the player resumes", primed,
		"status=%s" % str(stats))
	_check("generator queue stays within the 50 ms target",
		int(stats.get("queue_frames", 0)) <= int(stats.get("target_frames", 0)) \
		and int(stats.get("target_frames", 0)) <= int(floor(GlowVoice.RATE * 0.05)))
	_check("paused startup did not underrun", int(stats.get("skips", -1)) == 0,
		"skips=%s" % str(stats.get("skips", null)))
	_check("telemetry accessor returns a detached producer snapshot",
		pump.telemetry_snapshot() == telemetry)
	var updated: Dictionary = telemetry.duplicate(true)
	updated["rpm"] = 6400.0
	pump.update_telemetry(updated)
	_check("telemetry publication advances the producer revision",
		int(pump.stats().get("published_revision", 0)) >= 2)
	_check("primed remains latched while the mixer consumes ordinary buffers", pump.is_primed())
	player.stream_paused = false
	await _wait_wall_msec(150)
	_drain_capture(capture)
	var pre_stall_stats: Dictionary = pump.stats()
	var stall_started_usec: int = Time.get_ticks_usec()
	OS.delay_msec(600)
	var measured_stall_seconds: float = float(Time.get_ticks_usec() - stall_started_usec) / 1000000.0
	var stall_pcm: PackedVector2Array = _drain_capture(capture)
	var post_stall_stats: Dictionary = pump.stats()
	var driver_name: String = AudioServer.get_driver_name()
	var mix_rate: float = float(AudioServer.get_mix_rate())
	var capture_seconds: float = float(stall_pcm.size()) / mix_rate
	var capture_rms: float = _stereo_rms(stall_pcm)
	var nonzero_frames: int = _nonzero_frames(stall_pcm)
	var skipped_delta: int = int(post_stall_stats.get("skips", 0)) - int(pre_stall_stats.get("skips", 0))
	var output_latency: float = AudioServer.get_output_latency()
	var is_dummy_driver: bool = driver_name.to_lower().contains("dummy")
	print("INFO worker stall: driver=%s fallback=%s elapsed=%.3fs captured=%.3fs rms=%.7f nonzero=%d skips=%d->%d latency=%.3fs" % [
		driver_name, str(post_stall_stats.get("fallback", false)), measured_stall_seconds,
		capture_seconds, capture_rms, nonzero_frames, int(pre_stall_stats.get("skips", 0)),
		int(post_stall_stats.get("skips", 0)), output_latency,
	])
	if bool(post_stall_stats.get("fallback", false)):
		print("N/A dedicated-worker stall qualification: Thread.start selected the synchronous fallback")
	else:
		_check("dedicated PCM worker remains live through a 0.6 s main-thread stall",
			bool(post_stall_stats.get("running", false)) and str(post_stall_stats.get("worker_error", "")).is_empty(),
			str(post_stall_stats))
		_check("captured PCM during the stall is nonzero and audible",
			capture_seconds > 0.0 and nonzero_frames > 0 and capture_rms > 1e-5,
			"captured %.3fs, RMS %.7f, nonzero frames %d" % [capture_seconds, capture_rms, nonzero_frames])
		if not is_dummy_driver:
			_check("AudioStreamGenerator skip count does not rise during the main-thread stall",
				skipped_delta == 0, "skip delta=%d" % skipped_delta)
			var permitted_loss: float = output_latency + 2048.0 / AudioServer.get_mix_rate()
			_check("native capture covers the stall within output latency and two mix buffers",
				capture_seconds >= measured_stall_seconds - permitted_loss,
				"captured %.3fs of %.3fs; allowed loss %.3fs" % [capture_seconds, measured_stall_seconds, permitted_loss])
		else:
			print("N/A skip-free and native-duration qualification: Dummy driver is a smoke test only")
	player.stream_paused = true
	# The worker's cached stats can lag the mixer, and the mixer may advance between the
	# post-stall sample and the pause. Compare playback counters within the paused interval.
	var paused_skips_before: int = _playback_skips(playback)
	await _wait_wall_msec(100)
	var paused_skips_after: int = _playback_skips(playback)
	_check("paused playback stays primed without an underrun",
		pump.is_primed() and paused_skips_after == paused_skips_before,
		"skips=%d->%d" % [paused_skips_before, paused_skips_after])
	# Discard the paused interval so the next capture cannot pass on pre-pause audio.
	_drain_capture(capture)
	if bool(post_stall_stats.get("fallback", false)):
		pump.update_telemetry(updated) # Production updates refill the synchronous fallback.
	player.stream_paused = false
	await _wait_wall_msec(100)
	var resumed_pcm: PackedVector2Array = _drain_capture(capture)
	var resumed_rms: float = _stereo_rms(resumed_pcm)
	var resumed_nonzero: int = _nonzero_frames(resumed_pcm)
	var resumed_skips: int = _playback_skips(playback)
	var resumed_stats: Dictionary = pump.stats()
	_check("resumed playback retains a live primed pump",
		bool(resumed_stats.get("running", false)) and bool(resumed_stats.get("primed", false)) \
		and str(resumed_stats.get("worker_error", "")).is_empty(), str(resumed_stats))
	_check("resumed playback produces audible PCM after the paused capture was drained",
		resumed_nonzero > 0 and resumed_rms > 1e-5,
		"frames=%d nonzero=%d RMS=%.7f driver=%s" % [resumed_pcm.size(), resumed_nonzero, resumed_rms, driver_name])
	if not is_dummy_driver and not bool(resumed_stats.get("fallback", false)):
		_check("native playback resumes without an underrun", resumed_skips == paused_skips_after,
			"skips=%d->%d" % [paused_skips_after, resumed_skips])
	pump.stop()
	_check("stop joins the worker before playback is stopped", not pump.is_running())
	player.stop()
	player.play()
	player.stream_paused = true
	var second_playback := player.get_stream_playback() as AudioStreamGeneratorPlayback
	_check("player can create a fresh playback after a joined stop", second_playback != null)
	if second_playback != null:
		_check("pump starts cleanly again after stop and join", pump.start(second_playback, telemetry))
		_check("restarted pump primes without waiting on stale queue state", await _wait_for_primed(pump, 120))
		pump.stop()
	player.stop()
	root.remove_child(player)
	player.free()
	AudioServer.remove_bus_effect(master_bus, AudioServer.get_bus_effect_count(master_bus) - 1)
	pump.reset()
	# Release local audio references and let the mixer settle before SceneTree quits.
	playback = null
	second_playback = null
	generator = null
	capture = null
	pump = null
	player = null
	await _wait_wall_msec(100)


func _wait_for_primed(pump, max_frames: int) -> bool:
	for _frame: int in max_frames:
		if pump.is_primed():
			return true
		await process_frame
	return pump.is_primed()


func _wait_wall_msec(duration_msec: int) -> void:
	var deadline_usec: int = Time.get_ticks_usec() + duration_msec * 1000
	while Time.get_ticks_usec() < deadline_usec:
		await process_frame


func _drain_capture(capture: AudioEffectCapture) -> PackedVector2Array:
	var frames: int = capture.get_frames_available()
	return capture.get_buffer(frames) if frames > 0 else PackedVector2Array()


func _playback_skips(playback: AudioStreamGeneratorPlayback) -> int:
	AudioServer.lock()
	var skips: int = playback.get_skips()
	AudioServer.unlock()
	return skips


func _stereo_rms(samples: PackedVector2Array) -> float:
	if samples.is_empty():
		return 0.0
	var sum_squares := 0.0
	for sample: Vector2 in samples:
		sum_squares += sample.length_squared()
	return sqrt(sum_squares / (2.0 * float(samples.size())))


func _nonzero_frames(samples: PackedVector2Array) -> int:
	var count := 0
	for sample: Vector2 in samples:
		if sample.length_squared() > 1e-12:
			count += 1
	return count


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	print(("ok   " if condition else "FAIL ") + label + (" — " + detail if not detail.is_empty() else ""))
	if not condition:
		_failures += 1

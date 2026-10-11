extends SceneTree

const CrashAudio = preload("res://render/crash/crash_audio.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var original_bus_count: int = AudioServer.bus_count
	var audio: Node3D = CrashAudio.new()
	root.add_child(audio)
	audio.setup()
	_check("setup creates exactly eight bounded voices", audio.voice_count() == 8, str(audio.voice_count()))
	_check("setup adds one isolated bus", AudioServer.bus_count == original_bus_count + 1)
	var bus_index: int = AudioServer.get_bus_index(audio.output_bus())
	_check("crash bus routes directly to Master", bus_index > 0 and AudioServer.get_bus_send(bus_index) == &"Master")
	var limiter: AudioEffectHardLimiter = AudioServer.get_bus_effect(bus_index, 0) as AudioEffectHardLimiter
	_check("crash bus has a -1 dBFS hard limiter", limiter != null and is_equal_approx(limiter.ceiling_db, -1.0))

	var invalid: Dictionary = {valid = false, "class" = 4, severity = 1.0, surface = "asphalt"}
	audio.impact(Vector3.ZERO, invalid, true)
	_check("invalid severity produces no sound", audio.active_voice_count() == 0)
	audio.update(0.02, false, 0.0)
	_check("fire stays off without an ignition input", audio.active_voice_count() == 0)
	var severe: Dictionary = {
		valid = true, "class" = 4, severity = 1.0, energy_j = 20_000.0,
		estimated_energy_j = 20_000.0, component_damage = 1.0,
		component = "nose", component_is_estimate = false, surface = "asphalt",
		impact_angle_deg = 45.0, speed_mps = 40.0, trigger = "hull_contact",
	}
	audio.impact(Vector3(1.0, 0.0, 2.0), severe, true)
	_check("severe impact layers crack, surface, tear, debris, scrape and turbine rundown", audio.active_voice_count() == 6, str(audio.active_voice_count()))
	audio.impact(Vector3.ZERO, severe, false)
	_check("one primary impact per flight is accepted", audio.active_voice_count() == 6)
	audio.update(0.02, true, 0.0)
	_check("user pause freezes all one-shot voices", _one_shots_paused(audio, true))
	audio.update(0.02, false, 0.0)
	_check("resume unfreezes one-shot voices", _one_shots_paused(audio, false))
	audio.update(0.02, false, 1.0)
	_check("fire starts only after separate positive input", audio.active_voice_count() <= audio.voice_count())
	for i: int in 20:
		audio.secondary(Vector3(float(i), 0.0, 0.0), 1.0)
		audio.update(0.08, false, 0.2)
	_check("secondary debris stays within the eight-voice bound", audio.active_voice_count() <= 8, str(audio.active_voice_count()))
	audio.reset()
	_check("reset clears old-flight voices and fire", audio.active_voice_count() == 0)
	audio.impact(Vector3.ZERO, severe, false)
	_check("reset allows the next flight impact", audio.active_voice_count() > 0)
	audio.shutdown()
	_check("shutdown removes only its own bus", AudioServer.bus_count == original_bus_count and AudioServer.get_bus_index(audio.output_bus()) == -1)
	audio.queue_free()
	await process_frame

	await _capture_peak()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _capture_peak() -> void:
	var audio: Node3D = CrashAudio.new()
	root.add_child(audio)
	audio.setup()
	var listener: AudioListener3D = AudioListener3D.new()
	root.add_child(listener)
	listener.make_current()
	listener.global_position = Vector3(0.0, 1.0, -1.0)
	var bus_index: int = AudioServer.get_bus_index(audio.output_bus())
	var capture: AudioEffectCapture = AudioEffectCapture.new()
	capture.buffer_length = 0.5
	AudioServer.add_bus_effect(bus_index, capture)
	await process_frame
	var severe: Dictionary = {valid = true, "class" = 4, severity = 1.0, surface = "asphalt"}
	audio.impact(Vector3.ZERO, severe, true)
	var peak: float = 0.0
	var captured_frames: int = 0
	for _frame: int in 180:
		await create_timer(1.0 / 60.0).timeout
		var available: int = capture.get_frames_available()
		if available > 0:
			var samples: PackedVector2Array = capture.get_buffer(available)
			captured_frames += samples.size()
			for sample: Vector2 in samples:
				peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
	if captured_frames == 0 or peak <= 0.0001:
		_check("native peak measurement unavailable from this audio driver", true,
			"frames=%d, peak=%.6f; no rendered event signal" % [captured_frames, peak])
	else:
		var ceiling: float = db_to_linear(-1.0)
		_check("native post-limiter crash-bus peak stays <= -1 dBFS", peak <= ceiling + 0.004,
			"peak=%.6f (%.2f dBFS), frames=%d" % [peak, linear_to_db(maxf(peak, 0.000001)), captured_frames])
		_check("native crash-bus capture contains event audio", peak > 0.0001, "peak=%.6f" % peak)
	audio.shutdown()
	audio.queue_free()
	listener.queue_free()
	await process_frame


func _one_shots_paused(audio: Node, expected: bool) -> bool:
	var voices: Array = audio.get("_voices")
	if voices.size() != 7:
		return false
	for voice: AudioStreamPlayer3D in voices:
		print("pause probe ", voice.name, " actual=", voice.stream_paused, " expected=", expected)
		if voice.stream_paused != expected:
			return false
	return true


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("OK: ", label)
	else:
		_failures += 1
		printerr("FAIL: %s%s" % [label, " — " + detail if not detail.is_empty() else ""])

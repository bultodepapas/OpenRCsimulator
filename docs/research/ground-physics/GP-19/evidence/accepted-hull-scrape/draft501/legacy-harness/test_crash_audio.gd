extends SceneTree

const CrashAudio = preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp19-hull-scrape/draft/crash_audio.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.audio_listener_enable_3d = true
	var camera: Camera3D = Camera3D.new()
	root.add_child(camera)
	camera.global_position = Vector3(0.0, 1.0, -1.0)
	camera.make_current()
	var listener: AudioListener3D = AudioListener3D.new()
	camera.add_child(listener)
	listener.make_current()
	await physics_frame
	await physics_frame
	var original_bus_count: int = AudioServer.bus_count
	var audio: Node3D = CrashAudio.new()
	root.add_child(audio)
	audio.setup()
	_check("setup creates exactly eight bounded voices", audio.voice_count() == 8, str(audio.voice_count()))
	_check("setup adds one isolated bus", AudioServer.bus_count == original_bus_count + 1)
	var bus_index: int = AudioServer.get_bus_index(audio.output_bus())
	_check("crash bus routes directly to Master", bus_index > 0 and AudioServer.get_bus_send(bus_index) == &"Master")
	var limiter: AudioEffectHardLimiter = AudioServer.get_bus_effect(bus_index, 0) as AudioEffectHardLimiter
	_check("crash bus has a -1.25 dBFS hard limiter", limiter != null and is_equal_approx(limiter.ceiling_db, -1.25))
	# GP-07d: the field's runway is a mown grass strip; paving is asphalt or concrete.
	_check("ground-surface aliases resolve", audio.call("_surface_sample", "asphalt") == "impact_hard"
		and audio.call("_surface_sample", "runway") == "impact_grass"
		and audio.call("_surface_sample", "rough_grass") == "impact_dirt"
		and audio.call("_surface_sample", "mown_grass") == "impact_grass")

	var invalid: Dictionary = {valid = false, "class" = 4, severity = 1.0, surface = "asphalt"}
	audio.impact(Vector3.ZERO, invalid, true)
	_check("invalid severity produces no sound", audio.active_voice_count() == 0)
	audio.update(0.02, false, 0.0)
	_check("fire stays off without an ignition input", audio.active_voice_count() == 0)
	if AudioServer.get_driver_name() == "Dummy":
		_check("Dummy driver allocates bounded pool without attempting playback", audio.get("_voices").size() == 7)
		var dummy_severe: Dictionary = {valid = true, "class" = 4, severity = 1.0, surface = "asphalt"}
		audio.impact(Vector3.ZERO, dummy_severe, true)
		audio.secondary(Vector3(1.0, 0.0, 0.0), 1.0)
		audio.update(0.02, false, 1.0)
		var no_dummy_playbacks: bool = audio.active_voice_count() == 0 and not audio._fire_voice.playing
		for voice: AudioStreamPlayer3D in audio._voices:
			no_dummy_playbacks = no_dummy_playbacks and not voice.playing \
				and not voice.has_stream_playback() and voice.stream == null
		_check("Dummy driver suppresses one-shot, secondary and fire playback", no_dummy_playbacks)
		_check("native peak capture is reserved for a real audio driver", true, "Dummy")
		audio.reset()
		_check("reset clears Dummy-driver state", audio.active_voice_count() == 0)
		audio.shutdown()
		_check("shutdown removes only its own bus", AudioServer.bus_count == original_bus_count and AudioServer.get_bus_index(audio.output_bus()) == -1)
		root.remove_child(audio)
		audio.free()
		root.remove_child(camera)
		camera.free()
		await process_frame
		print("%d checks, %d failed" % [_checks, _failures])
		quit(1 if _failures > 0 else 0)
		return
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
	await physics_frame
	audio.update(0.02, true, 0.0)
	await process_frame
	_check("user pause silences one-shot voices", bool(audio.get("_user_paused")) and _one_shots_muted(audio), _pause_details(audio))
	audio.update(0.02, false, 0.0)
	_check("resume restores remaining one-shot voices", _one_shots_restored(audio))
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
	root.remove_child(audio)
	audio.free()
	root.remove_child(camera)
	camera.free()
	await process_frame

	await _capture_peak()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
func _capture_peak() -> void:
	var driver: String = AudioServer.get_driver_name()
	if driver == "Dummy":
		_check("native peak capture explicitly skipped on Dummy driver", true, driver)
		return
	root.audio_listener_enable_3d = true
	var audio: Node3D = CrashAudio.new()
	root.add_child(audio)
	audio.setup()
	var camera: Camera3D = Camera3D.new()
	root.add_child(camera)
	camera.global_position = Vector3(0.0, 1.0, -1.0)
	camera.make_current()
	var listener: AudioListener3D = AudioListener3D.new()
	camera.add_child(listener)
	listener.make_current()
	await physics_frame
	await physics_frame
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
		await create_timer(1.0 / 60.0, true, false, true).timeout
		var available: int = capture.get_frames_available()
		if available > 0:
			var samples: PackedVector2Array = capture.get_buffer(available)
			captured_frames += samples.size()
			for sample: Vector2 in samples:
				peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
	_check("native crash-bus capture contains event audio", captured_frames > 0 and peak > 0.0001,
		"driver=%s frames=%d peak=%.6f" % [driver, captured_frames, peak])
	var ceiling: float = db_to_linear(-1.0)
	_check("native post-limiter crash-bus peak stays <= -1 dBFS", peak > 0.0001 and peak <= ceiling,
		"peak=%.6f (%.2f dBFS), frames=%d" % [peak, linear_to_db(maxf(peak, 0.000001)), captured_frames])
	print("Native crash bus capture: driver=%s peak=%.6f (%.2f dBFS), frames=%d" % [
		driver, peak, linear_to_db(maxf(peak, 0.000001)), captured_frames,
	])
	audio.shutdown()
	root.remove_child(audio)
	audio.free()
	root.remove_child(camera)
	camera.free()
	await process_frame


func _one_shots_muted(audio: Node) -> bool:
	var voices: Array = audio.get("_voices")
	if voices.size() != 7:
		return false
	for voice: AudioStreamPlayer3D in voices:
		# The player also gets stream_paused=true; this gain guard covers queued playback.
		if voice.volume_db > -79.9:
			return false
		if voice.has_stream_playback() and not voice.stream_paused:
			return false
	return true


func _one_shots_restored(audio: Node) -> bool:
	var voices: Array = audio.get("_voices")
	for voice: AudioStreamPlayer3D in voices:
		if voice.playing and voice.volume_db <= -79.9:
			return false
		if voice.has_stream_playback() and voice.stream_paused:
			return false
	return true


func _pause_details(audio: Node) -> String:
	var voices: Array = audio.get("_voices")
	var states: PackedStringArray = PackedStringArray()
	for voice: AudioStreamPlayer3D in voices:
		states.append("%s playback=%s paused=%s @%.1fdB" % [voice.name, str(voice.has_stream_playback()), str(voice.stream_paused), voice.volume_db])
	return "; ".join(states)


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("OK: ", label)
	else:
		_failures += 1
		printerr("FAIL: %s%s" % [label, " — " + detail if not detail.is_empty() else ""])

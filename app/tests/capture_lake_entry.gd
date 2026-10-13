## Native-renderer capture of one real FlightSession water collision.
## Run without --headless and without an audio-driver override:
##   godot --path app --script res://tests/capture_lake_entry.gd -- --out=res://../.tools/lake-entry
extends SceneTree

const Main := preload("res://main.gd")
const RB := preload("res://physics/rigid_body.gd")
const Frames := preload("res://render/frames.gd")
const Commands := preload("res://input/commands.gd")
const WaterEffects := preload("res://render/lake/water_effects.gd")
const LakeWorld := preload("res://render/lake/lake_world.gd")
const Scenery := preload("res://scenery/scenery.gd")
const AUDIO_LEAD_SECONDS := 1.0
const AUDIO_AFTER_SECONDS := 5.0
const AUDIO_BUFFER_SECONDS := 7.0

class CaptureFlight extends Main:
	pass

const START_NED := [110.0, 125.0, -2.0]
const START_VELOCITY_BODY := [0.0, 0.0, 12.0]
const MAX_FLIGHT_TICKS := 120

var _out_dir := ""
var _shots := {}
var _failure := ""
var _audio_capture: AudioEffectCapture
var _audio_samples := PackedVector2Array()
var _audio_bus_index := -1
var _audio_effect_index := -1
var _manual_step_timings: Array[Dictionary] = []


func _initialize() -> void:
	var width := 1280
	var height := 720
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--width="):
			width = int(arg.get_slice("=", 1))
		elif arg.begins_with("--height="):
			height = int(arg.get_slice("=", 1))
	root.size = Vector2i(width, height)
	Engine.max_fps = 60
	_out_dir = _output_directory()
	if DirAccess.make_dir_recursive_absolute(_out_dir) != OK:
		_failure = "cannot create capture output directory: " + _out_dir
	call_deferred("_run")


func _run() -> void:
	if not _failure.is_empty():
		printerr(_failure)
		quit(1)
		return
	var lake_options: Dictionary = LakeWorld.options()
	var scenery_options: Dictionary = Scenery.options()
	if not bool(lake_options.enabled) or not bool(scenery_options.enabled) \
			or bool(scenery_options.file_explicit) or not bool(scenery_options.audio) \
			or AudioServer.get_driver_name() == "Dummy":
		printerr("lake-entry capture requires default lake/scenery options and a native audio driver")
		quit(1)
		return
	if Engine.physics_ticks_per_second != 240:
		printerr("lake-entry capture requires the simulator's 240 Hz fixed step")
		quit(1)
		return
	var flight := CaptureFlight.new()
	flight.name = "LakeEntryCaptureFlight"
	flight.interactive_start = true
	root.add_child(flight)
	flight.set_process(false)
	flight.set_process_unhandled_input(false)
	await process_frame
	if flight.session == null or flight._field_node == null or flight._airplane.is_empty():
		await _abort(flight, "production Main did not construct a field, aircraft, and flight session")
		return
	flight.set_process(false)
	flight.set_process_unhandled_input(false)
	flight.session.set_physics_process(false)
	flight.session.sim.set_physics_process(false)
	flight.session.input_enabled = false
	flight.session.commands = Commands.neutral_commands()
	flight.session.raw = Commands.neutral_raw()
	flight.session.sim.inputs = flight.session._inputs()
	var lake: Dictionary = flight.session.lake_context()
	var field_identity := str(flight._field_node.get_meta("lake_identity", ""))
	var lake_node: Node = flight._field_node.get_node_or_null("Lake")
	var scene_identity := str(lake_node.get_meta("identity", "")) if lake_node != null else ""
	if lake.is_empty() or field_identity != str(lake.get("identity", "")) \
			or scene_identity != field_identity:
		await _abort(flight, "field metadata, render lake, and simulation lake identities do not match")
		return
	if str(lake.get("id", "")) != "near_runway" or str(lake.get("format", "")) != "openrc-lake v1":
		await _abort(flight, "production field did not load the authored near_runway definition")
		return
	if flight._crash_director == null or flight._crash_director.water_effects == null \
			or not flight._crash_director.water_effects._configured:
		await _abort(flight, "production crash director did not configure water effects")
		return

	var camera := Camera3D.new()
	camera.name = "LakeEntryCaptureCamera"
	camera.near = 0.05
	camera.far = 500.0
	root.add_child(camera)
	_set_camera(camera)
	if not flight.session.sim.reset(RB.make_state(PackedFloat64Array(START_NED), PackedFloat64Array(START_VELOCITY_BODY),
		PackedFloat64Array([1.0, 0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]))):
		await _abort(flight, "simulation rejected the bounded lake-entry initial state")
		return
	flight.session.sim.set_paused(false)
	# Complete GPU shader/probe warmup before measuring real-time audio or taking the first picture.
	flight._process(0.0)
	for _frame in 60:
		await process_frame
		await RenderingServer.frame_post_draw
	_audio_bus_index = AudioServer.get_bus_index(&"Master")
	if _audio_bus_index < 0:
		await _abort(flight, "native mixer has no Master output bus")
		return
	_audio_capture = AudioEffectCapture.new()
	_audio_capture.buffer_length = AUDIO_BUFFER_SECONDS
	AudioServer.add_bus_effect(_audio_bus_index, _audio_capture)
	_audio_effect_index = AudioServer.get_bus_effect_count(_audio_bus_index) - 1
	if _audio_effect_index < 0:
		await _abort(flight, "could not install AudioEffectCapture on the Master output bus")
		return

	flight._process(0.0) # Exercise Main's production render path with automatic processing disabled.
	await _capture_real_interval(flight, AUDIO_LEAD_SECONDS)
	if flight.session.sim.tick != 0:
		await _abort(flight, "simulation advanced during the one-second native audio lead-in")
		return
	await _capture_shot("before", flight, camera)
	var actual_event: Variant = null
	for _tick in MAX_FLIGHT_TICKS:
		var step_started_usec: int = Time.get_ticks_usec()
		flight.session.sim.step()
		_manual_step_timings.append({
			"tick": int(flight.session.sim.tick),
			"wall_usec": Time.get_ticks_usec() - step_started_usec,
			"sim_step_usec": float(flight.session.sim.step_usec),
		})
		if not flight.session.crash.is_empty():
			actual_event = flight.session.last_lake_event()
			break
	if actual_event == null or flight.session.crash.is_empty():
		await _abort(flight, "manual sim.step produced no bounded lake collision; no impact was synthesized")
		return
	var event_sim_tick: int = int(flight.session.sim.tick)
	var impact: Variant = flight.session.crash.get("impact")
	if impact == null or impact.trigger != "water" or actual_event.material != "water":
		await _abort(flight, "the actual simulation event was not a water contact")
		return

	var effects: WaterEffects = flight._crash_director.water_effects
	var point_ned: PackedFloat64Array = actual_event.point_ned
	if point_ned.size() != 3:
		await _abort(flight, "water event did not provide contact-point kinematics")
		return
	var audio_after_start_usec: int = Time.get_ticks_usec()
	flight._process(0.0) # Starts the actual WaterEffects player through Main's production director.
	if not effects._has_event:
		await _abort(flight, "actual water event did not reach the production effects path")
		return
	var impact_stream_path: String = str(effects._impact_voice.stream.resource_path) \
		if effects._impact_voice != null and effects._impact_voice.stream != null else ""
	await _capture_real_interval(flight, 0.15)
	await _capture_shot("plume", flight, camera)
	await _capture_real_interval(flight, 0.55)
	await _capture_shot("ripples", flight, camera)
	await _capture_real_interval(flight, 2.00)
	await _capture_shot("sink", flight, camera)

	var elapsed_before_pause := effects._elapsed_s
	flight.session.hold("lake-entry-capture-pause")
	await _capture_real_interval(flight, 0.15)
	var paused_effect_elapsed := effects._elapsed_s
	var ambience_paused := flight._lake_ambience == null or flight._lake_ambience.stream_paused
	var impact_voice_paused := effects._impact_voice == null or not effects._impact_voice.playing \
		or effects._impact_voice.stream_paused
	var pause_ok := paused_effect_elapsed == elapsed_before_pause and ambience_paused and impact_voice_paused
	flight.session.release("lake-entry-capture-pause")
	await _capture_real_interval(flight, 0.25)
	var resumed_effect_elapsed := effects._elapsed_s
	var resume_ok := resumed_effect_elapsed > paused_effect_elapsed
	var post_event_wall_s := float(Time.get_ticks_usec() - audio_after_start_usec) / 1000000.0
	if post_event_wall_s < AUDIO_AFTER_SECONDS:
		await _capture_real_interval(flight, AUDIO_AFTER_SECONDS - post_event_wall_s)
	post_event_wall_s = float(Time.get_ticks_usec() - audio_after_start_usec) / 1000000.0
	_drain_audio_capture()
	var event_effect_started := effects._has_event
	var audio_snapshot := {
		"enabled": effects._audio_enabled,
		"impact_requests": effects._impact_audio_requests_this_event,
		"impact_emitted": effects._impact_audio_emitted,
		"impact_source_index": effects._impact_audio_source_index,
		"impact_stream_path": impact_stream_path,
		"impact_voice_playing_before_reset": effects._impact_voice != null and effects._impact_voice.playing,
		"ambience_configured": flight._lake_ambience != null and flight._lake_ambience.stream != null,
		"ambience_paused_before_reset": flight._lake_ambience != null and flight._lake_ambience.stream_paused,
		"dry_crash_voices_before_reset": flight._crash_director.audio.active_voice_count(),
		"driver": AudioServer.get_driver_name(),
		"master_bus": String(AudioServer.get_bus_name(_audio_bus_index)),
		"lead_seconds_requested": AUDIO_LEAD_SECONDS,
		"post_event_seconds": post_event_wall_s,
		"captured_frames": _audio_samples.size(),
		"mix_rate_hz": int(AudioServer.get_mix_rate()),
		"discarded_frames": _audio_capture.get_discarded_frames(),
	}
	flight.session.reset()
	flight._process(0.0)
	var reset_clears_event: bool = not effects._has_event and flight.session.last_lake_event() == null \
		and flight.session.crash.is_empty()
	await _capture_shot("reset", flight, camera)

	var report := {
		"format": "openrc-lake-entry-capture v1",
		"render_adapter": RenderingServer.get_video_adapter_name(),
		"render_api": RenderingServer.get_video_adapter_api_version(),
		"engine": Engine.get_version_info(),
		"lake_id": str(lake.id),
		"lake_identity": str(lake.identity),
		"field_lake_identity": field_identity,
		"render_lake_identity": scene_identity,
		"starting_position_ned_m": START_NED,
		"starting_velocity_body_frd_mps": START_VELOCITY_BODY,
		"event": {
			"trigger": str(impact.trigger),
			"material": str(actual_event.material),
			"obstacle_kind": str(actual_event.obstacle_kind),
			"response_status": str(actual_event.response_status),
			"tick": int(actual_event.tick),
			"time_fraction": float(actual_event.time_fraction),
			"probe_kind": str(actual_event.probe_kind),
			"probe_order": int(actual_event.probe_order),
			"point_index": int(actual_event.point_index),
			"point_ned_m": Array(point_ned),
			"surface_down_m": float(actual_event.surface_down_m),
			"depth_m": float(actual_event.depth_m),
			"normal_speed_mps": float(actual_event.normal_speed_mps),
			"sim_tick_after_event": event_sim_tick,
			"fixed_step_hz": Engine.physics_ticks_per_second,
			"fixed_duration_to_event_s": float(event_sim_tick) / float(Engine.physics_ticks_per_second),
			"step_timings_usec": _manual_step_timings.duplicate(true),
		},
		"aftermath": {
			"event_started": event_effect_started,
			"sink_duration_s": WaterEffects.SINK_DURATION_S,
			"sink_depth_m": WaterEffects.SINK_DEPTH_M,
			"elapsed_before_pause_s": elapsed_before_pause,
			"elapsed_while_paused_s": paused_effect_elapsed,
			"elapsed_after_resume_s": resumed_effect_elapsed,
			"pause_freezes_visuals_and_ambience": pause_ok,
			"resume_advances_visuals": resume_ok,
			"reset_clears_event": reset_clears_event,
		},
		"audio": audio_snapshot,
		"audio_capture": _audio_statistics(),
		"audio_wav_path": _out_dir.path_join("lake-entry.wav"),
		"shots": _shots.duplicate(true),
	}
	var wav_saved := _save_audio_wav(_out_dir.path_join("lake-entry.wav"))
	report["audio_capture"]["wav_saved"] = wav_saved
	var report_path := _out_dir.path_join("report.json")
	var report_file := FileAccess.open(report_path, FileAccess.WRITE)
	if report_file == null:
		_failure = "cannot write capture report: " + report_path
	else:
		report_file.store_string(JSON.stringify(report, "\t"))
		report_file.flush()
	if not pause_ok or not resume_ok or not reset_clears_event \
			or int(audio_snapshot.impact_requests) != 1 or not bool(audio_snapshot.impact_emitted) \
			or not bool(audio_snapshot.enabled) or not wav_saved \
			or int(audio_snapshot.discarded_frames) != 0 \
			or int(report.audio_capture.frames) <= 0 or float(report.audio_capture.peak_linear) <= 0.0001:
		_failure = "water aftermath pause, resume, or reset contract failed"
	print("lake-entry capture: actual water tick %d at NED %s, depth %.3f m; shots=%d; report=%s" % [
		int(actual_event.tick), str(point_ned), float(actual_event.depth_m),
		_shots.size(), report_path])
	if not _failure.is_empty():
		printerr(_failure)
	if _audio_effect_index >= 0:
		AudioServer.remove_bus_effect(_audio_bus_index, _audio_effect_index)
	await _cleanup(flight, camera)
	quit(1 if not _failure.is_empty() else 0)


func _capture_shot(label: String, flight: CaptureFlight, camera: Camera3D) -> void:
	_set_camera(camera)
	camera.look_at_from_position(Frames.ned_to_render([114.0, 122.0, -1.8]),
		Frames.ned_to_render([110.0, 125.0, 0.45]))
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image.is_empty():
		_failure = "renderer returned an empty image for shot " + label
		return
	var path := _out_dir.path_join(label + ".png")
	var error := image.save_png(path)
	if error != OK:
		_failure = "cannot save shot %s: %s" % [label, error_string(error)]
	else:
		_shots[label] = {"path": path, "width": image.get_width(), "height": image.get_height()}


func _capture_real_interval(flight: CaptureFlight, duration_s: float) -> void:
	var start_usec: int = Time.get_ticks_usec()
	var previous_usec: int = start_usec
	while float(Time.get_ticks_usec() - start_usec) / 1000000.0 < duration_s:
		await process_frame
		var now_usec: int = Time.get_ticks_usec()
		var delta_s: float = maxf(float(now_usec - previous_usec) / 1000000.0, 0.0)
		previous_usec = now_usec
		flight._process(delta_s)
		_drain_audio_capture()
		await RenderingServer.frame_post_draw


func _drain_audio_capture() -> void:
	if _audio_capture == null:
		return
	var available: int = _audio_capture.get_frames_available()
	if available > 0:
		_audio_samples.append_array(_audio_capture.get_buffer(available))


func _audio_statistics() -> Dictionary:
	var peak_linear := 0.0
	var square_sum := 0.0
	for frame: Vector2 in _audio_samples:
		peak_linear = maxf(peak_linear, maxf(absf(frame.x), absf(frame.y)))
		square_sum += frame.length_squared()
	var sample_count := maxf(float(_audio_samples.size()) * 2.0, 1.0)
	return {
		"frames": _audio_samples.size(),
		"mix_rate_hz": int(AudioServer.get_mix_rate()),
		"captured_seconds": float(_audio_samples.size()) / maxf(float(AudioServer.get_mix_rate()), 1.0),
		"peak_linear": peak_linear,
		"peak_dbfs": linear_to_db(maxf(peak_linear, 1.0e-12)),
		"rms_linear": sqrt(square_sum / sample_count),
		"rms_dbfs": linear_to_db(maxf(sqrt(square_sum / sample_count), 1.0e-12)),
		"discarded_frames": _audio_capture.get_discarded_frames() if _audio_capture != null else -1,
		"bus": String(AudioServer.get_bus_name(_audio_bus_index)) if _audio_bus_index >= 0 else "",
		"native_driver": AudioServer.get_driver_name(),
	}


func _save_audio_wav(path: String) -> bool:
	var wav := AudioStreamWAV.new()
	wav.mix_rate = int(AudioServer.get_mix_rate())
	wav.stereo = true
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	var bytes := PackedByteArray()
	bytes.resize(_audio_samples.size() * 4)
	for index: int in _audio_samples.size():
		bytes.encode_s16(index * 4, clampi(roundi(_audio_samples[index].x * 32767.0), -32768, 32767))
		bytes.encode_s16(index * 4 + 2, clampi(roundi(_audio_samples[index].y * 32767.0), -32768, 32767))
	wav.data = bytes
	return wav.save_to_wav(path) == OK


func _set_camera(camera: Camera3D) -> void:
	camera.current = true
	camera.fov = 40.0


func _output_directory() -> String:
	var value := "res://../.tools/lake-entry"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			value = arg.trim_prefix("--out=")
	return ProjectSettings.globalize_path(value)


func _abort(flight: CaptureFlight, message: String) -> void:
	_failure = message
	printerr("lake-entry capture refused: " + message)
	await _cleanup(flight, null)
	quit(1)


func _cleanup(flight: CaptureFlight, camera: Camera3D) -> void:
	if camera != null and is_instance_valid(camera):
		camera.queue_free()
	if is_instance_valid(flight):
		flight.queue_free()
	await process_frame

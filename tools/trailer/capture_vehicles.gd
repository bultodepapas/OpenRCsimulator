# TRA-05. Capture playable production vehicle routes through their normal input paths.
# Run from the repo root, for example:
#   .tools/Godot_v4.7.2-stable_win64_console.exe --path app --script ../tools/trailer/capture_vehicles.gd -- --vehicle=mt8-bisonte --out-dir=../tmp/trailer/vehicles/bisonte
# No session state is scripted: keyboard keys are delivered through Godot InputEventKey.
extends SceneTree

const FPS := 60
const WIDTH := 1920
const HEIGHT := 1080
const AppRootScene := preload("res://app_root.tscn")

var output_dir := ""
var vehicle_id := ""
var pilot := false
var pressed: Dictionary = {}
var app
var activity
var movie_path := ""
var audio_record: AudioEffectRecord
var record_bus := -1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var current_dir := DirAccess.open(".").get_current_dir()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--vehicle="):
			vehicle_id = arg.trim_prefix("--vehicle=")
		elif arg.begins_with("--out-dir="):
			var requested: String = arg.trim_prefix("--out-dir=")
			output_dir = requested if requested.is_absolute_path() else current_dir.path_join(requested)
		elif arg == "--pilot":
			pilot = true
	if vehicle_id not in ["xcell-60-research", "mt8-bisonte", "monster-car-2"] or output_dir.is_empty():
		push_error("Expected --vehicle=xcell-60-research|mt8-bisonte|monster-car-2 and --out-dir=<absolute-or-project-relative-path>.")
		quit(2)
		return
	var heli := vehicle_id == "xcell-60-research"
	var frames := (2 * FPS if heli else 60) if pilot else (5 * FPS if heli else 4 * FPS)
	# Keep pilot and final captures at the requested production canvas. The Movie
	# Maker reads the project viewport before this SceneTree script starts.
	var width := WIDTH
	var height := HEIGHT
	DirAccess.make_dir_recursive_absolute(output_dir)
	root.size = Vector2i(width, height)
	movie_path = Engine.get_write_movie_path()
	var movie_maker := not movie_path.is_empty()
	if not movie_maker and not pilot:
		push_error("Full captures require Godot Movie Maker for fixed 60 fps and synchronized audio; launch with --write-movie <clip.avi> --fixed-fps 60.")
		quit(2)
		return
	if not movie_maker:
		Engine.max_fps = FPS
		_setup_audio_recording()
	else:
		Engine.max_fps = 0
	print("VEHICLE_MOVIE_WRITER ", movie_path if movie_maker else "unavailable; pilot fallback")

	app = AppRootScene.instantiate()
	if heli:
		app.user_args = PackedStringArray(["--aircraft=xcell-60-research", "--start=airborne", "--view=chase"])
	else:
		app.user_args = PackedStringArray(["--vehicle=" + vehicle_id])
	root.add_child(app)
	for _wait in range(120):
		await process_frame
		activity = app.flight if heli else app.ground_vehicle
		if activity != null:
			break
	if activity == null:
		push_error("Production route did not create an activity: " + vehicle_id)
		quit(1)
		return
	if heli:
		if not activity.startup_error.is_empty():
			push_error("Helicopter route refused startup: " + activity.startup_error)
			quit(1)
			return
		activity.set_overlays_visible(false)
		if activity.session.sim.paused or not activity.session.is_flyable():
			push_error("Helicopter did not reach its unpaused airborne start.")
			quit(1)
			return
		var heli_camera = activity.get("_rig")
		heli_camera.set_view("orbit")
		await process_frame
		heli_camera.orbit.distance = 2.55
		heli_camera.orbit.elevation_deg = 12.0
		heli_camera.orbit.azimuth_deg = 215.0
	else:
		if not activity.startup_error.is_empty():
			push_error("Ground route refused startup: " + activity.startup_error)
			quit(1)
			return
		if vehicle_id == "monster-car-2":
			# This Nitro truck starts with its engine stopped. Use the normal pit
			# service action before driving so the capture shows a live powertrain.
			activity.handle_action("engine_start")
			if not activity.session.load_error.is_empty():
				push_error("Monster Car 2 engine service failed: " + activity.session.load_error)
				quit(1)
				return
		activity.handle_action("resume")
		activity.dashboard.visible = false
		# A closer-than-default boom keeps the camera low to the suspension while framing the full truck.
		activity.camera_rig.distance = 1.75
		activity.camera_rig.chase.distance = 1.75
		activity.camera_rig.chase.height = 0.62
		if activity.session.paused:
			push_error("Ground session did not resume from the production garage.")
			quit(1)
			return
	var warm_start_tick := int(activity.session.tick) if not heli else -1
	for _warm in range(6):
		await process_frame
	if not heli and (activity.session.paused or int(activity.session.tick) <= warm_start_tick):
		push_error("Ground session failed to advance after resume: paused=%s tick=%d start_tick=%d focused=%s controls=%s" % [
			str(activity.session.paused), int(activity.session.tick), warm_start_tick,
			str(activity._focused), str(activity._last_controls)])
		quit(1)
		return
	if audio_record != null:
		audio_record.set_recording_active(true)
	var movie_start_process_frame := Engine.get_process_frames()

	var manifest := {
		"format": "openrc-trailer-vehicle-capture v1",
		"classification": "playable production-route gameplay; real session physics and keyboard input",
		"vehicle_id": vehicle_id,
		"frames": frames,
		"fps": FPS,
		"width": width,
		"height": height,
		"engine": Engine.get_version_info().string,
		"camera": "production orbit view, low 2.55 m boom" if heli else "production ground chase view, low 1.75 m boom",
		"input": "Godot InputEventKey sent through Input.parse_input_event; no scripted_controls or session-state keyframes",
		"movie_writer_path": movie_path,
		"movie_writer_start_process_frame": movie_start_process_frame,
		"movie_writer_clip_start_index": movie_start_process_frame + 2,
		"movie_writer_clip_end_index_exclusive": movie_start_process_frame + 2 + frames,
		"audio": "48 kHz stereo PCM in Movie Maker AVI" if not movie_path.is_empty() else "AudioEffectRecord WAV fallback",
		"start_session_tick": int(activity.session.tick) if not heli else -1,
		"start_session_paused": bool(activity.session.paused) if not heli else false,
		"start_focused": bool(activity._focused) if not heli else true,
		"controller_selection_required": bool(activity._controller_requires_selection) if not heli else false,
		"records": [],
	}
	for frame: int in range(frames):
		_set_shot_input(frame, heli)
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		if image.get_width() != width or image.get_height() != height:
			push_error("Viewport size mismatch: %dx%d" % [image.get_width(), image.get_height()])
			_release_keys()
			quit(1)
			return
		if movie_path.is_empty() or (pilot and frame in [0, 30, frames - 1]):
			var image_name := "frame_%05d.png" % frame if movie_path.is_empty() else "sample_%05d.png" % frame
			var err: Error = image.save_png(output_dir.path_join(image_name))
			if err != OK:
				push_error("PNG write failed at frame %d (error %d)" % [frame, err])
				_release_keys()
				quit(err)
				return
		if frame % 30 == 0:
			manifest.records.append(_record(frame, heli))
		if frame % FPS == 0:
			print("VEHICLE_FRAME ", vehicle_id, " ", frame, "/", frames)
	_release_keys()
	manifest["movie_writer_end_process_frame"] = Engine.get_process_frames()
	manifest["movie_writer_clip_end_index_exclusive"] = int(manifest.movie_writer_clip_start_index) + frames
	if audio_record != null:
		audio_record.set_recording_active(false)
		var recording: AudioStreamWAV = audio_record.get_recording()
		if recording != null:
			var audio_error: Error = recording.save_to_wav(output_dir.path_join("capture.wav"))
			manifest["audio_wav"] = output_dir.path_join("capture.wav")
			manifest["audio_error"] = audio_error
			AudioServer.remove_bus_effect(record_bus, AudioServer.get_bus_effect_count(record_bus) - 1)
	var file := FileAccess.open(output_dir.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("VEHICLE_CAPTURE_OK ", vehicle_id, " ", frames, " frames -> ", output_dir)
	quit()


func _setup_audio_recording() -> void:
	record_bus = AudioServer.get_bus_index("Master")
	if record_bus < 0:
		push_warning("Master audio bus unavailable; this pilot will have no separate WAV capture.")
		return
	audio_record = AudioEffectRecord.new()
	AudioServer.add_bus_effect(record_bus, audio_record)
	audio_record.set_recording_active(false)


func _set_shot_input(frame: int, heli: bool) -> void:
	var desired: Dictionary = {}
	if heli:
		# Preserve the hover trim, apply a measured yaw turn, then a short forward cyclic input.
		if frame >= FPS * 1.25 and frame < FPS * 1.9:
			desired[KEY_D] = true
		if frame >= FPS * 2.55 and frame < FPS * 3.25:
			desired[KEY_UP] = true
	elif vehicle_id == "mt8-bisonte":
		if frame < FPS * 3.15:
			desired[KEY_W] = true
		if frame >= FPS * 0.75 and frame < FPS * 1.35:
			desired[KEY_D] = true
		elif frame >= FPS * 1.35 and frame < FPS * 2.35:
			desired[KEY_A] = true
		elif frame >= FPS * 2.35 and frame < FPS * 2.75:
			desired[KEY_D] = true
	else:
		if frame < FPS * 3.1:
			desired[KEY_W] = true
		if frame >= FPS * 0.9 and frame < FPS * 1.55:
			desired[KEY_A] = true
		elif frame >= FPS * 1.55 and frame < FPS * 2.45:
			desired[KEY_D] = true
		elif frame >= FPS * 2.45 and frame < FPS * 2.8:
			desired[KEY_A] = true
	for code: int in [KEY_W, KEY_A, KEY_D, KEY_UP]:
		_set_key(code, bool(desired.get(code, false)))


func _set_key(code: int, down: bool) -> void:
	if bool(pressed.get(code, false)) == down:
		return
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	pressed[code] = down


func _release_keys() -> void:
	for code: Variant in pressed.keys():
		_set_key(int(code), false)


func _record(frame: int, heli: bool) -> Dictionary:
	if heli:
		var session = activity.session
		var state: PackedFloat64Array = session.sim.state.duplicate()
		return {
			"frame": frame,
			"time_s": session.sim.time(),
			"position_ned_m": [state[0], state[1], state[2]],
			"speed_mps": sqrt(state[3] * state[3] + state[4] * state[4] + state[5] * state[5]),
			"yaw_input": session.commands.yaw,
			"pitch_input": session.commands.pitch,
			"phase": session.power_phase(),
			"crashed": not session.crash.is_empty(),
		}
	var telemetry: Dictionary = activity.session.telemetry_snapshot()
	var state: PackedFloat64Array = activity.session.state_snapshot()
	return {
		"frame": frame,
		"tick": int(activity.session.tick),
		"paused": bool(activity.session.paused),
		"time_s": activity.session.time_s(),
		"position": [state[0], state[1], state[2]],
		"speed_mps": float(telemetry.get("speed_m_per_s", 0.0)),
		"forward_speed_mps": float(telemetry.get("forward_speed_m_per_s", 0.0)),
		"airborne": bool(telemetry.get("airborne", false)),
		"engine_running": bool(telemetry.get("engine_running", false)),
		"steering": float(activity._last_controls.get("steering", 0.0)),
		"controls": activity._last_controls.duplicate(true),
	}

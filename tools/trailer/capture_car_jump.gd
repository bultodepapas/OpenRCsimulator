## External capture for a native Monster Car 2 tabletop jump on the production RC circuit.
## Use a production/runtime project at 1920x1080 with Movie Maker for a synchronized AVI.
extends SceneTree

const GroundActivity := preload("res://vehicles/ground/ground_scene.gd")
const AirfieldCourse := preload("res://physics/ground_vehicle/airfield_course.gd")

const FPS := 60
const WIDTH := 1920
const HEIGHT := 1080
const TICK_HZ := 240
const TICK_DT := 1.0 / TICK_HZ
const MOVIE_WRITER_LEAD_FRAMES := 3
const NEUTRAL := {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true}

var _out_dir := ""
var _seconds := 8.0
var _rehearsal := false
var _pilot := false
var _activity: Node
var _course_data: Dictionary = {}
var _movie_path := ""
var _failure := ""
var _pressed: Dictionary = {}
var _records: Array[Dictionary] = []
var _event_records: Array[Dictionary] = []
var _frame := 0
var _capture_start_process_frame := -1
var _pause_resume_count := 0
var _first_event_seen := 0
var _release_on_jump_number := 2
var _key_release_frame := -1
var _last_sample_tick := -1
var _launch_records: Array[Dictionary] = []


func _initialize() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	root.size = Vector2i(WIDTH, HEIGHT)
	root.msaa_3d = Viewport.MSAA_4X
	call_deferred("_run")


func _run() -> void:
	_parse_args()
	if not _failure.is_empty():
		_fail(_failure)
		return
	var directory_error := DirAccess.make_dir_recursive_absolute(_out_dir)
	if directory_error != OK:
		_fail("could not create output directory: " + error_string(directory_error))
		return
	_movie_path = Engine.get_write_movie_path()
	if _rehearsal and not _movie_path.is_empty():
		_fail("rehearsal mode must run without Movie Maker")
		return
	if not _rehearsal and not _pilot and _movie_path.is_empty():
		_fail("capture mode requires --write-movie and --fixed-fps 60")
		return
	if _pilot and not _movie_path.is_empty():
		_fail("pilot mode must run without Movie Maker")
		return
	if _movie_path.is_empty():
		Engine.max_fps = FPS
	if DisplayServer.get_name() != "headless":
		# Window decorations steal 19 px from the render viewport on this Windows host.
		# Make the native render surface borderless before moving it off-screen so
		# previews and Movie Maker keep the configured 1920x1080 canvas.
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		DisplayServer.window_set_size(Vector2i(WIDTH, HEIGHT))
		root.size = Vector2i(WIDTH, HEIGHT)
		DisplayServer.window_set_position(Vector2i.ZERO)

	TranslationServer.set_locale("en")
	_activity = GroundActivity.new()
	_activity.vehicle_id = "monster-car-2"
	_activity.use_practice_fixture = false
	_activity.enable_audio = not _rehearsal and not _pilot
	_activity.enable_vehicle_effects = not _rehearsal
	_activity.enable_course_visual = not _rehearsal
	root.add_child(_activity)
	for _wait in range(120):
		await process_frame
		if _activity.dashboard != null:
			break
	if _activity.dashboard == null or not _activity.startup_error.is_empty():
		_fail("production activity startup failed: " + str(_activity.startup_error))
		return
	if _activity.session == null or not _activity.session.prepared:
		_fail("production ground session did not prepare")
		return

	if not _activity.session.reset("track_start"):
		_fail("supported Circuit · Ramps spawn was rejected: " + str(_activity.session.load_error))
		return
	_activity._after_reset()
	_course_data = _activity.session.course_snapshot()
	if not _ensure_engine_running():
		_fail("Monster Car 2 engine service failed: " + str(_activity.session.load_error))
		return
	_activity.session.event_added.connect(_on_session_event)
	_setup_camera()
	_activity.dashboard.visible = false
	if not _activity.session.paused:
		_activity.session.add_pause_hold("garage")
	if _rehearsal:
		_run_rehearsal()
		return
	_activity.handle_action("resume")
	if _activity.session.paused:
		_fail("production ground session did not resume from the ramp spawn")
		return
	var warm_start_tick := int(_activity.session.tick)
	for _warm in range(2):
		await process_frame
	if _activity.session.paused or int(_activity.session.tick) <= warm_start_tick:
		_fail("ground physics did not advance after resume")
		return

	_capture_start_process_frame = Engine.get_process_frames()
	var start_tick := int(_activity.session.tick)
	var frame_count := int(round(_seconds * FPS))
	for frame in range(frame_count):
		_frame = frame
		_guard_capture_session()
		if not _failure.is_empty():
			break
		_set_key(KEY_W, _should_hold_throttle())
		await process_frame
		await RenderingServer.frame_post_draw
		var entry := _physical_sample(frame, "frame")
		_records.append(entry)
		if frame in [0, 30, 60, 90, 120, 150, 180, 210, 240, 270, 300, 330, 360, 390, 420, 450]:
			_save_preview(frame)
		if frame % FPS == 0:
			print("CAR_JUMP_FRAME ", frame, "/", frame_count, " tick=", entry.tick,
				" pos=", entry.position_ned_m, " speed=", entry.speed_mps,
				" airborne=", entry.airborne, " wheels=", entry.wheel_contact_count)
	if not _pressed.is_empty():
		_set_key(KEY_W, false)
	var end_tick := int(_activity.session.tick)
	var manifest := _build_manifest(frame_count, start_tick, end_tick)
	_write_json(_out_dir.path_join("capture.json"), manifest)
	if _failure.is_empty() and _has_valid_jump_and_landing(manifest):
		print("CAR_JUMP_CAPTURE_OK ", frame_count, " frames -> ", _movie_path)
		quit()
	else:
		if _failure.is_empty():
			_failure = "capture ended without a complete, upright, wheel-supported ramp jump and landing"
		manifest["capture_error"] = _failure
		manifest["complete"] = false
		_write_json(_out_dir.path_join("capture.json"), manifest)
		push_error(_failure)
		quit(1)


func _parse_args() -> void:
	var current_dir := DirAccess.open(".").get_current_dir()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out-dir="):
			var path := argument.trim_prefix("--out-dir=").replace("\\", "/")
			_out_dir = path if path.is_absolute_path() else current_dir.path_join(path).simplify_path()
		elif argument.begins_with("--seconds="):
			var value := argument.trim_prefix("--seconds=")
			if not value.is_valid_float():
				_failure = "--seconds must be a number from 1 to 16"
			else:
				_seconds = value.to_float()
		elif argument.begins_with("--release-on-jump="):
			var value := argument.trim_prefix("--release-on-jump=")
			if not value.is_valid_int():
				_failure = "--release-on-jump must be a positive jump number"
			else:
				_release_on_jump_number = value.to_int()
		elif argument == "--rehearsal":
			_rehearsal = true
		elif argument == "--pilot":
			_pilot = true
		else:
			_failure = "unsupported argument: " + argument
		if not _failure.is_empty():
			return
	if _out_dir.is_empty():
		_failure = "required argument missing: --out-dir=<absolute path>"
	elif _seconds < 1.0 or _seconds > 16.0:
		_failure = "--seconds must be in [1, 16]"
	elif _release_on_jump_number < 1 or _release_on_jump_number > 8:
		_failure = "--release-on-jump must be in [1, 8]"


func _ensure_engine_running() -> bool:
	var nitro: Dictionary = _activity.session.telemetry_snapshot().get("nitro", {})
	if bool(nitro.get("engine_running", false)):
		return true
	if float(nitro.get("fuel_kg", 0.0)) <= 0.0:
		_activity.handle_action("refuel")
		if not _activity.session.load_error.is_empty():
			return false
	_activity.handle_action("engine_start")
	if not _activity.session.load_error.is_empty():
		return false
	return bool(_activity.session.telemetry_snapshot().get("nitro", {}).get("engine_running", false))


func _setup_camera() -> void:
	var rig = _activity.camera_rig
	rig.mode = 2
	rig.distance = 3.8
	# The production straight runs east (+render X). Stay behind and on the north
	# side to clear south-side barriers that occluded the close pilot frame.
	rig.orbit_yaw = -0.65
	rig.orbit_pitch = 0.30
	rig.chase.distance = 2.0
	rig.reset()
	_activity.camera.fov = 46.0


func _run_rehearsal() -> void:
	_activity.set_physics_process(false)
	_activity.set_process(false)
	_activity.scripted_controls = _rehearsal_controls
	_activity.session.tick_once(NEUTRAL)
	_activity.session.release_pause_hold("garage")
	_activity.session.release_pause_hold("focus")
	if not _activity.session.resume():
		_fail("rehearsal could not resume the production session")
		return
	var start_tick := int(_activity.session.tick)
	var total_ticks := int(round(_seconds * TICK_HZ))
	for tick_index in total_ticks:
		_activity._physics_process(TICK_DT)
		var telemetry: Dictionary = _activity.session.telemetry_snapshot()
		if tick_index % 4 == 3 or bool(telemetry.get("airborne", false)):
			var entry := _physical_sample(int(round(float(tick_index + 1) / 4.0)), "tick")
			_records.append(entry)
		if not str(_activity.session.fault_reason).is_empty():
			_failure = "session fault: " + str(_activity.session.fault_reason)
			break
	var manifest := _build_manifest(int(round(_seconds * FPS)), start_tick, int(_activity.session.tick))
	manifest["rehearsal"] = true
	manifest["input"] = "accepted throttle control through the GroundScene scripted_controls test seam; no state injection"
	_write_json(_out_dir.path_join("rehearsal.json"), manifest)
	if _failure.is_empty():
		print("CAR_JUMP_REHEARSAL_OK events=", _event_records.size(), " samples=", _records.size(),
			" tick=", _activity.session.tick, " trace=", _out_dir.path_join("rehearsal.json"))
		quit()
	else:
		push_error(_failure)
		quit(1)


func _rehearsal_controls(_tick: int) -> Dictionary:
	var jumps := 0
	for item in _event_records:
		if str(item.event.get("type", "")) == "jump":
			jumps += 1
	var throttle := 1.0 if jumps < _release_on_jump_number else 0.0
	return {"throttle": throttle, "steering": 0.0, "brake": 0.0,
		"reverse": false, "armed": true}


func _should_hold_throttle() -> bool:
	var jump_count := 0
	for item in _event_records:
		if str(item.event.get("type", "")) == "jump":
			jump_count += 1
	return jump_count < _release_on_jump_number


func _guard_capture_session() -> void:
	if not _activity.session.paused:
		return
	if not str(_activity.session.fault_reason).is_empty() or not _activity.session.run_valid:
		_failure = "capture session paused after a simulation fault or invalid run"
		return
	# A native focus notification may open the garage. The harness resumes only that UI pause
	# after feeding the required neutral armed sample; it does not alter the vehicle state.
	_pause_resume_count += 1
	_activity._focused = true
	# Windows clears physical key state after focus loss while _pressed can stay
	# true; force a release so the main capture loop reasserts ordinary W input.
	_set_key(KEY_W, false)
	_activity.session.tick_once(NEUTRAL)
	_activity.session.release_pause_hold("focus")
	_activity.session.release_pause_hold("garage")
	if _activity.session.resume():
		_activity.dashboard.set_menu(false)
	else:
		_failure = "could not resume after a window-focus pause"


func _on_session_event(event: Dictionary) -> void:
	var event_type := str(event.get("type", ""))
	if event_type == "jump":
		_first_event_seen += 1
	var record := _physical_sample(_frame, "event", event)
	record["event"] = event.duplicate(true)
	record["movie_writer_frame_estimate"] = _movie_frame_estimate(_frame)
	_event_records.append(record)
	if event_type == "jump":
		_launch_records.append(record.duplicate(true))
		print("CAR_JUMP_EVENT ", JSON.stringify(record, "", true, true))
	elif event_type == "landing":
		print("CAR_LANDING_EVENT ", JSON.stringify(record, "", true, true))


func _physical_sample(frame: int, kind: String, event: Dictionary = {}) -> Dictionary:
	var state: PackedFloat64Array = _activity.session.state_snapshot()
	var telemetry: Dictionary = _activity.session.telemetry_snapshot()
	var road: Dictionary = AirfieldCourse.sample(_course_data, float(state[0]), float(state[1]))
	var wheel_flags: PackedByteArray = telemetry.get("wheel_in_contact", PackedByteArray())
	var hull_flags: PackedByteArray = telemetry.get("hull_in_contact", PackedByteArray())
	var wheel_count := _contact_count(wheel_flags)
	var hull_count := _contact_count(hull_flags)
	var item := {
		"kind": kind,
		"capture_frame": frame,
		"movie_writer_frame_estimate": _movie_frame_estimate(frame),
		"tick": int(_activity.session.tick),
		"time_s": float(_activity.session.time_s()),
		"position_ned_m": [float(state[0]), float(state[1]), float(state[2])],
		"up_m": -float(state[2]),
		"road_height_m": float(road.get("height_m", 0.0)),
		"cg_clearance_m": -float(state[2]) - float(road.get("height_m", 0.0)),
		"track_feature": str(road.get("feature_id", "")),
		"speed_mps": float(telemetry.get("speed_m_per_s", 0.0)),
		"forward_speed_mps": float(telemetry.get("forward_speed_m_per_s", 0.0)),
		"airborne": bool(telemetry.get("airborne", false)),
		"wheel_contact_count": wheel_count,
		"wheel_contact_flags": _flags_array(wheel_flags),
		"hull_contact_count": hull_count,
		"engine_running": bool(telemetry.get("nitro", {}).get("engine_running", false)),
		"engine_rpm": float(telemetry.get("nitro", {}).get("engine_rpm", 0.0)),
		"accepted_controls": _activity._last_controls.duplicate(true),
		"run_valid": bool(_activity.session.run_valid),
	}
	if not event.is_empty():
		item["event"] = event.duplicate(true)
	return item


func _movie_frame_estimate(frame: int) -> int:
	if _capture_start_process_frame < 0:
		return int(round(float(frame)))
	return MOVIE_WRITER_LEAD_FRAMES + frame


func _contact_count(flags: PackedByteArray) -> int:
	var count := 0
	for flag in flags:
		if flag != 0:
			count += 1
	return count


func _flags_array(flags: PackedByteArray) -> Array[int]:
	var result: Array[int] = []
	for flag in flags:
		result.append(int(flag))
	return result


func _set_key(code: Key, down: bool) -> void:
	if bool(_pressed.get(code, false)) == down:
		return
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	_pressed[code] = down


func _save_preview(frame: int) -> void:
	var image: Image = root.get_texture().get_image()
	if image.get_width() != WIDTH or image.get_height() != HEIGHT:
		_failure = "render viewport is not 1920x1080: %dx%d" % [image.get_width(), image.get_height()]
		return
	var error := image.save_png(_out_dir.path_join("frame_%04d.png" % frame))
	if error != OK:
		_failure = "could not save representative PNG at frame %d: %s" % [frame, error_string(error)]


func _build_manifest(frame_count: int, start_tick: int, end_tick: int) -> Dictionary:
	var identities: Dictionary = _activity.session.identities_snapshot() if _activity != null else {}
	var events: Array[Dictionary] = []
	for item in _event_records:
		events.append(item.duplicate(true))
	var best_event := _best_jump_summary()
	var movie_probe := not _movie_path.is_empty()
	return {
		"format": "openrc-trailer-car-jump-capture v1",
		"complete": _failure.is_empty(),
		"capture_error": _failure,
		"engine": Engine.get_version_info().string,
		"width": WIDTH,
		"height": HEIGHT,
		"fps": FPS,
		"frames_requested": frame_count,
		"seconds_requested": _seconds,
		"movie_file": _movie_path,
		"movie_writer_lead_frames_expected": MOVIE_WRITER_LEAD_FRAMES,
		"movie_writer_start_process_frame": _capture_start_process_frame,
		"movie_writer_clip_start_index_estimate": MOVIE_WRITER_LEAD_FRAMES if _capture_start_process_frame >= 0 else -1,
		"movie_writer_clip_end_index_exclusive_estimate": MOVIE_WRITER_LEAD_FRAMES + frame_count if _capture_start_process_frame >= 0 else -1,
		"movie_maker_enabled": movie_probe,
		"vehicle_id": "monster-car-2",
		"vehicle_name": "MONSTER CAR 2",
		"course_spawn_id": str(_activity.session.spawn_id) if _activity != null else "",
		"course_track_id": str(_activity.session.course_snapshot().get("track", {}).get("id", "")) if _activity != null else "",
		"route": "production shared airfield course, Circuit · Ramps, supported track_start spawn",
		"camera": {
			"view": "low side-quarter tracking orbit",
			"rig_mode": 2,
			"distance_m": 3.8,
			"orbit_yaw_rad": -0.65,
			"orbit_pitch_rad": 0.30,
		},
		"input": "production GroundScene keyboard path; ordinary W accelerator event; release after configured jump count",
		"release_on_jump_number": _release_on_jump_number,
		"focus_pause_resumes": _pause_resume_count,
		"start_tick": start_tick,
		"end_tick": end_tick,
		"start_time_s": float(start_tick) / TICK_HZ,
		"end_time_s": float(end_tick) / TICK_HZ,
		"physical_tick_hz": TICK_HZ,
		"run_valid": bool(_activity.session.run_valid) if _activity != null else false,
		"vehicle_identity": identities.get("model", {}),
		"course_identity": identities.get("course", {}),
		"events": events,
		"launch_landing_summary": best_event,
		"frame_samples": _records,
	}


func _best_jump_summary() -> Dictionary:
	var launch := {}
	var landing := {}
	var candidates: Array[Dictionary] = []
	for item in _event_records:
		if str(item.event.get("type", "")) == "jump":
			launch = item
			landing = {}
		elif str(item.event.get("type", "")) == "landing" and not launch.is_empty() and landing.is_empty():
			landing = item
			candidates.append(_jump_pair_summary(launch, landing))
			launch = {}
			landing = {}
	var best: Dictionary = {}
	for candidate in candidates:
		if best.is_empty() or float(candidate.airtime_s) > float(best.airtime_s):
			best = candidate.duplicate(true)
	if best.is_empty():
		return {"complete": false, "launch": {}, "landing": {}, "candidates": candidates}
	best["candidates"] = candidates
	return best


func _jump_pair_summary(launch: Dictionary, landing: Dictionary) -> Dictionary:
	return {
		"complete": true,
		"airtime_s": float(landing.time_s) - float(launch.time_s),
		"launch_speed_mps": float(launch.speed_mps),
		"launch_forward_speed_mps": float(launch.forward_speed_mps),
		"launch_wheel_contact_count": int(launch.wheel_contact_count),
		"peak_clearance_m": _peak_clearance_between(int(launch.tick), int(landing.tick)),
		"landing_speed_mps": float(landing.speed_mps),
		"landing_wheel_contact_count": int(landing.wheel_contact_count),
		"landing_hull_contact_count": int(landing.hull_contact_count),
		"landing_run_valid": bool(landing.run_valid),
		"launch": launch,
		"landing": landing,
	}


func _peak_clearance_between(start_tick: int, end_tick: int) -> float:
	var peak := -INF
	for item in _records:
		if int(item.tick) >= start_tick and int(item.tick) <= end_tick:
			peak = maxf(peak, float(item.cg_clearance_m))
	return peak if is_finite(peak) else -1.0


func _has_valid_jump_and_landing(manifest: Dictionary) -> bool:
	var summary: Dictionary = manifest.get("launch_landing_summary", {})
	return bool(summary.get("complete", false)) and bool(summary.get("landing_run_valid", false)) \
		and int(summary.get("landing_wheel_contact_count", 0)) > 0


func _write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failure = "could not write JSON: " + path
		return
	file.store_string(JSON.stringify(value, "\t", true, true) + "\n")
	file.close()


func _fail(message: String) -> void:
	_failure = message
	push_error(message)
	if not _out_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(_out_dir)
		_write_json(_out_dir.path_join("capture.json"), {
			"format": "openrc-trailer-car-jump-capture v1",
			"complete": false,
			"capture_error": message,
		})
	quit(1)

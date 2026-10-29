# VQ-01c / DT-10: real Home -> Fly -> Home loading, outside the production tree.
# Run with a native renderer. Engine elapsed time is not parent-process launch time.
extends SceneTree

const AUDIO_DRAIN_TIMEOUT_USEC := 1_000_000
var _app: Node
var _settings_path := "" # Only a sidecar successfully created by this run.
var _finishing := false
var _last_shutdown: Dictionary = {}
var _observe_camera := false
var _camera_frames: Array[Dictionary] = []
var _camera_uncovered_frames := 0
var _camera_capture_prefix := ""
var _camera_capture_pending := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var output := ""
	var aircraft := "jensen-das-ugly-stik-60"
	var start_choice := "airborne"
	var input_mode := "auto"
	var cycles := 3
	var dwell_msec := 0
	var prefetch_mode := "off"
	var prefetch_delay_msec := 350
	for arg in OS.get_cmdline_user_args():
		if arg == "--observe-camera":
			_observe_camera = true
		elif arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
		elif arg.begins_with("--aircraft="):
			aircraft = arg.trim_prefix("--aircraft=")
		elif arg.begins_with("--start="):
			start_choice = arg.trim_prefix("--start=")
		elif arg.begins_with("--input="):
			input_mode = arg.trim_prefix("--input=")
		elif arg.begins_with("--cycles=") and arg.trim_prefix("--cycles=").is_valid_int():
			cycles = int(arg.trim_prefix("--cycles="))
		elif arg.begins_with("--dwell-ms=") and arg.trim_prefix("--dwell-ms=").is_valid_int():
			dwell_msec = int(arg.trim_prefix("--dwell-ms="))
		elif arg.begins_with("--prefetch="):
			prefetch_mode = arg.trim_prefix("--prefetch=")
		elif arg.begins_with("--prefetch-delay-ms=") and arg.trim_prefix("--prefetch-delay-ms=").is_valid_int():
			prefetch_delay_msec = int(arg.trim_prefix("--prefetch-delay-ms="))
		else:
			_fail("Unknown or invalid option: " + arg)
			return
	if output.is_empty() or FileAccess.file_exists(output) or cycles < 1 or cycles > 50 or start_choice not in ["airborne", "runway"]:
		_fail("Provide a new --output file, --cycles in 1..50 and --start=airborne|runway")
		return
	if dwell_msec < 0 or dwell_msec > 30000 or prefetch_delay_msec < 0 or prefetch_delay_msec > 10000 \
			or prefetch_mode not in ["off", "scene", "trim", "scene_trim"]:
		_fail("Use --dwell-ms=0..30000, --prefetch=off|scene|trim|scene_trim and --prefetch-delay-ms=0..10000")
		return
	if DisplayServer.get_name() == "headless":
		_fail("Loading first-draw measurements require a native renderer")
		return
	if input_mode not in ["auto", "keyboard"]:
		_fail("Use --input=auto|keyboard")
		return
	var prefs_path := output + ".settings.cfg"
	if FileAccess.file_exists(prefs_path):
		_fail("Refusing to overwrite probe settings")
		return
	var preferences_script: Script = load("res://app_state/preferences.gd")
	var catalog: Script = load("res://app_state/aircraft_catalog.gd")
	var flight_session: Script = load("res://sim/flight_session.gd")
	if not catalog.can_fly(aircraft) or catalog.is_rotorcraft(aircraft):
		_fail("Probe requires a flyable fixed-wing catalog ID")
		return
	var prefs: Dictionary = preferences_script.DEFAULTS.duplicate(true)
	prefs.aircraft = aircraft
	prefs.language = "en"
	prefs.first_flight_hint_seen = true
	prefs.start_choice = start_choice
	if preferences_script.save_to(prefs_path, prefs) != OK:
		_fail("Cannot write isolated probe settings")
		return
	_settings_path = prefs_path
	var before_load := Time.get_ticks_usec()
	var packed: PackedScene = load("res://app_root.tscn")
	var app: Node = packed.instantiate()
	_app = app
	app.set("user_args", PackedStringArray())
	app.set("preferences_path", prefs_path)
	if "home_flight_prefetch_mode" in app:
		app.set("home_flight_prefetch_mode", prefetch_mode)
		app.set("home_flight_prefetch_delay_msec", prefetch_delay_msec)
	elif prefetch_mode != "off":
		_fail("This app does not implement Home flight prefetch")
		return
	var before_home := Time.get_ticks_usec()
	root.add_child(app)
	# Use the same explicit selection as Controls, within the probe's private profile.
	# This keeps connected controllers from adding a different confirmation hold to each role.
	if input_mode == "keyboard" and not app.controllers.select_devices(-1, -1):
		_fail("Could not select keyboard controls")
		return
	var home_ready := Time.get_ticks_usec()
	await process_frame
	await RenderingServer.frame_post_draw
	var home_drawn := Time.get_ticks_usec()
	var home: Control = app.get("home")
	if home == null or not home.is_visible_in_tree():
		_fail("Home did not become visible")
		return
	var samples: Array[Dictionary] = []
	var cycle_home_drawn := home_drawn
	for index in range(cycles):
		var memory_before_dwell := int(Performance.get_monitor(Performance.MEMORY_STATIC))
		var dwell := await _wait_at_home(dwell_msec)
		var preparation_before_fly := _preparation_snapshot(app)
		var trim_cache_before: Dictionary = flight_session.launch_trim_cache_stats()
		var fly: Button = app.get("home").get("fly_button")
		if fly.disabled:
			_fail("Home Fly is disabled")
			return
		var begin := Time.get_ticks_usec()
		if _observe_camera:
			_camera_frames.clear()
			_camera_uncovered_frames = 0
			_camera_capture_prefix = output + ".cycle-%d" % (index + 1)
			RenderingServer.frame_pre_draw.connect(_observe_camera_frame)
			RenderingServer.frame_post_draw.connect(_capture_camera_frame)
		fly.pressed.emit()
		var dispatched := Time.get_ticks_usec()
		# Home renders its acknowledgement before emitting fly_requested (UI-34c).
		# Await the real handoff; never call start_flight directly or bypass readiness.
		var handoff := await _wait_for_flight(app, home)
		if not handoff.ok:
			# Keep the actual refusal/cancellation reason before cleanup disposes Home.
			var failure_state: Dictionary = {}
			if is_instance_valid(app):
				failure_state = {cycle = index + 1, loading = app.last_flight_loading,
					note = app.home.note_label.text if is_instance_valid(app.home) else "no Home",
					phase = app._loading_phase, cancelled = app._loading_cancelled,
					focus_lost = app._loading_focus_lost}
			print("loading probe failure state: ", JSON.stringify(failure_state))
			_fail(handoff.error)
			return
		var ready: int = handoff.ready_usec
		var flight: Node = handoff.flight
		var session: Node = flight.get("session")
		# Keep real callbacks and focus safety. No manual pose/physics substitution.
		await process_frame
		await RenderingServer.frame_post_draw
		var drawn := Time.get_ticks_usec()
		var sim: Node = session.get("sim")
		var sample := {
			"cycle": index + 1, "fly_sync_usec": dispatched - begin,
			"home_to_ready_usec": ready - cycle_home_drawn,
			"home_dwell": dwell,
			"memory_before_dwell_bytes": memory_before_dwell,
			"memory_before_fly_bytes": dwell.memory_after_bytes,
			"preparation_before_fly": preparation_before_fly,
			"preparation_after_fly": _preparation_snapshot(app),
			"trim_cache_before_fly": trim_cache_before,
			"trim_cache_after_fly": flight_session.launch_trim_cache_stats(),
			"fly_ready_usec": ready - begin,
			"fly_first_draw_usec": drawn - begin,
			"tick_at_first_draw": sim.get("tick"), "paused_at_first_draw": sim.get("paused"),
			"pause_reason_at_first_draw": str(session.get("pause_reason")),
			"holds_at_first_draw": session.get("holds").duplicate(),
			"nodes_in_flight": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			"handoff_frames_usec": handoff.frames_usec,
		}
		if "startup_preparation_metrics" in flight:
			sample["startup_preparation"] = flight.startup_preparation_metrics.duplicate(true)
		if "last_flight_loading" in app:
			sample["loading"] = app.last_flight_loading.duplicate(true)
			if app.last_flight_loading.has("feedback_usec"):
				sample["loading_first_draw_usec"] = app.last_flight_loading.accepted_usec + app.last_flight_loading.feedback_usec - begin
		if not sim.paused:
			sample["active_at_first_draw_usec"] = drawn - begin
		if _observe_camera:
			for _frame in 12:
				await process_frame
				await RenderingServer.frame_post_draw
			RenderingServer.frame_pre_draw.disconnect(_observe_camera_frame)
			RenderingServer.frame_post_draw.disconnect(_capture_camera_frame)
			sample["camera_handoff"] = _camera_frames.duplicate(true)
		await process_frame
		var return_begin := Time.get_ticks_usec()
		app.call("end_flight")
		var return_ready := Time.get_ticks_usec()
		await process_frame
		await RenderingServer.frame_post_draw
		if app.get("flight") != null or app.get("home") == null:
			_fail("End flight failed to restore Home")
			return
		home = app.get("home")
		cycle_home_drawn = Time.get_ticks_usec()
		sample["return_sync_usec"] = return_ready - return_begin
		sample["return_first_draw_usec"] = Time.get_ticks_usec() - return_begin
		sample["nodes_at_home"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		sample["orphan_nodes"] = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
		samples.append(sample)
	var report := {
		"format": "openrc-loading-probe v1", "complete": true, "aircraft_id": aircraft,
		"start_choice": start_choice, "camera_observation_enabled": _observe_camera,
		"input_mode": input_mode,
		"engine": Engine.get_version_info(), "adapter": RenderingServer.get_video_adapter_name(),
		"renderer": RenderingServer.get_current_rendering_method(), "display_server": DisplayServer.get_name(),
		"viewport_size": [root.size.x, root.size.y], "max_fps": Engine.max_fps,
		"vsync_mode": DisplayServer.window_get_vsync_mode(),
		"app_load_and_instantiate_usec": before_home - before_load,
		"home_sync_usec": home_ready - before_home,
		"home_first_draw_from_load_usec": home_drawn - before_load,
		"home_first_draw_engine_elapsed_usec": home_drawn,
		"cache_state": "fresh process; OS/import/shader cache state uncontrolled",
		"prefetch_mode": prefetch_mode, "prefetch_delay_msec": prefetch_delay_msec,
		"home_dwell_requested_msec": dwell_msec,
		"fly_timing_semantics": "fly_sync_usec is pressed.emit dispatch only; fly_ready_usec includes deferred handoff and validated scene readiness; fly_first_draw_usec additionally waits for post-draw",
		"scope": "real Home Fly signal through first post-draw; callbacks and focus safety unchanged; no pilot input or package qualification",
		"cycles": samples,
	}
	report["shutdown"] = await _cleanup()
	report.complete = report.shutdown.audio_released and report.shutdown.settings_removed and report.shutdown.preparation_drained
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		_fail("Cannot create report")
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("loading probe: %d Home/Fly cycles -> %s" % [cycles, output])
	if not report.complete:
		_fail("Probe cleanup incomplete: " + str(report.shutdown))
		return
	quit(0)


## Dwell is measured separately from click latency and included in Home-to-ready.
func _wait_at_home(duration_msec: int) -> Dictionary:
	var begin := Time.get_ticks_usec()
	var previous := begin
	var frames: Array[int] = []
	while Time.get_ticks_usec() - begin < duration_msec * 1000:
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append(now - previous)
		previous = now
	return {requested_msec = duration_msec, elapsed_usec = Time.get_ticks_usec() - begin,
		frames_usec = frames, memory_after_bytes = int(Performance.get_monitor(Performance.MEMORY_STATIC))}


## Optional first-reveal diagnostics; per-draw observations, not timing acceptance samples.
func _observe_camera_frame() -> void:
	if not is_instance_valid(_app) or not is_instance_valid(_app.flight) or _camera_frames.size() >= 2000:
		return
	var flight: Node = _app.flight
	var camera: Camera3D = flight.get("_camera")
	if not is_instance_valid(camera) or not camera.is_inside_tree():
		return
	var loading: Node = _app.get("_loading_screen")
	var covered: bool = is_instance_valid(loading) and loading.is_inside_tree() and loading.visible \
		and loading.surface.is_visible_in_tree() and loading.backdrop.is_visible_in_tree() and loading.surface.modulate.a >= 1.0 \
		and loading.backdrop.color.a >= 1.0
	var position := camera.global_position
	var forward := -camera.global_basis.z
	var airplane: Dictionary = flight.get("_airplane")
	var aircraft_position: Vector3 = airplane.root.global_position
	var rig: RefCounted = flight.get("_rig")
	_camera_frames.append({frame = Engine.get_process_frames(), usec = Time.get_ticks_usec(),
		covered = covered, loading_active = _app._loading_active, phase = _app._loading_phase,
		camera_position = [position.x, position.y, position.z], camera_current = camera.is_current(),
		camera_forward = [forward.x, forward.y, forward.z], camera_fov = camera.fov,
		aircraft_position = [aircraft_position.x, aircraft_position.y, aircraft_position.z],
		camera_placed = rig != null and rig.get("_placed"), view = rig.get("view") if rig != null else "",
		has_render_pose = not flight.get("_last_render_pose").is_empty(),
		startup_complete = flight.get("startup_complete")})
	if not covered:
		_camera_uncovered_frames += 1
		_camera_capture_pending = _camera_uncovered_frames in [1, 10]


func _capture_camera_frame() -> void:
	if not _camera_capture_pending:
		return
	_camera_capture_pending = false
	var path := _camera_capture_prefix + ".camera-%d.png" % _camera_uncovered_frames
	if not FileAccess.file_exists(path):
		root.get_texture().get_image().save_png(path)


func _preparation_snapshot(app: Node) -> Dictionary:
	if "home_flight_preparation" in app:
		return app.get("home_flight_preparation").duplicate(true)
	return {}


## Staged Home preparation can cross many frames; tolerate bounded scheduling, not an unbounded wait.
## An external process timeout still bounds synchronous construction blocking a frame.
func _wait_for_flight(app: Node, home: Node, max_frames: int = 7200) -> Dictionary:
	var begin := Time.get_ticks_usec()
	var last_frame := begin
	var frames_usec: Array[int] = []
	for index in range(max_frames + 1):
		var frame_now := Time.get_ticks_usec()
		if index > 0: frames_usec.append(frame_now - last_frame)
		last_frame = frame_now
		if not is_instance_valid(app) or not app.is_inside_tree():
			return {ok = false, error = "Home Fly cancelled: app left the tree"}
		if Time.get_ticks_usec() - begin > 60000000:
			return {ok = false, error = "Home Fly handoff exceeded 60 seconds"}
		if "_loading_active" in app and app._loading_active:
			if index < max_frames:
				await process_frame
			continue # A candidate or detached Home is not a completed transaction.
		var flight: Node = app.get("flight")
		if flight != null:
			if not str(flight.get("startup_error")).is_empty():
				return {ok = false, error = "Home Fly startup error: " + str(flight.get("startup_error"))}
			var session: Node = flight.get("session")
			if session == null or not session.is_flyable():
				return {ok = false, error = "Flight session is not flyable"}
			return {ok = true, flight = flight, ready_usec = Time.get_ticks_usec(), frames_usec = frames_usec}
		if not is_instance_valid(home) or not home.is_inside_tree():
			return {ok = false, error = "Home Fly cancelled: Home left without a flight"}
		var fly: Button = home.get("fly_button")
		if fly == null or not fly.disabled:
			return {ok = false, error = "Home Fly rejected: returned to ready state without a flight"}
		if index < max_frames:
			await process_frame
	return {ok = false, error = "Home Fly handoff exceeded %d process frames" % max_frames}


## Outside every timing interval. Weak references observe mixer ownership without extending it.
func _cleanup() -> Dictionary:
	if RenderingServer.frame_pre_draw.is_connected(_observe_camera_frame):
		RenderingServer.frame_pre_draw.disconnect(_observe_camera_frame)
	if RenderingServer.frame_post_draw.is_connected(_capture_camera_frame):
		RenderingServer.frame_post_draw.disconnect(_capture_camera_frame)
	if not _last_shutdown.is_empty():
		return _last_shutdown
	var playbacks: Array[WeakRef] = []
	var preparation_drained := true
	if is_instance_valid(_app):
		if _app.has_method("shutdown_home_flight_preparation"):
			await _app.call("shutdown_home_flight_preparation")
			var preparation := _preparation_snapshot(_app)
			preparation_drained = preparation.get("drained", true)
		_collect_playbacks(_app, playbacks)
		_app.queue_free()
		_app = null
	var begin := Time.get_ticks_usec()
	await process_frame
	await process_frame
	var remaining := _remaining_playbacks(playbacks)
	while remaining > 0 and Time.get_ticks_usec() - begin < AUDIO_DRAIN_TIMEOUT_USEC:
		await process_frame
		remaining = _remaining_playbacks(playbacks)
	var settings_removed := true
	if not _settings_path.is_empty():
		settings_removed = DirAccess.remove_absolute(_settings_path) == OK
		if settings_removed:
			_settings_path = ""
	_last_shutdown = {tracked_playbacks = playbacks.size(), remaining_playbacks = remaining,
		preparation_drained = preparation_drained,
		audio_released = remaining == 0, elapsed_usec = Time.get_ticks_usec() - begin,
		timeout_usec = AUDIO_DRAIN_TIMEOUT_USEC, settings_removed = settings_removed}
	return _last_shutdown


func _collect_playbacks(node: Node, refs: Array[WeakRef]) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		if node.has_stream_playback():
			refs.append(weakref(node.get_stream_playback()))
	for child in node.get_children():
		_collect_playbacks(child, refs)


func _remaining_playbacks(refs: Array[WeakRef]) -> int:
	var remaining := 0
	for ref in refs:
		if ref.get_ref() != null:
			remaining += 1
	return remaining


func _fail(message: String) -> void:
	push_error(message)
	if _finishing:
		return
	_finishing = true
	_finish_failure.call_deferred()


func _finish_failure() -> void:
	var shutdown := await _cleanup()
	print("loading probe failure cleanup: ", JSON.stringify(shutdown))
	quit(1)

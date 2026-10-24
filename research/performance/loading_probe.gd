# VQ-01c / DT-10: real Home -> Fly -> Home loading, outside the production tree.
# Run with a native renderer. Engine elapsed time is not parent-process launch time.
extends SceneTree

const AUDIO_DRAIN_TIMEOUT_USEC := 1_000_000
var _app: Node
var _settings_path := "" # Only a sidecar successfully created by this run.
var _finishing := false
var _last_shutdown: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var output := ""
	var aircraft := "jensen-das-ugly-stik-60"
	var cycles := 3
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
		elif arg.begins_with("--aircraft="):
			aircraft = arg.trim_prefix("--aircraft=")
		elif arg.begins_with("--cycles=") and arg.trim_prefix("--cycles=").is_valid_int():
			cycles = int(arg.trim_prefix("--cycles="))
		else:
			_fail("Unknown or invalid option: " + arg)
			return
	if output.is_empty() or FileAccess.file_exists(output) or cycles < 1 or cycles > 50:
		_fail("Provide a new --output file and --cycles in 1..50")
		return
	if DisplayServer.get_name() == "headless":
		_fail("Loading first-draw measurements require a native renderer")
		return
	var prefs_path := output + ".settings.cfg"
	if FileAccess.file_exists(prefs_path):
		_fail("Refusing to overwrite probe settings")
		return
	var preferences_script: Script = load("res://app_state/preferences.gd")
	var catalog: Script = load("res://app_state/aircraft_catalog.gd")
	if not catalog.can_fly(aircraft) or catalog.is_rotorcraft(aircraft):
		_fail("Probe requires a flyable fixed-wing catalog ID")
		return
	var prefs: Dictionary = preferences_script.DEFAULTS.duplicate(true)
	prefs.aircraft = aircraft
	prefs.language = "en"
	prefs.first_flight_hint_seen = true
	prefs.start_choice = "airborne"
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
	var before_home := Time.get_ticks_usec()
	root.add_child(app)
	var home_ready := Time.get_ticks_usec()
	await process_frame
	await RenderingServer.frame_post_draw
	var home_drawn := Time.get_ticks_usec()
	var home: Control = app.get("home")
	if home == null or not home.is_visible_in_tree():
		_fail("Home did not become visible")
		return
	var samples: Array[Dictionary] = []
	for index in range(cycles):
		var fly: Button = app.get("home").get("fly_button")
		if fly.disabled:
			_fail("Home Fly is disabled")
			return
		var begin := Time.get_ticks_usec()
		fly.pressed.emit()
		var dispatched := Time.get_ticks_usec()
		# Home renders its acknowledgement before emitting fly_requested (UI-34c).
		# Await the real handoff; never call start_flight directly or bypass readiness.
		var handoff := await _wait_for_flight(app, home)
		if not handoff.ok:
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
			"fly_ready_usec": ready - begin,
			"fly_first_draw_usec": drawn - begin,
			"tick_at_first_draw": sim.get("tick"), "paused_at_first_draw": sim.get("paused"),
			"nodes_in_flight": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		}
		if "last_flight_loading" in app:
			sample["loading"] = app.last_flight_loading.duplicate(true)
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
		sample["return_sync_usec"] = return_ready - return_begin
		sample["return_first_draw_usec"] = Time.get_ticks_usec() - return_begin
		sample["nodes_at_home"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		sample["orphan_nodes"] = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
		samples.append(sample)
	var report := {
		"format": "openrc-loading-probe v1", "complete": true, "aircraft_id": aircraft,
		"engine": Engine.get_version_info(), "adapter": RenderingServer.get_video_adapter_name(),
		"renderer": RenderingServer.get_current_rendering_method(), "display_server": DisplayServer.get_name(),
		"viewport_size": [root.size.x, root.size.y], "max_fps": Engine.max_fps,
		"vsync_mode": DisplayServer.window_get_vsync_mode(),
		"app_load_and_instantiate_usec": before_home - before_load,
		"home_sync_usec": home_ready - before_home,
		"home_first_draw_from_load_usec": home_drawn - before_load,
		"home_first_draw_engine_elapsed_usec": home_drawn,
		"cache_state": "fresh process; OS/import/shader cache state uncontrolled",
		"fly_timing_semantics": "fly_sync_usec is pressed.emit dispatch only; fly_ready_usec includes deferred handoff and validated scene readiness; fly_first_draw_usec additionally waits for post-draw",
		"scope": "real Home Fly signal through first post-draw; callbacks and focus safety unchanged; no pilot input or package qualification",
		"cycles": samples,
	}
	report["shutdown"] = await _cleanup()
	report.complete = report.shutdown.audio_released and report.shutdown.settings_removed
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


## Staged Home preparation can cross many frames; tolerate bounded scheduling, not an unbounded wait.
## An external process timeout still bounds synchronous construction blocking a frame.
func _wait_for_flight(app: Node, home: Node, max_frames: int = 7200) -> Dictionary:
	var begin := Time.get_ticks_usec()
	for index in range(max_frames + 1):
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
			return {ok = true, flight = flight, ready_usec = Time.get_ticks_usec()}
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
	if not _last_shutdown.is_empty():
		return _last_shutdown
	var playbacks: Array[WeakRef] = []
	if is_instance_valid(_app):
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

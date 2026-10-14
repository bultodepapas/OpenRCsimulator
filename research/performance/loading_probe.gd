# VQ-01c / DT-10: real Home -> Fly -> Home loading, outside the production tree.
# Run with a native renderer. Engine elapsed time is not parent-process launch time.
extends SceneTree


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
	var before_load := Time.get_ticks_usec()
	var packed: PackedScene = load("res://app_root.tscn")
	var app: Node = packed.instantiate()
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
		var ready := Time.get_ticks_usec()
		var flight: Node = app.get("flight")
		if flight == null or not str(flight.get("startup_error")).is_empty():
			_fail("Home Fly failed to create a valid flight")
			return
		var session: Node = flight.get("session")
		if session == null or not session.is_flyable():
			_fail("Flight session is not flyable")
			return
		# Keep real callbacks and focus safety. No manual pose/physics substitution.
		await process_frame
		await RenderingServer.frame_post_draw
		var drawn := Time.get_ticks_usec()
		var sim: Node = session.get("sim")
		var sample := {
			"cycle": index + 1, "fly_sync_usec": ready - begin,
			"fly_first_draw_usec": drawn - begin,
			"tick_at_first_draw": sim.get("tick"), "paused_at_first_draw": sim.get("paused"),
			"nodes_in_flight": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		}
		await process_frame
		var return_begin := Time.get_ticks_usec()
		app.call("end_flight")
		var return_ready := Time.get_ticks_usec()
		await process_frame
		await RenderingServer.frame_post_draw
		if app.get("flight") != null or app.get("home") == null:
			_fail("End flight failed to restore Home")
			return
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
		"scope": "real Home Fly signal through first post-draw; callbacks and focus safety unchanged; no pilot input or package qualification",
		"cycles": samples,
	}
	app.queue_free()
	await process_frame
	await process_frame
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		_fail("Cannot create report")
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	DirAccess.remove_absolute(prefs_path)
	print("loading probe: %d Home/Fly cycles -> %s" % [cycles, output])
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

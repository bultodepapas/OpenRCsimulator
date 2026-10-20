# Read-only session observer. Production scenes, controls, physics and settings are unchanged.
# Engine callback intervals are not a measurement of display-present latency.
extends Node

var folder := ""
var app: Node
var sim: Node
var frames: FileAccess
var events: FileAccess
var rows := PackedStringArray()
var last_usec := 0
var next_context := 0
var last_flush := 0
var context_id := 0
var last_context: Dictionary = {}
var count := 0
var draws := 0
var previous_observer_usec := 0
var total_observer_usec := 0
var max_observer_usec := 0
var marker_count := 0
var started_usec := 0
var boot_finished_usec := 0
var smoke := false
var ready_written := false


func _ready() -> void:
	folder = OS.get_environment("OPENRC_RECORD_DIR")
	smoke = OS.get_environment("OPENRC_PROFILE_SMOKE") == "1"
	process_priority = 10000
	frames = FileAccess.open(folder.path_join("frames.csv"), FileAccess.WRITE)
	events = FileAccess.open(folder.path_join("events.jsonl"), FileAccess.WRITE)
	if frames == null or events == null:
		push_error("Profiler cannot create output files")
		get_tree().quit(1)
		return
	frames.store_line("engine_usec,interval_usec,engine_delta_usec,context_id,sim_tick,step_smoothed_usec,paused,process_monitor_usec,physics_monitor_usec,nodes,objects,static_bytes,video_bytes,draw_calls,focused,previous_observer_usec")
	started_usec = Time.get_ticks_usec()
	_event("clock_anchor", {unix_s = Time.get_unix_time_from_system(), engine_usec = started_usec,
		gpu_timing_queries = false, scope = "engine callback intervals; no display-present latency; previous_observer_usec belongs to previous callback"})
	RenderingServer.frame_post_draw.connect(_on_draw)
	_boot.call_deferred()


func _boot() -> void:
	var before := Time.get_ticks_usec()
	var scene: PackedScene = load("res://app_root.tscn")
	app = scene.instantiate()
	# No user arguments: the regular saved-preferences Home / Fly route.
	app.set("user_args", PackedStringArray())
	if smoke:
		app.set("preferences_path", folder.path_join("smoke-settings.cfg"))
	get_tree().root.add_child(app)
	get_tree().current_scene = app
	_event("app_ready", {elapsed_usec = Time.get_ticks_usec() - before,
		engine = Engine.get_version_info(), renderer = RenderingServer.get_current_rendering_method(),
		adapter = RenderingServer.get_video_adapter_name(), physics_hz = Engine.physics_ticks_per_second,
		max_fps = Engine.max_fps, vsync = DisplayServer.window_get_vsync_mode(),
		viewport = [get_viewport().size.x, get_viewport().size.y], audio_driver = AudioServer.get_driver_name()})
	last_usec = Time.get_ticks_usec()
	boot_finished_usec = last_usec


func _process(delta: float) -> void:
	if last_usec == 0 or frames == null:
		return
	var begin := Time.get_ticks_usec()
	var interval := begin - last_usec
	last_usec = begin
	if begin >= next_context:
		_refresh_context()
		next_context = begin + 100000
	var tick: int = int(sim.get("tick")) if is_instance_valid(sim) else -1
	var step: float = float(sim.get("step_usec")) if is_instance_valid(sim) else 0.0
	var paused := bool(sim.get("paused")) if is_instance_valid(sim) else true
	rows.append("%d,%d,%d,%d,%d,%.3f,%d,%.3f,%.3f,%d,%d,%d,%d,%d,%d,%d" % [
		begin, interval, int(delta * 1000000.0), context_id, tick, step, int(paused),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000000.0,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(DisplayServer.window_is_focused()), previous_observer_usec])
	count += 1
	if begin - last_flush >= 1000000 or rows.size() >= 4096:
		_flush()
		last_flush = begin
		if not ready_written:
			_write_json("ready.json", {pid = OS.get_process_id(), frames = count, engine_usec = begin})
			ready_written = true
	previous_observer_usec = Time.get_ticks_usec() - begin
	total_observer_usec += previous_observer_usec
	max_observer_usec = maxi(max_observer_usec, previous_observer_usec)
	if smoke and begin - boot_finished_usec > 3000000:
		get_tree().quit()
	# Bounded recorder; reaching the limit never closes the user's game.
	if begin - started_usec > 7200000000:
		_event("recording_limit", {seconds = 7200})
		_flush()
		set_process(false)


func _refresh_context() -> void:
	if not is_instance_valid(app):
		return
	var flight: Node = app.get("flight")
	sim = null
	var context := {screen = "", aircraft = "", camera = "", flight_id = 0,
		paused = true, fault = "", crash = false, input_enabled = false,
		focused = DisplayServer.window_is_focused(), viewport = [get_viewport().size.x, get_viewport().size.y]}
	var stack: RefCounted = app.get("screens")
	var entries: Array = stack.get("_entries")
	var ids := PackedStringArray()
	for entry: Dictionary in entries:
		ids.append(str(entry.id))
	context.screen = "/".join(ids) if not ids.is_empty() else "flight"
	if is_instance_valid(flight):
		context.aircraft = str(flight.get("aircraft_id"))
		context.flight_id = flight.get_instance_id()
		if flight.has_method("_view_name"):
			context.camera = flight.call("_view_name")
		var session: Node = flight.get("session")
		if is_instance_valid(session):
			sim = session.get("sim")
			context.input_enabled = bool(session.get("input_enabled"))
			var crash_state: Dictionary = session.get("crash")
			context.crash = not crash_state.is_empty()
			if is_instance_valid(sim):
				context.paused = bool(sim.get("paused"))
				context.fault = str(sim.get("fault_reason"))
	else:
		var home: Node = app.get("home")
		if is_instance_valid(home):
			context.aircraft = str(home.get("aircraft_id"))
	if context != last_context:
		context_id += 1
		last_context = context
		_event("context", {id = context_id, state = context})


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F12:
		marker_count += 1
		_event("user_marker", {number = marker_count, context_id = context_id})
		print("Performance marker %d recorded" % marker_count)
		# Observe without consuming or remapping any control input.


func _on_draw() -> void:
	draws += 1


func _event(kind: String, detail: Dictionary) -> void:
	if events != null:
		events.store_line(JSON.stringify({engine_usec = Time.get_ticks_usec(), kind = kind, detail = detail}))


func _flush() -> void:
	if frames != null and not rows.is_empty():
		frames.store_string("\n".join(rows) + "\n")
		rows.clear()
		frames.flush()
	if events != null:
		events.flush()


func _write_json(name_: String, data: Dictionary) -> void:
	var file := FileAccess.open(folder.path_join(name_), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t") + "\n")
		file.close()


func _exit_tree() -> void:
	_flush()
	_write_json("observer-finish.json", {normal_observer_teardown = true, frames = count,
		draw_events = draws, markers = marker_count, engine_usec = Time.get_ticks_usec(),
		observer_total_usec = total_observer_usec, observer_max_usec = max_observer_usec})
	if frames != null:
		frames.close()
	if events != null:
		events.close()

extends SceneTree

var samples: Array[Dictionary] = []
var output := ""
var origin := 0
var app: Node
var pause_events: Array[Dictionary] = []
var last_pause := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--frametimes="):
			output = arg.trim_prefix("--frametimes=") + ".monitors.json"
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	_run.call_deferred()

func _run() -> void:
	app = load("res://app_root.tscn").instantiate()
	root.add_child(app)
	origin = Time.get_ticks_usec()
	process_frame.connect(_sample)

func _sample() -> void:
	if samples.size() >= 20000:
		return
	var flight: Node = app.get("flight") if is_instance_valid(app) else null
	var session: Node = flight.get("session") if is_instance_valid(flight) else null
	if is_instance_valid(session) and session.sim.paused != last_pause:
		last_pause = session.sim.paused
		pause_events.append({"elapsed_s": float(Time.get_ticks_usec() - origin) / 1000000.0,
			"paused": last_pause, "tick": session.sim.tick, "holds": session.holds.duplicate(true),
			"crash": session.crash.duplicate(true), "fault": session.sim.fault_reason})
	samples.append({
		"elapsed_s": float(Time.get_ticks_usec() - origin) / 1000000.0,
		"static_memory": Performance.get_monitor(Performance.MEMORY_STATIC),
		"video_memory": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
		"resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphans": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"render_cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),
		"render_gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),
	})

func _finalize() -> void:
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify({"scope": "read-only native observer; render timers exclude scripts/physics", "samples": samples, "pause_events": pause_events}))

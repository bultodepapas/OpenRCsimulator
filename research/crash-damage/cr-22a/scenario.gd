## Production-scene crash capture/qualification. Run with -- --crash-out=<absolute folder>.
extends SceneTree
const RB = preload("res://physics/rigid_body.gd")
const M = preload("res://physics/math3d.gd")
var flight: Node3D
var frames := 0
var out := ""
var name_id := "ugly"
var timings: Array[float] = []
var effects_times: Array[float] = []
var update_times: Array[float] = []
var _clock := 0
var _snapshot: Array = []
var failures: Array[String] = []
var _captures := [16,36,90,240,480]
var _stats: Dictionary = {}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--crash-out="):
			out = arg.trim_prefix("--crash-out=")
		if arg.begins_with("--crash-name="):
			name_id = arg.trim_prefix("--crash-name=")
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280,720)
	if out.is_empty():
		push_error("--crash-out required")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	flight = load("res://main.tscn").instantiate()
	root.add_child(flight)
	flight.session.input_enabled = false
	flight.session.set_physics_process(false)
	flight.session.sim.set_physics_process(false)
	flight._show_perf = false
	flight._inspect = true
	_clock = Time.get_ticks_usec()

func _process(_delta: float) -> bool:
	if flight == null:
		return false
	var now := Time.get_ticks_usec()
	if frames > 20:
		timings.append((now-_clock)/1000.0)
		effects_times.append(float(flight._crash_director.effects.last_update_usec))
		update_times.append(float(flight._crash_director.last_update_usec))
	_clock = now
	frames += 1
	if frames == 12:
		trigger()
	if frames in _captures and DisplayServer.get_name() != "headless":
		capture.call_deferred(frames)
	if frames == 500:
		_stats = flight._crash_director.stats()
		if flight.session.crash.is_empty():
			failures.append("aftermath auto-restarted")
		if _snapshot != observation():
			failures.append("presentation mutated simulation")
		flight.session.hold("crash-probe")
	if frames == 515:
		flight.session.release("crash-probe")
	if frames == 540:
		flight.session.reset()
		if flight._crash_director.active or not flight._airplane.root.visible:
			failures.append("reset did not restore airplane")
		if flight._crash_director.effects.stats().marks != 0:
			failures.append("reset retained marks")
	if frames == 555:
		trigger()
	if frames == 600:
		finish.call_deferred()
	return false

func trigger() -> void:
	var speed := 40.0 if flight.aircraft_id.contains("avanti") else 22.0
	var pitch := -0.95
	var roll := 0.2
	if name_id == "scrape":
		speed = 3.0
		pitch = -0.03
		roll = 0.0
	elif name_id == "wingtip":
		pitch = -0.12
		roll = 1.0
	var att := M.q_from_euler(roll,pitch,0.55)
	flight.session.sim.previous = RB.make_state(M.v3(0,-15,-2.0),M.v3(speed,0,0),att,M.v3(0.4,0.1,0.2))
	flight.session.sim.state = RB.make_state(M.v3(0,-15,0.12),M.v3(speed,0,0),att,M.v3(0.4,0.1,0.2))
	flight.session.sim.set_paused(false)
	flight.session._physics_process(flight.session.sim.dt())
	_snapshot = observation()

func observation() -> Array:
	var sim: Node = flight.session.sim
	return [sim.state.duplicate(),sim.previous.duplicate(),sim.continuous.duplicate(),sim.aux.duplicate(),sim.modes.duplicate(),sim.tick]

func capture(frame: int) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("%s-%03d.png" % [name_id,frame]))

func percentile(values: Array[float], p: float) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[mini(sorted.size()-1,int(ceil(sorted.size()*p))-1)] if not sorted.is_empty() else 0.0

func finish() -> void:
	var result := {case=name_id, aircraft=flight.aircraft_id, godot=Engine.get_version_info().string, adapter=RenderingServer.get_video_adapter_name(), renderer=RenderingServer.get_current_rendering_method(), frames=timings.size(),frame_ms_p50=percentile(timings,0.5),frame_ms_p95=percentile(timings,0.95),frame_ms_p99=percentile(timings,0.99),effects_us_p95=percentile(effects_times,0.95),update_us_p95=percentile(update_times,0.95),stats=_stats,failures=failures, note="Manufactured descending interval through production detector; fixed 60 FPS simulation, measured native frame wall intervals; not a physical drop validation."}
	FileAccess.open(out.path_join(name_id+".json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	flight.free()
	await process_frame
	print(JSON.stringify(result))
	quit(1 if not failures.is_empty() else 0)

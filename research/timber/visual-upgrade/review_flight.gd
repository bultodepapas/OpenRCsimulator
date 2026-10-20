## TT-20 native review of production flight, ground motion and flown crash aftermath.
## This fixture supplies a fixed input tape; presentation is checked for state writes.
extends SceneTree
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

var _out := ""
var _case := "takeoff"
var _flight: Node3D
var _records: Array = []
var _failures: Array[String] = []

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--review-out="): _out = arg.trim_prefix("--review-out=")
		if arg.begins_with("--review-case="): _case = arg.trim_prefix("--review-case=")
	_run.call_deferred()

func _snapshot() -> Array:
	var sim: Node = _flight.session.sim
	return [sim.state.duplicate(), sim.previous.duplicate(), sim.continuous.duplicate(),
		sim.aux.duplicate(), sim.modes.duplicate(), sim.tick]

func _run() -> void:
	if _out.is_empty() or DirAccess.dir_exists_absolute(_out):
		push_error("Pass a new --review-out directory")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = Vector2i(1600, 1000)
	Engine.max_fps = 60
	_flight = load("res://main.tscn").instantiate()
	_flight.accident_archive_path = _out.path_join("fixture-incident.json")
	root.add_child(_flight)
	_flight.set_process(false)
	var session: Node = _flight.session
	session.set_physics_process(false)
	session.sim.set_physics_process(false)
	session.input_enabled = true
	session.read_raw = func() -> Dictionary:
		var speed := float(session.sim.state[RB.VEL])
		var time_s := float(session.sim.time())
		return {roll = 0.0, pitch = 0.12 if speed >= 8.0 else 0.0,
			yaw = 0.12 if time_s > 1.0 and time_s < 2.0 else 0.0,
			throttle = 0.22 if time_s < 3.0 else 1.0}
	if _case == "crash":
		session.input_enabled = false
		var state := RB.make_state(M.v3(-25, -15, -5), M.v3(22, 0, 0),
			M.q_from_euler(0.2, -0.95, 0.55), M.v3(0.4, 0.1, 0.2))
		session.sim.state = state
		session.sim.previous = state.duplicate()
		session.sim.set_paused(false)
	_flight._panel.visible = false
	_flight._hud.visible = false
	_flight._show_perf = false
	_flight._rig.set_view("closeup")
	var motion: Node = _flight._airplane.root.get_node_or_null("TimberVisualMotion")
	var crash_frame := -1
	for frame in 660:
		for tick in 4:
			if not session.sim.paused:
				session._physics_process(session.sim.dt())
				session.sim.step()
				session._physics_process(session.sim.dt())
		if not session.crash.is_empty() and crash_frame < 0:
			crash_frame = frame
		var before := _snapshot()
		_flight._process(1.0 / 60.0)
		_flight._panel.visible = false
		_flight._hud.visible = false
		if _case != "crash" or crash_frame < 0:
			var plane: Node3D = _flight._airplane.root
			_flight._camera.fov = 39.0
			_flight._camera.near = 0.02
			_flight._camera.look_at_from_position(plane.to_global(Vector3(-1.65, 0.60, -1.65)),
				plane.to_global(Vector3(0, 0, 0.23)), Vector3.UP)
		elif frame > crash_frame + 15:
			_flight._accident_report.suspend(true)
			var wreck: Node = _flight._crash_director.wreck
			if is_instance_valid(wreck._core_body):
				var target: Vector3 = wreck._core_body.global_position
				_flight._camera.fov = 40
				_flight._camera.look_at_from_position(target + Vector3(-2.2, 1.2, -2.2), target + Vector3(0, 0.08, 0))
		await process_frame
		if before != _snapshot():
			_failures.append("renderer changed flight state at frame %d" % frame)
			break
		var capture := frame in [0, 120, 240, 360, 540, 659] if _case != "crash" else frame - crash_frame in [10, 30, 90, 300, 600] and crash_frame >= 0
		if capture:
			await RenderingServer.frame_post_draw
			var path := _out.path_join("%s-%03d.png" % [_case, frame])
			root.get_texture().get_image().save_png(path)
			_records.append({image = path.get_file(), tick = session.sim.tick, state = Array(session.sim.state),
				compressions = Array(session.gear_compressions(session.sim.state)), crash = not session.crash.is_empty(),
				motion_attached = motion != null, draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				camera = str(_flight._camera.transform)})
	if _case == "crash" and crash_frame < 0: _failures.append("flown crash did not occur")
	if _case == "takeoff" and not session.crash.is_empty(): _failures.append("takeoff tape crashed")
	var report := {case = _case, failures = _failures, records = _records,
		adapter = RenderingServer.get_video_adapter_name(), renderer = RenderingServer.get_current_rendering_method(),
		crash = _flight._crash_director.stats() if crash_frame >= 0 else {}}
	FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t") + "\n")
	_flight.free()
	await process_frame
	print("TT-20 production review: %s, %d captures, %d failures" % [_case, _records.size(), _failures.size()])
	quit(0 if _failures.is_empty() else 1)

extends SceneTree
const RB = preload("res://physics/rigid_body.gd")
const M = preload("res://physics/math3d.gd")
var flight: Node3D
var out := ""
var results: Array = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	_run.call_deferred()

func _run() -> void:
	Engine.max_fps = 60
	root.size = Vector2i(1280, 720)
	var load_clock := Time.get_ticks_usec()
	flight = load("res://main.tscn").instantiate()
	root.add_child(flight)
	flight.session.input_enabled = false
	if OS.get_cmdline_user_args().has("--no-ui"):
		root.canvas_cull_mask = 0
	flight.session.set_physics_process(false)
	flight.session.sim.set_physics_process(false)
	var setup_us := Time.get_ticks_usec() - load_clock
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
	var first_draw_us := Time.get_ticks_usec() - load_clock
	if OS.get_cmdline_user_args().has("--hide-effects"):
		flight._crash_director.effects.hide()
	if OS.get_cmdline_user_args().has("--hide-wreck"):
		flight._crash_director.wreck.hide()
	for run in 2:
		flight._airplane.root.set_meta("scuff_samples", [])
		for i in 90: await process_frame
		var state: PackedFloat64Array = flight.session.sim.state.duplicate()
		var att := M.q_from_euler(0.2, -0.95, 0.55)
		for i in 4: state[RB.ATT + i] = att[i]
		state[RB.POS] = -25.0
		state[RB.POS+1] = -15.0
		var deepest := -INF
		var hull: PackedFloat64Array = flight.session.aircraft.model.crash_hull
		for i in range(0, hull.size(), 3):
			deepest = maxf(deepest, M.q_rotate(att, hull.slice(i, i+3))[2])
		state[RB.POS+2] = -deepest + 0.001
		var velocity := M.q_rotate(M.q_conj(att), PackedFloat64Array([12.0, 0.0, 25.0]))
		for i in 3:
			state[RB.VEL+i] = velocity[i]
			state[RB.RATE+i] = 0.0
		flight.session.sim.state = state.duplicate()
		flight.session.sim.state[RB.POS+2] -= 5.0
		flight.session.sim.previous = flight.session.sim.state.duplicate()
		for i in 90: await process_frame
		var flown := OS.get_cmdline_user_args().has("--flown")
		if not flown:
			flight.session.sim.state = state
			flight.session.sim.previous = state.duplicate()
			flight.session.sim.previous[RB.POS+2] -= 0.02
		flight.session.sim.set_paused(false)
		var began := Time.get_ticks_usec()
		if flown:
			flight.session.set_physics_process(true)
			flight.session.sim.set_physics_process(true)
		else:
			flight.session._physics_process(flight.session.sim.dt())
		var detect_us := Time.get_ticks_usec() - began
		var checkpoint: Dictionary = {} if flown else flight.session.sim.checkpoint()
		var impact_frame := -1
		var intervals: Array = []
		var main_times: Array = []
		var stamp := began
		for i in 90:
			await process_frame
			var now := Time.get_ticks_usec()
			intervals.append((now - stamp) / 1000.0)
			main_times.append(flight.get_meta("process_us", 0))
			if impact_frame < 0 and not flight.session.crash.is_empty():
				impact_frame = i
				if flown: checkpoint = flight.session.sim.checkpoint()
			stamp = now
		var director: Node = flight._crash_director
		results.append({run=run, aircraft=flight.aircraft_id, detect_us=detect_us,
			impact_us=director.impact_usec, warmup=director.stats().get("shader_warmup", {}), stages=director.get_meta("profile", {}), frames_ms=intervals,
			setup_us=setup_us, first_draw_us=first_draw_us,
			main_us=main_times, impact_frame=impact_frame, flown=flown, state=Array(flight.session.sim.state), active=director.active, class_level=director.report.get("class", -1),
			unchanged=checkpoint == flight.session.sim.checkpoint(), scuff_us=flight._airplane.root.get_meta("scuff_samples", []), stats=director.stats()})
		flight.session.reset()
		flight.session.set_physics_process(false)
		flight.session.sim.set_physics_process(false)
	FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify({adapter=RenderingServer.get_video_adapter_name(), results=results}, "\t"))
	flight.free()
	await process_frame
	quit()

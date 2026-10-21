## TT-20 native review of production flight, ground motion and flown crash aftermath.
## This fixture supplies a fixed input tape; presentation is checked for state writes.
extends SceneTree
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

var _out := ""
var _case := "takeoff"
var _record_frames := false
var _review_cost_report := false
var _frames := 660
var _crash_speed := 22.0
var _flight: Node3D
var _records: Array = []
var _failures: Array[String] = []

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--review-out="): _out = arg.trim_prefix("--review-out=")
		if arg.begins_with("--review-case="): _case = arg.trim_prefix("--review-case=")
		if arg == "--review-record": _record_frames = true
		if arg == "--review-cost-report": _review_cost_report = true
		if arg.begins_with("--review-frames="): _frames = int(arg.trim_prefix("--review-frames="))
		if arg.begins_with("--review-crash-speed="): _crash_speed = float(arg.trim_prefix("--review-crash-speed="))
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
	if _record_frames:
		DirAccess.make_dir_recursive_absolute(_out.path_join("frames"))
	root.size = Vector2i(1600, 1000)
	Engine.max_fps = 60
	_flight = load("res://main.tscn").instantiate()
	_flight.accident_archive_path = _out.path_join("fixture-incident.json")
	root.add_child(_flight)
	_flight.set_process(false)
	var session: Node = _flight.session
	session.set_physics_process(false)
	session.sim.set_physics_process(false)
	# Use the fixed fixture tape even when the host has a physical controller plugged in.
	session.radio.disconnect_device()
	# Late native hotplug announcements must not replace the fixture tape or trip focus failsafe.
	session.external_controller_selection = true
	session.set_process_input(false)
	_flight.set_process_unhandled_input(false)
	session.input_enabled = true
	session.read_raw = func() -> Dictionary:
		var speed := float(session.sim.state[RB.VEL])
		var time_s := float(session.sim.time())
		return {roll = 0.0, pitch = 0.12 if speed >= 8.0 else 0.0,
			yaw = 0.12 if time_s > 1.0 and time_s < 2.0 else 0.0,
			throttle = 0.22 if time_s < 3.0 else 1.0}
	if _case == "crash":
		session.input_enabled = false
		var state := RB.make_state(M.v3(-25, -15, -5), M.v3(_crash_speed, 0, 0),
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
	var initial_down: float = session.sim.state[RB.POS + 2]
	var airborne := false
	var fixture_focus_resumes := 0
	for frame in _frames:
		# Native capture windows can lose focus to another review. Only this deterministic
		# fixture resumes that empty-reason hold; production focus/pause policy is unchanged.
		if session.sim.paused and session.crash.is_empty() and session.sim.fault_reason.is_empty() \
				and session.holds.is_empty() and session.pause_reason.is_empty():
			session.sim.set_paused(false)
			fixture_focus_resumes += 1
		for tick in 4:
			if not session.sim.paused:
				session._physics_process(session.sim.dt())
				session.sim.step()
				session._physics_process(session.sim.dt())
		if not session.crash.is_empty() and crash_frame < 0:
			crash_frame = frame
		if session.sim.state[RB.POS + 2] < initial_down - 0.2:
			airborne = true
		var before := _snapshot()
		_flight._process(1.0 / 60.0)
		_flight._panel.visible = false
		_flight._hud.visible = false
		# The report is reviewed separately, including its real calculated amounts.
		_flight._accident_report.suspend(true)
		if _case != "crash" or crash_frame < 0:
			var plane: Node3D = _flight._airplane.root
			_flight._camera.fov = 39.0
			_flight._camera.near = 0.02
			_flight._camera.look_at_from_position(plane.to_global(Vector3(-1.65, 0.60, -1.65)),
				plane.to_global(Vector3(0, 0, 0.23)), Vector3.UP)
		elif frame > crash_frame + 15:
			var wreck: Node = _flight._crash_director.wreck
			if is_instance_valid(wreck._core_body):
				var target: Vector3 = wreck._core_body.global_position
				_flight._camera.fov = 40
				_flight._camera.look_at_from_position(target + Vector3(-2.2, 1.2, -2.2), target + Vector3(0, 0.08, 0))
		await process_frame
		if before != _snapshot():
			_failures.append("renderer changed flight state at frame %d" % frame)
			break
		if _record_frames and frame % 2 == 0:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_jpg(_out.path_join("frames/%04d.jpg" % (frame / 2)), 0.90)
		var capture := frame in [0, 120, 240, 360, 540, 659] if _case != "crash" else frame == 0 or (frame - crash_frame in [10, 30, 90, 300, 600] and crash_frame >= 0)
		if capture:
			await RenderingServer.frame_post_draw
			var path := _out.path_join("%s-%03d.png" % [_case, frame])
			root.get_texture().get_image().save_png(path)
			_records.append({image = path.get_file(), tick = session.sim.tick, state = Array(session.sim.state),
				paused = session.sim.paused, fault = session.sim.fault_reason, holds = session.holds.duplicate(),
				pause_reason = session.pause_reason, commands = session.commands.duplicate(),
				compressions = Array(session.gear_compressions(session.sim.state)), crash = not session.crash.is_empty(),
				motion_attached = motion != null, draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				camera = str(_flight._camera.transform)})
			FileAccess.open(_out.path_join("progress.json"), FileAccess.WRITE).store_string(JSON.stringify(_records[-1], "\t") + "\n")
			if not str(session.sim.fault_reason).is_empty():
				_failures.append("simulation fault: " + session.sim.fault_reason)
				break
	if not str(session.sim.fault_reason).is_empty() and not _failures.has("simulation fault: " + session.sim.fault_reason):
		_failures.append("simulation fault: " + session.sim.fault_reason)
	if _case == "crash" and crash_frame < 0: _failures.append("flown crash did not occur")
	if _case == "takeoff" and not session.crash.is_empty(): _failures.append("takeoff tape crashed")
	if _case == "takeoff" and not airborne: _failures.append("takeoff tape did not become airborne")
	var cost_report_capture := {enabled = _review_cost_report}
	if _review_cost_report:
		cost_report_capture = await _capture_cost_report()
	var report := {case = _case, failures = _failures, records = _records,
		fixture_crash_initial_speed_mps = _crash_speed if _case == "crash" else 0.0,
		final_tick = session.sim.tick, final_state = Array(session.sim.state),
		final_fault = session.sim.fault_reason, final_pause_reason = session.pause_reason, final_holds = session.holds,
		fixture_focus_resumes = fixture_focus_resumes,
		asset_sha256 = FileAccess.get_sha256("res://assets/aircraft/turbo-lumber-evolution/timber.glb"),
		visual_details_sha256 = FileAccess.get_sha256("res://aircraft/timber_visual_details.gd"),
		visual_detail_data_sha256 = FileAccess.get_sha256("res://assets/aircraft/turbo-lumber-evolution/visual-upgrade/visual_detail_data.gd"),
		visual_motion_sha256 = FileAccess.get_sha256("res://aircraft/timber_visual_motion.gd"),
		visual_lighting_sha256 = FileAccess.get_sha256("res://aircraft/timber_visual_lighting.gd"),
		adapter = RenderingServer.get_video_adapter_name(), renderer = RenderingServer.get_current_rendering_method(),
		crash = _flight._crash_director.stats() if crash_frame >= 0 else {}}
	if _review_cost_report:
		report["cost_report_capture"] = cost_report_capture
	# Like the loading probe, observe mixer release outside the review/timing window.
	# One rendered frame is not necessarily one audio mix callback on a fast host.
	var playbacks: Array[WeakRef] = []
	_collect_audio_playbacks(_flight, playbacks)
	_flight.queue_free()
	_flight = null
	var cleanup_started := Time.get_ticks_usec()
	await process_frame
	await process_frame
	var remaining := _remaining_audio_playbacks(playbacks)
	while remaining > 0 and Time.get_ticks_usec() - cleanup_started < 1000000:
		await process_frame
		remaining = _remaining_audio_playbacks(playbacks)
	report.fixture_shutdown = {tracked_playbacks = playbacks.size(), remaining_playbacks = remaining,
		elapsed_usec = Time.get_ticks_usec() - cleanup_started, timeout_usec = 1000000}
	if remaining > 0:
		_failures.append("review audio teardown did not drain within one second")
	FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t") + "\n")
	print("TT-20 production review: %s, %d captures, %d failures" % [_case, _records.size(), _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _capture_cost_report() -> Dictionary:
	if _case != "crash" or _flight._accident_incident == null or _flight._accident_report == null:
		_failures.append("cost-report capture requires the production crash incident and report UI")
		return {enabled = true, ok = false, reason = "production report unavailable"}
	var incident: RefCounted = _flight._accident_incident
	var report_copy: Dictionary = incident.report.duplicate(true)
	if str(_flight.aircraft_id) == "turbo-lumber-evolution" \
		and (incident.dossier.is_empty() or not report_copy.get("ok", false) or report_copy.get("lines", []).is_empty()):
		_failures.append("Turbo Lumber cost-report capture requires a successful incident report, validated dossier and assessed parts")
		return {enabled = true, ok = false, reason = "Turbo Lumber valuation unavailable or assessed parts empty",
			dossier_nonempty = not incident.dossier.is_empty(), report_ok = report_copy.get("ok", false),
			line_count = report_copy.get("lines", []).size()}
	if report_copy.is_empty():
		_failures.append("cost-report capture has no production incident report")
		return {enabled = true, ok = false, reason = "incident report empty"}
	var ledger_before := _ledger_snapshot(incident)
	var physics_before := _snapshot()
	var ui: CanvasLayer = _flight._accident_report
	ui.suspend(false)
	ui.show_assessment(report_copy, true)
	if not ui._expanded and not ui.controller_action("details"):
		_failures.append("cost-report breakdown could not be expanded")
	for _layout_frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var png_path := _out.path_join("crash-cost-report.png")
	var image_error: Error = image.save_png(png_path)
	if image_error != OK:
		_failures.append("cost-report screenshot save failed: %s" % error_string(image_error))
	var json_path := _out.path_join("incident-report.json")
	var file := FileAccess.open(json_path, FileAccess.WRITE)
	var json_error: Error = ERR_CANT_CREATE if file == null else OK
	if file != null:
		file.store_string(JSON.stringify(report_copy, "\t", true, true) + "\n")
		file.flush()
		json_error = file.get_error()
		file.close()
	if json_error != OK:
		_failures.append("incident report save failed: %s" % error_string(json_error))
	var ledger_unchanged: bool = ledger_before == _ledger_snapshot(incident)
	var physics_unchanged: bool = physics_before == _snapshot()
	var ui_matches_report: bool = ui._report == report_copy
	if not ledger_unchanged:
		_failures.append("showing the cost report changed the production incident ledger")
	if not physics_unchanged:
		_failures.append("showing the cost report changed the physics snapshot")
	if not ui_matches_report:
		_failures.append("cost-report UI did not retain the copied production report")
	return {enabled = true, ok = image_error == OK and json_error == OK and ledger_unchanged
		and physics_unchanged and ui_matches_report, screenshot = png_path, incident_report = json_path,
		ledger_unchanged = ledger_unchanged, physics_unchanged = physics_unchanged,
		ui_matches_report = ui_matches_report, report_format = report_copy.get("format", ""),
		known_subtotal_minor = report_copy.get("known_subtotal_minor"), total_minor = report_copy.get("total_minor"),
		complete = report_copy.get("complete"), line_count = report_copy.get("lines", []).size()}

func _ledger_snapshot(incident: RefCounted) -> Dictionary:
	return {report = incident.report.duplicate(true), assessment = incident._assessment.duplicate(true),
		journal = incident.journal.duplicate(true), confirmed_facts = incident._confirmed_facts.duplicate(true),
		revision = incident._revision, pending = incident._pending}

func _collect_audio_playbacks(node: Node, refs: Array[WeakRef]) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		if node.has_stream_playback():
			refs.append(weakref(node.get_stream_playback()))
	for child in node.get_children():
		_collect_audio_playbacks(child, refs)

func _remaining_audio_playbacks(refs: Array[WeakRef]) -> int:
	var remaining := 0
	for ref in refs:
		if ref.get_ref() != null:
			remaining += 1
	return remaining

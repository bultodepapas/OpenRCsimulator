## Native stock smoke review: actual flight, eight 240 Hz ticks per rendered frame.
extends SceneTree

const World := preload("res://render/world/world.gd")
var flight: Node
var out := ""
var aircraft_id := "sebart-avanti-s-a200-p100rx"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
		if arg.begins_with("--aircraft="): aircraft_id = arg.trim_prefix("--aircraft=")
	if out.is_empty():
		printerr("Pass --out=<fresh absolute directory>")
		quit(1)
		return
	_run.call_deferred()

func _run() -> void:
	if not out.is_absolute_path() or DirAccess.dir_exists_absolute(out):
		printerr("Capture output must be a fresh absolute directory")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	flight = load("res://main.tscn").instantiate()
	flight.aircraft_id = aircraft_id
	flight.interactive_start = true
	flight.external_controller_selection = true
	flight.start_choice = "airborne_half_power"
	flight.crash_effects_enabled = false
	flight.accident_reports_enabled = false
	flight.set_user_args(PackedStringArray(["--soundscape=off", "--scenery=off", "--birds=off", "--companions=0"]))
	root.add_child(flight)
	if flight._profile_smoke == null or not flight.startup_error.is_empty():
		printerr("Stock smoke unavailable for ", aircraft_id, ": ", flight.startup_error)
		quit(1)
		return
	flight.set_process(false)
	flight.set_process_unhandled_input(false)
	flight.session.set_physics_process(false)
	flight.session.sim.set_physics_process(false)
	flight.session.input_enabled = false
	flight.session.crash_auto_restart = false
	flight.session.sim.process_mode = Node.PROCESS_MODE_DISABLED
	flight.session.reset()
	flight.session.sim.set_paused(false)
	flight.set_overlays_visible(false)
	await process_frame
	flight._smoke_key_on = true
	for frame in 120:
		await _frame()
		if frame == 29: await _capture("tailpipe-close", true)
	await _capture("flight-trail", false)
	var on_evidence: Dictionary = flight._smoke_evidence()
	flight._smoke_key_on = false
	for frame in 15: await _frame()
	await _capture("off-residual", false)
	# All admitted show lifetimes expire. Ordinary engine exhaust may continue.
	for frame in 255: await _frame()
	await _capture("off-expired", false)
	var report := {aircraft_id = aircraft_id, engine = Engine.get_version_info(), renderer = RenderingServer.get_video_adapter_name(),
		scope = "Actual 240 Hz trimmed flight, presented at 30 Hz; camera framing only is scripted. OFF expires requested show smoke; ordinary exhaust still follows its running engine.",
		tick = flight.session.sim.tick, fault = flight.session.sim.fault_reason,
		crash = flight.session.crash, smoke_on = on_evidence, smoke = flight._smoke_evidence(),
		source_sha256 = {}, captures_sha256 = {}}
	for path: String in ["res://main.gd", "res://render/smoke/stock_profile.gd", "res://render/smoke/profile_smoke.gd",
			"res://render/smoke/profile_process.gdshader", "res://data/aircraft_customization.json", get_script().resource_path]:
		report.source_sha256[path] = FileAccess.get_sha256(path)
	for label in ["tailpipe-close", "flight-trail", "off-residual", "off-expired"]:
		report.captures_sha256[label + ".png"] = FileAccess.get_sha256(out.path_join(label + ".png"))
	var file := FileAccess.open(out.path_join("capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("Stock smoke capture complete: ", out)
	var result := 0 if flight.session.sim.fault_reason.is_empty() and flight.session.crash.is_empty() else 1
	flight.queue_free()
	await process_frame
	quit(result)

func _frame() -> void:
	# This manual accepted-tick capture owns its clock. Window focus must not
	# pause smoke while synchronous physics ticks continue behind the still plume.
	if flight.session.sim.fault_reason.is_empty() and flight.session.crash.is_empty():
		flight.session.sim.set_paused(false)
	for tick in 8: flight.session.sim.step()
	var pose: Dictionary = flight._pose_of(flight.session.sim.state)
	flight._render_pose(pose, flight.session.surfaces(), 0.0)
	_camera(false)
	flight._update_smoke()
	World.update(flight._env, flight.session.sim.time(), flight._render_wind(flight.session.sim.time()), pose.pos, flight._camera)
	await process_frame
	await RenderingServer.frame_post_draw

func _camera(close: bool) -> void:
	var model: Node3D = flight._airplane.root
	var p := model.global_position
	var b := model.global_basis
	flight._camera.global_position = p + b.x * (4.0 if close else 30.0) + Vector3.UP * (1.8 if close else 10.0) + b.z * (5.0 if close else 36.0)
	flight._camera.look_at(p + b.z * (1.0 if close else 14.0), Vector3.UP)
	flight._camera.fov = 45.0

func _capture(label: String, close: bool) -> void:
	_camera(close)
	# Drain the final manual process request on Compatibility before a still
	# readback; no new presentation time or particle request is submitted here.
	for draw in 8:
		await process_frame
		await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(out.path_join(label + ".png"))
	if error != OK: push_error("Could not save capture " + label)

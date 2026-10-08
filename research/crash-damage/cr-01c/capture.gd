# Manufactured crash intervals in the production flight scene. Run under Xvfb, not headless.
extends SceneTree
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
const Frames = preload("res://render/frames.gd")
var _out: String = ""
var _records: Array = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cr01c-out="):
			_out = arg.trim_prefix("--cr01c-out=")
	if _out.is_empty():
		printerr("--cr01c-out=<directory> required")
		quit(1)
		return
	_run.call_deferred()

func _xyz(v: Vector3) -> Array:
	return [v.x,v.y,v.z]

func _run() -> void:
	root.size = Vector2i(960,540)
	DirAccess.make_dir_recursive_absolute(_out)
	var flight: Node = load("res://main.tscn").instantiate()
	root.add_child(flight)
	flight.set_process(false)
	flight.session.set_physics_process(false)
	flight.session.sim.set_physics_process(false)
	flight.session.input_enabled = false
	flight._panel.visible = false # paired images isolate the pose, not text layout
	flight._hud.visible = false
	flight._show_perf = false
	for fixture in ["banked", "level"]:
		flight.session.reset()
		var q: PackedFloat64Array = M.q_from_euler(0,0,deg_to_rad(35)) if fixture == "banked" else M.q_identity()
		var previous: PackedFloat64Array = RB.make_state(M.v3(0,-15,-1.2),M.v3(10,0,3),q,M.v3(0,0,0))
		var detected: PackedFloat64Array = previous.duplicate()
		detected[RB.POS+2] = .15
		flight.session.sim.previous = previous
		flight.session.sim.state = detected
		flight.session.sim.tick = 12
		flight.session.sim.set_paused(false)
		flight.session._physics_process(flight.session.sim.dt())
		var hit: RefCounted = flight.session.crash.impact
		if hit.crossing == null or not hit.crossing.available:
			printerr("fixture did not reconstruct a crossing")
			quit(1)
			return
		flight._inspect = true
		flight._process(1.0/60.0)
		var fixed_camera: Transform3D = flight._camera.transform
		var fixed_fov: float = flight._camera.fov
		await _save(flight,fixture+"-crossing",hit)
		# Controlled reference: draw the detected tick using the same camera and scene.
		flight._render_pose(flight._pose_of(detected),flight.session.surfaces(),flight._prop_angle)
		flight._camera.transform = fixed_camera
		flight._camera.fov = fixed_fov
		await _save(flight,fixture+"-detected-reference",hit)
		if fixture == "banked":
			flight._inspect = false
			flight._process(1.0/60.0)
			await _save(flight,"banked-pilot-crossing",hit)
		if flight.session.sim.state != detected or flight.session.sim.previous != previous or flight.session.sim.tick != 12:
			printerr("capture mutated simulation")
			quit(1)
			return
	var file: FileAccess = FileAccess.open(_out.path_join("captures.json"),FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify({format="openrc-cr01c-captures v1",records=_records},"\t",true,true)+"\n")
	file.close()
	flight.queue_free()
	await process_frame
	quit()

func _save(flight: Node, name: String, hit: RefCounted) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path: String = _out.path_join(name+".png")
	var img: Image = root.get_texture().get_image()
	if img.save_png(path) != OK:
		printerr("cannot save "+path)
		quit(1)
		return
	var index: int = hit.crossing.point_index
	var r: PackedFloat64Array = flight.session.aircraft.model.crash_hull.slice(index*3,index*3+3)
	var contact: Vector3 = flight._airplane.root.transform * (flight._cg_model+Vector3(r[1],-r[2],-r[0]))
	_records.append({name=name,image_sha256=FileAccess.get_sha256(path),size=[img.get_width(),img.get_height()],
		crossing_fraction=hit.crossing.fraction,hull_index=index,rendered_contact=_xyz(contact),
		rendered_cg=_xyz(flight._last_render_pose.pos),camera_position=_xyz(flight._camera.position),
		camera_basis=[_xyz(flight._camera.basis.x),_xyz(flight._camera.basis.y),_xyz(flight._camera.basis.z)],
		camera_fov=flight._camera.fov,detected_state=Array(hit.detected_state),
		crossing_position_ned=Array(hit.crossing.position_ned),crossing_attitude=Array(hit.crossing.attitude)})
	print("saved ",path," contact height ",contact.y)

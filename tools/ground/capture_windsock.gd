extends SceneTree
const Field = preload("res://render/field.gd")
const Loader = preload("res://data/field_loader.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const Clock = preload("res://render/shader_clock.gd")
var out: String = ""
var scenery_on: bool = false
var world: Node3D
var camera: Camera3D

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg == "--scenery=on":
			scenery_on = true
	_run.call_deferred()

func _run() -> void:
	if out.is_empty():
		push_error("--out required")
		quit(1)
		return
	out = ProjectSettings.globalize_path(out)
	if DirAccess.make_dir_recursive_absolute(out) != OK:
		push_error("cannot create output")
		quit(1)
		return
	var directory: DirAccess = DirAccess.open(out)
	if directory == null or not directory.get_files().is_empty() or not directory.get_directories().is_empty():
		push_error("output must be empty")
		quit(1)
		return
	OS.set_environment("OPENRC_SCENERY", "on" if scenery_on else "off")
	OS.set_environment("OPENRC_SCENERY_AUDIO", "off")
	OS.set_environment("OPENRC_SCENERY_BIRDS", "off")
	Clock.register()
	Clock.update(0.0, Vector3.ZERO)
	var loaded: Dictionary = Loader.load_from()
	if not loaded.ok:
		push_error(str(loaded.errors))
		quit(1)
		return
	world = Field.build(loaded.field)
	root.add_child(world)
	var cues: Array = loaded.field.get("flight_cues", [])
	if cues.size() != 1:
		push_error("expected one default flight cue")
		quit(1)
		return
	var cue: Dictionary = cues[0]
	var sock: Node3D = world.get_node_or_null(str(cue.id)) as Node3D
	if sock == null:
		push_error("FieldBuilder did not construct the windsock")
		quit(1)
		return
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Atmosphere.environment()
	world.add_child(environment)
	Atmosphere.create_sun(world)
	camera = Camera3D.new()
	camera.near = 0.1
	camera.far = 21000
	world.add_child(camera)
	camera.current = true
	await process_frame
	Atmosphere.update_clouds(environment.environment,0.0)
	var poses: Array[Dictionary] = [
		{"id":"close", "eye":sock.position+Vector3(5,4,5), "target":sock.position+Vector3(0.5,2.2,0), "fov":40.0},
		{"id":"pilot_turn", "eye":Vector3(0,1.7,0), "target":sock.position+Vector3(.5,2.1,0), "fov":50.0},
		{"id":"overview", "eye":Vector3(14,12,28), "target":Vector3(0,0,-8), "fov":50.0}]
	var records: Array[Dictionary] = []
	for pose: Dictionary in poses:
		camera.position = pose.eye
		camera.look_at(pose.target)
		camera.fov = pose.fov
		for visible_state: bool in [false,true]:
			sock.visible = visible_state
			for frame: int in 2:
				await RenderingServer.frame_post_draw
			var picture: Image = root.get_texture().get_image()
			if picture == null or picture.get_size() != Vector2i(960, 540):
				push_error("invalid capture image")
				quit(1)
				return
			var name: String = "%s-%s.png" % [pose.id,"on" if visible_state else "off"]
			if picture.save_png(out.path_join(name)) != OK:
				push_error("save failed")
				quit(1)
				return
			records.append({"image":name,"sha256":FileAccess.get_sha256(out.path_join(name)),"draws":int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),"primitives":int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)), "bounds":_bounds(sock), "eye":_vec(camera.position), "target":_vec(pose.target), "fov":pose.fov})
	var file: FileAccess = FileAccess.open(out.path_join("capture.json"),FileAccess.WRITE)
	if file == null:
		push_error("cannot write manifest")
		quit(1)
		return
	file.store_string(JSON.stringify({"format":"openrc-l10a-capture v1", "records":records,
		"adapter":RenderingServer.get_video_adapter_name(), "method":RenderingServer.get_current_rendering_method(),
		"driver":RenderingServer.get_current_rendering_driver_name(), "viewport":[960,540],
		"shader_time":Clock.last_clock,"scenery":scenery_on, "cue":cue},"  ")+"\n")
	file.close()
	world.queue_free()
	quit()


func _bounds(sock: Node3D) -> Array[float]:
	var minimum: Vector2 = Vector2(INF, INF)
	var maximum: Vector2 = Vector2(-INF, -INF)
	for child: Node in sock.get_children():
		var mesh: MeshInstance3D = child as MeshInstance3D
		if mesh == null:
			continue
		var box: AABB = mesh.mesh.get_aabb()
		for i: int in 8:
			var point: Vector3 = mesh.global_transform * box.get_endpoint(i)
			var pixel: Vector2 = camera.unproject_position(point)
			minimum = minimum.min(pixel)
			maximum = maximum.max(pixel)
	return [minimum.x, minimum.y, maximum.x, maximum.y]


func _vec(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]

extends SceneTree
const Field = preload("res://render/field.gd")
const Loader = preload("res://data/field_loader.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const Clock = preload("res://render/shader_clock.gd")
var out: String = ""
var scenery_on: bool = false
var cue_type: String = "windsock"
var world: Node3D
var camera: Camera3D

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--cue="):
			cue_type = arg.trim_prefix("--cue=")
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
	var cues: Array = loaded.field.get("flight_cues", []).filter(func(c: Dictionary) -> bool: return c.type == cue_type)
	if cue_type == "contact_shadows":
		cues = [{"id":"FlightCueShadows", "type":"contact_shadows"}]
	if cues.size() != 1:
		push_error("expected one default cue of selected type")
		quit(1)
		return
	var cue: Dictionary = cues[0]
	var sock: Node3D = world.get_node_or_null(str(cue.id)) as Node3D
	if sock == null:
		push_error("FieldBuilder did not construct the requested cue")
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
	if cue_type == "pilot_station":
		var origin: Vector3 = sock.position
		var pilot_eye: Vector3 = origin + Vector3.UP * float(loaded.field.pilot.eye_height)
		poses = [
			{"id":"close", "eye":origin+Vector3(3,2.5,-4), "target":origin+Vector3(0,.35,0), "fov":40.0},
			{"id":"rear", "eye":origin+Vector3(2.5,2.0,3), "target":origin+Vector3(0,.35,0), "fov":40.0},
			{"id":"overview", "eye":origin+Vector3(14,12,28), "target":origin+Vector3(0,0,-8), "fov":50.0}]
		for surface: Dictionary in loaded.field.surfaces:
			if surface.id == loaded.field.runway:
				for side: float in [-1.0, 1.0]:
					poses.append({"id":"pilot_left" if side < 0.0 else "pilot_right", "eye":pilot_eye,
						"target":Vector3(surface.center_east + side * surface.length_east_west * 0.5, 0, -surface.center_north), "fov":50.0})
	if cue_type == "flightline_barrier":
		var origin: Vector3 = sock.position
		poses = [
			{"id":"close", "eye":origin+Vector3(28,10,-38), "target":origin+Vector3(0,.35,0), "fov":50.0},
			{"id":"rear", "eye":origin+Vector3(24,10,38), "target":origin+Vector3(0,.35,0), "fov":50.0},
			{"id":"overview", "eye":Vector3(14,16,42), "target":Vector3(0,0,-8), "fov":50.0}]
		var pilot_eye: Vector3 = Vector3(loaded.field.pilot.east, loaded.field.pilot.eye_height, -loaded.field.pilot.north)
		for surface: Dictionary in loaded.field.surfaces:
			if surface.id == loaded.field.runway:
				for side: float in [-1.0, 1.0]:
					poses.append({"id":"pilot_left" if side < 0.0 else "pilot_right", "eye":pilot_eye,
						"target":Vector3(surface.center_east + side * surface.length_east_west * 0.5, 0, -surface.center_north), "fov":50.0})
	if cue_type == "contact_shadows":
		poses = [
			{"id":"close", "eye":Vector3(-10,1.8,8), "target":Vector3(-12,0,6), "fov":40.0},
			{"id":"station", "eye":Vector3(2,2,3), "target":Vector3.ZERO, "fov":40.0},
			{"id":"barrier", "eye":Vector3(5,1.6,-2.5), "target":Vector3(5,0,-4.5), "fov":40.0}]
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
			records.append({"image":name,"sha256":FileAccess.get_sha256(out.path_join(name)),"draws":int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),"primitives":int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)), "bounds":[] if str(pose.id).begins_with("pilot_") and cue_type in ["pilot_station", "flightline_barrier"] else _bounds(sock), "runway_polygon":_runway_polygon(loaded.field) if cue_type == "flightline_barrier" and str(pose.id).begins_with("pilot_") else [], "eye":_vec(camera.position), "target":_vec(pose.target), "fov":pose.fov})
	var file: FileAccess = FileAccess.open(out.path_join("capture.json"),FileAccess.WRITE)
	if file == null:
		push_error("cannot write manifest")
		quit(1)
		return
	file.store_string(JSON.stringify({"format":"openrc-%s-capture v1" % {"windsock":"l10a", "pilot_station":"l10b", "flightline_barrier":"l10c", "contact_shadows":"l10d"}[cue_type], "records":records,
		"adapter":RenderingServer.get_video_adapter_name(), "method":RenderingServer.get_current_rendering_method(),
		"driver":RenderingServer.get_current_rendering_driver_name(), "viewport":[960,540],
		"shader_time":Clock.last_clock,"scenery":scenery_on, "cue":cue},"  ")+"\n")
	file.close()
	world.queue_free()
	quit()


func _bounds(sock: Node3D) -> Array[float]:
	var minimum: Vector2 = Vector2(INF, INF)
	var maximum: Vector2 = Vector2(-INF, -INF)
	var candidates: Array[Node] = sock.get_children()
	if sock is MeshInstance3D:
		candidates.append(sock)
	for child: Node in candidates:
		var mesh: MeshInstance3D = child as MeshInstance3D
		if mesh == null:
			continue
		var box: AABB = mesh.mesh.get_aabb()
		var local_corners: Array[Vector3] = []
		for i: int in 8:
			local_corners.append(camera.global_transform.affine_inverse() * mesh.global_transform * box.get_endpoint(i))
		var projected: Array[Vector3] = []
		for i: int in 8:
			var a: Vector3 = local_corners[i]
			if a.z <= -camera.near:
				projected.append(a)
			for bit: int in [1,2,4]:
				var b: Vector3 = local_corners[i ^ bit]
				if (a.z <= -camera.near) != (b.z <= -camera.near):
					projected.append(a.lerp(b, (-camera.near - a.z) / (b.z - a.z)))
		for point: Vector3 in projected:
			var pixel: Vector2 = camera.unproject_position(camera.global_transform * point)
			minimum = minimum.min(pixel)
			maximum = maximum.max(pixel)
	return [minimum.x, minimum.y, maximum.x, maximum.y]


func _vec(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _runway_polygon(field: Dictionary) -> Array:
	var polygon: Array[Vector3] = []
	for surface: Dictionary in field.surfaces:
		if surface.id != field.runway:
			continue
		for corner: Vector2 in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
			polygon.append(camera.global_transform.affine_inverse() * Vector3(
				surface.center_east + corner.x * surface.length_east_west * .5,
				0.03, -surface.center_north + corner.y * surface.width_north_south * .5))
	# Clip at the near plane before projecting; the opposite threshold can be behind the eye.
	var clipped: Array[Vector3] = []
	for i: int in polygon.size():
		var a: Vector3 = polygon[i]
		var b: Vector3 = polygon[(i + 1) % polygon.size()]
		var a_inside: bool = a.z <= -camera.near
		var b_inside: bool = b.z <= -camera.near
		if a_inside:
			clipped.append(a)
		if a_inside != b_inside:
			clipped.append(a.lerp(b, (-camera.near - a.z) / (b.z - a.z)))
	var pixels: Array = []
	for point: Vector3 in clipped:
		var pixel: Vector2 = camera.unproject_position(camera.global_transform * point)
		pixels.append([pixel.x, pixel.y])
	return pixels

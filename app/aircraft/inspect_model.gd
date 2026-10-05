extends SceneTree

## Isolated visual inspection harness for the current procedural airplane builder.
## Run from app/ with Godot and pass --output-dir after the `--` separator.

const AirplaneBuilder := preload("res://render/airplane.gd")
const IMAGE_SIZE := Vector2i(1280, 720)
const FLIGHT_FOV_DEG := 50.0
const FLIGHT_DISTANCES_M := [20.0, 50.0, 100.0]
const ORTHO := Camera3D.PROJECTION_ORTHOGONAL

var _world_root: Node3D
var _airplane: Dictionary
var _camera: Camera3D
var _caption_title: Label
var _caption_detail: Label
var _out_dir := ""
var _records: Array[Dictionary] = []
var _run_started_usec := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_run_started_usec = Time.get_ticks_usec()
	_out_dir = _output_directory()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	get_root().size = IMAGE_SIZE
	get_root().title = "Ugly Stik model inspection"

	_world_root = Node3D.new()
	_world_root.name = "InspectionWorld"
	get_root().add_child(_world_root)
	_add_lighting()
	_add_airplane()
	_add_camera()
	_add_caption()

	await process_frame
	await RenderingServer.frame_post_draw

	for capture in _capture_definitions():
		var capture_started_usec := Time.get_ticks_usec()
		_apply_capture(capture)
		await process_frame
		await RenderingServer.frame_post_draw
		var image := get_root().get_texture().get_image()
		var output_path := _out_dir.path_join(String(capture.filename))
		var error := image.save_png(output_path)
		if error != OK:
			push_error("Could not write capture %s (Error %d)" % [output_path, error])
			quit(1)
			return
		var capture_elapsed_ms := float(Time.get_ticks_usec() - capture_started_usec) / 1000.0
		_records.append(_capture_record(capture, output_path, capture_elapsed_ms))
		print("Captured %s" % output_path)

	_write_manifest()
	quit(0)


func _output_directory() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			return ProjectSettings.globalize_path(argument.trim_prefix("--output-dir="))
	return ProjectSettings.globalize_path("res://../research/ugly-stik/model-v1/captures")


func _add_lighting() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#111820")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#b8c3d1")
	env.ambient_light_energy = 0.55
	environment.environment = env
	_world_root.add_child(environment)

	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.rotation_degrees = Vector3(-47.0, -32.0, -9.0)
	key.light_color = Color("#fff3e1")
	key.light_energy = 1.45
	_world_root.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.rotation_degrees = Vector3(-24.0, 145.0, 12.0)
	fill.light_color = Color("#c9d9ff")
	fill.light_energy = 0.35
	_world_root.add_child(fill)


func _add_airplane() -> void:
	_airplane = AirplaneBuilder.build()
	for required_key in ["root", "propeller", "hinges"]:
		if not _airplane.has(required_key):
			push_error("Airplane builder is missing dictionary key '%s'" % required_key)
			quit(1)
			return
	if not (_airplane.root is Node3D and _airplane.propeller is Node3D and _airplane.hinges is Dictionary):
		push_error("Airplane builder returned a wrong type for root, propeller, or hinges")
		quit(1)
		return
	for hinge_name in ["aileron_left", "aileron_right", "elevator", "rudder"]:
		if not _airplane.hinges.has(hinge_name) or not (_airplane.hinges[hinge_name] is Node3D):
			push_error("Airplane builder is missing Node3D hinge '%s'" % hinge_name)
			quit(1)
			return
	_world_root.add_child(_airplane.root)


func _add_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "InspectionCamera"
	_camera.current = true
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.near = 0.02
	_camera.far = 500.0
	_world_root.add_child(_camera)


func _add_caption() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Caption"
	get_root().add_child(layer)

	_caption_title = Label.new()
	_caption_title.position = Vector2(22.0, 18.0)
	_caption_title.add_theme_font_size_override("font_size", 21)
	_caption_title.add_theme_color_override("font_color", Color("#ffffff"))
	layer.add_child(_caption_title)

	_caption_detail = Label.new()
	_caption_detail.position = Vector2(22.0, 47.0)
	_caption_detail.add_theme_font_size_override("font_size", 14)
	_caption_detail.add_theme_color_override("font_color", Color("#d0d8e0"))
	layer.add_child(_caption_detail)


func _capture_definitions() -> Array[Dictionary]:
	var captures: Array[Dictionary] = [
		{
			"filename": "top.png", "title": "PLANTA · NEUTRO",
			"detail": "Ortográfica superior · escala 1:1 relativa · Jensen Ugly Stik 60 / .61",
			"projection": ORTHO, "size": 1.58, "camera": Vector3(0.0, 5.0, 0.0),
			"target": Vector3.ZERO, "up": Vector3(0.0, 0.0, -1.0), "pose": "neutral",
		},
		{
			"filename": "bottom.png", "title": "INTRADÓS · NEUTRO",
			"detail": "Ortográfica inferior · misma geometría y encuadre que la planta",
			"projection": ORTHO, "size": 1.58, "camera": Vector3(0.0, -5.0, 0.0),
			"target": Vector3.ZERO, "up": Vector3(0.0, 0.0, -1.0), "pose": "neutral",
		},
		{
			"filename": "side.png", "title": "PERFIL · NEUTRO",
			"detail": "Ortográfica izquierda · morro hacia la derecha de imagen",
			"projection": ORTHO, "size": 0.92, "camera": Vector3(4.0, 0.0, 0.0),
			"target": Vector3.ZERO, "up": Vector3.UP, "pose": "neutral",
		},
		{
			"filename": "front.png", "title": "FRENTE · NEUTRO",
			"detail": "Ortográfica · desde el morro · envergadura horizontal",
			"projection": ORTHO, "size": 0.92, "camera": Vector3(0.0, 0.0, -4.0),
			"target": Vector3.ZERO, "up": Vector3.UP, "pose": "neutral",
		},
		{
			"filename": "three-quarter-neutral.png", "title": "TRES CUARTOS · NEUTRO",
			"detail": "Perspectiva de inspección · sin deflexiones de mandos",
			"projection": Camera3D.PROJECTION_PERSPECTIVE, "fov": 38.0,
			"camera": Vector3(-2.15, 1.65, 2.75), "target": Vector3.ZERO,
			"up": Vector3.UP, "pose": "neutral",
		},
		{
			"filename": "three-quarter-deflected.png", "title": "TRES CUARTOS · MANDOS DESVIADOS",
			"detail": "Pose demostrativa fija · alerones, elevador y timón articulados",
			"projection": Camera3D.PROJECTION_PERSPECTIVE, "fov": 38.0,
			"camera": Vector3(-2.15, 1.65, 2.75), "target": Vector3.ZERO,
			"up": Vector3.UP, "pose": "deflected",
		},
	]
	for distance in FLIGHT_DISTANCES_M:
		captures.append({
			"filename": "flight-%dm.png" % int(distance),
			"title": "LECTURA EN VUELO · %d m" % int(distance),
			"detail": "1280×720 · FOV vertical 50° · KEEP_HEIGHT · geometría idéntica",
			"projection": Camera3D.PROJECTION_PERSPECTIVE, "fov": FLIGHT_FOV_DEG,
			"camera": Vector3(0.0, 0.0, distance), "target": Vector3.ZERO,
			"up": Vector3.UP, "pose": "neutral", "distance_m": distance,
		})
	return captures


func _apply_capture(capture: Dictionary) -> void:
	_airplane.root.position = Vector3.ZERO
	_airplane.root.rotation = Vector3.ZERO
	_set_pose(String(capture.pose))
	_camera.projection = int(capture.projection)
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.fov = float(capture.get("fov", FLIGHT_FOV_DEG))
	_camera.size = float(capture.get("size", 1.58))
	_camera.position = capture.camera
	_camera.look_at(capture.target, capture.up)
	_camera.force_update_transform()
	_caption_title.text = String(capture.title)
	_caption_detail.text = String(capture.detail)


func _set_pose(pose_name: String) -> void:
	var rotations := {}
	if pose_name == "deflected":
		rotations = {
			"aileron_left": {"x": -0.30, "y": 0.0},
			"aileron_right": {"x": 0.30, "y": 0.0},
			"elevator": {"x": 0.34, "y": 0.0},
			"rudder": {"x": 0.0, "y": 0.30},
		}
	AirplaneBuilder.apply_surfaces(_airplane, rotations)


func _capture_record(capture: Dictionary, output_path: String, capture_elapsed_ms: float) -> Dictionary:
	var bounds := _model_bounds()
	var record := {
		"file": output_path.get_file(),
		"width_px": IMAGE_SIZE.x,
		"height_px": IMAGE_SIZE.y,
		"projection": "orthographic" if int(capture.projection) == Camera3D.PROJECTION_ORTHOGONAL else "perspective",
		"pose": capture.pose,
		"mesh_instances": _mesh_instances().size(),
		"triangle_count": _triangle_count(),
		"material_count": _material_count(),
		"model_bounds_m": bounds,
		"capture_elapsed_ms": capture_elapsed_ms,
		"capture_time_unix": int(Time.get_unix_time_from_system()),
	}
	if capture.has("distance_m"):
		var distance := float(capture.distance_m)
		var vertical_fov := deg_to_rad(FLIGHT_FOV_DEG)
		record["distance_m"] = distance
		record["fov_vertical_deg"] = FLIGHT_FOV_DEG
		record["keep_aspect"] = "KEEP_HEIGHT"
		record["visible_vertical_m"] = 2.0 * distance * tan(vertical_fov / 2.0)
		record["model_x_extent_px"] = float(bounds.extent[0]) * float(IMAGE_SIZE.y) / (2.0 * distance * tan(vertical_fov / 2.0))
	return record


func _mesh_instances() -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for child in _airplane.root.find_children("*", "MeshInstance3D", true, false):
		result.append(child as MeshInstance3D)
	return result


func _triangle_count() -> int:
	var total := 0
	for instance in _mesh_instances():
		if instance.mesh == null:
			continue
		for surface_index in range(instance.mesh.get_surface_count()):
			var arrays := instance.mesh.surface_get_arrays(surface_index)
			var index_data: Variant = arrays[Mesh.ARRAY_INDEX]
			if index_data is PackedInt32Array and not index_data.is_empty():
				total += int(index_data.size() / 3)
			else:
				var vertex_data: Variant = arrays[Mesh.ARRAY_VERTEX]
				if vertex_data is PackedVector3Array:
					total += int(vertex_data.size() / 3)
	return total


func _material_count() -> int:
	var materials: Dictionary = {}
	for instance in _mesh_instances():
		if instance.material_override != null:
			materials[instance.material_override.get_instance_id()] = true
		elif instance.mesh != null:
			for surface_index in range(instance.mesh.get_surface_count()):
				var material := instance.mesh.surface_get_material(surface_index)
				if material != null:
					materials[material.get_instance_id()] = true
	return materials.size()


func _model_bounds() -> Dictionary:
	var min_corner := Vector3(INF, INF, INF)
	var max_corner := Vector3(-INF, -INF, -INF)
	for instance in _mesh_instances():
		if instance.mesh == null:
			continue
		var aabb := instance.get_aabb()
		for x in [aabb.position.x, aabb.end.x]:
			for y in [aabb.position.y, aabb.end.y]:
				for z in [aabb.position.z, aabb.end.z]:
					var point := instance.global_transform * Vector3(x, y, z)
					min_corner = min_corner.min(point)
					max_corner = max_corner.max(point)
	return {
		"min": [min_corner.x, min_corner.y, min_corner.z],
		"max": [max_corner.x, max_corner.y, max_corner.z],
		"extent": [max_corner.x - min_corner.x, max_corner.y - min_corner.y, max_corner.z - min_corner.z],
	}


func _write_manifest() -> void:
	var manifest := {
		"model": "Jensen Ugly Stik 60 / nitro .61 first",
		"builder": "res://render/airplane.gd",
		"builder_contract": ["root", "propeller", "hinges"],
		"axes": {"forward": "-Z", "right": "+X", "up": "+Y"},
		"resolution_px": [IMAGE_SIZE.x, IMAGE_SIZE.y],
		"flight_camera": {"fov_vertical_deg": FLIGHT_FOV_DEG, "keep_aspect": "KEEP_HEIGHT"},
		"total_elapsed_ms": float(Time.get_ticks_usec() - _run_started_usec) / 1000.0,
		"captures": _records,
	}
	var file := FileAccess.open(_out_dir.path_join("manifest.json"), FileAccess.WRITE)
	if file == null:
		push_error("Could not open output manifest in %s" % _out_dir)
		quit(1)
		return
	file.store_string(JSON.stringify(manifest, "\t") + "\n")
	print("Wrote %s" % _out_dir.path_join("manifest.json"))

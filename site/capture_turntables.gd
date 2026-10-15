# Documentation-only 360-degree studio captures of each distinct catalog model.
# Run with the pinned Godot build and --path app, passing -- --out-dir=<absolute path>.
extends SceneTree

const Builder = preload("res://render/airplane.gd")
const Catalog = preload("res://app_state/aircraft_catalog.gd")

const FRAME_COUNT: int = 36
const FRAME_SIZE: Vector2i = Vector2i(640, 360)
const BACKGROUND: Color = Color("101820")
const AMBIENT_COLOR: Color = Color("c8c8c8")
const AMBIENT_ENERGY: float = 0.45
const CAMERA_FOV_DEGREES: float = 38.0
const CAMERA_ELEVATION_DEGREES: float = 22.0
const CAMERA_DISTANCE_EXTENTS: float = 1.28
const LIGHTS: Array[Dictionary] = [
	{"rotation_degrees": [-47.0, -32.0, -9.0], "energy": 0.90},
	{"rotation_degrees": [-24.0, 145.0, 12.0], "energy": 0.38},
	{"rotation_degrees": [48.0, -28.0, 0.0], "energy": 0.40},
]
const MODELS := [
	{"key": "stik", "id": "jensen-das-ugly-stik-60"},
	{"key": "extra", "id": "gp-extra-300s-60"},
	{"key": "mustang", "id": "p51d-mustang-120"},
	{"key": "jet", "id": "sebart-avanti-s-a200-p100rx"},
	{"key": "timber", "id": "turbo-lumber-evolution"},
	{"key": "heli", "id": "xcell-60-research"},
]

var output: String = ""
var world: Node3D
var camera: Camera3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="):
			output = arg.trim_prefix("--out-dir=")
	if output.is_empty() or DirAccess.make_dir_recursive_absolute(output.path_join("frames")) != OK:
		push_error("Provide a writable absolute --out-dir")
		quit(1)
		return

	root.size = FRAME_SIZE
	world = Node3D.new()
	root.add_child(world)
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = BACKGROUND
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = AMBIENT_COLOR
	environment.ambient_light_energy = AMBIENT_ENERGY
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	environment_node.environment = environment
	world.add_child(environment_node)
	for light_config: Dictionary in LIGHTS:
		_add_light(light_config)

	camera = Camera3D.new()
	camera.fov = CAMERA_FOV_DEGREES
	camera.current = true
	world.add_child(camera)

	var aircraft_manifest: Array[Dictionary] = []
	var total_frames: int = 0
	for model_spec: Dictionary in MODELS:
		var aircraft_id: String = str(model_spec.id)
		var catalog_entry: Dictionary = Catalog.entry(aircraft_id)
		if catalog_entry.is_empty():
			push_error("Turntable ID is absent from the aircraft catalog: " + aircraft_id)
			quit(1)
			return
		var model: Dictionary = Builder.build(aircraft_id)
		var airplane: Node3D = model.get("root") as Node3D
		if model.is_empty() or airplane == null:
			push_error("The catalog model builder failed for: " + aircraft_id)
			quit(1)
			return
		world.add_child(airplane)
		await process_frame
		var bounds: AABB = _bounds(airplane, Transform3D.IDENTITY)
		var center: Vector3 = bounds.get_center()
		var extent: float = maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
		if extent <= 0.0 or bounds.size.length_squared() <= 0.0:
			push_error("The catalog model has no visible mesh bounds: " + aircraft_id)
			quit(1)
			return

		var model_key: String = str(model_spec.key)
		var frame_dir: String = output.path_join("frames").path_join(model_key)
		if DirAccess.make_dir_recursive_absolute(frame_dir) != OK:
			push_error("Cannot create frame directory: " + frame_dir)
			quit(1)
			return
		for frame_index: int in range(FRAME_COUNT):
			var azimuth_degrees: float = 360.0 * float(frame_index) / float(FRAME_COUNT)
			_aim(center, extent, azimuth_degrees)
			var frame_path: String = frame_dir.path_join("%02d.png" % frame_index)
			var saved: bool = await _save(frame_path)
			if not saved:
				quit(1)
				return
			total_frames += 1

		aircraft_manifest.append({
			"key": model_key,
			"id": aircraft_id,
			"name": str(catalog_entry.get("name", model_key)),
			"status": str(catalog_entry.get("status", "")),
			"vehicle": "rotorcraft" if Catalog.is_rotorcraft(aircraft_id) else "airplane",
			"frames": FRAME_COUNT,
			"frame_directory": "frames/" + model_key,
			"bounds": {
				"position": [bounds.position.x, bounds.position.y, bounds.position.z],
				"size": [bounds.size.x, bounds.size.y, bounds.size.z],
			},
		})
		airplane.queue_free()
		await process_frame

	var manifest: Dictionary = {
		"format": "openrc-turntable-capture-v1",
		"purpose": "Studio model presentation; not gameplay or flight validation",
		"engine": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_method(),
		"frame_size": [FRAME_SIZE.x, FRAME_SIZE.y],
		"frame_count_per_model": FRAME_COUNT,
		"total_frame_count": total_frames,
		"background": "#101820",
		"background_mode": "color",
		"ambient_light": {"color": "#c8c8c8", "energy": AMBIENT_ENERGY},
		"camera": {
			"projection": "perspective",
			"fov_degrees": CAMERA_FOV_DEGREES,
			"elevation_degrees": CAMERA_ELEVATION_DEGREES,
			"orbit_axis": "world_y",
			"orbit_start_azimuth_degrees": 0.0,
			"orbit_step_degrees": 10.0,
			"orbit_degrees": 360.0,
			"distance_model_extents": CAMERA_DISTANCE_EXTENTS,
		},
		"lighting": LIGHTS,
		"models": aircraft_manifest,
	}
	var file: FileAccess = FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	if file == null:
		push_error("Cannot write turntable capture manifest")
		quit(1)
		return
	file.store_string(JSON.stringify(manifest, "\t") + "\n")
	file.close()
	print("TURNTABLE_CAPTURE_OK: %d models, %d full-orbit frames" % [aircraft_manifest.size(), total_frames])
	quit(0)


func _add_light(config: Dictionary) -> void:
	var light: DirectionalLight3D = DirectionalLight3D.new()
	var angles: Array = config.rotation_degrees
	light.rotation_degrees = Vector3(float(angles[0]), float(angles[1]), float(angles[2]))
	light.light_energy = float(config.energy)
	world.add_child(light)


func _bounds(node: Node3D, parent_transform: Transform3D) -> AABB:
	var transform: Transform3D = parent_transform * node.transform
	var result: AABB = AABB()
	if node is MeshInstance3D and node.visible and node.mesh != null:
		result = transform * node.get_aabb()
	for child: Node in node.get_children():
		if child is Node3D and child.visible:
			var child_bounds: AABB = _bounds(child, transform)
			if child_bounds.size.length_squared() > 0.0:
				result = child_bounds if result.size.length_squared() == 0.0 else result.merge(child_bounds)
	return result


func _aim(center: Vector3, extent: float, azimuth_degrees: float) -> void:
	var azimuth: float = deg_to_rad(azimuth_degrees)
	var elevation: float = deg_to_rad(CAMERA_ELEVATION_DEGREES)
	var offset: Vector3 = extent * CAMERA_DISTANCE_EXTENTS * Vector3(
		sin(azimuth) * cos(elevation),
		sin(elevation),
		-cos(azimuth) * cos(elevation))
	camera.look_at_from_position(center + offset, center)


func _save(path: String) -> bool:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image == null or image.is_empty() or image.get_size() != FRAME_SIZE:
		push_error("Cannot read a complete %dx%d frame at %s" % [FRAME_SIZE.x, FRAME_SIZE.y, path])
		return false
	var error: Error = image.save_png(path)
	if error != OK:
		push_error("Cannot save %s: %s" % [path, error_string(error)])
		return false
	return true

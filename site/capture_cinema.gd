# WEB-03 native model cinema capture. Studio presentation only; no model materials are changed.
# Run with pinned Godot, --path app, and -- --aircraft=jet|stik --mode=poster|video|details.
extends SceneTree

const Builder = preload("res://render/airplane.gd")

const AIRCRAFT: Dictionary = {
	"stik": {
		"id": "jensen-das-ugly-stik-60",
		"name": "Jensen Das Ugly Stik 60",
		"center_model": false,
		"ambient_color": "9eafbd",
		"ambient_energy": 0.28,
		"lights": [
			{"role": "warm key with cast shadow", "rotation_degrees": [-48.0, -32.0, -10.0], "color": "fff0df", "energy": 1.20, "shadow": true},
			{"role": "cool camera fill", "rotation_degrees": [-20.0, 145.0, 7.0], "color": "c8d8e6", "energy": 0.34, "shadow": false},
			{"role": "blue rear rim", "rotation_degrees": [-35.0, 25.0, 0.0], "color": "8eb8d6", "energy": 0.72, "shadow": false},
		],
		"fov": 38.0,
		"elevation": 25.0,
		"azimuth": 40.0,
		"distance_extents": 1.16,
		"orbit_amplitude": 12.0,
	},
	"jet": {
		"id": "sebart-avanti-s-a200-p100rx",
		"name": "Ventage Jet",
		"center_model": true,
		"ambient_color": "a9b9c8",
		"ambient_energy": 0.28,
		"lights": [
			{"role": "warm key with cast shadow", "rotation_degrees": [-48.0, -32.0, -10.0], "color": "fff0df", "energy": 0.88, "shadow": true},
			{"role": "cool camera fill", "rotation_degrees": [-20.0, 145.0, 7.0], "color": "d4e0eb", "energy": 0.34, "shadow": false},
			{"role": "blue rear rim", "rotation_degrees": [-35.0, 25.0, 0.0], "color": "a5c5de", "energy": 0.48, "shadow": false},
		],
		"fov": 34.0,
		"elevation": 17.0,
		"azimuth": 42.0,
		"distance_extents": 1.25,
		"orbit_amplitude": 9.0,
	},
}
const BACKGROUND: Color = Color("101820")
const POSTER_SIZE: Vector2i = Vector2i(1600, 1000)
const VIDEO_SIZE: Vector2i = Vector2i(1280, 800)
const FRAME_RATE: int = 24
const DURATION_SECONDS: float = 12.0
# Targets are in the aircraft's visible-bounds-centered model coordinates. They are refined from
# the rendered native GLB, and the same entries are exported for the site's model-viewer controls.
const JET_DETAIL_SHOTS: Array[Dictionary] = [
	{
		"id": "cockpit",
		"target": [0.0, -0.04, -0.55],
		"azimuth_degrees": 40.0,
		"elevation_degrees": 22.0,
		"radius_m": 1.45,
		"fov_degrees": 38.0,
	},
	{
		"id": "wing",
		"target": [0.42, -0.26, 0.12],
		"azimuth_degrees": 70.0,
		"elevation_degrees": 20.0,
		"radius_m": 1.55,
		"fov_degrees": 36.0,
	},
	{
		"id": "tail",
		"target": [0.0, 0.10, 0.71],
		"azimuth_degrees": 145.0,
		"elevation_degrees": 18.0,
		"radius_m": 1.65,
		"fov_degrees": 35.0,
	},
]

var aircraft_key: String = "stik"
var mode: String = "poster"
var output_dir: String = ""
var aircraft_id: String = ""
var aircraft_name: String = ""
var aircraft_config: Dictionary = {}
var inspect_model: bool = false
var hero_azimuth: float = 0.0
var hero_elevation: float = 0.0
var hero_distance_extents: float = 0.0
var custom_hero_azimuth: bool = false
var custom_hero_elevation: bool = false
var custom_hero_distance: bool = false
var world: Node3D
var camera: Camera3D
var airplane: Node3D
var model_bounds_center: Vector3
var model_bounds_size: Vector3
var model_extent: float = 0.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--aircraft="):
			aircraft_key = arg.trim_prefix("--aircraft=")
		elif arg.begins_with("--mode="):
			mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--out-dir="):
			output_dir = arg.trim_prefix("--out-dir=")
		elif arg == "--dump-model":
			inspect_model = true
		elif arg.begins_with("--camera-azimuth="):
			hero_azimuth = float(arg.trim_prefix("--camera-azimuth="))
			custom_hero_azimuth = true
		elif arg.begins_with("--camera-elevation="):
			hero_elevation = float(arg.trim_prefix("--camera-elevation="))
			custom_hero_elevation = true
		elif arg.begins_with("--camera-distance-extents="):
			hero_distance_extents = float(arg.trim_prefix("--camera-distance-extents="))
			custom_hero_distance = true
	if not AIRCRAFT.has(aircraft_key):
		push_error("--aircraft must be jet or stik")
		quit(1)
		return
	if mode not in ["poster", "video", "details"]:
		push_error("--mode must be poster, video, or details")
		quit(1)
		return
	if output_dir.is_empty() or DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		push_error("Provide a writable absolute --out-dir")
		quit(1)
		return
	aircraft_config = AIRCRAFT[aircraft_key]
	aircraft_id = str(aircraft_config.id)
	aircraft_name = str(aircraft_config.name)
	if not custom_hero_azimuth:
		hero_azimuth = float(aircraft_config.azimuth)
	if not custom_hero_elevation:
		hero_elevation = float(aircraft_config.elevation)
	if not custom_hero_distance:
		hero_distance_extents = float(aircraft_config.distance_extents)

	root.size = POSTER_SIZE if mode == "poster" else VIDEO_SIZE
	root.msaa_3d = Viewport.MSAA_4X
	world = Node3D.new()
	world.name = "CinemaStage"
	root.add_child(world)
	_add_environment()
	_add_lights()
	camera = Camera3D.new()
	camera.name = "StudioCamera"
	camera.fov = float(aircraft_config.fov)
	camera.current = true
	world.add_child(camera)

	var model: Dictionary = Builder.build(aircraft_id)
	airplane = model.get("root") as Node3D
	if model.is_empty() or airplane == null:
		push_error("Native catalog builder failed for " + aircraft_id)
		quit(1)
		return
	if inspect_model:
		_dump_meshes(airplane, Transform3D.IDENTITY, airplane.name)
	airplane.name = "airplane"
	world.add_child(airplane)
	await process_frame
	var bounds: AABB = _bounds(airplane, Transform3D.IDENTITY)
	model_bounds_center = bounds.get_center()
	model_bounds_size = bounds.size
	model_extent = maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	if model_extent <= 0.0 or bounds.size.length_squared() <= 0.0:
		push_error("Native catalog builder produced no visible mesh bounds")
		quit(1)
		return

	# Jet shots use the same visible-bounds-centered coordinate system as the site's exported GLB.
	# Stik retains its established center-and-floor transform and asset framing.
	if bool(aircraft_config.center_model):
		airplane.position = -model_bounds_center
	else:
		airplane.position = Vector3(-model_bounds_center.x, -bounds.position.y + 0.012, -model_bounds_center.z)
	await process_frame

	var saved: bool = false
	if mode == "poster":
		_aim_hero(hero_azimuth)
		saved = await _save(output_dir.path_join("poster.png"))
	elif mode == "video":
		var frames_dir: String = output_dir.path_join("frames")
		if DirAccess.make_dir_recursive_absolute(frames_dir) != OK:
			push_error("Cannot create frame directory: " + frames_dir)
			quit(1)
			return
		var frame_count: int = int(round(DURATION_SECONDS * float(FRAME_RATE)))
		for frame_index: int in range(frame_count):
			var phase: float = TAU * float(frame_index) / float(frame_count)
			var azimuth: float = hero_azimuth + float(aircraft_config.orbit_amplitude) * cos(phase - PI * 0.5)
			_aim_hero(azimuth)
			var frame_path: String = frames_dir.path_join("%04d.png" % frame_index)
			if not await _save(frame_path):
				quit(1)
				return
		saved = _write_capture_manifest(frame_count)
	else:
		saved = await _capture_details()
	if not saved:
		quit(1)
		return
	print("CINEMA_CAPTURE_OK: %s, %s, %s, %dx%d" % [aircraft_key, mode, aircraft_id, root.size.x, root.size.y])
	quit(0)


func _add_environment() -> void:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = BACKGROUND
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(str(aircraft_config.ambient_color))
	environment.ambient_light_energy = float(aircraft_config.ambient_energy)
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	environment_node.environment = environment
	world.add_child(environment_node)


func _add_lights() -> void:
	for config: Dictionary in aircraft_config.lights:
		var light: DirectionalLight3D = DirectionalLight3D.new()
		var angles: Array = config.rotation_degrees
		light.rotation_degrees = Vector3(float(angles[0]), float(angles[1]), float(angles[2]))
		light.light_color = Color(str(config.color))
		light.light_energy = float(config.energy)
		light.shadow_enabled = bool(config.shadow)
		if bool(config.shadow):
			light.shadow_bias = 0.035
			light.shadow_normal_bias = 1.0
			light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			light.directional_shadow_max_distance = 10.0
			light.directional_shadow_pancake_size = 4.0
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


func _dump_meshes(node: Node3D, parent_transform: Transform3D, node_path: String) -> void:
	var transform: Transform3D = parent_transform * node.transform
	if node is MeshInstance3D and node.mesh != null:
		var mesh_bounds: AABB = transform * node.get_aabb()
		var center := mesh_bounds.get_center()
		var size := mesh_bounds.size
		var materials: Array[String] = []
		for surface_index: int in range(node.mesh.get_surface_count()):
			var material: Material = node.get_active_material(surface_index)
			materials.append(material.resource_name if material != null else "none")
		print("CINEMA_MESH|%s|center=%s|size=%s|materials=%s" % [node_path, center, size, materials])
	for child: Node in node.get_children():
		if child is Node3D:
			_dump_meshes(child, transform, node_path.path_join(child.name))


func _hero_target() -> Vector3:
	# Offset the model slightly right in the wide studio frame, leaving the dark left field calm.
	if aircraft_key == "jet":
		var azimuth := deg_to_rad(hero_azimuth)
		var shift := model_extent * 0.10
		return Vector3(cos(azimuth) * shift, -0.01, sin(azimuth) * shift)
	return Vector3.ZERO


func _aim_hero(azimuth_degrees: float) -> void:
	var azimuth: float = deg_to_rad(azimuth_degrees)
	var elevation: float = deg_to_rad(hero_elevation)
	var distance: float = model_extent * hero_distance_extents
	var offset: Vector3 = distance * Vector3(
		sin(azimuth) * cos(elevation),
		sin(elevation),
		-cos(azimuth) * cos(elevation))
	camera.fov = float(aircraft_config.fov)
	camera.look_at_from_position(_hero_target() + offset, _hero_target())
	if inspect_model:
		print("CINEMA_CAMERA|position=%s|target=%s|rotation=%s|azimuth=%s|elevation=%s|distance=%s" % [camera.position, _hero_target(), camera.rotation_degrees, azimuth_degrees, hero_elevation, distance])


func _aim_detail(config: Dictionary) -> void:
	var target_array: Array = config.target
	var target := Vector3(float(target_array[0]), float(target_array[1]), float(target_array[2]))
	var azimuth := deg_to_rad(float(config.azimuth_degrees))
	var elevation := deg_to_rad(float(config.elevation_degrees))
	var distance := float(config.radius_m)
	var offset := distance * Vector3(
		sin(azimuth) * cos(elevation),
		sin(elevation),
		-cos(azimuth) * cos(elevation))
	camera.fov = float(config.fov_degrees)
	camera.look_at_from_position(target + offset, target)


func _capture_details() -> bool:
	if aircraft_key != "jet":
		push_error("Detail stills are currently defined for the jet catalog model")
		return false
	var details_dir := output_dir.path_join("details")
	if DirAccess.make_dir_recursive_absolute(details_dir) != OK:
		push_error("Cannot create details directory: " + details_dir)
		return false
	for config: Dictionary in JET_DETAIL_SHOTS:
		_aim_detail(config)
		var image_path := details_dir.path_join("%s.png" % str(config.id))
		if not await _save(image_path):
			return false
	return true


func _save(path: String) -> bool:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image == null or image.is_empty() or image.get_size() != root.size:
		push_error("Cannot read a complete frame at " + path)
		return false
	var error: Error = image.save_png(path)
	if error != OK:
		push_error("Cannot save %s: %s" % [path, error_string(error)])
		return false
	return true


func _orbit_record(azimuth_degrees: float, elevation_degrees: float, radius_m: float, target: Vector3) -> Dictionary:
	return {
		"target_centered_model_m": [target.x, target.y, target.z],
		"azimuth_degrees": azimuth_degrees,
		"elevation_degrees": elevation_degrees,
		"radius_m": radius_m,
		"model_viewer_orbit_degrees": {
			"theta": 180.0 - azimuth_degrees,
			"phi": 90.0 - elevation_degrees,
			"radius_m": radius_m,
		},
	}


func _write_capture_manifest(frame_count: int) -> bool:
	var hero_target := _hero_target()
	var hero_radius := model_extent * hero_distance_extents
	var detail_records: Dictionary = {}
	for config: Dictionary in JET_DETAIL_SHOTS if aircraft_key == "jet" else []:
		var target_array: Array = config.target
		var target := Vector3(float(target_array[0]), float(target_array[1]), float(target_array[2]))
		detail_records[str(config.id)] = {
			"filename": "jet-%s.webp" % str(config.id),
			"frame_size": [VIDEO_SIZE.x, VIDEO_SIZE.y],
			"fov_degrees": float(config.fov_degrees),
			"camera": _orbit_record(float(config.azimuth_degrees), float(config.elevation_degrees), float(config.radius_m), target),
		}
	var manifest: Dictionary = {
		"format": "openrc-cinema-capture-v1",
		"purpose": "Silent studio model presentation; visual source study only, not gameplay or flight validation",
		"aircraft_key": aircraft_key,
		"aircraft_id": aircraft_id,
		"aircraft_name": aircraft_name,
		"engine": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_method(),
		"frame_size": [root.size.x, root.size.y],
		"frame_rate": FRAME_RATE,
		"frame_count": frame_count,
		"duration_seconds": DURATION_SECONDS,
		"background": "#101820",
		"camera": {
			"projection": "perspective",
			"fov_degrees": float(aircraft_config.fov),
			"target_centered_model_m": [hero_target.x, hero_target.y, hero_target.z],
			"elevation_degrees": hero_elevation,
			"base_azimuth_degrees": hero_azimuth,
			"orbit": "phase-shifted cosine yaw around world Y; starts at base azimuth",
			"orbit_amplitude_degrees": float(aircraft_config.orbit_amplitude),
			"distance_model_extents": hero_distance_extents,
			"radius_m": hero_radius,
			"model_viewer_orbit_degrees": {
				"theta": 180.0 - hero_azimuth,
				"phi": 90.0 - hero_elevation,
				"radius_m": hero_radius,
			},
			"detail_shots": detail_records,
		},
		"ambient_light": {"color": "#" + str(aircraft_config.ambient_color), "energy": float(aircraft_config.ambient_energy)},
		"lighting": aircraft_config.lights,
		"model_bounds": {
			"size": [model_bounds_size.x, model_bounds_size.y, model_bounds_size.z],
			"source_center": [model_bounds_center.x, model_bounds_center.y, model_bounds_center.z],
			"placement": "visible bounds centered" if bool(aircraft_config.center_model) else "centered in X/Z; lowest authored mesh 0.012 above floor",
		},
	}
	var file := FileAccess.open(output_dir.path_join("capture.json"), FileAccess.WRITE)
	if file == null:
		push_error("Cannot write cinema capture manifest")
		return false
	file.store_string(JSON.stringify(manifest, "\t") + "\n")
	file.close()
	return true

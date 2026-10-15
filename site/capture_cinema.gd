# WEB-03 still and looping studio presentation of the native Jensen Das Ugly Stik builder.
# Run with the pinned Godot build, --path app, and -- --mode=poster|video --out-dir=<absolute path>.
extends SceneTree

const Builder = preload("res://render/airplane.gd")

const AIRCRAFT_ID: String = "jensen-das-ugly-stik-60"
const AIRCRAFT_NAME: String = "Jensen Das Ugly Stik 60"
const BACKGROUND: Color = Color("101820")
const AMBIENT_COLOR: Color = Color("9eafbd")
const AMBIENT_ENERGY: float = 0.28
const POSTER_SIZE: Vector2i = Vector2i(1600, 1000)
const VIDEO_SIZE: Vector2i = Vector2i(1280, 800)
const FRAME_RATE: int = 24
const DURATION_SECONDS: float = 12.0
const CAMERA_FOV_DEGREES: float = 38.0
const CAMERA_ELEVATION_DEGREES: float = 25.0
const CAMERA_BASE_AZIMUTH_DEGREES: float = 40.0
const CAMERA_ORBIT_AMPLITUDE_DEGREES: float = 12.0
const CAMERA_DISTANCE_EXTENTS: float = 1.16
const LIGHTS: Array[Dictionary] = [
	{
		"role": "warm key with cast shadow",
		"rotation_degrees": [-48.0, -32.0, -10.0],
		"color": "fff0df",
		"energy": 1.20,
		"shadow": true,
	},
	{
		"role": "cool camera fill",
		"rotation_degrees": [-20.0, 145.0, 7.0],
		"color": "c8d8e6",
		"energy": 0.34,
		"shadow": false,
	},
	{
		"role": "blue rear rim",
		"rotation_degrees": [-35.0, 25.0, 0.0],
		"color": "8eb8d6",
		"energy": 0.72,
		"shadow": false,
	},
]

var mode: String = "poster"
var output_dir: String = ""
var world: Node3D
var camera: Camera3D
var airplane: Node3D
var model_center: Vector3
var model_bounds_size: Vector3
var model_extent: float = 0.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--out-dir="):
			output_dir = arg.trim_prefix("--out-dir=")
	if mode not in ["poster", "video"]:
		push_error("--mode must be poster or video")
		quit(1)
		return
	if output_dir.is_empty() or DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		push_error("Provide a writable absolute --out-dir")
		quit(1)
		return

	root.size = POSTER_SIZE if mode == "poster" else VIDEO_SIZE
	root.msaa_3d = Viewport.MSAA_4X
	world = Node3D.new()
	world.name = "CinemaStage"
	root.add_child(world)
	_add_environment()
	_add_lights()
	camera = Camera3D.new()
	camera.name = "StudioCamera"
	camera.fov = CAMERA_FOV_DEGREES
	camera.current = true
	world.add_child(camera)

	var model: Dictionary = Builder.build(AIRCRAFT_ID)
	airplane = model.get("root") as Node3D
	if model.is_empty() or airplane == null:
		push_error("Native catalog builder failed for " + AIRCRAFT_ID)
		quit(1)
		return
	airplane.name = "airplane"
	world.add_child(airplane)
	await process_frame
	var bounds: AABB = _bounds(airplane, Transform3D.IDENTITY)
	model_center = bounds.get_center()
	model_bounds_size = bounds.size
	model_extent = maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	if model_extent <= 0.0 or bounds.size.length_squared() <= 0.0:
		push_error("Native catalog builder produced no visible mesh bounds")
		quit(1)
		return

	# The source builder and all of its child geometry remain intact. This root transform
	# centers the model and places its lowest authored mesh just above the studio floor.
	airplane.position = Vector3(-model_center.x, -bounds.position.y + 0.012, -model_center.z)
	model_center = Vector3.ZERO
	await process_frame

	var saved: bool = false
	if mode == "poster":
		_aim(CAMERA_BASE_AZIMUTH_DEGREES)
		saved = await _save(output_dir.path_join("poster.png"))
	else:
		var frames_dir: String = output_dir.path_join("frames")
		if DirAccess.make_dir_recursive_absolute(frames_dir) != OK:
			push_error("Cannot create frame directory: " + frames_dir)
			quit(1)
			return
		var frame_count: int = int(round(DURATION_SECONDS * float(FRAME_RATE)))
		for frame_index: int in range(frame_count):
			var phase: float = TAU * float(frame_index) / float(frame_count)
			var azimuth: float = CAMERA_BASE_AZIMUTH_DEGREES + CAMERA_ORBIT_AMPLITUDE_DEGREES * cos(phase - PI * 0.5)
			_aim(azimuth)
			var frame_path: String = frames_dir.path_join("%04d.png" % frame_index)
			if not await _save(frame_path):
				quit(1)
				return
		saved = _write_capture_manifest(frame_count)
	if not saved:
		quit(1)
		return
	print("CINEMA_CAPTURE_OK: %s, %s, %dx%d" % [mode, AIRCRAFT_ID, root.size.x, root.size.y])
	quit(0)


func _add_environment() -> void:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = BACKGROUND
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = AMBIENT_COLOR
	environment.ambient_light_energy = AMBIENT_ENERGY
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	environment_node.environment = environment
	world.add_child(environment_node)


func _add_lights() -> void:
	for config: Dictionary in LIGHTS:
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


func _aim(azimuth_degrees: float) -> void:
	var azimuth: float = deg_to_rad(azimuth_degrees)
	var elevation: float = deg_to_rad(CAMERA_ELEVATION_DEGREES)
	var offset: Vector3 = model_extent * CAMERA_DISTANCE_EXTENTS * Vector3(
		sin(azimuth) * cos(elevation),
		sin(elevation),
		-cos(azimuth) * cos(elevation))
	camera.look_at_from_position(model_center + offset, model_center)


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


func _write_capture_manifest(frame_count: int) -> bool:
	var manifest: Dictionary = {
		"format": "openrc-cinema-capture-v1",
		"purpose": "Silent studio model presentation; not gameplay or flight validation",
		"aircraft_id": AIRCRAFT_ID,
		"aircraft_name": AIRCRAFT_NAME,
		"engine": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_method(),
		"frame_size": [root.size.x, root.size.y],
		"frame_rate": FRAME_RATE,
		"frame_count": frame_count,
		"duration_seconds": DURATION_SECONDS,
		"background": "#101820",
		"camera": {
			"projection": "perspective",
			"fov_degrees": CAMERA_FOV_DEGREES,
			"elevation_degrees": CAMERA_ELEVATION_DEGREES,
			"base_azimuth_degrees": CAMERA_BASE_AZIMUTH_DEGREES,
			"orbit": "phase-shifted cosine yaw around world Y; starts at base azimuth",
			"orbit_amplitude_degrees": CAMERA_ORBIT_AMPLITUDE_DEGREES,
			"distance_model_extents": CAMERA_DISTANCE_EXTENTS,
		},
		"ambient_light": {"color": "#9eafbd", "energy": AMBIENT_ENERGY},
		"lighting": LIGHTS,
		"model_bounds": {
			"size": [model_bounds_size.x, model_bounds_size.y, model_bounds_size.z],
			"placement": "centered; lowest authored mesh 0.012 above floor",
		},
	}
	var file: FileAccess = FileAccess.open(output_dir.path_join("capture.json"), FileAccess.WRITE)
	if file == null:
		push_error("Cannot write cinema capture manifest")
		return false
	file.store_string(JSON.stringify(manifest, "\t") + "\n")
	file.close()
	return true

extends SceneTree

const FRAMES_PER_PHASE := 64
const DLSS_SINGLETON := "Streamline"
const DLSS_CAPABILITY := "STREAMLINE_CAPABILITY_DLSS"
const DLSS_MODE := "SCALING_3D_MODE_DLSS"
const FULL_SIZE := Vector2i(1920, 1080)
const RESIZE_SIZE := Vector2i(1600, 900)

var _scene: Node3D
var _moving_box: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("MINIMAL_DLSS|UNAVAILABLE|reason=headless_renderer")
		quit(2)
		return
	var renderer := str(RenderingServer.get_current_rendering_method())
	if renderer != "forward_plus":
		printerr("MINIMAL_DLSS|UNAVAILABLE|reason=forward_plus_required|renderer=%s" % renderer)
		quit(2)
		return
	var native_control := OS.get_cmdline_user_args().has("--native")
	var mode_id := Viewport.SCALING_3D_MODE_BILINEAR
	if not native_control:
		var capability := _dlss_capability()
		if not bool(capability.get("available", false)):
			printerr("MINIMAL_DLSS|UNAVAILABLE|reason=%s" % str(capability.get("reason", "unknown")))
			quit(2)
			return
		mode_id = int(capability.mode_id)
		print("MINIMAL_DLSS|CAPABILITY|supported=true|mode_id=%d" % mode_id)
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with("--preset="):
				var preset := argument.trim_prefix("--preset=")
				if preset not in ["F", "J", "K"]:
					printerr("MINIMAL_DLSS|UNAVAILABLE|reason=invalid_test_preset")
					quit(2)
					return
				var parameter := ClassDB.class_get_integer_constant(DLSS_SINGLETON, "STREAMLINE_PARAM_DLSS_PRESET")
				Engine.get_singleton(DLSS_SINGLETON).call("set_parameter", parameter, preset)
				print("MINIMAL_DLSS|PRESET|value=%s" % preset)
	else:
		print("MINIMAL_DLSS|CAPABILITY|native_control=true")

	_build_scene()
	print("MINIMAL_DLSS|RUN_START|provider=%s|renderer=%s|window=%dx%d|frames_per_phase=%d" % [
		"native" if native_control else "dlss", renderer, FULL_SIZE.x, FULL_SIZE.y, FRAMES_PER_PHASE])
	var phases: Array[Dictionary] = []
	if native_control:
		phases = [
			{"name": "NATIVE_1920x1080", "size": FULL_SIZE},
			{"name": "NATIVE_RESIZE_1600x900", "size": RESIZE_SIZE},
			{"name": "NATIVE_RESIZE_1920x1080", "size": FULL_SIZE},
		]
	else:
		phases = [
			{"name": "DLAA", "size": FULL_SIZE, "scale": 1.0},
			{"name": "QUALITY", "size": FULL_SIZE, "scale": 2.0 / 3.0},
			{"name": "BALANCED", "size": FULL_SIZE, "scale": 1.0 / 1.7},
			{"name": "PERFORMANCE", "size": FULL_SIZE, "scale": 0.5},
			{"name": "RESIZE_1600x900_QUALITY", "size": RESIZE_SIZE, "scale": 2.0 / 3.0},
			{"name": "RESIZE_1920x1080_QUALITY", "size": FULL_SIZE, "scale": 2.0 / 3.0},
		]
	for phase: Dictionary in phases:
		var phase_scale := float(phase.get("scale", 1.0))
		if not await _render_phase(str(phase.name), Vector2i(phase.size), mode_id, phase_scale, native_control):
			quit(3)
			return
	print("MINIMAL_DLSS|RUN_COMPLETE|provider=%s|phases=%d|frames=%d" % [
		"native" if native_control else "dlss", phases.size(), phases.size() * FRAMES_PER_PHASE])
	quit(0)


func _dlss_capability() -> Dictionary:
	if not ClassDB.class_has_integer_constant("Viewport", DLSS_MODE):
		return {"available": false, "reason": "viewport_dlss_mode_missing"}
	if not Engine.has_singleton(DLSS_SINGLETON):
		return {"available": false, "reason": "streamline_singleton_missing"}
	if not ClassDB.class_has_integer_constant(DLSS_SINGLETON, DLSS_CAPABILITY):
		return {"available": false, "reason": "dlss_capability_constant_missing"}
	var streamline: Object = Engine.get_singleton(DLSS_SINGLETON)
	if streamline == null or not streamline.has_method("get_capability"):
		return {"available": false, "reason": "streamline_capability_query_missing"}
	var capability_id := ClassDB.class_get_integer_constant(DLSS_SINGLETON, DLSS_CAPABILITY)
	if not bool(streamline.call("get_capability", capability_id)):
		return {"available": false, "reason": "dlss_not_supported_by_runtime"}
	return {"available": true, "mode_id": ClassDB.class_get_integer_constant("Viewport", DLSS_MODE)}


func _build_scene() -> void:
	_scene = Node3D.new()
	_scene.name = "ReproducerScene"
	root.add_child(_scene)

	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.18, 0.25, 0.34)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.68, 0.73, 0.82)
	environment.ambient_light_energy = 0.7
	world.environment = environment
	_scene.add_child(world)

	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.position = Vector3(8.5, 7.5, 11.0)
	camera.fov = 50.0
	_scene.add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)

	var light := DirectionalLight3D.new()
	light.name = "KeyLight"
	light.rotation_degrees = Vector3(-52.0, -33.0, 0.0)
	light.light_energy = 2.0
	light.shadow_enabled = true
	_scene.add_child(light)

	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(22.0, 0.2, 18.0)
	var floor := MeshInstance3D.new()
	floor.name = "Floor"
	floor.mesh = floor_mesh
	floor.position = Vector3(0.0, -0.15, -1.5)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.17, 0.21, 0.25)
	floor_material.roughness = 0.86
	floor.material_override = floor_material
	_scene.add_child(floor)

	var index := 0
	for x: int in range(-4, 5):
		for z: int in range(-4, 4):
			var height := 0.35 + float((index * 7) % 5) * 0.12
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.72, height, 0.72)
			var instance := MeshInstance3D.new()
			instance.name = "Box_%02d" % index
			instance.mesh = mesh
			instance.position = Vector3(float(x) * 1.55, height * 0.5, float(z) * 1.55 - 1.5)
			var material := StandardMaterial3D.new()
			material.albedo_color = Color.from_hsv(float((index * 13) % 100) / 100.0, 0.62, 0.82)
			material.roughness = 0.48
			material.metallic = 0.08
			instance.material_override = material
			_scene.add_child(instance)
			if x == 0 and z == 0:
				_moving_box = instance
			index += 1


func _render_phase(label: String, size: Vector2i, mode_id: int, scale: float, native_control: bool) -> bool:
	var initial_dispatches := 0
	var streamline: Object = null
	if not native_control:
		streamline = Engine.get_singleton(DLSS_SINGLETON)
		if not streamline.has_method("get_dlss_status"):
			printerr("MINIMAL_DLSS|FAIL|reason=dispatch_status_missing")
			return false
		initial_dispatches = int(streamline.call("get_dlss_status").get("dispatches", 0))
	DisplayServer.window_set_size(size)
	root.size = size
	root.scaling_3d_mode = mode_id
	root.scaling_3d_scale = scale
	root.msaa_3d = Viewport.MSAA_4X if native_control else Viewport.MSAA_DISABLED
	root.fsr_sharpness = 0.0
	root.use_taa = false
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	print("MINIMAL_DLSS|PHASE_START|name=%s|output=%dx%d|scale=%.6f|mode_id=%d" % [
		label, size.x, size.y, scale, mode_id])
	for _frame: int in range(FRAMES_PER_PHASE):
		if is_instance_valid(_moving_box):
			_moving_box.rotate_y(0.012)
		await RenderingServer.frame_post_draw
	print("MINIMAL_DLSS|PHASE_DONE|name=%s|actual_output=%dx%d|frames=%d" % [
		label, root.size.x, root.size.y, FRAMES_PER_PHASE])
	if not native_control:
		var status: Dictionary = streamline.call("get_dlss_status")
		print("MINIMAL_DLSS|STATUS|name=%s|backend=%s" % [label, JSON.stringify(status)])
		if bool(status.get("backend_failed", true)) or not bool(status.get("available", false)) \
				or int(status.get("dispatches", 0)) <= initial_dispatches:
			printerr("MINIMAL_DLSS|FAIL|reason=no_successful_dispatch|phase=%s" % label)
			return false
	return true

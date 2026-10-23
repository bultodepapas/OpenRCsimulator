# CAM-02 fixed-pose studio evidence; not a flight or performance collector.
extends SceneTree

const AirplaneBuilder := preload("res://render/airplane.gd")
const PilotCamera := preload("res://render/pilot_camera.gd")
const CameraRig := preload("res://render/camera/camera_rig.gd")


func _initialize() -> void:
	_run.call_deferred()


static func _flat(_x: float, _z: float) -> float:
	return 0.0


func _run() -> void:
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	if DisplayServer.get_name() == "headless" or not out.is_absolute_path() or DirAccess.dir_exists_absolute(out):
		printerr("requires native rendering and --out=<new absolute directory>")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(out) != OK:
		quit(2)
		return
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.28, 0.40, 0.56)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	root.add_child(environment)
	var sun := DirectionalLight3D.new()
	root.add_child(sun)
	sun.rotation_degrees = Vector3(-40, -30, 0)
	var aircraft := AirplaneBuilder.build()
	if aircraft.is_empty():
		quit(1)
		return
	var model: Node3D = aircraft.root
	root.add_child(model)
	var camera := PilotCamera.create(root, {eye_height = 1.7})
	var rig := CameraRig.new(camera, 1.524)
	rig.auto_zoom = false
	var eye := Vector3(0, 1.7, 0)
	var results := []
	var passed := true
	for item in [{name = "ordinary", offset = Vector3(6, 3, -8)}, {name = "overhead", offset = Vector3(0, 8, 0)}, {name = "underfoot", offset = Vector3(0, -8, 0)}, {name = "near-pole-diagonal", offset = Vector3(0.000064, 8, 0.000064)}]:
		camera.position = eye
		camera.look_at(eye + Vector3(20, 10, 0), Vector3.UP)
		model.position = eye + item.offset
		rig.update(model.position, model.transform, model.basis, 1.0 / 60.0, false, _flat)
		for frame in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var center_error_px := camera.unproject_position(model.position).distance_to(Vector2(960, 540))
		# Camera3D rounds the nearly vertical pose; qualify pixel-level centering.
		var centered := center_error_px < 0.5
		var ok := img.get_size() == Vector2i(1920, 1080) and centered and camera.basis.is_finite()
		var path := out.path_join(item.name + ".png")
		ok = img.save_png(path) == OK and ok
		passed = passed and ok
		results.append({case = item.name, ok = ok, width = img.get_width(), height = img.get_height(), centered = centered, center_error_px = center_error_px, fov = camera.fov, aim_dot = (-camera.basis.z).dot((item.offset as Vector3).normalized()), png_sha256 = FileAccess.get_sha256(path)})
	var report := FileAccess.open(out.path_join("report.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({godot = Engine.get_version_info(), adapter = RenderingServer.get_video_adapter_name(), renderer = RenderingServer.get_current_rendering_method(), cases = results, ok = passed}, "\t"))
	print("camera pole native captures passed" if passed else "camera pole native captures FAILED")
	quit(0 if passed else 1)

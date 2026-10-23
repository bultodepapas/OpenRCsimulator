# DT-11a: matched native studio frames using the retained reference and candidate.
extends SceneTree

const Builder = preload("res://render/airplane.gd")
const Clock = preload("res://render/shader_clock.gd")
const Exposure = preload("res://render/world/exposure.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := ""
	var reference: Script
	var candidate: Script
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
		if arg.begins_with("--reference="): reference = load(arg.trim_prefix("--reference="))
		if arg.begins_with("--candidate="): candidate = load(arg.trim_prefix("--candidate="))
	if DisplayServer.get_name() == "headless" or reference == null or candidate == null or not out.is_absolute_path() or DirAccess.dir_exists_absolute(out):
		printerr("requires native rendering, --reference, --candidate and --out=<new absolute directory>")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(out) != OK:
		quit(2)
		return
	Clock.register()
	Clock.update(0.4)
	Exposure.set_value(1.0)
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.msaa_3d = Viewport.MSAA_4X
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("#1d2c3c")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.15
	root.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -25, 0)
	sun.light_energy = 0.2
	root.add_child(sun)
	var camera := Camera3D.new()
	camera.fov = 35.0
	root.add_child(camera)
	camera.current = true
	var rows := []
	var passed := true
	for id in [Builder.STIK_ID, Builder.P51_ID, Builder.TIMBER_ID]:
		var model: Dictionary = Builder.build(id)
		if model.is_empty():
			quit(1)
			return
		root.add_child(model.root)
		camera.look_at_from_position(Vector3(2.5, -1.4, -3.5), Vector3.ZERO, Vector3.UP)
		var images: Array[Image] = []
		for script: Script in [reference, candidate]:
			var kit: Node3D = script.attach(model.root)
			for frame in 8:
				await process_frame
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			var path := out.path_join(id + ("-reference.png" if script == reference else "-candidate.png"))
			passed = img.save_png(path) == OK and passed
			images.append(img)
			model.root.remove_child(kit)
			kit.free()
		var exact := images[0].get_data() == images[1].get_data()
		passed = exact and images[0].get_size() == Vector2i(1920, 1080) and passed
		rows.append({aircraft = id, width = images[0].get_width(), height = images[0].get_height(), exact = exact})
		model.root.free()
		await process_frame
	var report := FileAccess.open(out.path_join("report.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({ok = passed, cases = rows, adapter = RenderingServer.get_video_adapter_name(), renderer = RenderingServer.get_current_rendering_method()}, "\t"))
	print("landing-anchor native captures passed" if passed else "landing-anchor native captures FAILED")
	quit(0 if passed else 1)

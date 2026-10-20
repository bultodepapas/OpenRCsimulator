## Native Compatibility fixture using the production sock and field shadow manager.
extends SceneTree
const Sock = preload("res://render/windsock.gd")
const FieldShadows = preload("res://render/field_projected_shadows.gd")
const Loader = preload("res://data/field_loader.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const Clock = preload("res://render/shader_clock.gd")
var output: String

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	_run.call_deferred()

func _run() -> void:
	if output.is_empty() or DirAccess.dir_exists_absolute(output):
		printerr("--out must be a new directory")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 720)
	root.msaa_3d = Viewport.MSAA_4X
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Clock.register()
	Clock.update(0.0)
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.29, 0.36, 0.43)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.8, 0.85, 0.95)
	environment.environment.ambient_light_energy = 0.55
	world.add_child(environment)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(100, 100)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.37, 0.43, 0.25)
	ground_material.roughness = 1.0
	ground.material_override = ground_material
	world.add_child(ground)
	var cue: Dictionary = Loader.load_from().field.flight_cues.filter(func(c: Dictionary) -> bool: return c.type == "windsock")[0].duplicate(true)
	cue.north = 0.0
	cue.east = 0.0
	var sock := Sock.build(cue)
	world.add_child(sock)
	var lighting: Dictionary = Atmosphere.Spec.ATMOSPHERE.duplicate(true)
	lighting.shadow_strength = 1.0
	lighting.sun_elevation_deg = 45.0
	lighting.sun_azimuth_deg = 220.0
	FieldShadows.attach(world, {flight_cues = [cue]}, lighting)
	var manager: Node = world.get_node("ProjectedFieldShadows")
	var projector: Node = manager.projectors[0]
	var sun := Atmosphere.create_sun(world, lighting)
	sun.shadow_enabled = false
	var camera := Camera3D.new()
	camera.position = Vector3(8.5, 7.5, 10)
	camera.fov = 48.0
	world.add_child(camera)
	camera.look_at(Vector3(0.2, 1.3, 0))
	camera.make_current()
	var records: Array[Dictionary] = []
	for entry: Array in [["calm", 0.0, 45.0], ["light", 1.5, 45.0], ["strong", 12.0, 45.0], ["reverse", -12.0, 45.0], ["low-sun", 12.0, 15.0], ["high-sun", 12.0, 75.0], ["night", 12.0, -12.0]]:
		Sock.reset(sock, 0.0)
		var wind: Array = [0.0, entry[1], 0.0]
		for tick: int in 1200:
			Sock.advance(sock, (tick + 1) / 240.0, wind)
		Sock.update(sock, 5.0, wind)
		Clock.update(5.0)
		lighting.sun_elevation_deg = entry[2]
		lighting.shadow_strength = 0.0 if float(entry[2]) < 0.0 else 1.0
		sun.basis = Basis.looking_at(-Atmosphere.sun_direction(lighting), Vector3.UP)
		manager.apply(lighting)
		for frame: int in 8:
			await process_frame
			await RenderingServer.frame_post_draw
		var name: String = entry[0]
		root.get_texture().get_image().save_png(output.path_join(name + ".png"))
		projector.viewport.get_texture().get_image().save_png(output.path_join(name + "-mask.png"))
		if name == "low-sun":
			camera.position = Vector3(23, 19, 19)
			camera.look_at(Vector3(5, 1, -5))
			for frame: int in 3:
				await process_frame
				await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("low-sun-wide.png"))
			camera.position = Vector3(8.5, 7.5, 10)
			camera.look_at(Vector3(0.2, 1.3, 0))
		projector.refresh(float(projector.get_meta("soft_height")), Atmosphere.shadow_direction(lighting), 0.0, false)
		for frame: int in 3:
			await process_frame
			await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(name + "-no-shadow.png"))
		records.append({name = name, elevation_deg = entry[2], wind_east_mps = entry[1], mask_size = projector.viewport.size.x,
			triangles = projector.triangle_count, bounds = str(projector.bounds), target_pixels = manager.target_pixels})
	var file := FileAccess.open(output.path_join("capture.json"), FileAccess.WRITE)
	var sources: Dictionary = {}
	for path: String in ["res://render/windsock_projected_shadow.gd", "res://render/windsock_deformation.gdshaderinc", "res://render/windsock_fabric.gdshader", "res://render/windsock_shadow_mask.gdshader", "res://render/field_projected_shadows.gd"]:
		sources[path] = FileAccess.get_sha256(path)
	file.store_string(JSON.stringify({renderer = RenderingServer.get_current_rendering_method(), adapter = RenderingServer.get_video_adapter_name(), sources_sha256 = sources, records = records}, "\t"))
	world.queue_free()
	await process_frame
	quit()

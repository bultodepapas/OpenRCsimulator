extends SceneTree
## F4U-20-R3: small UI previews from the validated production models, never live gallery viewports.
const Builder = preload("res://render/airplane.gd")
const Presentation = preload("res://ui/home_presentation.gd")
const FAMILY := "f4u-corsair-250"
var output := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	_run.call_deferred()

func _run() -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless":
		printerr("Pass --out=<directory> and use a rendering display.")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	load("res://render/shader_clock.gd").register()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(288, 162)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#242932")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Reflective paints need a neutral sky even though the card background is solid.
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var world := WorldEnvironment.new()
	world.environment = env
	viewport.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 1.2
	viewport.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 150, 0)
	fill.light_energy = 0.3
	viewport.add_child(fill)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	viewport.add_child(camera)
	camera.current = true
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft_models/" + FAMILY + ".json"))
	for record: Dictionary in manifest.liveries:
		var model: Dictionary = Builder.build(FAMILY, NAN, {}, record.id)
		if model.is_empty():
			quit(1)
			return
		viewport.add_child(model.root)
		var pose: Dictionary = Presentation.prepare(model)
		model.root.basis = pose.alignment
		model.propeller.rotation.z = 0.6
		# Home's fitter reserves space for its sidebar; this thumbnail uses the entire image.
		var box: AABB = Presentation.mesh_bounds(model.root, model.root)
		var target: Vector3 = model.root.global_transform * box.get_center()
		camera.position = target + Vector3(-3.4, 2.0, -4.1)
		camera.look_at(target, Vector3.UP)
		var low := Vector2(INF, INF)
		var high := Vector2(-INF, -INF)
		for corner in range(8):
			var point: Vector3 = camera.global_transform.affine_inverse() * model.root.global_transform * box.get_endpoint(corner)
			low = low.min(Vector2(point.x, point.y))
			high = high.max(Vector2(point.x, point.y))
		camera.size = maxf(high.y - low.y, (high.x - low.x) / (288.0 / 162.0)) * 1.08
		for frame in range(4): await process_frame
		await RenderingServer.frame_post_draw
		var path := output.path_join(str(record.id) + "-" + str(record.sha256) + ".png")
		# Keep an existing valid preview intact if the destination disk fills.
		var temporary := path + ".tmp"
		var err := viewport.get_texture().get_image().save_png(temporary)
		if err == OK: err = DirAccess.rename_absolute(temporary, path)
		if err != OK:
			printerr("Cannot save ", path, ": ", err)
			quit(1)
			return
		print("preview ", record.id)
		model.root.free()
	viewport.free()
	quit(0)

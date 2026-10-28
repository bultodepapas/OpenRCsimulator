## GDU-11b: bounded projection, sloped fallback and receiver isolation.
extends SceneTree
const Effects := preload("res://render/crash/effects.gd")
const Ground := preload("res://render/ground.gd")
var failures := 0

func _initialize() -> void: run.call_deferred()
func check(label: String, condition: bool) -> void:
	print(("ok " if condition else "FAIL ") + label)
	if not condition: failures += 1
func slope(point: Vector3) -> PackedFloat64Array:
	return PackedFloat64Array([point.x * 0.2, 0.0, 0.2])
func draw() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
func luminance(color: Color) -> float:
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722

func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.world_3d = World3D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var fx := Effects.new()
	viewport.add_child(fx)
	fx.ground_sampler = slope
	fx.prepare()
	var native := DisplayServer.get_name() != "headless"
	var decal_support := Effects.supports_decals()
	check("headless renderer retains plane fallback", native or not decal_support)
	check("supported renderers respect eight-per-receiver limit", fx.mark_decals.size() == (8 if decal_support else 0))
	var second := Effects.new()
	viewport.add_child(second)
	second.prepare()
	check("second owner cannot exceed the world's decal budget", second.mark_decals.is_empty())
	second.free()
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0, 17, 13)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.15, 0.2)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.7
	viewport.world_3d.environment = env
	var sun := DirectionalLight3D.new()
	viewport.add_child(sun)
	sun.rotation_degrees = Vector3(-65, -25, 0)
	var receiver := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(17, 17)
	receiver.mesh = plane
	receiver.rotation.z = atan(0.2)
	receiver.layers |= Ground.MARK_RECEIVER_LAYER
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.65, 0.7, 0.45)
	mat.roughness = 1.0
	receiver.material_override = mat
	if "--ground-material" in OS.get_cmdline_user_args():
		receiver.material_override = Ground.grass_material({})
	viewport.add_child(receiver)
	var points: Array[Vector3] = []
	for i in 16: points.append(Vector3((i % 4 - 1.5) * 3, 0, (i / 4 - 1.5) * 3))
	var before: Image
	if native:
		await draw()
		before = viewport.get_texture().get_image()
	var primary := Transform3D.IDENTITY
	for i in 16:
		fx.mark(points[i], Vector3.BACK, 0.8, i == 0)
		if i == 0: primary = fx.marks[0].transform
		if i == 8:
			check("ninth mark uses a visible fallback without dropping primary", fx.stats().marks == 9 and fx.marks[8].visible and fx.marks[0].transform == primary)
	check("sixteen marks keep exactly one representation per slot", fx.marks.filter(func(m): return m.visible).size() + fx.mark_decals.filter(func(d): return d.visible).size() == 16)
	check("fallback aligns to sampled slope", fx.marks[15].basis.y.normalized().is_equal_approx(Vector3(-0.2, 1, 0).normalized()) and absf(fx.marks[15].position.y - slope(points[15])[0]) < 0.02)
	if native:
		await draw()
		var after := viewport.get_texture().get_image()
		check("native image is actual 1080p", after.get_size() == Vector2i(1920, 1080))
		for i in 16:
			var pixel := Vector2i(camera.unproject_position(Vector3(points[i].x, slope(points[i])[0], points[i].z)))
			check("mark %d visibly reaches the shared sloped receiver" % i, luminance(after.get_pixelv(pixel)) < luminance(before.get_pixelv(pixel)) * 0.85)
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--out="):
				var output := arg.trim_prefix("--out=")
				DirAccess.make_dir_recursive_absolute(output)
				check("save native evidence", after.save_png(output.path_join("marks-16-1080.png")) == OK and before.save_png(output.path_join("receiver-1080.png")) == OK)
		check("decal cannot project onto aircraft or wreck layers", fx.mark_decals.all(func(d): return d.cull_mask == Ground.MARK_RECEIVER_LAYER))
		if decal_support:
			receiver.layers = 1
			await draw()
			var excluded := viewport.get_texture().get_image()
			for i in 8:
				var pixel := Vector2i(camera.unproject_position(Vector3(points[i].x, slope(points[i])[0], points[i].z)))
				check("unmarked geometry rejects projected mark %d" % i, absf(luminance(excluded.get_pixelv(pixel)) - luminance(before.get_pixelv(pixel))) < 0.01)
			receiver.layers |= Ground.MARK_RECEIVER_LAYER
		camera.position.x += 2.0
		camera.look_at(Vector3.ZERO)
		await draw()
		var moved := viewport.get_texture().get_image()
		for i in 16:
			var pixel := Vector2i(camera.unproject_position(Vector3(points[i].x, slope(points[i])[0], points[i].z)))
			check("camera motion retains mark %d" % i, luminance(moved.get_pixelv(pixel)) < luminance(mat.albedo_color) * 0.7)
	for i in 48: fx.mark(Vector3(i * 0.1, 0, 0), Vector3.BACK, 0.4)
	check("recycling preserves primary and total cap", fx.stats().marks == 16 and fx.marks[0].transform == primary)
	fx.reset()
	fx.ground_sampler = func(_point: Vector3) -> PackedFloat64Array: return PackedFloat64Array([NAN, NAN, NAN])
	fx.mark(Vector3.ZERO, Vector3.BACK, 0.4)
	check("invalid terrain sample safely uses the finite plane fallback", fx.marks[0].visible and fx.marks[0].transform.is_finite() and (fx.mark_decals.is_empty() or not fx.mark_decals[0].visible))
	fx.reset()
	check("reset clears both representations", fx.stats().marks == 0 and fx.marks.all(func(m): return not m.visible) and fx.mark_decals.all(func(d): return not d.visible))
	viewport.free()
	await process_frame
	print("Ground marks: %d failures" % failures)
	quit(1 if failures else 0)

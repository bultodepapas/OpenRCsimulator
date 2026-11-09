## Native regression: source-material mask confines backlighting to leaves;
## the renderer applies albedo once, and absent direct light adds no energy.
extends SceneTree

const Trees := preload("res://render/treeline.gd")
const Clock := preload("res://render/shader_clock.gd")
var checks := 0
var failures := 0
var viewport: SubViewport
var material: ShaderMaterial
var sun: DirectionalLight3D
var metrics := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("skip tree-card backlight pixels: a native framebuffer is required")
		quit(0)
		return
	Clock.register()
	Clock.update(0.0, Vector3.ZERO)
	root.mode = Window.MODE_MINIMIZED
	RenderingServer.render_loop_enabled = false
	viewport = SubViewport.new()
	viewport.size = Vector2i(192, 192)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.2
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	stage.add_child(world_environment)
	var tree := Trees.build({id = "probe", positions = [[0.0, 0.0, 0.0]]},
		{north = 0.0, east = 0.0, down = 0.0})
	stage.add_child(tree)
	material = tree.get_child(0).multimesh.mesh.surface_get_material(0)
	var height := float(Trees.identity(0.0, 0.0).height)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.current = true
	camera.look_at_from_position(Vector3(0.0, height * 0.5, height * 2.0), Vector3(0.0, height * 0.5, 0.0))
	camera.fov = 36.0
	sun = DirectionalLight3D.new()
	stage.add_child(sun)
	sun.look_at_from_position(Vector3(0.0, height * 0.5, -height * 2.0), Vector3(0.0, height * 0.5, 0.0))
	var default_backlight := float(RenderingServer.shader_get_parameter_default(material.shader.get_rid(), "backlight"))
	_check("production backlight has a bounded nonzero coefficient", default_backlight > 0.0 and default_backlight <= 1.0)
	var bark_off := await _image(0.6, 0.0, 0.0)
	var bark_on := await _image(0.6, 0.0, default_backlight)
	var bark_delta := _maximum_delta(bark_off, bark_on)
	metrics["bark_max_delta_8bit"] = bark_delta
	_check("opaque bark receives no leaf backlight", bark_delta == 0)
	var dark_off := await _image(0.4, 1.0, 0.0)
	var dark_on := await _image(0.4, 1.0, default_backlight)
	var bright_off := await _image(0.8, 1.0, 0.0)
	var bright_on := await _image(0.8, 1.0, default_backlight)
	var dark_delta := _mean_linear(dark_on) - _mean_linear(dark_off)
	var bright_delta := _mean_linear(bright_on) - _mean_linear(bright_off)
	_check("leaves receive direct-light backlighting", dark_delta > 0.00001 and bright_delta > 0.00001)
	var normalized_ratio := (bright_delta / Color(0.8, 0.8, 0.8).srgb_to_linear().r) \
		/ maxf(dark_delta / Color(0.4, 0.4, 0.4).srgb_to_linear().r, 0.00000001)
	metrics["albedo_normalized_backlight_gain_ratio"] = normalized_ratio
	_check("backlight gain does not multiply leaf albedo twice", absf(normalized_ratio - 1.0) < 0.20)
	sun.light_energy = 0.0
	var ambient_off := await _image(0.6, 1.0, 0.0)
	var ambient_on := await _image(0.6, 1.0, default_backlight)
	var ambient_delta := _maximum_delta(ambient_off, ambient_on)
	metrics["ambient_max_delta_8bit"] = ambient_delta
	_check("backlighting adds no energy without direct light", ambient_delta == 0)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			var path := argument.trim_prefix("--out=")
			if not path.is_absolute_path() or FileAccess.file_exists(path):
				_check("output path is new and absolute", false)
				continue
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file == null:
				_check("pixel report can be written", false)
				continue
			file.store_string(JSON.stringify({checks = checks, failures = failures, metrics = metrics,
				shader_sha256 = FileAccess.get_sha256("res://render/treeline.gdshader"),
				godot = Engine.get_version_info(), adapter = RenderingServer.get_video_adapter_name(),
				renderer = RenderingServer.get_current_rendering_method()}, "\t") + "\n")
			file.close()
	viewport.free()
	print("tree-card backlight: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _image(grey: float, foliage: float, backlight: float) -> Image:
	var atlas := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(grey, grey, grey, 1.0))
	var mask := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	mask.fill(Color(foliage, foliage, foliage, 1.0))
	material.set_shader_parameter("atlas", ImageTexture.create_from_image(atlas))
	material.set_shader_parameter("foliage_mask", ImageTexture.create_from_image(mask))
	material.set_shader_parameter("backlight", backlight)
	for _frame in 4:
		await process_frame
		RenderingServer.force_draw(false)
	return viewport.get_texture().get_image()


func _maximum_delta(a: Image, b: Image) -> int:
	var maximum := 0
	for y in a.get_height():
		for x in a.get_width():
			var delta := a.get_pixel(x, y) - b.get_pixel(x, y)
			maximum = maxi(maximum, roundi(maxf(absf(delta.r), maxf(absf(delta.g), absf(delta.b))) * 255.0))
	return maximum


func _mean_linear(image: Image) -> float:
	var sum := 0.0
	for y in image.get_height():
		for x in image.get_width():
			sum += image.get_pixel(x, y).srgb_to_linear().r
	return sum / float(image.get_width() * image.get_height())


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)

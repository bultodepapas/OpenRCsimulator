## Native GPU regression for the production ridge material's encoded color controls.
## The test-only shader disables lighting and fog; its fragment and renderer branches stay intact.
extends SceneTree

const SHADER_PATH := "res://render/landscape_upgrade/ridge_haze.gdshader"
const VIEW_SIZE := Vector2i(800, 800)
const TERRAIN_CENTER_Z := -5100.0
const TOLERANCE := 3.5 / 255.0
const CASES := [
	{"name": "grass_low_clamp", "biome": Color(0, 0, 0), "grass": Color(0.1, 0.1, 0.1), "stone": Color(0.3, 0.3, 0.3), "detail": 1.0, "expected": Color(0.0935, 0.132, 0.05225)},
	{"name": "grass_mid_gray", "biome": Color(0, 0, 0), "grass": Color(0.25, 0.25, 0.25), "stone": Color(0.3, 0.3, 0.3), "detail": 1.0, "expected": Color(0.1275, 0.18, 0.07125)},
	{"name": "grass_high_clamp", "biome": Color(0, 0, 0), "grass": Color(0.75, 0.75, 0.75), "stone": Color(0.3, 0.3, 0.3), "detail": 1.0, "expected": Color(0.2465, 0.348, 0.13775)},
	{"name": "grass_rgb_luminance", "biome": Color(0, 0, 0), "grass": Color(0.2, 0.4, 0.6), "stone": Color(0.3, 0.3, 0.3), "detail": 1.0, "expected": Color(0.18513, 0.26136, 0.103455)},
	{"name": "blue_biome_meadow", "biome": Color(0, 0, 1), "grass": Color(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0), "stone": Color(0.3, 0.3, 0.3), "detail": 1.0, "expected": Color(0.245, 0.255, 0.14)},
	{"name": "green_biome_vegetation", "biome": Color(0, 1, 0), "grass": Color(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0), "stone": Color(0.3, 0.3, 0.3), "detail": 1.0, "expected": Color(0.086, 0.164, 0.071)},
	{"name": "stone_low_clamp", "biome": Color(1, 0, 0), "grass": Color(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0), "stone": Color(0.1, 0.1, 0.1), "detail": 1.0, "expected": Color(0.123, 0.12, 0.108)},
	{"name": "stone_mid_gray", "biome": Color(1, 0, 0), "grass": Color(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0), "stone": Color(0.3, 0.3, 0.3), "detail": 1.0, "expected": Color(0.1599, 0.156, 0.1404)},
	{"name": "stone_high_clamp", "biome": Color(1, 0, 0), "grass": Color(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0), "stone": Color(0.9, 0.9, 0.9), "detail": 1.0, "expected": Color(0.287, 0.28, 0.252)},
	{"name": "rock_cover_blend", "biome": Color(0.5, 0, 0), "grass": Color(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0), "stone": Color(0.3, 0.3, 0.3), "detail": 1.0, "expected": Color(0.164706, 0.195968, 0.118798)},
	{"name": "detail_alpha", "biome": Color(0, 0, 0), "grass": Color(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0), "stone": Color(0.3, 0.3, 0.3), "detail": 0.5, "expected": Color(0.085, 0.12, 0.0475)},
]


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("requires a native GPU renderer; headless execution is not a pass")
		return
	_run.call_deferred()


func _run() -> void:
	var source := FileAccess.get_file_as_string(SHADER_PATH)
	const RENDER_MODE := "render_mode cull_back;"
	if source.is_empty() or not source.contains(RENDER_MODE):
		_fail("could not derive the isolated test shader from the production ridge shader")
		return
	var test_shader := Shader.new()
	test_shader.code = source.replace(RENDER_MODE, "render_mode cull_back, unshaded, fog_disabled;")
	var viewport := SubViewport.new()
	viewport.size = VIEW_SIZE
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.04, 0.05, 0.07)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.tonemap_exposure = 1.0
	environment.fog_enabled = false
	var world := Node3D.new()
	viewport.add_child(world)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	world.add_child(world_environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 24.0
	camera.far = 100.0
	camera.position = Vector3(0, 26, TERRAIN_CENTER_Z)
	world.add_child(camera)
	camera.look_at(Vector3(0, 0, TERRAIN_CENTER_Z), Vector3(0, 0, -1))
	camera.current = true
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.3, 1.3)
	var samples: Array[Dictionary] = []
	for index in CASES.size():
		var item: Dictionary = CASES[index]
		var z := TERRAIN_CENTER_Z + (float(index) - float(CASES.size() - 1) * 0.5) * 2.2
		var shader_material := ShaderMaterial.new()
		shader_material.shader = test_shader
		shader_material.set_shader_parameter("relief", _texture(Color(0.5, 0.5, 1.0, item.detail)))
		shader_material.set_shader_parameter("habitat", _texture(item.biome))
		shader_material.set_shader_parameter("grass_rock", _texture(item.grass))
		shader_material.set_shader_parameter("rocks", _texture(item.stone))
		var shader_mesh := _panel(plane, shader_material, Vector3(-2, 0, z))
		world.add_child(shader_mesh)
		var reference := StandardMaterial3D.new()
		reference.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		# The contract is the accepted GLES3 cubic, not exact IEC sRGB. They
		# differ visibly near black. StandardMaterial3D decodes sRGB on RD;
		# encode the expected legacy-linear value for that independent path.
		var display_reference := _legacy_linear(item.expected).linear_to_srgb()
		reference.albedo_color = item.expected if RenderingServer.get_current_rendering_method() == "gl_compatibility" else display_reference
		var reference_mesh := _panel(plane, reference, Vector3(2, 0, z))
		world.add_child(reference_mesh)
		samples.append({"case": item, "display_reference": display_reference, "shader_position": shader_mesh.position,
			"reference_position": reference_mesh.position})
	for _frame in 4:
		await process_frame
		RenderingServer.force_draw(false)
	var image := viewport.get_texture().get_image()
	if image.is_empty():
		_fail("native viewport returned no pixels")
		return
	var failures := 0
	for sample: Dictionary in samples:
		var actual := _sample(image, camera, sample.shader_position)
		var expected := _sample(image, camera, sample.reference_position)
		# Reject empty/background samples even if both columns accidentally miss
		# their panels; agreement alone would let a broken camera pass.
		if _rgb_error(expected, sample.display_reference) > 0.02:
			failures += 1
			printerr("ridge reference panel not resolved: %s" % sample.case.name)
		var error := _rgb_error(actual, expected)
		if error > TOLERANCE:
			failures += 1
			printerr("ridge color mismatch %s: max %.2f/255 (shader %s, reference %s)" % [
				sample.case.name, error * 255.0, actual, expected])
	viewport.queue_free()
	await process_frame
	if failures > 0:
		_fail("%d of %d palette cases exceeded %.1f/255" % [failures, CASES.size(), TOLERANCE * 255.0])
	else:
		print("ridge color GPU regression passed: %s, %d cases, %.1f/255 tolerance" % [
			RenderingServer.get_current_rendering_method(), CASES.size(), TOLERANCE * 255.0])
		quit()


func _panel(mesh: Mesh, material: Material, position: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	return instance


func _texture(color: Color) -> ImageTexture:
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.set_pixel(0, 0, color)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _sample(image: Image, camera: Camera3D, world_position: Vector3) -> Color:
	var point := camera.unproject_position(world_position)
	return image.get_pixel(clampi(roundi(point.x), 0, image.get_width() - 1),
		clampi(roundi(point.y), 0, image.get_height() - 1))


func _rgb_error(left: Color, right: Color) -> float:
	return maxf(absf(left.r - right.r), maxf(absf(left.g - right.g), absf(left.b - right.b)))


func _legacy_linear(value: Color) -> Color:
	var result := Color(0, 0, 0, 1)
	for channel in 3:
		var s: float = value[channel]
		result[channel] = s * (s * (s * 0.305306011 + 0.682171111) + 0.012522878)
	return result


func _fail(message: String) -> void:
	printerr("ridge color GPU regression: " + message)
	quit(1)

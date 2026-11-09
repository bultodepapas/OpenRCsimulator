## L8a-R4: source Backlight parity, opt-in variant isolation and one-family treatment.
extends SceneTree

const Library := preload("res://scenery/imported_vegetation.gd")
const Clock := preload("res://render/shader_clock.gd")
var checks := 0
var failures := 0
var pixels: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Clock.register()
	Clock.update(0.0, Vector3.ZERO)
	_test_production_scope()
	_test_material_guard()
	if DisplayServer.get_name() == "headless":
		print("skip native backlight pixels: headless renderer draws nothing")
	else:
		await _test_pixels()
		_check("all 30 native pixel comparisons executed", pixels.size() == 30)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			var file := FileAccess.open(arg.trim_prefix("--report="), FileAccess.WRITE)
			if file == null:
				_check("pixel report opens", false)
			else:
				file.store_string(JSON.stringify({checks = checks, failures = failures, pixels = pixels,
					renderer = RenderingServer.get_current_rendering_method(),
					adapter = RenderingServer.get_video_adapter_name()}, "\t") + "\n")
	print("tree backlight: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _test_production_scope() -> void:
	for id in ["landscapelab_fagus", "landscapelab_quercus", "landscapelab_quercus2", "landscapelab_pine", "maple_tree"]:
		for part in Library.get_parts(id):
			for surface in (part.materials as Array).size():
				var material: BaseMaterial3D = part.materials[surface]
				var expected: bool = id == "landscapelab_fagus" and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				_check("%s surface %d backlight scope" % [id, surface], material.backlight_enabled == expected)
				if expected:
					_check("Fagus uses neutral bounded color without an extra map", material.backlight == Library.FAGUS_FOLIAGE_BACKLIGHT
						and material.get_texture(BaseMaterial3D.TEXTURE_BACKLIGHT) == null)
					var source := (part.mesh as Mesh).surface_get_material(surface) as BaseMaterial3D
					_check("downloaded Fagus material stays immutable", not source.backlight_enabled)


func _test_material_guard() -> void:
	var material := StandardMaterial3D.new()
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.backlight_enabled = true
	_check("backlight is supported", Library._tree_material_support_reason(material).is_empty())
	material.subsurf_scatter_enabled = true
	_check("subsurface scattering stays rejected", Library._tree_material_support_reason(material).contains("subsurface scattering"))
	material.subsurf_scatter_enabled = false
	material.subsurf_scatter_transmittance_enabled = true
	_check("subsurface transmittance stays rejected", Library._tree_material_support_reason(material).contains("transmittance"))
	material.subsurf_scatter_transmittance_enabled = false
	material.uv1_triplanar = true
	_check("unsupported texture projection stays rejected", Library._tree_material_support_reason(material).contains("triplanar"))
	for key in ["double_repeat", "back_repeat", "double_clamp"]:
		var shader := load(Library.TREE_WIND_SHADER_PATHS[key]) as Shader
		_check("feature-off variant stays compiled without backlight", not shader.code.contains("#define TREE_WIND_BACKLIGHT"))


func _test_pixels() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(128, 128)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.1
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.5
	camera.position = Vector3(0, 0, 3)
	camera.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation.y = PI
	viewport.add_child(sun)
	var instance := MeshInstance3D.new()
	instance.mesh = QuadMesh.new()
	(instance.mesh as QuadMesh).size = Vector2(2, 2)
	viewport.add_child(instance)
	var image := Image.create(16, 16, true, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			image.set_pixel(x, y, Color(float(x) / 64.0, float(y) / 64.0, 0.12, 1))
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	for key in ["double_repeat", "back_repeat", "double_clamp"]:
		for mode in ["off", "missing", "color", "texture", "combined"]:
			var source := StandardMaterial3D.new()
			source.cull_mode = BaseMaterial3D.CULL_BACK if key == "back_repeat" else BaseMaterial3D.CULL_DISABLED
			source.texture_repeat = key != "double_clamp"
			source.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			source.albedo_color = Color(0.32, 0.54, 0.18)
			source.roughness = 0.85
			source.uv1_scale = Vector3(1.3, 0.7, 1)
			source.uv1_offset = Vector3(-0.2, 0.1, 0)
			source.backlight_enabled = mode != "off"
			source.backlight = Color(0.35, 0.2, 0.4) if mode in ["off", "color", "combined"] else Color.BLACK
			source.backlight_texture = texture if mode in ["off", "texture", "combined"] else null
			var wind := Library._tree_wind_material(source, AABB(Vector3.ZERO, Vector3.ONE), 0.13)
			var expected_key: String = key + ("_backlight" if source.backlight_enabled else "")
			_check("%s/%s selects only its feature variant" % [key, mode], wind.shader.resource_path == Library.TREE_WIND_SHADER_PATHS[expected_key])
			for energy in [0.0, 1.0]:
				sun.light_energy = energy
				instance.material_override = source
				var reference := await _frame(viewport)
				instance.material_override = wind
				var candidate := await _frame(viewport)
				var error := 0
				var a := reference.get_data()
				var b := candidate.get_data()
				for i in a.size(): error = maxi(error, absi(int(a[i]) - int(b[i])))
				pixels.append({variant = key, mode = mode, direct_light = energy, max_channel_error = error})
				_check("%s/%s direct=%s source/wind pixel parity" % [key, mode, energy], error == 0)
	viewport.free()


func _frame(viewport: SubViewport) -> Image:
	for _i in 4:
		await process_frame
		await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

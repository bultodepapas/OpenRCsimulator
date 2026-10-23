extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	RenderingServer.render_loop_enabled = false
	var results := []
	for hdr: bool in [false, true]:
		for exposure: float in [1.0, 2.0]:
			var viewport := SubViewport.new()
			viewport.size = Vector2i(128, 128)
			viewport.use_hdr_2d = hdr
			viewport.own_world_3d = true
			viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			root.add_child(viewport)
			var env := WorldEnvironment.new()
			env.environment = Environment.new()
			env.environment.background_mode = Environment.BG_COLOR
			env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
			env.environment.tonemap_exposure = exposure
			viewport.add_child(env)
			var plane := MeshInstance3D.new()
			plane.mesh = QuadMesh.new()
			var shader := Shader.new()
			shader.code = "shader_type spatial; render_mode unshaded; void fragment() { ALBEDO = vec3(2.0, 0.5, 0.1); }"
			var material := ShaderMaterial.new()
			material.shader = shader
			plane.material_override = material
			viewport.add_child(plane)
			var camera := Camera3D.new()
			camera.position.z = 2.0
			viewport.add_child(camera)
			camera.make_current()
			for i in 12:
				await process_frame
				RenderingServer.force_draw(false)
			var picture := viewport.get_texture().get_image()
			var pixel := picture.get_pixel(64, 64)
			results.append({hdr = hdr, exposure = exposure, pixel = [pixel.r, pixel.g, pixel.b], image_format = picture.get_format()})
			viewport.free()
			await process_frame
	print("HDR probe: ", JSON.stringify(results))
	quit()

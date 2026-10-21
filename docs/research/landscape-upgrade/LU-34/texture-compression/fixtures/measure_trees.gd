extends SceneTree
# Cold-load two downloaded trees, report texture formats/bytes, renderer texture memory and fixed renders.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(900, 900)
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.72, 0.82)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.75, 0.85)
	env.environment.ambient_light_energy = 0.6
	viewport.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	viewport.add_child(sun)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.current = true
	await process_frame
	RenderingServer.force_draw(false)
	var base_mem := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
	var report := {}
	var x := 0.0
	for path in ["res://trees/quercus/quercus.glb", "res://trees/pine/pine_joined.glb"]:
		var t0 := Time.get_ticks_usec()
		var scene := load(path) as PackedScene
		var load_ms := (Time.get_ticks_usec() - t0) / 1000.0
		var node := scene.instantiate() as Node3D
		viewport.add_child(node)
		var aabb := AABB()
		var textures := {}
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			var m: MeshInstance3D = mi
			aabb = m.get_aabb() if aabb.size == Vector3.ZERO else aabb.merge(m.get_aabb())
			for s in m.mesh.get_surface_count():
				var mat := m.mesh.surface_get_material(s) as BaseMaterial3D
				for prop in ["albedo_texture", "normal_texture", "roughness_texture"]:
					var tex: Texture2D = mat.get(prop)
					if tex and not textures.has(tex.resource_path):
						var img := tex.get_image()
						textures[tex.resource_path.get_file()] = {format = img.get_format(), bytes = img.get_data_size(), mips = img.get_mipmap_count()}
		var scale := 10.0 / aabb.size.y
		node.scale = Vector3.ONE * scale
		node.position = Vector3(x, 0, 0)
		report[path.get_file()] = {load_ms = load_ms, textures = textures}
		for view in [["front", Vector3(0, 5, 18)], ["side", Vector3(18, 5, 0)], ["under", Vector3(0, 1, 7)]]:
			camera.fov = 45 if view[0] != "under" else 70
			camera.look_at_from_position(node.position + view[1], node.position + Vector3(0, 5, 0))
			for _i in 3:
				await process_frame
				RenderingServer.force_draw(false)
			viewport.get_texture().get_image().save_png(out.path_join("%s_%s.png" % [path.get_file().get_basename(), view[0]]))
		node.visible = false
		x += 60.0
	report["renderer_texture_mem_added_bytes"] = Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) - base_mem
	var f := FileAccess.open(out.path_join("report.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  ", true))
	f.close()
	print("MEASURE DONE")
	quit(0)

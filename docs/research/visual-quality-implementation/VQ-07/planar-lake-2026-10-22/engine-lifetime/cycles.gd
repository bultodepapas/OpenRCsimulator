extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var count := 1
	var with_probe := "--probe" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cycles="):
			count = int(arg.trim_prefix("--cycles="))
	for cycle in range(count):
		await _cycle(with_probe)
	print("isolated worlds complete cycles=", count, " probe=", with_probe)
	quit()

func _cycle(with_probe: bool) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(320, 180)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = Sky.new()
	environment.sky.sky_material = ProceduralSkyMaterial.new()
	var holder := WorldEnvironment.new()
	holder.environment = environment
	viewport.add_child(holder)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0, 2, 5)
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	viewport.add_child(box)
	if with_probe:
		var probe := ReflectionProbe.new()
		probe.size = Vector3(20, 20, 20)
		viewport.add_child(probe)
	for frame in range(40):
		await process_frame
	viewport.free()
	environment = null
	for frame in range(10):
		await process_frame

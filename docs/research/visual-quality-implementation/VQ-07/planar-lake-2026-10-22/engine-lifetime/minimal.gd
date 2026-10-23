extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var with_probe := "--probe" in OS.get_cmdline_user_args()
	var world := Node3D.new()
	root.add_child(world)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = Sky.new()
	environment.sky.sky_material = ProceduralSkyMaterial.new()
	var holder := WorldEnvironment.new()
	holder.environment = environment
	world.add_child(holder)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 2, 5)
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	world.add_child(box)
	if with_probe:
		var probe := ReflectionProbe.new()
		probe.size = Vector3(20, 20, 20)
		world.add_child(probe)
	for frame in range(40):
		await process_frame
	world.free()
	environment = null
	for frame in range(10):
		await process_frame
	print("minimal lifetime complete probe=", with_probe)
	quit()

extends SceneTree
## F4U-18: render cost and appearance of one Corsair GLB in isolation, Compatibility renderer, from fixed cameras.
## Sky, sun with the flight scene's PSSM 2-split shadows (300 m), MSAA 2x, a ground plane and the model with its
## lowest vertex on the ground. Per camera: warm-up, then frame times (vsync off), the viewport's measured CPU/GPU
## render time, visible and shadow draw calls and primitives, and one screenshot. Not the flight scene: scenery,
## HUD and simulation cost are absent, so the results are the model's own cost.
##   Godot_v4.7.2-stable_win64_console.exe --rendering-driver opengl3 --resolution 1920x1080 --path <bench> \
##     --script res://bench.gd -- --model=res://models/<name>.glb --out=<new .json> [--shots=<dir>] [--clay] [--frames=N]
const CAMERAS := "res://cameras.json"
var model_path := ""
var out_path := ""
var shots := ""
var clay := false
var frames := 300
var warmup := 90
var cameras: Array = []
var camera: Camera3D
var results := []
var info := {}


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--model="): model_path = argument.trim_prefix("--model=")
		elif argument.begins_with("--out="): out_path = argument.trim_prefix("--out=")
		elif argument.begins_with("--shots="): shots = argument.trim_prefix("--shots=")
		elif argument == "--clay": clay = true
		elif argument.begins_with("--frames="): frames = int(argument.trim_prefix("--frames="))
	if model_path.is_empty() or out_path.is_empty() or FileAccess.file_exists(out_path):
		printerr("F4U-18 bench: pass --model=<res://...glb> and --out=<new .json>")
		quit(2)
		return
	if not shots.is_empty():
		DirAccess.make_dir_recursive_absolute(shots)
	cameras = JSON.parse_string(FileAccess.get_file_as_string(CAMERAS))
	call_deferred("_run")


func _environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = env
	root.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 300.0
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2000.0, 2000.0)
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color(0.32, 0.40, 0.26)
	grass.roughness = 0.95
	plane.material = grass
	ground.mesh = plane
	root.add_child(ground)
	camera = Camera3D.new()
	camera.near = 0.05
	camera.far = 4000.0
	root.add_child(camera)
	camera.make_current()


func _meshes(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_meshes(child, out)


func _run() -> void:
	_environment()
	var t0 := Time.get_ticks_usec()
	var scene: PackedScene = load(model_path)
	var model: Node3D = scene.instantiate()
	root.add_child(model)
	var load_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var meshes := []
	_meshes(model, meshes)
	var box := AABB()
	var triangles := 0
	var surfaces := 0
	var gray := StandardMaterial3D.new()
	gray.albedo_color = Color(0.45, 0.45, 0.44)
	gray.roughness = 0.55
	for index in meshes.size():
		var instance: MeshInstance3D = meshes[index]
		var mesh_box: AABB = instance.global_transform * instance.get_aabb()
		box = mesh_box if index == 0 else box.merge(mesh_box)
		var mesh: Mesh = instance.mesh
		surfaces += mesh.get_surface_count()
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			triangles += (indices.size() if not indices.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		if clay:
			instance.material_override = gray
	model.position.y -= box.position.y
	info = { model = model_path, clay = clay, load_ms = load_ms, mesh_instances = meshes.size(), surfaces = surfaces,
		triangles = triangles, aabb_size = [box.size.x, box.size.y, box.size.z],
		resolution = [root.size.x, root.size.y], adapter = RenderingServer.get_video_adapter_name(),
		driver = RenderingServer.get_current_rendering_driver_name(), godot = Engine.get_version_info().string }
	print("F4U-18 bench ", JSON.stringify(info))
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var center := box.get_center() - Vector3(0.0, box.position.y, 0.0)
	for spec in cameras:
		var target := center + _vec(spec.target)
		camera.fov = spec.fov
		camera.look_at_from_position(center + _vec(spec.position), target)
		for i in warmup:
			await process_frame
		var times := PackedFloat64Array()
		var cpu := 0.0
		var gpu := 0.0
		var last := Time.get_ticks_usec()
		for i in frames:
			await process_frame
			var now := Time.get_ticks_usec()
			times.append((now - last) / 1000.0)
			last = now
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		times.sort()
		var row := { camera = spec.name, distance_m = _vec(spec.position).distance_to(_vec(spec.target)),
			frame_ms_median = times[times.size() / 2], frame_ms_p95 = times[int(times.size() * 0.95)],
			render_cpu_ms = cpu / frames, render_gpu_ms = gpu / frames,
			draw_calls = RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
			primitives = RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
			shadow_draw_calls = RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
			shadow_primitives = RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME) }
		results.append(row)
		print("F4U-18 camera ", JSON.stringify(row))
		if not shots.is_empty():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(shots.path_join(spec.name + ".png"))
	info.video_mem_mb = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0
	info.texture_mem_mb = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0
	info.buffer_mem_mb = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED) / 1048576.0
	info.cameras = results
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(info, "\t"))
	file.close()
	quit(0)


func _vec(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])

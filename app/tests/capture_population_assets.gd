## LU-21 native asset review: isolated fixed-light views, real renderer LOD counters,
## and deterministic simulation-clock pause/reset images. Never a frame-time benchmark.
extends SceneTree
const Population = preload("res://scenery/population.gd")
const Clock = preload("res://render/shader_clock.gd")
var args := {}

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=", true, 1)
		args[pair[0]] = pair[1] if pair.size() > 1 else "on"
	_run.call_deferred()

func _run() -> void:
	Clock.register()
	root.size = Vector2i(1280, 720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var out := str(args.get("out", "user://population-review"))
	DirAccess.make_dir_recursive_absolute(out)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#44494f")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("#a9b6c4")
	env.environment.ambient_light_energy = 0.7
	world.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-38.0, -30.0, 0.0)
	light.light_energy = 1.1
	world.add_child(light)
	var camera := Camera3D.new()
	camera.fov = 38.0
	camera.near = 0.05
	camera.far = 1500.0
	world.add_child(camera)
	camera.current = true
	var report := {engine = Engine.get_version_info(), adapter = RenderingServer.get_video_adapter_name(),
		renderer = "gl_compatibility", width = root.size.x, height = root.size.y, assets = {}, motion = {}}
	# Cars by catalog id; people by every SC-HUM-07 outfit variant ("<pose>/<outfit>").
	var subjects: Array = [["car_sedan", "sedan"], ["car_hatch", "hatch"], ["car_suv", "crossover"]]
	for key: String in Population.human_assets():
		subjects.append(["person_" + Population.pose_of(key), key])
	for subject: Array in subjects:
		var id: String = subject[0]
		var asset: String = subject[1]
		if args.has("assets") and not str(args.assets).split(",").has(asset):
			continue
		var source: Dictionary = Population._source(asset)
		var batches := {}
		Population.queue_asset(batches, asset, id, Transform3D.IDENTITY, 42, source.bounds.size)
		var population := Population.build(batches)
		world.add_child(population)
		var distances := {}
		for distance: float in [5.0, 15.0, 40.0, 120.0]:
			camera.look_at_from_position(Vector3(distance * 0.35, 1.6, -distance), Vector3(0.0, source.bounds.size.y * 0.5, 0.0))
			Clock.update(0.0)
			await _settle()
			var filename := "%s_%dm.png" % [asset.replace("/", "_"), int(distance)]
			root.get_texture().get_image().save_png(out.path_join(filename))
			distances[str(int(distance))] = {image = filename,
				draws = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				primitives = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}
		report.assets[asset] = distances
		if id.begins_with("person_"):
			camera.look_at_from_position(Vector3(0.7, 1.4, -3.2), Vector3(0.0, source.bounds.size.y * 0.55, 0.0))
			for node: MultiMeshInstance3D in population.get_children():
				node.multimesh.set_instance_custom_data(0, Color(0.2, 1.0, 0.3, 0.0))
			var hashes := {}
			for entry: Array in [["start", 0.0], ["moving", 7.0], ["paused", 7.0], ["reset", 0.0], ["wrapped", 1024.0]]:
				Clock.update(float(entry[1]))
				await _settle()
				var img := root.get_texture().get_image()
				var file := "%s_%s.png" % [asset.replace("/", "_"), entry[0]]
				img.save_png(out.path_join(file))
				var hash := HashingContext.new()
				hash.start(HashingContext.HASH_SHA256)
				hash.update(img.get_data())
				hashes[entry[0]] = hash.finish().hex_encode()
			report.motion[asset] = {hashes = hashes, changed = hashes.start != hashes.moving,
				pause_equal = hashes.moving == hashes.paused, reset_equal = hashes.start == hashes.reset,
				wrap_equal = hashes.start == hashes.wrapped}
		population.free()
	var file := FileAccess.open(out.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	world.free()
	print("LU21 asset native review complete: ", out)
	quit()

func _settle() -> void:
	for i in 8:
		await process_frame
		await RenderingServer.frame_post_draw

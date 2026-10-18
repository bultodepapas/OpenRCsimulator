## Tree-plan evidence using production assets and builders. No flight simulation.
## Run externally against an imported baseline/candidate app with --out=<new folder>.
extends SceneTree

const Library = preload("res://scenery/imported_vegetation.gd")
const Field = preload("res://render/field.gd")
const Loader = preload("res://data/field_loader.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const Clock = preload("res://render/shader_clock.gd")
const Frames = preload("res://render/frames.gd")
const Postcards = preload("res://scenery/postcards.gd")

var args: Dictionary = {}
var viewport: SubViewport
var stage: Node3D
var camera: Camera3D
var content: Node3D
var output: String
var views: Array[Dictionary] = []
var report: Dictionary = {format = "openrc-tree-quality v1", captures = [], samples = [], complete = false}


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		args[pair[0]] = pair[1] if pair.size() == 2 else "on"
	_run.call_deferred()


func _run() -> void:
	output = str(args.get("out", ""))
	if output.is_empty() or DisplayServer.get_name() == "headless":
		_fail("--out and a real Compatibility framebuffer are required")
		return
	if DirAccess.dir_exists_absolute(output) and not DirAccess.get_files_at(output).is_empty():
		_fail("output must be new or empty")
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		_fail("cannot create output")
		return
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		_fail("Compatibility is required")
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	RenderingServer.render_loop_enabled = false
	Clock.register()
	Clock.update(0.0, Vector3.ZERO)
	viewport = SubViewport.new()
	viewport.size = Vector2i(int(args.get("width", "1280")), int(args.get("height", "720")))
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	stage = Node3D.new()
	viewport.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Atmosphere.environment()
	Atmosphere.update_clouds(env.environment, 0.0)
	stage.add_child(env)
	Atmosphere.create_sun(stage)
	camera = Camera3D.new()
	camera.near = 0.1
	camera.far = 21000.0
	stage.add_child(camera)
	camera.current = true
	var mode := str(args.get("mode", "field"))
	if mode == "gallery":
		if not _gallery():
			return
	elif mode == "field":
		if not _field():
			return
	else:
		_fail("mode must be field or gallery")
		return
	content.process_mode = Node.PROCESS_MODE_DISABLED
	if str(args.get("tree_shadows", "on")) == "off":
		_disable_tree_shadows(content)
	report["mode"] = mode
	report["arguments"] = args
	report["renderer"] = RenderingServer.get_current_rendering_method()
	report["adapter"] = RenderingServer.get_video_adapter_name()
	report["api"] = RenderingServer.get_video_adapter_api_version()
	report["godot"] = Engine.get_version_info().string
	report["viewport"] = [viewport.size.x, viewport.size.y]
	report["msaa"] = "4x"
	report["scope"] = "Prescribed static rendering; no aircraft physics, active-flight ratio or pilot acceptance."
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
	var duration := float(args.get("profile", "0"))
	if duration > 0.0:
		await _profile(duration)
	else:
		for view in views:
			await _capture(view, str(view.id), 0.0, Vector3.ZERO)
		if mode == "gallery":
			var view: Dictionary = views[0]
			for state in [
				["wind_start", 0.0, Vector3(5, 0, 0)],
				["wind_one", 1.0, Vector3(5, 0, 0)],
				["wind_repeat", 1.0, Vector3(5, 0, 0)],
				["wind_wrap", 1024.0, Vector3(5, 0, 0)],
				["wind_reverse", 1.0, Vector3(-5, 0, 0)],
			]:
				await _capture(view, state[0], state[1], state[2])
	report.complete = true
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	if file == null:
		_fail("cannot save report")
		return
	file.store_string(JSON.stringify(report, "\t", true) + "\n")
	file.close()
	viewport.queue_free()
	print("TREE QUALITY COMPLETE: ", output)
	quit(0)


func _field() -> bool:
	OS.set_environment("OPENRC_SCENERY", "on")
	OS.set_environment("OPENRC_SCENERY_AUDIO", "off")
	OS.set_environment("OPENRC_SCENERY_BIRDS", "off")
	var path := str(args.get("field", Loader.DEFAULT_PATH))
	var loaded: Dictionary = Loader.load_from(path)
	if not loaded.ok:
		_fail(str(loaded.errors))
		return false
	content = Field.build(loaded.field)
	stage.add_child(content)
	report["field_sha256"] = FileAccess.get_sha256(path)
	report["vegetation_catalog_sha256"] = FileAccess.get_sha256(Library.CATALOG_PATH)
	for id in ["pilot_north", "car_park", "postcard_meadow", "aerial_overview"]:
		var source: Dictionary = Postcards.VIEWS[id]
		views.append({id = id, eye = Frames.ned_to_render(source.eye), at = Frames.ned_to_render(source.at), fov = source.fov})
	return true


func _gallery() -> bool:
	var ids := str(args.get("ids", "common_tree_1,common_tree_3,pine_1")).split(",")
	var batches: Dictionary = {}
	var selected: Array[Dictionary] = []
	for index in ids.size():
		var id := ids[index]
		var asset: Dictionary = Library.get_asset(id)
		if asset.is_empty():
			_fail("missing gallery asset " + id)
			return false
		var origin := Vector3(index * 24.0, 0, 0)
		var placement := Library.fit_to_height(id, 10.0, Transform3D(Basis.IDENTITY, origin))
		Library.queue(batches, id, placement, 101 + index, id)
		selected.append(asset)
		views.append({id = id, eye = origin + Vector3(0, 5, 20), at = origin + Vector3(0, 5, 0), fov = 36.0})
	var options := {tree_wind = str(args.get("wind", "off")) == "on", tree_cell_size_m = float(args.get("cell", "0"))}
	if options.tree_wind or options.tree_cell_size_m > 0.0:
		# Dynamic call keeps the external probe usable against the unmodified baseline API.
		content = Library.new().call("build", batches, false, options)
	else:
		content = Library.build(batches)
	stage.add_child(content)
	report["assets"] = selected
	report["batch_count"] = content.get_child_count()
	report["vegetation_catalog_sha256"] = FileAccess.get_sha256(Library.CATALOG_PATH)
	var target := Vector3(0, 5, 0)
	views.append({id = "back", eye = Vector3(0, 5, -20), at = target, fov = 36.0})
	views.append({id = "underside", eye = Vector3(0, 0.5, 12), at = target, fov = 50.0})
	views.append({id = "overhead", eye = Vector3(0, 25, 0.01), at = target, fov = 40.0})
	return true


func _disable_tree_shadows(node: Node) -> void:
	if node is MultiMeshInstance3D and (str(node.name).contains("tree") or str(node.name).contains("pine")):
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_tree_shadows(child)


func _place(view: Dictionary) -> void:
	camera.fov = float(view.fov)
	camera.look_at_from_position(view.eye, view.at)


func _frame() -> void:
	await process_frame
	RenderingServer.force_draw(false)


func _counters() -> Dictionary:
	var rid := viewport.get_viewport_rid()
	return {
		draws = RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		primitives = RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
		shadow_draws = RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
	}


func _capture(view: Dictionary, id: String, clock: float, wind: Vector3) -> void:
	_place(view)
	Clock.update(clock, wind)
	for _index in 4:
		await _frame()
	var path := output.path_join(id + ".png")
	var image := viewport.get_texture().get_image()
	if image.is_empty() or image.save_png(path) != OK:
		_fail("empty/failed capture " + id)
		return
	report.captures.append({id = id, sha256 = FileAccess.get_sha256(path), counters = _counters(),
		clock = clock, wind = [wind.x, wind.y, wind.z], eye = [view.eye.x, view.eye.y, view.eye.z], fov = view.fov})


func _profile(duration: float) -> void:
	var view: Dictionary = views[0]
	for candidate in views:
		if candidate.id == str(args.get("view", "")):
			view = candidate
	_place(view)
	var warmup := float(args.get("warmup", "10"))
	var started := Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - started) / 1000000.0 < warmup:
		await _frame()
	started = Time.get_ticks_usec()
	var previous := started
	while float(Time.get_ticks_usec() - started) / 1000000.0 < duration:
		Clock.update(float(Time.get_ticks_usec() - started) / 1000000.0, Vector3(5, 0, 0))
		await _frame()
		var now := Time.get_ticks_usec()
		report.samples.append({wall_ms = float(now - previous) / 1000.0,
			cpu_ms = RenderingServer.viewport_get_measured_render_time_cpu(viewport.get_viewport_rid()),
			gpu_ms = RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid())})
		previous = now
	report["duration_s"] = float(Time.get_ticks_usec() - started) / 1000000.0
	report["warmup_s"] = warmup
	report["view"] = view.id
	report["counters"] = _counters()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

## L8a-R4: controlled lighting for one production broadleaf, static and qualified wind.
## Native Compatibility; --out=<new absolute folder>. Images are diagnostic, not flight acceptance.
extends SceneTree

const Library := preload("res://scenery/imported_vegetation.gd")
const Clock := preload("res://render/shader_clock.gd")
const ASSET := "landscapelab_fagus"
var output := ""
var viewport: SubViewport
var stage: Node3D
var sun: DirectionalLight3D
var report := {complete = false, captures = []}


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): output = argument.trim_prefix("--out=")
	_run.call_deferred()


func _run() -> void:
	if output.is_empty() or not output.is_absolute_path() or DisplayServer.get_name() == "headless":
		_fail("native framebuffer and --out=<new absolute folder> required")
		return
	if DirAccess.dir_exists_absolute(output) and not DirAccess.get_files_at(output).is_empty():
		_fail("refusing to overwrite output")
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		_fail("cannot create output")
		return
	Clock.register()
	Clock.update(0.0, Vector3.ZERO)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	stage = Node3D.new()
	viewport.add_child(stage)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.06, 0.06, 0.06)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.2
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	stage.add_child(world_environment)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	stage.add_child(sun)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.look_at_from_position(Vector3(0, 7.5, 26), Vector3(0, 7.5, 0))
	camera.fov = 36.0
	camera.current = true
	for wind in [false, true]:
		var batches := {}
		Library.queue(batches, ASSET, Library.fit_to_height(ASSET, 15.0), 101)
		var tree := Library.build(batches, false, {tree_wind = wind})
		stage.add_child(tree)
		for light in [
			["front", Vector3(0, 10, 20)], ["side", Vector3(20, 10, 0)],
			["rear", Vector3(0, 10, -20)], ["ambient", Vector3(0, 10, 20)]]:
			sun.look_at_from_position(light[1], Vector3(0, 7.5, 0))
			sun.light_energy = 0.0 if light[0] == "ambient" else 1.0
			await _capture("%s_%s" % ["wind" if wind else "static", light[0]], Vector3.ZERO, 0.0)
		if wind:
			for state in [["gust", 1.0], ["repeat", 1.0], ["wrap", 1025.0]]:
				sun.light_energy = 1.0
				sun.look_at_from_position(Vector3(0, 10, -20), Vector3(0, 7.5, 0))
				await _capture("wind_" + state[0], Vector3(5, 0, 0), state[1])
		tree.free()
	report.complete = true
	report["viewport"] = [1920, 1080]
	report["godot"] = Engine.get_version_info().string
	report["renderer"] = RenderingServer.get_current_rendering_method()
	report["adapter"] = RenderingServer.get_video_adapter_name()
	report["api"] = RenderingServer.get_video_adapter_api_version()
	report["scope"] = "Fixed camera/exposure/15 m production Fagus; only light direction and declared wind change. No aircraft simulation or performance qualification."
	var identities := {}
	for path in ["res://scenery/imported_vegetation.gd", "res://scenery/imported_tree_wind.gdshaderinc",
			"res://assets/landscape/vegetation/catalog.json"]:
		identities[path] = FileAccess.get_sha256(path)
	report["source_sha256"] = identities
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	if file == null:
		_fail("cannot write report")
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	viewport.free()
	print("TREE BACKLIGHT REVIEW COMPLETE")
	quit()


func _capture(id: String, wind: Vector3, clock: float) -> void:
	Clock.update(clock, wind)
	for _frame in 4:
		await process_frame
		await RenderingServer.frame_post_draw
	var path := output.path_join(id + ".png")
	if viewport.get_texture().get_image().save_png(path) != OK:
		_fail("capture failed")
		return
	report.captures.append({id = id, sha256 = FileAccess.get_sha256(path),
		light_direction = [-sun.global_basis.z.x, -sun.global_basis.z.y, -sun.global_basis.z.z],
		light_energy = sun.light_energy, clock = clock, wind = [wind.x, wind.y, wind.z]})


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

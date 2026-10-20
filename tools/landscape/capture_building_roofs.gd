## Native field-only roof review. Run with --out=<absolute directory> [--replace].
extends SceneTree

const Field := preload("res://render/field.gd")
const Loader := preload("res://data/field_loader.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const Frames := preload("res://render/frames.gd")
const Clock := preload("res://render/shader_clock.gd")

const VIEWS := [
	{name = "club_air", eye = [10.0, 34.0, -27.0], at = [-22.0, 0.0, -2.3], fov = 42.0},
	{name = "pavilion_pilot", eye = [-4.0, 14.0, -1.7], at = [-21.0, -2.0, -2.0], fov = 46.0},
	{name = "pavilion_roof", eye = [-12.0, 14.0, -11.0], at = [-22.0, 0.0, -3.0], fov = 43.0},
	{name = "shed_roof", eye = [-27.0, -21.0, -8.0], at = [-40.5, -33.5, -1.5], fov = 42.0},
	{name = "farm_roofs", eye = [450.0, 160.0, -75.0], at = [610.0, 365.0, -3.0], fov = 55.0},
	{name = "farm_close", eye = [550.0, 300.0, -24.0], at = [594.0, 333.0, -3.0], fov = 50.0},
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := ""
	var replace := false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg == "--replace":
			replace = true
	if out.is_empty() or (FileAccess.file_exists(out.path_join("capture.json")) and not replace):
		push_error("--out must name a new capture directory unless --replace is set")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	OS.set_environment("OPENRC_SCENERY", "on")
	OS.set_environment("OPENRC_SCENERY_AUDIO", "off")
	OS.set_environment("OPENRC_SCENERY_BIRDS", "off")
	Clock.register()
	Clock.update(0.0)
	RenderingServer.render_loop_enabled = false
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var loaded := Loader.load_from()
	if not loaded.ok:
		push_error(str(loaded.errors))
		quit(1)
		return
	var field := Field.build(loaded.field)
	viewport.add_child(field)
	var environment := WorldEnvironment.new()
	environment.environment = Atmosphere.environment()
	field.add_child(environment)
	Atmosphere.create_sun(field)
	var camera := Camera3D.new()
	camera.near = 0.03
	camera.far = 21000.0
	camera.current = true
	field.add_child(camera)
	var records := []
	var rid := viewport.get_viewport_rid()
	for view: Dictionary in VIEWS:
		camera.position = Frames.ned_to_render(view.eye)
		camera.look_at(Frames.ned_to_render(view.at))
		camera.fov = view.fov
		for frame in 30:
			await process_frame
			RenderingServer.force_draw(false)
		var path := out.path_join(str(view.name) + ".png")
		if viewport.get_texture().get_image().save_png(path) != OK:
			push_error("Failed to save " + path)
			quit(1)
			return
		records.append({"view": view.name, "eye_ned": view.eye, "at_ned": view.at,
			"fov": view.fov, "sha256": FileAccess.get_sha256(path),
			"draws": RenderingServer.viewport_get_render_info(rid,
				RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
				RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)})
	var report := {"complete": true, "adapter": RenderingServer.get_video_adapter_name(),
		"method": RenderingServer.get_current_rendering_method(), "records": records}
	var file := FileAccess.open(out.path_join("capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
	field.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame
	quit()

## L10b-R1: native production pilot-station close views.
extends SceneTree
const Field = preload("res://render/field.gd")
const Loader = preload("res://data/field_loader.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const Clock = preload("res://render/shader_clock.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	if out.is_empty() or DirAccess.dir_exists_absolute(out):
		push_error("--out must name a new directory")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
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
	var world := Field.build(loaded.field)
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Atmosphere.environment()
	world.add_child(environment)
	Atmosphere.create_sun(world)
	var camera := Camera3D.new()
	camera.near = 0.03
	camera.far = 21000.0
	camera.current = true
	world.add_child(camera)
	var barrier := world.get_node("pilot_station") as Node3D
	var origin := barrier.position
	var views := [
		["front", origin + Vector3(1.8, 1.25, -2.2), origin + Vector3(0, 0.30, 0), 48.0],
		["rear", origin + Vector3(1.8, 1.45, 2.0), origin + Vector3(0, 0.25, 0), 48.0],
		["joint", origin + Vector3(1.05, 0.85, -1.05), origin + Vector3(0.64, 0.48, -0.5), 48.0],
		["floor", origin + Vector3(0.5, 1.3, 1.2), origin + Vector3(0, 0.06, 0), 48.0]]
	var records := []
	var rid := viewport.get_viewport_rid()
	for view in views:
		camera.position = view[1]
		camera.look_at(view[2])
		camera.fov = view[3]
		for frame in 12:
			await process_frame
			RenderingServer.force_draw(false)
		var path := out.path_join(str(view[0]) + ".png")
		if viewport.get_texture().get_image().save_png(path) != OK:
			quit(1)
			return
		records.append({view = view[0], sha256 = FileAccess.get_sha256(path),
			eye = [camera.position.x, camera.position.y, camera.position.z], fov = camera.fov,
			draws = RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)})
	var mesh: Mesh = barrier.get_node("Station").mesh
	var report := {complete = true, adapter = RenderingServer.get_video_adapter_name(),
		method = RenderingServer.get_current_rendering_method(), records = records,
		station_triangles = mesh.surface_get_array_len(0) / 3, station_surfaces = mesh.get_surface_count(),
		builder_sha256 = FileAccess.get_sha256("res://render/pilot_station.gd")}
	var file := FileAccess.open(out.path_join("capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
	world.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame
	quit()

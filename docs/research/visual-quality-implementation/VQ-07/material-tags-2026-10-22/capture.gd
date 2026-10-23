## VQ-07 metadata parity: production shelter and flightline, fixed 1080p views.
extends SceneTree
const Field = preload("res://render/field.gd")
const Loader = preload("res://data/field_loader.gd")
const SceneryLoader = preload("res://scenery/scenery_loader.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const Clock = preload("res://render/shader_clock.gd")
const Frames = preload("res://render/frames.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Native renderer required")
		quit(1)
		return
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	if out.is_empty() or DirAccess.dir_exists_absolute(out):
		push_error("--out must name a new directory")
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
	viewport.size = Vector2i(1920, 1080)
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var loaded := Loader.load_from()
	if not loaded.ok:
		push_error(str(loaded.errors))
		quit(1)
		return
	var layout := SceneryLoader.load_from(SceneryLoader.DEFAULT_PATH, loaded.field)
	if not layout.ok:
		push_error(str(layout.errors))
		quit(1)
		return
	var shelter: Dictionary = layout.scenery.groups[0].placements[0]
	var origin: Vector3 = Frames.ned_to_render([shelter.north, shelter.east, 0.0])
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
	var views := [
		["front", origin + Vector3(1.8, 2.2, -9.0), origin + Vector3(0, 1.95, 0), 66.0],
		["underside", origin + Vector3(1.0, 1.55, -1.7), origin + Vector3(0, 3.0, 0), 74.0],
		["eave", origin + Vector3(-3.0, 2.35, -4.2), origin + Vector3(-3.5, 3.1, -2.4), 48.0],
		["flightline", Frames.ned_to_render([8.0,-9.0,-1.2]), Frames.ned_to_render([4.5,-12.0,-0.35]), 55.0]]

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
			draws = RenderingServer.viewport_get_render_info(rid,
				RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
				RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)})
	var report := {complete = true, adapter = RenderingServer.get_video_adapter_name(),
		method = RenderingServer.get_current_rendering_method(), records = records, viewport = [viewport.size.x, viewport.size.y],
		barrier_shader_sha256 = FileAccess.get_sha256("res://render/flightline_barrier.gdshader"),
		shelter_shader_sha256 = FileAccess.get_sha256("res://scenery/pit_shelter_roof.gdshader"),
		scenery_stats = world.get_node("Scenery").get_meta("stats"),
		builder_sha256 = FileAccess.get_sha256("res://scenery/prefabs.gd")}
	var file := FileAccess.open(out.path_join("capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
	world.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame
	print("material tag capture complete")
	quit()

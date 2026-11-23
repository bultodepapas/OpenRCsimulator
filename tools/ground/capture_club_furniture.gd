## SC-08-R1: native production club furniture close views.
extends SceneTree
const DamageBatches := preload("res://scenery/damage_batches.gd")
const Field = preload("res://render/field.gd")
const Loader = preload("res://data/field_loader.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const Clock = preload("res://render/shader_clock.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := ""
	var size := Vector2i(1280, 720)
	var verify_visible := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg == "--1080p":
			size = Vector2i(1920, 1080)
		elif arg == "--verify-visible":
			verify_visible = true
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
	viewport.size = size
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
	var views := [
		["table", Vector3(-6.6, 1.6, 22.0), Vector3(-9.5, 0.38, 24.5), 42.0],
		["table-detail", Vector3(-8.1, 1.25, 23.2), Vector3(-9.5, 0.52, 24.5), 42.0],
		["bench", Vector3(-16.5, 1.35, 13.8), Vector3(-14.0, 0.42, 16.5), 42.0],
		["bench-rear", Vector3(-16.0, 1.2, 18.5), Vector3(-14.0, 0.42, 16.5), 42.0]]
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
		var image := viewport.get_texture().get_image()
		if image == null or image.get_size() != viewport.size:
			push_error("Missing furniture view: " + str(view[0]))
			quit(1)
			return
		if image.save_png(path) != OK:
			quit(1)
			return
		var record := {view = view[0], sha256 = FileAccess.get_sha256(path),
			eye = [camera.position.x, camera.position.y, camera.position.z], fov = camera.fov,
			draws = RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)}
		if verify_visible:
			# Default layout's first table and first bench are at the two camera targets above.
			var id := "prop:picnic:00" if str(view[0]).begins_with("table") else "prop:benches:00"
			record.visibility = _verify_visible(world.get_node("Scenery"), viewport, image, id,
				out.path_join(str(view[0]) + "-absent.png"))
			if record.visibility.is_empty():
				push_error("Furniture removal and restoration did not identify " + id + " in " + str(view[0]))
				quit(1)
				return
		records.append(record)
	var report := {complete = true, adapter = RenderingServer.get_video_adapter_name(),
		method = RenderingServer.get_current_rendering_method(), records = records,
		scenery_stats = world.get_node("Scenery").get_meta("stats"), viewport = [viewport.size.x, viewport.size.y],
		furniture_sha256 = FileAccess.get_sha256("res://scenery/club_furniture.gd"),
		builder_sha256 = FileAccess.get_sha256("res://scenery/prefabs.gd")}
	var file := FileAccess.open(out.path_join("capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
	world.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame
	print("CLUB_FURNITURE_RENDER verdict=pass views=4 viewport=%dx%d visible=%d" % [size.x, size.y, 4 if verify_visible else 0])
	quit()


func _verify_visible(scenery: Node, viewport: SubViewport, image: Image, id: String, path: String) -> Dictionary:
	var damage := {}
	damage[id] = {"state": "broken"}
	for child in scenery.get_children():
		var batch := child as MeshInstance3D
		if batch == null or not batch.has_meta("damage_ranges") or not DamageBatches.apply(batch, damage):
			continue
		# Force both draws in this call, without advancing the camera, animation or simulation.
		RenderingServer.force_draw(false, 0.0)
		var absent := viewport.get_texture().get_image()
		if not DamageBatches.apply(batch, {}) or batch.mesh != batch.get_meta("damage_pristine_mesh"):
			return {}
		RenderingServer.force_draw(false, 0.0)
		var restored := viewport.get_texture().get_image()
		if absent == null or restored == null or absent.get_size() != image.get_size() or restored.get_size() != image.get_size():
			return {}
		var roi := Rect2i(image.get_size() / 4, image.get_size() / 2)
		var buffers: Array[PackedByteArray] = []
		for full: Image in [image, absent, restored]:
			var crop := full.get_region(roi)
			crop.convert(Image.FORMAT_RGBA8)
			buffers.append(crop.get_data())
		var changed := 0
		for i in range(0, buffers[0].size(), 4):
			var recovered := true
			var removed := false
			for c in 3:
				recovered = recovered and absi(int(buffers[0][i+c]) - int(buffers[2][i+c])) <= 2
				removed = removed or absi(int(buffers[0][i+c]) - int(buffers[1][i+c])) >= 8
			if recovered and removed:
				changed += 1
		if changed < 64 or absent.save_png(path) != OK:
			return {}
		return {id = id, changed_pixels = changed, roi = [roi.position.x, roi.position.y, roi.size.x, roi.size.y],
			absent_sha256 = FileAccess.get_sha256(path)}
	return {}

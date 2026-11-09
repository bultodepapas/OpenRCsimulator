## L10c-R1: fixed close/front/rear and pilot views of the production field.
extends SceneTree
const Field = preload("res://render/field.gd")
const Loader = preload("res://data/field_loader.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const Clock = preload("res://render/shader_clock.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := ""
	var width := 1920
	var height := 1080
	var planting_source := ""
	var motion_frames := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--width="):
			width = int(arg.trim_prefix("--width="))
		elif arg.begins_with("--height="):
			height = int(arg.trim_prefix("--height="))
		elif arg.begins_with("--planting-source="):
			planting_source = arg.trim_prefix("--planting-source=")
		elif arg.begins_with("--motion-frames="):
			motion_frames = int(arg.trim_prefix("--motion-frames="))
	if DisplayServer.get_name() == "headless" or width < 640 or height < 360:
		push_error("A native framebuffer and valid capture dimensions are required")
		quit(1)
		return
	if motion_frames != 0 and (motion_frames < 2 or motion_frames > 120):
		push_error("--motion-frames must be zero or 2 through 120")
		quit(1)
		return
	if out.is_empty() or DirAccess.dir_exists_absolute(out):
		push_error("--out must name a new directory")
		quit(1)
		return
	if DirAccess.make_dir_recursive_absolute(out) != OK:
		push_error("Could not create the capture directory")
		quit(1)
		return
	OS.set_environment("OPENRC_SCENERY_AUDIO", "off")
	OS.set_environment("OPENRC_SCENERY_BIRDS", "off")
	Clock.register()
	Clock.update(0.0)
	RenderingServer.render_loop_enabled = false
	var viewport := SubViewport.new()
	viewport.size = Vector2i(width, height)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var loaded := Loader.load_from()
	if not loaded.ok:
		push_error(str(loaded.errors))
		quit(1)
		return
	var world := Field.build(loaded.field)
	world.process_mode = Node.PROCESS_MODE_DISABLED
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
	var barrier := world.get_node("flightline_barrier") as Node3D
	# Compare a preserved source snapshot without editing or reimporting production files.
	# The replacement uses the same cue, post positions, source assets and build function.
	var snapshot_used := not planting_source.is_empty()
	if snapshot_used:
		var source_code := FileAccess.get_file_as_string(planting_source)
		var planting := GDScript.new()
		planting.source_code = source_code
		if source_code.is_empty() or planting.reload() != OK:
			push_error("Could not compile the requested planting source")
			quit(1)
			return
		var cue: Dictionary = {}
		for item: Dictionary in loaded.field.flight_cues:
			if item.id == "flightline_barrier":
				cue = item
		if cue.is_empty():
			push_error("Default field must contain the flightline barrier")
			quit(1)
			return
		barrier.get_node("PostVegetation").free()
		barrier.add_child(planting.build(cue, load("res://render/flightline_barrier.gd").post_positions(cue)))
	else:
		planting_source = "res://render/flightline_barrier_planting.gd"
	var origin := barrier.position
	var views := [
		["foot", origin + Vector3(3.45, 0.32, 0.55), origin + Vector3(3.1, 0.11, 0), 52.0],
		["detail", origin + Vector3(3.5, 0.95, 1.1), origin + Vector3(2.7, 0.39, 0.0), 48.0],
		["rear", origin + Vector3(3.5, 0.95, -1.1), origin + Vector3(2.7, 0.39, 0.0), 48.0],
		["flightline", origin + Vector3(9.0, 1.7, 5.5), origin + Vector3(0, 0.35, 0), 55.0],
		["pilot", Vector3(0, 1.7, 0), Vector3(25, 0.3, -15), 50.0],
		["gate", origin + Vector3(0.0, 1.3, 3.2), origin + Vector3(0.0, 0.15, 0.0), 60.0],
		["bank", origin + Vector3(7.0, 0.4, 1.9), origin + Vector3(3.5, 0.1, 0.0), 62.0],
		["overhead", origin + Vector3(2.5, 7.0, 0.01), origin + Vector3(2.5, 0.0, 0.0), 60.0]]
	# Offline camera translation only: readback/PNG work is not frame-time evidence.
	for index in motion_frames:
		var x := lerpf(3.45, 9.45, float(index) / float(motion_frames - 1))
		views.append(["motion-%03d" % index, origin + Vector3(x, 0.55, 1.5),
			origin + Vector3(x - 0.35, 0.12, 0.0), 56.0])
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
			target = [view[2].x, view[2].y, view[2].z], near_m = camera.near, far_m = camera.far,
			width = width, height = height,
			draws = RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)})
	var mesh: Mesh = barrier.get_node("Barrier").mesh
	var report := {complete = true, adapter = RenderingServer.get_video_adapter_name(),
		capture_script_sha256 = FileAccess.get_sha256(get_script().resource_path),
		engine = Engine.get_version_info(), viewport = [width, height],
		motion_frames = motion_frames,
		planting_source = planting_source, planting_sha256 = FileAccess.get_sha256(planting_source),
		source_snapshot_used = snapshot_used,
		method = RenderingServer.get_current_rendering_method(), records = records,
		barrier_triangles = mesh.surface_get_array_len(0) / 3, barrier_surfaces = mesh.get_surface_count(),
		builder_sha256 = FileAccess.get_sha256("res://render/flightline_barrier.gd")}
	var vegetation := barrier.get_node_or_null("PostVegetation")
	if vegetation != null:
		report["plants"] = vegetation.get_meta("layout").size()
		report["plant_source_triangles"] = vegetation.get_meta("source_triangles")
	var source_hashes := {}
	for path: String in ["res://render/flightline_barrier.gd", "res://render/flightline_barrier_detail.gd", "res://render/flightline_barrier.gdshader", "res://render/flightline_barrier_planting.gd", "res://render/flightline_barrier_foliage.gdshader", "res://render/flightline_barrier_soil.gdshader"]:
		source_hashes[path] = FileAccess.get_sha256(path)
	report["sources"] = source_hashes
	var file := FileAccess.open(out.path_join("capture.json"), FileAccess.WRITE)
	if file == null:
		push_error("Could not write the capture manifest")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
	world.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame
	print("FENCE CAPTURE COMPLETE: ", out)
	quit()

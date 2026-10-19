## VQ-04a-F2 native coverage oracle and bounded component timing fixture.
extends SceneTree
const Sock = preload("res://render/windsock.gd")
const Shadows = preload("res://render/field_projected_shadows.gd")
const Loader = preload("res://data/field_loader.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const Clock = preload("res://render/shader_clock.gd")
var output: String
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	_run.call_deferred()

func check(passed: bool, label: String) -> void:
	checks += 1
	if not passed:
		failures.append(label)
		printerr("FAIL " + label)

func draw() -> void:
	await process_frame
	await RenderingServer.frame_post_draw

func _run() -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless":
		printerr("Native display and --out=<JSON path> required")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	Engine.max_fps = 60
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Clock.register()
	var world := Node3D.new()
	root.add_child(world)
	var camera := Camera3D.new()
	camera.position = Vector3(8, 8, 10)
	world.add_child(camera)
	camera.look_at(Vector3(0, 2, 0))
	camera.make_current()
	var cue: Dictionary = Loader.load_from().field.flight_cues.filter(func(c: Dictionary) -> bool: return c.type == "windsock")[0].duplicate(true)
	cue.north = 0.0
	cue.east = 0.0
	var sock := Sock.build(cue)
	world.add_child(sock)
	var lighting: Dictionary = Atmosphere.Spec.ATMOSPHERE.duplicate(true)
	lighting.sun_elevation_deg = 45.0
	lighting.sun_azimuth_deg = 220.0
	lighting.shadow_strength = 1.0
	Shadows.attach(world, {flight_cues = [cue]}, lighting)
	var manager: Node = world.get_node("ProjectedFieldShadows")
	var projector: Node = manager.projectors[0]
	var masks: Dictionary = {}
	for entry: Array in [["calm", 0.0, 45.0], ["light", 1.5, 45.0], ["strong", 12.0, 45.0], ["reversal", -12.0, 45.0], ["low-sun", 9.0, 15.0]]:
		Sock.reset(sock, 0.0)
		var wind: Array = [0.0, entry[1], 0.0]
		for tick: int in 1200: Sock.advance(sock, (tick + 1) / 240.0, wind)
		Sock.update(sock, 5.0, wind)
		Clock.update(5.0)
		lighting.sun_elevation_deg = entry[2]
		manager.apply(lighting)
		await draw()
		await draw()
		var image: Image = projector.viewport.get_texture().get_image()
		var context := HashingContext.new()
		context.start(HashingContext.HASH_SHA256)
		context.update(image.get_data())
		masks[entry[0]] = context.finish().hex_encode()
		check(image.get_size() == Vector2i(512, 512), str(entry[0]) + " uses 512² coverage")
		var border_clear := true
		for p: int in 512:
			border_clear = border_clear and image.get_pixel(p, 0).a == 0.0 and image.get_pixel(p, 511).a == 0.0 \
				and image.get_pixel(0, p).a == 0.0 and image.get_pixel(511, p).a == 0.0
		check(border_clear, str(entry[0]) + " has an unclipped clear border")
		var direction: Vector3 = Atmosphere.shadow_direction(lighting)
		var centres: PackedVector3Array = sock.get_node("Fabric").get_meta("centreline")
		for station: int in range(7, 11):
			# Independent world-space light-ray intersection, then receiver plane UV.
			var point: Vector3 = sock.global_transform * centres[station]
			var ray_time: float = (point.y - projector.receiver.global_position.y) / direction.y
			var ground: Vector3 = point - direction * ray_time
			var local: Vector3 = projector.receiver.global_transform.affine_inverse() * ground
			var pixel := Vector2i(roundi((local.x + 0.5) * 512.0), roundi((local.z + 0.5) * 512.0))
			var alpha: float = 0.0
			# Two texels cover raster edges and the sub-centimetre visual flutter.
			for dx: int in range(-2, 3):
				for dy: int in range(-2, 3):
					alpha = maxf(alpha, image.get_pixel(clampi(pixel.x + dx, 0, 511), clampi(pixel.y + dy, 0, 511)).a)
			check(alpha > 0.5, "%s station %d projects inside cloth coverage" % [entry[0], station])
		await draw()
		check(image.get_data() == projector.viewport.get_texture().get_image().get_data(), str(entry[0]) + " paused repeated pose is identical")
	check(masks.strong != masks.calm and masks.strong != masks.reversal, "wind and reversal replace the mask")
	sock.visible = false
	check(not projector.receiver.visible and projector.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "hidden source disables map")
	sock.visible = true
	lighting.shadow_strength = 0.0
	manager.apply(lighting)
	check(not projector.receiver.visible and projector.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "zero direct strength disables map")
	lighting.shadow_strength = 1.0
	lighting.sun_elevation_deg = 45.0
	manager.apply(lighting)
	await draw()
	check(projector.receiver.visible, "daylight restores map")
	var main_rid := root.get_viewport_rid()
	var mask_rid: RID = projector.viewport.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(main_rid, true)
	RenderingServer.viewport_set_measure_render_time(mask_rid, true)
	var segments: Array[Dictionary] = []
	for active: bool in [true, false, true, false]:
		Sock.reset(sock, 0.0)
		projector.set_process(active)
		var samples: Array = []
		var previous: int = Time.get_ticks_usec()
		for frame: int in 100:
			for substep: int in 4:
				var t: float = (frame * 4 + substep + 1) / 240.0
				Sock.advance(sock, t, [2.0 * sin(t), 8.0 + 3.0 * sin(t * 3.0), -sin(t * 2.0)])
			var now: float = (frame + 1) / 60.0
			Sock.update(sock, now, [2.0 * sin(now), 8.0 + 3.0 * sin(now * 3.0), -sin(now * 2.0)])
			Clock.update(now)
			await draw()
			var stamp: int = Time.get_ticks_usec()
			if frame >= 20:
				samples.append([float(stamp - previous) / 1000.0,
					RenderingServer.viewport_get_measured_render_time_cpu(main_rid), RenderingServer.viewport_get_measured_render_time_gpu(main_rid),
					RenderingServer.viewport_get_measured_render_time_cpu(mask_rid) if active else 0.0,
					RenderingServer.viewport_get_measured_render_time_gpu(mask_rid) if active else 0.0])
			previous = stamp
		segments.append({dynamic_mask = active, samples_ms = samples})
	var report := {passed = failures.is_empty(), checks = checks, failures = failures,
		renderer = RenderingServer.get_current_rendering_method(), gpu = RenderingServer.get_video_adapter_name(),
		mask_hashes = masks, segments = segments, sample_columns = ["wall", "main_cpu", "main_gpu", "mask_cpu", "mask_gpu"],
		projector_sha256 = FileAccess.get_sha256("res://render/windsock_projected_shadow.gd"),
		limitations = "Component fixture, alternating dynamic and cached mask. Cached mask timings are zero because no new mask draw is requested. Not a full flight, isolated hardware deadline, or minimum-GPU qualification."}
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	world.free()
	await process_frame
	print("Windsock native oracle: %d checks, %d failed" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

## Native Compatibility evidence; run with --out=<absolute directory>.
extends SceneTree
const Field = preload("res://render/field.gd")
const Loader = preload("res://data/field_loader.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const Airplane = preload("res://render/airplane.gd")
const Shadow = preload("res://render/shadow.gd")
const Clock = preload("res://render/shader_clock.gd")
const Catalog = preload("res://app_state/aircraft_catalog.gd")
var args := {}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=", true, 1)
		args[pair[0]] = pair[1] if pair.size() > 1 else "on"
	run.call_deferred()

func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(1280, 720)
	root.msaa_3d = Viewport.MSAA_4X
	Clock.register()
	Clock.update(0.0)
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Atmosphere.environment()
	world.add_child(environment)
	var field_node := Field.build(Loader.load_from(Loader.DEFAULT_PATH).field)
	world.add_child(field_node)
	Atmosphere.create_sun(world)
	var camera := Camera3D.new()
	camera.fov = 42.0
	camera.far = 21000
	world.add_child(camera)
	camera.current = true
	var rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var result := {engine = Engine.get_version_info(), gpu = RenderingServer.get_video_adapter_name(),
		renderer = RenderingServer.get_current_rendering_method(), resolution = [1280,720],
		msaa = 4, args = args, cases = []}
	var static_shadows := field_node.get_node_or_null("ProjectedFieldShadows")
	result["static_shadow_maps"] = static_shadows.projectors.size() if static_shadows != null else 0
	result["static_shadow_target_pixels"] = static_shadows.target_pixels if static_shadows != null else 0
	var out: String = args.out
	DirAccess.make_dir_recursive_absolute(out)
	var ids := Catalog.ids()
	if args.has("aircraft"):
		ids = PackedStringArray([args.aircraft])
	if args.has("profile") or args.has("field"):
		ids = PackedStringArray([Airplane.P51_ID])
	for id in ids:
		var aircraft: Dictionary = Airplane.build(id)
		world.add_child(aircraft.root)
		var extent := Shadow.model_extent(aircraft.root)
		var shadow := Shadow.create(world)
		var bind_start := Time.get_ticks_usec()
		var api = Shadow.new()
		if api.has_method("bind_model"):
			api.call("bind_model", shadow, aircraft.root)
		var bind_ms := float(Time.get_ticks_usec() - bind_start) / 1000.0
		var projected: Node = shadow.get_node_or_null("ProjectedShadow")
		var mask_rid := RID()
		if projected != null:
			mask_rid = projected.viewport.get_viewport_rid()
			RenderingServer.viewport_set_measure_render_time(mask_rid, true)
		var poses := [["low", 0.5, 0.0], ["pass", 2.0, 25.0], ["knife", 2.0, 90.0], ["inverted", 2.0, 180.0], ["high", 12.0, 25.0]]
		if args.has("profile"):
			poses = [["moving", 2.0, 25.0]]
		if args.has("field"):
			poses = [["flightline", 2.0, 0.0], ["pilot", 2.0, 0.0], ["club", 2.0, 0.0]]
			if args.has("profile"):
				poses = [["club", 2.0, 0.0]]
		for pose in poses:
			var height: float = pose[1]
			var b := Basis.from_euler(Vector3(0.0, 0.35, deg_to_rad(pose[2])))
			var pos := Vector3(0.0, height, -30.0)
			aircraft.root.transform = Transform3D(b, pos)
			Shadow.update(shadow, b, pos, extent.x, extent.y, Atmosphere.sun_direction())
			camera.position = Vector3(6, maxf(6.0, height + 3), -21)
			if height > 5.0:
				camera.position = Vector3(12, height + 20, -12)
			camera.look_at(Vector3(height * 0.35, height * 0.5, -30 + height * 0.35))
			if args.has("field"):
				aircraft.root.visible = false
				shadow.visible = false
				Shadow.update(shadow, b, pos, extent.x, extent.y, Atmosphere.sun_direction(), 0.0)
				match pose[0]:
					"flightline":
						camera.position = Vector3(10, 5, 12)
						camera.look_at(Vector3(0, 0.3, -3))
					"pilot":
						camera.position = Vector3(4, 3.5, 7)
						camera.look_at(Vector3(0, 0.6, 0))
					"club":
						camera.position = Vector3(-32, 15, -12)
						camera.look_at(Vector3(0, 0, 27))
			var warmup := Time.get_ticks_usec() + int(float(args.get("warmup", "0.3")) * 1e6)
			for frame in range(16):
				await process_frame
				await RenderingServer.frame_post_draw
			while Time.get_ticks_usec() < warmup:
				await process_frame
				await RenderingServer.frame_post_draw
			var samples := []
			var previous := Time.get_ticks_usec()
			var end := previous + int(float(args.get("seconds", "1")) * 1e6)
			var frame := 0
			while (Time.get_ticks_usec() < end if args.has("profile") else frame < 8):
				if args.has("profile") and not args.has("field"):
					b = Basis.from_euler(Vector3(0.1, 0.35, 0.4 + sin(frame * 0.02) * 0.2))
					aircraft.root.basis = b
					Shadow.update(shadow, b, pos, extent.x, extent.y, Atmosphere.sun_direction())
				await process_frame
				await RenderingServer.frame_post_draw
				var now := Time.get_ticks_usec()
				samples.append([float(now - previous) / 1000.0,
					RenderingServer.viewport_get_measured_render_time_cpu(rid),
					RenderingServer.viewport_get_measured_render_time_gpu(rid),
					RenderingServer.viewport_get_measured_render_time_cpu(mask_rid) if mask_rid.is_valid() else 0.0,
					RenderingServer.viewport_get_measured_render_time_gpu(mask_rid) if mask_rid.is_valid() else 0.0])
				previous = now
				frame += 1
			var name: String = id + "-" + pose[0]
			root.get_texture().get_image().save_png(out.path_join(name + ".png"))
			if projected != null and not args.has("profile") and not args.has("field"):
				projected.viewport.get_texture().get_image().save_png(out.path_join(name + "-mask.png"))
			result.cases.append({id = name, bind_cpu_ms = bind_ms, samples_wall_maincpu_maingpu_maskcpu_maskgpu_ms = samples,
				draws = RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
				mask_triangles = projected.triangle_count if projected != null else 0})
		shadow.free()
		aircraft.root.free()
	FileAccess.open(out.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	quit()

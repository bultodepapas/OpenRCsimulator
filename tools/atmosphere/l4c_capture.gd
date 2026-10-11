## L4c: production field/sky/model, fixed poses, native GPU timer and raw frame intervals.
## Run through l4c_verify.py; this producer writes only caller-selected evidence.
extends SceneTree

const Atmosphere = preload("res://render/atmosphere.gd")
const Field = preload("res://render/field.gd")
const Loader = preload("res://data/field_loader.gd")
const Airplane = preload("res://render/airplane.gd")
const Frames = preload("res://render/frames.gd")
const Clock = preload("res://render/shader_clock.gd")
const Spec = preload("res://spec.gd")
const Lighting = preload("res://render/time_of_day_lighting.gd")
const Config = preload("res://environment/time_of_day_config.gd")

var args: Dictionary = {}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var pair = arg.trim_prefix("--").split("=", true, 1)
		args[pair[0]] = pair[1] if pair.size() > 1 else "on"
	run.call_deferred()

func run() -> void:
	var out: String = args["out"]
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.render_loop_enabled = false
	var width: int = int(args.get("width", "1280"))
	root.size = Vector2i(width, width * 9 / 16)
	# An always-updating offscreen viewport keeps evidence independent of desktop
	# occlusion/minimization. It still uses the real native Compatibility GPU.
	var viewport = SubViewport.new()
	viewport.size = root.size
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	Clock.register()
	var world = Node3D.new()
	viewport.add_child(world)
	var lighting: Dictionary = {}
	if args.has("hour"):
		var config: Dictionary = Config.defaults()
		config.mode = "astronomical"
		config.local_seconds = float(args.hour) * 3600.0
		lighting = Lighting.snapshot(config)
	var env = Atmosphere.environment(lighting)
	var wen = WorldEnvironment.new()
	wen.environment = env
	world.add_child(wen)
	var field: Dictionary = Loader.load_from(Loader.DEFAULT_PATH).field
	world.add_child(Field.build(field, lighting))
	Atmosphere.create_sun(world, lighting)
	var camera = Camera3D.new()
	world.add_child(camera)
	camera.current = true
	camera.fov = 50.0
	camera.far = 21000.0
	camera.position = Frames.ned_to_render([field.pilot.north, field.pilot.east, -1.7])
	var airplane: Node3D = Airplane.build().root
	world.add_child(airplane)
	var mat: ShaderMaterial = env.sky.sky_material
	if args.has("strength"):
		mat.set_shader_parameter("cloud_relief_strength", float(args.strength))
	if args.has("coverage"):
		mat.set_shader_parameter("cloud_coverage", float(args.coverage))
	if args.get("airplane", "on") == "off":
		airplane.visible = false
	var rid = viewport.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var cases: Array = []
	var views: Array = [["sun",225.0,35.0], ["cross",315.0,35.0], ["antisun",45.0,35.0],
		["horizon",225.0,3.0], ["ground",225.0,-18.0], ["zenith",225.0,85.0]]
	if args.get("profile", "off") == "on":
		views = [["sun",225.0,35.0]]
	for view in views:
		var az = deg_to_rad(view[1])
		var el = deg_to_rad(view[2])
		var direction = Frames.ned_to_render([cos(az)*cos(el),sin(az)*cos(el),-sin(el)])
		camera.look_at(camera.position + direction)
		airplane.position = camera.position + direction * 40.0
		airplane.rotation_degrees = Vector3(0.0, -40.0, 20.0)
		for t in ([0.0] if args.get("profile", "off") == "on" else [0.0,120.0]):
			Clock.update(t)
			Atmosphere.update_clouds(env,t)
			var warmup_end: int = Time.get_ticks_usec() + int(float(args.get("warmup", "0.1")) * 1000000.0)
			for frame in range(30):
				await process_frame
				RenderingServer.force_draw(false)
			while Time.get_ticks_usec() < warmup_end:
				await process_frame
				RenderingServer.force_draw(false)
			var samples: Array = []
			var last: int = Time.get_ticks_usec()
			var sample_end: int = last + int(float(args.get("seconds", "1")) * 1000000.0)
			var frame: int = 0
			while (Time.get_ticks_usec() < sample_end if args.get("profile", "off") == "on" else frame < 8):
				await process_frame
				RenderingServer.force_draw(false)
				var now: int = Time.get_ticks_usec()
				samples.append([float(now-last)/1000.0,
					RenderingServer.viewport_get_measured_render_time_cpu(rid),
					RenderingServer.viewport_get_measured_render_time_gpu(rid)])
				last = now
				frame += 1
			var name: String = "%s-%03d" % [view[0],int(t)]
			viewport.get_texture().get_image().save_png(out.path_join(name + ".png"))
			cases.append({"id":name,"time":t,"samples_wall_cpu_gpu_ms":samples,
				"draws":RenderingServer.viewport_get_render_info(rid,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
				"primitives":RenderingServer.viewport_get_render_info(rid,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)})
	var result = {"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),
		"renderer":RenderingServer.get_current_rendering_method(),"cases":cases,"args":args,
		"viewport":[viewport.size.x,viewport.size.y],"msaa":viewport.msaa_3d,
		"offscreen":true,"manual_draw":true}
	FileAccess.open(out.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	quit()

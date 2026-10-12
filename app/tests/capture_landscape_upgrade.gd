## LU native evidence: actual world and aircraft, controlled optics cases and raw frame times.
extends SceneTree
const World := preload("res://render/world/world.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Frames := preload("res://render/frames.gd")
const Airplane := preload("res://render/airplane.gd")
const Glare := preload("res://render/landscape_upgrade/sun_glare.gd")
const Ridges := preload("res://render/landscape_upgrade/ridges.gd")
const Postcards := preload("res://scenery/postcards.gd")
const LightingConfig := preload("res://environment/time_of_day_config.gd")
const SnapshotLighting := preload("res://render/time_of_day_lighting.gd")
const FLEET_VIEWS := {
	"parked_stik": {eye = [-16.3, -35.7, -1.7], at = [-17.6, -38.0, -0.5], fov = 55.0},
	"parked_extra": {eye = [-16.3, -21.7, -1.7], at = [-17.6, -24.0, -0.5], fov = 55.0},
	"parked_p51": {eye = [-16.3, 27.5, -2.1], at = [-17.8, 24.0, -0.8], fov = 60.0},
	"parked_avanti": {eye = [-13.5, 39.5, -1.8], at = [-17.6, 38.5, -0.8], fov = 44.0},
}
var args := {}

func _initialize() -> void:
	OS.set_environment("OPENRC_SCENERY_AUDIO", "off") # visual timings; avoid audio mixing in a capture-only process
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else "on"
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(int(args.get("width", 1280)), int(args.get("height", 720)))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var out := str(args.get("out", "user://landscape-upgrade"))
	DirAccess.make_dir_recursive_absolute(out)
	var parent := Node3D.new()
	root.add_child(parent)
	var loaded: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	Atmosphere.engine_shadows = str(args.get("engine_shadows", "on")) != "off"
	var snapshot := {}
	if args.has("time-of-day"):
		var lighting: Dictionary = LightingConfig.from_args(args)
		if not lighting.ok:
			printerr(lighting.errors)
			quit(1)
			return
		snapshot = SnapshotLighting.snapshot(lighting.config)
	var built := World.build(parent, loaded.field, Callable(), {}, snapshot)
	if built.field.get_node_or_null("DistantRidges") == null:
		parent.add_child(Ridges.build())
	var camera := Camera3D.new()
	camera.far = 21000
	camera.near = 0.1
	parent.add_child(camera)
	camera.current = true
	var flare: MeshInstance3D = parent.get_node_or_null("SunGlare")
	if flare == null:
		flare = Glare.attach(parent, built.environment)
	var aircraft := Airplane.build()
	parent.add_child(aircraft.root)
	aircraft.root.visible = false
	var blocker := MeshInstance3D.new()
	var block_mesh := BoxMesh.new()
	block_mesh.size = Vector3(2.8, 2.8, 0.2)
	blocker.mesh = block_mesh
	parent.add_child(blocker)
	blocker.visible = false
	var sky: ShaderMaterial = built.environment.sky.sky_material
	var sun: Vector3 = sky.get_shader_parameter("disc_dir")
	var original_disc: float = sky.get_shader_parameter("sun_disc")
	var original_cloud: float = sky.get_shader_parameter("cloud_coverage")
	var original_exposure: float = built.environment.tonemap_exposure
	var report := {adapter = RenderingServer.get_video_adapter_name(), driver = RenderingServer.get_video_adapter_api_version(),
		engine = Engine.get_version_info(), renderer = "gl_compatibility", width = root.size.x, height = root.size.y,
		arguments = args, cases = {}}
	var cases := str(args.get("cases", "pilot_north,postcard_club,glare_clear,glare_off,glare_blocked,glare_aircraft,glare_side,glare_night")).split(",")
	for case: String in cases:
		aircraft.root.visible = false
		blocker.visible = false
		flare.intensity = 1.0
		built.environment.tonemap_exposure = original_exposure
		sky.set_shader_parameter("sun_disc", original_disc)
		sky.set_shader_parameter("cloud_coverage", original_cloud)
		if case.begins_with("glare_"):
			sky.set_shader_parameter("cloud_coverage", 0.0) # isolate geometric occlusion, separately test production clouds
			if case.begins_with("glare_cloud"):
				sky.set_shader_parameter("cloud_coverage", 1.0)
			if case.begins_with("glare_low_exposure"):
				built.environment.tonemap_exposure = 0.15
			if case == "glare_half":
				flare.intensity = 0.5
			camera.fov = 38.0
			camera.look_at_from_position(Vector3(0, 2, 0), Vector3(0, 2, 0) + sun * 100.0)
			var source_pos := camera.position + sun * 70.0
			if case.ends_with("_off"):
				flare.intensity = 0.0
			if case == "glare_off":
				flare.intensity = 0.0
			if case in ["glare_blocked", "glare_blocked_off", "glare_partial", "glare_partial_off"]:
				blocker.visible = true
				blocker.position = source_pos
				blocker.basis = camera.basis
				if "partial" in case:
					blocker.position += camera.basis.x * 1.4
			if case.begins_with("glare_aircraft"):
				aircraft.root.visible = true
				aircraft.root.position = camera.position + sun * 50.0
				aircraft.root.basis = camera.basis * Basis(Vector3.RIGHT, PI / 2.0)
				if "left" in case:
					aircraft.root.position -= camera.basis.x * 1.4
				elif "right" in case:
					aircraft.root.position += camera.basis.x * 1.4
			if case in ["glare_side", "glare_side_off"]:
				camera.look_at(camera.position + Vector3(-sun.z, 0.2, sun.x))
			if case in ["glare_night", "glare_night_off"]:
				sky.set_shader_parameter("sun_disc", 0.0)
		else:
			var view: Dictionary = FLEET_VIEWS[case] if FLEET_VIEWS.has(case) else Postcards.VIEWS[case]
			camera.fov = view.fov
			camera.look_at_from_position(Frames.ned_to_render(view.eye), Frames.ned_to_render(view.at))
		for i in 60:
			World.update(built.environment, 1.5, Vector3.ZERO, camera.position + -camera.basis.z * 30.0, camera)
			await process_frame
			await RenderingServer.frame_post_draw
		var frames := []
		var last := Time.get_ticks_usec()
		for i in int(args.get("frames", 30)):
			await process_frame
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			frames.append((now - last) / 1000.0)
			last = now
		root.get_texture().get_image().save_png(out.path_join(case + ".png"))
		var raw_frames := frames.duplicate()
		frames.sort()
		report.cases[case] = {draws = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			visible_draws = RenderingServer.viewport_get_render_info(root.get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
			shadow_draws = RenderingServer.viewport_get_render_info(root.get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
			primitives = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			video_memory = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
			frame_ms_raw = raw_frames, median_ms = frames[frames.size()/2], p95_ms = frames[mini(frames.size()-1, ceili(frames.size()*0.95)-1)],
			p99_ms = frames[mini(frames.size()-1, ceili(frames.size()*0.99)-1)],
			glare_visible = flare.visible, glare_strength = flare.get_meta("strength", 0.0), exposure = built.environment.tonemap_exposure}
	var file := FileAccess.open(out.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("LU native capture complete: ", out)
	parent.free()
	quit()

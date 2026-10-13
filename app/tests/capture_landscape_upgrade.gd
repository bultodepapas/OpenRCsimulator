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
const SceneryMaterials := preload("res://scenery/scenery.gd")
const FLEET_VIEWS := {
	"lake_overview": {eye = [45.0, 50.0, -45.0], at = [110.0, 125.0, 0.45], fov = 55.0},
	"lake_shore": {eye = [78.0, 113.0, -1.5], at = [112.0, 130.0, 0.45], fov = 58.0},
	"lake_bottom": {eye = [109.5, 125.0, -55.0], at = [110.0, 125.0, 4.5], fov = 58.0},
	"hedge_detail": {eye = [238.0, 45.0, -1.65], at = [242.0, 43.0, -0.85], fov = 55.0},
	"herb_border": {eye = [-12.5, -2.0, -0.8], at = [-15.0, -3.0, -0.25], fov = 48.0},
	"meadow_low": {eye = [50.0, 92.0, -1.25], at = [61.0, 103.0, -0.4], fov = 48.0},
	"crop_close": {eye = [556.0, 316.0, -3.0], at = [569.0, 336.0, -0.3], fov = 52.0},
	"cultivated_overview": {eye = [542.0, 307.0, -32.0], at = [572.0, 342.0, -0.1], fov = 52.0},
	"tree_detail": {eye = [-44.0, -26.0, -1.6], at = [-49.0, -22.0, -6.0], fov = 50.0},
	"shrub_detail": {eye = [-18.0, -7.0, -0.8], at = [-19.75, -6.5, -0.4], fov = 45.0},
	"people_5m": {eye = [-12.5, -2.5, -1.65], at = [-17.5, -2.5, -0.9], fov = 38.0},
	"people_15m": {eye = [-2.5, -2.5, -1.65], at = [-17.5, -2.5, -0.9], fov = 38.0},
	"people_40m": {eye = [22.5, -2.5, -1.65], at = [-17.5, -2.5, -0.9], fov = 38.0},
	"cars_5m": {eye = [-31.2, -5.3, -1.65], at = [-37.25, -3.75, -0.7], fov = 52.0},
	"seated_5m": {eye = [-11.5, 12.3, -1.6], at = [-16.5, 11.5, -0.85], fov = 42.0},
	"pilot_5m": {eye = [5.0, -12.3, -1.65], at = [0.0, -13.0, -0.95], fov = 38.0},
	"flower_border": {eye = [-11.5, 4.0, -1.1], at = [-15.5, 3.2, -0.28], fov = 42.0},
	"entry_path": {eye = [-12.0, -8.0, -2.0], at = [-21.0, 0.0, -0.4], fov = 52.0},
	"horizon_raised25": {eye = [0.0, 0.0, -25.0], at = [4000.0, 0.0, -80.0], fov = 55.0},
	"horizon_raised120": {eye = [0.0, 0.0, -120.0], at = [4000.0, 0.0, -100.0], fov = 55.0},
	"gravel_close": {eye = [-35.0, -8.0, -1.2], at = [-39.0, -12.0, -0.04], fov = 45.0},
	"gravel_far": {eye = [-39.0, -15.0, -240.0], at = [-38.9, -15.0, 0.0], fov = 55.0},
	"twilight_aircraft": {eye = [0.0, 0.0, -1.7], at = [120.0, 0.0, -13.0], fov = 38.0},
	"twilight_background": {eye = [0.0, 0.0, -1.7], at = [120.0, 0.0, -13.0], fov = 38.0},
	"parked_stik": {eye = [-16.3, -35.7, -1.7], at = [-17.6, -38.0, -0.5], fov = 55.0},
	"parked_extra": {eye = [-16.3, -21.7, -1.7], at = [-17.6, -24.0, -0.5], fov = 55.0},
	"parked_p51": {eye = [-16.3, 27.5, -2.1], at = [-17.8, 24.0, -0.8], fov = 60.0},
	"parked_avanti": {eye = [-13.5, 39.5, -1.8], at = [-17.6, 38.5, -0.8], fov = 44.0},
	"runway_west": {eye = [15.0, -72.0, -2.2], at = [15.0, 51.0, -0.35], fov = 40.0},
	"runway_east_far": {eye = [15.0, 180.0, -6.0], at = [15.0, 0.0, -0.35], fov = 32.0},
	"runway_inside": {eye = [15.0, 15.0, -1.5], at = [15.0, 51.0, -0.35], fov = 40.0},
	"pit_service": {eye = [-15.0, -36.0, -1.8], at = [-19.9, -38.0, -1.02], fov = 30.0},
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
	var lake: Node3D = built.field.get_node_or_null("Lake")
	var lake_diagnostics := {}
	if lake != null:
		if str(args.get("lake_reflection", "on")) == "off":
			lake.get_node("Reflection").queue_free()
		var basin: MeshInstance3D = lake.get_node("Basin")
		var basin_arrays: Array = basin.mesh.surface_get_arrays(0)
		var bverts: PackedVector3Array = basin_arrays[Mesh.ARRAY_VERTEX]
		var binds: PackedInt32Array = basin_arrays[Mesh.ARRAY_INDEX]
		lake_diagnostics = {identity = lake.get_meta("identity"), bounds = str(basin.mesh.get_aabb()),
			vertices = bverts.size(), triangles = lake.get_meta("triangles"),
			mask_mode = built.field.get_node("rough").material_override.get_shader_parameter("lake_mask_mode"),
			mask_count = basin.material_override.get_shader_parameter("lake_bank_count"),
			bank_shader = basin.material_override.shader.resource_path,
			grass_texture = str(basin.material_override.get_shader_parameter("grass")),
			first_normal = str(basin_arrays[Mesh.ARRAY_NORMAL][0]),
			first_cross = str((bverts[binds[1]]-bverts[binds[0]]).cross(bverts[binds[2]]-bverts[binds[0]]))}
		if str(args.get("lake_diagnostic", "normal")) == "solid":
			var debug_material := StandardMaterial3D.new()
			debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			debug_material.cull_mode = BaseMaterial3D.CULL_DISABLED
			debug_material.albedo_color = Color(0.7, 0.4, 0.1)
			basin.material_override = debug_material
		elif str(args.get("lake_diagnostic", "normal")) == "two-sided":
			var debug_shader := Shader.new()
			debug_shader.code = basin.material_override.shader.code.replace("render_mode cull_back;", "render_mode cull_disabled;")
			basin.material_override.shader = debug_shader
		elif str(args.get("lake_diagnostic", "normal")) == "unlit":
			var debug_shader := Shader.new()
			debug_shader.code = basin.material_override.shader.code.replace("render_mode cull_back;", "render_mode unshaded, cull_back;")
			basin.material_override.shader = debug_shader
		elif str(args.get("lake_diagnostic", "normal")) == "maskless":
			basin.material_override.set_shader_parameter("lake_mask_mode", 0)
	if built.field.get_node_or_null("DistantRidges") == null:
		parent.add_child(Ridges.build())
	# LU-16 diagnostic controls preserve camera/time/exposure while isolating the seam.
	var horizon_diagnostic := str(args.get("horizon_diagnostic", "normal"))
	if horizon_diagnostic == "no-ridges":
		var ridges: Node3D = built.field.get_node_or_null("DistantRidges")
		if ridges != null:
			ridges.visible = false
	if horizon_diagnostic == "no-rim":
		for mat: ShaderMaterial in World.haze_materials(built.field):
			if mat.shader.resource_path == "res://render/ground.gdshader":
				mat.set_shader_parameter("rim_start", 100000.0)
				mat.set_shader_parameter("rim_end", 100001.0)
	# LU-12 isolated material A/B. Same world, geometry and draws, no production setting.
	if str(args.get("gravel_detail", "on")) in ["off", "legacy"]:
		var pending: Array[Node] = [parent]
		while not pending.is_empty():
			var item: Node = pending.pop_back()
			pending.append_array(item.get_children())
			if item is MeshInstance3D and item.mesh != null:
				for surface in item.mesh.get_surface_count():
					var material: Material = item.mesh.surface_get_material(surface)
					if material is ShaderMaterial and material.shader.resource_path == "res://scenery/gravel.gdshader":
						if str(args.gravel_detail) == "legacy":
							item.mesh.surface_set_material(surface, SceneryMaterials.opaque_material())
						else:
							material.set_shader_parameter("detail_strength", 0.0)
	var habitats: Node3D = built.field.get_node_or_null("Scenery/BotanicalHabitats")
	if habitats != null and str(args.get("botanicals", "on")) == "off":
		habitats.visible = false
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
	var lighting_helper := parent.get_node_or_null("AirfieldLighting")
	var sun: Vector3 = sky.get_shader_parameter("disc_dir")
	var original_disc: float = sky.get_shader_parameter("sun_disc")
	var original_cloud: float = sky.get_shader_parameter("cloud_coverage")
	var original_exposure: float = built.environment.tonemap_exposure
	var report := {adapter = RenderingServer.get_video_adapter_name(), driver = RenderingServer.get_video_adapter_api_version(),
		engine = Engine.get_version_info(), renderer = "gl_compatibility", width = root.size.x, height = root.size.y,
		arguments = args, lake = lake_diagnostics, field_build_ms = built.field_build_ms,
		reflection_slots = ProjectSettings.get_setting("rendering/reflections/reflection_atlas/reflection_count"),
		botanical_stats = built.field.get_node("Scenery").get_meta("stats") if built.field.has_node("Scenery") else {}, cases = {}}
	var cases := str(args.get("cases", "pilot_north,postcard_club,glare_clear,glare_off,glare_blocked,glare_aircraft,glare_side,glare_night")).split(",")
	for case: String in cases:
		if lighting_helper != null:
			lighting_helper.set_process(not case.begins_with("marker_"))
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
			var view: Dictionary = Postcards.VIEWS.runway_threshold if case.begins_with("marker_") else \
				FLEET_VIEWS[case] if FLEET_VIEWS.has(case) else Postcards.VIEWS[case]
			camera.fov = view.fov
			camera.look_at_from_position(Frames.ned_to_render(view.eye), Frames.ned_to_render(view.at))
			if case == "twilight_aircraft":
				aircraft.root.visible = true
				aircraft.root.position = Frames.ned_to_render([120.0, 0.0, -13.0])
				aircraft.root.basis = Basis(Vector3.UP, PI / 3.0) * Basis(Vector3.FORWARD, PI / 7.0)
			if case == "marker_occluded":
				blocker.visible = true
				blocker.position = Frames.ned_to_render([15.0, 55.0, -0.7])
				blocker.basis = camera.basis
		for i in 60:
			World.update(built.environment, float(args.get("botanical_clock", 1.5)), Vector3(float(args.get("botanical_wind", 0.0)), 0, 1.0 if args.has("botanical_wind") else 0.0), camera.position + -camera.basis.z * 30.0, camera)
			if horizon_diagnostic == "no-rim":
				for mat: ShaderMaterial in World.haze_materials(built.field):
					if mat.shader.resource_path == "res://render/ground.gdshader":
						mat.set_shader_parameter("rim_start", 100000.0)
						mat.set_shader_parameter("rim_end", 100001.0)
			if case.begins_with("marker_") and lighting_helper != null:
				# Hold sky/exposure fixed to isolate the lamp fade and real opaque-depth occlusion.
				var elevation := 3.0 if case == "marker_off" else -0.5 if case == "marker_half" else -4.0
				lighting_helper.apply_lighting({sun_elevation_deg = elevation})
			await process_frame
			await RenderingServer.frame_post_draw
		if args.has("horizon_diagnostic"):
			for mat: ShaderMaterial in World.haze_materials(built.field):
				if mat.shader.resource_path == "res://render/ground.gdshader":
					print("HORIZON diagnostic=", horizon_diagnostic, " rim=", mat.get_shader_parameter("rim_start"), ",", mat.get_shader_parameter("rim_end"))
		var frames := []
		var motion := str(args.get("motion", "off"))
		var camera_origin := camera.transform
		var aircraft_origin: Transform3D = aircraft.root.transform
		var motion_frames := []
		var last := Time.get_ticks_usec()
		for i in int(args.get("frames", 30)):
			if motion != "off":
				var elapsed := float(i) / 60.0
				if motion == "camera":
					camera.position = camera_origin.origin + camera_origin.basis.x * elapsed * 1.5
				elif motion == "aircraft":
					aircraft.root.position = aircraft_origin.origin + camera.basis.x * (elapsed * 2.0 - 2.0)
				World.update(built.environment, 1.5 + elapsed, Vector3(3.0, 0.0, 1.0), camera.position + -camera.basis.z * 30.0, camera)
			await process_frame
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			frames.append((now - last) / 1000.0)
			last = now
			if motion != "off":
				var filename := "%s_%03d.png" % [case, i]
				root.get_texture().get_image().save_png(out.path_join(filename))
				motion_frames.append({file = filename, time_s = float(i) / 60.0,
					camera_position = camera.position, aircraft_position = aircraft.root.position,
					exposure = built.environment.tonemap_exposure, glare_strength = flare.get_meta("strength", 0.0)})
		root.get_texture().get_image().save_png(out.path_join(case + ".png"))
		var raw_frames := frames.duplicate()
		frames.sort()
		report.cases[case] = {draws = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			visible_draws = RenderingServer.viewport_get_render_info(root.get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
			shadow_draws = RenderingServer.viewport_get_render_info(root.get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
			primitives = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			video_memory = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
			frame_ms_raw = raw_frames, median_ms = frames[frames.size()/2], p95_ms = frames[mini(frames.size()-1, ceili(frames.size()*0.95)-1)],
			motion = motion_frames, timing_valid = motion == "off",
			p99_ms = frames[mini(frames.size()-1, ceili(frames.size()*0.99)-1)],
			glare_visible = flare.visible, glare_strength = flare.get_meta("strength", 0.0), exposure = built.environment.tonemap_exposure,
			lamp_factor = lighting_helper.get_meta("night_factor", 0.0) if lighting_helper != null else 0.0,
			marker_center_px = camera.unproject_position(Frames.ned_to_render([15.0, 51.0, -0.35]))}
	var file := FileAccess.open(out.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("LU native capture complete: ", out)
	parent.free()
	quit()

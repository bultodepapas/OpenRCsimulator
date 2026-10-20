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
const ReferenceScenery := preload("res://scenery/scenery_loader.gd")
const ReferenceWoodland := preload("res://scenery/woodland_edge_habitat.gd")
const FLEET_VIEWS := {
	"plain_village": {eye = [-610.0, -960.0, -45.0], at = [-680.0, -760.0, -3.0], fov = 55.0},
	"plain_highway": {eye = [-350.0, 880.0, -22.0], at = [50.0, 945.0, -0.2], fov = 50.0},
	"plain_crop": {eye = [480.0, 400.0, -8.0], at = [520.0, 500.0, -0.2], fov = 55.0},
	"plain_overview": {eye = [-650.0, -950.0, -680.0], at = [350.0, 260.0, 0.0], fov = 58.0},
	"plain_east": {eye = [-450.0, 350.0, -220.0], at = [400.0, 950.0, 0.0], fov = 55.0},
	"plain_farm": {eye = [450.0, 160.0, -75.0], at = [610.0, 365.0, -3.0], fov = 55.0},
	"plain_farm_gate": {eye = [726.0, 705.0, -5.0], at = [748.0, 666.0, -2.0], fov = 58.0},
	"night_runway_club": {eye = [15.0, 72.0, -2.2], at = [15.0, -51.0, -0.35], fov = 40.0},
	"night_runway_airfield": {eye = [15.0, 72.0, -2.2], at = [15.0, -51.0, -0.35], fov = 40.0},
	"night_runway_off": {eye = [15.0, 72.0, -2.2], at = [15.0, -51.0, -0.35], fov = 40.0},
	"night_mast_ortho": {eye = [2.0, -10.0, -12.8], at = [-8.0, 0.0, -11.7], fov = 38.0},
	"night_campfire_side": {eye = [-24.0, 10.0, -1.4], at = [-24.0, 15.0, -0.45], fov = 44.0},
	"night_mast": {eye = [2.0, -10.0, -12.8], at = [-8.0, 0.0, -11.7], fov = 38.0},
	"night_campfire": {eye = [-20.0, 18.0, -1.4], at = [-24.0, 15.0, -0.45], fov = 44.0},
	"night_court": {eye = [-38.0, 27.0, -4.2], at = [-13.0, 3.0, -1.0], fov = 62.0},
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
## SUN-03: the crossing case's start and end angle from the sun (deg).
const SUN_CROSSING_DEG := 4.0

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
	# LU-28 A/B: custom reference layouts fail the strict woodland identity gate.
	# Restore the unchanged canonical woodland for an equal-content comparison.
	if str(args.get("plain_reference", "off")) == "on" and not built.field.has_node("Countryside"):
		var reference_scene: Node3D = built.field.get_node("Scenery")
		var old_edges: Node = reference_scene.get_node("WoodlandEdges")
		old_edges.free()
		var canonical := ReferenceScenery.load_from(ReferenceScenery.DEFAULT_PATH, loaded.field)
		var edges := ReferenceWoodland.build(loaded.field, canonical.scenery,
			str(reference_scene.get_meta("stats").quality))
		reference_scene.add_child(edges)
		var stats: Dictionary = reference_scene.get_meta("stats")
		stats.woodland_edge_plants = edges.get_meta("plants").size()
		stats.woodland_edge_triangles = edges.get_meta("triangles")
		stats.woodland_edge_batches = edges.get_meta("batches")
		reference_scene.set_meta("stats", stats)
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
	var report := {night_options = built.get("night_options", {}), adapter = RenderingServer.get_video_adapter_name(), driver = RenderingServer.get_video_adapter_api_version(),
		engine = Engine.get_version_info(), renderer = "gl_compatibility", width = root.size.x, height = root.size.y,
		arguments = args, lake = lake_diagnostics, field_build_ms = built.field_build_ms,
		reflection_slots = ProjectSettings.get_setting("rendering/reflections/reflection_atlas/reflection_count"),
		botanical_stats = built.field.get_node("Scenery").get_meta("stats") if built.field.has_node("Scenery") else {}, cases = {}}
	var cases := str(args.get("cases", "pilot_north,postcard_club,glare_clear,glare_off,glare_blocked,glare_aircraft,glare_side,glare_night")).split(",")
	for case: String in cases:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		if case.begins_with("night_runway_"):
			World.set_night_options(case.trim_prefix("night_runway_"), bool(built.night_options.campfire))
		else:
			World.set_night_options(str(built.night_options.field_lighting), bool(built.night_options.campfire))
		if lighting_helper != null:
			lighting_helper.set_process(not case.begins_with("marker_"))
		aircraft.root.visible = false
		blocker.visible = false
		flare.intensity = 1.0
		camera.set_meta(&"openrc_optics", "lens" if case.begins_with("glare_lens") else "eye") # SUN-04
		if flare.has_method("rest"):
			flare.rest()
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
			if case.begins_with("glare_offset_"):
				# SUN-02 veil: the pilot's view centred on the aircraft 60 m away, `deg` beside the sun. With
				# _hidden (aircraft removed) and _off (no glare) the four images give its displayed contrast.
				var parts := case.trim_prefix("glare_offset_").split("_")
				camera.fov = 30.0
				aircraft.root.visible = not "hidden" in parts
				_follow_aircraft(camera, aircraft.root, sun, float(parts[0]))
			if case.begins_with("glare_crossing"):
				camera.fov = 30.0
				aircraft.root.visible = not "hidden" in case
				_follow_aircraft(camera, aircraft.root, sun, -SUN_CROSSING_DEG)
			if case.begins_with("glare_disc_zoom"):
				# SUN-01: the disc itself (limb darkening, refraction flattening) and its aureole, sky only.
				camera.fov = 2.5
				flare.intensity = 0.0
			if case.begins_with("glare_lens"):
				camera.look_at(camera.position + (sun + sun.cross(Vector3.UP).normalized() * 0.25).normalized())
			if case in ["glare_night", "glare_night_off"]:
				sky.set_shader_parameter("sun_disc", 0.0)
		elif case == "sun_alignment":
			# The full-atmosphere L1 view is a presentation capture: cloud/aureole radiance clips the 0.53° disc
			# into a broad white region on llvmpipe. Keep the same apparent light direction, but remove those
			# overlays so a geometric centre can be measured independently of the projected coordinate.
			sky.set_shader_parameter("cloud_coverage", 0.0)
			sky.set_shader_parameter("sun_aureole_lin", Vector3.ZERO)
			flare.intensity = 0.0
			camera.fov = 50.0
			var eye := Vector3(0.0, 2.0, 0.0)
			var horizontal := Vector3(sun.x, 0.0, sun.z).normalized()
			var view_dir := horizontal * cos(deg_to_rad(25.0)) + Vector3.UP * sin(deg_to_rad(25.0))
			camera.look_at_from_position(eye, eye + view_dir * 100.0)
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
		if case.ends_with("_ortho"):
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = 10.0
		var warm_clock := float(args.get("botanical_clock", 1.5))
		for i in 60:
			if case.begins_with("glare_crossing"):
				# SUN-03 crossing: the aircraft flies from 4° before the sun to 4° past it in 1.33 s of simulation with the
				# view following it, then holds there 0.67 s (_late: 5 s).
				var step := 1.0 / 30.0 if i < 40 or not "late" in case else 0.25
				warm_clock = float(args.get("botanical_clock", 1.5)) + (float(i) / 30.0 if i < 40 else 40.0 / 30.0 + (i - 39) * step)
				_follow_aircraft(camera, aircraft.root, sun, lerpf(-SUN_CROSSING_DEG, SUN_CROSSING_DEG, minf(float(i) / 39.0, 1.0)))
			if case.begins_with("glare_afterimage"):
				# SUN-03: 1.33 s of simulation looking at the sun, then 40° away (out of the frame) for 0.67 s.
				warm_clock = float(args.get("botanical_clock", 1.5)) + float(i) / 30.0
				if i == 40:
					camera.look_at(camera.position + (sun + sun.cross(Vector3.UP).normalized() * 0.84).normalized())
					if case.begins_with("glare_afterimage_rested") and flare.has_method("rest"):
						flare.rest() # same view and veil, an eye that never saw the sun: the patch's control
			World.update(built.environment, warm_clock, Vector3(float(args.get("botanical_wind", 0.0)), 0, 1.0 if args.has("botanical_wind") else 0.0), camera.position + -camera.basis.z * 30.0, camera)
			if case == "sun_alignment":
				# World.update refreshes the production sky. Reapply the isolation after that update for the captured frame.
				sky.set_shader_parameter("cloud_coverage", 0.0)
				sky.set_shader_parameter("sun_aureole_lin", Vector3.ZERO)
			if i == 1 and flare.has_method("skyline") and flare.skyline() != null:
				flare.skyline().finish() # SUN-09: in flight it builds over ~500 frames; captures use the finished one
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
		var image_path := out.path_join(case + ".png")
		root.get_texture().get_image().save_png(image_path)
		var raw_frames := frames.duplicate()
		frames.sort()
		var case_report := {night_options = parent.get_meta("night_options", {}), draws = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			visible_draws = RenderingServer.viewport_get_render_info(root.get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
			shadow_draws = RenderingServer.viewport_get_render_info(root.get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
			primitives = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			video_memory = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
			frame_ms_raw = raw_frames, median_ms = frames[frames.size()/2], p95_ms = frames[mini(frames.size()-1, ceili(frames.size()*0.95)-1)],
			motion = motion_frames, timing_valid = motion == "off",
			p99_ms = frames[mini(frames.size()-1, ceili(frames.size()*0.99)-1)],
			glare_visible = flare.visible, glare_strength = flare.get_meta("strength", 0.0), exposure = built.environment.tonemap_exposure,
			glare_afterimage = flare.get_meta("afterimage", 0.0), glare_optics = flare.get_meta("optics", ""),
			glare_aureole_coeff = flare.get_meta("aureole_coeff", 0.0), glare_background_scale = flare.get_meta("background_scale", 0.0),
			glare_solar_uv = flare.get_meta("solar_uv", Vector2(-1.0, -1.0)),
			lamp_factor = lighting_helper.get_meta("night_factor", 0.0) if lighting_helper != null else 0.0,
			marker_center_px = camera.unproject_position(Frames.ned_to_render([15.0, 51.0, -0.35]))}
		if case == "sun_alignment":
			var sun_px := camera.unproject_position(camera.global_position + sun * 1000.0)
			case_report.sun_px = [sun_px.x, sun_px.y]
			case_report.image_sha256 = FileAccess.get_sha256(image_path)
			case_report.mode = "isolated solar-disc alignment"
			case_report.camera_fov_deg = camera.fov
			case_report.sun_disc = sky.get_shader_parameter("sun_disc")
			case_report.cloud_coverage = sky.get_shader_parameter("cloud_coverage")
			var aureole: Vector3 = sky.get_shader_parameter("sun_aureole_lin")
			case_report.sun_aureole_lin = [aureole.x, aureole.y, aureole.z]
		report.cases[case] = case_report
	var file := FileAccess.open(out.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("LU native capture complete: ", out)
	parent.free()
	quit()


## SUN-02/03: the pilot's view centred on the aircraft 60 m away, `offset_deg` from the sun across its azimuth, belly
## toward the eye (planform, the most visible attitude).
static func _follow_aircraft(camera: Camera3D, aircraft: Node3D, sun: Vector3, offset_deg: float) -> void:
	var offset_rad := deg_to_rad(offset_deg)
	var across := sun.cross(Vector3.UP).normalized()
	aircraft.position = camera.position + (sun * cos(offset_rad) + across * sin(offset_rad)).normalized() * 60.0
	camera.look_at(aircraft.position)
	aircraft.basis = camera.basis * Basis(Vector3.RIGHT, PI / 2.0)

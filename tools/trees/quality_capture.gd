## Tree-plan evidence using production assets and builders. No flight simulation.
## Run externally against an imported baseline/candidate app with --out=<new folder>.
extends SceneTree

const Library = preload("res://scenery/imported_vegetation.gd")
const Field = preload("res://render/field.gd")
const Loader = preload("res://data/field_loader.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const Clock = preload("res://render/shader_clock.gd")
const Frames = preload("res://render/frames.gd")
const Postcards = preload("res://scenery/postcards.gd")
const LightingConfig = preload("res://environment/time_of_day_config.gd")
const SnapshotLighting = preload("res://render/time_of_day_lighting.gd")
const GroundSurfaces = preload("res://physics/ground_surfaces.gd")
const GroundTerrain = preload("res://physics/ground_terrain.gd")
const LakeLoader = preload("res://data/lake_loader.gd")

var args: Dictionary = {}
var viewport: SubViewport
var stage: Node3D
var camera: Camera3D
var content: Node3D
var output: String
var views: Array[Dictionary] = []
var lighting: Dictionary = {}
var report: Dictionary = {format = "openrc-tree-quality v1", captures = [], samples = [], complete = false}


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		args[pair[0]] = pair[1] if pair.size() == 2 else "on"
	_run.call_deferred()


func _run() -> void:
	output = str(args.get("out", ""))
	if output.is_empty() or DisplayServer.get_name() == "headless":
		_fail("--out and a real Compatibility framebuffer are required")
		return
	if DirAccess.dir_exists_absolute(output) and not DirAccess.get_files_at(output).is_empty():
		_fail("output must be new or empty")
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		_fail("cannot create output")
		return
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		_fail("Compatibility is required")
		return
	if float(args.get("profile", "0")) < 0.0 or float(args.get("warmup", "10")) < 0.0:
		_fail("profile and warmup must be nonnegative")
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	RenderingServer.render_loop_enabled = false
	Clock.register()
	Clock.update(0.0, Vector3.ZERO)
	if args.has("engine_shadows"):
		Atmosphere.engine_shadows = str(args.engine_shadows) == "on"
	viewport = SubViewport.new()
	viewport.size = Vector2i(int(args.get("width", "1280")), int(args.get("height", "720")))
	var lod_threshold := float(args.get("mesh_lod_threshold", "1"))
	if not is_finite(lod_threshold) or lod_threshold < 0.0 or lod_threshold > 16.0:
		_fail("mesh_lod_threshold must be zero to sixteen pixels")
		return
	viewport.mesh_lod_threshold = lod_threshold
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	stage = Node3D.new()
	viewport.add_child(stage)
	if args.has("time-of-day"):
		var configured := LightingConfig.from_args(args)
		if not configured.ok:
			_fail(str(configured.errors))
			return
		lighting = SnapshotLighting.snapshot(configured.config)
		report["lighting"] = SnapshotLighting.context(configured.config, lighting)
	var env := WorldEnvironment.new()
	env.environment = Atmosphere.environment(lighting)
	Atmosphere.update_clouds(env.environment, 0.0)
	stage.add_child(env)
	var sun := Atmosphere.create_sun(stage, lighting)
	report["directional_shadows_enabled"] = sun.shadow_enabled
	report["directional_shadow_distance_m"] = sun.directional_shadow_max_distance
	camera = Camera3D.new()
	camera.near = 0.1
	camera.far = 21000.0
	stage.add_child(camera)
	camera.current = true
	var mode := str(args.get("mode", "field"))
	var construction_started := Time.get_ticks_usec()
	if mode == "gallery":
		if not _gallery():
			return
	elif mode == "field":
		if not _field():
			return
	else:
		_fail("mode must be field or gallery")
		return
	report["construction_ms"] = float(Time.get_ticks_usec() - construction_started) / 1000.0
	report["engine_static_memory_bytes"] = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	report["memory_scope"] = "Engine static CPU memory only; GPU residency is not measured. OS file caches are not reset."
	content.process_mode = Node.PROCESS_MODE_DISABLED
	if str(args.get("tree_shadows", "on")) == "off":
		_disable_tree_shadows(content)
	report["mode"] = mode
	report["arguments"] = args
	report["renderer"] = RenderingServer.get_current_rendering_method()
	report["adapter"] = RenderingServer.get_video_adapter_name()
	report["api"] = RenderingServer.get_video_adapter_api_version()
	report["godot"] = Engine.get_version_info().string
	report["viewport"] = [viewport.size.x, viewport.size.y]
	report["msaa"] = "4x"
	report["mesh_lod_threshold"] = viewport.mesh_lod_threshold
	report["scope"] = "Prescribed static rendering; no aircraft physics, active-flight ratio or pilot acceptance."
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
	var duration := float(args.get("profile", "0"))
	if args.has("motion"):
		if mode != "field" or duration > 0.0 or not await _motion():
			_fail("Motion requires field mode without profiling and valid route/frame count")
			return
	elif duration > 0.0:
		if not await _profile(duration):
			return
	else:
		for view in views:
			if not await _capture(view, str(view.id), 0.0, Vector3.ZERO):
				return
		if mode == "gallery":
			var view: Dictionary = views[0]
			for state in [
				["wind_start", 0.0, Vector3(5, 0, 0)],
				["wind_one", 1.0, Vector3(5, 0, 0)],
				["wind_repeat", 1.0, Vector3(5, 0, 0)],
				["wind_wrap", 1024.0, Vector3(5, 0, 0)],
				["wind_reverse", 1.0, Vector3(-5, 0, 0)],
			]:
				if not await _capture(view, state[0], state[1], state[2]):
					return
	report.complete = true
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	if file == null:
		_fail("cannot save report")
		return
	file.store_string(JSON.stringify(report, "\t", true) + "\n")
	file.close()
	viewport.queue_free()
	print("TREE QUALITY COMPLETE: ", output)
	quit(0)


func _field() -> bool:
	OS.set_environment("OPENRC_SCENERY", "on")
	OS.set_environment("OPENRC_SCENERY_AUDIO", "off")
	OS.set_environment("OPENRC_SCENERY_BIRDS", "off")
	if args.has("wind"):
		OS.set_environment("OPENRC_TREE_WIND", str(args.wind))
	if args.has("cell"):
		OS.set_environment("OPENRC_TREE_CELL_SIZE_M", str(args.cell))
	if args.has("woodland_meshes"):
		if str(args.woodland_meshes) not in ["on", "off"]:
			_fail("woodland_meshes must be on or off")
			return false
		OS.set_environment("OPENRC_WOODLAND_MESHES", str(args.woodland_meshes))
	if args.has("woodland_cards"):
		if str(args.woodland_cards) not in ["source", "legacy"]:
			_fail("woodland_cards must be source or legacy")
			return false
		OS.set_environment("OPENRC_WOODLAND_CARDS", str(args.woodland_cards))
	if args.has("woodland_shrubs"):
		if str(args.woodland_shrubs) not in ["source", "legacy"]:
			_fail("woodland_shrubs must be source or legacy")
			return false
		OS.set_environment("OPENRC_WOODLAND_SHRUBS", str(args.woodland_shrubs))
	var path := str(args.get("field", Loader.DEFAULT_PATH))
	var loaded: Dictionary = Loader.load_from(path)
	if not loaded.ok:
		_fail(str(loaded.errors))
		return false
	var grass_source := str(args.get("near_grass_source", "res://scenery/imported_near_grass.gd"))
	var meadow_source := str(args.get("meadow_source", "res://scenery/runway_meadow.gd"))
	if args.has("near_grass_source") or args.has("meadow_source"):
		# Capture-only source substitution preserves the full production build order,
		# including its current scenery, path, light, lake and course exclusions.
		var field_source := FileAccess.get_file_as_string("res://render/field.gd")
		for replacement: Array in [
			["near_grass_source", "res://scenery/imported_near_grass.gd", grass_source],
			["meadow_source", "res://scenery/runway_meadow.gd", meadow_source],
		]:
			if not args.has(replacement[0]): continue
			var original := "preload(%s)" % JSON.stringify(replacement[1])
			if not FileAccess.file_exists(replacement[2]) or field_source.count(original) != 1:
				_fail("source snapshot requires a readable source and the production field preload")
				return false
			field_source = field_source.replace(original, "preload(%s)" % JSON.stringify(replacement[2]))
		var captured_builder := GDScript.new()
		captured_builder.source_code = field_source
		if captured_builder.reload() != OK:
			_fail("cannot compile the source-snapshot field builder")
			return false
		content = captured_builder.build(loaded.field, lighting)
	else:
		content = Field.build(loaded.field, lighting)
	stage.add_child(content)
	if not _woodland_review(loaded.field): return false
	if args.has("card_shader_source"):
		var shader_path := str(args.card_shader_source)
		var shader_code := FileAccess.get_file_as_string(shader_path)
		if shader_code.is_empty():
			_fail("card_shader_source must be readable")
			return false
		var shader := Shader.new()
		shader.code = shader_code
		var materials: Array[ShaderMaterial] = []
		for batch: MultiMeshInstance3D in content.find_children("*", "MultiMeshInstance3D", true, false):
			for surface in batch.multimesh.mesh.get_surface_count():
				var material := batch.multimesh.mesh.surface_get_material(surface) as ShaderMaterial
				if material != null and material.shader.resource_path == "res://render/treeline.gdshader" and not materials.has(material):
					materials.append(material)
		if materials.is_empty():
			_fail("card shader comparison found no production tree-card materials")
			return false
		for material in materials:
			material.shader = shader
			material.set_shader_parameter("backlight", RenderingServer.shader_get_parameter_default(shader.get_rid(), "backlight"))
		report["card_shader_source"] = {path = shader_path, sha256 = FileAccess.get_sha256(shader_path), materials = materials.size()}
	else:
		report["card_shader_source"] = {path = "res://render/treeline.gdshader", sha256 = FileAccess.get_sha256("res://render/treeline.gdshader")}
	var foreground := content.get_node_or_null("NearGrass")
	if foreground != null:
		report["near_grass"] = {source = grass_source, source_sha256 = FileAccess.get_sha256(grass_source),
			clumps = foreground.get_meta("clumps", 0), triangles = foreground.get_meta("source_triangles", 0),
			placements = foreground.get_meta("cpu_placements", []),
			quality = foreground.get_meta("quality", ""), wind_material = foreground.has_meta("grass_wind")}
	var meadow := content.get_node_or_null("RunwayMeadow")
	if meadow != null:
		var accents: Array[String] = []
		for batch: Node in meadow.get_children():
			if batch is MultiMeshInstance3D and not str(batch.name).begins_with("grass_"):
				for index in batch.multimesh.instance_count:
					accents.append("%s:%d:%s" % [batch.name, index, batch.multimesh.get_instance_transform(index)])
		report["meadow"] = {source = meadow_source, source_sha256 = FileAccess.get_sha256(meadow_source),
			plants = meadow.get_meta("plants", 0), triangles = meadow.get_meta("source_triangles", 0),
			batches = meadow.get_child_count(), groups = meadow.get_meta("groups", {}),
			accent_transform_sha256 = "\n".join(accents).sha256_text()}
	var plants := content.get_node_or_null("Scenery/ImportedVegetationBatches")
	var tree_batches := 0
	var tree_instances := 0
	if plants != null:
		for child in plants.get_children():
			if child is MultiMeshInstance3D and Library.get_asset(str(child.name).get_slice("_Part_", 0)).get("role", "") == "tree":
				tree_batches += 1
				tree_instances += child.multimesh.instance_count
	report["imported_tree_batches"] = tree_batches
	report["imported_tree_instances"] = tree_instances
	report["field_sha256"] = FileAccess.get_sha256(path)
	report["vegetation_catalog_sha256"] = FileAccess.get_sha256(Library.CATALOG_PATH)
	for id in ["pilot_north", "car_park", "postcard_meadow", "aerial_overview"]:
		var source: Dictionary = Postcards.VIEWS[id]
		views.append({id = id, eye = Frames.ned_to_render(source.eye), at = Frames.ned_to_render(source.at), fov = source.fov})
	views.append({id = "forest_overview", eye = Vector3(0, 1900, 1250), at = Vector3(0, 0, -100), fov = 70.0})
	# Fixed camera at the unchanged shade-trees:06 placement; identical for old and new sources.
	views.append({id = "oak_close", eye = Vector3(27, 7, 49), at = Vector3(10.5, 5, 32), fov = 42.0})
	if args.has("views"):
		# L6c map-expansion cameras, now through the exact-size SubViewport.
		views.append({id = "farm_maples", eye = Frames.ned_to_render([520.0, 340.0, -8.0]),
			at = Frames.ned_to_render([568.0, 296.0, -5.0]), fov = 50.0})
		views.append({id = "forest_maple", eye = Frames.ned_to_render([-455.0, -737.0, -4.0]),
			at = Frames.ned_to_render([-480.0, -770.0, -5.0]), fov = 45.0})
		views.append({id = "front_woods_zoom", eye = Vector3(0.0, 1.7, 0.0), at = Vector3(0.0, 9.0, -430.0), fov = 10.0})
		views.append({id = "west_cards_close", eye = Frames.ned_to_render([-220.0, -495.0, -5.0]),
			at = Frames.ned_to_render([-249.5, -534.5, -13.0]), fov = 48.0})
		var pilot: Dictionary = loaded.field.pilot
		var pn := float(pilot.north)
		var pe := float(pilot.east)
		for pose: Array in [
			["grass_pilot", [pn, pe, -1.7], [pn + 30.0, pe + 8.0, 0.0], 55.0],
			["grass_low", [pn + 2.0, pe + 2.0, -0.55], [pn + 10.0, pe + 2.0, 0.0], 68.0],
			["grass_margin", [pn + 4.0, pe + 2.0, -0.55], [pn + 5.5, pe + 12.0, 0.0], 62.0],
			["grass_reverse", [pn + 14.0, pe + 12.0, -1.7], [pn - 5.0, pe + 1.0, 0.0], 55.0],
			["grass_overhead", [pn + 5.0, pe, -25.0], [pn + 5.1, pe, 0.0], 65.0],
			["grass_transition", [pn - 20.0, pe + 15.0, -0.65], [pn - 5.0, pe, 0.0], 55.0],
		]:
			views.append({id = pose[0], eye = Frames.ned_to_render(pose[1]), at = Frames.ned_to_render(pose[2]), fov = pose[3]})
		var selected: Array[Dictionary] = []
		for requested in str(args.views).split(",", false):
			var found := false
			for view in views:
				if view.id == requested:
					selected.append(view)
					found = true
			if not found:
				return false
		if selected.is_empty():
			return false
		views = selected
	return true


## Capture-only material controls; leave the cached production material immutable.
func _woodland_review(field: Dictionary) -> bool:
	var woodland := content.find_child("WoodlandEdges", true, false)
	if woodland == null:
		if args.has("woodland_shader_source") or args.has("woodland_root_lift") or str(args.get("views", "")).contains("woodland-"):
			_fail("woodland review requires the production WoodlandEdges subtree")
			return false
		return true
	var inventory := {plants = woodland.get_meta("plants", []).size(), triangles = woodland.get_meta("triangles", 0),
		batches = woodland.get_meta("batches", 0), recipe_sha256 = FileAccess.get_sha256("res://data/woodland_edges.json"),
		builder_sha256 = FileAccess.get_sha256("res://scenery/woodland_edge_habitat.gd"),
		mesh_details = woodland.get_meta("mesh_details", false), mesh_plans = woodland.get_meta("mesh_plans", []),
		fern_cards = woodland.get_meta("fern_cards", "legacy"),
		shrub_cards = woodland.get_meta("shrub_cards", "legacy"),
		plant_records = woodland.get_meta("plants", []), source_triangle_allowances = {}}
	var scenery := content.get_node_or_null("Scenery")
	if scenery != null:
		inventory.source_triangle_allowances = load("res://tests/scene_source_budget.gd").counts(scenery)
	if args.has("woodland_texture_filter"):
		if str(args.woodland_texture_filter) != "linear":
			_fail("woodland_texture_filter diagnostic accepts linear only")
			return false
		for batch: MultiMeshInstance3D in woodland.find_children("*", "MultiMeshInstance3D", true, false):
			if batch.material_override != null: continue
			var mesh := batch.multimesh.mesh.duplicate() as ArrayMesh
			if mesh == null: continue
			for surface in mesh.get_surface_count():
				var material := mesh.surface_get_material(surface).duplicate() as BaseMaterial3D
				if material != null:
					material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
					mesh.surface_set_material(surface, material)
			batch.multimesh.mesh = mesh
		inventory["mesh_texture_filter_diagnostic"] = "linear without mipmaps"
	var shader_path := str(args.get("woodland_shader_source", ""))
	if shader_path.is_empty():
		for child: Node in woodland.get_children():
			if child is MultiMeshInstance3D:
				shader_path = child.material_override.shader.resource_path
				break
	var shader_code := FileAccess.get_file_as_string(shader_path)
	if shader_code.is_empty():
		_fail("woodland_shader_source must be readable")
		return false
	var lift := -1.0
	if args.has("woodland_root_lift"):
		var value := str(args.woodland_root_lift)
		if not value.is_valid_float() or not is_finite(float(value)) or float(value) < 0.0 or float(value) > 1.0:
			_fail("woodland_root_lift must be finite and between zero and one")
			return false
		lift = float(value)
	var material: ShaderMaterial
	for child in woodland.get_children():
		if not child is MultiMeshInstance3D: continue
		if material == null:
			material = child.material_override.duplicate() as ShaderMaterial
			if material == null:
				_fail("woodland review requires production ShaderMaterials")
				return false
			if args.has("woodland_shader_source"):
				var shader := Shader.new()
				shader.code = shader_code
				material.shader = shader
			if lift >= 0.0:
				var supported := false
				for uniform: Dictionary in material.shader.get_shader_uniform_list():
					if str(uniform.name) == "root_lift": supported = true
				if not supported:
					_fail("woodland_root_lift requires a shader declaring that control")
					return false
				material.set_shader_parameter("root_lift", lift)
		child.material_override = material
	if material != null:
		var effective: Variant = material.get_shader_parameter("root_lift")
		if effective == null:
			effective = RenderingServer.shader_get_parameter_default(material.shader.get_rid(), "root_lift")
		inventory["root_lift"] = effective
		var color: Variant = RenderingServer.shader_get_parameter_default(material.shader.get_rid(), "root_color")
		inventory["root_color"] = [color.r, color.g, color.b] if color is Color else ([color.x, color.y, color.z] if color is Vector3 else null)
		var fractions: Variant = material.get_shader_parameter("grass_height_fractions")
		inventory["grass_height_fractions"] = [fractions.x, fractions.y] if fractions is Vector2 else null
		inventory["atlases"] = {}
		for parameter: String in ["impostor_atlas", "plain_atlas", "short_grass_atlas", "fern_atlas", "shrub_atlas_a", "shrub_atlas_b"]:
			var texture := material.get_shader_parameter(parameter) as Texture2D
			if texture != null:
				inventory.atlases[parameter] = {path = texture.resource_path, sha256 = FileAccess.get_sha256(texture.resource_path)}
	inventory["shader_path"] = shader_path
	inventory["shader_sha256"] = FileAccess.get_sha256(shader_path)
	inventory["shader_include_sha256"] = FileAccess.get_sha256("res://scenery/woodland_card_surface.gdshaderinc")
	report["woodland"] = inventory
	if not str(args.get("views", "")).contains("woodland-"): return true
	var table := GroundSurfaces.load_table()
	var lake := LakeLoader.load_from()
	if not table.ok or not lake.ok: return false
	var surfaces := GroundSurfaces.build(table.table, field)
	if not surfaces.ok: return false
	var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/woodland_edges.json"))
	for patch: Dictionary in recipe.patches:
		var center: Array = patch.floor_center_ne_m
		var ground := GroundTerrain.sample_validated(float(center[0]), float(center[1]), surfaces.rects, lake.lake)
		var target := Frames.ned_to_render([float(center[0]), float(center[1]), -ground[0]])
		for pose: Array in [["eye", Vector3(4.0, 1.65, 4.0)], ["overview", Vector3(7.0, 5.0, 7.0)],
				["close", Vector3(1.8, 0.8, 1.8)],
				["reverse", Vector3(-4.0, 1.65, -4.0)]]:
			views.append({id = str(patch.id) + "-" + str(pose[0]), eye = target + pose[1],
				at = target + Vector3.UP * 0.38, fov = 50.0})
	return true


func _gallery() -> bool:
	var ids := str(args.get("ids", "common_tree_1,common_tree_3,pine_1")).split(",")
	var asset_height := float(args.get("asset_height_m", "10.0"))
	if not is_finite(asset_height) or asset_height < 0.1 or asset_height > 50.0:
		_fail("gallery asset_height_m must be between 0.1 and 50 metres")
		return false
	var view_scale := asset_height / 10.0
	var batches: Dictionary = {}
	var selected: Array[Dictionary] = []
	for index in ids.size():
		var id := ids[index]
		var asset: Dictionary = Library.get_asset(id)
		if asset.is_empty():
			_fail("missing gallery asset " + id)
			return false
		var origin := Vector3(index * 24.0 * view_scale, 0, 0)
		var placement := Library.fit_to_height(id, asset_height, Transform3D(Basis.IDENTITY, origin))
		Library.queue(batches, id, placement, 101 + index, id)
		selected.append(asset)
		views.append({id = id, eye = origin + Vector3(0, 5, 20) * view_scale,
			at = origin + Vector3(0, 5, 0) * view_scale, fov = 36.0})
	var options := {tree_wind = str(args.get("wind", "off")) == "on", tree_cell_size_m = float(args.get("cell", "0"))}
	if options.tree_wind or options.tree_cell_size_m > 0.0:
		# Dynamic call keeps the external probe usable against the unmodified baseline API.
		content = Library.new().call("build", batches, false, options)
	else:
		content = Library.build(batches)
	stage.add_child(content)
	report["assets"] = selected
	report["batch_count"] = content.get_child_count()
	report["vegetation_catalog_sha256"] = FileAccess.get_sha256(Library.CATALOG_PATH)
	var target := Vector3(0, 5, 0) * view_scale
	views.append({id = "back", eye = Vector3(0, 5, -20) * view_scale, at = target, fov = 36.0})
	views.append({id = "underside", eye = Vector3(0, 0.5, 12) * view_scale, at = target, fov = 50.0})
	views.append({id = "overhead", eye = Vector3(0, 25, 0.01) * view_scale, at = target, fov = 40.0})
	return true


func _disable_tree_shadows(node: Node) -> void:
	if node is MultiMeshInstance3D and (str(node.name).contains("tree") or str(node.name).contains("pine")):
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_tree_shadows(child)


func _place(view: Dictionary) -> void:
	camera.fov = float(view.fov)
	camera.look_at_from_position(view.eye, view.at)


func _frame() -> void:
	await process_frame
	RenderingServer.force_draw(false)


func _counters() -> Dictionary:
	var rid := viewport.get_viewport_rid()
	return {
		draws = RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		primitives = RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
		shadow_draws = RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
	}


func _capture(view: Dictionary, id: String, clock: float, wind: Vector3) -> bool:
	_place(view)
	Clock.update(clock, wind)
	for _index in 4:
		await _frame()
	var path := output.path_join(id + ".png")
	var image := viewport.get_texture().get_image()
	if image.is_empty() or image.save_png(path) != OK:
		_fail("empty/failed capture " + id)
		return false
	report.captures.append({id = id, sha256 = FileAccess.get_sha256(path), counters = _counters(),
		clock = clock, wind = [wind.x, wind.y, wind.z], eye = [view.eye.x, view.eye.y, view.eye.z],
		at = [view.at.x, view.at.y, view.at.z], fov = view.fov})
	return true


func _motion() -> bool:
	var route := str(args.motion)
	var count := int(args.get("frames", "192"))
	var wind_mps := float(args.get("wind_mps", "5"))
	if route not in ["oak-approach", "card-orbit", "forest-pan", "car-park-wind", "grass-margin-pan", "woodland-orbit"] or count < 24 or count > 480 \
			or not is_finite(wind_mps) or wind_mps < 0.0 or wind_mps > 20.0:
		return false
	var loaded: Dictionary = Loader.load_from(str(args.get("field", Loader.DEFAULT_PATH)))
	var treeline: Dictionary = {}
	for item: Dictionary in loaded.field.objects:
		if item.type == "treeline": treeline = item
	if treeline.is_empty(): return false
	var first: Array = treeline.positions[0]
	var identity: Dictionary = load("res://render/treeline.gd").identity(float(first[0]), float(first[1]))
	var card: Vector3 = Frames.ned_to_render([float(first[0]) + float(loaded.field.pilot.north),
		float(first[1]) + float(loaded.field.pilot.east), -float(identity.height) * 0.55])
	report["scope"] = "Offline prescribed camera motion through production trees at 24 samples/s; no aircraft simulation or native frame pacing. Geometry/render counters qualify only the captured route."
	report["motion"] = {route = route, fps = 24, frames = count, wind_mps = wind_mps, card_north_east = first,
		card_identity = identity, tree_mesh_lod_threshold_pixels = viewport.mesh_lod_threshold}
	for index in count:
		var phase := float(index) / float(count - 1)
		var view := {id = "frame-%04d" % index, eye = Vector3.ZERO, at = Vector3.ZERO, fov = 50.0}
		match route:
			"oak-approach":
				var distance := 8.0 + 242.0 * sin(PI * phase)
				view.at = Vector3(10.5, 5.0, 32.0)
				view.eye = view.at + Vector3(0.70, 0.03, 0.714).normalized() * distance
				view.fov = 42.0
			"card-orbit":
				var angle := phase * TAU
				view.at = card
				view.eye = card + Vector3(cos(angle) * 27.0, -4.0 + 18.0 * sin(PI * phase), sin(angle) * 27.0)
			"forest-pan":
				view.eye = Vector3(0.0, 1.7, 0.0)
				var angle := deg_to_rad(-35.0 + 70.0 * phase)
				view.at = view.eye + Vector3(sin(angle), 0.03, -cos(angle)) * 500.0
			"car-park-wind":
				# L15b-R2: fixed postcard camera; only the clock advances, so close downloaded
				# trees (Quercus, pine, static maple) show their own sway and flutter.
				var source: Dictionary = Postcards.VIEWS["car_park"]
				view.eye = Frames.ned_to_render(source.eye)
				view.at = Frames.ned_to_render(source.at)
				view.fov = float(source.fov)
			"grass-margin-pan":
				var pn := float(loaded.field.pilot.north)
				var pe := float(loaded.field.pilot.east)
				view.eye = Frames.ned_to_render([pn + 4.0, pe + 1.0 + 6.0 * phase, -0.6])
				view.at = Frames.ned_to_render([pn + 5.5, pe + 11.0 + 6.0 * phase, -0.1])
				view.fov = 62.0
			"woodland-orbit":
				if not str(views[0].id).begins_with("woodland-edge-"):
					_fail("woodland-orbit requires one selected woodland view")
					return false
				var target: Vector3 = views[0].at
				var angle := phase * TAU
				view.at = target
				view.eye = target + Vector3(cos(angle) * 6.0, 1.27, sin(angle) * 6.0)
				view.fov = 55.0
		if not await _capture(view, view.id, float(index) / 24.0, Vector3(wind_mps, 0.0, 0.0)):
			return false
	return true


func _profile(duration: float) -> bool:
	var view: Dictionary = views[0]
	var requested := str(args.get("view", view.id))
	var found := false
	for candidate in views:
		if candidate.id == requested:
			view = candidate
			found = true
	if not found:
		_fail("unknown view " + requested)
		return false
	_place(view)
	var warmup := float(args.get("warmup", "10"))
	var wind_mps := float(args.get("wind_mps", "5"))
	if not is_finite(wind_mps) or wind_mps < 0.0 or wind_mps > 20.0:
		_fail("wind_mps must be zero to twenty")
		return false
	var started := Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - started) / 1000000.0 < warmup:
		await _frame()
	started = Time.get_ticks_usec()
	var previous := started
	while float(Time.get_ticks_usec() - started) / 1000000.0 < duration:
		Clock.update(float(Time.get_ticks_usec() - started) / 1000000.0, Vector3(wind_mps, 0, 0))
		await _frame()
		var now := Time.get_ticks_usec()
		report.samples.append({wall_ms = float(now - previous) / 1000.0,
			cpu_ms = RenderingServer.viewport_get_measured_render_time_cpu(viewport.get_viewport_rid()),
			gpu_ms = RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid())})
		previous = now
	report["duration_s"] = float(Time.get_ticks_usec() - started) / 1000000.0
	report["warmup_s"] = warmup
	report["profile_wind_mps"] = wind_mps
	report["view"] = view.id
	report["counters"] = _counters()
	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

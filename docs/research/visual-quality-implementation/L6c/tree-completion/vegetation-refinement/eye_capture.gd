## Native static fixture for the four default woodland-edge patches and one field-wide view.
## Run against the frozen candidate app with Compatibility rendering and a real display:
## godot --path <candidate-app> --script C:/DEVELOPMENT/OpenRCsimulator/tmp/tree-completion/woodland_capture.gd -- --out=<new-folder>
extends SceneTree

const FieldBuilder = preload("res://render/field.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const LakeLoader = preload("res://data/lake_loader.gd")
const GroundSurfaces = preload("res://physics/ground_surfaces.gd")
const GroundTerrain = preload("res://physics/ground_terrain.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const ShaderClock = preload("res://render/shader_clock.gd")
const Frames = preload("res://render/frames.gd")

const WOODLAND_DATA := "res://data/woodland_edges.json"
const FIELD_PATH := FieldLoader.DEFAULT_PATH
const SCENERY_PATH := "res://data/scenery/default.json"
const LAKE_PATH := LakeLoader.DEFAULT_PATH

var _args: Dictionary = {}
var _out := ""
var _viewport: SubViewport
var _stage: Node3D
var _camera: Camera3D
var _report: Dictionary = {format = "openrc-woodland-edge-capture v1", captures = [], complete = false}


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		_args[pair[0]] = pair[1] if pair.size() == 2 else "on"
	_run.call_deferred()


func _run() -> void:
	_out = str(_args.get("out", ""))
	if _out.is_empty() or DisplayServer.get_name() == "headless":
		_fail("--out and a real Compatibility framebuffer are required")
		return
	if DirAccess.dir_exists_absolute(_out) and not DirAccess.get_files_at(_out).is_empty():
		_fail("output must be new or empty")
		return
	if DirAccess.make_dir_recursive_absolute(_out) != OK:
		_fail("cannot create output directory")
		return
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		_fail("Compatibility rendering is required")
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	RenderingServer.render_loop_enabled = false
	ShaderClock.register()
	ShaderClock.update(0.0, Vector3.ZERO)
	OS.set_environment("OPENRC_SCENERY", "on")
	OS.set_environment("OPENRC_SCENERY_AUDIO", "off")
	OS.set_environment("OPENRC_SCENERY_BIRDS", "off")
	Atmosphere.engine_shadows = true

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(int(_args.get("width", "1280")), int(_args.get("height", "720")))
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_stage = Node3D.new()
	_viewport.add_child(_stage)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = Atmosphere.environment()
	Atmosphere.update_clouds(world_environment.environment, 0.0)
	_stage.add_child(world_environment)
	var sun := Atmosphere.create_sun(_stage)
	_camera = Camera3D.new()
	_camera.near = 0.1
	_camera.far = 21000.0
	_stage.add_child(_camera)
	_camera.current = true

	var field_result: Dictionary = FieldLoader.load_from(FIELD_PATH)
	if not field_result.ok:
		_fail("default field failed to load: " + str(field_result.errors))
		return
	var lake_result: Dictionary = LakeLoader.load_from(LAKE_PATH)
	if not lake_result.ok:
		_fail("default lake failed to load: " + str(lake_result.errors))
		return
	var field: Dictionary = field_result.field
	var lake: Dictionary = lake_result.lake
	var started := Time.get_ticks_usec()
	var content := FieldBuilder.build(field)
	_stage.add_child(content)
	content.process_mode = Node.PROCESS_MODE_DISABLED
	_report["field_build_ms"] = float(Time.get_ticks_usec() - started) / 1000.0
	_report["field_id"] = field.get("id", "")
	_report["renderer"] = RenderingServer.get_current_rendering_method()
	_report["adapter"] = RenderingServer.get_video_adapter_name()
	_report["api"] = RenderingServer.get_video_adapter_api_version()
	_report["godot"] = Engine.get_version_info().string
	_report["viewport"] = [_viewport.size.x, _viewport.size.y]
	_report["msaa"] = "4x"
	_report["landscape_lighting"] = {
		"environment_background": "production Atmosphere.environment()",
		"directional_shadows_enabled": sun.shadow_enabled,
		"directional_shadow_distance_m": sun.directional_shadow_max_distance,
		"engine_shadows": Atmosphere.engine_shadows,
	}
	_report["source_sha256"] = {
		"field": FileAccess.get_sha256(FIELD_PATH),
		"scenery": FileAccess.get_sha256(SCENERY_PATH),
		"lake": FileAccess.get_sha256(LAKE_PATH),
		"woodland_recipe": FileAccess.get_sha256(WOODLAND_DATA),
		"woodland_builder": FileAccess.get_sha256("res://scenery/woodland_edge_habitat.gd"),
	}
	_report["scope"] = "Static visual fixture from full production Field.build with field surfaces, scenery, woodland edges, lake, default atmosphere and sun. No aircraft simulation or user-acceptance claim."

	var woodland := content.find_child("WoodlandEdges", true, false)
	if woodland == null:
		_fail("full Field.build did not attach WoodlandEdges")
		return
	var table := GroundSurfaces.load_table()
	if not table.ok:
		_fail("ground surface table failed to load")
		return
	var surfaces := GroundSurfaces.build(table.table, field)
	if not surfaces.ok:
		_fail("default ground surfaces failed to build")
		return
	var plants: Array = woodland.get_meta("plants", [])
	_report["woodland_summary"] = {
		"triangles": woodland.get_meta("triangles", 0),
		"batches": woodland.get_meta("batches", 0),
		"plant_count": plants.size(),
	}
	_report["plants"] = _plant_ground_records(plants, surfaces.rects, lake)
	var patches := _patch_views(_report.plants)
	if patches.size() != 4 or plants.size() != 60:
		_fail("expected four woodland patches and sixty built plants")
		return
	var limit := int(_args.get("limit", "5"))
	if limit < 1 or limit > 5:
		_fail("--limit must be between one close view and all five views")
		return
	_report["requested_view_limit"] = limit
	var close_count := mini(limit, patches.size())
	for index in close_count:
		var view: Dictionary = patches[index]
		if not await _capture(view):
			return
	if limit == 5 and not await _capture(_wide_view()):
		return
	_report["complete"] = true
	var report_file := FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE)
	if report_file == null:
		_fail("cannot write report.json")
		return
	report_file.store_string(JSON.stringify(_report, "\t", true) + "\n")
	report_file.close()
	_viewport.queue_free()
	print("WOODLAND EDGE CAPTURE COMPLETE: ", _out)
	quit(0)


func _plant_ground_records(plants: Array, surfaces: PackedFloat64Array, lake: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for plant_value: Variant in plants:
		if typeof(plant_value) != TYPE_DICTIONARY:
			continue
		var plant: Dictionary = plant_value
		var north := float(plant.get("north", 0.0))
		var east := float(plant.get("east", 0.0))
		var ground := GroundTerrain.sample_validated(north, east, surfaces, lake)
		result.append({
			"id": str(plant.get("id", "")),
			"asset_id": str(plant.get("asset_id", "")),
			"patch": str(plant.get("patch", "")),
			"north_m": north,
			"east_m": east,
			"plant_height_m": float(plant.get("height_m", 0.0)),
			"ground_sample_ned_m": ground,
			"ground_world_up_m": float(ground[0]) if ground.size() == 3 else null,
			"ground_valid": ground.size() == 3,
		})
	return result


func _patch_views(plants: Array) -> Array[Dictionary]:
	var by_patch: Dictionary = {}
	for plant_value: Dictionary in plants:
		var patch_id := str(plant_value.get("patch", ""))
		if not by_patch.has(patch_id):
			by_patch[patch_id] = []
		by_patch[patch_id].append(plant_value)
	var result: Array[Dictionary] = []
	var patch_ids: Array = by_patch.keys()
	patch_ids.sort()
	for patch_id: String in patch_ids:
		var items: Array = by_patch[patch_id]
		var north := 0.0
		var east := 0.0
		var ground_up := 0.0
		var valid_ground := true
		for plant: Dictionary in items:
			north += float(plant.north_m)
			east += float(plant.east_m)
			valid_ground = valid_ground and bool(plant.ground_valid)
			ground_up += float(plant.ground_world_up_m if plant.ground_valid else 0.0)
		north /= float(items.size())
		east /= float(items.size())
		ground_up /= float(items.size())
		var target := Frames.ned_to_render([north, east, -ground_up])
		var at := target + Vector3.UP * 0.38
		result.append({
			"id": str(patch_id) + "_close",
			"patch_id": str(patch_id),
			"eye": target + Vector3(4.0, 1.65, 4.0),
			"at": at,
			"fov": 50.0,
			"target_north_m": north,
			"target_east_m": east,
			"mean_ground_world_up_m": ground_up,
			"ground_samples_valid": valid_ground,
			"plant_ids": items.map(func(plant: Dictionary) -> String: return str(plant.id)),
		})
	return result


func _wide_view() -> Dictionary:
	return {
		"id": "woodland_edges_field_wide",
		"eye": Vector3(0.0, 1350.0, 980.0),
		"at": Vector3(0.0, 0.0, -100.0),
		"fov": 58.0,
	}


func _capture(view: Dictionary) -> bool:
	_camera.fov = float(view.fov)
	_camera.look_at_from_position(view.eye, view.at, Vector3.UP)
	for _frame_index in 5:
		await process_frame
		RenderingServer.force_draw(false)
	var path := _out.path_join(str(view.id) + ".png")
	var image := _viewport.get_texture().get_image()
	if image.is_empty() or image.save_png(path) != OK:
		_fail("empty/failed capture " + str(view.id))
		return false
	var record := view.duplicate(true)
	record["sha256"] = FileAccess.get_sha256(path)
	record["width"] = image.get_width()
	record["height"] = image.get_height()
	_report.captures.append(record)
	return true


func _fail(message: String) -> void:
	printerr("WOODLAND EDGE CAPTURE FAILED: ", message)
	quit(1)

## L6c static inspection matrix using production world, aircraft and pilot camera.
## Synthetic poses; no simulation, attitude recognition or frame-time acceptance claim.
extends "../../research/performance/visibility_capture.gd"

var destination := ""
var light_name := "noon"
var image_size := Vector2i(1280, 720)
var records: Array[Dictionary] = []
var disabled_aircraft_shadow_sources := 0


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): destination = arg.trim_prefix("--out=")
		elif arg.begins_with("--light="): light_name = arg.trim_prefix("--light=")
		elif arg == "--1080": image_size = Vector2i(1920, 1080)
		else:
			_fail("Unknown option: " + arg)
			return
	if destination.is_empty() or DirAccess.dir_exists_absolute(destination) or FileAccess.file_exists(destination) \
			or light_name not in ["noon", "low_sun", "sunset", "night"]:
		_fail("Use a new --out directory and --light=noon|low_sun|sunset|night")
		return
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "gl_compatibility":
		_fail("Native Compatibility required")
		return
	if DirAccess.make_dir_recursive_absolute(destination) != OK:
		_fail("Cannot create output")
		return
	OS.set_environment("OPENRC_SCENERY", "on")
	OS.set_environment("OPENRC_SCENERY_THEME", "")
	OS.set_environment("OPENRC_SCENERY_QUALITY", "high")
	OS.set_environment("OPENRC_SCENERY_FILE", "res://data/scenery/default.json")
	OS.set_environment("OPENRC_SCENERY_AUDIO", "off")
	OS.set_environment("OPENRC_SCENERY_BIRDS", "off")
	OS.set_environment("OPENRC_TREE_WIND", "on")
	OS.set_environment("OPENRC_TREE_CELL_SIZE_M", "0")
	OS.set_environment("OPENRC_LANDSCAPE_UPGRADE", "on")
	OS.set_environment("OPENRC_SUN_GLARE", "1.0")
	root.mode = Window.MODE_MINIMIZED
	RenderingServer.render_loop_enabled = false
	var field_loader: Script = load("res://data/field_loader.gd")
	var loaded: Dictionary = field_loader.load_from()
	if not loaded.ok:
		_fail("Field failed validation")
		return
	var field: Dictionary = loaded.field
	var config_script: Script = load("res://environment/time_of_day_config.gd")
	var lighting_script: Script = load("res://render/time_of_day_lighting.gd")
	var checked: Dictionary = config_script.preset(config_script.defaults(), "noon" if light_name == "low_sun" else light_name)
	if not checked.ok:
		_fail("Lighting failed validation")
		return
	var config: Dictionary = checked.config
	if light_name == "low_sun": config.local_seconds = 17 * 3600 + 40 * 60
	var lighting: Dictionary = lighting_script.snapshot(config)
	_viewport = SubViewport.new()
	_viewport.size = image_size
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var scene := Node3D.new()
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	_viewport.add_child(scene)
	var world: Script = load("res://render/world/world.gd")
	world.build(scene, field, Callable(), {time_of_day = false}, lighting, {field_lighting = "club", campfire = false})
	var clock_script: Script = load("res://render/shader_clock.gd")
	clock_script.update(0.0, Vector3.ZERO)
	var treeline: Node3D = scene.find_child("treeline", true, false)
	if treeline == null:
		_fail("Production treeline is missing")
		return
	var imported_tree_batches := _imported_tree_batches(scene)
	if imported_tree_batches.is_empty():
		_fail("Production imported tree batches are missing")
		return
	var pilot: Script = load("res://render/pilot_camera.gd")
	var camera: Camera3D = pilot.create(scene, field.pilot)
	var builder: Script = load("res://render/airplane.gd")
	var catalog: Script = load("res://app_state/aircraft_catalog.gd")
	var data_script: Script = load("res://physics/aircraft_data.gd")
	var frame_script: Script = load("res://render/frames.gd")
	var shadow_script: Script = load("res://render/shadow.gd")
	for aircraft: String in ["jensen-das-ugly-stik-60", "p51d-mustang-120"]:
		var data: Dictionary = data_script.load_file(catalog.entry(aircraft).data)
		var built: Dictionary = builder.build(aircraft)
		var model: Node3D = built.root
		var aircraft_shadow_sources := _disable_aircraft_shadows(model)
		if aircraft_shadow_sources < 1:
			_fail("Aircraft geometry has no shadow-cast controls")
			return
		disabled_aircraft_shadow_sources += aircraft_shadow_sources
		var span: float = shadow_script.model_extent(model).x
		var datum: Vector2 = builder.datum(aircraft)
		var cg: Vector3 = frame_script.cg_in_model_frame(data.model.cg_le, datum.x, datum.y)
		scene.add_child(model)
		for distance: float in [20.0, 50.0, 100.0]:
			for background: String in ["sky", "trees"]:
				for zoom: bool in [false, true]:
					var azimuth := 9.0
					var elevation: float = ELEVATIONS[background]
					var az := deg_to_rad(azimuth)
					var el := deg_to_rad(elevation)
					var target: Vector3 = frame_script.ned_to_render([
						float(field.pilot.north) + distance * cos(az) * cos(el),
						float(field.pilot.east) + distance * sin(az) * cos(el),
						float(field.pilot.down) - float(field.pilot.eye_height) - distance * sin(el)])
					var group := "%s-%03dm-%s-%s" % [aircraft, distance, background, "zoom" if zoom else "normal"]
					var background_png := group + "-background.png"
					var without_trees_png := group + "-without-trees.png"
					pilot.aim(camera, target, Transform3D.IDENTITY, false, span if zoom else 0.0)
					model.visible = false
					await _save_frame(background_png, true)
					var treeline_was_visible := treeline.visible
					treeline.visible = false
					var imported_tree_visibility: Array[bool] = []
					for batch: MultiMeshInstance3D in imported_tree_batches:
						imported_tree_visibility.append(batch.visible)
						batch.visible = false
					await _save_frame(without_trees_png, false)
					treeline.visible = treeline_was_visible
					for batch_index in range(imported_tree_batches.size()):
						imported_tree_batches[batch_index].visible = imported_tree_visibility[batch_index]
					model.visible = true
					var camera_distance: float = camera.global_position.distance_to(target)
					var poses: Array = POSES.keys() if distance == 100.0 else ["level", "inverted"]
					for pose_name: String in poses:
						var pose: Array = POSES[pose_name]
						var basis: Basis = frame_script.attitude_to_render(deg_to_rad(azimuth + 90.0), deg_to_rad(pose[0]), deg_to_rad(pose[1]))
						model.transform = frame_script.root_transform(basis, target, cg)
						var filename := group + "-" + pose_name + ".png"
						await _save_frame(filename, false)
						records.append({png = filename, sha256 = FileAccess.get_sha256(destination.path_join(filename)),
							background_png = background_png, background_sha256 = FileAccess.get_sha256(destination.path_join(background_png)),
							aircraft = aircraft, without_trees_png = without_trees_png,
						without_trees_sha256 = FileAccess.get_sha256(destination.path_join(without_trees_png)),
							pose = pose_name, requested_background = background, distance_m = camera_distance,
						requested_distance_m = int(distance),
							autozoom = zoom, fov_deg = camera.fov, camera_transform = _transform_array(camera.global_transform),
							projected_span_px = pilot.projected_px(span, camera_distance, camera.fov, image_size.y)})
		model.free()
	# 2 aircraft × 40 combinations each: 20/50 m use two attitudes, 100 m uses all six.
	if records.size() != 80:
		_fail("Readability matrix did not produce all 80 aircraft captures")
		return
	var report := {format = "openrc-tree-readability v1", complete = true, captures = records,
		viewport = [image_size.x, image_size.y], renderer = RenderingServer.get_current_rendering_method(),
		adapter = RenderingServer.get_video_adapter_name(), godot = Engine.get_version_info().string,
		api = RenderingServer.get_video_adapter_api_version(), msaa = "4x",
		lighting = lighting_script.context(config, lighting), lighting_name = light_name,
		build_options = {
			scenery = load("res://scenery/scenery.gd").options(),
			landscape_upgrade = load("res://render/landscape_upgrade/options.gd").enabled(),
			sun_glare = load("res://render/landscape_upgrade/options.gd").glare_strength(),
		},
		aircraft_shadow_sources_disabled = disabled_aircraft_shadow_sources,
		scenery_shadow_casting_unchanged = true,
		field_sha256 = FileAccess.get_sha256("res://data/fields/default.json"),
		scope = "Synthetic static inspection, calm fixed clock, production SDR lighting and camera. Aircraft geometry does not cast ground shadows in this fixture; scenery shadow casting is unchanged. Requested tree/sky backgrounds need image review. Night uses normal aircraft materials without optional aircraft night kit. No human readability or physical-flight acceptance."}
	var file := FileAccess.open(destination.path_join("manifest.json"), FileAccess.WRITE)
	if file == null:
		_fail("Cannot write manifest")
		return
	file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	file.flush()
	if file.get_error() != OK:
		_fail("Cannot finish readability manifest")
		file.close()
		return
	file.close()
	_viewport.queue_free()
	await process_frame
	await process_frame
	print("TREE_READABILITY_OK ", records.size(), " cases")
	quit(0)


func _save_frame(filename: String, settle: bool) -> void:
	await process_frame
	for iteration in (8 if settle else 2): RenderingServer.force_draw(false, 0.0)
	var image := _viewport.get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(destination.path_join(filename)) != OK:
		_fail("Capture failed: " + filename)


static func _disable_aircraft_shadows(aircraft_root: Node3D) -> int:
	var count := 0
	for node: Node in aircraft_root.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		if geometry != null:
			geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			count += 1
	return count


static func _imported_tree_batches(scene: Node) -> Array[MultiMeshInstance3D]:
	var catalog_path := "res://assets/landscape/vegetation/catalog.json"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(catalog_path))
	if not parsed is Dictionary:
		return []
	var tree_ids: Dictionary = {}
	for asset_value: Variant in parsed.get("assets", []):
		if asset_value is Dictionary and str(asset_value.get("role", "")) == "tree":
			tree_ids[str(asset_value.get("id", ""))] = true
	var batch_root: Node = scene.find_child("ImportedVegetationBatches", true, false)
	if batch_root == null:
		return []
	var result: Array[MultiMeshInstance3D] = []
	for node: Node in batch_root.find_children("*", "MultiMeshInstance3D", true, false):
		for asset_id: String in tree_ids:
			if node.name.begins_with(asset_id + "_Part_"):
				result.append(node as MultiMeshInstance3D)
				break
	return result

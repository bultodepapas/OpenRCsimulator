## Bounded moving-view probe for the imported grass boundary on the production field.
## Run against a native Compatibility renderer; this fixture is diagnostic, not a pop gate.
extends SceneTree

const Atmosphere := preload("res://render/atmosphere.gd")
const FieldBuilder := preload("res://render/field.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Frames := preload("res://render/frames.gd")
const Scenery := preload("res://scenery/scenery.gd")
const ShaderClock := preload("res://render/shader_clock.gd")
const Vegetation := preload("res://scenery/imported_vegetation.gd")

const FORMAT := "openrc-grass-transition-capture v1"
const WIDTH := 1280
const HEIGHT := 720
const MSAA := Viewport.MSAA_4X
const SEED := 20261018
const CALM_WIND := Vector3.ZERO
const WIND_RENDER_MPS := Vector3(5.0, 0.0, 0.0)
const WIND_SWEEP_S := 3.0
const SETTLE_FRAMES := 3
const PILOT_HEIGHT_M := 1.7
const LOW_RC_HEIGHT_M := 0.55
const PILOT_LOOKAHEAD_M := 10.0
const LOW_RC_LOOKAHEAD_M := 4.0
const PILOT_FOV_DEG := 58.0
const LOW_RC_FOV_DEG := 68.0
const RADII_M: Array[float] = [
	22.0, 24.0, 26.0, 28.0, 29.0, 29.5, 29.75, 30.25, 30.5, 31.0, 32.0, 34.0, 36.0, 38.0,
]
const REQUIRED_SOURCE_FILES: Array[String] = [
	"res://render/frames.gd",
	"res://render/field.gd",
	"res://render/ground.gd",
	"res://render/ground.gdshader",
	"res://render/grass_quality.gd",
	"res://render/grass_surface.gdshaderinc",
	"res://render/near_grass.gd",
	"res://scenery/scenery.gd",
	"res://scenery/scenery_loader.gd",
	"res://scenery/imported_near_grass.gd",
	"res://scenery/imported_grass_material.gd",
	"res://scenery/imported_grass.gdshader",
	"res://scenery/imported_vegetation.gd",
	"res://data/fields/default.json",
	"res://data/fields/grass.json",
	"res://data/scenery/default.json",
	"res://assets/landscape/vegetation/catalog.json",
]
const GRASS_ASSET_IDS: Array[String] = [
	"grass_common_short",
	"grass_common_tall",
	"grass_wispy_tall",
]

var _args: Dictionary = {}
var _out_dir := ""
var _quality := "high"
var _material_profile := "default"
var _scenery_file_path := ""
var _finished := false
var _field: Dictionary = {}
var _lighting: Dictionary = {}
var _world: Node3D
var _field_node: Node3D
var _grass_node: Node3D
var _viewport: SubViewport
var _camera: Camera3D
var _captures: Array[Dictionary] = []
var _pose_records: Array[Dictionary] = []
var _source_identity: Dictionary = {}
var _scene_identity: Dictionary = {}


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
		_args[parts[0]] = parts[1] if parts.size() > 1 else "on"
	_run.call_deferred()


func _run() -> void:
	_quality = str(_args.get("quality", "high")).to_lower()
	_material_profile = str(_args.get("material", "default")).to_lower()
	var validate_only := _flag_enabled("validate-only")
	if _quality not in ["low", "balanced", "high"]:
		_fail("--quality must be low, balanced or high")
		return
	if _material_profile not in ["default", "enhanced"]:
		_fail("--material must be default or enhanced")
		return
	var loaded := FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	if not bool(loaded.get("ok", false)):
		_fail("default production field failed validation: " + str(loaded.get("errors", [])))
		return
	_field = loaded.get("field", {})
	if str(_field.get("id", "")) != "default":
		_fail("transition capture did not load the default production field")
		return
	_pose_records = _make_pose_plan()
	if _pose_records.size() != 92:
		_fail("internal pose plan is incomplete")
		return
	if validate_only:
		print("GRASS TRANSITION PLAN VALID ", _quality, " ", _material_profile,
			" poses=", _pose_records.size(), " image_pairs=", _pose_records.size())
		quit(0)
		return
	if DisplayServer.get_name().to_lower() == "headless":
		_fail("capture evidence requires a native display and Compatibility renderer")
		return
	if not _prepare_output():
		return
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		_fail("project must use the Compatibility renderer")
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.render_loop_enabled = false
	root.size = Vector2i(WIDTH, HEIGHT)
	_viewport = SubViewport.new()
	_viewport.name = "GrassTransitionViewport"
	_viewport.size = Vector2i(WIDTH, HEIGHT)
	_viewport.msaa_3d = MSAA
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	if _viewport.size != Vector2i(WIDTH, HEIGHT) or _viewport.msaa_3d != MSAA:
		_fail("could not establish the required 1280x720 MSAA4 viewport")
		return

	OS.set_environment("OPENRC_SCENERY", "on")
	OS.set_environment("OPENRC_SCENERY_QUALITY", _quality)
	OS.set_environment("OPENRC_SCENERY_AUDIO", "off")
	OS.set_environment("OPENRC_SCENERY_BIRDS", "off")
	OS.set_environment("OPENRC_SCENERY_THEME", "")
	OS.set_environment("OPENRC_SCENERY_FILE", "")
	OS.set_environment("OPENRC_TREE_WIND", "off")
	OS.set_environment("OPENRC_TREE_CELL_SIZE_M", "0")
	OS.set_environment("OPENRC_GRASS_QUALITY", "enhanced" if _material_profile == "enhanced" else "")
	seed(SEED)
	ShaderClock.register()
	ShaderClock.update(0.0, CALM_WIND)
	var scenery_options: Dictionary = Scenery.options()
	if str(scenery_options.get("quality", "")) != _quality:
		_fail("production Scenery.options() did not retain requested quality " + _quality)
		return
	if not bool(scenery_options.get("enabled", false)):
		_fail("production scenery could not be enabled")
		return
	if (
		str(scenery_options.get("theme", "")) != ""
		or bool(scenery_options.get("tree_wind", true))
		or float(scenery_options.get("tree_cell_size_m", -1.0)) != 0.0
		or bool(scenery_options.get("audio", true))
		or bool(scenery_options.get("birds", true))
		or bool(scenery_options.get("file_explicit", true))
	):
		_fail("production Scenery.options() did not retain the pinned no-wind default scene controls")
		return
	_scenery_file_path = str(scenery_options.get("file", ""))
	if _scenery_file_path != "res://data/scenery/default.json":
		_fail("transition capture requires the bundled default scenery definition")
		return
	_world = Node3D.new()
	_world.name = "GrassTransitionWorld"
	_viewport.add_child(_world)
	var environment_node := WorldEnvironment.new()
	environment_node.environment = Atmosphere.environment(_lighting)
	_world.add_child(environment_node)
	_field_node = FieldBuilder.build(_field, _lighting)
	# Keep the production placement and scene fixed; ShaderClock is the only animation input.
	_field_node.process_mode = Node.PROCESS_MODE_DISABLED
	_world.add_child(_field_node)
	Atmosphere.create_sun(_world, _lighting)
	Atmosphere.update_clouds(environment_node.environment, 0.0)
	_grass_node = _field_node.get_node_or_null("NearGrass") as Node3D
	if _grass_node == null or not bool(_grass_node.get_meta("imported", false)):
		_fail("production Field/NearGrass imported clump node is missing")
		return
	if str(_grass_node.get_meta("quality", "")) != _quality:
		_fail("production imported grass did not retain requested quality tier")
		return
	if int(_grass_node.get_meta("clumps", 0)) <= 0:
		_fail("production imported grass contains no placements")
		return
	_camera = Camera3D.new()
	_camera.name = "GrassTransitionCamera"
	_camera.near = 0.1
	_camera.far = 21000.0
	_world.add_child(_camera)
	_camera.current = true
	_source_identity = _source_hashes()
	if _finished:
		return
	_scene_identity = _grass_scene_identity()
	if _finished:
		return
	if _source_identity.is_empty() or _scene_identity.is_empty():
		_fail("source or grass-scene identity could not be established")
		return

	await _render_frame()
	await _render_frame()
	for _frame: int in 12:
		ShaderClock.update(0.0, CALM_WIND)
		await _render_frame()
	RenderingServer.viewport_set_measure_render_time(_viewport.get_viewport_rid(), true)
	for pose: Dictionary in _pose_records:
		if not await _capture_pose_pair(pose):
			return
	if not _write_manifest():
		return
	print("GRASS TRANSITION CAPTURE ", _quality, " ", _material_profile, " -> ", _out_dir)
	_finish(0)


func _make_pose_plan() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for height_case: Dictionary in _height_cases():
		for sequence: Dictionary in [
			{"id": "calm_outbound", "wind": CALM_WIND, "clocked": false, "direction": "outbound"},
			{"id": "wind_outbound", "wind": WIND_RENDER_MPS, "clocked": true, "direction": "outbound"},
			{"id": "calm_return", "wind": CALM_WIND, "clocked": false, "direction": "return"},
		]:
			var radii: Array[float] = RADII_M.duplicate()
			if str(sequence.direction) == "return":
				radii.reverse()
			for index: int in range(radii.size()):
				var fraction := float(index) / float(radii.size() - 1)
				var clock_s := fraction * WIND_SWEEP_S if bool(sequence.clocked) else 0.0
				result.append(_make_pose(
					str(sequence.id),
					str(sequence.direction),
					str(sequence.direction),
					str(height_case.id),
					float(height_case.height_m),
					float(height_case.lookahead_m),
					float(height_case.fov_deg),
					radii[index],
					index,
					radii.size(),
					clock_s,
					sequence.wind,
					false,
				))
		for cut: Dictionary in [
			{"id": "camera_cut_outbound", "direction": "outbound"},
			{"id": "camera_cut_return", "direction": "return"},
		]:
			var cut_radii: Array[float] = [29.75, 30.25]
			if str(cut.direction) == "return":
				cut_radii.reverse()
			for cut_index: int in range(cut_radii.size()):
				result.append(_make_pose(
					str(cut.id),
					str(cut.direction),
					str(cut.direction),
					str(height_case.id),
					float(height_case.height_m),
					float(height_case.lookahead_m),
					float(height_case.fov_deg),
					cut_radii[cut_index],
					cut_index,
					cut_radii.size(),
					1.0,
					WIND_RENDER_MPS,
					true,
				))
	return result


func _height_cases() -> Array[Dictionary]:
	return [
		{"id": "low_rc", "height_m": LOW_RC_HEIGHT_M, "lookahead_m": LOW_RC_LOOKAHEAD_M, "fov_deg": LOW_RC_FOV_DEG},
		{"id": "pilot", "height_m": PILOT_HEIGHT_M, "lookahead_m": PILOT_LOOKAHEAD_M, "fov_deg": PILOT_FOV_DEG},
	]


func _make_pose(sequence_id: String, direction: String, facing: String, height_id: String,
		height_m: float, lookahead_m: float, fov_deg: float, radius_m: float, index: int,
		count: int, clock_s: float, wind: Vector3, camera_cut: bool) -> Dictionary:
	var pilot: Dictionary = _field.get("pilot", {})
	var pilot_north := float(pilot.get("north", 0.0))
	var pilot_east := float(pilot.get("east", 0.0))
	var camera_north := pilot_north + radius_m
	var look_sign := 1.0 if facing == "outbound" else -1.0
	var eye := Frames.ned_to_render([camera_north, pilot_east, -height_m])
	var target := Frames.ned_to_render([camera_north + look_sign * lookahead_m, pilot_east, 0.0])
	var sequence_index := index
	var sample_index := index
	var pose_id := "%s_%s_%s_%s_%s_%02d" % [
		height_id, sequence_id, direction, _radius_label(radius_m), "cut" if camera_cut else "sweep", sample_index,
	]
	return {
		"pose_id": pose_id,
		"sequence_id": sequence_id,
		"sequence_kind": "camera_cut" if camera_cut else "moving_sweep",
		"sequence_direction": direction,
		"camera_facing": facing,
		"height_case": height_id,
		"camera_radius_from_pilot_m": radius_m,
		"eye_height_m": height_m,
		"lookahead_m": lookahead_m,
		"eye_render_m": eye,
		"target_render_m": target,
		"fov_deg": fov_deg,
		"sequence_index": sequence_index,
		"sequence_length": count,
		"shader_clock_s": clock_s,
		"wind_render_mps": wind,
		"camera_cut": camera_cut,
	}


func _capture_pose_pair(pose: Dictionary) -> bool:
	_place_camera(pose)
	var clock_s := float(pose.shader_clock_s)
	var wind: Vector3 = pose.wind_render_mps
	ShaderClock.update(clock_s, wind)
	_grass_node.visible = true
	for _frame: int in SETTLE_FRAMES:
		await _render_frame()
	var visible_record := _save_capture(pose, "visible")
	if visible_record.is_empty():
		return false
	_grass_node.visible = false
	for _frame: int in SETTLE_FRAMES:
		await _render_frame()
	var hidden_record := _save_capture(pose, "grass_hidden")
	_grass_node.visible = true
	if hidden_record.is_empty():
		return false
	_captures.append(visible_record)
	_captures.append(hidden_record)
	return true


func _save_capture(pose: Dictionary, state: String) -> Dictionary:
	var image: Image = _viewport.get_texture().get_image()
	if image == null or image.is_empty() or image.get_size() != Vector2i(WIDTH, HEIGHT):
		_fail("viewport returned an empty or wrong-sized image for " + str(pose.pose_id) + " " + state)
		return {}
	var image_name := str(pose.pose_id) + "_" + state + ".png"
	var image_path := _out_dir.path_join(image_name)
	if image.save_png(image_path) != OK:
		_fail("failed to save image: " + image_path)
		return {}
	var basis := _camera.global_transform.basis
	var record := _stable_value(pose) as Dictionary
	record["state"] = state
	record["grass_visible"] = state == "visible"
	record["grass_hidden_reference"] = state == "grass_hidden"
	record["image"] = image_name
	record["image_sha256"] = FileAccess.get_sha256(image_path)
	record["camera_right_render"] = _vector3(basis.x.normalized())
	record["camera_up_render"] = _vector3(basis.y.normalized())
	record["camera_forward_render"] = _vector3(-basis.z.normalized())
	record["draw_calls"] = _draw_calls()
	record["primitives"] = _primitives()
	record["grass_node_visible"] = _grass_node.visible
	record["ground_detail_enabled"] = true
	return record


func _place_camera(pose: Dictionary) -> void:
	_camera.set_perspective(float(pose.fov_deg), _camera.near, _camera.far)
	_camera.position = pose.eye_render_m
	_camera.look_at(pose.target_render_m, Vector3.UP)


func _grass_scene_identity() -> Dictionary:
	var placements: Variant = _grass_node.get_meta("placements", [])
	var batches: Array[Dictionary] = []
	var mesh_context := HashingContext.new()
	if mesh_context.start(HashingContext.HASH_SHA256) != OK:
		_fail("could not start imported-grass mesh hash")
		return {}
	var source_paths: Dictionary = {}
	for child: Node in _grass_node.get_children():
		if not child is MultiMeshInstance3D:
			_fail("imported grass contains an unexpected non-MultiMesh child: " + str(child.name))
			return {}
		var instance := child as MultiMeshInstance3D
		var multimesh := instance.multimesh
		var mesh: Mesh = multimesh.mesh if multimesh != null else null
		if multimesh == null or mesh == null:
			_fail("imported grass batch has no MultiMesh or Mesh: " + str(child.name))
			return {}
		var mesh_resource_path := mesh.resource_path
		if not mesh_resource_path.is_empty():
			source_paths[mesh_resource_path] = _resource_sha256(mesh_resource_path)
		for surface_index: int in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface_index)
			if mesh_context.update(var_to_bytes(arrays)) != OK:
				_fail("could not hash imported-grass mesh arrays")
				return {}
			var material := mesh.surface_get_material(surface_index)
			if material is StandardMaterial3D:
				var texture := (material as StandardMaterial3D).albedo_texture
				if texture != null and not texture.resource_path.is_empty():
					source_paths[texture.resource_path] = _resource_sha256(texture.resource_path)
		batches.append({
			"node": str(child.name),
			"instance_count": multimesh.instance_count,
			"visible_instance_count": multimesh.visible_instance_count,
			"mesh_resource_path": mesh_resource_path,
			"surface_count": mesh.get_surface_count(),
			"material_types": _surface_material_types(mesh),
		})
	if batches.is_empty():
		_fail("imported grass has no source batches")
		return {}
	var asset_records: Dictionary = {}
	for asset_id: String in GRASS_ASSET_IDS:
		asset_records[asset_id] = _stable_value(Vegetation.get_asset(asset_id))
	return {
		"node_path": str(_field_node.get_path_to(_grass_node)),
		"only_hidden_node": "Field/NearGrass.visible",
		"imported": true,
		"quality": str(_grass_node.get_meta("quality", "")),
		"clumps": int(_grass_node.get_meta("clumps", 0)),
		"source_triangles": int(_grass_node.get_meta("source_triangles", 0)),
		"placement_sha256": _hash_bytes(var_to_bytes(placements)),
		"mesh_arrays_sha256": mesh_context.finish().hex_encode(),
		"batches": batches,
		"source_assets": asset_records,
		"mesh_and_texture_file_sha256": source_paths,
		"ground_control": "ground meshes, shaders and materials remain enabled while only Field/NearGrass.visible is toggled",
	}


func _surface_material_types(mesh: Mesh) -> Array[String]:
	var result: Array[String] = []
	for surface_index: int in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface_index)
		result.append(material.get_class() if material != null else "null")
	return result


func _source_hashes() -> Dictionary:
	var result: Dictionary = {}
	for resource_path: String in REQUIRED_SOURCE_FILES:
		var digest := _resource_sha256(resource_path)
		if digest.is_empty():
			_fail("required source identity is missing: " + resource_path)
			return {}
		result[resource_path] = digest
	var scenery_file_sha256 := _resource_sha256(_scenery_file_path)
	if scenery_file_sha256.is_empty():
		_fail("selected scenery source identity is missing: " + _scenery_file_path)
		return {}
	return {
		"files_sha256": result,
		"field_id": str(_field.get("id", "")),
		"field_sha256": _resource_sha256(FieldLoader.DEFAULT_PATH),
		"scenery_file_path": _scenery_file_path,
		"scenery_file_sha256": scenery_file_sha256,
		"grass_quality_variant": _material_profile,
		"quality_tier": _quality,
	}


func _write_manifest() -> bool:
	var manifest := {
		"format": FORMAT,
		"complete": true,
		"mode": "moving_boundary_diagnostic",
		"interpretation": "Grass-only temporal residuals describe rendered image motion attributable to the imported clumps after matched hidden-reference subtraction. Camera optical motion remains expected; no residual ratio is a pop threshold or owner acceptance.",
		"field": FieldLoader.DEFAULT_PATH,
		"field_id": str(_field.get("id", "")),
		"field_sha256": _source_identity.get("field_sha256", ""),
		"pilot_render_m": _vector3(Frames.ned_to_render([
			float(_field.get("pilot", {}).get("north", 0.0)),
			float(_field.get("pilot", {}).get("east", 0.0)),
			0.0,
	])),
		"quality_tier": _quality,
		"material_profile": _material_profile,
		"engine": Engine.get_version_info(),
		"renderer_method": RenderingServer.get_current_rendering_method(),
		"renderer_driver": RenderingServer.get_current_rendering_driver_name(),
		"renderer_adapter": RenderingServer.get_video_adapter_name(),
		"viewport": {"width": WIDTH, "height": HEIGHT, "msaa_3d": MSAA, "msaa_label": "MSAA_4X"},
		"weather_policy": "production field environment; clouds frozen at time zero; no simulation weather",
		"scenery_options": {
			"quality": _quality,
			"theme": str(Scenery.options().get("theme", "")),
			"file": _scenery_file_path,
			"file_sha256": _source_identity.get("scenery_file_sha256", ""),
			"file_explicit": bool(Scenery.options().get("file_explicit", true)),
			"tree_wind": false,
			"tree_cell_size_m": 0.0,
			"audio": false,
			"birds": false,
		},
		"clock_policy": "ShaderClock set explicitly for every pose; calm sequences use zero wind at fixed t=0; windy sweeps use render-space +X 5 m/s and a monotone 0–3 s clock; cuts use matched t=1 s",
		"near_detail_control": "each grass-hidden reference toggles only Field/NearGrass.visible; production ground detail and all other scene nodes stay enabled",
		"camera_path": {
			"axis": "north from the pilot station",
			"pilot_height_m": PILOT_HEIGHT_M,
			"low_rc_height_m": LOW_RC_HEIGHT_M,
			"radii_m": RADII_M,
			"near_boundary_step_m": 0.5,
			"refinement_control_steps_m": [0.25, 0.25],
			"outbound_camera_faces": "outward while the 30 m boundary is ahead, then beyond the edge",
			"return_camera_faces": "inward so the 30 m boundary stays ahead as the camera returns across it",
			"cut_protocol": "29.75 m and 30.25 m views use the same clock and wind for each direction",
		},
		"scene_identity": _scene_identity,
		"source_identity": _source_identity,
		"captures": _captures,
		"limits": [
			"This moving-view residual is diagnostic. Expected camera motion and changing perspective remain in the images.",
			"The step-refinement ratio compares a 0.5 m boundary step with adjacent 0.25 m controls; it is not a pass/fail threshold.",
			"The existing static 3 percent channel-change and FLIP p99 0.1 seam limits remain owned by check_grass_seam.py and are unchanged.",
			"Ground-ray radial bins approximate the projected roots; blade tips can project beyond their root radius.",
		],
		"harness_sha256": _harness_sha256(),
	}
	var path := _out_dir.path_join("transition-manifest.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("cannot write capture manifest: " + path)
		return false
	file.store_string(JSON.stringify(_stable_value(manifest), "  ", true, true) + "\n")
	file.close()
	return true


func _prepare_output() -> bool:
	var requested := str(_args.get("out", "")).strip_edges()
	if requested.is_empty():
		_fail("--out is required")
		return false
	_out_dir = ProjectSettings.globalize_path(requested)
	if DirAccess.make_dir_recursive_absolute(_out_dir) != OK:
		_fail("cannot create output directory: " + _out_dir)
		return false
	var directory := DirAccess.open(_out_dir)
	if directory == null or not directory.get_files().is_empty() or not directory.get_directories().is_empty():
		_fail("output directory must be empty; evidence is never overwritten: " + _out_dir)
		return false
	return true


func _resource_sha256(resource_path: String) -> String:
	if resource_path.is_empty() or not resource_path.begins_with("res://"):
		return ""
	var absolute_path := ProjectSettings.globalize_path(resource_path)
	if not FileAccess.file_exists(absolute_path):
		return ""
	return FileAccess.get_sha256(absolute_path)


func _hash_bytes(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK or context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode()


func _harness_sha256() -> String:
	for argument: String in OS.get_cmdline_args():
		if argument.ends_with("transition_capture.gd") and FileAccess.file_exists(argument):
			return FileAccess.get_sha256(argument)
	return ""


func _draw_calls() -> int:
	return int(RenderingServer.viewport_get_render_info(
		_viewport.get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
		RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME,
	))


func _primitives() -> int:
	return int(RenderingServer.viewport_get_render_info(
		_viewport.get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
		RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME,
	))


func _render_frame() -> void:
	await process_frame
	RenderingServer.force_draw(false)


func _vector3(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _radius_label(radius_m: float) -> String:
	return ("%.2f" % radius_m).replace(".", "p")


func _stable_value(value: Variant) -> Variant:
	if value is Vector2:
		return [value.x, value.y]
	if value is Vector3:
		return _vector3(value)
	if value is Color:
		return [value.r, value.g, value.b, value.a]
	if value is Transform3D:
		var xform := value as Transform3D
		return {"basis": _stable_value(xform.basis), "origin": _stable_value(xform.origin)}
	if value is Basis:
		var basis := value as Basis
		return [_stable_value(basis.x), _stable_value(basis.y), _stable_value(basis.z)]
	if value is Dictionary:
		var result: Dictionary = {}
		var keys: Array = value.keys()
		keys.sort()
		for key: Variant in keys:
			result[str(key)] = _stable_value(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_stable_value(item))
		return result
	if value is PackedStringArray:
		return Array(value)
	if value is PackedFloat32Array or value is PackedFloat64Array or value is PackedInt32Array or value is PackedInt64Array:
		return Array(value)
	if value is Resource:
		var resource := value as Resource
		return {"class": resource.get_class(), "resource_path": resource.resource_path}
	return value


func _flag_enabled(name: String) -> bool:
	return str(_args.get(name, "off")).to_lower() in ["1", "true", "yes", "on"]


func _fail(message: String) -> void:
	if _finished:
		return
	_finished = true
	push_error("Grass transition capture: " + message)
	quit(1)


func _finish(exit_code: int) -> void:
	if _finished:
		return
	_finished = true
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
	if _viewport != null and is_instance_valid(_viewport):
		_viewport.queue_free()
	quit(exit_code)

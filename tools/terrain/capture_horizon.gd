## L7 render evidence for the visual horizon. Captures the same field, camera and vegetation before and after swapping
## the rough ArrayMesh for the original 64 × 64 PlaneMesh. The dedicated rim views hide every other field visual.
extends SceneTree

const Atmosphere := preload("res://render/atmosphere.gd")
const FieldBuilder := preload("res://render/field.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Frames := preload("res://render/frames.gd")
const Horizon := preload("res://render/horizon.gd")
const ShaderClock := preload("res://render/shader_clock.gd")

const PRESET_VISIBILITY_M: Dictionary = {"default": 23000.0, "hazy": 12000.0, "clear": 40000.0}
const AZIMUTHS: Array[int] = [0, 90, 180, 270]
const ALTITUDES_M: Array[float] = [1.7, 30.0, 140.0]
const RIM_AZIMUTHS: Array[int] = [90, 270]
const FIELD_SIZE_M: float = 40000.0
const SUBDIVISIONS: int = 63
const CAPTURE_TIME_S: float = 1.5
const OUTPUT_FORMAT: String = "openrc-horizon-capture v1"

var _args: Dictionary = {}
var _out_dir: String = ""
var _cases: Array[Dictionary] = []


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
		_args[parts[0]] = parts[1] if parts.size() > 1 else "on"
	_run.call_deferred()


func _run() -> void:
	_out_dir = str(_args.get("out", ""))
	if _out_dir.is_empty():
		_fail("--out is required")
		return
	_out_dir = ProjectSettings.globalize_path(_out_dir)
	if DirAccess.make_dir_recursive_absolute(_out_dir) != OK:
		_fail("cannot create output directory: " + _out_dir)
		return
	var preset: String = str(_args.get("visibility", "default"))
	if not PRESET_VISIBILITY_M.has(preset):
		_fail("unknown visibility preset: " + preset)
		return
	var expected_visibility: float = float(PRESET_VISIBILITY_M[preset])
	if absf(Atmosphere.visibility_m - expected_visibility) > 0.001:
		_fail("Atmosphere.visibility_m=%s for --visibility=%s; expected %s" % [Atmosphere.visibility_m, preset, expected_visibility])
		return

	# This evidence is about the horizon and atmosphere; scenery remains off even if the caller's environment enables it.
	OS.set_environment("OPENRC_SCENERY", "off")
	ShaderClock.register()
	ShaderClock.update(CAPTURE_TIME_S)
	var loaded: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	if not bool(loaded.get("ok", false)):
		_fail("default field failed validation: " + str(loaded.get("errors", [])))
		return
	var field: Dictionary = loaded.get("field", {})
	var world_data: Dictionary = _build_world(field)
	if world_data.is_empty():
		return
	var world: Node3D = world_data["world"]
	var field_node: Node3D = world_data["field"]
	var rough: MeshInstance3D = world_data["rough"]
	var camera: Camera3D = world_data["camera"]
	var horizon_mesh: Mesh = rough.mesh
	if not (horizon_mesh is ArrayMesh):
		_fail("the production rough mesh is not an ArrayMesh")
		return
	var tree_counts: Dictionary = _tree_counts(field_node)
	if tree_counts.is_empty():
		return
	if int(tree_counts.near) != 480 or int(tree_counts.far) != 1200 or int(tree_counts.total) != 1680:
		_fail("expected 480 near + 1200 far tree instances; got %s" % [tree_counts])
		return
	var profile: Dictionary = Horizon.profile()
	if profile.is_empty():
		_fail("the committed horizon profile failed validation")
		return

	if preset == "default":
		for altitude: float in ALTITUDES_M:
			for azimuth: int in AZIMUTHS:
				var case_id: String = "l7-az%03d-%s" % [azimuth, _height_tag(altitude)]
				var captured: Dictionary = await _capture(camera, field, case_id, preset, azimuth, altitude,
					"polar-hills", "near+far", tree_counts, "field")
				_cases.append(captured)

		# Terrain-only A/B: keep the near tree population fixed at 480 while comparing hills and the flat plane.
		_set_tree_population(field_node, "near")
		for altitude: float in ALTITUDES_M:
			for azimuth: int in AZIMUTHS:
				var case_id: String = "terrain-az%03d-%s" % [azimuth, _height_tag(altitude)]
				var captured: Dictionary = await _capture(camera, field, case_id, preset, azimuth, altitude,
					"polar-hills", "near-only", tree_counts, "field")
				_cases.append(captured)

		# Combined L7 baseline: replace only the rough horizon mesh and trim far trees, retaining near trees, materials,
		# camera and field build. The paired L7 image above therefore compares hills + 1,680 trees with plane + 480.
		var flat_mesh: PlaneMesh = _flat_plane()
		rough.mesh = flat_mesh
		for altitude: float in ALTITUDES_M:
			for azimuth: int in AZIMUTHS:
				var case_id: String = "baseline-az%03d-%s" % [azimuth, _height_tag(altitude)]
				var captured: Dictionary = await _capture(camera, field, case_id, preset, azimuth, altitude,
					"flat-plane", "near-only", tree_counts, "field")
				_cases.append(captured)
	else:
		# The hazy and clear settings only need the controlled flat-corridor rim cases.
		rough.mesh = _flat_plane()

	# Keep just the rough plane, sky and sun. Trees, runway and mown patches must not make natural silhouettes in the
	# fog/sky equality measurement. East/west are the generator's exact-zero hill corridors.
	_hide_other_field_visuals(field_node, rough)
	for azimuth: int in RIM_AZIMUTHS:
		var case_id: String = "rim-%s-az%03d-h140" % [preset, azimuth]
		var captured: Dictionary = await _capture(camera, field, case_id, preset, azimuth, 140.0,
			"flat-plane", "hidden", tree_counts, "rough-only")
		captured["corridor_center_deg"] = azimuth
		captured["corridor_half_width_deg"] = 20.0
		_cases.append(captured)

	var manifest: Dictionary = {
		"format": OUTPUT_FORMAT,
		"visibility_preset": preset,
		"visibility_m": expected_visibility,
		"capture_time_s": CAPTURE_TIME_S,
		"viewport": {"width": root.get_viewport().size.x, "height": root.get_viewport().size.y},
		"renderer": RenderingServer.get_video_adapter_name(),
		"field": FieldLoader.DEFAULT_PATH,
		"horizon_profile_sha256": str(profile.get("sha256", "")),
		"rough_surface_id": rough.name,
		"cases": _cases,
	}
	var manifest_path: String = _out_dir.path_join("capture-manifest-%s.json" % preset)
	var file: FileAccess = FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		_fail("cannot write capture manifest: " + manifest_path)
		return
	file.store_string(JSON.stringify(manifest, "  ", true) + "\n")
	file.close()
	print("L7 HORIZON CAPTURE ", preset, " ", _cases.size(), " cases -> ", _out_dir)
	world.queue_free()
	quit(0)


func _build_world(field: Dictionary) -> Dictionary:
	var world: Node3D = Node3D.new()
	world.name = "HorizonCaptureWorld"
	root.add_child(world)
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	environment_node.environment = Atmosphere.environment()
	world.add_child(environment_node)
	var field_node: Node3D = FieldBuilder.build(field)
	world.add_child(field_node)
	Atmosphere.create_sun(world)
	var rough: MeshInstance3D = field_node.get_node_or_null("rough") as MeshInstance3D
	if rough == null:
		_fail("the default field has no MeshInstance3D named rough")
		return {}
	var camera: Camera3D = Camera3D.new()
	camera.name = "HorizonCaptureCamera"
	camera.fov = 50.0
	camera.near = 0.1
	camera.far = 21000.0
	world.add_child(camera)
	camera.current = true
	return {"world": world, "field": field_node, "rough": rough, "camera": camera}


func _flat_plane() -> PlaneMesh:
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(FIELD_SIZE_M, FIELD_SIZE_M)
	plane.subdivide_width = SUBDIVISIONS
	plane.subdivide_depth = SUBDIVISIONS
	return plane


func _hide_other_field_visuals(field_node: Node3D, rough: MeshInstance3D) -> void:
	for child: Node in field_node.get_children():
		_hide_visual_tree(child, rough)


func _hide_visual_tree(node: Node, keep: MeshInstance3D) -> void:
	if node == keep:
		return
	if node is VisualInstance3D:
		(node as VisualInstance3D).visible = false
	if node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
		(node as MultiMeshInstance3D).multimesh.visible_instance_count = 0
	for child: Node in node.get_children():
		_hide_visual_tree(child, keep)


func _tree_counts(field_node: Node3D) -> Dictionary:
	var near_count: int = 0
	var far_count: int = 0
	var total_count: int = 0
	var found: int = 0
	var nodes: Array[Node] = field_node.find_children("*", "MultiMeshInstance3D", true, false)
	for child: Node in nodes:
		var instance: MultiMeshInstance3D = child as MultiMeshInstance3D
		if instance.multimesh == null or not instance.has_meta("near_instance_count") or not instance.has_meta("far_instance_count"):
			continue
		var near: int = int(instance.get_meta("near_instance_count"))
		var far: int = int(instance.get_meta("far_instance_count"))
		if near < 0 or far < 0 or near + far != instance.multimesh.instance_count:
			_fail("tree sector metadata disagrees with its MultiMesh: " + str(instance.get_path()))
			return {}
		near_count += near
		far_count += far
		total_count += instance.multimesh.instance_count
		found += 1
	if found == 0:
		_fail("no tree MultiMesh with near/far metadata was found")
		return {}
	return {"near": near_count, "far": far_count, "total": total_count, "sectors": found}


func _set_tree_population(field_node: Node3D, population: String) -> void:
	var nodes: Array[Node] = field_node.find_children("*", "MultiMeshInstance3D", true, false)
	for child: Node in nodes:
		var instance: MultiMeshInstance3D = child as MultiMeshInstance3D
		if instance.multimesh == null or not instance.has_meta("near_instance_count"):
			continue
		if population == "near":
			instance.multimesh.visible_instance_count = int(instance.get_meta("near_instance_count"))
		else:
			instance.multimesh.visible_instance_count = -1


func _capture(camera: Camera3D, field: Dictionary, case_id: String, preset: String, azimuth: int,
		altitude: float, terrain_mode: String, tree_population: String, tree_counts: Dictionary,
		visual_scope: String) -> Dictionary:
	var pilot: Dictionary = field.get("pilot", {})
	var position: Vector3 = Frames.ned_to_render([
		float(pilot.get("north", 0.0)), float(pilot.get("east", 0.0)), float(pilot.get("down", 0.0)) - altitude,
	])
	var azimuth_rad: float = deg_to_rad(float(azimuth))
	var direction: Vector3 = Frames.ned_to_render([cos(azimuth_rad), sin(azimuth_rad), 0.0])
	camera.position = position
	camera.look_at(position + direction * 1000.0, Vector3.UP)
	for _frame: int in 3:
		await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var image_name: String = "capture-%s.png" % case_id
	var image_path: String = _out_dir.path_join(image_name)
	var save_error: Error = image.save_png(image_path)
	if save_error != OK:
		_fail("failed to save %s: error %d" % [image_path, save_error])
		return {}
	return {
		"id": case_id,
		"image": image_name,
		"visibility_preset": preset,
		"visibility_m": float(PRESET_VISIBILITY_M[preset]),
		"azimuth_deg": azimuth,
		"elevation_deg": 0.0,
		"camera_height_m": altitude,
		"camera_fov_deg": camera.fov,
		"terrain_mode": terrain_mode,
		"tree_population": tree_population,
		"near_tree_instances": int(tree_counts.near),
		"far_tree_instances": int(tree_counts.far),
		"visible_tree_instances": 0 if tree_population == "hidden" else int(tree_counts.total) if tree_population == "near+far" else int(tree_counts.near),
		"visual_scope": visual_scope,
		"world_id": "field-%s" % preset,
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
	}


func _height_tag(height: float) -> String:
	if is_equal_approx(height, 1.7):
		return "h1p7"
	return "h%dm" % int(round(height))


func _fail(message: String) -> void:
	printerr("L7 HORIZON CAPTURE ERROR: " + message)
	quit(1)

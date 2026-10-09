extends SceneTree

const AIRCRAFT_PATH := "res://assets/aircraft.glb"
const DEMO_PATH := "res://assets/aircraft_demo.glb"
const METADATA_PATH := "res://assets/metadata.json"
const OUTPUT_PATH := "res://probe-output/godot-report.json"
const NEUTRAL_IMAGE_PATH := "res://probe-output/neutral.png"
const ARTICULATED_IMAGE_PATH := "res://probe-output/articulated.png"
const BOUNDS_TOLERANCE_M := 0.001

var _stage: Node3D
var _report: Dictionary = {}
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_report = {
		"probe": {
			"step": "TT-00-R1",
			"godot_version": Engine.get_version_info().get("string", "unknown"),
			"renderer_method": RenderingServer.get_current_rendering_method(),
			"renderer_driver": RenderingServer.get_current_rendering_driver_name(),
		},
		"checks": {},
	}
	_stage = _make_stage()
	root.add_child(_stage)
	var probe_camera := _stage.get_node("ProbeCamera") as Camera3D
	probe_camera.look_at(Vector3(0.0, -0.005, 0.255), Vector3.UP)

	var metadata_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(METADATA_PATH))
	if typeof(metadata_value) != TYPE_DICTIONARY:
		_failures.append("Could not parse aircraft metadata.json")
		await _finish()
		call_deferred("quit", 1)
		return
	var metadata: Dictionary = metadata_value

	var aircraft_resource: Resource = load(AIRCRAFT_PATH)
	if not aircraft_resource is PackedScene:
		_failures.append("Godot did not import aircraft.glb as a PackedScene")
		await _finish()
		call_deferred("quit", 1)
		return
	var aircraft_scene: PackedScene = aircraft_resource
	var aircraft_root: Node3D = aircraft_scene.instantiate() as Node3D
	if aircraft_root == null:
		_failures.append("aircraft.glb root is not Node3D")
		await _finish()
		call_deferred("quit", 1)
		return
	aircraft_root.name = "VisibleAircraft"
	_stage.add_child(aircraft_root)

	var model_report := _inspect_aircraft(aircraft_root, metadata)
	_report["neutral_import"] = model_report
	_report["checks"]["neutral_import_loaded"] = model_report.get("loaded", false)
	_report["checks"]["root_scale_identity"] = model_report.get("root_scale_identity", false)
	_report["checks"]["metadata_axis_bounds_match"] = model_report.get("bounds_match_metadata", false)
	_report["checks"]["mesh_nodes_15"] = model_report.get("mesh_count", -1) == 15
	_report["checks"]["surfaces_36"] = model_report.get("surface_count", -1) == 36
	_report["checks"]["articulation_hierarchy_matches_metadata"] = model_report.get("articulation_hierarchy_match", false)
	_report["checks"]["moving_meshes_have_identity_local_transform"] = model_report.get("moving_meshes_identity", false)

	var independent_report := _check_independent_instances(aircraft_scene)
	_report["independent_instances"] = independent_report
	_report["checks"]["instances_have_independent_pivots"] = independent_report.get("independent_pivots", false)
	_report["checks"]["rest_times_local_x_rotation_composes"] = independent_report.get("rest_times_local_x_composes", false)
	_report["checks"]["rotating_one_instance_leaves_other_unchanged"] = independent_report.get("other_instance_unchanged", false)

	var demo_report := await _check_demo_animation(metadata)
	_report["demo_animation"] = demo_report
	_report["checks"]["demo_glb_loaded"] = demo_report.get("loaded", false)
	_report["checks"]["animation_player_available"] = demo_report.get("animation_player_found", false)
	_report["checks"]["control_demo_available"] = demo_report.get("control_demo_available", false)
	_report["checks"]["control_demo_moves_controls"] = demo_report.get("primary_control_motion", false)

	await process_frame
	await process_frame
	var neutral_error := _capture(NEUTRAL_IMAGE_PATH)
	_report["screenshots"] = {"neutral": {"path": NEUTRAL_IMAGE_PATH, "save_error": neutral_error}}
	_report["checks"]["neutral_screenshot_saved"] = neutral_error == OK

	var pose_report := _apply_articulated_pose(aircraft_root, metadata)
	_report["articulated_pose"] = pose_report
	_report["checks"]["articulated_pose_applied"] = pose_report.get("all_pivots_applied", false)
	await process_frame
	await process_frame
	var articulated_error := _capture(ARTICULATED_IMAGE_PATH)
	_report["screenshots"]["articulated"] = {"path": ARTICULATED_IMAGE_PATH, "save_error": articulated_error}
	_report["checks"]["articulated_screenshot_saved"] = articulated_error == OK

	await _finish()
	call_deferred("quit", 0 if _report["all_checks_pass"] else 1)


func _make_stage() -> Node3D:
	var stage := Node3D.new()
	stage.name = "ProbeStage"

	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.055, 0.075, 0.105)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.64, 0.69, 0.78)
	environment.ambient_light_energy = 0.75
	world_environment.environment = environment
	stage.add_child(world_environment)

	var key_light := DirectionalLight3D.new()
	key_light.name = "KeyLight"
	key_light.rotation_degrees = Vector3(-37.0, -28.0, 0.0)
	key_light.light_energy = 1.35
	key_light.shadow_enabled = true
	stage.add_child(key_light)

	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(4.0, 4.0)
	ground.mesh = ground_mesh
	ground.position = Vector3(0.0, -0.275, 0.2)
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.12, 0.16, 0.19)
	ground_material.roughness = 0.94
	ground.material_override = ground_material
	stage.add_child(ground)

	var probe_camera := Camera3D.new()
	probe_camera.name = "ProbeCamera"
	probe_camera.position = Vector3(2.15, 1.28, -2.48)
	probe_camera.fov = 38.0
	probe_camera.near = 0.05
	probe_camera.far = 100.0
	probe_camera.current = true
	stage.add_child(probe_camera)
	return stage


func _inspect_aircraft(aircraft_root: Node3D, metadata: Dictionary) -> Dictionary:
	var hierarchy: Array = []
	var mesh_instances: Array[MeshInstance3D] = []
	_walk(aircraft_root, "", hierarchy, mesh_instances)
	var datum_root_name := str(metadata["datum"]["root_node"])
	var datum_root := _find_named_node(aircraft_root, datum_root_name) as Node3D
	if datum_root == null:
		datum_root = aircraft_root
	var surface_count := 0
	for mesh_instance in mesh_instances:
		surface_count += mesh_instance.mesh.get_surface_count()

	var bounds := _measure_bounds(datum_root, mesh_instances)
	var expected_bounds: Dictionary = metadata["dimensions"]["model"]["bbox_sim_m"]
	var bounds_min: Array = bounds["min"]
	var bounds_max: Array = bounds["max"]
	var expected_min: Array = expected_bounds["min"]
	var expected_max: Array = expected_bounds["max"]
	var bounds_match := _arrays_close(bounds_min, expected_min, BOUNDS_TOLERANCE_M) and _arrays_close(bounds_max, expected_max, BOUNDS_TOLERANCE_M)

	var articulation_hierarchy_match := true
	var moving_meshes_identity := true
	var articulation_report: Dictionary = {}
	var articulations: Dictionary = metadata.get("articulations", {})
	for hinge_name_value in articulations.keys():
		var hinge_name := str(hinge_name_value)
		var description: Dictionary = articulations[hinge_name_value]
		var hinge := _find_named_node(aircraft_root, hinge_name) as Node3D
		var expected_parent_name := str(description.get("parent_node", ""))
		var parent_match := hinge != null and hinge.get_parent() != null and str(hinge.get_parent().name) == expected_parent_name
		articulation_hierarchy_match = articulation_hierarchy_match and parent_match
		var member_name := str(description.get("mesh_node", ""))
		var member := _find_named_node(aircraft_root, member_name) as MeshInstance3D if not member_name.is_empty() else null
		var member_is_direct_child := member == null or (hinge != null and member.get_parent() == hinge)
		var member_local_identity := member == null or _identity_transform(member)
		moving_meshes_identity = moving_meshes_identity and member_is_direct_child and member_local_identity
		articulation_report[hinge_name] = {
			"parent": str(hinge.get_parent().name) if hinge != null and hinge.get_parent() != null else "missing",
			"expected_parent": expected_parent_name,
			"parent_match": parent_match,
		"mesh_node": member_name,
			"mesh_direct_child": member_is_direct_child,
			"mesh_local_identity": member_local_identity,
			"rest_quaternion_xyzw": _quaternion_to_array(hinge.quaternion) if hinge != null else [],
			"metadata_keys": _metadata_keys(hinge) if hinge != null else [],
			"extras_summary": _extras_summary(hinge) if hinge != null else {},
		}

	var expected_axis_landmarks: Dictionary = metadata["landmarks"]
	var left_wingtip: Array = expected_axis_landmarks["left_wingtip"]["sim_m"]
	var right_wingtip: Array = expected_axis_landmarks["right_wingtip"]["sim_m"]
	var nose: Array = expected_axis_landmarks["nose_spinner_tip"]["sim_m"]
	var tail: Array = expected_axis_landmarks["tail_rudder_trailing_edge"]["sim_m"]
	var axis_order_matches := float(left_wingtip[0]) < 0.0 and float(right_wingtip[0]) > 0.0 and float(nose[2]) < float(tail[2])
	var scene_scale_identity := _arrays_close(_vector_to_array(aircraft_root.scale), [1.0, 1.0, 1.0], 0.000001)
	var datum_scale_identity := _arrays_close(_vector_to_array(datum_root.scale), [1.0, 1.0, 1.0], 0.000001)

	return {
		"loaded": true,
		"source": AIRCRAFT_PATH,
		"packed_scene_root": {
			"name": str(aircraft_root.name),
			"scale": _vector_to_array(aircraft_root.scale),
			"rotation_xyzw": _quaternion_to_array(aircraft_root.quaternion),
			"origin_m": _vector_to_array(aircraft_root.position),
			"scale_identity": scene_scale_identity,
		},
		"datum_root": {
			"name": str(datum_root.name),
			"scale": _vector_to_array(datum_root.scale),
			"rotation_xyzw": _quaternion_to_array(datum_root.quaternion),
			"origin_m": _vector_to_array(datum_root.position),
			"scale_identity": datum_scale_identity,
			"metadata_keys": _metadata_keys(datum_root),
		},
		"root_name": str(datum_root.name),
		"root_scale": _vector_to_array(datum_root.scale),
		"root_rotation_xyzw": _quaternion_to_array(datum_root.quaternion),
		"root_origin_m": _vector_to_array(datum_root.position),
		"root_scale_identity": scene_scale_identity and datum_scale_identity,
		"mesh_count": mesh_instances.size(),
		"surface_count": surface_count,
		"bounds_m": bounds,
		"expected_bounds_m": expected_bounds,
		"bounds_tolerance_m": BOUNDS_TOLERANCE_M,
		"bounds_match_metadata": bounds_match,
		"axes": {
			"right": "+X",
			"up": "+Y",
			"nose": "-Z",
			"axis_order_matches_metadata_landmarks": axis_order_matches,
		},
		"articulation_hierarchy_match": articulation_hierarchy_match,
		"moving_meshes_identity": moving_meshes_identity,
		"articulations": articulation_report,
		"hierarchy": hierarchy,
	}


func _check_independent_instances(aircraft_scene: PackedScene) -> Dictionary:
	var first_root := aircraft_scene.instantiate() as Node3D
	var second_root := aircraft_scene.instantiate() as Node3D
	if first_root == null or second_root == null:
		_failures.append("Could not instantiate two independent neutral scenes")
		return {"independent_pivots": false, "rest_times_local_x_composes": false, "other_instance_unchanged": false}
	var first_hinge := _find_named_node(first_root, "aileron_left_hinge") as Node3D
	var second_hinge := _find_named_node(second_root, "aileron_left_hinge") as Node3D
	if first_hinge == null or second_hinge == null:
		_failures.append("Aileron hinge missing from independent-instance probe")
		return {"independent_pivots": false, "rest_times_local_x_composes": false, "other_instance_unchanged": false}
	var rest_rotation := first_hinge.quaternion
	var second_before := second_hinge.quaternion
	var test_angle := deg_to_rad(17.0)
	var local_x_rotation := Quaternion(Vector3.RIGHT, test_angle)
	first_hinge.quaternion = rest_rotation * local_x_rotation
	var actual_delta := rest_rotation.inverse() * first_hinge.quaternion
	var independent_pivots := first_root != second_root and first_hinge != second_hinge
	var composition_residual := _quaternion_component_residual(actual_delta, local_x_rotation)
	var other_instance_residual := _quaternion_component_residual(second_hinge.quaternion, second_before)
	var composition_exact := composition_residual < 0.00001
	var other_unchanged := other_instance_residual < 0.000001
	return {
		"independent_pivots": independent_pivots,
		"rest_times_local_x_composes": composition_exact,
		"test_angle_deg": 17.0,
		"composition_residual_max_component": composition_residual,
		"other_instance_residual_max_component": other_instance_residual,
		"rest_quaternion_xyzw": _quaternion_to_array(rest_rotation),
		"applied_quaternion_xyzw": _quaternion_to_array(first_hinge.quaternion),
		"second_instance_before_xyzw": _quaternion_to_array(second_before),
		"second_instance_after_xyzw": _quaternion_to_array(second_hinge.quaternion),
		"other_instance_unchanged": other_unchanged,
	}


func _check_demo_animation(metadata: Dictionary) -> Dictionary:
	var demo_resource: Resource = load(DEMO_PATH)
	if not demo_resource is PackedScene:
		_failures.append("Godot did not import aircraft_demo.glb as a PackedScene")
		return {"loaded": false, "animation_player_found": false, "control_demo_available": false, "primary_control_motion": false}
	var demo_scene: PackedScene = demo_resource
	var demo_root := demo_scene.instantiate() as Node3D
	if demo_root == null:
		_failures.append("aircraft_demo.glb root is not Node3D")
		return {"loaded": false, "animation_player_found": false, "control_demo_available": false, "primary_control_motion": false}
	demo_root.name = "DemoAnimationProbe"
	_stage.add_child(demo_root)
	_set_visuals_visible(demo_root, false)
	var animation_player := _find_class(demo_root, "AnimationPlayer") as AnimationPlayer
	if animation_player == null:
		_failures.append("aircraft_demo.glb contains no AnimationPlayer")
		return {"loaded": true, "animation_player_found": false, "control_demo_available": false, "primary_control_motion": false}
	var names: Array[String] = []
	for animation_name in animation_player.get_animation_list():
		names.append(str(animation_name))
	if not names.has("control_demo"):
		_failures.append("Demo AnimationPlayer has no control_demo animation")
		return {"loaded": true, "animation_player_found": true, "control_demo_available": false, "animation_names": names, "primary_control_motion": false}
	var animation := animation_player.get_animation(&"control_demo")
	var duration := animation.length
	animation_player.play(&"control_demo")
	animation_player.seek(0.0, true)
	var primary_controls := ["aileron_left_hinge", "aileron_right_hinge", "elevator_hinge", "rudder_hinge"]
	var starting_rotations: Dictionary = {}
	var maximum_motion: Dictionary = {}
	for hinge_name in primary_controls:
		var hinge := _find_named_node(demo_root, hinge_name) as Node3D
		if hinge != null:
			starting_rotations[hinge_name] = hinge.quaternion
			maximum_motion[hinge_name] = 0.0
	for sample_index in range(17):
		var fraction := float(sample_index) / 16.0
		animation_player.seek(duration * fraction, true)
		for hinge_name in primary_controls:
			var hinge := _find_named_node(demo_root, hinge_name) as Node3D
			if hinge != null and starting_rotations.has(hinge_name):
				var start_rotation: Quaternion = starting_rotations[hinge_name]
				var current_max := float(maximum_motion[hinge_name])
				maximum_motion[hinge_name] = maxf(current_max, start_rotation.angle_to(hinge.quaternion))
	animation_player.stop()
	var control_motion: Dictionary = {}
	var all_primary_controls_move := true
	for hinge_name in primary_controls:
		var movement := float(maximum_motion.get(hinge_name, 0.0))
		control_motion[hinge_name] = {"max_delta_rad": movement, "max_delta_deg": rad_to_deg(movement)}
		all_primary_controls_move = all_primary_controls_move and movement > 0.01
	if not all_primary_controls_move:
		_failures.append("Demo control_demo did not move every sampled primary control")
	return {
		"loaded": true,
		"source": DEMO_PATH,
		"animation_player_found": true,
		"animation_names": names,
		"control_demo_available": true,
		"control_demo_length_s": duration,
		"sample_count": 17,
		"sampled_primary_control_motion": control_motion,
		"primary_control_motion": all_primary_controls_move,
		"expected_primary_controls": primary_controls,
		"authored_articulations": metadata.get("articulations", {}).keys().size(),
	}


func _apply_articulated_pose(aircraft_root: Node3D, metadata: Dictionary) -> Dictionary:
	var angles_deg := {
		"aileron_left_hinge": 18.0,
		"aileron_right_hinge": -18.0,
		"flap_left_hinge": 18.0,
		"flap_right_hinge": 18.0,
		"elevator_hinge": 12.0,
		"rudder_hinge": 18.0,
		"tailwheel_steer": 18.0,
		"tailwheel_axle": 35.0,
		"propeller_spin": 65.0,
		"gear_left_suspension": 8.0,
		"wheel_left_axle": 35.0,
		"gear_right_suspension": 8.0,
		"wheel_right_axle": -35.0,
	}
	var pivots: Dictionary = metadata.get("articulations", {})
	var applied: Dictionary = {}
	var all_applied := true
	for hinge_name_value in angles_deg.keys():
		var hinge_name := str(hinge_name_value)
		var hinge := _find_named_node(aircraft_root, hinge_name) as Node3D
		if hinge == null or not pivots.has(hinge_name):
			all_applied = false
			applied[hinge_name] = {"found": false}
			continue
		var angle_deg := float(angles_deg[hinge_name_value])
		var rest_rotation := hinge.quaternion
		var delta_rotation := Quaternion(Vector3.RIGHT, deg_to_rad(angle_deg))
		hinge.quaternion = rest_rotation * delta_rotation
		var measured_delta := rest_rotation.inverse() * hinge.quaternion
		var composition_residual := _quaternion_component_residual(measured_delta, delta_rotation)
		var composition_match := composition_residual < 0.00001
		all_applied = all_applied and composition_match
		applied[hinge_name] = {
			"found": true,
			"angle_deg": angle_deg,
			"formula": "rest_quaternion * Quaternion(local +X, angle_rad)",
			"rest_quaternion_xyzw": _quaternion_to_array(rest_rotation),
			"result_quaternion_xyzw": _quaternion_to_array(hinge.quaternion),
			"composition_matches": composition_match,
			"composition_residual_max_component": composition_residual,
			"range_deg": pivots[hinge_name].get("range", {}),
		}
	return {"all_pivots_applied": all_applied, "angles_and_rotations": applied}


func _measure_bounds(aircraft_root: Node3D, mesh_instances: Array[MeshInstance3D]) -> Dictionary:
	var bounds_min := Vector3(1.0e30, 1.0e30, 1.0e30)
	var bounds_max := Vector3(-1.0e30, -1.0e30, -1.0e30)
	var any_vertex := false
	for mesh_instance in mesh_instances:
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var surface_arrays: Array = mesh_instance.mesh.surface_get_arrays(surface_index)
			if surface_arrays.is_empty() or typeof(surface_arrays[Mesh.ARRAY_VERTEX]) != TYPE_PACKED_VECTOR3_ARRAY:
				continue
			var vertices: PackedVector3Array = surface_arrays[Mesh.ARRAY_VERTEX]
			for vertex_value in vertices:
				var vertex: Vector3 = vertex_value
				var model_point := aircraft_root.to_local(mesh_instance.to_global(vertex))
				bounds_min.x = minf(bounds_min.x, model_point.x)
				bounds_min.y = minf(bounds_min.y, model_point.y)
				bounds_min.z = minf(bounds_min.z, model_point.z)
				bounds_max.x = maxf(bounds_max.x, model_point.x)
				bounds_max.y = maxf(bounds_max.y, model_point.y)
				bounds_max.z = maxf(bounds_max.z, model_point.z)
				any_vertex = true
	return {"min": _vector_to_array(bounds_min), "max": _vector_to_array(bounds_max), "valid": any_vertex}


func _walk(node: Node, path: String, hierarchy: Array, mesh_instances: Array[MeshInstance3D]) -> void:
	var node_path := str(node.name) if path.is_empty() else path + "/" + str(node.name)
	hierarchy.append({"path": node_path, "name": str(node.name), "class": node.get_class()})
	if node is MeshInstance3D and node.mesh != null:
		mesh_instances.append(node as MeshInstance3D)
	for child in node.get_children():
		_walk(child, node_path, hierarchy, mesh_instances)


func _find_named_node(parent: Node, node_name: String) -> Node:
	return parent.find_child(node_name, true, false)


func _find_class(parent: Node, type_name: String) -> Node:
	if parent.get_class() == type_name:
		return parent
	for child in parent.get_children():
		var result := _find_class(child, type_name)
		if result != null:
			return result
	return null


func _metadata_keys(node: Node) -> Array[String]:
	var keys: Array[String] = []
	for meta_name in node.get_meta_list():
		keys.append(str(meta_name))
	return keys


func _extras_summary(node: Node) -> Dictionary:
	var summary: Dictionary = {}
	for meta_name in node.get_meta_list():
		var value: Variant = node.get_meta(meta_name)
		if typeof(value) == TYPE_DICTIONARY:
			var extra_keys: Array[String] = []
			for key in value.keys():
				extra_keys.append(str(key))
			summary[str(meta_name)] = {"type": "Dictionary", "keys": extra_keys}
		else:
			summary[str(meta_name)] = {"type_code": typeof(value)}
	return summary


func _quaternion_component_residual(actual: Quaternion, expected: Quaternion) -> float:
	var direct := maxf(maxf(absf(actual.x - expected.x), absf(actual.y - expected.y)), maxf(absf(actual.z - expected.z), absf(actual.w - expected.w)))
	var negated := maxf(maxf(absf(actual.x + expected.x), absf(actual.y + expected.y)), maxf(absf(actual.z + expected.z), absf(actual.w + expected.w)))
	return minf(direct, negated)


func _set_visuals_visible(node: Node, is_visible: bool) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).visible = is_visible
	for child in node.get_children():
		_set_visuals_visible(child, is_visible)


func _identity_transform(node: Node3D) -> bool:
	return node.position.length() < 0.000001 and node.quaternion.angle_to(Quaternion.IDENTITY) < 0.000001 and _arrays_close(_vector_to_array(node.scale), [1.0, 1.0, 1.0], 0.000001)


func _arrays_close(actual: Array, expected: Array, tolerance: float) -> bool:
	if actual.size() != expected.size():
		return false
	for index in range(actual.size()):
		if absf(float(actual[index]) - float(expected[index])) > tolerance:
			return false
	return true


func _vector_to_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _quaternion_to_array(value: Quaternion) -> Array:
	return [value.x, value.y, value.z, value.w]


func _capture(path: String) -> Error:
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_failures.append("Render capture was empty: " + path)
		return ERR_CANT_CREATE
	return image.save_png(path)


func _finish() -> void:
	_report["failures"] = _failures
	var checks: Dictionary = _report.get("checks", {})
	var all_checks_pass := true
	for check_value in checks.values():
		all_checks_pass = all_checks_pass and bool(check_value)
	_report["all_checks_pass"] = all_checks_pass and _failures.is_empty()
	var report_file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if report_file == null:
		push_error("Could not open probe report output: " + OUTPUT_PATH)
		call_deferred("quit", 1)
		return
	report_file.store_string(JSON.stringify(_report, "\t") + "\n")
	report_file.close()
	print("TIMBER_GODOT_PROBE " + JSON.stringify({"all_checks_pass": _report["all_checks_pass"], "checks": checks, "failures": _failures}))
	if _stage != null:
		_stage.queue_free()
		await process_frame

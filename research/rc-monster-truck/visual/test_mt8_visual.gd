# RCV-14a: verify the reviewed MT8 presentation adapter against its supplied rig.
# Run with Godot 4.7.2 using the app project. This is a visual-only test; it does
# not create a physics world or make claims about vehicle dynamics.
extends SceneTree

const Visual := preload("mt8_visual.gd")
const CORNERS := ["FL", "FR", "RL", "RR"]
const POSITION_TOLERANCE_M := 1.0e-4
const TRANSFORM_TOLERANCE := 1.0e-4

var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	print("%s %s%s" % ["PASS" if ok else "FAIL", label, " — " + detail if not detail.is_empty() else ""])
	if not ok:
		_failures += 1


func _initialize() -> void:
	await _run()


func _run() -> void:
	var baseline_children := root.get_child_count()
	var model_a: Dictionary = Visual.load_delivery()
	_check("load hash-pinned MT8 delivery", bool(model_a.get("ok", false)), str(model_a.get("error", "")))
	if not bool(model_a.get("ok", false)):
		print("MT8 visual: %d checks, %d failed" % [_checks, _failures])
		quit(1)
		return

	var root_a: Node3D = model_a["root"]
	var unloaded_snapshot := _snapshot(model_a)
	_check(
		"pose waits for SceneTree attachment",
		not Visual.apply_pose(model_a, _zero4(), 0.0, _zero4())
			and _snapshot_error(model_a, unloaded_snapshot) == 0.0,
	)
	root.add_child(root_a)
	await process_frame
	_check("delivery wrapper and model root are in SceneTree", root_a.is_inside_tree() and model_a.model_root.is_inside_tree())
	_check("neutral pose accepted after attachment", Visual.apply_pose(model_a, _zero4(), 0.0, _zero4()))
	_check_neutral_geometry(model_a)
	_check_no_physics_nodes(model_a)
	_check_default_proxies_hidden(model_a)
	_check_rest_pose(model_a)
	_check_wheel_dimensions(model_a)
	_check_independent_travel(model_a)
	_check_extreme_poses(model_a)
	_check_steer_and_spin_signs(model_a)
	_check_invalid_poses_transactional(model_a)
	await _check_instance_isolation(model_a)
	_check_rest_pose(model_a)

	var root_a_to_free: Node3D = model_a["root"]
	root_a_to_free.queue_free()
	await process_frame
	_check("main delivery instance frees cleanly", not is_instance_valid(root_a_to_free))
	_check("no test instance remains attached", root.get_child_count() == baseline_children)
	await _check_repeat_load_free(baseline_children)
	print("RCV-14a MT8 visual: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _check_neutral_geometry(model: Dictionary) -> void:
	var spec: Dictionary = model["spec"]
	var required := ["MT8_Root", "Chassis", "Body", "Collision", "Propulsion", "Bumper_F", "Bumper_R"]
	for corner in CORNERS:
		for part in ["ArmLower", "ArmUpper", "Suspension", "Spin", "WheelMesh", "DriveshaftIn", "DriveshaftOut", "ShockA_Body", "ShockA_Spring", "ShockA_Shaft", "ShockB_Body", "ShockB_Spring", "ShockB_Shaft"]:
			required.append(corner + "_" + part)
		required.append(corner + ("_Steer" if corner.begins_with("F") else "_Carrier"))
	for proxy in spec["collision_boxes"].keys():
		required.append(proxy)
	var bindings_ok := true
	for name in required:
		bindings_ok = bindings_ok and model.nodes.has(name) and model.rest.has(name)
	_check("node and rest-transform bindings cover the supplied rig", bindings_ok)

	var wheel_positions := {}
	var center_ok := true
	for corner in CORNERS:
		var actual := _model_position(model, corner + "_Spin")
		var expected := _vector3(spec["corners"][corner]["wheel_center_rest"])
		wheel_positions[corner] = actual
		center_ok = center_ok and actual.distance_to(expected) <= POSITION_TOLERANCE_M
	_check("all four wheel centers match delivered coordinates", center_ok)
	var front_z: float = 0.5 * (wheel_positions["FL"].z + wheel_positions["FR"].z)
	var rear_z: float = 0.5 * (wheel_positions["RL"].z + wheel_positions["RR"].z)
	var left_x: float = 0.5 * (wheel_positions["FL"].x + wheel_positions["RL"].x)
	var right_x: float = 0.5 * (wheel_positions["FR"].x + wheel_positions["RR"].x)
	_check("spec wheelbase is 0.420 m", absf(float(spec["wheelbase"]) - 0.420) < 1.0e-12, str(spec["wheelbase"]))
	_check("imported wheelbase is 0.420 m", absf((rear_z - front_z) - 0.420) < POSITION_TOLERANCE_M, str(rear_z - front_z))
	_check("spec track is 0.430 m", absf(float(spec["track"]) - 0.430) < 1.0e-12, str(spec["track"]))
	_check("imported track is 0.430 m", absf((right_x - left_x) - 0.430) < POSITION_TOLERANCE_M, str(right_x - left_x))
	_check("spec tire radius is 0.100 m", absf(float(spec["tire_radius"]) - 0.100) < 1.0e-12, str(spec["tire_radius"]))


func _check_wheel_dimensions(model: Dictionary) -> void:
	var spec: Dictionary = model["spec"]
	var wheel := _node(model, "FL_WheelMesh") as MeshInstance3D
	if wheel == null or wheel.mesh == null:
		_check("imported tire mesh exposes a measurable radius", false, "FL_WheelMesh or mesh missing")
		return
	var to_model: Transform3D = model.model_root.global_transform.affine_inverse() * wheel.global_transform
	var wheel_bounds: AABB = to_model * wheel.mesh.get_aabb()
	var radius_from_mesh := 0.5 * maxf(wheel_bounds.size.y, wheel_bounds.size.z)
	_check(
		"imported tire mesh radius is approximately 0.100 m",
		absf(radius_from_mesh - float(spec["tire_radius"])) < 0.002,
		"mesh radius %.6f m" % radius_from_mesh,
	)
	var body_bounds: AABB = Visual.visual_bounds(model)
	_check("visual model length stays near 0.66 m", absf(body_bounds.size.z - 0.66) < 0.01, str(body_bounds.size.z))
	_check("visual model width stays near 0.52 m", absf(body_bounds.size.x - 0.52) < 0.01, str(body_bounds.size.x))
	_check("visual tire bottom is near -0.125 m", absf(body_bounds.position.y + 0.125) < 0.003, str(body_bounds.position.y))


func _check_no_physics_nodes(model: Dictionary) -> void:
	var found := PackedStringArray()
	var pending: Array[Node] = []
	pending.append(model["root"])
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is CollisionObject3D or node is CollisionShape3D or node is Joint3D:
			found.append("%s (%s)" % [node.name, node.get_class()])
		for child in node.get_children():
			pending.append(child)
	_check("delivery contains no physics bodies, shapes, or joints", found.is_empty(), str(found))


func _check_default_proxies_hidden(model: Dictionary) -> void:
	var collision := _node(model, "Collision")
	var spec: Dictionary = model["spec"]
	var hidden := collision != null and not collision.visible
	var names: Dictionary = spec["collision_boxes"]
	for proxy in names.keys():
		var proxy_node := _node(model, str(proxy))
		hidden = hidden and proxy_node != null and not proxy_node.is_visible_in_tree()
	_check("collision proxy meshes are hidden by default", hidden)


func _check_rest_pose(model: Dictionary) -> void:
	var accepted := Visual.apply_pose(model, _zero4(), 0.0, _zero4())
	var error := _snapshot_error(model, model["rest"])
	_check("zero inputs restore every authored Node3D transform", accepted and error < TRANSFORM_TOLERANCE, "max transform error " + str(error))


func _check_independent_travel(model: Dictionary) -> void:
	Visual.apply_pose(model, _zero4(), 0.0, _zero4())
	var neutral_transforms := _snapshot(model)
	var independent := true
	for moving_index in 4:
		var travel := _zero4()
		travel[moving_index] = 0.04
		independent = independent and Visual.apply_pose(model, travel, 0.0, _zero4())
		for corner_index in 4:
			var corner: String = CORNERS[corner_index]
			var expected := _expected_wheel_center(model.spec, corner, travel[corner_index])
			var actual := _model_position(model, corner + "_Spin")
			independent = independent and actual.distance_to(expected) < POSITION_TOLERANCE_M
			for node_name: String in model.rest:
				if node_name.begins_with(corner + "_") and corner_index != moving_index:
					independent = independent and _transform_error(_node(model, node_name).transform, neutral_transforms[node_name]) == 0.0
		_check("each corner can travel without moving any other wheel assembly", independent)
	

func _check_extreme_poses(model: Dictionary) -> void:
	var cases := _extreme_cases(model.spec)
	_check("extreme set mirrors the 25 common poses plus two crossed poses", cases.size() == 27, str(cases.size()))
	var accepted := true
	var wheel_error := 0.0
	var arm_error := 0.0
	var shock_endpoint_error := 0.0
	var shock_axis_error := 0.0
	var shock_tip_inside := true
	var spring_scale_positive := true
	var declared_shock_lengths := true
	var worst_case := ""
	var worst_shock_case := ""
	var spec: Dictionary = model["spec"]
	var arm_length := float(spec["arm_length"])
	var shock_range: Dictionary = spec["shock_length"]
	var half_ball_joint_height := _half_ball_joint_height(spec)
	var root_inverse: Transform3D = model.model_root.global_transform.affine_inverse()

	for pose: Dictionary in cases:
		var travel: PackedFloat64Array = pose["travel"]
		var steer_rad := float(pose["steer"])
		if not Visual.apply_pose(model, travel, steer_rad, _zero4()):
			accepted = false
			worst_case = str(pose["label"])
			continue
		for index in 4:
			var corner: String = CORNERS[index]
			var corner_spec: Dictionary = spec["corners"][corner]
			var expected_center := _expected_wheel_center(spec, corner, travel[index])
			var actual_center := _model_position(model, corner + "_Spin")
			var center_error := actual_center.distance_to(expected_center)
			if center_error > wheel_error:
				wheel_error = center_error
				worst_case = "%s %s" % [pose["label"], corner]

			var hub_name := corner + ("_Steer" if corner.begins_with("F") else "_Suspension")
			var hub := _node(model, hub_name)
			var lower_arm := _node(model, corner + "_ArmLower")
			var upper_arm := _node(model, corner + "_ArmUpper")
			var lower_arm_transform: Transform3D = root_inverse * lower_arm.global_transform
			var upper_arm_transform: Transform3D = root_inverse * upper_arm.global_transform
			var hub_transform: Transform3D = root_inverse * hub.global_transform
			var side_sign := float(corner_spec["arm_rotation_sign"])
			var lower_end := lower_arm_transform * Vector3(side_sign * arm_length, 0.0, 0.0)
			var upper_end := upper_arm_transform * Vector3(side_sign * arm_length, 0.0, 0.0)
			var lower_joint := hub_transform * Vector3(0.0, -half_ball_joint_height, 0.0)
			var upper_joint := hub_transform * Vector3(0.0, half_ball_joint_height, 0.0)
			var corner_arm_error := maxf(lower_end.distance_to(lower_joint), upper_end.distance_to(upper_joint))
			arm_error = maxf(arm_error, corner_arm_error)

			for shock_name in ["A", "B"]:
				var shock_spec: Dictionary = corner_spec["shocks"][shock_name]
				var body := _node(model, corner + "_Shock" + shock_name + "_Body")
				var shaft := _node(model, corner + "_Shock" + shock_name + "_Shaft")
				var spring := _node(model, corner + "_Shock" + shock_name + "_Spring")
				var body_transform: Transform3D = root_inverse * body.global_transform
				var shaft_transform: Transform3D = root_inverse * shaft.global_transform
				var expected_upper := _vector3(shock_spec["upper_mount"])
				var expected_lower := _expected_shock_lower(spec, corner, shock_spec, travel[index])
				var upper_error := body_transform.origin.distance_to(expected_upper)
				var lower_error := shaft_transform.origin.distance_to(expected_lower)
				shock_endpoint_error = maxf(shock_endpoint_error, maxf(upper_error, lower_error))
				var to_lower := (shaft_transform.origin - body_transform.origin).normalized()
				var body_axis := (-body_transform.basis.y).normalized()
				var shaft_axis := shaft_transform.basis.y.normalized()
				shock_axis_error = maxf(
					shock_axis_error,
					maxf(body_axis.distance_to(to_lower), shaft_axis.distance_to(-to_lower)),
				)
				var shaft_tip := shaft_transform * Vector3(0.0, float(spec["shock_shaft_len"]), 0.0)
				var shaft_tip_distance := body_transform.origin.distance_to(shaft_tip)
				var body_length := float(spec["shock_body_len"])
				shock_tip_inside = shock_tip_inside and shaft_tip_distance > 0.0155 and shaft_tip_distance < body_length - 0.0145
				spring_scale_positive = spring_scale_positive and spring.transform.basis.y.length() > 0.0
				var expected_shock_length := expected_upper.distance_to(expected_lower)
				var actual_shock_length := body_transform.origin.distance_to(shaft_transform.origin)
				shock_endpoint_error = maxf(shock_endpoint_error, absf(actual_shock_length - expected_shock_length))
				if is_equal_approx(travel[index], -float(spec["travel_droop"])):
					declared_shock_lengths = declared_shock_lengths and absf(actual_shock_length - float(shock_range["max"])) < POSITION_TOLERANCE_M
				elif is_equal_approx(travel[index], float(spec["travel_bump"])):
					declared_shock_lengths = declared_shock_lengths and absf(actual_shock_length - float(shock_range["min"])) < POSITION_TOLERANCE_M
				elif is_equal_approx(travel[index], 0.0):
					declared_shock_lengths = declared_shock_lengths and absf(actual_shock_length - float(shock_range["rest"])) < POSITION_TOLERANCE_M

	_check("all 27 poses are accepted", accepted, worst_case)
	_check("wheel centers follow all-corner articulation geometry", wheel_error < POSITION_TOLERANCE_M, str(wheel_error) + " m at " + worst_case)
	_check("upper/lower arms close at both hub joints in all 27 poses", arm_error < POSITION_TOLERANCE_M, str(arm_error) + " m")
	_check("shock eyes match independent endpoints in all 27 poses", shock_endpoint_error < POSITION_TOLERANCE_M, str(shock_endpoint_error) + " m")
	_check("shock body and shaft axes meet without angular kinks", shock_axis_error < 1.0e-3, str(shock_axis_error))
	_check("shock shaft tips remain inside bodies over full travel", shock_tip_inside)
	_check("shock springs never reach zero or negative scale", spring_scale_positive)
	_check("bump/droop/rest shock lengths match declared endpoints", declared_shock_lengths)


func _check_steer_and_spin_signs(model: Dictionary) -> void:
	var spec: Dictionary = model["spec"]
	var positive_steer := deg_to_rad(20.0)
	var left_ok := Visual.apply_pose(model, _zero4(), positive_steer, _zero4())
	var front_left := _model_forward(model, "FL_Steer")
	var front_right := _model_forward(model, "FR_Steer")
	var rear_left := _model_forward(model, "RL_Suspension")
	var rear_right := _model_forward(model, "RR_Suspension")
	left_ok = left_ok and front_left.x < -0.25 and front_right.x < -0.25
	left_ok = left_ok and absf(rear_left.x) < 1.0e-6 and absf(rear_right.x) < 1.0e-6
	_check("positive steer points both front wheels left and leaves rear fixed", left_ok)

	var right_steer_ok := Visual.apply_pose(model, _zero4(), -positive_steer, _zero4())
	front_left = _model_forward(model, "FL_Steer")
	front_right = _model_forward(model, "FR_Steer")
	right_steer_ok = right_steer_ok and front_left.x > 0.25 and front_right.x > 0.25
	_check("negative steer points FL and FR right", right_steer_ok)

	var spin := PackedFloat64Array([0.35, 0.35, 0.35, 0.35])
	var spin_ok := Visual.apply_pose(model, _zero4(), 0.0, _zero4())
	var rest_tops := {}
	for corner in CORNERS:
		rest_tops[corner] = _node(model, corner + "_Spin").global_transform.basis.y.normalized()
	spin_ok = spin_ok and Visual.apply_pose(model, _zero4(), 0.0, spin)
	var forward := Vector3(0.0, 0.0, -1.0)
	for corner in CORNERS:
		var spin_node := _node(model, corner + "_Spin")
		var spun_top := spin_node.global_transform.basis.y.normalized()
		var rest_top: Vector3 = rest_tops[corner]
		spin_ok = spin_ok and (spun_top - rest_top).dot(forward) > 0.04
	_check("positive forward wheel spin moves each tire top toward -Z", spin_ok, str(spec["spin_axis"]))


func _check_invalid_poses_transactional(model: Dictionary) -> void:
	var valid_travel := PackedFloat64Array([0.025, -0.03, 0.04, -0.05])
	var valid_spin := PackedFloat64Array([0.4, -0.3, 0.2, -0.1])
	var valid := Visual.apply_pose(model, valid_travel, deg_to_rad(15.0), valid_spin)
	var all_rejected_unchanged := valid
	var invalid_cases: Array = [
		{"label": "short travel array", "travel": PackedFloat64Array([0.0, 0.0, 0.0]), "steer": 0.0, "spin": _zero4()},
		{"label": "short spin array", "travel": _zero4(), "steer": 0.0, "spin": PackedFloat64Array([0.0, 0.0, 0.0])},
		{"label": "NaN travel", "travel": PackedFloat64Array([NAN, 0.0, 0.0, 0.0]), "steer": 0.0, "spin": _zero4()},
		{"label": "infinite spin", "travel": _zero4(), "steer": 0.0, "spin": PackedFloat64Array([0.0, INF, 0.0, 0.0])},
		{"label": "NaN steering", "travel": _zero4(), "steer": NAN, "spin": _zero4()},
		{"label": "travel above bump stop", "travel": PackedFloat64Array([float(model.spec["travel_bump"]) + 1.0e-6, 0.0, 0.0, 0.0]), "steer": 0.0, "spin": _zero4()},
		{"label": "travel below droop stop", "travel": PackedFloat64Array([-float(model.spec["travel_droop"]) - 1.0e-6, 0.0, 0.0, 0.0]), "steer": 0.0, "spin": _zero4()},
		{"label": "steering above 30 degrees", "travel": _zero4(), "steer": deg_to_rad(float(model.spec["steer_max_deg"]) + 1.0), "spin": _zero4()},
		{"label": "steering below -30 degrees", "travel": _zero4(), "steer": deg_to_rad(-float(model.spec["steer_max_deg"]) - 1.0), "spin": _zero4()},
	]
	for invalid: Dictionary in invalid_cases:
		var before := _snapshot(model)
		var accepted := Visual.apply_pose(
			model,
			invalid.get("travel", _zero4()),
			float(invalid.get("steer", 0.0)),
			invalid.get("spin", _zero4()),
		)
		var after_error := _snapshot_error(model, before)
		all_rejected_unchanged = all_rejected_unchanged and not accepted and after_error == 0.0
	_check("every invalid pose is refused before mutating any transform", all_rejected_unchanged)
	_check("exact travel and steering limits remain valid", Visual.apply_pose(
		model,
		PackedFloat64Array([-float(model.spec["travel_droop"]), float(model.spec["travel_bump"]), 0.0, 0.0]),
		deg_to_rad(float(model.spec["steer_max_deg"])),
		_zero4(),
	))


func _check_instance_isolation(model_a: Dictionary) -> void:
	var model_b: Dictionary = Visual.load_delivery()
	var loaded := bool(model_b.get("ok", false))
	_check("second model instance loads", loaded, str(model_b.get("error", "")))
	if not loaded:
		return
	var root_b: Node3D = model_b["root"]
	root.add_child(root_b)
	await process_frame
	var body_a := _node(model_a, "Body")
	var body_b := _node(model_b, "Body")
	var nodes_are_distinct: bool = root_b != model_a.root and body_a != body_b
	_check("each delivery load owns distinct scene nodes", nodes_are_distinct)

	Visual.set_body_visible(model_a, false)
	var body_isolation := not body_a.visible and body_b.visible
	Visual.set_body_visible(model_a, true)
	body_isolation = body_isolation and body_a.visible and body_b.visible
	_check("body visibility changes only the selected model instance", body_isolation)

	Visual.set_proxies_visible(model_a, true)
	var proxy_isolation := true
	for proxy in model_a.spec["collision_boxes"].keys():
		var a_node := _node(model_a, str(proxy))
		var b_node := _node(model_b, str(proxy))
		proxy_isolation = proxy_isolation and a_node != null and b_node != null
		if a_node != null and b_node != null:
			proxy_isolation = proxy_isolation and a_node.is_visible_in_tree() and not b_node.is_visible_in_tree()
	Visual.set_proxies_visible(model_a, false)
	_check("proxy visibility changes only the selected model instance", proxy_isolation)

	var second_pose_before := _snapshot(model_b)
	var moved := Visual.apply_pose(model_a, PackedFloat64Array([0.045, 0.0, 0.0, 0.0]), 0.0, _zero4())
	_check("posing one loaded model leaves the other unchanged", moved and _snapshot_error(model_b, second_pose_before) == 0.0)
	Visual.apply_pose(model_a, _zero4(), 0.0, _zero4())
	root_b.queue_free()
	await process_frame
	_check("second delivery instance frees cleanly", not is_instance_valid(root_b))


func _check_repeat_load_free(baseline_children: int) -> void:
	var all_freed := true
	for cycle in 3:
		var loaded: Dictionary = Visual.load_delivery()
		if not bool(loaded.get("ok", false)):
			all_freed = false
			_check("repeat load %d succeeds" % cycle, false, str(loaded.get("error", "")))
			continue
		var instance: Node3D = loaded["root"]
		root.add_child(instance)
		await process_frame
		var distinct_node := _node(loaded, "FL_Spin")
		var valid := instance.is_inside_tree() and distinct_node != null
		instance.queue_free()
		await process_frame
		all_freed = all_freed and valid and not is_instance_valid(instance) and root.get_child_count() == baseline_children
	_check("three repeated load/attach/free cycles release every instance", all_freed)


func _extreme_cases(spec: Dictionary) -> Array:
	var cases: Array = []
	var droop := -float(spec["travel_droop"])
	var bump := float(spec["travel_bump"])
	var travel_values := [droop, droop * 0.5, 0.0, bump * 0.5, bump]
	var steer_limit := float(spec["steer_max_deg"])
	var steer_values := [-steer_limit, -steer_limit * 0.5, 0.0, steer_limit * 0.5, steer_limit]
	for travel in travel_values:
		for steer_degrees in steer_values:
			cases.append({
				"label": "common t=%+.3f steer=%+.0f" % [travel, steer_degrees],
				"travel": PackedFloat64Array([travel, travel, travel, travel]),
				"steer": deg_to_rad(steer_degrees),
			})
	for steer_degrees in [-float(spec["steer_max_deg"]), float(spec["steer_max_deg"])]:
		cases.append({
			"label": "crossed FL/RR bump FR/RL droop steer=%+.0f" % steer_degrees,
			"travel": PackedFloat64Array([bump, droop, droop, bump]),
			"steer": deg_to_rad(steer_degrees),
		})
	return cases


func _expected_wheel_center(spec: Dictionary, corner: String, travel: float) -> Vector3:
	var cdata: Dictionary = spec["corners"][corner]
	var theta := asin(travel / float(spec["arm_length"]))
	var side_sign := float(cdata["arm_rotation_sign"])
	var expected := _vector3(cdata["wheel_center_rest"])
	expected.x += side_sign * float(spec["arm_length"]) * (cos(theta) - 1.0)
	expected.y += float(spec["arm_length"]) * sin(theta)
	return expected


func _expected_shock_lower(
	spec: Dictionary,
	corner: String,
	shock_spec: Dictionary,
	travel: float,
) -> Vector3:
	var cdata: Dictionary = spec["corners"][corner]
	var pivot := _vector3(cdata["arm_lower_pivot"])
	var anchor := _vector3(shock_spec["lower_mount_arm_local"])
	var upper := _vector3(shock_spec["upper_mount"])
	var side_sign := float(cdata["arm_rotation_sign"])
	var theta := asin(travel / float(spec["arm_length"]))
	var angle := side_sign * theta
	var dz := upper.z - pivot.z
	var rotated := Vector3(
		cos(angle) * anchor.x - sin(angle) * anchor.y,
		sin(angle) * anchor.x + cos(angle) * anchor.y,
		dz,
	)
	return pivot + rotated


func _half_ball_joint_height(spec: Dictionary) -> float:
	var first: Dictionary = spec["corners"]["FL"]
	return 0.5 * (
		float(_vector3(first["arm_upper_pivot"]).y)
		- float(_vector3(first["arm_lower_pivot"]).y)
	)


func _model_forward(model: Dictionary, node_name: String) -> Vector3:
	var node := _node(model, node_name)
	if node == null:
		return Vector3(INF, INF, INF)
	var relative: Transform3D = model.model_root.global_transform.affine_inverse() * node.global_transform
	return (relative.basis * Vector3.FORWARD).normalized()


func _model_position(model: Dictionary, node_name: String) -> Vector3:
	var node := _node(model, node_name)
	if node == null:
		return Vector3(INF, INF, INF)
	return model.model_root.to_local(node.global_position)


func _node(model: Dictionary, node_name: String) -> Node3D:
	var bindings: Dictionary = model.get("nodes", {})
	var value: Variant = bindings.get(node_name)
	if value is Node3D:
		return value
	return null


func _vector3(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _snapshot(model: Dictionary) -> Dictionary:
	var result := {}
	var rest: Dictionary = model.get("rest", {})
	for name in rest:
		var node := _node(model, str(name))
		if node != null:
			result[name] = node.transform
	return result


func _snapshot_error(model: Dictionary, snapshot: Dictionary) -> float:
	var worst := 0.0
	for name in snapshot:
		var node := _node(model, str(name))
		if node == null:
			return INF
		worst = maxf(worst, _transform_error(node.transform, snapshot[name]))
	return worst


func _transform_error(a: Transform3D, b: Transform3D) -> float:
	return (
		a.origin.distance_to(b.origin)
		+ (a.basis.x - b.basis.x).length()
		+ (a.basis.y - b.basis.y).length()
		+ (a.basis.z - b.basis.z).length()
	)


func _zero4() -> PackedFloat64Array:
	return PackedFloat64Array([0.0, 0.0, 0.0, 0.0])

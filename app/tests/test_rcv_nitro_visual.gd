extends SceneTree

const Adapter = preload("res://vehicles/ground/monster_car_2_model.gd")
const CORNERS := ["FL", "FR", "RL", "RR"]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var visual: Dictionary = Adapter.build()
	if not visual.get("ok", false):
		_fail("Monster Car 2 visual build failed: " + str(visual.get("error", "unknown error")))
		return
	var source := JSON.parse_string(FileAccess.get_file_as_string("res://data/vehicles/ground/monster_car_2.json")) as Dictionary
	var parameters: Dictionary = source.parameters
	var cg_height := float(parameters.cg_height_above_chassis_datum_m.value)
	visual.cg_offset = Vector3(
		float(parameters.cg_right_from_datum_m.value),
		cg_height,
		-float(parameters.cg_forward_from_datum_m.value),
	)
	root.add_child(visual.root)
	var state := PackedFloat64Array()
	state.resize(33)
	state[6] = 1.0
	if not Adapter.draw(visual, state, cg_height):
		_fail("Monster Car 2 neutral pose did not draw")
		return
	var nodes: Dictionary = visual.nodes
	if not nodes.Body is MeshInstance3D or not nodes.Bumper_F is Node3D or not nodes.Bumper_R is Node3D:
		_fail("Monster Car 2 body/bumpers are not bound to authored nodes")
		return
	if visual.body_nodes.size() < 60 or visual.headlight_nodes.size() < 2 or visual.brake_light_nodes.is_empty():
		_fail("Monster Car 2 authored effect bindings are incomplete")
		return

	var expected_x: Array = parameters.corner_y_datum_frd_m.value
	var expected_y: Array = parameters.corner_z_datum_frd_m.value
	var expected_z: Array = parameters.corner_x_datum_frd_m.value
	var wheel_positions: Array[Vector3] = []
	for index in CORNERS.size():
		var wheel := nodes[CORNERS[index] + "_WheelMesh"] as MeshInstance3D
		var local_position: Vector3 = visual.root.to_local(wheel.global_position)
		var physics_datum_position := Vector3(float(expected_x[index]), -float(expected_y[index]), -float(expected_z[index]))
		if local_position.distance_to(physics_datum_position) > 0.001:
			_fail("%s authored wheel center misses the source physics datum by %.6f m" % [CORNERS[index], local_position.distance_to(physics_datum_position)])
			return
		wheel_positions.append(local_position)

	var wheels: Array[MeshInstance3D] = []
	var wheel_rest_transforms: Array[Transform3D] = []
	var wheel_top_vertices: Array[Vector3] = []
	var wheel_top_rest_positions: Array[Vector3] = []
	for index in CORNERS.size():
		var wheel := nodes[CORNERS[index] + "_WheelMesh"] as MeshInstance3D
		wheels.append(wheel)
		wheel_rest_transforms.append(wheel.transform)
		var top_vertex := _top_vertex_in_root(wheel, visual.root)
		wheel_top_vertices.append(top_vertex)
		wheel_top_rest_positions.append(visual.root.to_local(wheel.to_global(top_vertex)))
	var front_left := wheels[0]

	for driven_index in CORNERS.size():
		for index in CORNERS.size():
			state[25 + index] = 0.0
		state[25 + driven_index] = 1.1
		if not Adapter.draw(visual, state, cg_height):
			_fail("Monster Car 2 %s positive wheel-spin pose did not draw" % CORNERS[driven_index])
			return
		var top_after: Vector3 = visual.root.to_local(wheels[driven_index].to_global(wheel_top_vertices[driven_index]))
		var forward_motion: float = wheel_top_rest_positions[driven_index].z - top_after.z
		if forward_motion < 0.005:
			_fail("Monster Car 2 %s positive wheel angle moved its tire top aft/not forward (%.4f m)" % [CORNERS[driven_index], forward_motion])
			return
		if visual.root.to_local(wheels[driven_index].global_position).distance_to(wheel_positions[driven_index]) > 0.0001:
			_fail("Monster Car 2 %s wheel spin moved the tire center" % CORNERS[driven_index])
			return
		for index in CORNERS.size():
			if index != driven_index and not wheels[index].transform.is_equal_approx(wheel_rest_transforms[index]):
				_fail("Monster Car 2 %s wheel spin changed independent %s wheel pose" % [CORNERS[driven_index], CORNERS[index]])
				return
		state[25 + driven_index] = 0.0
		if not Adapter.draw(visual, state, cg_height):
			_fail("Monster Car 2 wheel-spin reset did not draw")
			return

	state[25] = 0.0
	state[13] = 0.03
	if not Adapter.draw(visual, state, cg_height):
		_fail("Monster Car 2 suspension pose did not draw")
		return
	var compressed_position: Vector3 = visual.root.to_local(front_left.global_position)
	if compressed_position.distance_to(wheel_positions[0]) < 0.01:
		_fail("Monster Car 2 authored suspension did not move its front wheel")
		return

	state[13] = 0.0
	var max_steer := float(parameters.max_steer_angle_rad.value)
	var neutral_front_basis: Array[Basis] = []
	for index in 2:
		neutral_front_basis.append(_basis_in_root(wheels[index], visual.root))
	var positive_steer := _measure_front_steer(visual, state, wheels, wheel_rest_transforms, neutral_front_basis, max_steer, cg_height)
	if not positive_steer.get("ok", false):
		_fail(str(positive_steer.get("error", "Positive steering check failed")))
		return
	var negative_steer := _measure_front_steer(visual, state, wheels, wheel_rest_transforms, neutral_front_basis, -max_steer, cg_height)
	if not negative_steer.get("ok", false):
		_fail(str(negative_steer.get("error", "Negative steering check failed")))
		return
	var positive_mean := float(positive_steer.mean)
	var negative_mean := float(negative_steer.mean)
	if positive_mean <= 0.0 or negative_mean >= 0.0:
		_fail("Monster Car 2 steering sign is not positive-right at both physical limits (mean %.4f / %.4f rad)" % [positive_mean, negative_mean])
		return
	if absf(positive_mean - max_steer) > 0.03 or absf(negative_mean + max_steer) > 0.03:
		_fail("Monster Car 2 mean steering angle misses the physical limits (mean %.4f / %.4f, expected ±%.4f rad)" % [positive_mean, negative_mean, max_steer])
		return
	if absf(positive_mean + negative_mean) > 0.015:
		_fail("Monster Car 2 steering angles are not symmetric at the physical limits")
		return
	var engine_mesh := visual._mesh_nodes["Volante_Motor"] as MeshInstance3D
	var engine_rest_basis := engine_mesh.transform.basis
	visual.engine_phase_rad = 1.25
	if not Adapter.draw(visual, state, cg_height):
		_fail("Monster Car 2 engine phase pose did not draw")
		return
	if engine_mesh.transform.basis.is_equal_approx(engine_rest_basis):
		_fail("Monster Car 2 engine phase did not rotate the authored flywheel")
		return
	visual.root.queue_free()
	print("Monster Car 2 visual test passed: bindings, datum fit, four-wheel positive roll, independent wheel poses, suspension, symmetric steering limits, and flywheel phase")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _top_vertex_in_root(wheel: MeshInstance3D, visual_root: Node3D) -> Vector3:
	var top_vertex := Vector3.ZERO
	var highest_y := -INF
	for surface in wheel.mesh.get_surface_count():
		var arrays: Array = wheel.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex: Vector3 in vertices:
			var root_position := visual_root.to_local(wheel.to_global(vertex))
			if root_position.y > highest_y:
				highest_y = root_position.y
				top_vertex = vertex
	return top_vertex


func _basis_in_root(node: Node3D, visual_root: Node3D) -> Basis:
	return (visual_root.global_transform.affine_inverse() * node.global_transform).basis


func _measure_front_steer(visual: Dictionary, state: PackedFloat64Array, wheels: Array[MeshInstance3D], rest_transforms: Array[Transform3D], neutral_basis: Array[Basis], steer_angle: float, cg_height: float) -> Dictionary:
	state[29] = steer_angle
	if not Adapter.draw(visual, state, cg_height):
		return {"ok": false, "error": "Monster Car 2 steering pose did not draw"}
	if visual.travel_outside_art:
		return {"ok": false, "error": "Monster Car 2 physical steering limit mapped outside the authored art range"}
	var mean_yaw := 0.0
	for index in 2:
		var rest_forward := neutral_basis[index] * Vector3.FORWARD
		var steered_forward := _basis_in_root(wheels[index], visual.root) * Vector3.FORWARD
		rest_forward.y = 0.0
		steered_forward.y = 0.0
		rest_forward = rest_forward.normalized()
		steered_forward = steered_forward.normalized()
		var dot := clampf(rest_forward.dot(steered_forward), -1.0, 1.0)
		var right_positive_cross := rest_forward.x * steered_forward.z - rest_forward.z * steered_forward.x
		mean_yaw += atan2(right_positive_cross, dot) / 2.0
	for index in range(2, CORNERS.size()):
		if not wheels[index].transform.is_equal_approx(rest_transforms[index]):
			return {"ok": false, "error": "Front steering changed independent rear %s wheel pose" % CORNERS[index]}
	return {"ok": true, "mean": mean_yaw}

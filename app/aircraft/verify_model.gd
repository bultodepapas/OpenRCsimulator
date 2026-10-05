# Geometry and hinge contract checks for the in-app Ugly Stik.
# Run: godot --headless --path app --script res://aircraft/verify_model.gd
extends SceneTree

const Commands := preload("res://input/commands.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")
const Geometry := preload("res://aircraft/ugly_stik_geometry.gd")
const VisualChecks := preload("res://aircraft/visual_checks.gd")
const Clearance := preload("res://aircraft/model_clearance.gd")

const SURFACE_NAMES := ["aileron_left", "aileron_right", "elevator", "rudder"]
const EXPECTED_SPAN_M := 1.524 # Jensen oz1253 drawing: 60 in, converted to metres.
const SPAN_TOLERANCE_M := 0.006 # allows scan/edge tessellation and the 1.5 in tip rise.
const NUMERIC_EPSILON := 0.00001
const WING_ROOT_SAMPLE_X_M := 0.003 # avoids the centerline seam after each half-wing's dihedral rotation.

var _checks := 0
var _failures := 0
var _root: Node3D
var _airplane: Dictionary


func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _finite_transform(value: Transform3D) -> bool:
	return _finite_vector(value.origin) and _finite_vector(value.basis.x) and _finite_vector(value.basis.y) and _finite_vector(value.basis.z)


func _transform_close(a: Transform3D, b: Transform3D, tolerance: float = NUMERIC_EPSILON) -> bool:
	return (
		a.origin.distance_to(b.origin) <= tolerance
		and a.basis.x.distance_to(b.basis.x) <= tolerance
		and a.basis.y.distance_to(b.basis.y) <= tolerance
		and a.basis.z.distance_to(b.basis.z) <= tolerance
	)


func _aabb_corners(bounds: AABB) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for x in [bounds.position.x, bounds.end.x]:
		for y in [bounds.position.y, bounds.end.y]:
			for z in [bounds.position.z, bounds.end.z]:
				result.append(Vector3(x, y, z))
	return result


func _collect_nodes(node: Node, output: Array[Node]) -> void:
	output.append(node)
	for child in node.get_children():
		_collect_nodes(child, output)


func _collect_meshes(node: Node, output: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		output.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, output)


func _find_named_meshes(node: Node, target_name: String, output: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and node.name == target_name:
		output.append(node as MeshInstance3D)
	for child in node.get_children():
		_find_named_meshes(child, target_name, output)


func _mesh_y_samples_at_xz(mesh_node: MeshInstance3D, x_value: float, z_value: float) -> Array[float]:
	var samples: Array[float] = []
	if mesh_node.mesh == null:
		return samples
	var faces := mesh_node.mesh.get_faces()
	for i in range(0, faces.size(), 3):
		var a := _root.to_local(mesh_node.to_global(faces[i]))
		var b := _root.to_local(mesh_node.to_global(faces[i + 1]))
		var c := _root.to_local(mesh_node.to_global(faces[i + 2]))
		var denominator := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
		if absf(denominator) <= 1e-12:
			continue
		var weight_a := ((b.z - c.z) * (x_value - c.x) + (c.x - b.x) * (z_value - c.z)) / denominator
		var weight_b := ((c.z - a.z) * (x_value - c.x) + (a.x - c.x) * (z_value - c.z)) / denominator
		var weight_c := 1.0 - weight_a - weight_b
		if weight_a >= -1e-7 and weight_b >= -1e-7 and weight_c >= -1e-7:
			samples.append(weight_a * a.y + weight_b * b.y + weight_c * c.y)
	return samples


func _minimum_y(samples: Array[float]) -> float:
	var result := INF
	for y in samples:
		result = minf(result, y)
	return result


func _maximum_y(samples: Array[float]) -> float:
	var result := -INF
	for y in samples:
		result = maxf(result, y)
	return result


# Probe an actual trailing vertex rather than a synthetic point that could sit in a cutout.
func _surface_point(surface_name: String) -> Vector3:
	var mesh := _root.find_child(surface_name, true, false) as MeshInstance3D
	var faces := mesh.mesh.get_faces()
	var trailing := faces[0]
	for point in faces:
		if point.z > trailing.z:
			trailing = point
	return mesh.to_global(trailing)


func _hinge_origins() -> Dictionary:
	var result := {}
	for surface_name in SURFACE_NAMES:
		var hinge: Node3D = _airplane.hinges[surface_name]
		result[surface_name] = hinge.global_position
	return result


func _parent_transforms() -> Dictionary:
	var result := {}
	for surface_name in SURFACE_NAMES:
		var hinge: Node3D = _airplane.hinges[surface_name]
		result[surface_name] = hinge.get_parent().global_transform
	return result


func _check_tree_and_meshes() -> bool:
	var nodes: Array[Node] = []
	var meshes: Array[MeshInstance3D] = []
	_collect_nodes(_root, nodes)
	_collect_meshes(_root, meshes)
	_check("root is named airplane", _root.name == "airplane", str(_root.name))
	_check("model has mesh geometry", not meshes.is_empty())

	var names := {}
	for node in nodes:
		var node_name := String(node.name)
		names[node_name] = int(names.get(node_name, 0)) + 1
		if node is Node3D:
			_check("finite transform %s" % node_name, _finite_transform((node as Node3D).transform))
	for node_name in names:
		_check("unique node name %s" % node_name, names[node_name] == 1, "count=%d" % names[node_name])

	var all_geometry_valid := true
	for mesh_node in meshes:
		var mesh: Mesh = mesh_node.mesh
		var valid := mesh != null
		if valid:
			var faces := mesh.get_faces()
			valid = mesh.get_surface_count() > 0 and faces.size() >= 3
			for vertex in faces:
				if not _finite_vector(vertex):
					valid = false
					break
			var bounds := mesh.get_aabb()
			valid = valid and _finite_vector(bounds.position) and _finite_vector(bounds.size)
			valid = valid and bounds.size.length_squared() > 1e-12
		_check("nonempty finite mesh %s" % mesh_node.name, valid)
		all_geometry_valid = all_geometry_valid and valid

	for surface_name in SURFACE_NAMES:
		var found: Array[MeshInstance3D] = []
		_find_named_meshes(_root, surface_name, found)
		_check("one mesh named %s" % surface_name, found.size() == 1, "count=%d" % found.size())
		if found.size() == 1:
			var hinge: Node3D = _airplane.hinges[surface_name]
			var named_mesh := found[0]
			_check("%s mesh belongs to its hinge" % surface_name, hinge.is_ancestor_of(named_mesh))
			if named_mesh.mesh == null:
				continue
			var relative_bounds := AABB()
			var first := true
			for corner in _aabb_corners(named_mesh.mesh.get_aabb()):
				var in_hinge := hinge.to_local(named_mesh.to_global(corner))
				if first:
					relative_bounds = AABB(in_hinge, Vector3.ZERO)
					first = false
				else:
					relative_bounds = relative_bounds.expand(in_hinge)
			_check(
				"%s mesh extends aft from its hinge" % surface_name,
				not first and relative_bounds.position.z >= -0.01 and relative_bounds.end.z > (0.03 if surface_name.begins_with("aileron_") or surface_name == "elevator" else 0.04),
				str(relative_bounds)
			)

	var span_bounds := AABB()
	var first_span_vertex := true
	for mesh_node in meshes:
		if mesh_node.mesh == null:
			continue
		var transformed_vertices_finite := true
		for vertex in mesh_node.mesh.get_faces():
			var point := _root.to_local(mesh_node.to_global(vertex))
			if not _finite_vector(point):
				transformed_vertices_finite = false
				continue
			if first_span_vertex:
				span_bounds = AABB(point, Vector3.ZERO)
				first_span_vertex = false
			else:
				span_bounds = span_bounds.expand(point)
		_check("finite transformed vertices %s" % mesh_node.name, transformed_vertices_finite)
	var span := span_bounds.size.x if not first_span_vertex else 0.0
	_check(
		"Jensen span 1.524 m within 6 mm",
		absf(span - EXPECTED_SPAN_M) <= SPAN_TOLERANCE_M,
		"measured=%.6f m expected=%.6f m" % [span, EXPECTED_SPAN_M]
	)
	return all_geometry_valid


func _check_interface() -> bool:
	var ok := true
	_check("builder returns root, propeller, hinges", _airplane.has_all(["root", "propeller", "hinges"]))
	if not _airplane.has_all(["root", "propeller", "hinges"]):
		return false
	_check("root is Node3D", _airplane.root is Node3D)
	_check("propeller is Node3D", _airplane.propeller is Node3D)
	_check("hinges is Dictionary", _airplane.hinges is Dictionary)
	if not (_airplane.root is Node3D and _airplane.propeller is Node3D and _airplane.hinges is Dictionary):
		return false
	_root = _airplane.root as Node3D
	for surface_name in SURFACE_NAMES:
		var valid_hinge: bool = _airplane.hinges.has(surface_name) and _airplane.hinges[surface_name] is Node3D
		_check("hinge interface %s" % surface_name, valid_hinge)
		ok = ok and valid_hinge
	return ok


func _check_dihedral_frames() -> void:
	var left_hinge: Node3D = _airplane.hinges["aileron_left"]
	var right_hinge: Node3D = _airplane.hinges["aileron_right"]
	var left_parent := left_hinge.get_parent() as Node3D
	var right_parent := right_hinge.get_parent() as Node3D
	_check("ailerons are under wing rest frames", left_parent != _root and right_parent != _root)
	if left_parent == _root or right_parent == _root:
		return
	var left_y := _root.global_basis.inverse() * left_parent.global_basis.y
	var right_y := _root.global_basis.inverse() * right_parent.global_basis.y
	_check(
		"wing rest frames carry opposite dihedral",
		absf(left_y.x) > 0.001 and absf(right_y.x) > 0.001 and left_y.x * right_y.x < 0.0,
		"left local up=%s right local up=%s" % [left_y, right_y]
	)
	for surface_name in ["aileron_left", "aileron_right"]:
		var hinge: Node3D = _airplane.hinges[surface_name]
		_check("%s dynamic hinge rests at local neutral" % surface_name, hinge.rotation.length() <= NUMERIC_EPSILON, str(hinge.rotation))


func _check_wing_fuselage_seat() -> void:
	var fuselage_nodes: Array[MeshInstance3D] = []
	var right_root_nodes: Array[MeshInstance3D] = []
	var left_root_nodes: Array[MeshInstance3D] = []
	_find_named_meshes(_root, "fuselage", fuselage_nodes)
	_find_named_meshes(_root, "wing_right_0", right_root_nodes)
	_find_named_meshes(_root, "wing_left_0", left_root_nodes)
	_check("fuselage has one mesh for seat check", fuselage_nodes.size() == 1)
	_check("both root wing panels exist for seat check", right_root_nodes.size() == 1 and left_root_nodes.size() == 1)
	if fuselage_nodes.size() != 1 or right_root_nodes.size() != 1 or left_root_nodes.size() != 1:
		return
	var wing: Dictionary = Geometry.DATA.wing
	var contact_z: float = wing.leading_z + wing.chord * 0.06
	for side in [-1.0, 1.0]:
		var sample_x: float = side * WING_ROOT_SAMPLE_X_M
		var wing_node: MeshInstance3D = right_root_nodes[0] if side > 0.0 else left_root_nodes[0]
		var wing_samples := _mesh_y_samples_at_xz(wing_node, sample_x, contact_z)
		var fuselage_samples := _mesh_y_samples_at_xz(fuselage_nodes[0], sample_x, contact_z)
		_check(
			"wing/fuselage samples exist at x=%.3f z=%.4f" % [sample_x, contact_z],
			not wing_samples.is_empty() and not fuselage_samples.is_empty(),
			"wing=%d fuselage=%d" % [wing_samples.size(), fuselage_samples.size()]
		)
		if wing_samples.is_empty() or fuselage_samples.is_empty():
			continue
		var wing_bottom := _minimum_y(wing_samples)
		var fuselage_top := _maximum_y(fuselage_samples)
		var gap := wing_bottom - fuselage_top
		_check(
			"%s wing root seats into fuselage near x=0" % ("right" if side > 0.0 else "left"),
			gap <= 0.001,
			"at x=%.3f z=%.4f m: wing bottom=%.5f m fuselage top=%.5f m gap=%.5f m" % [sample_x, contact_z, wing_bottom, fuselage_top, gap]
		)


func _check_control_direction(axis_control: String, surface_expected_signs: Dictionary, pose_index: int) -> void:
	var root_position := Vector3(2.3, -0.7, 4.1) if pose_index == 1 else Vector3.ZERO
	var root_rotation := Vector3(0.31, -0.47, 0.23) if pose_index == 1 else Vector3.ZERO
	_root.transform = Transform3D(Basis.from_euler(root_rotation), root_position)
	var neutral := Commands.neutral_commands()
	AirplaneBuilder.apply_surfaces(_airplane, Commands.hinge_rotations(neutral))
	var neutral_points := {}
	for surface_name in SURFACE_NAMES:
		neutral_points[surface_name] = _surface_point(surface_name)
	var neutral_hinges := _hinge_origins()
	var neutral_parents := _parent_transforms()
	var up_axis := _root.global_basis.y.normalized()
	var right_axis := _root.global_basis.x.normalized()

	for direction in [-1.0, 1.0]:
		var command := Commands.neutral_commands()
		command[axis_control] = direction
		var hinge_rotations := Commands.hinge_rotations(command)
		AirplaneBuilder.apply_surfaces(_airplane, hinge_rotations)
		for surface_name in SURFACE_NAMES:
			var hinge: Node3D = _airplane.hinges[surface_name]
			var origin_delta: float = hinge.global_position.distance_to(neutral_hinges[surface_name])
			_check("%s %+.0f keeps %s pivot fixed" % [axis_control, direction, surface_name], origin_delta <= NUMERIC_EPSILON, "delta=%.9f" % origin_delta)
			var parent: Node3D = hinge.get_parent() as Node3D
			_check("%s %+.0f keeps %s rest frame fixed" % [axis_control, direction, surface_name], _transform_close(parent.global_transform, neutral_parents[surface_name]))
		var root_local_axis := right_axis if surface_expected_signs.values().has("right") else up_axis
		for surface_name in surface_expected_signs:
			var movement: Vector3 = _surface_point(surface_name) - neutral_points[surface_name]
			var projection: float = movement.dot(root_local_axis)
			var sign_name: String = surface_expected_signs[surface_name]
			var expected_sign := 1.0 if sign_name == "up" or sign_name == "right" else -1.0
			_check(
				"%s %+.0f sends %s TE %s" % [axis_control, direction, surface_name, sign_name],
				projection * expected_sign * direction > 0.0001,
				"movement=%s projection=%.6f" % [movement, projection]
			)

		AirplaneBuilder.apply_surfaces(_airplane, Commands.hinge_rotations(Commands.neutral_commands()))
		for surface_name in SURFACE_NAMES:
			var hinge: Node3D = _airplane.hinges[surface_name]
			_check("%s returns %s hinge angle to neutral" % [axis_control, surface_name], hinge.rotation.length() <= NUMERIC_EPSILON, str(hinge.rotation))
			_check("%s returns %s TE to neutral" % [axis_control, surface_name], _surface_point(surface_name).distance_to(neutral_points[surface_name]) <= NUMERIC_EPSILON)


func _check_root_poses_and_propeller() -> void:
	var root_local_hinges := {}
	for surface_name in SURFACE_NAMES:
		var hinge: Node3D = _airplane.hinges[surface_name]
		root_local_hinges[surface_name] = _root.to_local(hinge.global_position)
	var pose := Transform3D(Basis.from_euler(Vector3(-0.22, 0.52, 0.37)), Vector3(-6.0, 3.2, 1.7))
	_root.transform = pose
	AirplaneBuilder.apply_surfaces(_airplane, Commands.hinge_rotations(Commands.neutral_commands()))
	for surface_name in SURFACE_NAMES:
		var hinge: Node3D = _airplane.hinges[surface_name]
		var expected := _root.to_global(root_local_hinges[surface_name])
		_check("root pose carries %s hinge with model" % surface_name, hinge.global_position.distance_to(expected) <= NUMERIC_EPSILON)
	var hub_position := (_airplane.propeller as Node3D).global_position
	for angle in [0.0, PI / 3.0, PI, TAU]:
		(_airplane.propeller as Node3D).rotation.z = angle
		_check("propeller spin %.2f keeps hub fixed" % angle, (_airplane.propeller as Node3D).global_position.distance_to(hub_position) <= NUMERIC_EPSILON)


func _check_nose_assembly() -> void:
	var fuselage := _root.find_child("fuselage", true, false) as MeshInstance3D
	var wing := _root.find_child("wing_right_0", true, false) as MeshInstance3D
	var nosewheel := _root.find_child("nosewheel", true, false) as MeshInstance3D
	_check("nose assembly nodes present", fuselage != null and wing != null and nosewheel != null)
	if fuselage == null or wing == null or nosewheel == null:
		return
	var firewall_z := _root.to_local(fuselage.to_global(fuselage.mesh.get_aabb().position)).z
	var leading_z := _root.to_local(wing.to_global(wing.mesh.get_aabb().position)).z
	# Independent scan reading: 6.94 in from F1 to LE, not copied from runtime parameters.
	var nose_length := leading_z - firewall_z
	_check("F1 to leading edge agrees with 6.94 in scan reading", absf(nose_length - 6.94 * 0.0254) <= 0.002, "got %.6f m" % nose_length)
	# This step translates the existing estimated installation as a unit; it does not rescale an engine.
	var prop_position := _root.to_local((_airplane.propeller as Node3D).global_position)
	_check("prop retains 117 mm installation offset ahead of F1", absf(firewall_z - prop_position.z - 0.117) < NUMERIC_EPSILON)
	var axle_z := _root.to_local(nosewheel.global_position).z
	_check("nose axle retains 40 mm offset behind F1", absf(axle_z - firewall_z - 0.04) < NUMERIC_EPSILON)


func _check_measured_fuselage_holdout() -> void:
	var fuselage := _root.find_child("fuselage", true, false) as MeshInstance3D
	# Reserved page x=2800, not a fitted station. Source picks roof2476, bottom2781, width346 px.
	var z := -0.115 + (2800 - 808) * 0.000254
	var samples := _mesh_y_samples_at_xz(fuselage, 0.0, z)
	_check("reserved fuselage section exists", not samples.is_empty())
	if samples.is_empty(): return
	_check("reserved fuselage roof within reading allowance", absf(_maximum_y(samples) - (-0.005 + (2595 - 2476) * 0.000254)) <= 0.003)
	_check("reserved fuselage bottom within reading allowance", absf(_minimum_y(samples) - (-0.005 + (2595 - 2781) * 0.000254)) <= 0.003)
	var widest := 0.0
	var faces := fuselage.mesh.get_faces()
	for i in range(0, faces.size(), 3):
		for edge in 3:
			var a := _root.to_local(fuselage.to_global(faces[i + edge]))
			var b := _root.to_local(fuselage.to_global(faces[i + (edge + 1) % 3]))
			if absf(b.z - a.z) < 1e-8: continue
			var fraction := (z - a.z) / (b.z - a.z)
			if fraction >= 0 and fraction <= 1:
				widest = maxf(widest, absf(lerpf(a.x, b.x, fraction)))
	_check("reserved fuselage width within reading allowance", absf(2.0 * widest - 346 * 0.000254) <= 0.006)


func _check_gear_animation() -> void:
	_check("gear interface present", _airplane.has("gear"))
	if not _airplane.has("gear"): return
	var centers := {}
	for key in ["left", "right", "nose"]:
		centers[key] = _airplane.gear[key].global_position
	AirplaneBuilder.apply_gear(_airplane, {left = 1.2, right = -0.7, nose = 0.5}, 0.3)
	for key in ["left", "right", "nose"]:
		_check("wheel spin keeps %s axle fixed" % key, _airplane.gear[key].global_position.distance_to(centers[key]) < NUMERIC_EPSILON)
	_check("nose steering carries its wheel", _airplane.gear.nose.get_parent() == _airplane.gear.steering)
	_check("nose steering takes requested angle", absf(_airplane.gear.steering.rotation.y - 0.3) < NUMERIC_EPSILON)
	_check("left wheel takes independent angle", absf(_airplane.gear.left.rotation.x - 1.2) < NUMERIC_EPSILON)
	_check("right wheel takes independent angle", absf(_airplane.gear.right.rotation.x + 0.7) < NUMERIC_EPSILON)
	AirplaneBuilder.apply_gear(_airplane, {}, 0.0)
	for key in ["left", "right", "nose", "steering"]:
		_check("gear %s resets to neutral" % key, _airplane.gear[key].rotation.length() < NUMERIC_EPSILON)


func _initialize() -> void:
	call_deferred("_run_model_checks")


func _run_model_checks() -> void:
	_airplane = AirplaneBuilder.build()
	if not _airplane.has_all(["root", "propeller", "hinges"]):
		_check("builder interface keys", false, str(_airplane.keys()))
		printerr("%d checks, %d failed" % [_checks, _failures])
		quit(1)
		return
	_root = _airplane.root as Node3D
	root.add_child(_root)
	if not _check_interface():
		_root.free()
		printerr("%d checks, %d failed" % [_checks, _failures])
		quit(1)
		return
	if not _check_tree_and_meshes():
		_root.free()
		printerr("%d checks, %d failed" % [_checks, _failures])
		quit(1)
		return
	var visual: Dictionary = VisualChecks.new().run(_airplane)
	_check("visual atlas and shared materials", visual.ok, str(visual.failures))
	_check_nose_assembly()
	_check_gear_animation()
	_check_measured_fuselage_holdout()
	_check_dihedral_frames()
	_check_wing_fuselage_seat()
	_check_root_poses_and_propeller()
	_check_control_direction("roll", { "aileron_left": "down", "aileron_right": "up" }, 1)
	_check_control_direction("pitch", { "elevator": "up" }, 1)
	_check_control_direction("yaw", { "rudder": "right" }, 1)
	_check_control_direction("roll", { "aileron_left": "down", "aileron_right": "up" }, 0)
	_check_control_direction("pitch", { "elevator": "up" }, 0)
	_check_control_direction("yaw", { "rudder": "right" }, 0)
	_root.transform = Transform3D.IDENTITY
	var clearance_report: Dictionary = Clearance.new().run(_airplane)
	_check("moving surfaces retain geometric clearance", clearance_report.ok, str(clearance_report.get("failures", [])))
	_check_visual_controls()
	_root.free()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)

func _check_visual_controls() -> void:
	var controller = AirplaneBuilder.Controls
	_check("visual controls present", _airplane.has("controls"))
	if not _airplane.has("controls"): return
	var controls: Dictionary = _airplane.controls
	var maximum_gap := 0.0
	var maximum_length := 0.0
	var poses: Array[Dictionary] = []
	for axis in ["roll", "pitch", "yaw"]:
		for i in range(21):
			var commands := {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": 0.0}
			commands[axis] = float(i) / 10.0 - 1.0
			poses.append(commands)
	for roll in [-1.0, 1.0]:
		for pitch in [-1.0, 1.0]:
			for yaw in [-1.0, 1.0]: poses.append({"roll": roll, "pitch": pitch, "yaw": yaw, "throttle": 0.0})
	for commands in poses:
		AirplaneBuilder.apply_surfaces(_airplane, Commands.hinge_rotations(commands))
		var report: Dictionary = controller.audit(controls)
		_check("control mechanism closes " + str(commands), bool(report.ok), str(report.failures))
		if not report.ok: continue
		for mechanism in controls.mechanisms.values():
			for rod in mechanism.rods:
				var node: MeshInstance3D = rod.node
				var cylinder := node.mesh as CylinderMesh
				var a := _root.to_local(node.to_global(Vector3(0, -cylinder.height / 2, 0)))
				var b := _root.to_local(node.to_global(Vector3(0, cylinder.height / 2, 0)))
				var start := _root.to_local(rod.start_joint.global_position)
				var finish := _root.to_local(rod.end_joint.global_position)
				var gap := maxf(a.distance_to(start), b.distance_to(finish))
				maximum_gap = maxf(maximum_gap, gap)
				maximum_length = maxf(maximum_length, absf(a.distance_to(b) - float(rod.target_length_m)))
	_check("built rod endpoints meet their joints over 71 command poses", maximum_gap <= 0.00025, str(maximum_gap))
	_check("built rod lengths remain constant over 71 command poses", maximum_length <= 0.00025, str(maximum_length))
	AirplaneBuilder.apply_surfaces(_airplane, Commands.hinge_rotations({"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": 0.0}))
	print("Visual linkage sweep: 71 poses; max built endpoint gap=%.9f m; max built rod length error=%.9f m" % [maximum_gap, maximum_length])

# Control-linkage closure and lifecycle checks; no changes to flight input.
# Run: godot --headless --path app --script res://aircraft/verify_controls.gd
extends SceneTree

const AirplaneAdapter := preload("res://render/airplane.gd")
const ControlsBuilder := preload("res://aircraft/ugly_stik_controls.gd")
const LINK_TOLERANCE_M := 0.00025
const SURFACE_SWEEPS := {
	"aileron_left": 20.0,
	"aileron_right": 20.0,
	"elevator": 20.0,
	"rudder": 25.0,
}

var _checks := 0
var _failures := 0
var _max_closure := 0.0
var _max_length_error := 0.0


func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _collect_ids(node: Node, output: Array[int]) -> void:
	output.append(node.get_instance_id())
	for child in node.get_children():
		_collect_ids(child, output)


func _pose_rotations(surface_name := "", degrees := 0.0) -> Dictionary:
	var rotations := {
		"aileron_left": {"x": 0.0, "y": 0.0},
		"aileron_right": {"x": 0.0, "y": 0.0},
		"elevator": {"x": 0.0, "y": 0.0},
		"rudder": {"x": 0.0, "y": 0.0},
	}
	var angle := deg_to_rad(degrees)
	match surface_name:
		"aileron_right": rotations.aileron_right.x = -angle
		"aileron_left": rotations.aileron_left.x = angle
		"elevator": rotations.elevator.x = -angle
		"rudder": rotations.rudder.y = angle
	return rotations


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var airplane: Dictionary = AirplaneAdapter.build()
	var root: Node3D = airplane.root
	var carrier := Node3D.new()
	carrier.name = "transformed_test_carrier"
	carrier.transform = Transform3D(Basis.from_euler(Vector3(0.11, -0.37, 0.22)), Vector3(1.7, -0.4, 2.2))
	get_root().add_child(carrier)
	root.transform = Transform3D(Basis.from_euler(Vector3(-0.24, 0.51, -0.16)), Vector3(-0.6, 0.8, 0.35))
	carrier.add_child(root)
	root.force_update_transform()
	var controls: Dictionary = airplane.controls
	_check("control builder succeeds", controls.get("ok", false), str(controls.get("failures", [])))
	if not controls.get("ok", false):
		print("%d checks, %d failed" % [_checks, _failures])
		quit(1)
	_check("two Jensen aileron servos", controls.servos.has_all(["aileron_left", "aileron_right"]))
	_check("two tail servos", controls.servos.has_all(["elevator", "rudder"]))
	_check("throttle servo is animated by the throttle linkage", controls.servos.has("throttle") and controls.servos.throttle.animated and controls.mechanisms.throttle.kind == "cable")
	# US-V18b: the throttle cable tube stays inside the fuselage (sides, floor, under the top sheeting) behind F1.
	var tube_outside := _tube_outside(controls.mechanisms.throttle)
	_check("throttle cable tube runs inside the fuselage behind F1", tube_outside.is_empty(), str(tube_outside))
	# US-V17: the owner chose the two-servo version; each aileron servo drives its horn directly (no bellcrank).
	_check("each aileron has its own servo and a direct pushrod", controls.mechanisms.aileron_left.kind == "direct" and controls.mechanisms.aileron_right.kind == "direct")
	for side in ["left", "right"]:
		var outside := _wing_servo_outside(root, controls, side)
		_check("aileron_%s servo case sits between the wing skins" % side, outside.is_empty(), str(outside))
	for servo_name in ["elevator", "rudder", "throttle"]:
		var outside := _fuselage_servo_outside(controls, servo_name)
		_check("%s servo case and tabs sit inside the fuselage sides and floor" % servo_name, outside.is_empty(), str(outside))
	_check("tail pushrods use direct closure", controls.mechanisms.elevator.kind == "direct" and controls.mechanisms.rudder.kind == "direct")

	var node_ids_before: Array[int] = []
	_collect_ids(root, node_ids_before)
	var neutral_angles: Dictionary = {}
	for mechanism_name in controls.mechanisms:
		neutral_angles[mechanism_name] = {
			"servo": controls.mechanisms[mechanism_name].last_servo_angle,
			"bell": controls.mechanisms[mechanism_name].get("last_bell_angle", 0.0),
			"rods": _rod_lengths(controls.mechanisms[mechanism_name]),
		}
	var initial_audit: Dictionary = ControlsBuilder.audit(controls)
	_check("neutral audit closes", initial_audit.ok, str(initial_audit.failures))
	_check("root really is transformed", root.global_position.distance_to(Vector3.ZERO) > 1.0)
	_check("root-local horn maps through transformed hierarchy", _transformed_horn_matches(root, controls.mechanisms.aileron_left))

	ControlsBuilder.set_maintenance(controls, true)
	_check("maintenance opens internal installation", controls.maintenance_group.visible)
	ControlsBuilder.set_maintenance(controls, false)
	_check("maintenance restores default visibility", not controls.maintenance_group.visible)

	for surface_name in SURFACE_SWEEPS:
		var limit_deg: float = SURFACE_SWEEPS[surface_name]
		for index in range(21):
			var amount := -1.0 + float(index) / 10.0
			AirplaneAdapter.apply_surfaces(airplane, _pose_rotations(surface_name, amount * limit_deg))
			root.force_update_transform()
			var result: Dictionary = ControlsBuilder.audit(controls)
			_max_closure = maxf(_max_closure, float(result.max_closure_error_m))
			_max_length_error = maxf(_max_length_error, float(result.max_length_error_m))
			_check("%s pose %d has continuous closure" % [surface_name, index], result.ok, str(result.failures))
			_check("%s pose %d allocates no nodes" % [surface_name, index], _same_node_ids(root, node_ids_before))
			_check("%s pose %d length within tolerance" % [surface_name, index], float(result.max_length_error_m) <= LINK_TOLERANCE_M, "%.9f m" % result.max_length_error_m)
			if index in [0, 10, 20]:
				_check("%s pose %d endpoint follows transformed hinge" % [surface_name, index], _transformed_horn_matches(root, controls.mechanisms[surface_name]))
			if surface_name.begins_with("aileron"):
				var touch := _aileron_rod_skin_gap(root, controls.mechanisms[surface_name])
				_check("%s pose %d pushrod stays below the lower skin" % [surface_name, index], touch >= 0.001, "%.4f m" % touch)

	# US-V09c: the carburettor lever follows the throttle command over its whole range with a constant-length rod.
	var lever: Node3D = controls.mechanisms.throttle.hinge
	var previous_tip := Vector3.INF
	var servo_angles: Array[float] = []
	var prop_z := float(ControlsBuilder.D.equipment.prop_z)
	var min_prop_gap := INF
	for index in range(21):
		var throttle := float(index) / 20.0
		AirplaneAdapter.apply_throttle(airplane, throttle)
		root.force_update_transform()
		var result: Dictionary = ControlsBuilder.audit(controls)
		_max_closure = maxf(_max_closure, float(result.max_closure_error_m))
		_max_length_error = maxf(_max_length_error, float(result.max_length_error_m))
		_check("throttle %.2f has continuous closure" % throttle, result.ok, str(result.failures))
		_check("throttle %.2f allocates no nodes" % throttle, _same_node_ids(root, node_ids_before))
		_check("throttle %.2f lever angle follows the command" % throttle, is_equal_approx(lever.rotation.x, deg_to_rad(ControlsBuilder.Equipment.THROTTLE_OPENING * (throttle - 0.5) * ControlsBuilder.THROTTLE_TRAVEL_DEG)), str(rad_to_deg(lever.rotation.x)))
		var tip: Vector3 = controls.mechanisms.throttle.endpoints_root.get("horn", Vector3.INF)
		servo_angles.append(rad_to_deg(float(controls.mechanisms.throttle.last_servo_angle)))
		if previous_tip != Vector3.INF:
			# US-V13: pull to open; the O.S. lever hangs below its barrel, so its height is not monotonic.
			_check("throttle %.2f lever tip moves aft" % throttle, tip.z > previous_tip.z, "%s -> %s" % [previous_tip, tip])
		previous_tip = tip
		min_prop_gap = minf(min_prop_gap, tip.z - prop_z)
	_check("throttle lever stays at least 15 mm behind the propeller plane", min_prop_gap >= 0.015, "%.4f m" % min_prop_gap)
	var servo_travel: float = servo_angles.max() - servo_angles.min()
	_check("throttle servo travel suits a standard servo (20..110 degrees)", servo_travel >= 20.0 and servo_travel <= 110.0, "%.1f deg" % servo_travel)
	var hits := _throttle_rod_engine_hits(root, controls, airplane)
	_check("throttle pushrod clears the engine and nose gear over the throttle range", hits.is_empty(), str(hits))
	AirplaneAdapter.apply_throttle(airplane, 0.5)

	AirplaneAdapter.apply_surfaces(airplane, _pose_rotations())
	root.force_update_transform()
	var restored_audit: Dictionary = ControlsBuilder.audit(controls)
	_check("neutral restored after all sweeps", restored_audit.ok, str(restored_audit.failures))
	for mechanism_name in controls.mechanisms:
		var mechanism: Dictionary = controls.mechanisms[mechanism_name]
		var original: Dictionary = neutral_angles[mechanism_name]
		var servo_delta := absf(wrapf(float(mechanism.last_servo_angle) - float(original.servo), -PI, PI))
		var bell_delta := absf(wrapf(float(mechanism.get("last_bell_angle", 0.0)) - float(original.bell), -PI, PI))
		_check("%s servo branch returns to neutral" % mechanism_name, servo_delta < 1.0e-5, "delta=%.8f rad" % servo_delta)
		if mechanism.kind == "bellcrank":
			_check("%s bellcrank branch returns to neutral" % mechanism_name, bell_delta < 1.0e-5, "delta=%.8f rad" % bell_delta)
		_check("%s neutral rod lengths restore" % mechanism_name, _rod_lengths(mechanism) == original.rods, str(_rod_lengths(mechanism)))
	_check("neutral restore allocates no nodes", _same_node_ids(root, node_ids_before))
	_check("maximum swept closure <= 0.25 mm", _max_closure <= LINK_TOLERANCE_M, "%.9f m" % _max_closure)
	_check("maximum swept rod error <= 0.25 mm", _max_length_error <= LINK_TOLERANCE_M, "%.9f m" % _max_length_error)

	root.free()
	carrier.free()
	print("%d checks, %d failed; max closure %.9f m; max length error %.9f m" % [_checks, _failures, _max_closure, _max_length_error])
	quit(1 if _failures > 0 else 0)


func _rod_lengths(mechanism: Dictionary) -> Array[float]:
	var result: Array[float] = []
	for rod in mechanism.rods:
		result.append(float(rod.current_length_m))
	return result


func _same_node_ids(root: Node3D, expected: Array[int]) -> bool:
	var current: Array[int] = []
	_collect_ids(root, current)
	return current == expected


## Root-space corners of a servo's case and tab tips.
func _servo_corners(servo: Dictionary) -> Array[Vector3]:
	var basis: Basis = servo.case_basis
	var size: Vector3 = ControlsBuilder.SERVO_CASE_M
	var centre: Vector3 = servo.case_root
	var corners: Array[Vector3] = []
	for x in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			for z in [-1.0, 1.0]:
				corners.append(centre + basis * Vector3(x * size.x, y * size.y, z * size.z) * 0.5)
		for z in [-1.0, 1.0]:
			var tab_y := ControlsBuilder.SERVO_TAB_Y_M - size.y * 0.5
			corners.append(centre + basis * Vector3(x * ControlsBuilder.SERVO_TAB_SPAN_M * 0.5, tab_y, z * 0.009))
	return corners


## Case corners of a wing servo outside the skins (lower skin plus hatch, upper skin less its 3/32 in sheet).
func _wing_servo_outside(root: Node3D, controls: Dictionary, side: String) -> Array:
	var frame := (controls.hinges["aileron_" + side] as Node3D).get_parent() as Node3D
	var to_frame := Transform3D(ControlsBuilder._basis_in_root(root, frame), ControlsBuilder._point_in_root(root, frame, Vector3.ZERO)).affine_inverse()
	var chord := float(ControlsBuilder.D.wing.chord)
	var outside := []
	for corner in _servo_corners(controls.servos["aileron_" + side]):
		var local := to_frame * corner
		var lower := ControlsBuilder._wing_surface_y(local.z / chord, false) + ControlsBuilder.HATCH_M.y * 0.5
		var upper := ControlsBuilder._wing_surface_y(local.z / chord, true) - 0.0024
		if local.y < lower or local.y > upper:
			outside.append("%s (skins %.4f..%.4f)" % [local, lower, upper])
	return outside


## Case and tab corners of a fuselage servo outside the sides (less sheeting) or below the floor sheeting.
func _fuselage_servo_outside(controls: Dictionary, servo_name: String) -> Array:
	var stations: Array = ControlsBuilder.D.fuselage_stations
	var outside := []
	for corner in _servo_corners(controls.servos[servo_name]):
		var floor := -INF
		for i in range(stations.size() - 1):
			if float(stations[i][0]) <= corner.z and corner.z <= float(stations[i + 1][0]):
				var t := (corner.z - float(stations[i][0])) / (float(stations[i + 1][0]) - float(stations[i][0]))
				floor = lerpf(float(stations[i][3]), float(stations[i + 1][3]), t) + ControlsBuilder.FUSELAGE_BOTTOM_M
		if absf(corner.x) > ControlsBuilder._fuselage_inner_half_width(corner.z) or corner.y < floor:
			outside.append(str(corner))
	return outside


## Throttle tube centre-line samples behind F1 whose tube wall leaves the fuselage interior.
func _tube_outside(mechanism: Dictionary) -> Array:
	var e: Dictionary = ControlsBuilder.D.equipment
	var radius: float = ControlsBuilder.THROTTLE_TUBE_RADIUS_M
	var outside := []
	for point: Vector3 in mechanism.tube_path:
		if point.z < float(e.firewall_z) + 0.0064: continue # in F1 or ahead of it
		var section: Vector3 = ControlsBuilder._fuselage_section(point.z)
		var half := section.x - ControlsBuilder.FUSELAGE_SIDE_M
		if absf(point.x) + radius > half or point.y - radius < section.z + ControlsBuilder.FUSELAGE_BOTTOM_M or point.y + radius > section.y - 0.0064:
			outside.append(str(point))
	return outside


## Smallest clearance between an aileron pushrod (surface, 1.15 mm radius) and the fixed wing's lower skin.
func _aileron_rod_skin_gap(root: Node3D, mechanism: Dictionary) -> float:
	var frame := (mechanism.hinge as Node3D).get_parent() as Node3D
	var to_frame := Transform3D(ControlsBuilder._basis_in_root(root, frame), ControlsBuilder._point_in_root(root, frame, Vector3.ZERO)).affine_inverse()
	var wing: Dictionary = ControlsBuilder.D.wing
	var a: Vector3 = to_frame * (mechanism.endpoints_root.servo as Vector3)
	var b: Vector3 = to_frame * (mechanism.endpoints_root.horn as Vector3)
	var gap := INF
	for i in range(41):
		var point := a.lerp(b, float(i) / 40.0)
		var u := point.z / float(wing.chord)
		if u >= float(wing.hinge_fraction): continue
		gap = minf(gap, ControlsBuilder._wing_surface_y(u, false) - point.y - ControlsBuilder.ROD_RADIUS_M)
	return gap


func _transformed_horn_matches(root: Node3D, mechanism: Dictionary) -> bool:
	var expected_world: Vector3 = mechanism.hinge.to_global(mechanism.horn_local)
	var root_local: Vector3 = mechanism.endpoints_root.get("horn", Vector3.INF)
	var actual_world := root.to_global(root_local)
	return expected_world.distance_to(actual_world) < 0.000001


# Rod envelope (axis and 1.3 mm parallels, inset 8 mm from each clevis) against every engine and nose-gear triangle, in
# millimetres, at 11 throttles. US-V13: the imported engine is indexed and has ~140k triangles, so faces come from
# get_faces() into one TriangleMesh (BVH) instead of a GDScript loop per segment.
func _throttle_rod_engine_hits(root: Node3D, controls: Dictionary, airplane: Dictionary) -> Array:
	var triangles := PackedVector3Array()
	for mesh_name in ["engine_assembly", "nose_gear_strut", "nose_bearing", "nose_spring"]:
		var part := root.find_child(mesh_name, true, false) as MeshInstance3D
		if part == null: return ["missing " + mesh_name]
		var to_root := Transform3D.IDENTITY
		var cursor: Node = part
		while cursor != null and cursor != root:
			to_root = (cursor as Node3D).transform * to_root
			cursor = cursor.get_parent()
		# Millimetres: Geometry3D rejects determinants below its 1e-5 epsilon, which metre-sized mm triangles fall under.
		for point: Vector3 in part.mesh.get_faces(): triangles.append(to_root * point * 1000.0)
	var bvh := TriangleMesh.new()
	if not bvh.create_from_faces(triangles): return ["cannot build the engine BVH (%d vertices)" % triangles.size()]
	var hits: Array = []
	# Positive control: a segment across the crankcase must cross its walls, or the probe proves nothing.
	var e: Dictionary = ControlsBuilder.D.equipment
	var centre := Vector3(0, float(e.shaft_y), (float(e.firewall_z) + float(e.prop_z)) * 0.5)
	if bvh.intersect_segment((centre + Vector3(-0.1, 0, 0)) * 1000.0, (centre + Vector3(0.1, 0, 0)) * 1000.0).is_empty():
		return ["probe found no engine triangles (%d vertices)" % triangles.size()]
	for index in range(11):
		var throttle := float(index) / 10.0
		AirplaneAdapter.apply_throttle(airplane, throttle)
		var ends: Dictionary = controls.mechanisms.throttle.endpoints_root
		# US-V18b: the exposed front cable, from its tube at F1 to the lever.
		var a: Vector3 = ends.get("cable_front", ends.servo)
		var b: Vector3 = ends.horn
		var direction := (b - a).normalized()
		a = (a + direction * 0.008) * 1000.0
		b = (b - direction * 0.008) * 1000.0
		# The axis plus four parallels 1.3 mm off it (0.8 mm rod radius + 0.5 mm clearance).
		var side := direction.cross(Vector3.UP).normalized() * 1.3
		var lift := side.cross(direction).normalized() * 1.3
		var hit := false
		for offset: Vector3 in [Vector3.ZERO, side, -side, lift, -lift]:
			hit = hit or not bvh.intersect_segment(a + offset, b + offset).is_empty()
		if hit: hits.append(throttle)
	AirplaneAdapter.apply_throttle(airplane, 0.5)
	return hits


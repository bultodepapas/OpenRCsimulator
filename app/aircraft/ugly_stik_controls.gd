# Jensen-style visual control linkages for the Ugly Stik 60.
# Geometry is estimated where the plan does not give a dimension; the simulation
# remains the source of each hinge pose and this file does not affect flight.
extends RefCounted

const Geometry := preload("res://aircraft/ugly_stik_geometry.gd")
const Finish := preload("res://aircraft/ugly_stik_finish.gd")
const D: Dictionary = Geometry.DATA

const PLASTIC := Color("24272b")
const DARK_PLASTIC := Color("15181b")
const STEEL := Color("9ca3a8")
const THREAD_DARK := Color("565b60")
const BRASS := Color("b88736")
const FIBER_PLATE := Color("686a65")
const WOOD := Color("b58a58")
const SERVO_BODY_SIZE := Vector3(0.040, 0.022, 0.020) # Generic standard-class servo silhouette; no model selected.
const HORN_REACH_M := 0.028
const ROD_RADIUS_M := 0.00115
const LINK_ERROR_TOLERANCE_M := 0.00025 # Visual implementation target from US-V04/05.
const SOLVER_EPSILON := 1.0e-10


## Add one-time geometry under `root`. Hinge rotations remain owned by the adapter.
static func build(root: Node3D, hinges: Dictionary) -> Dictionary:
	if root == null:
		return {"ok": false, "failures": ["root must be Node3D"]}
	for hinge_name in ["aileron_left", "aileron_right", "elevator", "rudder"]:
		if not hinges.has(hinge_name) or not (hinges[hinge_name] is Node3D):
			return {"ok": false, "failures": ["missing Node3D hinge: %s" % hinge_name]}

	var assembly := Node3D.new()
	assembly.name = "control_system"
	root.add_child(assembly)
	var service := Node3D.new()
	service.name = "maintenance_installation"
	assembly.add_child(service)
	service.visible = false
	var linkages := Node3D.new()
	linkages.name = "external_linkages"
	assembly.add_child(linkages)
	var mechanisms: Dictionary = {}
	var servos: Dictionary = {}
	var failures: Array[String] = []

	_build_wing_mechanism(root, assembly, service, linkages, hinges, "left", mechanisms, servos, failures)
	_build_wing_mechanism(root, assembly, service, linkages, hinges, "right", mechanisms, servos, failures)
	_build_tail_mechanism(root, assembly, service, linkages, hinges, "elevator", mechanisms, servos, failures)
	_build_tail_mechanism(root, assembly, service, linkages, hinges, "rudder", mechanisms, servos, failures)
	_build_throttle_approximation(root, service, linkages, servos)
	_batch_static_meshes(service, "maintenance_static")
	_batch_static_meshes(linkages, "linkage_static")
	var controls := {
		"ok": failures.is_empty(),
		"root": root,
		"assembly": assembly,
		"maintenance_group": service,
		"linkage_group": linkages,
		"hinges": hinges,
		"mechanisms": mechanisms,
		"servos": servos,
		"maintenance": false,
		"errors": {"max_closure_error_m": 0.0, "max_length_error_m": 0.0, "solve_failures": failures.duplicate()},
		"failures": failures,
	}
	update(controls)
	return controls


## Called after the adapter applies the flight model's hinge rotations.
static func update(controls: Dictionary) -> void:
	if not controls.get("ok", false):
		return
	var failures: Array[String] = []
	for mechanism_name in controls.mechanisms:
		var mechanism: Dictionary = controls.mechanisms[mechanism_name]
		var root: Node3D = controls.root
		var hinge: Node3D = mechanism.hinge
		var target := _point_in_root(root, hinge, mechanism.horn_local)
		var u: Vector3 = mechanism.plane_u
		var v: Vector3 = mechanism.plane_v
		var normal: Vector3 = mechanism.plane_normal
		var rods: Array = mechanism.rods
		var solved := true
		var endpoints: Dictionary = {}

		if mechanism.kind == "direct":
			var servo_solution := _solve_crank(
				mechanism.servo_pivot, mechanism.servo_radius_m, target, mechanism.rods[0].target_length_m,
				u, v, normal, mechanism.last_servo_angle
			)
			if not servo_solution.ok:
				solved = false
				failures.append("%s servo crank has no circle closure" % mechanism_name)
			else:
				mechanism.last_servo_angle = servo_solution.angle
				_update_arm(mechanism.servo_arm, mechanism.servo_pivot, servo_solution.point, u, v, normal, servo_solution.angle)
				endpoints["servo"] = servo_solution.point
				endpoints["horn"] = target
				_update_rod(rods[0], servo_solution.point, target, normal)
				mechanism.closure_error_m = rods[0].length_error_m
		elif mechanism.kind == "bellcrank":
			var bell_solution := _solve_crank(
				mechanism.bell_pivot, mechanism.bell_output_radius_m, target, mechanism.rods[1].target_length_m,
				u, v, normal, mechanism.last_bell_angle
			)
			if not bell_solution.ok:
				solved = false
				failures.append("%s bellcrank has no circle closure" % mechanism_name)
			else:
				mechanism.last_bell_angle = bell_solution.angle
				var bell_input_vector: Vector3 = mechanism.bell_input_zero.rotated(normal, bell_solution.angle)
				var bell_input_point: Vector3 = mechanism.bell_pivot + bell_input_vector
				var servo_solution := _solve_crank(
					mechanism.servo_pivot, mechanism.servo_radius_m, bell_input_point, mechanism.rods[0].target_length_m,
					u, v, normal, mechanism.last_servo_angle
				)
				if not servo_solution.ok:
					solved = false
					failures.append("%s input rod has no circle closure" % mechanism_name)
				else:
					mechanism.last_servo_angle = servo_solution.angle
					_update_arm(mechanism.servo_arm, mechanism.servo_pivot, servo_solution.point, u, v, normal, servo_solution.angle)
					mechanism.bell_output_arm.transform = _beam_transform(mechanism.bell_pivot, bell_solution.point, normal)
					mechanism.bell_input_arm.transform = _beam_transform(mechanism.bell_pivot, bell_input_point, normal)
					_update_rod(rods[0], servo_solution.point, bell_input_point, normal)
					_update_rod(rods[1], bell_solution.point, target, normal)
					endpoints["servo"] = servo_solution.point
					endpoints["bellcrank_input"] = bell_input_point
					endpoints["bellcrank_output"] = bell_solution.point
					endpoints["horn"] = target
				mechanism.closure_error_m = maxf(rods[0].length_error_m, rods[1].length_error_m)
		else:
			solved = false
			failures.append("%s has unknown mechanism kind" % mechanism_name)

		mechanism.solved = solved
		mechanism.endpoints_root = endpoints
		mechanism.length_errors_m = []
		for rod in rods:
			mechanism.length_errors_m.append(float(rod.get("length_error_m", 0.0)))
		if not solved:
			mechanism.closure_error_m = INF

	controls.failures = failures
	controls.errors = _rollup_errors(controls.mechanisms, failures)


## Show the internal servos, trays, isolators and feed wires in the model inspector.
static func set_maintenance(controls: Dictionary, visible: bool) -> void:
	if not controls.has("maintenance_group"):
		return
	var group: Node3D = controls.maintenance_group
	group.visible = visible
	controls.maintenance = visible


## Small contract helper used by the standalone verifier and the app's model verifier.
static func audit(controls: Dictionary) -> Dictionary:
	if not controls.get("ok", false):
		return {"ok": false, "failures": controls.get("failures", ["control build failed"])}
	var failures: Array[String] = []
	var max_closure_error := 0.0
	var max_length_error := 0.0
	var mechanism_results: Dictionary = {}
	for mechanism_name in controls.mechanisms:
		var mechanism: Dictionary = controls.mechanisms[mechanism_name]
		var closure_error: float = float(mechanism.get("closure_error_m", INF))
		max_closure_error = maxf(max_closure_error, closure_error)
		var rod_results: Array[Dictionary] = []
		for rod in mechanism.rods:
			var actual: float = float(rod.get("current_length_m", INF))
			var target: float = float(rod.target_length_m)
			var error := absf(actual - target)
			max_length_error = maxf(max_length_error, error)
			rod_results.append({
				"name": rod.name,
				"target_length_m": target,
				"current_length_m": actual,
				"length_error_m": error,
			})
			if error > LINK_ERROR_TOLERANCE_M:
				failures.append("%s rod %s length error %.6f m" % [mechanism_name, rod.name, error])
		if not mechanism.get("solved", false):
			failures.append("%s did not solve" % mechanism_name)
		elif closure_error > LINK_ERROR_TOLERANCE_M:
			failures.append("%s closure error %.6f m" % [mechanism_name, closure_error])
		mechanism_results[mechanism_name] = {
			"kind": mechanism.kind,
			"solved": mechanism.get("solved", false),
			"closure_error_m": closure_error,
			"rods": rod_results,
			"endpoints_root": mechanism.get("endpoints_root", {}),
		}
	for failure in controls.get("failures", []):
		if not failures.has(failure):
			failures.append(failure)
	return {
		"ok": failures.is_empty(),
		"max_closure_error_m": max_closure_error,
		"max_length_error_m": max_length_error,
		"mechanisms": mechanism_results,
		"failures": failures,
	}


static func _build_wing_mechanism(root: Node3D, assembly: Node3D, service: Node3D, linkages: Node3D, hinges: Dictionary, side: String, mechanisms: Dictionary, servos: Dictionary, failures: Array[String]) -> void:
	var surface_name := "aileron_" + side
	var hinge: Node3D = hinges[surface_name]
	var frame := hinge.get_parent() as Node3D
	if frame == null:
		failures.append("%s hinge needs a wing rest frame" % surface_name)
		return
	var sign := -1.0 if side == "left" else 1.0
	var wing: Dictionary = D.wing
	var frame_basis := _basis_in_root(root, frame).orthonormalized()
	var outward: Vector3 = frame_basis.x * sign
	var aft: Vector3 = frame_basis.z
	var normal := outward.cross(aft).normalized()
	var half_span: float = (float(wing.aileron_outer) - float(wing.aileron_inner)) * 0.5
	var local_horn_x := -sign * (half_span - 0.008)
	var horn_local := Vector3(local_horn_x, -0.028, (1.0 - float(wing.hinge_fraction)) * float(wing.chord) * 0.83)
	_add_control_horn(hinge, surface_name + "_control_horn", horn_local, false, normal)
	var horn_root := _point_in_root(root, hinge, horn_local)

	# The drawing shows a root mounted servo, a spanwise pushrod and a bellcrank that
	# turns the motion into a short run to the aileron horn. Stations are visual estimates.
	var servo_local := Vector3(sign * 0.055, -0.027, 0.155)
	var bell_local := Vector3(sign * 0.165, -0.027, 0.155)
	var servo_pivot := _point_in_root(root, frame, servo_local)
	var bell_pivot := _point_in_root(root, frame, bell_local)
	var servo_radius := 0.012
	var bell_input_radius := 0.010
	var bell_output_radius := 0.014
	var servo_zero := outward * servo_radius
	var to_horn := horn_root - bell_pivot
	var flat_delta := to_horn - normal * to_horn.dot(normal)
	if flat_delta.length_squared() <= SOLVER_EPSILON:
		failures.append("%s estimated horn and bellcrank stations collapse" % surface_name)
		return
	var bell_output_zero := (normal.cross(flat_delta.normalized()) * bell_output_radius).normalized() * bell_output_radius
	var bell_output_zero_angle := atan2(bell_output_zero.dot(aft), bell_output_zero.dot(outward))
	var bell_input_neutral := outward * bell_input_radius
	var bell_input_zero := bell_input_neutral.rotated(normal, -bell_output_zero_angle)
	var servo_endpoint_neutral := servo_pivot + servo_zero
	var bell_input_neutral_point := bell_pivot + bell_input_neutral
	var input_length := servo_endpoint_neutral.distance_to(bell_input_neutral_point)
	var output_length := (bell_pivot + bell_output_zero).distance_to(horn_root)
	if input_length <= 0.01 or output_length <= 0.01:
		failures.append("%s has an implausibly short estimated linkage" % surface_name)
		return

	var servo_case := _point_in_root(root, frame, servo_local + Vector3(0, 0.002, -0.012))
	_add_servo(service, "aileron_servo_" + side, servo_case, frame_basis, SERVO_BODY_SIZE, servo_pivot, normal, Vector3(sign, 0, 0), Vector3(-sign * 0.050, 0, 0), true)
	servos["aileron_" + side] = {"type": "aileron", "side": side, "shaft_root": servo_pivot, "case_root": servo_case, "reference": "Jensen sheet 2: one root servo and bellcrank per semispan"}
	_add_bellcrank_support(linkages, surface_name + "_bellcrank", bell_pivot, normal, frame_basis, 0.014)
	var bell_output_arm := _new_arm(linkages, surface_name + "_bellcrank_output_arm", bell_pivot, outward, aft, normal, bell_output_zero_angle, bell_output_radius, 0.0032)
	var bell_input_arm := _new_arm(service, surface_name + "_bellcrank_input_arm", bell_pivot, outward, aft, normal, bell_output_zero_angle, bell_input_radius, 0.0028)
	var servo_arm := _new_arm(service, surface_name + "_servo_arm", servo_pivot, outward, aft, normal, 0.0, servo_radius, 0.0034)

	var input_rod := _new_rod(service, surface_name + "_servo_to_bellcrank", input_length, ROD_RADIUS_M, STEEL, "steel")
	var output_rod := _new_rod(linkages, surface_name + "_bellcrank_to_horn", output_length, ROD_RADIUS_M, STEEL, "steel")
	var input_start := _new_joint(service, surface_name + "_input_servo_clevis", servo_endpoint_neutral, normal)
	var input_end := _new_joint(service, surface_name + "_input_bellcrank_clevis", bell_input_neutral_point, normal)
	var output_start := _new_joint(linkages, surface_name + "_output_bellcrank_clevis", bell_pivot + bell_output_zero, normal)
	var output_end := _new_joint(linkages, surface_name + "_output_horn_clevis", horn_root, normal)
	var cable_end := servo_local - Vector3(sign * 0.040, 0, 0)
	_add_cable_route(service, surface_name + "_servo_lead", [_point_in_root(root, frame, servo_local + Vector3(-sign * 0.014, 0.004, -0.010)), _point_in_root(root, frame, servo_local + Vector3(-sign * 0.030, 0.002, -0.010)), _point_in_root(root, frame, cable_end)])

	mechanisms[surface_name] = {
		"kind": "bellcrank",
		"surface": surface_name,
		"hinge": hinge,
		"horn_local": horn_local,
		"plane_u": outward,
		"plane_v": aft,
		"plane_normal": normal,
		"servo_pivot": servo_pivot,
		"servo_radius_m": servo_radius,
		"last_servo_angle": 0.0,
		"servo_arm": servo_arm,
		"bell_pivot": bell_pivot,
		"bell_input_radius_m": bell_input_radius,
		"bell_input_zero": bell_input_neutral,
		"bell_output_radius_m": bell_output_radius,
		"bell_output_zero_angle": bell_output_zero_angle,
		"last_bell_angle": bell_output_zero_angle,
		"bell_output_arm": bell_output_arm,
		"bell_input_arm": bell_input_arm,
		"rods": [
			{"name": surface_name + "_servo_to_bellcrank", "node": input_rod, "start_joint": input_start, "end_joint": input_end, "target_length_m": input_length, "current_length_m": input_length, "length_error_m": 0.0},
			{"name": surface_name + "_bellcrank_to_horn", "node": output_rod, "start_joint": output_start, "end_joint": output_end, "target_length_m": output_length, "current_length_m": output_length, "length_error_m": 0.0},
		],
		"solved": true,
		"closure_error_m": 0.0,
		"estimated_geometry": true,
	}
	_update_arm(servo_arm, servo_pivot, servo_endpoint_neutral, outward, aft, normal, 0.0)
	_update_beam(bell_output_arm, bell_pivot, bell_pivot + bell_output_zero, normal)
	_update_beam(bell_input_arm, bell_pivot, bell_input_neutral_point, normal)
	_update_rod(mechanisms[surface_name].rods[0], servo_endpoint_neutral, bell_input_neutral_point, normal)
	_update_rod(mechanisms[surface_name].rods[1], bell_pivot + bell_output_zero, horn_root, normal)


static func _build_tail_mechanism(root: Node3D, assembly: Node3D, service: Node3D, linkages: Node3D, hinges: Dictionary, surface_name: String, mechanisms: Dictionary, servos: Dictionary, failures: Array[String]) -> void:
	var hinge: Node3D = hinges[surface_name]
	var is_elevator := surface_name == "elevator"
	var normal := Vector3.RIGHT if is_elevator else Vector3.DOWN
	var u := Vector3.UP if is_elevator else Vector3.RIGHT
	var v := Vector3.BACK
	# The tail control surfaces extend aft (negative local z) from the hinge.
	var horn_local := Vector3(-0.046, -0.024, -0.030) if is_elevator else Vector3(0.027, 0.006, -0.018)
	_add_control_horn(hinge, surface_name + "_control_horn", horn_local, not is_elevator, normal)
	var horn_root := _point_in_root(root, hinge, horn_local)
	var servo_center := Vector3(-0.013, -0.025, 0.045) if is_elevator else Vector3(0.013, -0.025, 0.045)
	var servo_radius := 0.016
	var servo_pivot := servo_center + (normal * 0.011 if is_elevator else Vector3.UP * 0.011)
	var servo_zero := u * servo_radius
	var neutral_endpoint := servo_pivot + servo_zero
	var rod_length := neutral_endpoint.distance_to(horn_root)
	if rod_length <= 0.1:
		failures.append("%s estimated pushrod is too short" % surface_name)
		return
	# Two compact servos sit side by side near the wing. Their long axes run along
	# the fuselage; the elevator output shaft faces sideways and the rudder shaft up.
	var body_basis := Basis(Vector3.FORWARD, normal, Vector3.FORWARD.cross(normal).normalized())
	_add_servo(service, surface_name + "_servo", servo_center, body_basis, SERVO_BODY_SIZE, servo_pivot, normal, u, Vector3(0.052, 0, 0), false)
	servos[surface_name] = {"type": surface_name, "shaft_root": servo_pivot, "case_root": servo_center, "reference": "Jensen fuselage servo rails; installation station estimated"}
	var tray_center := servo_center + Vector3(0, -0.013, 0)
	for side in [-1.0, 1.0]:
		_add_box(service, surface_name + "_tray_rail_" + ("left" if side < 0 else "right"), Vector3(0.006, 0.004, 0.054), tray_center + Vector3(side * 0.013, 0, 0), Basis.IDENTITY, WOOD, "wood")
	var rod := _new_rod(linkages, surface_name + "_long_pushrod", rod_length, ROD_RADIUS_M, STEEL, "steel")
	var start_joint := _new_joint(linkages, surface_name + "_servo_clevis", neutral_endpoint, normal)
	var end_joint := _new_joint(linkages, surface_name + "_horn_clevis", horn_root, normal)
	var arm := _new_arm(service, surface_name + "_servo_arm", servo_pivot, u, v, normal, 0.0, servo_radius, 0.0034)
	var cable_to := Vector3(0, -0.024, 0.008)
	_add_cable_route(service, surface_name + "_servo_lead", [servo_center + Vector3(0.004, 0.002, -0.010), servo_center + Vector3(0.002, 0.002, -0.022), cable_to])
	_add_tail_guide(root, linkages, surface_name, neutral_endpoint, horn_root, normal)
	mechanisms[surface_name] = {
		"kind": "direct",
		"surface": surface_name,
		"hinge": hinge,
		"horn_local": horn_local,
		"plane_u": u,
		"plane_v": v,
		"plane_normal": normal,
		"servo_pivot": servo_pivot,
		"servo_radius_m": servo_radius,
		"last_servo_angle": 0.0,
		"servo_arm": arm,
		"rods": [
			{"name": surface_name + "_long_pushrod", "node": rod, "start_joint": start_joint, "end_joint": end_joint, "target_length_m": rod_length, "current_length_m": rod_length, "length_error_m": 0.0},
		],
		"solved": true,
		"closure_error_m": 0.0,
		"estimated_geometry": true,
	}
	_update_arm(arm, servo_pivot, neutral_endpoint, u, v, normal, 0.0)
	_update_rod(mechanisms[surface_name].rods[0], neutral_endpoint, horn_root, normal)


static func _build_throttle_approximation(root: Node3D, service: Node3D, linkages: Node3D, servos: Dictionary) -> void:
	# The geometry API contains no throttle hinge/command. This is a quiet, neutral
	# installation cue only; the adapter may animate it later if it supplies throttle.
	var e: Dictionary = D.equipment
	var engine_z := (float(e.firewall_z) + float(e.prop_z)) * 0.5
	var carburetor_point := Vector3(0.019, float(e.shaft_y) + 0.031, engine_z - 0.030)
	var servo_center := Vector3(0, -0.020, float(e.firewall_z) + 0.035)
	var servo_pivot := servo_center + Vector3(0.012, 0.004, 0.010)
	var normal := Vector3.DOWN
	var u := Vector3.RIGHT
	var v := Vector3.BACK
	_add_servo(service, "throttle_servo", servo_center, Basis.IDENTITY, SERVO_BODY_SIZE, servo_pivot, normal, u, Vector3(0, 0, -0.030), false)
	servos["throttle"] = {"type": "throttle", "shaft_root": servo_pivot, "case_root": servo_center, "animated": false, "reference": "static estimated gas servo; no throttle command in the hinge API"}
	var endpoint := servo_pivot + u * 0.010
	var rod_length := endpoint.distance_to(carburetor_point)
	var rod := _new_rod(linkages, "throttle_pushrod_static", rod_length, 0.0008, STEEL, "steel")
	var start_joint := _new_joint(linkages, "throttle_servo_clevis_static", endpoint, normal)
	var end_joint := _new_joint(linkages, "throttle_carburetor_clevis_estimated", carburetor_point, normal)
	_update_rod({"node": rod, "start_joint": start_joint, "end_joint": end_joint, "target_length_m": rod_length, "current_length_m": rod_length, "length_error_m": 0.0}, endpoint, carburetor_point, normal)
	_add_cable_route(service, "throttle_servo_lead", [servo_center + Vector3(-0.010, 0.002, 0.004), servo_center + Vector3(-0.018, 0.002, -0.010), Vector3(0, -0.018, -0.08)])


static func _add_control_horn(hinge: Node3D, label: String, endpoint_local: Vector3, vertical: bool, normal: Vector3) -> void:
	var horn := Node3D.new()
	horn.name = label
	var washer_axis := Vector3.RIGHT if vertical else Vector3.UP
	var washer_basis := Basis(Quaternion(Vector3.UP, washer_axis))
	var washer := _cylinder_mesh(label + "_brass_washer", 0.007, 0.0014, BRASS, "aluminum", 12)
	var horn_web := _box_mesh(label + "_brass_web", Vector3(0.004, 0.025, 0.008), BRASS, "aluminum")
	var screw := _cylinder_mesh(label + "_washer_screw", 0.0015, 0.002, STEEL, "steel", 8)
	var hole := _cylinder_mesh(label + "_clevis_pin", 0.0017, 0.006, STEEL, "steel", 8)
	if vertical:
		# Side-mounted rudder horn: circular base washer and a brass web projecting outboard.
		var base_position := Vector3(0.003, endpoint_local.y, endpoint_local.z - 0.004)
		var web_start_x := base_position.x + 0.004
		var web_length := endpoint_local.x - web_start_x
		washer.transform = Transform3D(washer_basis, base_position)
		screw.transform = Transform3D(washer_basis, base_position + washer_axis * 0.0014)
		horn_web.mesh.size = Vector3(maxf(0.008, web_length), 0.004, 0.008)
		horn_web.transform = Transform3D(Basis.IDENTITY, Vector3((web_start_x + endpoint_local.x) * 0.5, endpoint_local.y, endpoint_local.z))
		hole.transform = Transform3D(washer_basis, endpoint_local)
	else:
		# Aileron/elevator horns sit on the lower skin and hang into the linkage plane.
		var base_position := Vector3(endpoint_local.x, -0.001, endpoint_local.z - 0.003)
		var web_length := absf(endpoint_local.y - base_position.y)
		washer.transform = Transform3D(washer_basis, base_position)
		screw.transform = Transform3D(washer_basis, base_position - washer_axis * 0.0014)
		horn_web.mesh.size = Vector3(0.004, maxf(0.008, web_length), 0.008)
		horn_web.transform = Transform3D(Basis.IDENTITY, Vector3(endpoint_local.x, (base_position.y + endpoint_local.y) * 0.5, endpoint_local.z))
		hole.transform = Transform3D(washer_basis, endpoint_local)
	horn.add_child(washer)
	horn.add_child(horn_web)
	horn.add_child(screw)
	horn.add_child(hole)
	_batch_static_meshes(horn, label + "_hardware")
	hinge.add_child(horn)
	# Keep the moving tip point in the surface's own coordinates for exact pose updates.
	horn.set_meta("endpoint_local", endpoint_local)


static func _add_bellcrank_support(parent: Node3D, label: String, pivot: Vector3, normal: Vector3, basis: Basis, arm_radius: float) -> void:
	var orient := Basis(Quaternion(Vector3.UP, normal))
	var foot := _box_mesh(label + "_mount", Vector3(0.020, 0.003, 0.020), WOOD, "wood")
	foot.transform = Transform3D(basis, pivot - basis.y * 0.009)
	parent.add_child(foot)
	var standoff := _cylinder_mesh(label + "_standoff", 0.0025, 0.014, STEEL, "steel", 8)
	standoff.transform = Transform3D(orient, pivot - normal * 0.002)
	parent.add_child(standoff)
	var washer := _cylinder_mesh(label + "_washer", 0.004, 0.002, STEEL, "steel", 10)
	washer.transform = Transform3D(orient, pivot)
	parent.add_child(washer)
	var hub := _cylinder_mesh(label + "_hub", 0.0035, 0.004, PLASTIC, "plastic", 10)
	hub.transform = Transform3D(orient, pivot + normal * 0.002)
	parent.add_child(hub)


static func _add_servo(parent: Node3D, label: String, center: Vector3, body_basis: Basis, body_size: Vector3, shaft: Vector3, axis: Vector3, arm_u: Vector3, cable_hint: Vector3, wing_mount: bool) -> void:
	var body := _box_mesh(label + "_case", body_size, PLASTIC, "plastic")
	body.transform = Transform3D(body_basis, center)
	parent.add_child(body)
	var lid := _box_mesh(label + "_lid", Vector3(body_size.x * 0.70, 0.0015, body_size.z * 0.70), DARK_PLASTIC, "plastic")
	lid.transform = Transform3D(body_basis, center + body_basis.y * (body_size.y * 0.51))
	parent.add_child(lid)
	var ear_axis := body_basis.y.normalized()
	var grommet_basis := Basis(Quaternion(Vector3.UP, ear_axis))
	var ear_span := body_basis.x.normalized()
	for sign in [-1.0, 1.0]:
		var ear_center: Vector3 = center + ear_span * sign * (body_size.x * 0.58) - ear_axis * 0.002
		var ear := _box_mesh(label + "_ear_" + ("a" if sign < 0 else "b"), Vector3(body_size.x * 0.24, 0.004, body_size.z * 0.80), PLASTIC, "plastic")
		ear.transform = Transform3D(body_basis, ear_center)
		parent.add_child(ear)
		var grommet := _cylinder_mesh(label + "_grommet_" + ("a" if sign < 0 else "b"), 0.003, 0.003, Color("1b1d20"), "rubber", 8)
		grommet.transform = Transform3D(grommet_basis, ear_center - ear_axis * 0.001)
		parent.add_child(grommet)
		var eyelet := _cylinder_mesh(label + "_eyelet_" + ("a" if sign < 0 else "b"), 0.0018, 0.0034, STEEL, "aluminum", 8)
		eyelet.transform = Transform3D(grommet_basis, ear_center - ear_axis * 0.0005)
		parent.add_child(eyelet)
		var screw := _cylinder_mesh(label + "_mount_screw_" + ("a" if sign < 0 else "b"), 0.0017, 0.002, STEEL, "steel", 8)
		screw.transform = Transform3D(grommet_basis, ear_center + ear_axis * 0.0015)
		parent.add_child(screw)
		if wing_mount:
			var rail := _box_mesh(label + "_rail_" + ("a" if sign < 0 else "b"), Vector3(0.056, 0.004, 0.006), WOOD, "wood")
			rail.transform = Transform3D(body_basis, center - body_basis.y * 0.006 + body_basis.z * sign * 0.010)
			parent.add_child(rail)
	var shaft_basis := Basis(Quaternion(Vector3.UP, axis.normalized()))
	var collar := _cylinder_mesh(label + "_output_collar", 0.0046, 0.005, STEEL, "aluminum", 10)
	collar.transform = Transform3D(shaft_basis, shaft)
	parent.add_child(collar)
	var cable_anchor := center + body_basis * cable_hint
	var cable_dir := cable_anchor.direction_to(center + body_basis * (cable_hint + Vector3(0.004, 0, 0)))
	var cable_end := center + body_basis * (cable_hint + Vector3(0.016, -0.001, 0))
	_add_cable_route(parent, label + "_lead", [cable_anchor, cable_anchor + cable_dir * 0.008, cable_end])


static func _new_arm(parent: Node3D, name: String, pivot: Vector3, u: Vector3, v: Vector3, normal: Vector3, angle: float, radius: float, thickness: float) -> MeshInstance3D:
	var beam := _box_mesh(name, Vector3(thickness, radius, thickness), PLASTIC, "plastic")
	beam.set_meta("controls_dynamic", true)
	_update_arm(beam, pivot, pivot + u.rotated(normal, angle) * radius, u, v, normal, angle)
	parent.add_child(beam)
	return beam


static func _update_arm(arm: Node3D, pivot: Vector3, endpoint: Vector3, u: Vector3, v: Vector3, normal: Vector3, angle: float) -> void:
	var direction := (endpoint - pivot).normalized()
	var orientation := Basis(Quaternion(Vector3.UP, direction))
	var midpoint := (pivot + endpoint) * 0.5
	arm.transform = Transform3D(orientation, midpoint)


static func _new_rod(parent: Node3D, name: String, length: float, radius: float, color: Color, profile: String) -> MeshInstance3D:
	var node := _cylinder_mesh(name, radius, length, color, profile, 8)
	node.set_meta("controls_dynamic", true)
	# Two subtle raised bands at each end stand in for threaded adjustment sections.
	for end_sign in [-1.0, 1.0]:
		for index in range(2):
			var band := _cylinder_mesh(name + ("_thread_%s_%d" % ["a" if end_sign < 0 else "b", index]), radius * 1.36, 0.0010, THREAD_DARK, "steel", 8)
			band.position.y = end_sign * (length * 0.5 - 0.004 - float(index) * 0.002)
			node.add_child(band)
	_batch_static_meshes(node, name + "_hardware")
	parent.add_child(node)
	return node


static func _new_joint(parent: Node3D, name: String, position: Vector3, normal: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = name
	# Fork ears leave a gap for the control horn; the cross pin follows the
	# linkage-plane normal while the clevis yoke follows the rod direction.
	var ear_a := _box_mesh(name + "_metal_ear_a", Vector3(0.006, 0.0015, 0.008), STEEL, "steel")
	ear_a.position = Vector3(0, -0.0022, 0.0005)
	var ear_b := _box_mesh(name + "_metal_ear_b", Vector3(0.006, 0.0015, 0.008), STEEL, "steel")
	ear_b.position = Vector3(0, 0.0022, 0.0005)
	var sleeve := _cylinder_mesh(name + "_threaded_socket", 0.0018, 0.006, STEEL, "steel", 8)
	sleeve.transform = Transform3D(Basis(Quaternion(Vector3.UP, Vector3.BACK)), Vector3(0, 0, -0.005))
	var pin := _cylinder_mesh(name + "_transverse_pin", 0.00125, 0.0062, STEEL, "steel", 8)
	pin.position = Vector3(0, 0, 0.0005)
	var pin_head_a := _cylinder_mesh(name + "_pin_head_a", 0.00155, 0.0007, THREAD_DARK, "aluminum", 8)
	pin_head_a.position = Vector3(0, -0.0034, 0.0005)
	var pin_head_b := _cylinder_mesh(name + "_pin_head_b", 0.00155, 0.0007, THREAD_DARK, "aluminum", 8)
	pin_head_b.position = Vector3(0, 0.0034, 0.0005)
	node.add_child(ear_a)
	node.add_child(ear_b)
	node.add_child(sleeve)
	node.add_child(pin)
	node.add_child(pin_head_a)
	node.add_child(pin_head_b)
	node.set_meta("controls_dynamic", true)
	_batch_static_meshes(node, name + "_hardware")
	parent.add_child(node)
	node.position = position
	node.basis = _joint_basis(normal, Vector3.FORWARD)
	return node


static func _update_rod(rod: Dictionary, a: Vector3, b: Vector3, normal: Vector3) -> void:
	var node: Node3D = rod.node
	var delta := b - a
	var actual_length := delta.length()
	if actual_length > SOLVER_EPSILON:
		node.transform = Transform3D(Basis(Quaternion(Vector3.UP, delta / actual_length)), (a + b) * 0.5)
	rod.start_joint.position = a
	rod.end_joint.position = b
	var direction := delta / actual_length if actual_length > SOLVER_EPSILON else Vector3.BACK
	rod.start_joint.basis = _joint_basis(normal, direction)
	rod.end_joint.basis = _joint_basis(normal, direction)
	rod.current_length_m = actual_length
	rod.length_error_m = absf(actual_length - float(rod.target_length_m))


static func _update_beam(beam: Node3D, a: Vector3, b: Vector3, normal: Vector3) -> void:
	var delta := b - a
	var length := delta.length()
	if length <= SOLVER_EPSILON:
		return
	beam.transform = Transform3D(Basis(Quaternion(Vector3.UP, delta / length)), (a + b) * 0.5)


static func _beam_transform(pivot: Vector3, endpoint: Vector3, normal: Vector3) -> Transform3D:
	var delta := endpoint - pivot
	var length := delta.length()
	if length <= SOLVER_EPSILON:
		return Transform3D(Basis.IDENTITY, pivot)
	return Transform3D(Basis(Quaternion(Vector3.UP, delta / length)), (pivot + endpoint) * 0.5)


static func _joint_basis(normal: Vector3, direction: Vector3) -> Basis:
	var pin_axis := normal.normalized()
	var rod_axis := direction - pin_axis * direction.dot(pin_axis)
	if rod_axis.length_squared() <= SOLVER_EPSILON:
		rod_axis = Vector3.FORWARD - pin_axis * Vector3.FORWARD.dot(pin_axis)
	if rod_axis.length_squared() <= SOLVER_EPSILON:
		rod_axis = Vector3.RIGHT - pin_axis * Vector3.RIGHT.dot(pin_axis)
	rod_axis = rod_axis.normalized()
	var width_axis := pin_axis.cross(rod_axis).normalized()
	return Basis(width_axis, pin_axis, rod_axis).orthonormalized()


static func _add_tail_guide(root: Node3D, linkages: Node3D, surface_name: String, servo_end: Vector3, horn_end: Vector3, normal: Vector3) -> void:
	# The long rod runs inside the fuselage for most of its length. A short
	# side-exit sleeve and fibre-pattern plate make its exposed terminal route legible.
	var guide_start := servo_end.lerp(horn_end, 0.78)
	var guide_finish := servo_end.lerp(horn_end, 0.965)
	var delta := guide_finish - guide_start
	var length := delta.length()
	if length <= SOLVER_EPSILON:
		return
	var plate_basis := Basis(Quaternion(Vector3.UP, normal.normalized()))
	var plate := _box_mesh(surface_name + "_fibre_exit_plate", Vector3(0.020, 0.0022, 0.016), FIBER_PLATE, "plastic")
	plate.transform = Transform3D(plate_basis, guide_start)
	linkages.add_child(plate)
	for x_sign in [-1.0, 1.0]:
		for z_sign in [-1.0, 1.0]:
			var offset := Vector3(x_sign * 0.007, 0.0014, z_sign * 0.005)
			var screw := _cylinder_mesh(surface_name + "_exit_plate_screw", 0.0011, 0.0015, STEEL, "steel", 8)
			screw.transform = Transform3D(plate_basis, guide_start + plate_basis * offset)
			linkages.add_child(screw)
	var guide := _cylinder_mesh(surface_name + "_pushrod_exit_tube", 0.0022, length, FIBER_PLATE, "plastic", 10)
	guide.transform = Transform3D(Basis(Quaternion(Vector3.UP, delta / length)), (guide_start + guide_finish) * 0.5)
	linkages.add_child(guide)


static func _batch_static_meshes(parent: Node3D, label: String) -> void:
	# Fold fixed hardware into one mesh per material while preserving the moving
	# arms, links and joint assemblies as independent transforms.
	var groups: Dictionary = {}
	for child in parent.get_children():
		if not (child is MeshInstance3D) or child.get_meta("controls_dynamic", false):
			continue
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null or mesh_instance.mesh.get_surface_count() == 0:
			continue
		var material: Material = mesh_instance.material_override
		if material == null:
			material = mesh_instance.mesh.surface_get_material(0)
		if material == null:
			continue
		var key := material.get_instance_id()
		if not groups.has(key):
			groups[key] = {"material": material, "nodes": []}
		groups[key].nodes.append(mesh_instance)
	var batch_index := 0
	for key in groups:
		var group: Dictionary = groups[key]
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tool.set_material(group.material)
		for mesh_instance in group.nodes:
			tool.append_from(mesh_instance.mesh, 0, mesh_instance.transform)
		var combined := tool.commit()
		if combined == null or combined.get_surface_count() == 0:
			continue
		var batch := MeshInstance3D.new()
		batch.name = label + "_material_%02d" % batch_index
		batch.mesh = combined
		batch.material_override = group.material
		parent.add_child(batch)
		for mesh_instance in group.nodes:
			mesh_instance.free()
		batch_index += 1


static func _solve_crank(pivot: Vector3, radius: float, target: Vector3, rod_length: float, u: Vector3, v: Vector3, normal: Vector3, previous_angle: float) -> Dictionary:
	var candidates := _circle_intersections(pivot, radius, target, rod_length, u, v, normal)
	if candidates.is_empty():
		return {"ok": false, "angle": previous_angle, "point": pivot}
	var selected: Dictionary = candidates[0]
	var best_delta := INF
	for candidate in candidates:
		var delta := absf(wrapf(float(candidate.angle) - previous_angle, -PI, PI))
		if delta < best_delta:
			selected = candidate
			best_delta = delta
	return {"ok": true, "angle": selected.angle, "point": selected.point}


static func _circle_intersections(c1: Vector3, r1: float, c2: Vector3, r2: float, u: Vector3, v: Vector3, normal: Vector3) -> Array[Dictionary]:
	var n := normal.normalized()
	var axis_u := u.normalized()
	var axis_v := v.normalized()
	var delta := c2 - c1
	var dx := delta.dot(axis_u)
	var dz := delta.dot(axis_v)
	var height := delta.dot(n)
	if absf(height) > r2 + SOLVER_EPSILON:
		return []
	var planar_radius_sq := r2 * r2 - height * height
	if planar_radius_sq < -SOLVER_EPSILON:
		return []
	var planar_radius := sqrt(maxf(0.0, planar_radius_sq))
	var distance := sqrt(dx * dx + dz * dz)
	if distance <= SOLVER_EPSILON or distance > r1 + planar_radius + SOLVER_EPSILON or distance < absf(r1 - planar_radius) - SOLVER_EPSILON:
		return []
	var along := (r1 * r1 - planar_radius * planar_radius + distance * distance) / (2.0 * distance)
	var height_sq := r1 * r1 - along * along
	if height_sq < -SOLVER_EPSILON:
		return []
	var side := sqrt(maxf(0.0, height_sq))
	var toward := (axis_u * dx + axis_v * dz) / distance
	var across := n.cross(toward).normalized()
	var base := c1 + toward * along
	var offsets: Array[float] = [-side, side]
	var candidates: Array[Dictionary] = []
	for offset in offsets:
		var point := base + across * offset
		var from_center := point - c1
		candidates.append({"point": point, "angle": atan2(from_center.dot(axis_v), from_center.dot(axis_u))})
	return candidates


static func _point_in_root(root: Node3D, node: Node3D, point: Vector3) -> Vector3:
	var result := point
	var cursor: Node = node
	while cursor != null and cursor != root:
		if cursor is Node3D:
			result = (cursor as Node3D).transform * result
		cursor = cursor.get_parent()
	return result


static func _basis_in_root(root: Node3D, node: Node3D) -> Basis:
	var result := Basis.IDENTITY
	var cursor: Node = node
	while cursor != null and cursor != root:
		if cursor is Node3D:
			result = (cursor as Node3D).transform.basis * result
		cursor = cursor.get_parent()
	return result


static func _box_mesh(name: String, size: Vector3, color: Color, profile: String) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = Finish.material(color, profile)
	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = mesh
	return instance


static func _cylinder_mesh(name: String, radius: float, length: float, color: Color, profile: String, segments: int = 12) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = segments
	mesh.rings = 1
	mesh.material = Finish.material(color, profile)
	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = mesh
	return instance


static func _add_box(parent: Node3D, name: String, size: Vector3, position: Vector3, basis: Basis, color: Color, profile: String) -> MeshInstance3D:
	var instance := _box_mesh(name, size, color, profile)
	instance.transform = Transform3D(basis, position)
	parent.add_child(instance)
	return instance


static func _add_cable_route(parent: Node3D, name: String, points: Array[Vector3]) -> void:
	for index in range(points.size() - 1):
		var start: Vector3 = points[index]
		var finish: Vector3 = points[index + 1]
		var length := start.distance_to(finish)
		if length <= SOLVER_EPSILON:
			continue
		var cable := _cylinder_mesh(name + "_%d" % index, 0.00065, length, DARK_PLASTIC, "rubber", 6)
		cable.transform = Transform3D(Basis(Quaternion(Vector3.UP, (finish - start) / length)), (start + finish) * 0.5)
		parent.add_child(cable)


static func _rollup_errors(mechanisms: Dictionary, failures: Array[String]) -> Dictionary:
	var max_closure := 0.0
	var max_length := 0.0
	for mechanism_name in mechanisms:
		var mechanism: Dictionary = mechanisms[mechanism_name]
		max_closure = maxf(max_closure, float(mechanism.get("closure_error_m", INF)))
		for rod in mechanism.rods:
			max_length = maxf(max_length, float(rod.get("length_error_m", INF)))
	return {"max_closure_error_m": max_closure, "max_length_error_m": max_length, "solve_failures": failures.duplicate()}

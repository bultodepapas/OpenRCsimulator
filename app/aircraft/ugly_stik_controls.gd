# Jensen-style visual control linkages for the Ugly Stik 60.
# Geometry is estimated where the plan does not give a dimension; the simulation
# remains the source of each hinge pose and this file does not affect flight.
extends RefCounted

const Geometry := preload("res://aircraft/ugly_stik_geometry.gd")
const Finish := preload("res://aircraft/ugly_stik_finish.gd")
const Equipment := preload("res://aircraft/ugly_stik_equipment.gd")
const Installation := preload("res://aircraft/ugly_stik_installation.gd")
const D: Dictionary = Geometry.DATA

const PLASTIC := Color("24272b")
const DARK_PLASTIC := Color("15181b")
const STEEL := Color("9ca3a8")
const THREAD_DARK := Color("565b60")
const BRASS := Color("b88736")
const FIBER_PLATE := Color("686a65")
const WOOD := Color("b58a58")
const NYLON := Color("e6e2d6")
const RUBBER := Color("1b1d20")
const SERVO_LABEL := Color("3b4048")
# US-V17: a generic standard-class servo, the common 40 x 20 x 36 mm case with 54 mm mounting tabs (no make or model is
# claimed). Servo frame: X along the case toward the output end, Y up the output shaft, Z across the case.
const SERVO_CASE_M := Vector3(0.0405, 0.036, 0.020) # length x height to the top cover x width
const SERVO_TAB_Y_M := 0.0265 # tab underside above the case bottom; the tabs are 2.5 mm thick
const SERVO_TAB_SPAN_M := 0.0545 # tab tip to tab tip
const SERVO_SHAFT_X_M := 0.010 # output shaft ahead of the case centre
const SERVO_SPLINE_TOP_M := 0.040 # arm seat above the case bottom
const ARM_THICKNESS_M := 0.0025
const ROD_RADIUS_M := 0.00115
# US-V17 (owner: the two-servo version). Jensen sheet 2 draws one central Kraft servo driving both W3 bellcranks; the
# two-servo variant gives each aileron its own servo, so neither needs a bellcrank. The servo lies on its side on blocks
# glued to a bottom hatch, its arm out through a slot, with a short pushrod to the plan's nylon horn, hole under the
# hinge line. Stations are estimates: the servo sits aft of the spar where the wing is still deep enough for the case.
const AILERON_HORN_INSET_M := 0.012 # horn plane outboard of the aileron's inner end
const AILERON_HORN_HOLE_M := Vector2(0.002, -0.0225) # (aft of, below) the hinge line: a 7/8 in horn
const AILERON_HORN_BASE_AFT_M := 0.010
const AILERON_SERVO_SHAFT_Z_M := 0.150 # aft of the leading edge (chord fraction 0.49)
const AILERON_ARM_RADIUS_M := 0.0225 # equal to the horn: a parallelogram, aileron throw follows the servo
const HATCH_M := Vector3(0.050, 0.0016, 0.064) # span x 1/16 in plywood x chord, film covered
const HATCH_PROUD_M := 0.0003
const HATCH_CLEARANCE_M := 0.0008 # servo case above the hatch's inner face
const FUSELAGE_SIDE_M := 0.00635 # Jensen sheet 1: 1/4 in balsa sides (servo rails are glued to their inner faces)
const FUSELAGE_BOTTOM_M := 0.0024 # and a 3/32 in bottom
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
	_build_throttle_mechanism(root, service, linkages, mechanisms, servos, failures)
	_add_servo_tray(service)
	var installation := Installation.build(root, service, linkages, servos)
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
		"installation": installation,
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
				_update_arm(mechanism.servo_arm, mechanism.servo_pivot, servo_solution.point, mechanism.servo_axis)
				endpoints["servo"] = servo_solution.point
				endpoints["horn"] = target
				_update_rod(rods[0], servo_solution.point, target, normal)
				mechanism.closure_error_m = rods[0].length_error_m
		elif mechanism.kind == "cable":
			var cables: Array = mechanism.cables
			var front_exposed: float = target.distance_to(cables[0].tube_point)
			var rear_exposed: float = float(mechanism.cable_total_m) - front_exposed
			var servo_solution := _solve_crank(
				mechanism.servo_pivot, mechanism.servo_radius_m, cables[1].tube_point, rear_exposed,
				u, v, normal, mechanism.last_servo_angle
			)
			if not servo_solution.ok:
				solved = false
				failures.append("%s cable has no servo closure" % mechanism_name)
			else:
				mechanism.last_servo_angle = servo_solution.angle
				_update_arm(mechanism.servo_arm, mechanism.servo_pivot, servo_solution.point, mechanism.servo_axis)
				_update_cable(cables[0], target)
				_update_cable(cables[1], servo_solution.point)
				endpoints["servo"] = servo_solution.point
				endpoints["horn"] = target
				endpoints["cable_front"] = cables[0].tube_point
				endpoints["cable_rear"] = cables[1].tube_point
				mechanism.closure_error_m = absf(float(cables[0].exposed_m) + float(cables[1].exposed_m) - float(mechanism.cable_total_m))
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
	var chord := float(wing.chord)
	var frame_basis := _basis_in_root(root, frame).orthonormalized()
	var outward: Vector3 = frame_basis.x * sign
	var down: Vector3 = -frame_basis.y
	var aft: Vector3 = frame_basis.z
	var normal := down.cross(aft).normalized()

	# The horn shares the arm's chordwise plane; its base sits on the aileron's lower face, its hole under the hinge line.
	var plane_x := sign * (float(wing.aileron_inner) + float(wing.inboard_gap) + AILERON_HORN_INSET_M)
	var horn_local := Vector3(plane_x - hinge.position.x, AILERON_HORN_HOLE_M.y, AILERON_HORN_HOLE_M.x)
	var base_z := AILERON_HORN_BASE_AFT_M
	var face_rise := (_aileron_lower_y(base_z + 0.001) - _aileron_lower_y(base_z)) / 0.001
	var horn_base := Vector3(horn_local.x, _aileron_lower_y(base_z), base_z)
	_add_control_horn(hinge, surface_name + "_control_horn", horn_local, horn_base, Vector3(0, face_rise, 1), NYLON, "plastic")
	var horn_root := _point_in_root(root, hinge, horn_local)

	# The hatch is a flat plate parallel to the lower skin's secant over its chord, offset past the skin's sag so it
	# stands just proud of the film everywhere. Frame coordinates.
	var hatch_z := AILERON_SERVO_SHAFT_Z_M - SERVO_SHAFT_X_M
	var z0 := hatch_z - HATCH_M.z * 0.5
	var z1 := hatch_z + HATCH_M.z * 0.5
	var y0 := _wing_surface_y(z0 / chord, false)
	var y1 := _wing_surface_y(z1 / chord, false)
	var sag := 0.0
	for i in range(17):
		var t := float(i) / 16.0
		sag = maxf(sag, lerpf(y0, y1, t) - _wing_surface_y(lerpf(z0, z1, t) / chord, false))
	var slope := (y1 - y0) / (z1 - z0)
	var hatch_aft := Vector3(0, slope, 1).normalized()
	var hatch_up := Vector3(0, 1, -slope).normalized()
	var hatch_basis := Basis(Vector3.RIGHT, hatch_up, hatch_aft)
	var outer_y := func(z: float) -> float: return y0 + slope * (z - z0) - sag - HATCH_PROUD_M
	var hatch_x := plane_x - sign * (HATCH_M.x * 0.5 - 0.006)
	var hatch := Node3D.new()
	hatch.name = surface_name + "_servo_hatch"
	var slot := _box_mesh(surface_name + "_hatch_slot", Vector3(0.006, 0.0002, 0.026), Color("0b0c0e"), "plastic")
	slot.transform = Transform3D(hatch_basis, Vector3(plane_x, outer_y.call(AILERON_SERVO_SHAFT_Z_M), AILERON_SERVO_SHAFT_Z_M) - hatch_up * 0.0001)
	hatch.add_child(slot)
	for corner_x in [-1.0, 1.0]:
		for corner_z in [-1.0, 1.0]:
			var z: float = hatch_z + corner_z * (HATCH_M.z * 0.5 - 0.0045)
			var screw := _cylinder_mesh(surface_name + "_hatch_screw", 0.0011, 0.0006, STEEL, "steel", 8)
			screw.transform = Transform3D(hatch_basis, Vector3(hatch_x + corner_x * (HATCH_M.x * 0.5 - 0.0045), outer_y.call(z), z) - hatch_up * 0.0003)
			hatch.add_child(screw)
	_batch_static_meshes(hatch, surface_name + "_hatch")
	# US-V18a: the plate is covered in the wing film (atlas and Workshop paint slot "wing"), not a fixed red.
	var plate_centre: Vector3 = Vector3(hatch_x, outer_y.call(hatch_z), hatch_z) + hatch_up * (HATCH_M.y * 0.5)
	hatch.add_child(_film_box(surface_name + "_hatch_plate", HATCH_M, Transform3D(hatch_basis, plate_centre), "wing"))
	frame.add_child(hatch)

	# The servo lies on its side on the hatch, output shaft outboard in the horn's plane, case parallel to the hatch.
	var shaft_z := AILERON_SERVO_SHAFT_Z_M
	var servo_frame := Vector3(plane_x, outer_y.call(shaft_z), shaft_z) + hatch_up * (HATCH_M.y + HATCH_CLEARANCE_M + SERVO_CASE_M.z * 0.5)
	var servo_pivot := _point_in_root(root, frame, servo_frame)
	var up_root: Vector3 = frame_basis * hatch_up
	var servo := _add_servo(service, "aileron_servo_" + side, servo_pivot, outward, frame_basis * hatch_aft)
	var lead_exit := _point_in_root(root, frame, Vector3(sign * 0.040, servo_frame.y, hatch_z - 0.035))
	servos["aileron_" + side] = {"type": "aileron", "side": side, "shaft_root": servo_pivot, "case_root": servo.centre, "case_basis": servo.basis,
		"lead": lead_exit, "lead_dir": Vector3.DOWN,
		"reference": "US-V17 two-servo variant: one servo per semispan on a bottom hatch (Jensen sheet 2 draws one central servo)"}
	# Hardwood blocks glued to the hatch take the tab screws, from the hatch up to the top of each tab.
	var block_low := -(HATCH_CLEARANCE_M + SERVO_CASE_M.z * 0.5)
	var block_high := 0.009
	for tab: Vector3 in servo.tabs:
		var block := _box_mesh("aileron_servo_%s_block" % side, Vector3(0.007, 0.010, block_high - block_low), WOOD, "wood")
		block.transform = Transform3D(servo.basis, tab - servo.basis.y * 0.00625 + up_root * ((block_low + block_high) * 0.5))
		service.add_child(block)
	_add_cable_route(service, surface_name + "_servo_lead", [servo.lead, servo.lead - frame_basis * hatch_aft * 0.010, lead_exit])

	var neutral_endpoint := servo_pivot + down * AILERON_ARM_RADIUS_M
	var rod_length := neutral_endpoint.distance_to(horn_root)
	var arm := _new_arm(linkages, surface_name + "_servo_arm", servo_pivot, neutral_endpoint, outward, AILERON_ARM_RADIUS_M)
	var rod := _new_rod(linkages, surface_name + "_pushrod", rod_length, ROD_RADIUS_M, STEEL, "steel")
	var start_joint := _new_joint(linkages, surface_name + "_servo_clevis", neutral_endpoint, normal)
	var end_joint := _new_joint(linkages, surface_name + "_horn_clevis", horn_root, normal)
	mechanisms[surface_name] = {
		"kind": "direct",
		"surface": surface_name,
		"hinge": hinge,
		"horn_local": horn_local,
		"plane_u": down,
		"plane_v": aft,
		"plane_normal": normal,
		"servo_pivot": servo_pivot,
		"servo_axis": outward,
		"servo_radius_m": AILERON_ARM_RADIUS_M,
		"last_servo_angle": 0.0,
		"servo_arm": arm,
		"rods": [
			{"name": surface_name + "_pushrod", "node": rod, "start_joint": start_joint, "end_joint": end_joint, "target_length_m": rod_length, "current_length_m": rod_length, "length_error_m": 0.0},
		],
		"solved": true,
		"closure_error_m": 0.0,
		"estimated_geometry": true,
	}
	_update_rod(mechanisms[surface_name].rods[0], neutral_endpoint, horn_root, normal)


static func _build_tail_mechanism(root: Node3D, assembly: Node3D, service: Node3D, linkages: Node3D, hinges: Dictionary, surface_name: String, mechanisms: Dictionary, servos: Dictionary, failures: Array[String]) -> void:
	var hinge: Node3D = hinges[surface_name]
	var is_elevator := surface_name == "elevator"
	# US-V18b: the elevator and rudder servos stand in the plan's tray (equipment.servo_tray), output aft. Their arms point
	# toward the centre line, so the pushrods start near the middle and diverge to horns on either side of the tail.
	var u := Vector3.RIGHT if is_elevator else Vector3.LEFT
	var v := Vector3.BACK
	var normal := u.cross(v)
	# The tail control surfaces extend aft (negative local z) from the hinge.
	var horn_local := Vector3(-0.046, -0.024, -0.030) if is_elevator else Vector3(0.027, 0.006, -0.018)
	# Brass horns after the owner's photo C: the elevator horn hangs below its surface, the rudder horn stands off its side.
	var horn_base := Vector3(horn_local.x, -0.001, horn_local.z - 0.003) if is_elevator else Vector3(0.003, horn_local.y, horn_local.z - 0.004)
	_add_control_horn(hinge, surface_name + "_control_horn", horn_local, horn_base, Vector3.BACK, BRASS, "aluminum")
	var horn_root := _point_in_root(root, hinge, horn_local)
	var horn_pin := Vector3.RIGHT if is_elevator else Vector3.UP
	var servo_pivot := _tray_shaft(surface_name, Vector3.BACK)
	var servo_radius := 0.016
	var neutral_endpoint := servo_pivot + u * servo_radius
	var rod_length := neutral_endpoint.distance_to(horn_root)
	if rod_length <= 0.1:
		failures.append("%s estimated pushrod is too short" % surface_name)
		return
	var servo := _add_servo(service, surface_name + "_servo", servo_pivot, Vector3.UP, Vector3.BACK)
	servos[surface_name] = {"type": surface_name, "shaft_root": servo_pivot, "case_root": servo.centre, "case_basis": servo.basis,
		"lead": servo.lead, "lead_dir": -(servo.basis as Basis).x, "reference": "Jensen sheet 1 servo tray between F3 and F4 (plan picks); order estimated"}
	var rod := _new_rod(linkages, surface_name + "_long_pushrod", rod_length, ROD_RADIUS_M, STEEL, "steel")
	var start_joint := _new_joint(linkages, surface_name + "_servo_clevis", neutral_endpoint, normal)
	var end_joint := _new_joint(linkages, surface_name + "_horn_clevis", horn_root, horn_pin)
	var arm := _new_arm(service, surface_name + "_servo_arm", servo_pivot, neutral_endpoint, Vector3.UP, servo_radius)
	_add_tail_guide(root, linkages, surface_name, neutral_endpoint, horn_root, horn_pin)
	mechanisms[surface_name] = {
		"kind": "direct",
		"surface": surface_name,
		"hinge": hinge,
		"horn_local": horn_local,
		"plane_u": u,
		"plane_v": v,
		"plane_normal": normal,
		"servo_pivot": servo_pivot,
		"servo_axis": Vector3.UP,
		"servo_radius_m": servo_radius,
		"last_servo_angle": 0.0,
		"servo_arm": arm,
		"rods": [
			{"name": surface_name + "_long_pushrod", "node": rod, "start_joint": start_joint, "end_joint": end_joint, "end_normal": horn_pin, "target_length_m": rod_length, "current_length_m": rod_length, "length_error_m": 0.0},
		],
		"solved": true,
		"closure_error_m": 0.0,
		"estimated_geometry": true,
	}
	_update_rod(mechanisms[surface_name].rods[0], neutral_endpoint, horn_root, normal)


## Output shaft (arm mid-thickness) of a tray servo whose output end faces `output_dir`: arms on the thrust line.
static func _tray_shaft(servo_name: String, output_dir: Vector3) -> Vector3:
	var e: Dictionary = D.equipment
	var tray: Dictionary = e.servo_tray
	return Vector3(float(tray.servo_x[servo_name]), float(e.shaft_y), float(tray.case_z)) + output_dir * SERVO_SHAFT_X_M


## The plan's two hardwood servo rails across the fuselage, glued to the sides, under the tabs of the tray servos.
static func _add_servo_tray(service: Node3D) -> void:
	var e: Dictionary = D.equipment
	var tray: Dictionary = e.servo_tray
	var rail: Array = tray.rail
	var top := float(e.shaft_y) - SERVO_SPLINE_TOP_M - ARM_THICKNESS_M * 0.5 + SERVO_TAB_Y_M
	var tab_x := (SERVO_TAB_SPAN_M + SERVO_CASE_M.x) * 0.25
	for end in [-1.0, 1.0]:
		var z: float = float(tray.case_z) + end * tab_x
		var half := _fuselage_inner_half_width(z)
		_add_box(service, "servo_tray_rail", Vector3(half * 2.0, float(rail[1]), float(rail[0])), Vector3(0, top - float(rail[1]) * 0.5, z), Basis.IDENTITY, WOOD, "wood")


# US-V09c: the carburettor lever (Equipment, node carburetor_throttle_arm_hinge) turns about X with the throttle
# command. US-V13: the O.S. 61 lever opens by turning about -X (Equipment.THROTTLE_OPENING). US-V18b: the gas servo
# stands in the middle of the plan's tray, output forward, and pushes a cable that slides in a fixed brass tube (Jensen
# sheet 1: "brass brake cable tubing", "nylon tubing ... to throttle"). The tube runs from just ahead of the servo arm
# along the right side, past the tank, and crosses F1 at equipment.servo_tray.throttle_f1. The cable cannot stretch:
# what leaves the front of the tube enters at the back, so the exposed front and rear lengths keep their neutral sum,
# and the servo angle closes that sum. The 60-degree barrel travel and the 9 mm arm hole are estimates.
const THROTTLE_TRAVEL_DEG := 60.0
const THROTTLE_SERVO_RADIUS_M := 0.009 # inner hole: about 70 degrees of servo travel for the barrel
const THROTTLE_TUBE_RADIUS_M := 0.002 # 5/32 in tube
const THROTTLE_CABLE_RADIUS_M := 0.0006
const THROTTLE_TUBE_PROUD_M := 0.003 # tube end ahead of F1's front face
const THROTTLE_REAR_EXPOSED_M := 0.025
const THROTTLE_CABLE_HIDDEN_M := 0.010 # cable kept inside the tube at the extremes

static func _build_throttle_mechanism(root: Node3D, service: Node3D, linkages: Node3D, mechanisms: Dictionary, servos: Dictionary, failures: Array[String]) -> void:
	var hinge := root.find_child("carburetor_throttle_arm_hinge", false, false) as Node3D
	if hinge == null:
		failures.append("missing carburetor throttle arm")
		return
	var e: Dictionary = D.equipment
	var horn_local: Vector3 = Equipment.throttle_arm_tip() - Equipment.throttle_arm_pivot()
	var tip := _point_in_root(root, hinge, horn_local)
	var u := Vector3.RIGHT
	var v := Vector3.BACK
	var normal := u.cross(v)
	var servo_pivot := _tray_shaft("throttle", Vector3.FORWARD)
	var servo := _add_servo(service, "throttle_servo", servo_pivot, Vector3.UP, Vector3.FORWARD)
	servos["throttle"] = {"type": "throttle", "shaft_root": servo_pivot, "case_root": servo.centre, "case_basis": servo.basis, "animated": true,
		"lead": servo.lead, "lead_dir": -(servo.basis as Basis).x, "reference": "Jensen sheet 1 servo tray; drives the carburettor lever through a cable in a tube"}
	var arm_end := servo_pivot + u * THROTTLE_SERVO_RADIUS_M
	var crossing: Array = e.servo_tray.throttle_f1
	var front := Vector3(float(crossing[0]), float(crossing[1]), float(e.firewall_z) - THROTTLE_TUBE_PROUD_M)
	var rear := arm_end + Vector3.FORWARD * THROTTLE_REAR_EXPOSED_M
	var path := _throttle_tube_path(front, (front - tip).normalized(), rear)
	var tube := MeshInstance3D.new()
	tube.name = "throttle_cable_tube"
	tube.mesh = _swept_tube(path, THROTTLE_TUBE_RADIUS_M, 10, BRASS, "aluminum")
	service.add_child(tube)
	# Exposed lengths over the throttle range, from the lever's own rotation.
	var total := tip.distance_to(front) + arm_end.distance_to(rear)
	var front_max := 0.0
	var front_min := INF
	for index in range(21):
		hinge.rotation.x = deg_to_rad(Equipment.THROTTLE_OPENING * (float(index) / 20.0 - 0.5) * THROTTLE_TRAVEL_DEG)
		var exposed := _point_in_root(root, hinge, horn_local).distance_to(front)
		front_max = maxf(front_max, exposed)
		front_min = minf(front_min, exposed)
	hinge.rotation.x = 0.0
	var front_cable := _new_rod(linkages, "throttle_cable_front", front_max + THROTTLE_CABLE_HIDDEN_M, THROTTLE_CABLE_RADIUS_M, STEEL, "steel")
	var rear_cable := _new_rod(service, "throttle_cable_rear", total - front_min + THROTTLE_CABLE_HIDDEN_M, THROTTLE_CABLE_RADIUS_M, STEEL, "steel")
	var servo_joint := _new_joint(service, "throttle_servo_clevis", arm_end, normal)
	var lever_joint := _new_joint(linkages, "throttle_carburetor_clevis", tip, Vector3.RIGHT)
	var arm := _new_arm(service, "throttle_servo_arm", servo_pivot, arm_end, Vector3.UP, THROTTLE_SERVO_RADIUS_M)
	mechanisms["throttle"] = {
		"kind": "cable",
		"surface": "throttle",
		"hinge": hinge,
		"horn_local": horn_local,
		"plane_u": u,
		"plane_v": v,
		"plane_normal": normal,
		"servo_pivot": servo_pivot,
		"servo_axis": Vector3.UP,
		"servo_radius_m": THROTTLE_SERVO_RADIUS_M,
		"last_servo_angle": 0.0,
		"servo_arm": arm,
		"rods": [],
		"cables": [
			{"name": "throttle_cable_front", "node": front_cable, "joint": lever_joint, "pin": Vector3.RIGHT, "tube_point": front, "length_m": front_max + THROTTLE_CABLE_HIDDEN_M},
			{"name": "throttle_cable_rear", "node": rear_cable, "joint": servo_joint, "pin": normal, "tube_point": rear, "length_m": total - front_min + THROTTLE_CABLE_HIDDEN_M},
		],
		"cable_total_m": total,
		"tube_path": path,
		"solved": true,
		"closure_error_m": 0.0,
		"estimated_geometry": true,
	}
	_update_cable(mechanisms.throttle.cables[0], tip)
	_update_cable(mechanisms.throttle.cables[1], arm_end)


## Centre line of the throttle cable tube: straight through F1 on the cable's line, along the right side (past the tank),
## then in to a straight run ahead of the servo arm.
static func _throttle_tube_path(front: Vector3, aft_dir: Vector3, rear: Vector3) -> Array[Vector3]:
	var points: Array[Vector3] = [front, front + aft_dir * 0.014]
	var first: Vector3 = points[1]
	for z in [-0.24, -0.17, -0.10]:
		var t := inverse_lerp(first.z, rear.z, z)
		points.append(Vector3(_fuselage_inner_half_width(z) - THROTTLE_TUBE_RADIUS_M - 0.002, lerpf(first.y, rear.y, t), z))
	# Turn in toward the servo early, so the spline does not bulge into the side.
	var approach := rear + Vector3.FORWARD * 0.02
	var turn_t := inverse_lerp(first.z, rear.z, -0.03)
	points.append(Vector3(lerpf(points[points.size() - 1].x, approach.x, 0.35), lerpf(first.y, rear.y, turn_t), -0.03))
	points.append(approach)
	points.append(rear)
	return _catmull_rom(points, 8)


## Uniform Catmull-Rom through `points` (ends extended along the end chords), `steps` samples per segment.
static func _catmull_rom(points: Array[Vector3], steps: int) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var count := points.size()
	for i in range(count - 1):
		var p0: Vector3 = points[i - 1] if i > 0 else points[0] * 2.0 - points[1]
		var p1: Vector3 = points[i]
		var p2: Vector3 = points[i + 1]
		var p3: Vector3 = points[i + 2] if i + 2 < count else points[count - 1] * 2.0 - points[count - 2]
		for step in range(steps):
			var t := float(step) / float(steps)
			result.append(0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t))
	result.append(points[count - 1])
	return result


## Indexed swept tube along `path` in one material (indexed so the static batch keeps it).
static func _swept_tube(path: Array[Vector3], radius: float, sides: int, color: Color, profile: String) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	Equipment._sweep_tube(tool, path, radius, sides)
	tool.index()
	var mesh := tool.commit()
	mesh.surface_set_material(0, Finish.material(color, profile))
	return mesh


## A sliding cable: from its exposed end (at its clevis) toward its tube point, running on into the tube.
static func _update_cable(cable: Dictionary, exposed_end: Vector3) -> void:
	var direction: Vector3 = (cable.tube_point - exposed_end).normalized()
	var node: Node3D = cable.node
	node.transform = Transform3D(Basis(Quaternion(Vector3.UP, direction)), exposed_end + direction * float(cable.length_m) * 0.5)
	var joint: Node3D = cable.joint
	joint.position = exposed_end
	joint.basis = _joint_basis(cable.pin, -direction)
	cable["exposed_m"] = exposed_end.distance_to(cable.tube_point)

## Throttle command 0..1 → carburettor lever angle; the neutral built pose is half throttle. Updates every linkage.
static func set_throttle(controls: Dictionary, throttle: float) -> void:
	if not controls.get("ok", false) or not controls.mechanisms.has("throttle"):
		return
	var hinge: Node3D = controls.mechanisms.throttle.hinge
	hinge.rotation.x = deg_to_rad(Equipment.THROTTLE_OPENING * (clampf(throttle, 0.0, 1.0) - 0.5) * THROTTLE_TRAVEL_DEG)
	update(controls)


## A control horn on a surface, in hinge coordinates: a base plate on the surface at `base`, a tapered web out to the
## clevis hole at `endpoint_local`, two base screws and the clevis pin. `along` lies in the surface and the horn's plane.
static func _add_control_horn(hinge: Node3D, label: String, endpoint_local: Vector3, base: Vector3, along: Vector3, color: Color, profile: String) -> void:
	var a := along.normalized()
	var reach := endpoint_local - base
	var out := (reach - a * reach.dot(a)).normalized()
	var across := a.cross(out).normalized()
	var basis := Basis(a, out, across)
	var tip := Vector2(reach.dot(a), reach.dot(out))
	var outline := PackedVector2Array([Vector2(-0.008, 0.0), Vector2(0.008, 0.0)])
	for step in range(6):
		outline.append(tip + Vector2.from_angle(TAU * float(step) / 6.0) * 0.0028)
	var hull := Geometry2D.convex_hull(outline)
	hull.remove_at(hull.size() - 1)
	var horn := Node3D.new()
	horn.name = label
	var web := MeshInstance3D.new()
	web.name = label + "_web"
	web.mesh = _plate_mesh(hull, 0.0016)
	web.material_override = Finish.material(color, profile)
	web.transform = Transform3D(basis, base)
	horn.add_child(web)
	var foot := _box_mesh(label + "_base", Vector3(0.020, 0.0012, 0.008), color, profile)
	foot.transform = Transform3D(basis, base + out * 0.0006)
	horn.add_child(foot)
	for end in [-1.0, 1.0]:
		var screw := _cylinder_mesh(label + "_base_screw", 0.0013, 0.0008, STEEL, "steel", 8)
		screw.transform = Transform3D(basis, base + a * (end * 0.0085) + out * 0.0016)
		horn.add_child(screw)
	var hole_basis := Basis(out, across, a)
	for fraction in [0.3, 0.55]:
		var hole := _cylinder_mesh(label + "_spare_hole", 0.0007, 0.0019, DARK_PLASTIC, "plastic", 6)
		hole.transform = Transform3D(hole_basis, base + basis * Vector3(tip.x, tip.y, 0.0) * (1.0 - fraction))
		horn.add_child(hole)
	var pin := _cylinder_mesh(label + "_clevis_pin", 0.0017, 0.006, STEEL, "steel", 8)
	pin.transform = Transform3D(hole_basis, endpoint_local)
	horn.add_child(pin)
	_batch_static_meshes(horn, label + "_hardware")
	hinge.add_child(horn)
	# Keep the moving tip point in the surface's own coordinates for exact pose updates.
	horn.set_meta("endpoint_local", endpoint_local)


## Height of the wing's traced upper or lower skin at chord fraction `u`, in the wing frame (metres).
static func _wing_surface_y(u: float, upper: bool) -> float:
	var section: Array = D.wing.section
	var trailing := 0
	for i in section.size():
		if is_equal_approx(float(section[i][0]), 1.0): trailing = i
	for i in (range(0, trailing) if upper else range(trailing, section.size())):
		var a: Array = section[i]
		var b: Array = section[(i + 1) % section.size()]
		if minf(float(a[0]), float(b[0])) <= u and u <= maxf(float(a[0]), float(b[0])) and not is_equal_approx(float(a[0]), float(b[0])):
			return lerpf(float(a[1]), float(b[1]), (u - float(a[0])) / (float(b[0]) - float(a[0]))) * float(D.wing.chord)
	return 0.0


## Height of the aileron's lower face `z` metres aft of its hinge line, in the hinge frame: the moving section is a wedge.
static func _aileron_lower_y(z: float) -> float:
	var wing: Dictionary = D.wing
	var gap := float(wing.hinge_gap) * 0.5
	var length := (1.0 - float(wing.hinge_fraction)) * float(wing.chord)
	return _wing_surface_y(float(wing.hinge_fraction), false) * clampf(1.0 - (z - gap) / (length - gap), 0.0, 1.0)


## Inner half width of the fuselage sides at station `z` (root metres).
static func _fuselage_inner_half_width(z: float) -> float:
	return _fuselage_section(z).x - FUSELAGE_SIDE_M


## Outer fuselage section at station `z`: (half width, top, bottom), interpolated between the traced stations; zero
## size outside them.
static func _fuselage_section(z: float) -> Vector3:
	var stations: Array = D.fuselage_stations
	for i in range(stations.size() - 1):
		var a: Array = stations[i]
		var b: Array = stations[i + 1]
		if float(a[0]) <= z and z <= float(b[0]):
			var t := (z - float(a[0])) / (float(b[0]) - float(a[0]))
			return Vector3(lerpf(float(a[1]), float(b[1]), t), lerpf(float(a[2]), float(b[2]), t), lerpf(float(a[3]), float(b[3]), t))
	return Vector3.ZERO


## A standard servo whose arm turns about `pivot` (mid-thickness of the arm) on a shaft along `axis`, the case reaching
## from the output end back along -`output_dir`. Returns its frame, centre, tab centres and lead exit (parent space).
static func _add_servo(parent: Node3D, label: String, pivot: Vector3, axis: Vector3, output_dir: Vector3) -> Dictionary:
	var y := axis.normalized()
	var x := (output_dir - y * output_dir.dot(y)).normalized()
	var basis := Basis(x, y, x.cross(y).normalized())
	var bottom := pivot - y * (SERVO_SPLINE_TOP_M + ARM_THICKNESS_M * 0.5) - x * SERVO_SHAFT_X_M
	var size := SERVO_CASE_M
	var tab_y := SERVO_TAB_Y_M + 0.00125
	var tab_x := (SERVO_TAB_SPAN_M + size.x) * 0.25
	# Bottom cover, case to the tab flange, flange with tabs, top cover (seams read as slightly inset covers), output
	# boss and spline, side label and lead grommet.
	var parts := [
		[_box_mesh(label + "_bottom_cover", Vector3(size.x - 0.0005, 0.004, size.z - 0.0004), PLASTIC, "plastic"), Vector3(0, 0.002, 0)],
		[_box_mesh(label + "_case", Vector3(size.x, 0.025, size.z), PLASTIC, "plastic"), Vector3(0, 0.0165, 0)],
		[_box_mesh(label + "_tabs", Vector3(SERVO_TAB_SPAN_M, 0.0025, 0.018), PLASTIC, "plastic"), Vector3(0, tab_y, 0)],
		[_box_mesh(label + "_top_cover", Vector3(size.x - 0.0005, size.y - 0.029, size.z - 0.0004), PLASTIC, "plastic"), Vector3(0, (0.029 + size.y) * 0.5, 0)],
		[_cylinder_mesh(label + "_output_boss", 0.0058, 0.0016, PLASTIC, "plastic", 16), Vector3(SERVO_SHAFT_X_M, size.y + 0.0008, 0)],
		[_cylinder_mesh(label + "_spline", 0.0029, SERVO_SPLINE_TOP_M - size.y - 0.0016, DARK_PLASTIC, "plastic", 12), Vector3(SERVO_SHAFT_X_M, (size.y + 0.0016 + SERVO_SPLINE_TOP_M) * 0.5, 0)],
		[_box_mesh(label + "_label", Vector3(0.026, 0.013, 0.0003), SERVO_LABEL, "plastic"), Vector3(-0.003, 0.0165, size.z * 0.5 + 0.00015)],
		[_box_mesh(label + "_lead_grommet", Vector3(0.003, 0.004, 0.007), DARK_PLASTIC, "rubber"), Vector3(-size.x * 0.5 - 0.0015, 0.006, 0)],
	]
	var tabs: Array[Vector3] = []
	for end in [-1.0, 1.0]:
		parts.append([_cylinder_mesh(label + "_grommet", 0.0032, 0.0046, RUBBER, "rubber", 10), Vector3(end * tab_x, tab_y, 0)])
		parts.append([_cylinder_mesh(label + "_eyelet", 0.0016, 0.0052, STEEL, "aluminum", 8), Vector3(end * tab_x, tab_y, 0)])
		parts.append([_cylinder_mesh(label + "_mount_screw", 0.0021, 0.0010, STEEL, "steel", 8), Vector3(end * tab_x, tab_y + 0.0028, 0)])
		tabs.append(bottom + basis * Vector3(end * tab_x, tab_y, 0))
	for part in parts:
		var node: MeshInstance3D = part[0]
		node.transform = Transform3D(basis, bottom + basis * (part[1] as Vector3))
		parent.add_child(node)
	return {"basis": basis, "centre": bottom + basis.y * (size.y * 0.5), "tabs": tabs, "lead": bottom + basis * Vector3(-size.x * 0.5 - 0.003, 0.006, 0)}


## A servo arm turning about `pivot` on a shaft along `axis`: round hub, tapered blade, spare holes and hub screw.
static func _new_arm(parent: Node3D, name: String, pivot: Vector3, endpoint: Vector3, axis: Vector3, radius: float) -> MeshInstance3D:
	var outline := PackedVector2Array([Vector2(-0.004, 0.0), Vector2(0.004, 0.0), Vector2(0.0024, radius), Vector2(0.0012, radius + 0.0021), Vector2(-0.0012, radius + 0.0021), Vector2(-0.0024, radius)])
	var hub_basis := Basis(Vector3.RIGHT, PI * 0.5)
	var parts := [
		[_plate_mesh(outline, ARM_THICKNESS_M), Transform3D.IDENTITY, PLASTIC, "plastic"],
		[_cylinder(0.0045, 0.005, 14), Transform3D(hub_basis, Vector3(0, 0, -0.001)), PLASTIC, "plastic"],
		[_cylinder(0.0017, 0.0006, 8), Transform3D(hub_basis, Vector3(0, 0, 0.0018)), STEEL, "steel"],
	]
	for offset in [0.0032, 0.0064]:
		parts.append([_cylinder(0.0007, ARM_THICKNESS_M + 0.0002, 6), Transform3D(hub_basis, Vector3(0, radius - offset, 0)), DARK_PLASTIC, "plastic"])
	var arm := MeshInstance3D.new()
	arm.name = name
	arm.mesh = _merged_mesh(parts)
	arm.set_meta("controls_dynamic", true)
	_update_arm(arm, pivot, endpoint, axis)
	parent.add_child(arm)
	return arm


## Arm frame: origin on the shaft, +Y toward the clevis, +Z up the shaft (away from the servo).
static func _update_arm(arm: Node3D, pivot: Vector3, endpoint: Vector3, axis: Vector3) -> void:
	var along := (endpoint - pivot).normalized()
	var up := (axis - along * axis.dot(along)).normalized()
	arm.transform = Transform3D(Basis(along.cross(up), along, up), pivot)


## A flat plate: convex `outline` (XY, metres) extruded `thickness` along Z, centred on Z = 0, with flat normals.
static func _plate_mesh(outline: PackedVector2Array, thickness: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centre := Vector2.ZERO
	for point in outline:
		centre += point
	centre /= float(outline.size())
	var half := thickness * 0.5
	for i in outline.size():
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % outline.size()]
		for z in [half, -half]:
			_face(tool, Vector3(centre.x, centre.y, z), Vector3(a.x, a.y, z), Vector3(b.x, b.y, z), Vector3(0, 0, signf(z)))
		var side := Vector3(b.y - a.y, a.x - b.x, 0).normalized()
		if side.dot(Vector3(a.x - centre.x, a.y - centre.y, 0)) < 0.0:
			side = -side
		_face(tool, Vector3(a.x, a.y, half), Vector3(b.x, b.y, half), Vector3(b.x, b.y, -half), side)
		_face(tool, Vector3(a.x, a.y, half), Vector3(b.x, b.y, -half), Vector3(a.x, a.y, -half), side)
	# Indexed with tangents like the primitive meshes: SurfaceTool.append_from keeps only indexed triangles once any
	# merged part is indexed, so an unindexed plate would silently vanish from a batch.
	tool.index()
	tool.generate_tangents()
	return tool.commit()


## One flat triangle wound to face `normal` (Godot front faces are clockwise).
static func _face(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, region := "") -> void:
	var corners := [a, b, c] if (b - a).cross(c - a).dot(normal) < 0.0 else [a, c, b]
	for corner: Vector3 in corners:
		tool.set_normal(normal)
		tool.set_uv(Finish.uv(corner, region) if not region.is_empty() else Vector2(corner.x, corner.y))
		tool.add_vertex(corner)


## A box covered in the airframe film: each corner samples the atlas at its own position in `region`'s unwrap, so the
## box carries the surrounding colours and takes the paint slot that names it. `transform` is in that region's frame.
static func _film_box(name: String, size: Vector3, transform: Transform3D, region: String) -> MeshInstance3D:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axis in 3:
		for side in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = side
			var u := Vector3.ZERO
			u[(axis + 1) % 3] = 1.0
			var v := Vector3.ZERO
			v[(axis + 2) % 3] = 1.0
			var corners: Array[Vector3] = []
			for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				corners.append(transform * ((n + u * corner.x + v * corner.y) * size * 0.5))
			var normal := (transform.basis * n).normalized()
			_face(tool, corners[0], corners[1], corners[2], normal, region)
			_face(tool, corners[0], corners[2], corners[3], normal, region)
	# Unindexed like every film surface (the film checks read triangles in order); it is never merged.
	tool.generate_tangents()
	var mesh := tool.commit()
	mesh.surface_set_material(0, Finish.covering())
	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = mesh
	return instance


## Merge [mesh, transform, colour, profile] parts into one mesh with a surface per material (for moving parts).
static func _merged_mesh(parts: Array) -> ArrayMesh:
	var tools: Dictionary = {}
	for part in parts:
		var material := Finish.material(part[2], part[3])
		if not tools.has(material):
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			tool.set_material(material)
			tools[material] = tool
		(tools[material] as SurfaceTool).append_from(_indexed(part[0]), 0, part[1])
	var mesh := ArrayMesh.new()
	for material in tools:
		(tools[material] as SurfaceTool).commit(mesh)
	return mesh


## `mesh` with an index array: SurfaceTool.append_from keeps only indexed triangles once any merged part is indexed,
## so every part is indexed before a merge (US-V17).
static func _indexed(mesh: Mesh) -> Mesh:
	var indices: Variant = mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	if indices != null and not (indices as PackedInt32Array).is_empty():
		return mesh
	var tool := SurfaceTool.new()
	tool.create_from(mesh, 0)
	tool.index()
	return tool.commit()


static func _cylinder(radius: float, length: float, segments: int) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = segments
	mesh.rings = 1
	return mesh


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
	# Each clevis pin follows its own crank: the servo arm's axis, or the horn's when it turns in another plane.
	rod.start_joint.basis = _joint_basis(rod.get("start_normal", normal), direction)
	rod.end_joint.basis = _joint_basis(rod.get("end_normal", normal), direction)
	rod.current_length_m = actual_length
	rod.length_error_m = absf(actual_length - float(rod.target_length_m))


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
	# The long rod runs inside the fuselage and leaves it near the tail. US-V18b: a fibre exit plate sits on the skin
	# where the neutral rod actually crosses it (side or bottom), over a short guide tube inside.
	var exit := _fuselage_exit(servo_end, horn_end)
	if exit.is_empty():
		return
	var point: Vector3 = exit.point
	var direction := (horn_end - servo_end).normalized()
	var plate_basis := Basis(Quaternion(Vector3.UP, exit.normal))
	var plate := _box_mesh(surface_name + "_fibre_exit_plate", Vector3(0.020, 0.0022, 0.016), FIBER_PLATE, "plastic")
	plate.transform = Transform3D(plate_basis, point)
	linkages.add_child(plate)
	for x_sign in [-1.0, 1.0]:
		for z_sign in [-1.0, 1.0]:
			var offset := Vector3(x_sign * 0.007, 0.0014, z_sign * 0.005)
			var screw := _cylinder_mesh(surface_name + "_exit_plate_screw", 0.0011, 0.0015, STEEL, "steel", 8)
			screw.transform = Transform3D(plate_basis, point + plate_basis * offset)
			linkages.add_child(screw)
	var guide_start := point - direction * 0.05
	var guide_finish := point + direction * 0.003
	var guide := _cylinder_mesh(surface_name + "_pushrod_exit_tube", 0.0022, guide_start.distance_to(guide_finish), FIBER_PLATE, "plastic", 10)
	guide.transform = Transform3D(Basis(Quaternion(Vector3.UP, direction)), (guide_start + guide_finish) * 0.5)
	linkages.add_child(guide)


## Where the segment a→b first leaves the fuselage's outer section (sides, top or bottom): {point, normal}, or {}.
static func _fuselage_exit(a: Vector3, b: Vector3) -> Dictionary:
	var inside := func(p: Vector3) -> bool:
		var section := _fuselage_section(p.z)
		return absf(p.x) <= section.x and p.y >= section.z and p.y <= section.y
	if not inside.call(a):
		return {}
	var lo := 0.0
	var hi := -1.0
	for step in range(1, 401):
		if not inside.call(a.lerp(b, float(step) / 400.0)):
			hi = float(step) / 400.0
			break
		lo = float(step) / 400.0
	if hi < 0.0:
		return {}
	for i in range(30):
		var mid := (lo + hi) * 0.5
		if inside.call(a.lerp(b, mid)): lo = mid
		else: hi = mid
	var point := a.lerp(b, hi)
	var section := _fuselage_section(point.z)
	var side := absf(absf(point.x) - section.x)
	var bottom := absf(point.y - section.z)
	var top := absf(point.y - section.y)
	var normal := Vector3.RIGHT * signf(point.x)
	if bottom < side and bottom <= top: normal = Vector3.DOWN
	elif top < side: normal = Vector3.UP
	return {"point": point, "normal": normal}


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
			tool.append_from(_indexed(mesh_instance.mesh), 0, mesh_instance.transform)
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

extends SceneTree

const Turbine := preload("res://physics/turbine.gd")
const M := preload("res://physics/math3d.gd")

var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	print(("ok   " if ok else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))
	if not ok:
		_failures += 1


func _prop() -> Dictionary:
	return {
		axis = M.v3(1.0, 0.0, 0.0),
		offset = PackedFloat64Array([0.0, 0.0, -0.05]),
		intake_offset = PackedFloat64Array([-0.3, 0.0, 0.0]),
		installed_factor = 0.9,
		static_thrust = PackedFloat64Array([0.0, 0.0, 150000.0, 100.0]),
		mass_flow = PackedFloat64Array([0.0, 0.0001, 150000.0, 0.2]),
	}


func _near_vec(a: PackedFloat64Array, b: PackedFloat64Array, tolerance: float) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if absf(a[i] - b[i]) > tolerance:
			return false
	return true


func _max_diff(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var worst := 0.0
	for i in a.size():
		worst = maxf(worst, absf(a[i] - b[i]))
	return worst


func _initialize() -> void:
	var prop := _prop()
	var rpm := 150000.0
	var rho := 1.225
	_check("force-law identity is separate from the continuous spool law",
		Turbine.LOADS_LAW.begins_with("turbine-capture-vector-signed-axial-")
		and Turbine.LOADS_LAW != Turbine.CONTINUOUS_LAW, Turbine.LOADS_LAW)
	_check("static installed thrust remains 90 N", absf(Turbine.thrust(rpm, 0.0, prop, rho) - 90.0) < 1e-12)
	_check("positive axial thrust at 50 m/s remains 80 N", absf(Turbine.thrust(rpm, 50.0, prop, rho) - 80.0) < 1e-12)
	_check("reverse axial scalar continuation uses signed u", absf(Turbine.thrust(rpm, -40.0, prop, rho) - 98.0) < 1e-12)

	# At zero axial velocity, transverse flow is still captured by the vector continuation.
	# Values on either side of u=0 use the same nonnegative static captured-flow endpoint.
	var epsilon := 1.0e-6
	var at_zero := Turbine.loads(M.v3(0.0, 20.0, -13.0), rpm, prop, rho)
	var from_negative := Turbine.loads(M.v3(-epsilon, 20.0, -13.0), rpm, prop, rho)
	var from_positive := Turbine.loads(M.v3(epsilon, 20.0, -13.0), rpm, prop, rho)
	_check("crossflow capture force is continuous through axial zero from both sides",
		_max_diff(from_negative, from_positive) < 1.0e-6
		and _max_diff(at_zero, from_positive) < 1.0e-6,
		"negative→positive max delta %.12f; zero→positive %.12f N/N·m" % [_max_diff(from_negative, from_positive), _max_diff(at_zero, from_positive)])
	_check("zero-axial transverse inlet momentum remains present",
		absf(at_zero[0] - 90.0) < 1e-12 and absf(at_zero[1] + 4.0) < 1e-12 and absf(at_zero[2] - 2.6) < 1e-12,
		"F=[%.6f, %.6f, %.6f] N" % [at_zero[0], at_zero[1], at_zero[2]])

	# Rotate the shaft axis and independently check force projection and both physical arms.
	var axis := M.v3(0.6, 0.0, 0.8)
	prop.axis = axis
	var u := -7.0
	var crossflow := M.v3(-16.0, 22.0, 12.0) # dot(axis, crossflow) == 0
	var v_in := M.add(M.scale(axis, u), crossflow)
	var flow := Turbine.mass_flow(rpm, prop, rho, u)
	var gross := M.scale(axis, Turbine.gross_thrust(rpm, prop, rho, u))
	var inlet := M.scale(v_in, -flow)
	var loads := Turbine.loads(v_in, rpm, prop, rho)
	var expected_force := M.add(gross, inlet)
	var r_exit := M.v3(-prop.offset[0], prop.offset[1], -prop.offset[2])
	var r_intake := M.v3(-prop.intake_offset[0], prop.intake_offset[1], -prop.intake_offset[2])
	var expected_moment := M.add(M.cross(r_exit, gross), M.cross(r_intake, inlet))
	var projection := M.dot(M.v3(loads[0], loads[1], loads[2]), axis)
	_check("rotated-axis scalar thrust equals vector-load projection in reverse flow",
		absf(projection - Turbine.thrust(rpm, u, prop, rho)) < 1e-12,
		"projection %.12f N; scalar %.12f N" % [projection, Turbine.thrust(rpm, u, prop, rho)])
	_check("rotated-axis force uses captured flow and distinct exit/intake arms",
		_near_vec(loads.slice(0, 3), expected_force, 1e-12)
		and _near_vec(loads.slice(3, 6), expected_moment, 1e-12),
		"force error %.12f; moment error %.12f" % [_max_diff(loads.slice(0, 3), expected_force), _max_diff(loads.slice(3, 6), expected_moment)])

	# Rigid-body applied-load power identity: forces at their two declared points equal
	# the net force at O plus the reported moment about O. This is not an engine energy closure.
	var v_o := M.v3(23.0, -8.0, 4.0)
	var omega := M.v3(-1.2, 0.7, 2.1)
	var v_exit := M.add(v_o, M.cross(omega, r_exit))
	var v_intake := M.add(v_o, M.cross(omega, r_intake))
	var point_power := M.dot(gross, v_exit) + M.dot(inlet, v_intake)
	var body_power := M.dot(expected_force, v_o) + M.dot(expected_moment, omega)
	_check("two-arm rigid-body load power identity", absf(point_power - body_power) < 1e-10,
		"point %.12f W; body %.12f W; delta %.12f W" % [point_power, body_power, point_power - body_power])

	print("F02 captured-air continuity: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)

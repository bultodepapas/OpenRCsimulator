# D8a-R1: the analysis Jacobian uses the shared runtime equations, including rotor gyroscopic momentum.
# Also compare the shared evaluator against an independent composition of the real air/aero/propulsion/body calls.
# Run: godot --headless --path . --script res://tests/test_dynamics.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const AD := preload("res://physics/aircraft_data.gd")
const L := preload("res://physics/linearize.gd")
const Trim := preload("res://physics/trim.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const FlightModes := preload("res://physics/flight_modes.gd")
const Scenarios := preload("res://sim/scenarios.gd")

const G := 9.80665

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])
	if not ok:
		_failures += 1


func _close_array(got: PackedFloat64Array, want: PackedFloat64Array, tol := 1e-11) -> bool:
	if got.size() != want.size():
		return false
	for i in got.size():
		if absf(got[i] - want[i]) > tol * maxf(1.0, absf(want[i])):
			return false
	return true


func _sum_loads(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	var out := a.duplicate()
	for i in out.size():
		out[i] += b[i]
	return out


func _is_square(matrix: Array, n: int) -> bool:
	if matrix.size() != n:
		return false
	for row in matrix:
		if (row as PackedFloat64Array).size() != n:
			return false
	return true


func _state_from_mode_x(x: PackedFloat64Array) -> PackedFloat64Array:
	return RB.make_state(M.v3(0, 0, -100), M.v3(x[0], x[1], x[2]),
		M.q_from_euler(0.0, x[7], x[6]), M.v3(x[3], x[4], x[5]))


func _mode_output_no_rotor(x: PackedFloat64Array, model: Dictionary, d: Dictionary, rpm: float) -> PackedFloat64Array:
	var s := _state_from_mode_x(x)
	var air := Air.compute(s, M.v3(0, 0, 0))
	var loads := _sum_loads(Aero.loads(s, air, d, model, Air.RHO_SEA_LEVEL),
		Propulsion.loads(air.v_air, rpm, model.propulsion, Air.RHO_SEA_LEVEL))
	var dot := RB.derivative(s, model.mass_kg, model.inertia, RB.inertia_inverse(model.inertia),
		M.v3(loads[0], loads[1], loads[2]), M.v3(loads[3], loads[4], loads[5]), G)
	var phi := x[6]
	var theta := x[7]
	return PackedFloat64Array([dot[RB.VEL], dot[RB.VEL + 1], dot[RB.VEL + 2], dot[RB.RATE], dot[RB.RATE + 1], dot[RB.RATE + 2],
		x[3] + (x[4] * sin(phi) + x[5] * cos(phi)) * tan(theta), x[4] * cos(phi) - x[5] * sin(phi)])


func _initialize() -> void:
	var model: Dictionary = AD.load_file(Scenarios.AIRCRAFT).model
	# Manual composition of the real modules at a nontrivial state, wind, density, surface set and rpm.
	var s := RB.make_state(M.v3(20, -4, -100), M.v3(17.0, 1.3, 3.2), M.q_from_euler(0.21, -0.08, 0.12), M.v3(0.31, -0.24, 0.18))
	var d := { elevator = -0.045, aileron_right = -0.07, aileron_left = 0.035, rudder = 0.025 }
	var wind := M.v3(-2.1, 1.4, 0.6)
	var rho := 1.08
	var rpm := 9600.0
	var air := Air.compute(s, wind, rho)
	var aero_loads := Aero.loads(s, air, d, model, rho)
	var propulsion_loads := Propulsion.loads(air.v_air, rpm, model.propulsion, rho)
	var manual_loads := _sum_loads(aero_loads, propulsion_loads)
	var h := Dynamics.rotor_momentum(model, rpm)
	var manual_derivative := RB.derivative(s, model.mass_kg, model.inertia, RB.inertia_inverse(model.inertia),
		M.v3(manual_loads[0], manual_loads[1], manual_loads[2]), M.v3(manual_loads[3], manual_loads[4], manual_loads[5]), G, h)
	var evaluation := Dynamics.evaluate(s, model, d, rpm, rho, wind, G)
	_check("shared loads equal manual aero + propulsion evaluation", _close_array(Dynamics.loads(s, model, d, rpm, rho, wind), manual_loads)
		and _close_array(evaluation.loads, manual_loads))
	_check("shared derivative equals manual rigid-body derivative including rotor momentum",
		_close_array(evaluation.derivative, manual_derivative) and _close_array(Dynamics.derivative(s, model, d, rpm, rho, wind, G), manual_derivative))
	_check("shared evaluation reports its explicit air/load/rotor context",
		evaluation.air.V == air.V and _close_array(evaluation.aero_loads, aero_loads)
		and _close_array(evaluation.propulsion_loads, propulsion_loads) and _close_array(evaluation.rotor_momentum, h))

	var trim := Trim.solve("level", 15.0, model, G, model.controls.throw_rad)
	_check("15 m/s level trim exists", trim.ok, trim.get("message", ""))
	if not trim.ok:
		quit(1)
		return

	var modes := FlightModes.analyze(model, 15.0, G)
	_check("flight modes expose the full 8×8 Jacobian", modes.ok and _is_square(modes.get("full_jacobian", []), 8))
	if modes.ok and _is_square(modes.get("full_jacobian", []), 8):
		var full: Array = modes.full_jacobian
		var projection: Dictionary = modes.get("projected_jacobians", {})
		_check("existing longitudinal and lateral modes use explicit 4×4 projections",
			_is_square(projection.get("longitudinal", []), 4) and _is_square(projection.get("lateral", []), 4))
		# The rotor's +x angular momentum adds +h to the r-dot moment for a unit q perturbation.
		# Compare the exposed full matrix against the same linearization with that term explicitly removed.
		var e := M.q_to_euler(trim.state.slice(RB.ATT, RB.ATT + 4))
		var x0 := PackedFloat64Array([trim.state[RB.VEL], trim.state[RB.VEL + 1], trim.state[RB.VEL + 2],
			0.0, 0.0, 0.0, e[2], e[1]])
		var trim_d := { elevator = trim.elevator, aileron_right = trim.aileron,
			aileron_left = -trim.aileron, rudder = trim.rudder }
		var no_gyro := L.jacobian(func(x: PackedFloat64Array) -> PackedFloat64Array:
			return _mode_output_no_rotor(x, model, trim_d, trim.rpm), x0)
		var expected_gyro := RB.inertia_mul(RB.inertia_inverse(model.inertia),
			M.v3(0.0, 0.0, model.propulsion.rotor_inertia * trim.rpm * TAU / 60.0))
		_check("full Jacobian retains the rotor q→r gyroscopic coupling",
			absf(full[5][4] - no_gyro[5][4] - expected_gyro[2]) < 1e-7,
			"ΔA[ṙ,q] %s vs J⁻¹(0,0,h)z %s" % [String.num_scientific(full[5][4] - no_gyro[5][4]), String.num_scientific(expected_gyro[2])])

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)

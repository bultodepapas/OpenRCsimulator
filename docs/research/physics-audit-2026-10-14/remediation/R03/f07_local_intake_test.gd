extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const Turbine := preload("res://physics/turbine.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

const AIRCRAFT_DATA := "res://data/aircraft/sebart_avanti_s_a200.json"
const AIRCRAFT_ID := "sebart-avanti-s-a200-p100rx"

var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	print(("ok   " if ok else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))
	if not ok:
		_failures += 1


func _near_vec(a: PackedFloat64Array, b: PackedFloat64Array, tolerance: float) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if absf(a[i] - b[i]) > tolerance:
			return false
	return true


func _subtract(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	var result := a.duplicate()
	for i in result.size():
		result[i] -= b[i]
	return result


func _initialize() -> void:
	var flight := FlightSession.new()
	flight.setup(AIRCRAFT_DATA, AIRCRAFT_ID)
	root.add_child(flight)
	if not flight.aircraft.get("ok", false) or not flight.start.get("ok", false):
		_check("Avanti fixture loads for common turbine dispatch", false, str(flight.start.get("message", "")))
		flight.free()
		quit(1)
		return

	var model: Dictionary = flight.aircraft.model
	var prop: Dictionary = model.propulsion
	var state: PackedFloat64Array = flight.sim.state.duplicate()
	state[RB.VEL] = 38.0
	state[RB.VEL + 1] = -4.0
	state[RB.VEL + 2] = 7.0
	var deflections: Dictionary = flight._deflections(flight.sim.aux)
	var wind := M.v3(3.0, -2.0, 1.0)
	var rho := 1.225
	var rpm: float = float(prop.max_rpm)
	var arms_ok := true
	var kinematic_change_ok := true
	var max_formula_error := 0.0
	var max_dispatch_error := 0.0
	var max_stage_path_error := 0.0
	var first_local := PackedFloat64Array()
	var first_prop_loads := PackedFloat64Array()
	var q_values: Array[float] = [2.0, -2.0, 0.0]
	for q in q_values:
		var stage := state.duplicate()
		stage[RB.RATE] = 0.0
		stage[RB.RATE + 1] = q
		stage[RB.RATE + 2] = 0.0
		var omega := stage.slice(RB.RATE, RB.RATE + 3)
		var air: Dictionary = Air.compute(stage, wind, rho)
		# Independent R03 formula: transform the authored [aft,right,up] point to FRD and add omega × r.
		var authored_arm: PackedFloat64Array = prop.intake_offset
		var r_intake := M.v3(-authored_arm[0], authored_arm[1], -authored_arm[2])
		var independent_local := M.add(air.v_air, M.cross(omega, r_intake))
		var helper_local: PackedFloat64Array = Turbine.local_intake_velocity(air.v_air, omega, prop)
		max_formula_error = maxf(max_formula_error, _max_abs(_subtract(helper_local, independent_local)))

		var direct_local_loads := Turbine.loads(independent_local, rpm, prop, rho)
		var common := Dynamics.loads(stage, model, deflections, rpm, rho, wind)
		var common_air := Aero.loads(stage, air, deflections, model, rho)
		var common_propulsion := _subtract(common, common_air)
		max_dispatch_error = maxf(max_dispatch_error, _max_abs(_subtract(common_propulsion, direct_local_loads)))
		var common_stage := Dynamics.loads_from_air(stage, model, deflections, rpm, rho, air)
		max_stage_path_error = maxf(max_stage_path_error, _max_abs(_subtract(common_stage, common)))
		if q == 2.0:
			first_local = helper_local
			first_prop_loads = direct_local_loads
		elif q == -2.0:
			kinematic_change_ok = not _near_vec(first_local, helper_local, 1e-9) \
				and not _near_vec(first_prop_loads, direct_local_loads, 1e-9)
		var projection := M.dot(direct_local_loads.slice(0, 3), prop.axis)
		var axial := M.dot(independent_local, prop.axis)
		arms_ok = arms_ok and absf(projection - Turbine.thrust(rpm, axial, prop, rho)) < 1e-9

	_check("local intake helper equals independent body-rate point velocity", max_formula_error < 1e-12,
		"max component error %.12f m/s across q=+2,-2,0 rad/s" % max_formula_error)
	_check("common Dynamics propulsion load uses local inlet velocity", max_dispatch_error < 1e-9,
		"max component error %.12f N/N·m" % max_dispatch_error)
	_check("generic and stage-air Dynamics paths agree at each same stage", max_stage_path_error < 1e-9,
		"max component error %.12f N/N·m" % max_stage_path_error)
	_check("q=±2 rad/s changes local velocity and turbine loads at the offset intake", kinematic_change_ok,
		"+q local=%s; -q local=%s" % [str(first_local), str(Turbine.local_intake_velocity(Air.compute(state, wind, rho).v_air, M.v3(0.0, -2.0, 0.0), prop))])
	_check("thrust projection and separate intake/nozzle arms remain consistent", arms_ok)

	# The rigid-body correction vanishes for zero rate or zero intake offset.
	var zero_rate := Turbine.local_intake_velocity(Air.compute(state, wind, rho).v_air, M.v3(0.0, 0.0, 0.0), prop)
	_check("zero body rate reduces local intake velocity to datum air velocity", _near_vec(zero_rate, Air.compute(state, wind, rho).v_air, 1e-12))
	var prop_zero := prop.duplicate(true)
	prop_zero.intake_offset = PackedFloat64Array([0.0, 0.0, 0.0])
	var omega_nonzero := M.v3(0.0, 2.0, 0.0)
	var offset_zero := Turbine.local_intake_velocity(Air.compute(state, wind, rho).v_air, omega_nonzero, prop_zero)
	_check("zero intake offset reduces local intake velocity to datum air velocity",
		_near_vec(offset_zero, Air.compute(state, wind, rho).v_air, 1e-12))
	flight.free()
	print("F07 local turbine intake kinematics: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _max_abs(values: PackedFloat64Array) -> float:
	var worst := 0.0
	for value in values:
		worst = maxf(worst, absf(value))
	return worst

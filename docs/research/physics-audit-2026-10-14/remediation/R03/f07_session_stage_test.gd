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


func _max_abs(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	if a.size() != b.size():
		return INF
	var worst := 0.0
	for i in a.size():
		worst = maxf(worst, absf(a[i] - b[i]))
	return worst


func _add6(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	var out := a.duplicate()
	if b.is_empty():
		return out
	for i in 6:
		out[i] += b[i]
	return out


func _independent_intake(air_v: PackedFloat64Array, omega: PackedFloat64Array, prop: Dictionary) -> PackedFloat64Array:
	var authored: PackedFloat64Array = prop.intake_offset
	var arm_frd := M.v3(-authored[0], authored[1], -authored[2])
	return M.add(air_v, M.cross(omega, arm_frd))


func _initialize() -> void:
	var session := FlightSession.new()
	session.setup(AIRCRAFT_DATA, AIRCRAFT_ID)
	root.add_child(session)
	if not session.aircraft.get("ok", false) or not session.start.get("ok", false):
		_check("Avanti continuous session setup", false, str(session.start.get("message", "")))
		session.free()
		quit(1)
		return

	var model: Dictionary = session.aircraft.model
	var prop: Dictionary = model.propulsion
	_check("fixture is the authored continuous turbine branch", Turbine.is_continuous(prop)
		and session.turbine_is_continuous(), str(prop.get("engine", {}).get("spool_integrator", "")))
	if not Turbine.is_continuous(prop):
		session.free()
		quit(1)
		return

	var stage_state: PackedFloat64Array = session.sim.state.duplicate()
	stage_state[RB.VEL] = 38.0
	stage_state[RB.VEL + 1] = -4.0
	stage_state[RB.VEL + 2] = 7.0
	stage_state[RB.RATE] = 0.4
	stage_state[RB.RATE + 1] = 1.7
	stage_state[RB.RATE + 2] = -0.6
	var stage_values: PackedFloat64Array = session.sim.continuous.duplicate()
	var stage_rpm: float = float(prop.max_rpm) * 0.73
	stage_values[0] = stage_rpm
	var stage_time: float = session.sim.time() + 0.37
	var air: Dictionary = session.air_data(stage_state, stage_time)
	var density: float = session.air_density()
	var local_air := _independent_intake(air.v_air, stage_state.slice(RB.RATE, RB.RATE + 3), prop)
	var axial := M.dot(local_air, prop.axis)
	var expected_turbine := Turbine.loads(local_air, stage_rpm, prop, density)
	var defs: Dictionary = session._deflections(session.sim.aux)
	var lag: int = session.downwash_index()
	var downwash: float = session.sim.aux[lag] if lag >= 0 and lag < session.sim.aux.size() else NAN
	var expected_dynamics: PackedFloat64Array = Dynamics.loads_from_air(stage_state, model, defs, stage_rpm,
		density, air, downwash, PackedFloat64Array(), session._ground_up(stage_state), expected_turbine)
	var ground_air: Dictionary = air if session.gear_is_retractable() else {}
	var expected_ground: Dictionary = session._ground_evaluation(stage_state, session.sim.aux, stage_values, ground_air)
	var actual_stage: Dictionary = session._turbine_evaluate(stage_state, stage_values, stage_time)
	var expected_total: PackedFloat64Array = _add6(expected_dynamics, expected_ground.loads) if expected_ground.get("ok", false) else PackedFloat64Array()
	_check("actual RK callback accepts the supplied stage", not actual_stage.is_empty() and expected_ground.get("ok", false))
	_check("actual RK callback uses this stage's RPM and independently derived local intake flow",
		not actual_stage.is_empty() and _max_abs(actual_stage.loads, expected_total) < 1e-9,
		"rpm %.3f differs from committed %.3f; axial local %.9f m/s; load delta %s N/N·m" %
		[stage_rpm, session.sim.continuous[0], axial, str(_max_abs(actual_stage.get("loads", PackedFloat64Array()), expected_total))])
	var expected_spool: float = Turbine.spool_rate(stage_rpm,
		Turbine.demand_rpm(session.propulsion_throttle(), prop), prop) if session.engine_running else 0.0
	_check("actual RK callback spool derivative uses stage RPM", absf(actual_stage.derivative[0] - expected_spool) < 1e-12,
		"got %.12f; expected %.12f rpm/s" % [actual_stage.derivative[0], expected_spool])
	var expected_h: PackedFloat64Array = Turbine.rotor_momentum(stage_rpm, prop)
	_check("actual RK callback gyro uses stage RPM", _max_abs(actual_stage.rotor_momentum, expected_h) < 1e-12)

	# Put a coherent accepted endpoint into the session, then check the observer uses the same local intake point.
	var endpoint_state: PackedFloat64Array = stage_state.duplicate()
	var endpoint_rpm: float = float(prop.max_rpm) * 0.61
	session.sim.state = endpoint_state
	session.sim.continuous[0] = endpoint_rpm
	session.sim.aux[0] = endpoint_rpm
	var endpoint_air: Dictionary = session.air_data(endpoint_state, session.sim.time())
	var endpoint_local := _independent_intake(endpoint_air.v_air,
		endpoint_state.slice(RB.RATE, RB.RATE + 3), prop)
	var endpoint_axial := M.dot(endpoint_local, prop.axis)
	var observed: Dictionary = session.turbine_state()
	_check("accepted telemetry reports the accepted RPM and local intake vector",
		observed.get("ok", false) and observed.rpm == endpoint_rpm
		and _max_abs(observed.intake_air_velocity_body_m_s, endpoint_local) < 1e-12,
		"rpm %.3f; local axial %.9f m/s" % [observed.get("rpm", NAN), observed.get("axial_airspeed_m_s", NAN)])
	_check("accepted telemetry thrust/flow are calculated from local axial airspeed",
		absf(observed.axial_airspeed_m_s - endpoint_axial) < 1e-12
		and absf(observed.mass_flow_kg_s - Turbine.mass_flow(endpoint_rpm, prop, density, endpoint_axial)) < 1e-12
		and absf(observed.gross_thrust_n - Turbine.gross_thrust(endpoint_rpm, prop, density, endpoint_axial)) < 1e-12
		and absf(observed.net_thrust_n - Turbine.thrust(endpoint_rpm, endpoint_axial, prop, density)) < 1e-12)

	session.free()
	print("F07 FlightSession continuous stage and telemetry: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)

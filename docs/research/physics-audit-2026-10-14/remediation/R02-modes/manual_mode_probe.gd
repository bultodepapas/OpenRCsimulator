## Independent R02 modal reference input. The manual derivative/Jacobian path does not call
## FlightModes or Linearize. It composes Air, Aero, Propulsion, and RigidBody at actual trim and
## separately records the production matrix as a comparator; SciPy eigensolves the manual matrix.
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const M := preload("res://physics/math3d.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const RB := preload("res://physics/rigid_body.gd")
const Trim := preload("res://physics/trim.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const FlightModes := preload("res://physics/flight_modes.gd")
const Scenarios := preload("res://sim/scenarios.gd")

const G := 9.80665
const RHO := 1.225
const STEPS := [{"key": "1.0e-05", "value": 1e-5}, {"key": "1.0e-06", "value": 1e-6},
	{"key": "1.0e-07", "value": 1e-7}]


func _initialize() -> void:
	var loaded: Dictionary = AD.load_file(Scenarios.AIRCRAFT)
	if not loaded.get("ok", false):
		printerr("model load failed: ", str(loaded.get("errors", [])))
		quit(1)
		return
	var model: Dictionary = loaded.model
	var length: float = float(model.surfaces.horizontal.downwash_lag_length)
	for speed in [10.0, 15.0, 25.0]:
		var trim: Dictionary = Trim.solve("level", speed, model, G, model.controls.throw_rad, RHO)
		if not trim.get("ok", false):
			printerr("trim failed at ", speed, ": ", trim.get("message", ""))
			quit(1)
			return
		var controls := { elevator = trim.elevator, aileron_right = trim.aileron,
			aileron_left = -trim.aileron, rudder = trim.rudder }
		var state: PackedFloat64Array = trim.state
		var e: PackedFloat64Array = M.q_to_euler(state.slice(RB.ATT, RB.ATT + 4))
		var x0 := PackedFloat64Array([state[RB.VEL], state[RB.VEL + 1], state[RB.VEL + 2],
			0.0, 0.0, 0.0, e[2], e[1]])
		var air: Dictionary = Air.compute(state, M.v3(0.0, 0.0, 0.0), RHO)
		x0.append(Aero.wing_wake_velocity(state, air, controls, model))
		var f := func(x: PackedFloat64Array) -> PackedFloat64Array:
			return _manual_derivative(x, controls, model, float(trim.rpm), length)
		var matrices := {}
		for step in STEPS:
			matrices[step.key] = _jacobian(f, x0, step.value)
		var production: Dictionary = FlightModes.analyze(model, speed, G)
		var data := {
			"speed_mps": speed,
			"trim_alpha_rad": trim.alpha,
			"trim_beta_rad": trim.beta,
			"trim_throttle": trim.throttle,
			"trim_rpm": trim.rpm,
			"trim_deflections_rad": controls,
			"trim_state": x0,
			"wake_state_mps": x0[8],
			"wake_length_m": length,
			"jacobians": matrices,
			"production_jacobian": production.full_jacobian,
			"production_modes": {
				"short_period_frequency_hz": production.short_period.f_hz,
				"short_period_zeta": production.short_period.zeta,
				"phugoid_frequency_hz": production.phugoid.f_hz,
				"phugoid_zeta": production.phugoid.zeta,
				"roll_tau_s": production.roll_tau,
				"dutch_roll_frequency_hz": production.dutch_roll.f_hz,
				"dutch_roll_zeta": production.dutch_roll.zeta,
				"spiral_eigenvalue_1_s": -1.0 / production.spiral_tau,
				"wake_lag_eigenvalue_1_s": production.downwash_lag_root,
			},
		}
		print("MODE_REF_JSON=" + JSON.stringify(data))
	quit(0)


func _manual_derivative(x: PackedFloat64Array, controls: Dictionary, model: Dictionary,
		rpm: float, wake_length: float) -> PackedFloat64Array:
	var s := RB.make_state(M.v3(0.0, 0.0, -100.0), M.v3(x[0], x[1], x[2]),
		M.q_from_euler(0.0, x[7], x[6]), M.v3(x[3], x[4], x[5]))
	var air: Dictionary = Air.compute(s, M.v3(0.0, 0.0, 0.0), RHO)
	var aero: PackedFloat64Array = Aero.loads(s, air, controls, model, RHO, x[8])
	var prop: PackedFloat64Array = Propulsion.loads(air.v_air, rpm, model.propulsion, RHO)
	var loads := aero.duplicate()
	for i in 6:
		loads[i] += prop[i]
	var rotor_h: PackedFloat64Array = Dynamics.rotor_momentum(model, rpm)
	var body_dot: PackedFloat64Array = RB.derivative(s, float(model.mass_kg), model.inertia,
		RB.inertia_inverse(model.inertia), M.v3(loads[0], loads[1], loads[2]),
		M.v3(loads[3], loads[4], loads[5]), G, rotor_h)
	var phi: float = x[6]
	var theta: float = x[7]
	var out := PackedFloat64Array([body_dot[RB.VEL], body_dot[RB.VEL + 1], body_dot[RB.VEL + 2],
		body_dot[RB.RATE], body_dot[RB.RATE + 1], body_dot[RB.RATE + 2],
		x[3] + (x[4] * M.sin_(phi) + x[5] * M.cos_(phi)) * M.tan_(theta),
		x[4] * M.cos_(phi) - x[5] * M.sin_(phi)])
	var target: float = Aero.wing_wake_velocity(s, air, controls, model)
	out.append((target - x[8]) * float(air.V) / wake_length)
	return out


func _jacobian(f: Callable, x0: PackedFloat64Array, h: float) -> Array:
	var n := x0.size()
	var rows := []
	for i in n:
		var row := PackedFloat64Array()
		row.resize(n)
		rows.append(row)
	for k in n:
		var xp := x0.duplicate()
		var xm := x0.duplicate()
		xp[k] += h
		xm[k] -= h
		var fp: PackedFloat64Array = f.call(xp)
		var fm: PackedFloat64Array = f.call(xm)
		for i in n:
			rows[i][k] = (fp[i] - fm[i]) / (2.0 * h)
	return rows

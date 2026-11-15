# Read-only FS-64V mode and trim diagnosis. Uses production aircraft loader, trim,
# FlightModes, Dynamics and Linearize. Fixed-throttle root is diagnostic only.
# Run with a checked runner on the exact pinned, imported app; this script does not fly.
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Modes := preload("res://physics/flight_modes.gd")
const Lin := preload("res://physics/linearize.gd")
const Trim := preload("res://physics/trim.gd")
const Session := preload("res://sim/flight_session.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

const RHO := 1.225
const G := 9.80665
const FS_PATH := "res://data/aircraft/stik_glow_fs64v_4t.json"
const PATHS := {
	"fs64v": FS_PATH,
	"basic": "res://data/aircraft/jensen_ugly_stik_60.json",
	"electric_ideal": "res://data/aircraft/stik_electric_6s.json",
	"extra": "res://data/aircraft/gp_extra_300s_60.json",
}


func _initialize() -> void:
	var models := {}
	var identities := {}
	for label: String in PATHS:
		var loaded: Dictionary = AD.load_file(PATHS[label])
		if not loaded.get("ok", false):
			printerr("MODES_PROBE_LOAD_FAILED ", label, " ", loaded.get("errors", []))
			quit(1)
			return
		models[label] = loaded.model
		identities[label] = loaded.get("input_identity", {})
	var fs: Dictionary = models.fs64v
	var vs_est: float = sqrt(2.0 * float(fs.mass_kg) * G / (RHO * float(fs.reference.S) * float(fs.envelope.CL_max)))
	var output := {"format": "openrc-fs64v-modes-followup-v1", "aircraft_input_identity": identities,
		"source_scope": "Production modes linearize at 1.225 kg/m3 and frozen RPM/controls, with block projections. No actual flight or physical validation.",
		"state_order": ["u_mps", "v_mps", "w_mps", "p_radps", "q_radps", "r_radps", "phi_rad", "theta_rad", "wake_mps_if_present"],
		"longitudinal_indices": [0, 2, 4, 7, 8], "lateral_indices": [1, 3, 5, 6],
		"fs_analytic_vs_mps": vs_est, "modes": [], "trim_boundary": {}, "full_throttle_root": {}}
	for v: float in [1.3 * vs_est, 15.0, 17.0, 18.0, 19.0, 20.0, 21.0, 22.4, 24.0, 25.0, 27.0]:
		output.modes.append(_mode_case("fs64v", fs, v, false))
	for v: float in [1.3 * vs_est, 20.0]:
		var instantaneous: Dictionary = fs.duplicate(true)
		instantaneous.surfaces.horizontal.erase("downwash_lag_length")
		output.modes.append(_mode_case("fs64v", instantaneous, v, true))
	for spec: Array in [["basic", 15.0], ["electric_ideal", 15.0], ["extra", 22.0]]:
		output.modes.append(_mode_case(str(spec[0]), models[spec[0]], float(spec[1]), false))
	var flight := Session.new()
	flight.setup(FS_PATH)
	root.add_child(flight)
	if not flight.aircraft.get("ok", false) or not flight.start.get("ok", false):
		printerr("MODES_PROBE_SESSION_FAILED ", flight.start.get("message", "unknown"))
		flight.free()
		quit(1)
		return
	flight.set_physics_process(false)
	flight.sim.set_physics_process(false)
	var query: Dictionary = flight._trim_model(flight.aircraft.model)
	var down: float = float(flight.start.state[RB.POS + 2])
	var rho: float = flight._weather.air_density(down)
	var charge: float = flight._weather.engine_charge_ratio(down)
	var gravity: float = flight.sim.gravity
	var throws: Dictionary = query.controls.throw_rad
	var reference27: Dictionary = flight.trim_at(27.0, "level")
	var guess27 := _trim_guess(reference27)
	var boundary := {"rho_kg_m3": rho, "engine_charge_ratio": charge, "gravity_mps2": gravity,
		"session_fuel_fill": flight.fuel_start_fill, "session_start_down_m": down,
		"session_model_mass_kg": query.mass_kg, "query_has_mass_properties": query.has("trim_mass_properties"),
		"session_trim_at_27": _trim_summary(reference27), "session_trim_at_28": _trim_summary(flight.trim_at(28.0, "level")),
		"cold_and_warm": [], "individual_attempts_28": []}
	for v: float in [27.0, 27.25, 27.5, 27.75, 27.9, 28.0, 28.1, 28.25, 28.5]:
		var cold: Dictionary = Trim.solve("level", v, query, gravity, throws, rho, charge)
		var warm: Dictionary = Trim.solve("level", v, query, gravity, throws, rho, charge, guess27) if not guess27.is_empty() else {}
		boundary.cold_and_warm.append({"speed_mps": v, "cold": _trim_summary(cold), "warm_from_27": _trim_summary(warm)})
	for seed: float in [0.4, 0.75, 0.95]:
		boundary.individual_attempts_28.append({"throttle_seed": seed,
			"result": _trim_summary(Trim._solve_from("level", 28.0, query, gravity, throws, seed, rho, charge))})
	output.trim_boundary = boundary
	if not guess27.is_empty():
		output.full_throttle_root = _full_throttle_root(guess27, 27.0, query, gravity, rho, charge, throws)
	flight.free()
	print("MODES_FOLLOWUP_JSON ", JSON.stringify(output))
	print("MODES_FOLLOWUP_COMPLETE")
	quit(0)


func _mode_case(label: String, model: Dictionary, speed: float, no_lag: bool) -> Dictionary:
	var result: Dictionary = Modes.analyze(model, speed)
	var row := {"aircraft": label, "speed_mps": speed,
		"diagnostic_instantaneous_downwash": no_lag, "ok": result.get("ok", false), "message": result.get("message", "")}
	if not result.get("ok", false):
		return row
	var lon: Array = result.projected_jacobians.longitudinal
	var lat: Array = result.projected_jacobians.lateral
	var raw_lon: Array = Lin.eigenvalues(lon)
	var raw_lat: Array = Lin.eigenvalues(lat)
	row["trim"] = _trim_summary(result.trim)
	row["full_jacobian"] = _matrix_array(result.full_jacobian)
	row["longitudinal_jacobian"] = _matrix_array(lon)
	row["lateral_jacobian"] = _matrix_array(lat)
	row["longitudinal_roots_runtime"] = raw_lon
	row["lateral_roots_runtime"] = raw_lat
	row["longitudinal_classification_runtime"] = Lin.classify(raw_lon)
	row["short_period_runtime"] = result.short_period
	row["phugoid_runtime_before_card_suppression"] = result.phugoid
	row["lag_root_runtime"] = _finite_or_null(float(result.downwash_lag_root))
	row["lag_target_minus_V_over_length"] = -speed / float(model.surfaces.horizontal.downwash_lag_length) if not no_lag else null
	row["short_period_overdamped"] = result.short_period_overdamped
	# The following reproduces FlightModes' exact RHS to compare its default h to
	# two central-difference steps. It does not modify or replace production equations.
	var replicated := _replicated_jacobians(model, result.trim, [1e-7, 1e-6, 1e-5])
	row["finite_difference_replicated"] = replicated
	return row


func _replicated_jacobians(model: Dictionary, trim: Dictionary, steps: Array) -> Array:
	var d := {elevator = trim.elevator, aileron_right = trim.aileron, aileron_left = -trim.aileron, rudder = trim.rudder}
	var lagged: bool = model.get("surfaces", {}).get("horizontal", {}).has("downwash_lag_length")
	var make := func(x: PackedFloat64Array) -> PackedFloat64Array:
		return RB.make_state(M.v3(0.0, 0.0, -100.0), M.v3(x[0], x[1], x[2]), M.q_from_euler(0.0, x[7], x[6]), M.v3(x[3], x[4], x[5]))
	var rhs := func(x: PackedFloat64Array) -> PackedFloat64Array:
		var state: PackedFloat64Array = make.call(x)
		var evaluation: Dictionary = Dynamics.evaluate(state, model, d, trim.rpm, RHO, M.v3(0.0, 0.0, 0.0), G, PackedFloat64Array(), x[8] if lagged else NAN)
		var dot: PackedFloat64Array = evaluation.derivative
		var phi: float = x[6]
		var theta: float = x[7]
		var out := PackedFloat64Array([dot[RB.VEL], dot[RB.VEL+1], dot[RB.VEL+2], dot[RB.RATE], dot[RB.RATE+1], dot[RB.RATE+2],
			x[3] + (x[4]*M.sin_(phi)+x[5]*M.cos_(phi))*M.tan_(theta), x[4]*M.cos_(phi)-x[5]*M.sin_(phi)])
		if lagged:
			var air: Dictionary = evaluation.air
			out.append((Aero.wing_wake_velocity(state, air, d, model) - x[8]) * float(air.V) / float(model.surfaces.horizontal.downwash_lag_length))
		return out
	var state: PackedFloat64Array = trim.state
	var e: PackedFloat64Array = M.q_to_euler(state.slice(RB.ATT, RB.ATT+4))
	var x0 := PackedFloat64Array([state[RB.VEL], state[RB.VEL+1], state[RB.VEL+2], 0.0, 0.0, 0.0, e[2], e[1]])
	var indices := [0, 2, 4, 7]
	if lagged:
		var trimmed: PackedFloat64Array = make.call(x0)
		x0.append(Aero.wing_wake_velocity(trimmed, Air.compute(trimmed, M.v3(0.0, 0.0, 0.0), RHO), d, model))
		indices.append(8)
	var out := []
	for step: float in steps:
		var a: Array = Lin.jacobian(rhs, x0, step)
		var lon: Array = Lin.submatrix(a, indices)
		out.append({"h": step, "full_jacobian": _matrix_array(a),
			"longitudinal_jacobian": _matrix_array(lon), "runtime_roots": Lin.eigenvalues(lon)})
	return out


func _trim_guess(t: Dictionary) -> PackedFloat64Array:
	if not t.get("ok", false):
		return PackedFloat64Array()
	return PackedFloat64Array([t.alpha, t.elevator, t.throttle, t.beta, t.aileron, t.rudder])


func _trim_summary(t: Dictionary) -> Dictionary:
	if t.is_empty(): return {"ok": false, "message": "no result"}
	var result := {"ok": t.get("ok", false), "message": t.get("message", ""), "iterations": t.get("iterations", null)}
	for key: String in ["V", "alpha", "beta", "elevator", "aileron", "rudder", "throttle", "rpm", "thrust", "residual", "pitch_command"]:
		if t.has(key): result[key] = _finite_or_null(float(t[key]))
	return result


func _fixed_throttle_residual(y: PackedFloat64Array, model: Dictionary, gravity: float, rho: float, charge: float) -> PackedFloat64Array:
	var x := PackedFloat64Array([y[0], y[1], 1.0, y[3], y[4], y[5]])
	return Trim._residual(x, "level", y[2], model, gravity, rho, charge)


func _full_throttle_root(guess: PackedFloat64Array, speed: float, model: Dictionary, gravity: float,
		rho: float, charge: float, throws: Dictionary) -> Dictionary:
	# Diagnostic six-equation solve with speed as unknown and throttle fixed at 1.
	# A found root proves one equilibrium of the same equations, not global uniqueness.
	var y := PackedFloat64Array([guess[0], guess[1], speed, guess[3], guess[4], guess[5]])
	var r := _fixed_throttle_residual(y, model, gravity, rho, charge)
	var history := []
	var status := "iteration limit"
	for iteration in 35:
		var norm: float = Trim._norm(r)
		history.append({"iteration": iteration, "speed_mps": y[2], "residual_norm": _finite_or_null(norm)})
		if not is_finite(norm):
			status = "nonfinite residual"
			break
		if norm <= 1e-8:
			status = "converged"
			break
		var jac := []
		for _i in 6: jac.append(PackedFloat64Array([0.0,0.0,0.0,0.0,0.0,0.0]))
		for k in 6:
			var h := 1e-6 * maxf(1.0, absf(y[k]))
			var plus := y.duplicate()
			plus[k] += h
			var rp := _fixed_throttle_residual(plus, model, gravity, rho, charge)
			for i in 6: jac[i][k] = (rp[i] - r[i]) / h
		var neg := PackedFloat64Array()
		for value: float in r: neg.append(-value)
		var dx: PackedFloat64Array = Trim.solve_linear(jac, neg)
		if dx.is_empty():
			status = "singular or nonfinite diagnostic Jacobian"
			break
		var step := 1.0
		var accepted := false
		while step >= 1e-8:
			var candidate := y.duplicate()
			for i in 6: candidate[i] += step * dx[i]
			if candidate[2] >= 20.0 and candidate[2] <= 35.0:
				var candidate_r := _fixed_throttle_residual(candidate, model, gravity, rho, charge)
				var candidate_norm: float = Trim._norm(candidate_r)
				if is_finite(candidate_norm) and candidate_norm < norm:
					y = candidate
					r = candidate_r
					accepted = true
					break
			step *= 0.5
		if not accepted:
			status = "no decreasing bounded speed step"
			break
	var x := PackedFloat64Array([y[0], y[1], 1.0, y[3], y[4], y[5]])
	var throw_message: String = Trim._throw_limit_message(x, throws, model)
	return {"status": status, "speed_search_bounds_mps": [20.0, 35.0], "speed_mps": _finite_or_null(y[2]),
		"alpha_rad": _finite_or_null(y[0]), "elevator_rad": _finite_or_null(y[1]), "beta_rad": _finite_or_null(y[3]),
		"aileron_rad": _finite_or_null(y[4]), "rudder_rad": _finite_or_null(y[5]), "throttle": 1.0,
		"residual": _safe_array(r), "residual_norm": _finite_or_null(Trim._norm(r)), "throw_limit_message": throw_message,
		"iterations": history}


func _matrix_array(rows: Array) -> Array:
	var result := []
	for row in rows: result.append(_safe_array(row))
	return result


func _safe_array(values: PackedFloat64Array) -> Array:
	var out := []
	for value: float in values: out.append(_finite_or_null(value))
	return out


func _finite_or_null(value: float) -> Variant:
	return value if is_finite(value) else null

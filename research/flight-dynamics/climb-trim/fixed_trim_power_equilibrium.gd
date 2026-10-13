extends SceneTree

## Read-only longitudinal equilibrium audit for the standard Ugly Stik.
## Run from the app project with:
##   Godot --headless --path app --script res://../research/flight-dynamics/climb-trim/fixed_trim_power_equilibrium.gd

const Flight := preload("res://sim/flight_session.gd")
const Trim := preload("res://physics/trim.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const AIRCRAFT_PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const AIRCRAFT_ID := "jensen-das-ugly-stik-60"
const RHO := 1.225
const G := 9.80665
const SPEED_MIN := 1.0
const SPEED_MAX := 60.0
const SPEED_STEP := 0.25

var flight: Node
var model: Dictionary
var deflections: Dictionary
var mass_kg: float


func _point(speed: float, alpha: float, rpm: float, include_flow_weight := false) -> Dictionary:
	var state: PackedFloat64Array = Trim.state_for(speed, alpha, 0.0, 0.0, M.v3(0.0, 0.0, -100.0))
	var wind := PackedFloat64Array([0.0, 0.0, 0.0])
	var air: Dictionary = Air.compute(state, wind, RHO)
	var wing_cl: float = Aero.wing_lift_coefficient(state, air, deflections, model)
	var downwash_cl: float = wing_cl if flight.downwash_index() >= 0 else NAN
	var loads: PackedFloat64Array = Dynamics.loads(state, model, deflections, rpm, RHO, wind, downwash_cl)
	var force_norm: float = M.sqrt_(loads[0] * loads[0] + loads[2] * loads[2])
	var theta: float = M.atan2_(loads[0], -loads[2])
	var propulsion: PackedFloat64Array = Propulsion.loads(air.v_air, rpm, model.propulsion, RHO)
	var flow_weight: Variant = null
	if include_flow_weight:
		flow_weight = Aero.local_flow_weight(state, air, deflections, model, downwash_cl)
	return {
		"speed_mps": speed,
		"alpha_rad": alpha,
		"gamma_rad": theta - alpha,
		"theta_rad": theta,
		"loads": loads,
		"wing_cl": wing_cl,
		"force_norm_n": force_norm,
		"force_gap_n": force_norm - mass_kg * G,
		"thrust_n": propulsion[0],
		"local_flow_weight": flow_weight,
	}


func _sha256(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "unavailable"
	var hash := HashingContext.new()
	if hash.start(HashingContext.HASH_SHA256) != OK:
		return "unavailable"
	hash.update(file.get_buffer(file.get_length()))
	return hash.finish().hex_encode()


func _pitch_moment(speed: float, alpha: float, rpm: float) -> float:
	return float(_point(speed, alpha, rpm).loads[4])


func _pitch_root(rpm: float) -> float:
	var roots: Array[Dictionary] = _pitch_roots_at(15.0, rpm)
	if roots.is_empty():
		return NAN
	return roots[0].alpha_rad


func _pitch_roots_at(speed: float, rpm: float) -> Array[Dictionary]:
	# Enumerate sign-changing roots throughout the attached/upright alpha range at 0.1-degree spacing.
	var roots: Array[Dictionary] = []
	var lower := deg_to_rad(-8.0)
	var upper := deg_to_rad(8.0)
	var step := deg_to_rad(0.1)
	var previous_alpha := lower
	var previous_moment := _pitch_moment(speed, previous_alpha, rpm)
	var count := int(round((upper - lower) / step))
	for i in range(1, count + 1):
		var alpha := lower + float(i) * step
		var moment := _pitch_moment(speed, alpha, rpm)
		if previous_moment == 0.0 or previous_moment * moment < 0.0:
			var lo := previous_alpha
			var hi := alpha
			var flo := previous_moment
			for _j in 50:
				var mid := 0.5 * (lo + hi)
				var fm := _pitch_moment(speed, mid, rpm)
				if flo * fm <= 0.0:
					hi = mid
				else:
					lo = mid
					flo = fm
			var root_alpha := 0.5 * (lo + hi)
			var point: Dictionary = _point(speed, root_alpha, rpm, true)
			roots.append({
				"alpha_rad": root_alpha,
				"alpha_deg": rad_to_deg(root_alpha),
				"My_Nm": point.loads[4],
				"local_flow_weight": point.local_flow_weight,
				"wing_cl": point.wing_cl,
				"force_gap_n": point.force_gap_n,
			})
		previous_alpha = alpha
		previous_moment = moment
	return roots


func _minimum_force_gap(throttle: float) -> Dictionary:
	var rpm: float = Propulsion.target_rpm(throttle, model.propulsion)
	var alpha: float = _pitch_root(rpm)
	if not is_finite(alpha):
		return {"ok": false, "throttle": throttle, "rpm": rpm, "reason": "no attached pitch-moment root"}
	var best: Dictionary = {}
	var best_i := 0
	var n := int(round((SPEED_MAX - SPEED_MIN) / SPEED_STEP))
	for i in range(n + 1):
		var speed := SPEED_MIN + float(i) * SPEED_STEP
		var point := _point(speed, alpha, rpm)
		if best.is_empty() or point.force_gap_n < best.force_gap_n:
			best = point
			best_i = i
	# Refine the global coarse-grid minimum locally with golden-section search.
	if best_i > 0 and best_i < n:
		var lo := SPEED_MIN + float(best_i - 1) * SPEED_STEP
		var hi := SPEED_MIN + float(best_i + 1) * SPEED_STEP
		var ratio := 0.5 * (sqrt(5.0) - 1.0)
		var x1 := hi - ratio * (hi - lo)
		var x2 := lo + ratio * (hi - lo)
		var p1 := _point(x1, alpha, rpm)
		var p2 := _point(x2, alpha, rpm)
		for _i in 45:
			if p1.force_gap_n <= p2.force_gap_n:
				hi = x2
				x2 = x1
				p2 = p1
				x1 = hi - ratio * (hi - lo)
				p1 = _point(x1, alpha, rpm)
			else:
				lo = x1
				x1 = x2
				p1 = p2
				x2 = lo + ratio * (hi - lo)
				p2 = _point(x2, alpha, rpm)
		best = p1 if p1.force_gap_n < p2.force_gap_n else p2
	best["ok"] = true
	best["throttle"] = throttle
	best["rpm"] = rpm
	best["alpha_deg"] = rad_to_deg(alpha)
	return best


func _speed_roots(throttle: float) -> Array[Dictionary]:
	var rpm: float = Propulsion.target_rpm(throttle, model.propulsion)
	var alpha: float = _pitch_root(rpm)
	var roots: Array[Dictionary] = []
	if not is_finite(alpha):
		return roots
	var previous_speed := SPEED_MIN
	var previous: Dictionary = _point(previous_speed, alpha, rpm)
	var n := int(round((SPEED_MAX - SPEED_MIN) / SPEED_STEP))
	for i in range(1, n + 1):
		var speed := SPEED_MIN + float(i) * SPEED_STEP
		var point := _point(speed, alpha, rpm)
		if previous.force_gap_n * point.force_gap_n <= 0.0:
			var lo := previous_speed
			var hi := speed
			var flo: float = previous.force_gap_n
			for _j in 50:
				var mid := 0.5 * (lo + hi)
				var fm: float = _point(mid, alpha, rpm).force_gap_n
				if flo * fm <= 0.0:
					hi = mid
				else:
					lo = mid
					flo = fm
			var root: Dictionary = _point(0.5 * (lo + hi), alpha, rpm)
			root["alpha_deg"] = rad_to_deg(alpha)
			root["gamma_deg"] = rad_to_deg(root.gamma_rad)
			root["theta_deg"] = rad_to_deg(root.theta_rad)
			root["upright_and_climbing"] = root.theta_rad > deg_to_rad(-90.0) and root.theta_rad < deg_to_rad(90.0) and root.gamma_rad > 0.0
			roots.append(root)
		previous = point
		previous_speed = speed
	return roots


func _longitudinal_rhs(x: PackedFloat64Array, throttle: float) -> PackedFloat64Array:
	# Planar projection: retain Fx/Fz/My and exact rigid-body gravity/coriolis terms; discard lateral/roll/yaw loads.
	var state: PackedFloat64Array = RB.make_state(
		M.v3(0.0, 0.0, -100.0), M.v3(x[0], 0.0, x[1]),
		M.q_from_euler(0.0, x[3], 0.0), M.v3(0.0, x[2], 0.0)
	)
	var wind := PackedFloat64Array([0.0, 0.0, 0.0])
	var air: Dictionary = Air.compute(state, wind, RHO)
	var wing_cl: float = Aero.wing_lift_coefficient(state, air, deflections, model)
	var loads: PackedFloat64Array = Dynamics.loads(state, model, deflections, x[5], RHO, wind, x[4])
	var derivative: PackedFloat64Array = RB.derivative(
		state, mass_kg, model.inertia, RB.inertia_inverse(model.inertia),
		M.v3(loads[0], 0.0, loads[2]), M.v3(0.0, loads[4], 0.0), G,
		Dynamics.rotor_momentum(model, x[5])
	)
	var length: float = model.surfaces.horizontal.downwash_lag_length
	var downwash_dot: float = (wing_cl - x[4]) * air.V / length
	var target_rpm: float = Propulsion.target_rpm(throttle, model.propulsion)
	var rpm_dot: float = (target_rpm - x[5]) / model.propulsion.lag
	return PackedFloat64Array([derivative[RB.VEL], derivative[RB.VEL + 2], derivative[RB.RATE + 1],
		x[2], downwash_dot, rpm_dot])


func _longitudinal_linearization(throttle: float, root: Dictionary) -> Dictionary:
	var alpha: float = root.alpha_rad
	var speed: float = root.speed_mps
	var rpm: float = Propulsion.target_rpm(throttle, model.propulsion)
	var equilibrium := PackedFloat64Array([
		speed * M.cos_(alpha), speed * M.sin_(alpha), 0.0, root.theta_rad, root.wing_cl, rpm
	])
	var steps := PackedFloat64Array([1.0e-5, 1.0e-5, 1.0e-6, 1.0e-6, 1.0e-7, 1.0e-2])
	var matrix: Array[PackedFloat64Array] = []
	for _i in 6:
		matrix.append(PackedFloat64Array())
		for _j in 6:
			matrix[_i].append(0.0)
	for col in 6:
		var plus := equilibrium.duplicate()
		var minus := equilibrium.duplicate()
		plus[col] += steps[col]
		minus[col] -= steps[col]
		var fp := _longitudinal_rhs(plus, throttle)
		var fm := _longitudinal_rhs(minus, throttle)
		for row in 6:
			matrix[row][col] = (fp[row] - fm[row]) / (2.0 * steps[col])
	return {
		"coordinates": ["u_mps", "w_mps", "q_rad_s", "theta_rad", "downwash_cl", "rpm"],
		"equilibrium_state": equilibrium,
		"jacobian_s_inv": matrix,
		"scope": "Planar fixed-surface/fixed-throttle linearization; retains first-order D5 rpm and downwash lag; projects away lateral, roll and yaw equations and moments. Eigenvalues describe this projected model only.",
	}


func _trimmed_branch_check(rpm: float, alpha: float) -> Dictionary:
	var rows: Array[Dictionary] = []
	for speed in [5.0, 9.0, 15.0, 24.728, 40.0]:
		var point: Dictionary = _point(speed, alpha, rpm, true)
		rows.append({
			"speed_mps": speed,
			"My_Nm": point.loads[4],
			"alpha_deg": rad_to_deg(alpha),
			"force_gap_n": point.force_gap_n,
			"local_flow_weight_at_pitch_root": point.local_flow_weight,
			"attached_range_pitch_root_scan": _pitch_roots_at(speed, rpm),
		})
	return {"pitch_root_residual_by_speed": rows}


func _initialize() -> void:
	flight = Flight.new()
	flight.setup(AIRCRAFT_PATH, AIRCRAFT_ID)
	if not flight.is_flyable():
		print(JSON.stringify({"ok": false, "error": flight.pause_reason}))
		quit(1)
		return
	model = flight.aircraft.model
	mass_kg = model.mass_kg
	deflections = flight._deflections(flight.sim.aux)
	var actual_start_rpm: float = float(flight.sim.aux[0])
	var start_state: PackedFloat64Array = flight.sim.state
	var wind := PackedFloat64Array([0.0, 0.0, 0.0])
	var start_air: Dictionary = Air.compute(start_state, wind, RHO)
	var start_wing_cl: float = Aero.wing_lift_coefficient(start_state, start_air, deflections, model)
	var start_loads: PackedFloat64Array = Dynamics.loads(
		start_state, model, deflections, actual_start_rpm, RHO, wind,
		start_wing_cl if flight.downwash_index() >= 0 else NAN
	)
	var trim_power: float = float(flight.commands.throttle)
	var trim_rpm: float = Propulsion.target_rpm(trim_power, model.propulsion)
	var trim_alpha: float = _pitch_root(trim_rpm)
	var full_rpm: float = Propulsion.target_rpm(1.0, model.propulsion)
	var full_alpha: float = _pitch_root(full_rpm)
	var throttle_rows: Array[Dictionary] = []
	var bracket_lo := -1.0
	var bracket_hi := -1.0
	var last_with_any_root := -1.0
	for i in range(41):
		var throttle := float(i) * 0.025
		var result: Dictionary = _minimum_force_gap(throttle)
		throttle_rows.append({"throttle": throttle, "min_gap_n": result.get("force_gap_n", NAN),
			"speed_mps": result.get("speed_mps", NAN), "alpha_deg": result.get("alpha_deg", NAN)})
		if result.ok and result.force_gap_n <= 0.0:
			last_with_any_root = throttle
		elif result.ok and bracket_hi < 0.0:
			bracket_lo = last_with_any_root
			bracket_hi = throttle
	var critical: Dictionary = {}
	if bracket_lo >= 0.0 and bracket_hi >= 0.0:
		var lo := bracket_lo
		var hi := bracket_hi
		for _i in 24:
			var mid := 0.5 * (lo + hi)
			var result: Dictionary = _minimum_force_gap(mid)
			if result.force_gap_n <= 0.0:
				lo = mid
			else:
				hi = mid
		critical = _minimum_force_gap(0.5 * (lo + hi))
		critical["throttle_bracket"] = [lo, hi]
		critical["gamma_deg"] = rad_to_deg(critical.gamma_rad)
		critical["theta_deg"] = rad_to_deg(critical.theta_rad)
	var selected: Array[Dictionary] = []
	for throttle in [trim_power, 0.5, 0.75, 0.85, 1.0]:
		var rpm: float = Propulsion.target_rpm(throttle, model.propulsion)
		var alpha: float = _pitch_root(rpm)
		var roots: Array[Dictionary] = _speed_roots(throttle)
		var linearization: Dictionary = {}
		if not roots.is_empty():
			linearization = _longitudinal_linearization(throttle, roots[0])
		selected.append({
			"throttle": throttle,
			"rpm": rpm,
			"pitch_trim_alpha_deg": rad_to_deg(alpha),
			"equilibrium_roots": roots,
			"longitudinal_linearization": linearization,
			"minimum_force_gap": _minimum_force_gap(throttle),
			"root_moment_check": _trimmed_branch_check(rpm, alpha),
		})
	var output := {
		"ok": true,
		"aircraft": AIRCRAFT_ID,
		"method": "projected longitudinal equilibrium: My=0 and sqrt(Fx^2+Fz^2)=W at zero body rates; gamma is recovered from the force direction",
		"caveat": "Fixed aileron/rudder are retained, but lateral force/roll/yaw equilibrium is not solved; loads are model calculations, not physical validation.",
		"mass_kg": mass_kg,
		"weight_n": mass_kg * G,
		"source_sha256": {
			"aircraft_json": _sha256("res://data/aircraft/jensen_ugly_stik_60.json"),
			"aero_gd": _sha256("res://physics/aero.gd"),
			"dynamics_gd": _sha256("res://physics/dynamics.gd"),
			"flight_session_gd": _sha256("res://sim/flight_session.gd"),
			"propulsion_gd": _sha256("res://physics/propulsion.gd"),
			"trim_gd": _sha256("res://physics/trim.gd"),
			"rigid_body_gd": _sha256("res://physics/rigid_body.gd"),
		},
		"fixed_surface_deflections_data_rad": deflections,
		"launch": {
			"speed_mps": start_air.V,
			"alpha_deg": rad_to_deg(start_air.alpha),
			"throttle": trim_power,
			"actual_rpm": actual_start_rpm,
			"target_rpm": trim_rpm,
			"loads": start_loads,
			"force_norm_xz_n": M.sqrt_(start_loads[0] * start_loads[0] + start_loads[2] * start_loads[2]),
			"force_gap_xz_n": M.sqrt_(start_loads[0] * start_loads[0] + start_loads[2] * start_loads[2]) - mass_kg * G,
		},
		"full_power_pitch_root": {"alpha_deg": rad_to_deg(full_alpha), "checks": _trimmed_branch_check(full_rpm, full_alpha)},
		"critical_throttle_for_any_longitudinal_root": critical,
		"throttle_minimum_scan": throttle_rows,
		"selected_power_cases": selected,
	}
	var encoded := JSON.stringify(output)
	print(encoded)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			var output_path := argument.trim_prefix("--output=")
			var output_file := FileAccess.open(output_path, FileAccess.WRITE)
			if output_file == null:
				push_error("Could not write output JSON: " + output_path)
				quit(1)
				return
			output_file.store_string(encoded + "\n")
			output_file.close()
	flight.free()
	quit()

# HELI-18: airborne hover trim on the complete coupled rotorcraft equations.
extends RefCounted

const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
const Flight = preload("res://physics/rotorcraft/flight_dynamics.gd")
const MAX_ITERATIONS: int = 60
const STATE_SIZE: int = 19


## Initial unknowns are [roll,pitch,long-stick,lat-stick,tail-bias,
## collective-stick,a1,b1,vi,Omega]. The final controls are mapped through source angles/curves.
## Options may provide flight_mode, initial_guess and tolerance; the seeded start
## is numerical only and all physical parameters remain in the prepared context.
static func solve_hover(context: Dictionary, yaw: float,
		position_ned: PackedFloat64Array, wind_ned_m_s: PackedFloat64Array,
		options: Dictionary = {}) -> Dictionary:
	if not context.is_read_only() or context.get("law") != "openrc-helicopter-flight-dynamics-v1":
		return _failure("hover trim needs a prepared flight context", 0)
	for key: Variant in options.keys():
		if typeof(key) != TYPE_STRING or not ["flight_mode", "initial_guess", "tolerance"].has(key):
			return _failure("hover-trim options contain an unknown field", 0)
	var flight_mode: String = str(options.get("flight_mode", "normal"))
	var initial_guess: PackedFloat64Array = _as_f64(options.get("initial_guess", hover_seed(context, yaw)))
	var tolerance: float = float(options.get("tolerance", 1.0e-10))
	if not _input_valid(context, flight_mode, yaw, position_ned, wind_ned_m_s, initial_guess, tolerance):
		return _failure("invalid hover-trim arguments", 0)
	var x: PackedFloat64Array = initial_guess.duplicate()
	var evaluated: Dictionary = _evaluate(x, context, flight_mode, yaw, position_ned, wind_ned_m_s)
	if not evaluated.ok:
		return _failure("initial hover-trim state refused: " + str(evaluated.get("message", "invalid state")), 0)
	var residual: PackedFloat64Array = _scaled_residual(evaluated, context)
	var residual_norm: float = _norm(residual)
	if not is_finite(residual_norm):
		return _failure("initial hover-trim residual is nonfinite", 0)
	var iterations: int = 0
	while iterations < MAX_ITERATIONS and residual_norm > tolerance:
		iterations += 1
		var jacobian: Array = []
		for row: int in range(10):
			jacobian.append(PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]))
		for column: int in range(10):
			var step: float = 1.0e-6 * maxf(1.0, absf(x[column]))
			var probe: PackedFloat64Array = x.duplicate()
			probe[column] += step
			var direction: float = 1.0
			if not _unknowns_valid(probe, context):
				probe[column] = x[column] - step
				direction = -1.0
			if not _unknowns_valid(probe, context):
				return _failure("hover trim reached an unknown's physical boundary", iterations)
			var probe_result: Dictionary = _evaluate(probe, context, flight_mode, yaw, position_ned, wind_ned_m_s)
			if not probe_result.ok:
				return _failure("hover-trim Jacobian evaluation refused: " + str(probe_result.get("message", "invalid probe")), iterations)
			var probe_residual: PackedFloat64Array = _scaled_residual(probe_result, context)
			for row: int in range(10):
				jacobian[row][column] = (probe_residual[row] - residual[row]) / (direction * step)
		var rhs: PackedFloat64Array = PackedFloat64Array()
		for value: float in residual:
			rhs.append(-value)
		var correction: PackedFloat64Array = solve_linear(jacobian, rhs)
		if correction.size() != 10:
			return _failure("hover-trim Jacobian is singular", iterations)
		var accepted: bool = false
		var scale: float = 1.0
		for search: int in range(14):
			var candidate: PackedFloat64Array = x.duplicate()
			for index: int in range(10):
				candidate[index] += scale * correction[index]
			if _unknowns_valid(candidate, context):
				var candidate_result: Dictionary = _evaluate(candidate, context, flight_mode, yaw, position_ned, wind_ned_m_s)
				if candidate_result.ok:
					var candidate_residual: PackedFloat64Array = _scaled_residual(candidate_result, context)
					var candidate_norm: float = _norm(candidate_residual)
					if is_finite(candidate_norm) and candidate_norm < residual_norm:
						x = candidate
						evaluated = candidate_result
						residual = candidate_residual
						residual_norm = candidate_norm
						accepted = true
						break
			scale *= 0.5
		if not accepted:
			var failed_search: Dictionary = _failure("hover trim line search could not reduce the full-force residual", iterations)
			failed_search["unknowns"] = x
			failed_search["residual_components"] = residual
			failed_search["residual_norm"] = residual_norm
			failed_search["correction"] = correction
			return failed_search
	if residual_norm > tolerance:
		return _failure("hover trim did not converge (scaled residual %.6g)" % residual_norm, iterations)
	if not evaluated.aero.main_rotor.get("within_small_flap_angle_range", false):
		return _failure("hover trim lies outside the identified small-flap range", iterations)
	var final_state: PackedFloat64Array = evaluated.state
	var trim: Dictionary = {
		"roll_reference_rad": x[0],
		"pitch_reference_rad": x[1],
		"cyclic_forward_bias_rad": evaluated.result.controls.cyclic_forward_rad,
		"cyclic_right_bias_rad": evaluated.result.controls.cyclic_right_rad,
		"tail_collective_bias_rad": x[4],
	}
	return {"ok": true, "message": "trimmed airborne hover", "state": final_state,
		"sticks": evaluated.sticks, "controls": evaluated.result.controls, "trim": trim,
		"residual": residual_norm, "residual_components": residual,
		"iterations": iterations, "evaluation": evaluated.result,
		"rotor_speed_rad_s": final_state[Flight.OMEGA],
		"collective_75_rad": evaluated.result.controls.collective_75_rad,
		"cyclic_forward_rad": evaluated.result.controls.cyclic_forward_rad,
		"cyclic_right_rad": evaluated.result.controls.cyclic_right_rad,
		"tail_collective_rad": evaluated.result.controls.tail_collective_rad}


## Aircraft-data-seeded start for a solver caller. The zero stick/flap/inflow
## values are numerical initial guesses only; all physical parameters come from context.
static func hover_seed(context: Dictionary, yaw: float = 0.0) -> PackedFloat64Array:
	var state: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	state[9] = context.drive_model.governor_target_main_rad_s
	return state


static func _evaluate(x: PackedFloat64Array, context: Dictionary, flight_mode: String,
		yaw: float, position_ned: PackedFloat64Array, wind_ned_m_s: PackedFloat64Array) -> Dictionary:
	var attitude: PackedFloat64Array = M.q_from_euler(yaw, x[1], x[0])
	var velocity_body: PackedFloat64Array = M.q_rotate(M.q_conj(attitude), wind_ned_m_s)
	var body: PackedFloat64Array = RB.make_state(position_ned, velocity_body, attitude, M.v3(0.0, 0.0, 0.0))
	body.append_array(PackedFloat64Array([x[9], x[6], x[7], x[8], yaw, 0.0]))
	var sticks: PackedFloat64Array = PackedFloat64Array([x[2], x[3], 0.0, x[5]])
	var trim_offsets: Dictionary = {"tail_collective_bias_rad": x[4]}
	var result: Dictionary = Flight.evaluate(body, context, sticks, flight_mode, false, false,
		wind_ned_m_s, true, PackedFloat64Array(), trim_offsets)
	if not result.ok:
		return {"ok": false, "message": str(result.get("message", "flight equations refused trim probe"))}
	return {"ok": true, "state": body, "sticks": sticks, "result": result, "aero": result.aero}


static func _scaled_residual(evaluation: Dictionary, context: Dictionary) -> PackedFloat64Array:
	var body: PackedFloat64Array = evaluation.result.body_derivative
	var continuous: PackedFloat64Array = evaluation.result.derivative
	var g: float = maxf(context.gravity_m_s2, 1.0)
	var radius: float = context.main_model.rotor_radius_m
	var angular_scale: float = g / radius
	var omega_scale: float = context.drive_model.governor_target_main_rad_s
	var rho: float = context.main_model.rho_kg_m3
	var disk_area: float = PI * radius * radius
	var hover_velocity: float = M.sqrt_(context.mass_kg * g / (2.0 * rho * disk_area))
	var inflow_scale: float = hover_velocity * hover_velocity / radius
	return PackedFloat64Array([
		body[RB.VEL] / g,
		body[RB.VEL + 1] / g,
		body[RB.VEL + 2] / g,
		body[RB.RATE] / angular_scale,
		body[RB.RATE + 1] / angular_scale,
		body[RB.RATE + 2] / angular_scale,
		continuous[0] / (omega_scale * omega_scale),
		continuous[1] / omega_scale,
		continuous[2] / omega_scale,
		continuous[3] / inflow_scale,
	])


static func _unknowns_valid(x: PackedFloat64Array, context: Dictionary) -> bool:
	if x.size() != 10:
		return false
	for value: float in x:
		if not is_finite(value):
			return false
	if absf(x[0]) >= PI / 2.0 or absf(x[1]) >= PI / 2.0:
		return false
	if absf(x[2]) > 1.0 or absf(x[3]) > 1.0 or absf(x[5]) > 1.0:
		return false
	var tail_bias_min: float = context.electronics_model.tail_collective_min_rad \
		- context.electronics_model.tail_collective_trim_rad
	var tail_bias_max: float = context.electronics_model.tail_collective_max_rad \
		- context.electronics_model.tail_collective_trim_rad
	if x[4] < tail_bias_min or x[4] > tail_bias_max:
		return false
	if absf(x[6]) >= PI / 2.0 or absf(x[7]) >= PI / 2.0 or x[9] <= 0.0:
		return false
	return true


## Partial-pivoting Gaussian elimination for the bounded ten-equation hover trim.
static func solve_linear(matrix: Array, rhs: PackedFloat64Array) -> PackedFloat64Array:
	var n: int = rhs.size()
	if n == 0 or matrix.size() != n:
		return PackedFloat64Array()
	var a: Array = []
	var b: PackedFloat64Array = rhs.duplicate()
	for row: int in range(n):
		if matrix[row].size() != n:
			return PackedFloat64Array()
		a.append(matrix[row].duplicate())
	for column: int in range(n):
		var pivot: int = column
		for row: int in range(column + 1, n):
			if absf(a[row][column]) > absf(a[pivot][column]):
				pivot = row
		if not is_finite(a[pivot][column]) or absf(a[pivot][column]) <= 1.0e-14:
			return PackedFloat64Array()
		if pivot != column:
			var row_swap: Variant = a[pivot]
			a[pivot] = a[column]
			a[column] = row_swap
			var value_swap: float = b[pivot]
			b[pivot] = b[column]
			b[column] = value_swap
		for row: int in range(column + 1, n):
			var factor: float = a[row][column] / a[column][column]
			for k: int in range(column, n):
				a[row][k] -= factor * a[column][k]
			b[row] -= factor * b[column]
	var solution: PackedFloat64Array = PackedFloat64Array()
	solution.resize(n)
	for row: int in range(n - 1, -1, -1):
		var sum: float = b[row]
		for column: int in range(row + 1, n):
			sum -= a[row][column] * solution[column]
		solution[row] = sum / a[row][row]
		if not is_finite(solution[row]):
			return PackedFloat64Array()
	return solution


static func _norm(values: PackedFloat64Array) -> float:
	var total: float = 0.0
	for value: float in values:
		total += value * value
	return M.sqrt_(total)


static func _as_f64(value: Variant) -> PackedFloat64Array:
	if typeof(value) == TYPE_PACKED_FLOAT64_ARRAY:
		return value.duplicate()
	if typeof(value) == TYPE_ARRAY:
		return PackedFloat64Array(value)
	return PackedFloat64Array()


static func _input_valid(context: Dictionary, flight_mode: String, yaw: float,
		position: PackedFloat64Array, wind: PackedFloat64Array,
		guess: PackedFloat64Array, tolerance: float) -> bool:
	if not context.is_read_only() or context.get("law") != "openrc-helicopter-flight-dynamics-v1" \
			or flight_mode.is_empty() or position.size() != 3 or wind.size() != 3 \
			or guess.size() != 10 or not is_finite(yaw) or not is_finite(tolerance) or tolerance <= 0.0:
		return false
	for values: PackedFloat64Array in [position, wind, guess]:
		for value: float in values:
			if not is_finite(value):
				return false
	return _unknowns_valid(guess, context)


static func _failure(message: String, iterations: int) -> Dictionary:
	return {"ok": false, "message": message, "iterations": iterations, "state": PackedFloat64Array(),
		"sticks": PackedFloat64Array(), "residual": NAN}

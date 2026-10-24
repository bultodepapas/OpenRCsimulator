# Trim solver: steady, wings-level, straight flight on the REAL simulation equations (D4, six-axis since D5).
# Newton–Raphson, finite-difference Jacobian, Gaussian elimination with partial pivoting. 64-bit only (guarded).
# Unknowns x = [alpha, elevator, X, beta, aileron, rudder] with residuals = all six accelerations
#   level: X = throttle (0…1); engine rpm = its steady value (lag target, or the shaft torque balance at the trimmed
#   airspeed); the prop's torque is trimmed out by aileron/rudder.
#   glide: X = flight-path angle gamma; engine stopped.
# Surfaces in the data conventions (rad; elevator and ailerons +TE down, rudder +TE left; aileron is antisymmetric:
# right = +aileron, left = −aileron). Results also give the pilot-side trims (−1…1), as on a radio.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Air := preload("res://physics/air_data.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const FixedDatum := preload("res://physics/fixed_datum_body.gd")

const N := 6


## Trimmed state: airspeed V, angle of attack alpha, sideslip beta, path angle gamma, heading yaw, wings level.
static func state_for(V: float, alpha: float, gamma: float, yaw: float, pos_ned: PackedFloat64Array, beta := 0.0) -> PackedFloat64Array:
	var u := V * M.cos_(alpha) * M.cos_(beta)
	var v := V * M.sin_(beta)
	var w := V * M.sin_(alpha) * M.cos_(beta)
	return RB.make_state(pos_ned, M.v3(u, v, w), M.q_from_euler(yaw, gamma + alpha, 0.0), M.v3(0, 0, 0))


static func _deflections(x: PackedFloat64Array) -> Dictionary:
	return { elevator = x[1], aileron_right = x[4], aileron_left = -x[4], rudder = x[5] }


## Shared loads/derivative and state for unknowns x. Unknown control angles remain in Aero's data convention.
static func _evaluate(x: PackedFloat64Array, mode: String, V: float, model: Dictionary, g: float, rho: float, engine_charge_ratio: float) -> Dictionary:
	var gamma := 0.0 if mode == "level" else x[2]
	var s := state_for(V, x[0], gamma, 0.0, M.v3(0, 0, -100), x[3])
	var throttle := x[2] if mode == "level" else 0.0
	var rpm := _rpm(throttle, s, mode, model, rho, engine_charge_ratio)
	var result: Dictionary = Dynamics.evaluate(s, model, _deflections(x), rpm, rho, M.v3(0, 0, 0), g)
	if Propulsion.is_electric(model.propulsion):
		result["rpm"] = rpm
	# A session may freeze its launch inventory for a static trim query. The original
	# geometry stays at O; only the force moment and derivative move to the live CM.
	if model.has("trim_mass_properties"):
		var properties: Dictionary = model.trim_mass_properties
		var force: PackedFloat64Array = result.loads.slice(0, 3)
		var moment: PackedFloat64Array = M.sub(result.loads.slice(3, 6), M.cross(properties.cg_body_m, force))
		result.derivative = FixedDatum.derivative(s, properties, force, moment, g, result.rotor_momentum)
	return result


## Steady engine rpm in the trimmed state: the lag model's target, or the shaft model's torque balance at the
## state's axial airspeed (calm air). 0 in a glide (engine stopped).
static func _rpm(throttle: float, s: PackedFloat64Array, mode: String, model: Dictionary, rho: float, engine_charge_ratio: float) -> float:
	if mode != "level":
		return 0.0
	var u := M.dot(M.v3(s[RB.VEL], s[RB.VEL + 1], s[RB.VEL + 2]), Propulsion.axis(model.propulsion))
	return Propulsion.steady_rpm(throttle, u, model.propulsion, rho, engine_charge_ratio)


static func _residual(x: PackedFloat64Array, mode: String, V: float, model: Dictionary, g: float, rho: float, engine_charge_ratio: float) -> PackedFloat64Array:
	var e := _evaluate(x, mode, V, model, g, rho, engine_charge_ratio)
	var dot: PackedFloat64Array = e.derivative
	return PackedFloat64Array([dot[RB.VEL], dot[RB.VEL + 2], dot[RB.RATE + 1], dot[RB.VEL + 1], dot[RB.RATE], dot[RB.RATE + 2]])


## throws: { elevator, aileron, rudder } maximum deflections in radians.
## Returns { ok, message, mode, V, alpha, beta, gamma, throttle, thrust, rpm, elevator, aileron, rudder,
##           pitch_command, roll_command, yaw_command, state, residual, iterations }.
## Requires a structurally valid loader model. Numerical failures keep these keys, with unavailable values NaN.
## `initial` (D6e-R3): an optional six-value warm start [alpha, elevator, X, beta, aileron, rudder], tried before the
## standard guesses; a nearby converged trim (the previous speed of a sweep) saves most Newton iterations.
static func solve(mode: String, V: float, model: Dictionary, g: float, throws: Dictionary, rho: float = Air.RHO_SEA_LEVEL, engine_charge_ratio: float = 1.0, initial: PackedFloat64Array = PackedFloat64Array()) -> Dictionary:
	if mode != "level" and mode != "glide":
		return _numerical_failure("unsupported trim mode", mode, V, 0)
	if not is_finite(V) or V <= 0.0 or not is_finite(g) or g < 0.0:
		return _numerical_failure("trim needs finite positive speed and finite nonnegative gravity", mode, V, 0)
	if not is_finite(rho) or rho <= 0.0:
		return _numerical_failure("trim needs finite positive air density", mode, V, 0)
	if not is_finite(engine_charge_ratio) or engine_charge_ratio < 0.0:
		return _numerical_failure("trim needs a finite nonnegative engine charge ratio", mode, V, 0)
	for axis in ["elevator", "aileron", "rudder"]:
		var limit: Variant = throws.get(axis)
		if (typeof(limit) != TYPE_FLOAT and typeof(limit) != TYPE_INT) or not is_finite(limit) or limit <= 0.0:
			return _numerical_failure("trim needs a finite positive " + axis + " throw", mode, V, 0)
	var warm: bool = initial.size() == N and _all_finite(initial) and (mode != "level" or (initial[2] >= 0.0 and initial[2] <= 1.0))
	if Propulsion.is_electric(model.propulsion):
		var electric_result: Dictionary = {}
		if warm:
			electric_result = _solve_electric_from(mode, V, model, g, throws, initial[2], rho, initial)
			if electric_result.ok:
				return electric_result
		for guess in [0.2, 0.5, 0.8]:
			electric_result = _solve_electric_from(mode, V, model, g, throws, guess, rho)
			if electric_result.ok:
				return electric_result
		return electric_result
	# A large low-pitch propeller windmills at part throttle when V is near its pitch speed; there the thrust falls
	# with rpm and Newton walks the throttle below zero (P-51 1/4, 26x12 four-blade at 27 m/s). Retrying from higher
	# throttle guesses only after a failure keeps every previously converging trim bit-identical.
	var result := {}
	if warm:
		result = _solve_from(mode, V, model, g, throws, initial[2], rho, engine_charge_ratio, initial)
		if result.ok:
			return result
	for guess in ([0.4, 0.75, 0.95] if mode == "level" else [-0.1]):
		result = _solve_from(mode, V, model, g, throws, guess, rho, engine_charge_ratio)
		if result.ok:
			return result
	return result


static func _solve_from(mode: String, V: float, model: Dictionary, g: float, throws: Dictionary, x2: float, rho: float, engine_charge_ratio: float, x0: PackedFloat64Array = PackedFloat64Array()) -> Dictionary:
	var x := x0.duplicate() if x0.size() == N else PackedFloat64Array([0.05, -0.05, x2, 0.0, 0.0, 0.0])
	var bounded_glow_level: bool = mode == "level" and Propulsion.is_glow(model.propulsion)
	var r := _residual(x, mode, V, model, g, rho, engine_charge_ratio)
	var iterations := 0
	var residual_norm: float = _norm(r)
	if not is_finite(residual_norm):
		return _numerical_failure("nonfinite initial trim residual", mode, V, iterations)
	while iterations < 50 and residual_norm > 1e-10:
		iterations += 1
		var jac := [] # jac[i][k] = ∂r_i/∂x_k
		for i in N:
			jac.append(PackedFloat64Array([0, 0, 0, 0, 0, 0]))
		for k in N:
			var h := 1e-7 * maxf(1.0, absf(x[k]))
			var direction: float = 1.0
			if bounded_glow_level and k == 2 and x[k] + h > 1.0:
				direction = -1.0
			var xp := x.duplicate()
			xp[k] += direction * h
			var rp := _residual(xp, mode, V, model, g, rho, engine_charge_ratio)
			if not _all_finite(rp):
				return _numerical_failure("nonfinite perturbed trim residual", mode, V, iterations)
			for i in N:
				jac[i][k] = (rp[i] - r[i]) / (direction * h)
		var neg := PackedFloat64Array()
		for i in N:
			neg.append(-r[i])
		var dx := solve_linear(jac, neg)
		if dx.is_empty():
			return _numerical_failure("singular or nonfinite Jacobian (no trim near this condition)", mode, V, iterations)
		if bounded_glow_level:
			var step_scale: float = 1.0
			var bound := NAN # the throttle limit a full bounded step lands on exactly
			if dx[2] > 0.0 and x[2] + dx[2] > 1.0:
				step_scale = (1.0 - x[2]) / dx[2]
				bound = 1.0
			elif dx[2] < 0.0 and x[2] + dx[2] < 0.0:
				step_scale = (0.0 - x[2]) / dx[2]
				bound = 0.0
			step_scale = clampf(step_scale, 0.0, 1.0)
			var bounded_scale: float = step_scale
			var accepted_step: bool = false
			while step_scale >= 1e-8:
				var candidate: PackedFloat64Array = x.duplicate()
				for k in N:
					candidate[k] += step_scale * dx[k]
				if not is_nan(bound) and step_scale == bounded_scale:
					candidate[2] = bound # x + ((b - x)/dx)·dx is not b in floating point
				if candidate[2] >= 0.0 and candidate[2] <= 1.0 and _all_finite(candidate):
					var candidate_residual: PackedFloat64Array = _residual(candidate, mode, V, model, g, rho, engine_charge_ratio)
					var candidate_norm: float = _norm(candidate_residual)
					# Accept only a decreasing step; otherwise halve it (the residual must stay the iterate's own).
					if is_finite(candidate_norm) and candidate_norm < residual_norm:
						x = candidate
						r = candidate_residual
						residual_norm = candidate_norm
						accepted_step = true
						break
				step_scale *= 0.5
			if not accepted_step:
				return _result(false, "glow trim stalled: no finite residual-decreasing step within throttle [0,1]", x, mode, V, r, iterations, throws, model, g, rho, engine_charge_ratio)
			continue
		for k in N:
			x[k] += dx[k]
		if not _all_finite(x):
			return _numerical_failure("nonfinite Newton iterate", mode, V, iterations)
		r = _residual(x, mode, V, model, g, rho, engine_charge_ratio)
		residual_norm = _norm(r)
		if not is_finite(residual_norm):
			return _numerical_failure("nonfinite iterated trim residual", mode, V, iterations)
	if residual_norm > 1e-8:
		return _result(false, "did not converge (|residual| %s)" % String.num_scientific(residual_norm), x, mode, V, r, iterations, throws, model, g, rho, engine_charge_ratio)
	for check in [[x[1], throws.elevator, "elevator"], [x[4], throws.aileron, "aileron"], [x[5], throws.rudder, "rudder"]]:
		if absf(check[0]) > check[1]:
			return _result(false, "needs %.1f° of %s, more than the %.1f° throw" % [rad_to_deg(absf(check[0])), check[2], rad_to_deg(check[1])], x, mode, V, r, iterations, throws, model, g, rho, engine_charge_ratio)
	if mode == "level" and (x[2] < 0.0 or x[2] > 1.0):
		return _result(false, "needs throttle %.2f, outside 0…1" % x[2], x, mode, V, r, iterations, throws, model, g, rho, engine_charge_ratio)
	return _result(true, "trimmed", x, mode, V, r, iterations, throws, model, g, rho, engine_charge_ratio)


## Electric trim uses the same six-axis equations, with structured source failures and bounded duty probes.
## Non-electric trim continues through the source propulsion's steady-RPM path.
static func _solve_electric_from(mode: String, V: float, model: Dictionary, g: float, throws: Dictionary,
		duty_guess: float, rho: float, x0: PackedFloat64Array = PackedFloat64Array()) -> Dictionary:
	var x := x0.duplicate() if x0.size() == N else PackedFloat64Array([0.05, -0.05, duty_guess, 0.0, 0.0, 0.0])
	var evaluation: Dictionary = _evaluate_electric(x, mode, V, model, g, rho)
	if not evaluation.get("ok", false):
		return _numerical_failure("electric trim source equilibrium: " + str(evaluation.get("message", "failed")), mode, V, 0)
	var r: PackedFloat64Array = _residual_from_evaluation(evaluation)
	var iterations: int = 0
	var residual_norm: float = _norm(r)
	if not is_finite(residual_norm):
		return _numerical_failure("nonfinite initial electric trim residual", mode, V, iterations)
	while iterations < 50 and residual_norm > 1e-10:
		iterations += 1
		var jac: Array = []
		for i in N:
			jac.append(PackedFloat64Array([0, 0, 0, 0, 0, 0]))
		for k in N:
			var h: float = 1e-7 * maxf(1.0, absf(x[k]))
			var direction: float = 1.0
			if mode == "level" and k == 2 and x[k] + h > 1.0:
				direction = -1.0
			var xp: PackedFloat64Array = x.duplicate()
			xp[k] += direction * h
			if mode == "level" and k == 2 and (xp[k] < 0.0 or xp[k] > 1.0):
				return _numerical_failure("electric trim duty reached its [0,1] boundary", mode, V, iterations)
			var perturbed: Dictionary = _evaluate_electric_perturbation(
				x, xp, evaluation, mode, V, model, g, rho)
			if not perturbed.get("ok", false):
				return _numerical_failure("electric trim source equilibrium at a Jacobian probe: " + str(perturbed.get("message", "failed")), mode, V, iterations)
			var rp: PackedFloat64Array = _residual_from_evaluation(perturbed)
			if not _all_finite(rp):
				return _numerical_failure("nonfinite perturbed electric trim residual", mode, V, iterations)
			for i in N:
				jac[i][k] = (rp[i] - r[i]) / (direction * h)
		var neg := PackedFloat64Array()
		for i in N:
			neg.append(-r[i])
		var dx: PackedFloat64Array = solve_linear(jac, neg)
		if dx.is_empty():
			return _numerical_failure("singular or nonfinite electric trim Jacobian (no trim near this condition)", mode, V, iterations)
		if mode == "level" and ((x[2] >= 1.0 and dx[2] > 0.0) or (x[2] <= 0.0 and dx[2] < 0.0)):
			var boundary_message: String = "needs throttle %.3f, outside 0…1" % (x[2] + dx[2])
			return _result(false, boundary_message, x, mode, V, r, iterations, throws, model, g, rho, 1.0)
		var step_scale: float = 1.0
		if mode == "level" and x[2] + dx[2] > 1.0:
			step_scale = (1.0 - x[2]) / dx[2]
		elif mode == "level" and x[2] + dx[2] < 0.0:
			step_scale = (0.0 - x[2]) / dx[2]
		step_scale = clampf(step_scale, 0.0, 1.0)
		for k in N:
			x[k] += dx[k] * step_scale
		if not _all_finite(x):
			return _numerical_failure("nonfinite electric Newton iterate", mode, V, iterations)
		evaluation = _evaluate_electric(x, mode, V, model, g, rho)
		if not evaluation.get("ok", false):
			return _numerical_failure("electric trim source equilibrium: " + str(evaluation.get("message", "failed")), mode, V, iterations)
		r = _residual_from_evaluation(evaluation)
		residual_norm = _norm(r)
		if not is_finite(residual_norm):
			return _numerical_failure("nonfinite iterated electric trim residual", mode, V, iterations)
	if residual_norm > 1e-8:
		return _result(false, "did not converge (|residual| %s)" % String.num_scientific(residual_norm), x, mode, V, r, iterations, throws, model, g, rho, 1.0)
	for check in [[x[1], throws.elevator, "elevator"], [x[4], throws.aileron, "aileron"], [x[5], throws.rudder, "rudder"]]:
		if absf(check[0]) > check[1]:
			return _result(false, "needs %.1f° of %s, more than the %.1f° throw" % [rad_to_deg(absf(check[0])), check[2], rad_to_deg(check[1])], x, mode, V, r, iterations, throws, model, g, rho, 1.0)
	if mode == "level" and (x[2] < 0.0 or x[2] > 1.0):
		return _result(false, "needs throttle %.2f, outside 0…1" % x[2], x, mode, V, r, iterations, throws, model, g, rho, 1.0)
	return _result(true, "trimmed", x, mode, V, r, iterations, throws, model, g, rho, 1.0)


static func _evaluate_electric(x: PackedFloat64Array, mode: String, V: float, model: Dictionary,
		g: float, rho: float, reused_rpm := NAN) -> Dictionary:
	var gamma: float = 0.0 if mode == "level" else x[2]
	var state: PackedFloat64Array = state_for(V, x[0], gamma, 0.0, M.v3(0, 0, -100), x[3])
	var throttle: float = x[2] if mode == "level" else 0.0
	var rpm: float = 0.0
	if mode == "level":
		if is_finite(float(reused_rpm)):
			rpm = float(reused_rpm)
		else:
			var velocity: PackedFloat64Array = M.v3(state[RB.VEL], state[RB.VEL + 1], state[RB.VEL + 2])
			var u: float = M.dot(velocity, Propulsion.axis(model.propulsion))
			var operating_point: Dictionary = Propulsion.steady_operating_point(throttle, u, model.propulsion, rho)
			if not operating_point.get("ok", false):
				return {ok = false, message = str(operating_point.get("message", "no stable electric equilibrium")), operating_point = operating_point}
			rpm = float(operating_point.rpm)
	var result: Dictionary = Dynamics.evaluate(state, model, _deflections(x), rpm, rho, M.v3(0, 0, 0), g)
	result["ok"] = true
	result["rpm"] = rpm
	return result


## A level trim's equilibrium RPM depends on alpha, duty, sideslip, speed, propeller and density.
## Elevator, aileron and rudder perturbations leave those inputs unchanged, so their Jacobian probes
## reuse the current equilibrium while evaluating the changed aerodynamic controls normally.
static func _evaluate_electric_perturbation(base_x: PackedFloat64Array, perturbed_x: PackedFloat64Array,
		base_evaluation: Dictionary, mode: String, V: float, model: Dictionary, g: float, rho: float) -> Dictionary:
	var reused_rpm: float = NAN
	if _same_electric_steady_point_inputs(base_x, perturbed_x, mode) \
			and base_evaluation.get("ok", false) and base_evaluation.has("rpm") \
			and is_finite(float(base_evaluation.rpm)):
		reused_rpm = float(base_evaluation.rpm)
	return _evaluate_electric(perturbed_x, mode, V, model, g, rho, reused_rpm)


static func _same_electric_steady_point_inputs(base_x: PackedFloat64Array, candidate_x: PackedFloat64Array,
		mode: String) -> bool:
	return mode == "level" and base_x.size() == N and candidate_x.size() == N \
		and base_x[0] == candidate_x[0] and base_x[2] == candidate_x[2] and base_x[3] == candidate_x[3]


static func _residual_from_evaluation(evaluation: Dictionary) -> PackedFloat64Array:
	var dot: PackedFloat64Array = evaluation.derivative
	return PackedFloat64Array([dot[RB.VEL], dot[RB.VEL + 2], dot[RB.RATE + 1], dot[RB.VEL + 1], dot[RB.RATE], dot[RB.RATE + 2]])


static func _result(ok: bool, message: String, x: PackedFloat64Array, mode: String, V: float, r: PackedFloat64Array, iterations: int, throws: Dictionary, model: Dictionary, g: float, rho: float, engine_charge_ratio: float) -> Dictionary:
	var gamma := 0.0 if mode == "level" else x[2]
	var throttle := x[2] if mode == "level" else 0.0
	var e := _evaluate(x, mode, V, model, g, rho, engine_charge_ratio)
	var rpm: float = float(e.rpm) if Propulsion.is_electric(model.propulsion) else _rpm(throttle, e.state, mode, model, rho, engine_charge_ratio)
	var thrust: float = e.propulsion_loads[0]
	var result: Dictionary = {
		ok = ok, message = message, mode = mode, V = V,
		alpha = x[0], beta = x[3], gamma = gamma, throttle = throttle, thrust = thrust, rpm = rpm,
		elevator = x[1], aileron = x[4], rudder = x[5],
		# Pilot side (input/commands.gd): +pitch = elevator TE up; +roll = right aileron TE up; +yaw = rudder TE right.
		pitch_command = -x[1] / throws.elevator,
		roll_command = -x[4] / throws.aileron,
		yaw_command = -x[5] / throws.rudder,
		state = e.state,
		residual = _norm(r), iterations = iterations,
	}
	if ok:
		for value in result.values():
			if typeof(value) == TYPE_FLOAT and not is_finite(value):
				return _numerical_failure("nonfinite trim result", mode, V, iterations)
		if not _all_finite(result.state):
			return _numerical_failure("nonfinite trim state", mode, V, iterations)
	return result


## Do not evaluate a failed numerical candidate again or divide by invalid throws to build its diagnostic.
## Scenario adapters read angles even on refusal, so retain the result shape without inventing a usable trim.
static func _numerical_failure(message: String, mode: String, V: float, iterations: int) -> Dictionary:
	return {
		ok = false, message = message, mode = mode, V = V,
		alpha = NAN, beta = NAN, gamma = NAN, throttle = NAN, thrust = NAN, rpm = NAN,
		elevator = NAN, aileron = NAN, rudder = NAN,
		pitch_command = NAN, roll_command = NAN, yaw_command = NAN,
		state = PackedFloat64Array(), residual = NAN, iterations = iterations,
	}


static func _all_finite(values: PackedFloat64Array) -> bool:
	for value in values:
		if not is_finite(value):
			return false
	return true


static func _norm(v: PackedFloat64Array) -> float:
	var acc := 0.0
	for x in v:
		acc += x * x
	return M.sqrt_(acc)


## Solve A·x = b (A as an Array of PackedFloat64Array rows) by Gaussian elimination with partial pivoting.
## Returns empty for a malformed, singular or nonfinite system, including arithmetic overflow.
static func solve_linear(a_in: Array, b_in: PackedFloat64Array) -> PackedFloat64Array:
	var n := b_in.size()
	if n == 0 or a_in.size() != n or not _all_finite(b_in):
		return PackedFloat64Array()
	var a := []
	for row in a_in:
		if typeof(row) != TYPE_PACKED_FLOAT64_ARRAY or row.size() != n or not _all_finite(row):
			return PackedFloat64Array()
		a.append((row as PackedFloat64Array).duplicate())
	var b := b_in.duplicate()
	for col in n:
		var pivot := col
		for row in range(col + 1, n):
			if absf(a[row][col]) > absf(a[pivot][col]):
				pivot = row
		if absf(a[pivot][col]) < 1e-14:
			return PackedFloat64Array()
		if pivot != col:
			var tmp = a[col]
			a[col] = a[pivot]
			a[pivot] = tmp
			var tb := b[col]
			b[col] = b[pivot]
			b[pivot] = tb
		for row in range(col + 1, n):
			var f: float = a[row][col] / a[col][col]
			if not is_finite(f):
				return PackedFloat64Array()
			for k in range(col, n):
				a[row][k] -= f * a[col][k]
				if not is_finite(a[row][k]):
					return PackedFloat64Array()
			b[row] -= f * b[col]
			if not is_finite(b[row]):
				return PackedFloat64Array()
	var x := PackedFloat64Array()
	x.resize(n)
	for i in range(n - 1, -1, -1):
		var acc := b[i]
		for k in range(i + 1, n):
			acc -= a[i][k] * x[k]
			if not is_finite(acc):
				return PackedFloat64Array()
		x[i] = acc / a[i][i]
		if not is_finite(x[i]):
			return PackedFloat64Array()
	return x

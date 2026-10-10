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
	return Dynamics.evaluate(s, model, _deflections(x), rpm, rho, M.v3(0, 0, 0), g)


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
static func solve(mode: String, V: float, model: Dictionary, g: float, throws: Dictionary, rho: float = Air.RHO_SEA_LEVEL, engine_charge_ratio: float = 1.0) -> Dictionary:
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
	# A large low-pitch propeller windmills at part throttle when V is near its pitch speed; there the thrust falls
	# with rpm and Newton walks the throttle below zero (P-51 1/4, 26x12 four-blade at 27 m/s). Retrying from higher
	# throttle guesses only after a failure keeps every previously converging trim bit-identical.
	var result := {}
	for guess in ([0.4, 0.75, 0.95] if mode == "level" else [-0.1]):
		result = _solve_from(mode, V, model, g, throws, guess, rho, engine_charge_ratio)
		if result.ok:
			return result
	return result


static func _solve_from(mode: String, V: float, model: Dictionary, g: float, throws: Dictionary, x2: float, rho: float, engine_charge_ratio: float) -> Dictionary:
	var x := PackedFloat64Array([0.05, -0.05, x2, 0.0, 0.0, 0.0])
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
			var xp := x.duplicate()
			xp[k] += h
			var rp := _residual(xp, mode, V, model, g, rho, engine_charge_ratio)
			if not _all_finite(rp):
				return _numerical_failure("nonfinite perturbed trim residual", mode, V, iterations)
			for i in N:
				jac[i][k] = (rp[i] - r[i]) / h
		var neg := PackedFloat64Array()
		for i in N:
			neg.append(-r[i])
		var dx := solve_linear(jac, neg)
		if dx.is_empty():
			return _numerical_failure("singular or nonfinite Jacobian (no trim near this condition)", mode, V, iterations)
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


static func _result(ok: bool, message: String, x: PackedFloat64Array, mode: String, V: float, r: PackedFloat64Array, iterations: int, throws: Dictionary, model: Dictionary, g: float, rho: float, engine_charge_ratio: float) -> Dictionary:
	var gamma := 0.0 if mode == "level" else x[2]
	var throttle := x[2] if mode == "level" else 0.0
	var e := _evaluate(x, mode, V, model, g, rho, engine_charge_ratio)
	var rpm := _rpm(throttle, e.state, mode, model, rho, engine_charge_ratio)
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

# Trim solver: steady, wings-level, straight flight on the REAL simulation equations (D4, six-axis since D5).
# Newton–Raphson, finite-difference Jacobian, Gaussian elimination with partial pivoting. 64-bit only (guarded).
# Unknowns x = [alpha, elevator, X, beta, aileron, rudder] with residuals = all six accelerations
#   level: X = throttle (0…1); engine rpm = its steady target; the prop's torque is trimmed out by aileron/rudder.
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
	var u := V * cos(alpha) * cos(beta)
	var v := V * sin(beta)
	var w := V * sin(alpha) * cos(beta)
	return RB.make_state(pos_ned, M.v3(u, v, w), M.q_from_euler(yaw, gamma + alpha, 0.0), M.v3(0, 0, 0))


static func _deflections(x: PackedFloat64Array) -> Dictionary:
	return { elevator = x[1], aileron_right = x[4], aileron_left = -x[4], rudder = x[5] }


## Shared loads/derivative and state for unknowns x. Unknown control angles remain in Aero's data convention.
static func _evaluate(x: PackedFloat64Array, mode: String, V: float, model: Dictionary, g: float) -> Dictionary:
	var gamma := 0.0 if mode == "level" else x[2]
	var s := state_for(V, x[0], gamma, 0.0, M.v3(0, 0, -100), x[3])
	var throttle := x[2] if mode == "level" else 0.0
	var rpm := Propulsion.target_rpm(throttle, model.propulsion) if mode == "level" else 0.0
	return Dynamics.evaluate(s, model, _deflections(x), rpm, Air.RHO_SEA_LEVEL, M.v3(0, 0, 0), g)


static func _residual(x: PackedFloat64Array, mode: String, V: float, model: Dictionary, g: float) -> PackedFloat64Array:
	var e := _evaluate(x, mode, V, model, g)
	var dot: PackedFloat64Array = e.derivative
	return PackedFloat64Array([dot[RB.VEL], dot[RB.VEL + 2], dot[RB.RATE + 1], dot[RB.VEL + 1], dot[RB.RATE], dot[RB.RATE + 2]])


## throws: { elevator, aileron, rudder } maximum deflections in radians.
## Returns { ok, message, mode, V, alpha, beta, gamma, throttle, thrust, rpm, elevator, aileron, rudder,
##           pitch_command, roll_command, yaw_command, state, residual, iterations }.
static func solve(mode: String, V: float, model: Dictionary, g: float, throws: Dictionary) -> Dictionary:
	assert(mode == "level" or mode == "glide")
	var x := PackedFloat64Array([0.05, -0.05, 0.4 if mode == "level" else -0.1, 0.0, 0.0, 0.0])
	var r := _residual(x, mode, V, model, g)
	var iterations := 0
	while iterations < 50 and _norm(r) > 1e-10:
		iterations += 1
		var jac := [] # jac[i][k] = ∂r_i/∂x_k
		for i in N:
			jac.append(PackedFloat64Array([0, 0, 0, 0, 0, 0]))
		for k in N:
			var h := 1e-7 * maxf(1.0, absf(x[k]))
			var xp := x.duplicate()
			xp[k] += h
			var rp := _residual(xp, mode, V, model, g)
			for i in N:
				jac[i][k] = (rp[i] - r[i]) / h
		var neg := PackedFloat64Array()
		for i in N:
			neg.append(-r[i])
		var dx := solve_linear(jac, neg)
		if dx.is_empty():
			return _result(false, "singular Jacobian (no trim near this condition)", x, mode, V, r, iterations, throws, model, g)
		for k in N:
			x[k] += dx[k]
		r = _residual(x, mode, V, model, g)
	if _norm(r) > 1e-8:
		return _result(false, "did not converge (|residual| %s)" % String.num_scientific(_norm(r)), x, mode, V, r, iterations, throws, model, g)
	for check in [[x[1], throws.elevator, "elevator"], [x[4], throws.aileron, "aileron"], [x[5], throws.rudder, "rudder"]]:
		if absf(check[0]) > check[1]:
			return _result(false, "needs %.1f° of %s, more than the %.1f° throw" % [rad_to_deg(absf(check[0])), check[2], rad_to_deg(check[1])], x, mode, V, r, iterations, throws, model, g)
	if mode == "level" and (x[2] < 0.0 or x[2] > 1.0):
		return _result(false, "needs throttle %.2f, outside 0…1" % x[2], x, mode, V, r, iterations, throws, model, g)
	return _result(true, "trimmed", x, mode, V, r, iterations, throws, model, g)


static func _result(ok: bool, message: String, x: PackedFloat64Array, mode: String, V: float, r: PackedFloat64Array, iterations: int, throws: Dictionary, model: Dictionary, g: float) -> Dictionary:
	var gamma := 0.0 if mode == "level" else x[2]
	var throttle := x[2] if mode == "level" else 0.0
	var e := _evaluate(x, mode, V, model, g)
	var rpm := Propulsion.target_rpm(throttle, model.propulsion) if mode == "level" else 0.0
	var thrust: float = e.propulsion_loads[0]
	return {
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


static func _norm(v: PackedFloat64Array) -> float:
	var acc := 0.0
	for x in v:
		acc += x * x
	return sqrt(acc)


## Solve A·x = b (A as an Array of PackedFloat64Array rows) by Gaussian elimination with partial pivoting.
## Returns an empty array when A is singular.
static func solve_linear(a_in: Array, b_in: PackedFloat64Array) -> PackedFloat64Array:
	var n := b_in.size()
	var a := []
	for row in a_in:
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
			for k in range(col, n):
				a[row][k] -= f * a[col][k]
			b[row] -= f * b[col]
	var x := PackedFloat64Array()
	x.resize(n)
	for i in range(n - 1, -1, -1):
		var acc := b[i]
		for k in range(i + 1, n):
			acc -= a[i][k] * x[k]
		x[i] = acc / a[i][i]
	return x

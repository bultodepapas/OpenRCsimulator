# Trim solver (D4): steady, wings-level, straight flight on the REAL simulation equations.
# Newton–Raphson with a finite-difference Jacobian on the rigid-body accelerations (u̇, ẇ, q̇), so the trim
# is consistent with the simulation by construction. 64-bit floats only (guarded).
#   level: unknowns [alpha, elevator, thrust] at flight-path angle 0
#   glide: unknowns [alpha, elevator, gamma] with zero thrust
# Elevator is in the data convention (rad, +TE down); pitch_command is the pilot-side value (−1…1).
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")


## The trimmed state: heading `yaw`, airspeed V along a path `gamma` above the horizon, at position pos_ned.
static func state_for(V: float, alpha: float, gamma: float, yaw: float, pos_ned: PackedFloat64Array) -> PackedFloat64Array:
	return RB.make_state(pos_ned, M.v3(V * cos(alpha), 0.0, V * sin(alpha)), M.q_from_euler(yaw, gamma + alpha, 0.0), M.v3(0, 0, 0))


## Accelerations [u̇, ẇ, q̇] for unknowns x in the given mode.
static func _residual(x: PackedFloat64Array, mode: String, V: float, model: Dictionary, g: float, j_inv: PackedFloat64Array) -> PackedFloat64Array:
	var alpha := x[0]
	var gamma := 0.0 if mode == "level" else x[2]
	var thrust := x[2] if mode == "level" else 0.0
	var s := state_for(V, alpha, gamma, 0.0, M.v3(0, 0, -100))
	var d := { elevator = x[1], aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0 }
	var l := Aero.loads(s, Air.compute(s, M.v3(0, 0, 0)), d, model, Air.RHO_SEA_LEVEL)
	var dot := RB.derivative(s, model.mass_kg, model.inertia, j_inv, M.v3(l[0] + thrust, l[1], l[2]), M.v3(l[3], l[4], l[5]), g)
	return PackedFloat64Array([dot[RB.VEL], dot[RB.VEL + 2], dot[RB.RATE + 1]])


## Returns { ok, message, alpha, elevator, pitch_command, thrust, gamma, state, residual, iterations }.
## max_elevator_rad: the elevator throw available; a trim needing more fails.
static func solve(mode: String, V: float, model: Dictionary, g: float, max_elevator_rad: float) -> Dictionary:
	assert(mode == "level" or mode == "glide")
	var j_inv := RB.inertia_inverse(model.inertia)
	var x := PackedFloat64Array([0.05, -0.05, 2.0 if mode == "level" else -0.1])
	var r := _residual(x, mode, V, model, g, j_inv)
	var iterations := 0
	while iterations < 50 and _norm(r) > 1e-10:
		iterations += 1
		var jac := []
		for k in 3:
			var h := 1e-7 * maxf(1.0, absf(x[k]))
			var xp := x.duplicate()
			xp[k] += h
			var rp := _residual(xp, mode, V, model, g, j_inv)
			jac.append(PackedFloat64Array([(rp[0] - r[0]) / h, (rp[1] - r[1]) / h, (rp[2] - r[2]) / h]))
		var dx := _solve3(jac, PackedFloat64Array([-r[0], -r[1], -r[2]]))
		if dx.is_empty():
			return _result(false, "singular Jacobian (no trim near this condition)", x, mode, V, r, iterations, max_elevator_rad)
		for k in 3:
			x[k] += dx[k]
		r = _residual(x, mode, V, model, g, j_inv)
	if _norm(r) > 1e-8:
		return _result(false, "did not converge (|residual| %s)" % String.num_scientific(_norm(r)), x, mode, V, r, iterations, max_elevator_rad)
	if absf(x[1]) > max_elevator_rad:
		return _result(false, "needs %.1f° of elevator, more than the %.1f° throw" % [rad_to_deg(absf(x[1])), rad_to_deg(max_elevator_rad)], x, mode, V, r, iterations, max_elevator_rad)
	if mode == "level" and x[2] < 0.0:
		return _result(false, "needs negative thrust (%.2f N)" % x[2], x, mode, V, r, iterations, max_elevator_rad)
	return _result(true, "trimmed", x, mode, V, r, iterations, max_elevator_rad)


static func _result(ok: bool, message: String, x: PackedFloat64Array, mode: String, V: float, r: PackedFloat64Array, iterations: int, max_elevator_rad: float) -> Dictionary:
	var gamma := 0.0 if mode == "level" else x[2]
	return {
		ok = ok, message = message, mode = mode, V = V,
		alpha = x[0], elevator = x[1],
		pitch_command = -x[1] / max_elevator_rad, # pilot side: +1 = full up (TE up)
		thrust = x[2] if mode == "level" else 0.0,
		gamma = gamma,
		state = state_for(V, x[0], gamma, 0.0, M.v3(0, 0, -100)),
		residual = _norm(r), iterations = iterations,
	}


static func _norm(v: PackedFloat64Array) -> float:
	return sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])


## Solve a 3×3 system (rows = Jacobian columns as computed: jac[k][i] = ∂r_i/∂x_k) by Cramer's rule.
static func _solve3(jac: Array, b: PackedFloat64Array) -> PackedFloat64Array:
	# A[i][k] = jac[k][i]
	var a00: float = jac[0][0]
	var a01: float = jac[1][0]
	var a02: float = jac[2][0]
	var a10: float = jac[0][1]
	var a11: float = jac[1][1]
	var a12: float = jac[2][1]
	var a20: float = jac[0][2]
	var a21: float = jac[1][2]
	var a22: float = jac[2][2]
	var det := a00 * (a11 * a22 - a12 * a21) - a01 * (a10 * a22 - a12 * a20) + a02 * (a10 * a21 - a11 * a20)
	if absf(det) < 1e-14:
		return PackedFloat64Array()
	var x0 := (b[0] * (a11 * a22 - a12 * a21) - a01 * (b[1] * a22 - a12 * b[2]) + a02 * (b[1] * a21 - a11 * b[2])) / det
	var x1 := (a00 * (b[1] * a22 - a12 * b[2]) - b[0] * (a10 * a22 - a12 * a20) + a02 * (a10 * b[2] - b[1] * a20)) / det
	var x2 := (a00 * (a11 * b[2] - b[1] * a21) - a01 * (a10 * b[2] - b[1] * a20) + b[0] * (a10 * a21 - a11 * a20)) / det
	return PackedFloat64Array([x0, x1, x2])

# SF-09: the generalized-coordinate kernel (physics/generalized_coordinates.gd) against known answers.
# A cart (base body) carrying a pendulum (one local coordinate) is assembled as body + local and integrated with
# the shared RK4: its energy is conserved and its small-amplitude period matches ω² = g (M + m) / (M l).
# The block factorization agrees with the dense inverse on random coupled matrices, and the point-mass
# assembly reproduces m·JᵀJ.
extends SceneTree

const GC := preload("res://physics/generalized_coordinates.gd")
const RK := preload("res://physics/integrator.gd")

const G := 9.80665
const CART_MASS := 2.0
const BOB_MASS := 0.5
const ROD := 0.8
const BODY := 6
const LOCALS := 1

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_cart_pendulum()
	_factor_against_dense()
	_point_mass_assembly()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


## Generalized coordinates: body x (index 0) and pendulum angle θ (local 0, index 6); the other body coordinates
## carry unit mass and no load. The integrator renormalizes the rigid-body attitude slot after each step, so the
## pendulum state [x, θ, ẋ, θ̇] rides in the first four entries of a 13-value vector whose attitude slot holds the
## identity quaternion (its norm is exactly 1, so renormalization leaves every value unchanged).
func _padded(x: float, theta: float, x_dot: float, theta_dot: float) -> PackedFloat64Array:
	return PackedFloat64Array([x, theta, x_dot, theta_dot, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])


func _cart_pendulum_derivative(s: PackedFloat64Array, _t: float) -> PackedFloat64Array:
	var theta: float = s[1]
	var theta_dot: float = s[3]
	var n := BODY + LOCALS
	var matrix := PackedFloat64Array()
	matrix.resize(n * n)
	for i in BODY:
		matrix[i * n + i] = 1.0
	matrix[0] = CART_MASS + BOB_MASS
	var coupling: float = BOB_MASS * ROD * cos(theta)
	matrix[0 * n + 6] = coupling
	matrix[6 * n + 0] = coupling
	matrix[6 * n + 6] = BOB_MASS * ROD * ROD
	var rhs := PackedFloat64Array()
	rhs.resize(n)
	rhs[0] = BOB_MASS * ROD * theta_dot * theta_dot * sin(theta) # centripetal term on the cart
	rhs[6] = -BOB_MASS * G * ROD * sin(theta) # gravity torque on the bob
	var factor: Dictionary = GC.factor_body_local(matrix, BODY, LOCALS)
	var acceleration: PackedFloat64Array = GC.solve_body_local(factor, rhs, BODY, LOCALS)
	return PackedFloat64Array([s[2], s[3], acceleration[0], acceleration[6], 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])


func _energy(s: PackedFloat64Array) -> float:
	var x_dot: float = s[2]
	var theta: float = s[1]
	var theta_dot: float = s[3]
	return 0.5 * (CART_MASS + BOB_MASS) * x_dot * x_dot + BOB_MASS * ROD * x_dot * theta_dot * cos(theta) \
		+ 0.5 * BOB_MASS * ROD * ROD * theta_dot * theta_dot - BOB_MASS * G * ROD * cos(theta)


func _cart_pendulum() -> void:
	var dt := 1.0 / 240.0
	var small := _padded(0.0, 0.01, 0.0, 0.0)
	var state := small.duplicate()
	var e0 := _energy(state)
	var drift := 0.0
	var crossings: Array[float] = []
	var previous_theta: float = state[1]
	var f := Callable(self, "_cart_pendulum_derivative")
	for tick in 2400:
		state = RK.rk4_step_at(state, tick * dt, dt, f)
		drift = maxf(drift, absf(_energy(state) - e0))
		if previous_theta > 0.0 and state[1] <= 0.0:
			crossings.append((tick + 1) * dt - state[1] / (state[1] - previous_theta) * dt)
		previous_theta = state[1]
	_check("cart–pendulum energy drifts below 1e-10 J over ten seconds", drift < 1e-10, "%s J" % String.num_scientific(drift))
	var omega := sqrt(G * (CART_MASS + BOB_MASS) / (CART_MASS * ROD))
	var expected_period := 2.0 * PI / omega
	_check("at least five downward crossings observed in ten seconds (period 1.6 s)", crossings.size() >= 5, str(crossings.size()))
	if crossings.size() >= 2:
		var period: float = (crossings[crossings.size() - 1] - crossings[0]) / float(crossings.size() - 1)
		_check("small-amplitude period matches ω² = g (M + m) / (M l) within 1e-4", absf(period - expected_period) / expected_period < 1e-4,
			"%.6f s vs %.6f s" % [period, expected_period])
	var momentum_before: float = (CART_MASS + BOB_MASS) * 0.0
	var large := _padded(0.0, 1.2, 0.0, 0.0)
	state = large
	var x_momentum_drift := 0.0
	for tick in 2400:
		state = RK.rk4_step_at(state, tick * dt, dt, f)
		var p: float = (CART_MASS + BOB_MASS) * state[2] + BOB_MASS * ROD * state[3] * cos(state[1])
		x_momentum_drift = maxf(x_momentum_drift, absf(p - momentum_before))
	# RK4 does not conserve momentum exactly; its truncation leaves nanoscale drift at 240 Hz against a 1 kg·m/s swing.
	_check("horizontal momentum is conserved through a large swing within RK4 truncation (1e-7 kg·m/s)", x_momentum_drift < 1e-7, String.num_scientific(x_momentum_drift))


func _factor_against_dense() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	var worst := 0.0
	for trial in 20:
		var body := 6
		var locals := 1 + trial % 8
		var n := body + locals
		var matrix := PackedFloat64Array()
		matrix.resize(n * n)
		# A symmetric positive-definite body block from a random Gram matrix, positive local masses and couplings.
		var a := PackedFloat64Array()
		a.resize(body * body)
		for i in body * body:
			a[i] = rng.randf_range(-1.0, 1.0)
		for r in body:
			for c in body:
				var v := 0.0
				for k in body:
					v += a[r * body + k] * a[c * body + k]
				matrix[r * n + c] = v + (6.0 if r == c else 0.0)
		for local in locals:
			var dof := body + local
			matrix[dof * n + dof] = rng.randf_range(0.5, 3.0)
			for b in body:
				var cpl := rng.randf_range(-0.3, 0.3)
				matrix[b * n + dof] = cpl
				matrix[dof * n + b] = cpl
		var rhs := PackedFloat64Array()
		rhs.resize(n)
		for i in n:
			rhs[i] = rng.randf_range(-10.0, 10.0)
		var factor: Dictionary = GC.factor_body_local(matrix, body, locals)
		var fast: PackedFloat64Array = GC.solve_body_local(factor, rhs, body, locals)
		var inverse: Dictionary = GC.invert(matrix, n)
		if not factor.ok or not inverse.ok or fast.size() != n:
			_check("factor and inverse succeed on trial %d" % trial, false)
			continue
		var dense: PackedFloat64Array = GC.matrix_vector(inverse.inverse, rhs, n)
		var residual: PackedFloat64Array = GC.matrix_vector(matrix, fast, n)
		for i in n:
			worst = maxf(worst, absf(fast[i] - dense[i]))
			worst = maxf(worst, absf(residual[i] - rhs[i]))
	_check("block factorization agrees with the dense inverse and satisfies M·a = rhs (20 random sizes 7…14) within 1e-9", worst < 1e-9, String.num_scientific(worst))
	var singular := PackedFloat64Array()
	singular.resize(49)
	for i in 7:
		singular[i * 7 + i] = 1.0
	singular[6 * 7 + 6] = 0.0
	_check("a zero local mass is refused", not GC.factor_body_local(singular, 6, 1).ok)


func _point_mass_assembly() -> void:
	var n := 7
	var jacobian := PackedFloat64Array()
	jacobian.resize(3 * n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 3 * n:
		jacobian[i] = rng.randf_range(-1.0, 1.0)
	var matrix := PackedFloat64Array()
	matrix.resize(n * n)
	var active := PackedInt64Array([0, 1, 2, 3, 4, 5, 6])
	GC.add_point_mass(matrix, jacobian, 1.7, n, active)
	var worst := 0.0
	var symmetric := true
	for r in n:
		for c in n:
			var expected := 0.0
			for axis in 3:
				expected += jacobian[axis * n + r] * jacobian[axis * n + c]
			expected *= 1.7
			worst = maxf(worst, absf(matrix[r * n + c] - expected))
			symmetric = symmetric and matrix[r * n + c] == matrix[c * n + r]
	_check("point-mass assembly reproduces m·JᵀJ exactly and symmetrically", worst == 0.0 and symmetric, String.num_scientific(worst))

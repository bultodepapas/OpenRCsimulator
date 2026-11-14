# DR-07 (foundation slice): bounded four-rotor control allocation, FPV/03 §2. The static quadratic-law effectiveness
# matrix B maps rotor thrusts f [N] to the wrench w = [Σ thrust, τ_roll, τ_pitch, τ_yaw] about the CG in FRD; column i
# is [1, −y_i, x_i, s_i·κ_i], which is exactly what multirotor/rotor.gd produces with zero air velocity, zero body rates
# and zero rotor acceleration (moment = hub × (0, 0, −T) plus spin·Q about body z, Q = κ·T). The allocator minimizes
# ||W(B·f − w_req)||² with W = diag(weight_r / scale_r) inside the per-rotor box f_min <= f <= f_max.
# Not modeled: rotor drag in-plane forces, rotor acceleration (inertial) yaw, inflow/advance-ratio changes of κ, motor
# or bus feasibility of the bounds (the caller supplies them), rate limits, lexicographic priorities and any penalty
# on changing motor requests. B·f is an allocation target, not a sensor or a complete dynamic plant.
extends RefCounted

const LAW := "multirotor-bounded-wls-allocator-v1"
## Refuse geometry whose weighted matrix W·B has an infinity-norm condition number above this.
const CONDITION_LIMIT := 1.0e8
## A Gauss-Jordan pivot below this fraction of the largest |W·B| entry marks rank deficiency.
const PIVOT_TOLERANCE := 1.0e-12
## Production active-set iteration cap; hitting it falls back to the 81-set reference.
const MAX_ITERATIONS := 16
## Relative tolerance of KKT multiplier signs and reference feasibility.
const KKT_TOLERANCE := 1.0e-12
const STATUS_LOWER := 0
const STATUS_FREE := 1
const STATUS_UPPER := 2


## rotors: Array of 4 Dictionaries {hub_frd: PackedFloat64Array[3], spin: float (+1/-1)} in rotor order.
## kappa_m: PackedFloat64Array[4], torque-to-thrust ratio k_Q/k_T per rotor [m].
## scales: PackedFloat64Array[4] characteristic row scales [N, N·m, N·m, N·m] (> 0).
## weights: PackedFloat64Array[4] dimensionless row weights [collective, roll, pitch, yaw] (> 0).
## Returns {ok, errors, b (row-major 4×4), b_inverse, scales, weights, condition}. Refuses rank-deficient or
## ill-conditioned geometry; `condition` is the infinity-norm condition number of W·B.
static func prepare(rotors: Array, kappa_m: PackedFloat64Array, scales: PackedFloat64Array,
		weights: PackedFloat64Array) -> Dictionary:
	var errors := PackedStringArray()
	if rotors.size() != 4:
		errors.append("rotors must hold exactly 4 entries")
	else:
		for i in 4:
			var rotor: Variant = rotors[i]
			if typeof(rotor) != TYPE_DICTIONARY:
				errors.append("rotor %d must be a dictionary" % i)
				continue
			var hub: Variant = rotor.get("hub_frd")
			if typeof(hub) != TYPE_PACKED_FLOAT64_ARRAY or hub.size() != 3 \
					or not is_finite(hub[0]) or not is_finite(hub[1]) or not is_finite(hub[2]):
				errors.append("rotor %d hub_frd must be a finite PackedFloat64Array[3]" % i)
			var spin: Variant = rotor.get("spin")
			if typeof(spin) not in [TYPE_FLOAT, TYPE_INT] or absf(float(spin)) != 1.0:
				errors.append("rotor %d spin must be +1 or -1" % i)
	if kappa_m.size() != 4:
		errors.append("kappa_m must hold 4 values")
	else:
		for i in 4:
			if not is_finite(kappa_m[i]) or kappa_m[i] <= 0.0:
				errors.append("kappa_m[%d] must be finite and > 0" % i)
	if scales.size() != 4:
		errors.append("scales must hold 4 values")
	else:
		for r in 4:
			if not is_finite(scales[r]) or scales[r] <= 0.0:
				errors.append("scales[%d] must be finite and > 0" % r)
	if weights.size() != 4:
		errors.append("weights must hold 4 values")
	else:
		for r in 4:
			if not is_finite(weights[r]) or weights[r] <= 0.0:
				errors.append("weights[%d] must be finite and > 0" % r)
	if not errors.is_empty():
		return {ok = false, errors = errors}

	var b := PackedFloat64Array()
	b.resize(16)
	for i in 4:
		var hub: PackedFloat64Array = rotors[i].hub_frd
		b[i] = 1.0
		b[4 + i] = -hub[1]
		b[8 + i] = hub[0]
		b[12 + i] = float(rotors[i].spin) * kappa_m[i]
	var w_diag := PackedFloat64Array()
	w_diag.resize(4)
	for r in 4:
		w_diag[r] = weights[r] / scales[r]
		if not is_finite(w_diag[r]) or w_diag[r] <= 0.0:
			errors.append("weights[%d]/scales[%d] is not a finite positive number" % [r, r])
	var a := PackedFloat64Array()
	a.resize(16)
	for r in 4:
		for i in 4:
			a[r * 4 + i] = w_diag[r] * b[r * 4 + i]
			if not is_finite(a[r * 4 + i]):
				errors.append("weighted matrix entry (%d,%d) is not finite" % [r, i])
	if not errors.is_empty():
		return {ok = false, errors = errors}
	var a_inverse: PackedFloat64Array = _invert4(a)
	if a_inverse.is_empty():
		errors.append("rotor geometry is rank deficient (W·B singular)")
		return {ok = false, errors = errors}
	var condition: float = _norm_inf(a) * _norm_inf(a_inverse)
	if not is_finite(condition) or condition > CONDITION_LIMIT:
		errors.append("rotor geometry is ill-conditioned: cond(W·B) = %s" % String.num_scientific(condition))
		return {ok = false, errors = errors, condition = condition}
	# B⁻¹ = (W·B)⁻¹·W; the weighted inverse is the better-scaled one to form.
	var b_inverse := PackedFloat64Array()
	b_inverse.resize(16)
	for i in 4:
		for r in 4:
			b_inverse[i * 4 + r] = a_inverse[i * 4 + r] * w_diag[r]
	# H = AᵀA for the production active-set normal equations.
	var h := PackedFloat64Array()
	h.resize(16)
	var h_norm: float = 0.0
	for i in 4:
		for j in 4:
			var sum: float = 0.0
			for r in 4:
				sum += a[r * 4 + i] * a[r * 4 + j]
			h[i * 4 + j] = sum
			h_norm = maxf(h_norm, absf(sum))
	return {
		ok = true,
		errors = errors,
		law = LAW,
		b = b,
		b_inverse = b_inverse,
		scales = scales.duplicate(),
		weights = weights.duplicate(),
		condition = condition,
		w_diag = w_diag,
		a = a,
		h = h,
		h_norm = h_norm,
	}


## wrench_req = [total thrust N (>= 0, along -z body), tau_roll, tau_pitch, tau_yaw] in N and N·m about the CG, FRD.
## f_min/f_max: per-rotor thrust bounds [N], 0 <= f_min[i] <= f_max[i].
## Returns {ok, thrusts, wrench (= B·thrusts), saturated, objective, iterations, fallback}. `saturated` means the
## unconstrained solution B⁻¹·w_req lies outside the box. `objective` is computed from the returned thrusts.
## In-box requests return B⁻¹·w_req; otherwise a primal active-set iteration on the 4-variable box problem runs
## (blocking/releasing ties go to the lowest rotor index), and if MAX_ITERATIONS is reached the result is
## allocate_reference's, with fallback = true.
static func allocate(prepared: Dictionary, wrench_req: PackedFloat64Array, f_min: PackedFloat64Array,
		f_max: PackedFloat64Array) -> Dictionary:
	var invalid: String = _check_request(prepared, wrench_req, f_min, f_max)
	if not invalid.is_empty():
		return _failure(invalid)
	var b_inverse: PackedFloat64Array = prepared.b_inverse
	var f := PackedFloat64Array()
	f.resize(4)
	var inside: bool = true
	for i in 4:
		var row: int = i * 4
		var value: float = b_inverse[row] * wrench_req[0] + b_inverse[row + 1] * wrench_req[1] \
			+ b_inverse[row + 2] * wrench_req[2] + b_inverse[row + 3] * wrench_req[3]
		f[i] = value
		if value < f_min[i] or value > f_max[i]:
			inside = false
	if inside:
		return _result(prepared, f, wrench_req, f_min, f_max, false, 0, false)

	var h: PackedFloat64Array = prepared.h
	var a: PackedFloat64Array = prepared.a
	var w_diag: PackedFloat64Array = prepared.w_diag
	# g = Aᵀ·(W·w_req); the gradient of ½||A f − W w||² is H f − g.
	var g := PackedFloat64Array()
	g.resize(4)
	for i in 4:
		var sum: float = 0.0
		for r in 4:
			sum += a[r * 4 + i] * w_diag[r] * wrench_req[r]
		g[i] = sum
	var gradient_tolerance: float = _gradient_tolerance(prepared, g, f_max)
	# Feasible start: the unconstrained solution clamped to the box.
	var status := PackedInt64Array()
	status.resize(4)
	for i in 4:
		if f_min[i] == f_max[i] or f[i] <= f_min[i]:
			f[i] = f_min[i]
			status[i] = STATUS_LOWER
		elif f[i] >= f_max[i]:
			f[i] = f_max[i]
			status[i] = STATUS_UPPER
		else:
			status[i] = STATUS_FREE
	var iterations: int = 0
	while iterations < MAX_ITERATIONS:
		iterations += 1
		var target: PackedFloat64Array = _reduced_normal_solve(h, g, f, status)
		if target.is_empty():
			break
		# Blocking bound along the step toward the subproblem minimizer: smallest ratio, lowest index on ties.
		var alpha: float = 1.0
		var blocking: int = -1
		var blocking_status: int = STATUS_FREE
		for i in 4:
			if status[i] != STATUS_FREE:
				continue
			var step: float = target[i] - f[i]
			if target[i] < f_min[i] and step < 0.0:
				var ratio: float = (f_min[i] - f[i]) / step
				if ratio < alpha:
					alpha = ratio
					blocking = i
					blocking_status = STATUS_LOWER
			elif target[i] > f_max[i] and step > 0.0:
				var ratio_up: float = (f_max[i] - f[i]) / step
				if ratio_up < alpha:
					alpha = ratio_up
					blocking = i
					blocking_status = STATUS_UPPER
		if blocking >= 0:
			alpha = clampf(alpha, 0.0, 1.0)
			for i in 4:
				if status[i] == STATUS_FREE:
					f[i] = clampf(f[i] + alpha * (target[i] - f[i]), f_min[i], f_max[i])
			f[blocking] = f_min[blocking] if blocking_status == STATUS_LOWER else f_max[blocking]
			status[blocking] = blocking_status
			continue
		for i in 4:
			if status[i] == STATUS_FREE:
				f[i] = clampf(target[i], f_min[i], f_max[i])
		# Release the fixed bound whose multiplier sign is most violated (lowest index on ties).
		var release: int = -1
		var worst: float = gradient_tolerance
		for i in 4:
			if status[i] == STATUS_FREE or f_min[i] == f_max[i]:
				continue
			var grad: float = _gradient_component(h, g, f, i)
			var violation: float = -grad if status[i] == STATUS_LOWER else grad
			if violation > worst:
				worst = violation
				release = i
		if release < 0:
			return _result(prepared, f, wrench_req, f_min, f_max, true, iterations, false)
		status[release] = STATUS_FREE
	var reference: Dictionary = allocate_reference(prepared, wrench_req, f_min, f_max)
	reference.fallback = true
	return reference


## Independent reference: enumerates all 3^4 = 81 lower/free/upper active sets, solves each reduced least-squares
## problem by modified Gram-Schmidt QR on the free columns of W·B, keeps feasible KKT-valid candidates and returns
## the minimum objective. Tie rule: the lowest enumeration code (rotor i's status is base-3 digit i, lower = 0,
## free = 1, upper = 2) whose objective is within 1e-14·max(1, best) of the best. A rotor with f_min == f_max is only
## enumerated as lower. Same return shape as allocate (iterations = candidate sets examined).
static func allocate_reference(prepared: Dictionary, wrench_req: PackedFloat64Array, f_min: PackedFloat64Array,
		f_max: PackedFloat64Array) -> Dictionary:
	var invalid: String = _check_request(prepared, wrench_req, f_min, f_max)
	if not invalid.is_empty():
		return _failure(invalid)
	var a: PackedFloat64Array = prepared.a
	var w_diag: PackedFloat64Array = prepared.w_diag
	var target := PackedFloat64Array()
	target.resize(4)
	for r in 4:
		target[r] = w_diag[r] * wrench_req[r]
	var g := PackedFloat64Array()
	g.resize(4)
	for i in 4:
		var sum: float = 0.0
		for r in 4:
			sum += a[r * 4 + i] * target[r]
		g[i] = sum
	var gradient_tolerance: float = _gradient_tolerance(prepared, g, f_max)
	var codes := PackedInt64Array()
	var objectives := PackedFloat64Array()
	var candidates: Array[PackedFloat64Array] = []
	var feasible_codes := PackedInt64Array()
	var feasible_objectives := PackedFloat64Array()
	var feasible: Array[PackedFloat64Array] = []
	var examined: int = 0
	for code in 81:
		var status := PackedInt64Array()
		status.resize(4)
		var skip: bool = false
		var digits: int = code
		for i in 4:
			status[i] = digits % 3
			digits = floori(digits / 3.0)
			if f_min[i] == f_max[i] and status[i] != STATUS_LOWER:
				skip = true
		if skip:
			continue
		examined += 1
		var f: PackedFloat64Array = _reduced_qr_solve(a, target, f_min, f_max, status)
		if f.is_empty():
			continue
		var ok_bounds: bool = true
		for i in 4:
			var span: float = KKT_TOLERANCE * maxf(1.0, maxf(absf(f_min[i]), absf(f_max[i])))
			if f[i] < f_min[i] - span or f[i] > f_max[i] + span:
				ok_bounds = false
			f[i] = clampf(f[i], f_min[i], f_max[i])
		if not ok_bounds:
			continue
		var objective: float = _objective(prepared, f, wrench_req)
		feasible_codes.append(code)
		feasible_objectives.append(objective)
		feasible.append(f)
		# KKT: Aᵀ(A f − W w) must push a lower-bound rotor up (>= 0) and an upper-bound rotor down (<= 0).
		var kkt: bool = true
		for i in 4:
			if status[i] == STATUS_FREE or f_min[i] == f_max[i]:
				continue
			var grad: float = 0.0
			for r in 4:
				var residual: float = -target[r]
				for j in 4:
					residual += a[r * 4 + j] * f[j]
				grad += a[r * 4 + i] * residual
			if status[i] == STATUS_LOWER and grad < -gradient_tolerance:
				kkt = false
			elif status[i] == STATUS_UPPER and grad > gradient_tolerance:
				kkt = false
		if kkt:
			codes.append(code)
			objectives.append(objective)
			candidates.append(f)
	if candidates.is_empty():
		# Tolerance fallback only: the strictly convex minimizer is always feasible, so take the best feasible set.
		codes = feasible_codes
		objectives = feasible_objectives
		candidates = feasible
	if candidates.is_empty():
		return _failure("reference found no feasible active set")
	var best: float = INF
	for k in objectives.size():
		best = minf(best, objectives[k])
	var tie: float = 1.0e-14 * maxf(1.0, best)
	for k in objectives.size():
		if objectives[k] <= best + tie:
			var result: Dictionary = _result(prepared, candidates[k], wrench_req, f_min, f_max, false, examined, false)
			result.saturated = _unconstrained_outside(prepared, wrench_req, f_min, f_max)
			return result
	return _failure("reference tie selection failed")


## B·f.
static func wrench_of(prepared: Dictionary, thrusts: PackedFloat64Array) -> PackedFloat64Array:
	var b: PackedFloat64Array = prepared.b
	var w := PackedFloat64Array()
	w.resize(4)
	for r in 4:
		var row: int = r * 4
		w[r] = b[row] * thrusts[0] + b[row + 1] * thrusts[1] + b[row + 2] * thrusts[2] + b[row + 3] * thrusts[3]
	return w


static func _check_request(prepared: Dictionary, wrench_req: PackedFloat64Array, f_min: PackedFloat64Array,
		f_max: PackedFloat64Array) -> String:
	if not bool(prepared.get("ok", false)) or prepared.get("law", "") != LAW:
		return "allocator is not prepared"
	if wrench_req.size() != 4 or f_min.size() != 4 or f_max.size() != 4:
		return "wrench_req, f_min and f_max must hold 4 values"
	for k in 4:
		if not is_finite(wrench_req[k]):
			return "wrench_req must be finite"
		if not is_finite(f_min[k]) or not is_finite(f_max[k]) or f_min[k] < 0.0 or f_min[k] > f_max[k]:
			return "bounds require finite 0 <= f_min <= f_max"
	if wrench_req[0] < 0.0:
		return "requested total thrust must be >= 0"
	return ""


static func _unconstrained_outside(prepared: Dictionary, wrench_req: PackedFloat64Array, f_min: PackedFloat64Array,
		f_max: PackedFloat64Array) -> bool:
	var b_inverse: PackedFloat64Array = prepared.b_inverse
	for i in 4:
		var row: int = i * 4
		var value: float = b_inverse[row] * wrench_req[0] + b_inverse[row + 1] * wrench_req[1] \
			+ b_inverse[row + 2] * wrench_req[2] + b_inverse[row + 3] * wrench_req[3]
		if value < f_min[i] or value > f_max[i]:
			return true
	return false


static func _result(prepared: Dictionary, f: PackedFloat64Array, wrench_req: PackedFloat64Array,
		f_min: PackedFloat64Array, f_max: PackedFloat64Array, saturated: bool, iterations: int,
		fallback: bool) -> Dictionary:
	var thrusts := PackedFloat64Array()
	thrusts.resize(4)
	for i in 4:
		thrusts[i] = clampf(f[i], f_min[i], f_max[i])
	var wrench: PackedFloat64Array = wrench_of(prepared, thrusts)
	var w_diag: PackedFloat64Array = prepared.w_diag
	var objective: float = 0.0
	for r in 4:
		var residual: float = w_diag[r] * (wrench[r] - wrench_req[r])
		objective += residual * residual
	return {ok = true, thrusts = thrusts, wrench = wrench, saturated = saturated, objective = objective,
		iterations = iterations, fallback = fallback}


static func _objective(prepared: Dictionary, f: PackedFloat64Array, wrench_req: PackedFloat64Array) -> float:
	var wrench: PackedFloat64Array = wrench_of(prepared, f)
	var w_diag: PackedFloat64Array = prepared.w_diag
	var objective: float = 0.0
	for r in 4:
		var residual: float = w_diag[r] * (wrench[r] - wrench_req[r])
		objective += residual * residual
	return objective


static func _gradient_tolerance(prepared: Dictionary, g: PackedFloat64Array, f_max: PackedFloat64Array) -> float:
	var f_scale: float = 0.0
	var g_scale: float = 0.0
	for i in 4:
		f_scale = maxf(f_scale, absf(f_max[i]))
		g_scale = maxf(g_scale, absf(g[i]))
	return KKT_TOLERANCE * maxf(1.0e-300, 4.0 * float(prepared.h_norm) * f_scale + g_scale)


static func _gradient_component(h: PackedFloat64Array, g: PackedFloat64Array, f: PackedFloat64Array, i: int) -> float:
	var row: int = i * 4
	return h[row] * f[0] + h[row + 1] * f[1] + h[row + 2] * f[2] + h[row + 3] * f[3] - g[i]


## Minimizer over the free rotors with the others fixed at f: H_FF·x_F = g_F − H_FX·f_X (Gaussian elimination with
## partial pivoting, lowest row on pivot ties). Returns the full 4-vector, or empty if the reduced system is singular.
static func _reduced_normal_solve(h: PackedFloat64Array, g: PackedFloat64Array, f: PackedFloat64Array,
		status: PackedInt64Array) -> PackedFloat64Array:
	var free := PackedInt64Array()
	for i in 4:
		if status[i] == STATUS_FREE:
			free.append(i)
	var result: PackedFloat64Array = f.duplicate()
	var n: int = free.size()
	if n == 0:
		return result
	var m := PackedFloat64Array()
	m.resize(n * (n + 1))
	for p in n:
		var i: int = free[p]
		var rhs: float = g[i]
		for j in 4:
			if status[j] != STATUS_FREE:
				rhs -= h[i * 4 + j] * f[j]
		for q in n:
			m[p * (n + 1) + q] = h[i * 4 + free[q]]
		m[p * (n + 1) + n] = rhs
	var x: PackedFloat64Array = _gauss_solve(m, n)
	if x.is_empty():
		return x
	for p in n:
		result[free[p]] = x[p]
	return result


## Least squares over the free columns of A with fixed rotors at their bounds, by modified Gram-Schmidt QR.
static func _reduced_qr_solve(a: PackedFloat64Array, target: PackedFloat64Array, f_min: PackedFloat64Array,
		f_max: PackedFloat64Array, status: PackedInt64Array) -> PackedFloat64Array:
	var f := PackedFloat64Array()
	f.resize(4)
	var rhs: PackedFloat64Array = target.duplicate()
	var free := PackedInt64Array()
	for i in 4:
		if status[i] == STATUS_FREE:
			free.append(i)
			continue
		f[i] = f_min[i] if status[i] == STATUS_LOWER else f_max[i]
		for r in 4:
			rhs[r] -= a[r * 4 + i] * f[i]
	var n: int = free.size()
	if n == 0:
		return f
	# Columns q_k (4 rows each) and upper-triangular R (n×n, row-major).
	var q := PackedFloat64Array()
	q.resize(4 * n)
	for k in n:
		for r in 4:
			q[k * 4 + r] = a[r * 4 + free[k]]
	var rr := PackedFloat64Array()
	rr.resize(n * n)
	for k in n:
		for j in k:
			var dot: float = 0.0
			for r in 4:
				dot += q[j * 4 + r] * q[k * 4 + r]
			rr[j * n + k] = dot
			for r in 4:
				q[k * 4 + r] -= dot * q[j * 4 + r]
		var norm: float = 0.0
		for r in 4:
			norm += q[k * 4 + r] * q[k * 4 + r]
		norm = sqrt(norm)
		if not (norm > 0.0) or not is_finite(norm):
			return PackedFloat64Array()
		rr[k * n + k] = norm
		for r in 4:
			q[k * 4 + r] /= norm
	var y := PackedFloat64Array()
	y.resize(n)
	for k in n:
		var dot_rhs: float = 0.0
		for r in 4:
			dot_rhs += q[k * 4 + r] * rhs[r]
		y[k] = dot_rhs
	for k in range(n - 1, -1, -1):
		var value: float = y[k]
		for j in range(k + 1, n):
			value -= rr[k * n + j] * y[j]
		y[k] = value / rr[k * n + k]
	for k in n:
		f[free[k]] = y[k]
	return f


## Solve an n×n system stored as an n×(n+1) augmented row-major matrix. Empty on a zero/non-finite pivot.
static func _gauss_solve(m: PackedFloat64Array, n: int) -> PackedFloat64Array:
	var width: int = n + 1
	for col in n:
		var pivot_row: int = col
		var pivot_abs: float = absf(m[col * width + col])
		for r in range(col + 1, n):
			var candidate: float = absf(m[r * width + col])
			if candidate > pivot_abs:
				pivot_abs = candidate
				pivot_row = r
		if not (pivot_abs > 0.0) or not is_finite(pivot_abs):
			return PackedFloat64Array()
		if pivot_row != col:
			for c in width:
				var swap: float = m[col * width + c]
				m[col * width + c] = m[pivot_row * width + c]
				m[pivot_row * width + c] = swap
		var pivot: float = m[col * width + col]
		for r in range(col + 1, n):
			var factor: float = m[r * width + col] / pivot
			if factor == 0.0:
				continue
			for c in range(col, width):
				m[r * width + c] -= factor * m[col * width + c]
	var x := PackedFloat64Array()
	x.resize(n)
	for r in range(n - 1, -1, -1):
		var value: float = m[r * width + n]
		for c in range(r + 1, n):
			value -= m[r * width + c] * x[c]
		x[r] = value / m[r * width + r]
	return x


## Gauss-Jordan inverse of a row-major 4×4 matrix with partial pivoting. Empty when a pivot falls below
## PIVOT_TOLERANCE times the largest |entry| (rank deficiency).
static func _invert4(source: PackedFloat64Array) -> PackedFloat64Array:
	var m: PackedFloat64Array = source.duplicate()
	var inverse := PackedFloat64Array()
	inverse.resize(16)
	var largest: float = 0.0
	for k in 16:
		largest = maxf(largest, absf(m[k]))
	if not (largest > 0.0):
		return PackedFloat64Array()
	for i in 4:
		inverse[i * 4 + i] = 1.0
	for col in 4:
		var pivot_row: int = col
		var pivot_abs: float = absf(m[col * 4 + col])
		for r in range(col + 1, 4):
			var candidate: float = absf(m[r * 4 + col])
			if candidate > pivot_abs:
				pivot_abs = candidate
				pivot_row = r
		if pivot_abs <= PIVOT_TOLERANCE * largest:
			return PackedFloat64Array()
		if pivot_row != col:
			for c in 4:
				var swap: float = m[col * 4 + c]
				m[col * 4 + c] = m[pivot_row * 4 + c]
				m[pivot_row * 4 + c] = swap
				swap = inverse[col * 4 + c]
				inverse[col * 4 + c] = inverse[pivot_row * 4 + c]
				inverse[pivot_row * 4 + c] = swap
		var pivot: float = m[col * 4 + col]
		for c in 4:
			m[col * 4 + c] /= pivot
			inverse[col * 4 + c] /= pivot
		for r in 4:
			if r == col:
				continue
			var factor: float = m[r * 4 + col]
			if factor == 0.0:
				continue
			for c in 4:
				m[r * 4 + c] -= factor * m[col * 4 + c]
				inverse[r * 4 + c] -= factor * inverse[col * 4 + c]
	return inverse


static func _norm_inf(m: PackedFloat64Array) -> float:
	var best: float = 0.0
	for r in 4:
		var sum: float = absf(m[r * 4]) + absf(m[r * 4 + 1]) + absf(m[r * 4 + 2]) + absf(m[r * 4 + 3])
		best = maxf(best, sum)
	return best


static func _failure(message: String) -> Dictionary:
	return {ok = false, message = message, errors = PackedStringArray([message])}

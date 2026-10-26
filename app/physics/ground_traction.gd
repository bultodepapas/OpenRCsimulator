## GP-12: compact maximum-dissipation impulse QP. Pure float64, no runtime state.
## p=D*y; product of 1D intervals/2D unit disks. Full mobility objective is used;
## this is not a Euclidean clamp of an unconstrained physical force.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const GC := preload("res://physics/generalized_coordinates.gd")
const LAW := "compact-mobility-block-kkt-impulse-v1"
const MAX_DIMENSION := 64
const MAX_ITERATIONS := 1024
const MULTIPLIER_ITERATIONS := 72
const SYMMETRY_TOLERANCE := 1.0e-12
const PSD_TOLERANCE := 1.0e-12
const KKT_RELATIVE_TOLERANCE := 1.0e-10
const FEASIBILITY_TOLERANCE := 1.0e-12


## A is row-major J*M^-1*J^T; v contains free relative slip rates, D finite
## impulse bounds. Groups partition ALL rows, with one or two indices each.
## Linear/angular row units are mixed legitimately via their Jacobians.
## Dissipation = -(v.p + .5*p.A.p), relative to prescribed/moving support;
## it is not universally the decrease of a closed body's kinetic energy.
static func solve(a: PackedFloat64Array, v: PackedFloat64Array, limits: PackedFloat64Array,
		groups: Array, iteration_budget: int = MAX_ITERATIONS) -> Dictionary:
	var n := v.size()
	if n < 1 or n > MAX_DIMENSION or a.size() != n * n or limits.size() != n \
		or not _finite(a) or not _finite(v) or not _finite(limits) \
		or iteration_budget < 1 or iteration_budget > MAX_ITERATIONS:
		return _failure("invalid dimensions, finite inputs or iteration budget")
	var seen := PackedByteArray()
	seen.resize(n)
	for value: Variant in groups:
		if typeof(value) != TYPE_PACKED_INT32_ARRAY or value.size() not in [1, 2]:
			return _failure("groups must be packed integer intervals/disks")
		for index: int in value:
			if index < 0 or index >= n or seen[index] != 0:
				return _failure("groups must partition coordinates without overlap")
			seen[index] = 1
	for i in n:
		if seen[i] == 0 or limits[i] < 0.0:
			return _failure("unassigned coordinate or negative impulse limit")
	var validated := _validate_psd(a, n)
	if not validated.ok: return validated
	var symmetric: PackedFloat64Array = validated.matrix
	var h := PackedFloat64Array()
	var b := PackedFloat64Array()
	h.resize(n * n)
	b.resize(n)
	var scale := 0.0
	for i in n:
		b[i] = limits[i] * v[i]
		if not is_finite(b[i]) or (limits[i] != 0.0 and v[i] != 0.0 and b[i] == 0.0):
			return _failure("normalized linear term exceeds numeric range")
		scale = maxf(scale, absf(b[i]))
		for j in n:
			# Congruence via diagonal roots avoids avoidable D*A overflow.
			var left: float = limits[i] * validated.diagonal_roots[i]
			var right: float = limits[j] * validated.diagonal_roots[j]
			h[i * n + j] = validated.correlation[i * n + j] * left * right
			if not is_finite(h[i * n + j]) or (limits[i] > 0.0 and limits[j] > 0.0 and symmetric[i * n + j] != 0.0 and h[i * n + j] == 0.0):
				return _failure("normalized mobility exceeds numeric range")
			scale = maxf(scale, absf(h[i * n + j]))
	var y := PackedFloat64Array()
	y.resize(n)
	if scale == 0.0:
		return _publish(symmetric, v, limits, groups, h, b, y, 1.0, validated, 0, "zero_objective")
	var hs := h.duplicate()
	var bs := b.duplicate()
	var b_norm := 0.0
	for i in n:
		bs[i] /= scale
		if b[i] != 0.0 and bs[i] == 0.0: return _failure("linear scaling underflow")
		b_norm = maxf(b_norm, absf(bs[i]))
	for i in hs.size():
		hs[i] /= scale
		if h[i] != 0.0 and hs[i] == 0.0: return _failure("mobility scaling underflow")
	var tolerance := KKT_RELATIVE_TOLERANCE * b_norm
	if b_norm > 0.0 and tolerance == 0.0: return _failure("requested KKT accuracy exceeds numeric range")
	# Exact feasible SPD stationary point, when available. Zero-limit coordinates
	# are removed rather than regularized into an artificial mass/traction mode.
	var active: Array[int] = []
	for i in n:
		if limits[i] > 0.0: active.append(i)
	if not active.is_empty():
		var dense := PackedFloat64Array()
		var rhs := PackedFloat64Array()
		dense.resize(active.size() * active.size())
		for i in active.size():
			rhs.append(-bs[active[i]])
			for j in active.size(): dense[i * active.size() + j] = hs[active[i] * n + active[j]]
		var factor := GC.cholesky_factor(dense, active.size())
		if factor.ok:
			var free := GC.solve_cholesky(factor.lower, rhs, active.size())
			if free.size() == active.size() and _finite(free):
				for i in active.size(): y[active[i]] = free[i]
				var certified := _certificate(hs, bs, y, limits, groups, tolerance)
				if certified.ok:
					return _publish(symmetric, v, limits, groups, h, b, y, scale, validated, 0, "feasible_spd_stationary")
				y.fill(0.0)
	# Cyclic exact block minimization monotonically optimizes the FULL coupled
	# objective. Each two-row block is a mobility-metric trust-region solve.
	# Only the final GLOBAL KKT certificate authorizes publication.
	var previous_objective := 0.0
	var maximum_increase := 0.0
	for iteration in iteration_budget:
		for group: PackedInt32Array in groups:
			var indices: Array[int] = []
			for index: int in group:
				if limits[index] > 0.0: indices.append(index)
			if indices.is_empty(): continue
			var c := PackedFloat64Array()
			for index: int in indices:
				var value := bs[index]
				for j in n:
					if not indices.has(j): value += hs[index * n + j] * y[j]
				c.append(value)
			var block: PackedFloat64Array
			if indices.size() == 1:
				var diagonal := hs[indices[0] * n + indices[0]]
				block = PackedFloat64Array([clampf(-c[0] / diagonal, -1.0, 1.0) if diagonal > 0.0 else -signf(c[0])])
			else:
				block = _disk(hs[indices[0] * n + indices[0]], hs[indices[0] * n + indices[1]],
					hs[indices[1] * n + indices[1]], c[0], c[1])
			if block.size() != indices.size() or not _finite(block):
				return _failure("block metric solve could not be certified", "nonconverged", iteration + 1)
			for i in indices.size(): y[indices[i]] = block[i]
		var current_objective := _objective(hs, bs, y)
		maximum_increase = maxf(maximum_increase, current_objective - previous_objective)
		if not is_finite(current_objective) or current_objective > previous_objective + 0.00000000000002 * (absf(previous_objective) + b_norm):
			return _failure("block solve did not preserve monotone objective", "nonconverged", iteration + 1)
		previous_objective = current_objective
		var certified := _certificate(hs, bs, y, limits, groups, tolerance)
		if certified.ok:
			var published := _publish(symmetric, v, limits, groups, h, b, y, scale, validated, iteration + 1, "cyclic_exact_metric_blocks")
			published.maximum_objective_increase_scaled = maximum_increase
			return published
	var failure := _failure("global KKT residual exceeds iteration budget", "nonconverged", iteration_budget)
	var residual := _certificate(hs, bs, y, limits, groups, tolerance)
	failure.kkt_residual_scaled = residual.stationarity
	failure.kkt_tolerance_scaled = residual.tolerance
	failure.complementarity_scaled = residual.complementarity
	failure.feasibility_residual = residual.feasibility
	failure.duality_gap_scaled = residual.duality_gap
	return failure


## Unit-invariant congruence validation; no fictitious diagonal is introduced.
## Tiny residuals are explicitly reported as numerical PSD roundoff tolerance.
static func _validate_psd(a: PackedFloat64Array, n: int) -> Dictionary:
	var roots := PackedFloat64Array()
	roots.resize(n)
	for i in n:
		if a[i * n + i] < 0.0: return _failure("negative mobility diagonal", "indefinite")
		roots[i] = M.sqrt_(a[i * n + i])
	var correlation := PackedFloat64Array()
	var symmetric := a.duplicate()
	correlation.resize(n * n)
	var symmetry_error := 0.0
	for i in n:
		for j in n:
			if roots[i] == 0.0 or roots[j] == 0.0:
				if a[i * n + j] != 0.0 or a[j * n + i] != 0.0:
					return _failure("zero mobility diagonal has a nonzero row", "indefinite")
				continue
			var forward := a[i * n + j] / roots[i] / roots[j]
			var reverse := a[j * n + i] / roots[j] / roots[i]
			if not is_finite(forward) or not is_finite(reverse): return _failure("mobility equilibration overflow")
			symmetry_error = maxf(symmetry_error, absf(forward - reverse))
			if absf(forward - reverse) > SYMMETRY_TOLERANCE:
				return _failure("mobility is not symmetric in diagonal units")
			correlation[i * n + j] = 0.5 * forward + 0.5 * reverse
			symmetric[i * n + j] = 0.5 * a[i * n + j] + 0.5 * a[j * n + i]
	var schur := correlation.duplicate()
	var rank := 0
	var roundoff := 0.0
	for k in n:
		var pivot := k
		for i in range(k + 1, n):
			if schur[i * n + i] > schur[pivot * n + pivot]: pivot = i
		if pivot != k:
			for i in n:
				var value := schur[k * n + i]
				schur[k * n + i] = schur[pivot * n + i]
				schur[pivot * n + i] = value
			for i in n:
				var value := schur[i * n + k]
				schur[i * n + k] = schur[i * n + pivot]
				schur[i * n + pivot] = value
		var diagonal := schur[k * n + k]
		if diagonal < -PSD_TOLERANCE: return _failure("mobility has a negative PSD pivot", "indefinite")
		if diagonal <= PSD_TOLERANCE:
			for i in range(k, n):
				for j in range(k, n):
					roundoff = maxf(roundoff, absf(schur[i * n + j]))
			if roundoff > PSD_TOLERANCE: return _failure("singular mobility has an indefinite residual block", "indefinite")
			break
		rank += 1
		for i in range(k + 1, n):
			for j in range(k + 1, n): schur[i * n + j] -= schur[i * n + k] * schur[k * n + j] / diagonal
	return {ok = true, matrix = symmetric, diagonal_roots = roots, correlation = correlation,
		rank = rank, psd_roundoff = roundoff, symmetry_error = symmetry_error}


## Exact two-dimensional PSD trust-region subproblem to floating-point KKT
## tolerance. Bisection retains the feasible multiplier side, including linear
## objectives in singular/null mobility; compact disks are never 'unbounded'.
static func _disk(h00: float, h01: float, h11: float, c0: float, c1: float) -> PackedFloat64Array:
	var norm_c := _hypot(c0, c1)
	if norm_c == 0.0: return PackedFloat64Array([0.0, 0.0])
	var determinant := h00 * h11 - h01 * h01
	if determinant > 0.0:
		var free := PackedFloat64Array([(-h11 * c0 + h01 * c1) / determinant, (h01 * c0 - h00 * c1) / determinant])
		if _norm2(free) <= 1.0: return free
	elif h00 + h11 > 0.0:
		var trace := h00 + h11
		var candidate := PackedFloat64Array([-c0 / trace, -c1 / trace])
		var error0 := h00 * candidate[0] + h01 * candidate[1] + c0
		var error1 := h01 * candidate[0] + h11 * candidate[1] + c1
		if maxf(absf(error0), absf(error1)) <= 0.00000000000002 * norm_c and _norm2(candidate) <= 1.0:
			return candidate
	var lower := 0.0
	var upper := 2.0 * norm_c
	var feasible := PackedFloat64Array()
	for iteration in MULTIPLIER_ITERATIONS:
		var multiplier := upper if iteration == 0 else 0.5 * (lower + upper)
		var det := determinant + multiplier * (h00 + h11) + multiplier * multiplier
		if det <= 0.0 or not is_finite(det): return PackedFloat64Array()
		var value := PackedFloat64Array([(-(h11 + multiplier) * c0 + h01 * c1) / det,
			(h01 * c0 - (h00 + multiplier) * c1) / det])
		if _norm2(value) > 1.0:
			lower = multiplier
		else:
			upper = multiplier
			feasible = value
	return feasible


static func _certificate(h: PackedFloat64Array, b: PackedFloat64Array, y: PackedFloat64Array,
		limits: PackedFloat64Array, groups: Array, tolerance: float) -> Dictionary:
	var n := b.size()
	var gradient := GC.matrix_vector(h, y, n)
	for i in n: gradient[i] += b[i]
	var stationarity := 0.0
	var complementarity := 0.0
	var feasibility := 0.0
	var gap := 0.0
	for group: PackedInt32Array in groups:
		var norm_y_sq := 0.0
		var norm_g := 0.0
		var gy := 0.0
		for i: int in group:
			if limits[i] == 0.0:
				feasibility = maxf(feasibility, absf(y[i]))
				continue
			norm_y_sq += y[i] * y[i]
			norm_g = _hypot(norm_g, gradient[i])
			gy += gradient[i] * y[i]
		feasibility = maxf(feasibility, maxf(0.0, norm_y_sq - 1.0))
		var multiplier := maxf(0.0, -gy / norm_y_sq) if norm_y_sq > 0.0 else 0.0
		if norm_y_sq < 1.0 - FEASIBILITY_TOLERANCE: multiplier = 0.0
		for i: int in group:
			if limits[i] > 0.0: stationarity = maxf(stationarity, absf(gradient[i] + multiplier * y[i]))
		complementarity = maxf(complementarity, absf(multiplier * (1.0 - norm_y_sq)))
		gap += maxf(0.0, gy + norm_g)
	return {ok = is_finite(stationarity) and is_finite(gap) and stationarity <= tolerance \
		and complementarity <= tolerance and feasibility <= FEASIBILITY_TOLERANCE \
		and gap <= tolerance * maxf(1.0, float(groups.size()) * 2.0),
		stationarity = stationarity, complementarity = complementarity,
		feasibility = feasibility, duality_gap = gap, tolerance = tolerance}


static func _publish(a: PackedFloat64Array, v: PackedFloat64Array, limits: PackedFloat64Array,
		groups: Array, h: PackedFloat64Array, b: PackedFloat64Array, y: PackedFloat64Array,
		scale: float, validated: Dictionary, iterations: int, method: String) -> Dictionary:
	var n := v.size()
	y = y.duplicate()
	var correction := 0.0
	for group: PackedInt32Array in groups:
		var length_sq := 0.0
		for i: int in group: length_sq += y[i] * y[i]
		if length_sq > 1.0:
			if length_sq > 1.0 + FEASIBILITY_TOLERANCE: return _failure("infeasible block at publication", "nonconverged", iterations)
			var shrink := (1.0 - 0.000000000000002) / M.sqrt_(length_sq)
			for i: int in group:
				correction = maxf(correction, absf(y[i] * (1.0 - shrink)))
				y[i] *= shrink
	var impulse := PackedFloat64Array()
	impulse.resize(n)
	var linear := 0.0
	var quadratic := 0.0
	for i in n: impulse[i] = limits[i] * y[i] if limits[i] > 0.0 else 0.0
	var post := GC.matrix_vector(a, impulse, n)
	for i in n:
		linear += v[i] * impulse[i]
		quadratic += 0.5 * impulse[i] * post[i]
		post[i] += v[i]
	var objective := linear + quadratic
	if not _finite(impulse) or not _finite(post) or not is_finite(objective) or objective > 0.0:
		return _failure("work ledger or post-slip is outside the passive numeric domain", "nonconverged", iterations)
	var hs := h.duplicate()
	var bs := b.duplicate()
	var b_norm := 0.0
	for i in n:
		bs[i] /= scale
		b_norm = maxf(b_norm, absf(bs[i]))
	for i in hs.size(): hs[i] /= scale
	var certificate := _certificate(hs, bs, y, limits, groups, KKT_RELATIVE_TOLERANCE * b_norm)
	if not certificate.ok: return _failure("publication KKT verification failed", "nonconverged", iterations)
	var grouped: Array[PackedFloat64Array] = []
	for group: PackedInt32Array in groups:
		var values := PackedFloat64Array()
		for i: int in group: values.append(impulse[i])
		grouped.append(values)
	return {ok = true, status = "converged", law = LAW, converged = true, iterations = iterations,
		method = method, impulse = impulse, group_impulses = grouped, normalized_impulse = y.duplicate(),
		post_slip = post, linear_work = linear, mobility_work = quadratic, objective = objective,
		dissipation = -objective, objective_scale = scale,
		kkt_residual_scaled = certificate.stationarity, kkt_tolerance_scaled = certificate.tolerance,
		complementarity_scaled = certificate.complementarity, feasibility_residual = certificate.feasibility,
		duality_gap = certificate.duality_gap * scale, psd_rank = validated.rank,
		psd_roundoff_residual = validated.psd_roundoff, psd_tolerance = PSD_TOLERANCE,
		symmetry_residual = validated.symmetry_error, diagonal_regularization = 0.0,
		feasibility_roundoff_correction = correction,
		work_frame = "relative_to_prescribed_support_not_universal_closed_body_energy"}


static func _objective(h: PackedFloat64Array, b: PackedFloat64Array, y: PackedFloat64Array) -> float:
	var hy := GC.matrix_vector(h, y, b.size())
	var value := 0.0
	for i in b.size(): value += b[i] * y[i] + 0.5 * y[i] * hy[i]
	return value


static func _norm2(value: PackedFloat64Array) -> float:
	return _hypot(value[0], value[1])


static func _hypot(x: float, y: float) -> float:
	var largest := maxf(absf(x), absf(y))
	if largest == 0.0: return 0.0
	return largest * M.sqrt_((x / largest) * (x / largest) + (y / largest) * (y / largest))


static func _finite(value: PackedFloat64Array) -> bool:
	for number: float in value:
		if not is_finite(number): return false
	return true


static func _failure(reason: String, status := "invalid", iterations := 0) -> Dictionary:
	return {ok = false, status = status, law = LAW, reason = reason, converged = false, iterations = iterations}

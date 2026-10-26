extends SceneTree

const T := preload("res://physics/ground_traction.gd")
const G := preload("res://physics/generalized_coordinates.gd")
const W := preload("res://physics/wheel_coupling.gd")
const M := preload("res://physics/math3d.gd")
var _checks := 0
var _failures := 0


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL ", label, " ", detail)


func _initialize() -> void:
	_scalars()
	_circles_and_ellipse()
	_dense_and_coupled()
	_semidefinite()
	_capacity()
	_validation()
	_common_wheel_energy()
	print("GP-12 traction: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _p(values: Array) -> PackedFloat64Array:
	return PackedFloat64Array(values)


func _neg(value: PackedFloat64Array) -> PackedFloat64Array:
	var result := value.duplicate()
	for i in result.size(): result[i] = -result[i]
	return result


func _groups(count: int) -> Array:
	var result: Array = []
	for i in count: result.append(PackedInt32Array([i]))
	return result


func _verify(label: String, a: PackedFloat64Array, v: PackedFloat64Array,
		d: PackedFloat64Array, groups: Array, result: Dictionary) -> void:
	_check(label + " certified", result.get("ok", false) and result.get("converged", false), str(result))
	if not result.get("ok", false): return
	var n := v.size()
	var p: PackedFloat64Array = result.impulse
	var post := G.matrix_vector(a, p, n)
	var work := 0.0
	var quadratic := 0.0
	for i in n:
		work += v[i] * p[i]
		quadratic += 0.5 * p[i] * post[i]
		post[i] += v[i]
		if d[i] == 0.0: _check(label + " zero limit has exactly zero authority", p[i] == 0.0)
	_check(label + " loss ledger matches original physical mobility", absf(result.linear_work - work) < 1e-10
		and absf(result.mobility_work - quadratic) < 1e-10
		and absf(result.dissipation + work + quadratic) < 1e-10 and result.dissipation >= 0.0)
	_check(label + " post impulse slip matches original mobility", _distance(post, result.post_slip) < 1e-10)
	_check(label + " no fictitious mobility diagonal", result.diagonal_regularization == 0.0)
	_check(label + " global certificates satisfy declared tolerances", result.kkt_residual_scaled <= result.kkt_tolerance_scaled
		and result.complementarity_scaled <= result.kkt_tolerance_scaled and result.feasibility_residual <= T.FEASIBILITY_TOLERANCE)
	var y := PackedFloat64Array()
	var gradient := PackedFloat64Array()
	var b_norm := 0.0
	for i in n:
		y.append(p[i] / d[i] if d[i] > 0.0 else 0.0)
		gradient.append(d[i] * post[i] / result.objective_scale)
		b_norm = maxf(b_norm, absf(d[i] * v[i] / result.objective_scale))
	for group: PackedInt32Array in groups:
		var yy := 0.0
		var gy := 0.0
		var group_post_power := 0.0
		for i: int in group:
			yy += y[i] * y[i]
			gy += gradient[i] * y[i]
			group_post_power += p[i] * post[i]
		_check(label + " ellipse/interval feasibility", yy <= 1.0 + 1e-14)
		var lambda := maxf(0, -gy / yy) if yy > 1.0 - 1e-9 else 0.0
		var error := 0.0
		for i: int in group:
			if d[i] > 0.0: error = maxf(error, absf(gradient[i] + lambda * y[i]))
		_check(label + " independent original-matrix KKT", error <= maxf(1e-15, b_norm * 1e-8))
		_check(label + " group opposes resolved post-slip", group_post_power <= 1e-8 * maxf(1.0, result.objective_scale))
	_check(label + " frame interpretation is explicit", result.work_frame == "relative_to_prescribed_support_not_universal_closed_body_energy")


func _distance(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	if a.size() != b.size(): return INF
	var result := 0.0
	for i in a.size(): result = maxf(result, absf(a[i] - b[i]))
	return result


func _scalars() -> void:
	for row: Array in [[2.0, 3.0, 4.0, -1.5], [2.0, 100.0, 0.5, -0.5],
			[2.0, -100.0, 0.5, 0.5], [2.0, 0.0, 0.5, 0.0], [2.0, 10.0, 0.0, 0.0],
			[1e-20, 10.0, 1.0, -1.0], [0.0, -10.0, 0.7, 0.7]]:
		var a := _p([row[0]])
		var v := _p([row[1]])
		var d := _p([row[2]])
		var result := T.solve(a, v, d, _groups(1))
		_verify("analytic scalar", a, v, d, _groups(1), result)
		_check("1D minimizer matches independent scalar solution", result.get("ok", false) and absf(result.impulse[0] - row[3]) < 1e-12)


func _ellipse_objective(angle: float, a: PackedFloat64Array, v: PackedFloat64Array,
		d: PackedFloat64Array) -> float:
	var p := _p([d[0] * cos(angle), d[1] * sin(angle)])
	return G.dot(v, p, 2) + 0.5 * G.dot(p, G.matrix_vector(a, p, 2), 2)


func _angle_oracle(a: PackedFloat64Array, v: PackedFloat64Array, d: PackedFloat64Array) -> PackedFloat64Array:
	# Independent boundary angular enumeration plus ternary interval refinement;
	# this shares neither the production multiplier solve nor its PSD factor.
	var best := INF
	var angle := 0.0
	for i in 4096:
		var candidate := 2.0 * PI * float(i) / 4096.0
		var value := _ellipse_objective(candidate, a, v, d)
		if value < best:
			best = value
			angle = candidate
	var low := angle - 2.0 * PI / 4096.0
	var high := angle + 2.0 * PI / 4096.0
	for i in 72:
		var left := (2.0 * low + high) / 3.0
		var right := (low + 2.0 * high) / 3.0
		if _ellipse_objective(left, a, v, d) < _ellipse_objective(right, a, v, d): high = right
		else: low = left
	angle = 0.5 * (low + high)
	return _p([d[0] * cos(angle), d[1] * sin(angle)])


func _circles_and_ellipse() -> void:
	var circle := [PackedInt32Array([0, 1])]
	var a := _p([1, 0, 0, 1])
	var v := _p([3, 4])
	var d := _p([1, 1])
	var result := T.solve(a, v, d, circle)
	_verify("isotropic circle", a, v, d, circle, result)
	_check("circle analytical boundary answer", result.get("ok", false) and _distance(result.impulse, _p([-0.6, -0.8])) < 1e-10)
	for sample: Array in [[_p([1, 0, 0, 1]), _p([3, 4]), _p([2, 0.5])],
			[_p([8, 1.5, 1.5, 0.8]), _p([4, -5]), _p([1, 1])]]:
		a = sample[0]
		v = sample[1]
		d = sample[2]
		result = T.solve(a, v, d, circle)
		_verify("anisotropic metric", a, v, d, circle, result)
		var oracle := _angle_oracle(a, v, d)
		_check("metric solution matches independent angular oracle", result.get("ok", false) and _distance(result.impulse, oracle) < 1e-7,
			"expected=%s received=%s" % [oracle, result.get("impulse", [])])
		var reverse := T.solve(a, _neg(v), d, circle)
		_check("reverse slip reverses the same constrained solution", reverse.get("ok", false) and _distance(reverse.impulse, _neg(result.impulse)) < 1e-10)
	var mixed := T.solve(_p([1, 0, 0, 1]), _p([10, 10]), _p([0, 2]), circle)
	_verify("zero grip axis", _p([1, 0, 0, 1]), _p([10, 10]), _p([0, 2]), circle, mixed)
	_check("zero ellipse limit becomes an exact lower dimensional interval", mixed.get("ok", false) and mixed.impulse[0] == 0 and mixed.impulse[1] == -2)


func _dense_case() -> Dictionary:
	var n := 5
	var base := _p([2, .3, -.2, .1, .4, .3, 1.5, .2, -.1, .1,
		-.2, .2, 1.8, .3, -.2, .1, -.1, .3, 1.6, .2, .4, .1, -.2, .2, 1.4])
	var d := _p([2, .5, 1, 3, .2])
	var y := _p([-.6, -.8, .3, -sqrt(.91), .2])
	var h := PackedFloat64Array()
	h.resize(n * n)
	for i in n:
		for j in n:
			for k in n: h[i * n + j] += base[k * n + i] * base[k * n + j]
	var b := _neg(G.matrix_vector(h, y, n))
	for i in 2: b[i] -= 2.0 * y[i]
	for i in range(2, 4): b[i] -= 0.7 * y[i]
	var a := h.duplicate()
	var v := b.duplicate()
	for i in n:
		v[i] /= d[i]
		for j in n: a[i * n + j] /= d[i] * d[j]
	return {a = a, v = v, d = d, y = y, h = h,
		groups = [PackedInt32Array([0, 1]), PackedInt32Array([2, 3]), PackedInt32Array([4])]}


func _dense_and_coupled() -> void:
	var case := _dense_case()
	var input_bytes := var_to_bytes([case.a, case.v, case.d, case.groups])
	var result := T.solve(case.a, case.v, case.d, case.groups)
	_check("solver never mutates input mobility, slip, limits or groups", input_bytes == var_to_bytes([case.a, case.v, case.d, case.groups]))
	_verify("coupled tires and brake", case.a, case.v, case.d, case.groups, result)
	_check("dense coupled answer matches independent constructed KKT optimum", result.get("ok", false) and _distance(result.normalized_impulse, case.y) < 1e-8)
	_check("declared group impulses retain caller wheel/brake row order", result.get("ok", false) and result.group_impulses.size() == 3
		and result.group_impulses[0][0] == result.impulse[0] and result.group_impulses[2][0] == result.impulse[4])
	_check("same problem gives deterministic bytes", var_to_bytes(result) == var_to_bytes(T.solve(case.a, case.v, case.d, case.groups)))
	var insufficient := T.solve(case.a, case.v, case.d, case.groups, 1)
	_check("budget failure never publishes an approximate impulse", not insufficient.ok and not insufficient.converged
		and insufficient.status == "nonconverged" and not insufficient.has("impulse"))
	var units := _p([1e-6, 1e3, 1e5, 1e-4, 1e2])
	var unit_a: PackedFloat64Array = case.a.duplicate()
	var unit_v: PackedFloat64Array = case.v.duplicate()
	var unit_d: PackedFloat64Array = case.d.duplicate()
	for i in 5:
		unit_v[i] /= units[i]
		unit_d[i] *= units[i]
		for j in 5: unit_a[i * 5 + j] /= units[i] * units[j]
	var unit_result := T.solve(unit_a, unit_v, unit_d, case.groups)
	_verify("mixed row unit scaling", unit_a, unit_v, unit_d, case.groups, unit_result)
	_check("linear/angular unit conversion preserves dimensionless optimum", unit_result.get("ok", false)
		and _distance(unit_result.normalized_impulse, result.normalized_impulse) < 1e-9
		and absf(unit_result.dissipation - result.dissipation) < 1e-10)
	# Interior dense oracle generated from a chosen exact stationary point.
	var desired := _p([.1, -.2, .15, .1, -.1])
	var rhs := _neg(G.matrix_vector(case.a, desired, 5))
	var roomy := _p([2, 2, 2, 2, 2])
	var interior := T.solve(case.a, rhs, roomy, case.groups)
	_verify("dense static capture", case.a, rhs, roomy, case.groups, interior)
	_check("full-rank interior solution recovers chosen dense oracle", interior.get("ok", false)
		and _distance(interior.impulse, desired) < 1e-12 and interior.method == "feasible_spd_stationary")


func _semidefinite() -> void:
	var disk := [PackedInt32Array([0, 1])]
	for data: Array in [[_p([0, 0, 0, 0]), _p([3, 4]), _p([1, 1]), _p([-.6, -.8])],
			[_p([1, 1, 1, 1]), _p([1, -1]), _p([1, 1]), _p([-sqrt(.5), sqrt(.5)])],
			[_p([1, 1, 1, 1]), _p([-1, -1]), _p([1, 1]), _p([.5, .5])]]:
		var result := T.solve(data[0], data[1], data[2], disk)
		_verify("singular compact objective", data[0], data[1], data[2], disk, result)
		_check("singular/nullspace linear term has bounded analytic optimum", result.get("ok", false)
			and _distance(result.impulse, data[3]) < 1e-9 and result.psd_rank < 2)
	var rows := [_p([1.0, .3]), _p([2.0, -.4]), _p([-1.0, .8])]
	var gram := PackedFloat64Array()
	for i in 3:
		for j in 3: gram.append(G.dot(rows[i], rows[j], 2))
	var expected := _p([.6, -.8, 1.0])
	var linear := _neg(G.matrix_vector(gram, expected, 3))
	linear[0] -= .3 * expected[0]
	linear[1] -= .3 * expected[1]
	linear[2] -= .2 * expected[2]
	var redundant_groups := [PackedInt32Array([0, 1]), PackedInt32Array([2])]
	var redundant := T.solve(gram, linear, _p([1, 1, 1]), redundant_groups)
	_verify("redundant Gram contact rows", gram, linear, _p([1, 1, 1]), redundant_groups, redundant)
	_check("redundant contacts converge without a fictitious diagonal", redundant.get("ok", false)
		and _distance(redundant.impulse, expected) < 1e-8 and redundant.psd_rank == 2)
	var all_zero := T.solve(_p([0, 0, 0, 0]), _p([0, 0]), _p([1, 1]), disk)
	_check("flat zero objective selects deterministic zero impulse", all_zero.ok and all_zero.impulse == _p([0, 0]))


func _capacity() -> void:
	# Sixteen supports can require 64 tire/brake/rolling rows plus a shaft row.
	# Independent diagonal blocks have a closed-form disk/interval optimum.
	var count := 65
	var matrix := PackedFloat64Array()
	matrix.resize(count * count)
	var v := PackedFloat64Array()
	var limits := PackedFloat64Array()
	var expected := PackedFloat64Array()
	var groups: Array = []
	for i in count:
		matrix[i * count + i] = 1.0
		limits.append(1.0)
		v.append(-3.0 if i % 2 == 0 else 4.0)
		expected.append(.6 if i % 2 == 0 else -.8)
	for i in 32: groups.append(PackedInt32Array([2 * i, 2 * i + 1]))
	groups.append(PackedInt32Array([64]))
	expected[64] = 1.0
	var out := T.solve(matrix, v, limits, groups)
	_verify("65-row structured analytic capacity", matrix, v, limits, groups, out)
	_check("65 rows recover independent saturated disk/shaft answers", out.get("ok", false)
		and _distance(out.impulse, expected) < 1e-12 and T.MAX_DIMENSION == 128)
	var too_many := PackedFloat64Array()
	too_many.resize(129)
	var oversized_matrix := PackedFloat64Array()
	oversized_matrix.resize(129 * 129)
	var rejected := T.solve(oversized_matrix, too_many, too_many, _groups(129))
	_check("129 rows fail closed without publishing impulse", not rejected.ok and not rejected.has("impulse"))


func _validation() -> void:
	var good := _p([1, 0, 0, 1])
	var v := _p([1, 2])
	var d := _p([1, 1])
	var groups := [PackedInt32Array([0, 1])]
	for a: PackedFloat64Array in [_p([1, 2, 2, 1]), _p([1, .2, .3, 1]), _p([1, 0, 0, -1e-30]),
			_p([0, 1e-30, 1e-30, 1]), _p([1e20, 1, 1, 1e-22]), _p([1, 0, 0, NAN]), _p([1, 2])]:
		var result := T.solve(a, v, d, groups)
		_check("malformed/asymmetric/indefinite mobility rejected without impulse", not result.ok and not result.has("impulse"), str(result))
	for bad: Array in [[PackedInt32Array([0])], [PackedInt32Array([0, 0])], [PackedInt32Array([0, 2])], [[0, 1]], []]:
		_check("bad constraint partition rejected", not T.solve(good, v, d, bad).ok)
	_check("negative limits rejected", not T.solve(good, v, _p([-1, 1]), groups).ok)
	_check("nonfinite slip rejected", not T.solve(good, _p([INF, 0]), d, groups).ok)
	_check("limit dimension mismatch rejected", not T.solve(good, v, _p([1]), groups).ok)
	_check("invalid iteration budget rejected", not T.solve(good, v, d, groups, 0).ok)
	_check("normalization underflow fails explicitly", not T.solve(_p([1e-200]), _p([1e100]), _p([1e-100]), _groups(1)).ok)
	_check("numeric overflow fails closed", not T.solve(_p([1]), _p([1e308]), _p([1e308]), _groups(1)).ok)


func _response(wheel: Dictionary, force: PackedFloat64Array) -> PackedFloat64Array:
	var value := PackedFloat64Array([force[0] / 2.0, force[1] / 2.0, force[2] / 2.0])
	value.append_array(G.solve_body_local(wheel.factor, force.slice(3), 3, 1))
	return value


func _kinetic(z: PackedFloat64Array) -> float:
	return z[0] * z[0] + z[1] * z[1] + z[2] * z[2] \
		+ 0.5 * (z[3] * z[3] + z[4] * z[4] + z[5] * z[5]) - 0.1 * z[6] * z[4] + 0.5 * z[6] * z[6]


func _common_wheel_energy() -> void:
	# Hypothetical qualified fixed-axial WC fixture, not a stock inventory claim.
	var wheel := W.prepare(_p([1, 1, 1, 0, 0, 0]), _p([.1]), _p([.01]), _p([0, -1, 0]))
	_check("common wheel coupling fixture prepares", wheel.ok)
	if not wheel.ok: return
	var rows := [_p([1, 0, 0, 0, .2, 0, -1]), _p([0, 1, 0, -.2, 0, 0, 0]), _p([0, 0, 0, 0, 0, 0, 10])]
	var a := PackedFloat64Array()
	a.resize(9)
	for j in 3:
		var column := _response(wheel, rows[j])
		for i in 3: a[i * 3 + j] = G.dot(rows[i], column, 7)
	var initial := _p([3, .4, -.2, .1, -.2, .05, 1.7])
	var groups := [PackedInt32Array([0, 1]), PackedInt32Array([2])]
	for limits: PackedFloat64Array in [_p([.4, .4, .02]), _p([0, 0, .02])]:
		var slip := PackedFloat64Array()
		for row: PackedFloat64Array in rows: slip.append(G.dot(row, initial, 7))
		var result := T.solve(a, slip, limits, groups)
		_verify("WC contact/brake work", a, slip, limits, groups, result)
		if not result.ok: continue
		var impulse := PackedFloat64Array()
		impulse.resize(7)
		for i in 7:
			for j in 3: impulse[i] += rows[j][i] * result.impulse[j]
		var delta := _response(wheel, impulse)
		var after := initial.duplicate()
		for i in 7: after[i] += delta[i]
		_check("common coupled kinetic-energy change equals solver work", absf(_kinetic(after) - _kinetic(initial) + result.dissipation) < 1e-11)
		_check("linear momentum changes only by external tire impulse", absf(2.0 * delta[0] - result.impulse[0]) < 1e-12
			and absf(2.0 * delta[1] - result.impulse[1]) < 1e-12 and delta[2] == 0.0)
		_check("internal brake reaction preserves total coupled angular momentum",
			absf(delta[3] + .2 * result.impulse[1]) < 1e-12 and absf(delta[4] - .1 * delta[6] - .2 * result.impulse[0]) < 1e-12
			and absf(delta[5]) < 1e-12)
	# Moving ground can increase body energy while dissipating relative energy.
	var moving := T.solve(a, _p([-5, 0, 0]), _p([.4, .4, 0]), groups)
	_check("moving support solves relative maximum dissipation", moving.ok)
	if moving.ok:
		var impulse := PackedFloat64Array()
		impulse.resize(7)
		for i in 7:
			for j in 3: impulse[i] += rows[j][i] * moving.impulse[j]
		var after := _response(wheel, impulse)
		_check("prescribed-ground work supplies body gain and dissipation", _kinetic(after) > 0.0 and moving.dissipation > 0.0
			and absf(_kinetic(after) + moving.dissipation - 5.0 * moving.impulse[0]) < 1e-12)

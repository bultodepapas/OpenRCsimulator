## GP-12: fixed-center/frozen-pose CM + common-rotor impulse adapter.
## No body projection, mass inventory addition, coordinate reset or aircraft dispatch.
extends RefCounted

const RC := preload("res://physics/rotor_coupling.gd")
const GC := preload("res://physics/generalized_coordinates.gd")
const QP := preload("res://physics/ground_traction.gd")
const M := preload("res://physics/math3d.gd")
const LAW := "fixed-center-cm-common-rotor-ground-impulse-v1"
const MAX_ROTORS := 64
const MAX_ROWS := QP.MAX_DIMENSION
const RESIDUAL_RELATIVE_TOLERANCE := 1.0e-10
const CAPTURE_LAW := "finite-interior-relative-friction-capture-roundoff-polish-v1"
const CAPTURE_RELATIVE_ROUNDOFF := 128.0 * 2.220446049250313e-16


## z=[v_CM_body(3),omega_body(3),ALL relative sigma(rad/s)]. Bias is prescribed
## slip (carrier motion minus moving support), NOT a hidden state correction.
## Static relative holds are not composed here: caller must use a qualified joint
## policy, never silently break a hold or apply another projection afterward.
## Optional capture is EXACTLY {rotor_index:int,impulse_row:int}: one finite,
## independent +e_sigma friction row. Only an interior stationary QP solution
## within a declared floating-roundoff envelope may be polished to exact zero.
## Positive motion is preserved; genuine negative breakaway is unsupported.
static func apply(stage: Dictionary, mass_kg: float, velocity_cm_body: PackedFloat64Array,
		jacobian: PackedFloat64Array, prescribed_slip_bias: PackedFloat64Array,
		limits: PackedFloat64Array, groups: Array, iteration_budget: int = QP.MAX_ITERATIONS,
		capture: Dictionary = {}) -> Dictionary:
	var valid := _stage(stage)
	if not valid.ok: return valid
	var count: int = stage.axial.size()
	var n := 6 + count
	var rows := prescribed_slip_bias.size()
	if not is_finite(mass_kg) or mass_kg <= 0.0 or velocity_cm_body.size() != 3 \
		or not _finite(velocity_cm_body) or rows > MAX_ROWS or jacobian.size() != rows * n \
		or limits.size() != rows or not _finite(jacobian) or not _finite(prescribed_slip_bias) or not _finite(limits):
		return _failure("invalid CM mass, velocity or row layout")
	if rows == 0 and not groups.is_empty(): return _failure("zero rows cannot have constraint groups")
	if not capture.is_empty():
		var mapping := _capture_mapping(capture, count, jacobian, prescribed_slip_bias, groups)
		if not mapping.ok: return mapping
	var z := velocity_cm_body.duplicate()
	z.append_array(stage.velocity)
	var free_slip := PackedFloat64Array()
	for i in rows:
		var value := prescribed_slip_bias[i]
		for j in n: value += jacobian[i * n + j] * z[j]
		free_slip.append(value)
	if not _finite(free_slip): return _failure("free slip overflow")
	var response_columns: Array[PackedFloat64Array] = []
	for row in rows:
		var response := _response(valid.factor, count, mass_kg, jacobian.slice(row * n, (row + 1) * n))
		if response.size() != n or not _finite(response): return _failure("invalid generalized mass response")
		response_columns.append(response)
	var mobility := PackedFloat64Array()
	mobility.resize(rows * rows)
	for i in rows:
		for j in rows:
			var value := 0.0
			for k in n: value += jacobian[i * n + k] * response_columns[j][k]
			mobility[i * rows + j] = value
	var qp := {ok = true, converged = true, method = "empty_rows", impulse = PackedFloat64Array(),
		group_impulses = [], post_slip = PackedFloat64Array(), dissipation = 0.0}
	if rows > 0:
		qp = QP.solve(mobility, free_slip, limits, groups, iteration_budget)
		if not qp.ok: return {ok = false, status = "traction_nonconverged", reason = qp.get("reason", "traction rejected"), qp = qp}
	elif iteration_budget < 1 or iteration_budget > QP.MAX_ITERATIONS:
		return _failure("invalid iteration budget")
	var generalized_impulse := PackedFloat64Array()
	generalized_impulse.resize(n)
	for i in n:
		for row in rows: generalized_impulse[i] += jacobian[row * n + i] * qp.impulse[row]
	var delta := _response(valid.factor, count, mass_kg, generalized_impulse)
	if delta.size() != n or not _finite(delta): return _failure("impulse response overflow")
	var capture_receipt := {}
	if not capture.is_empty():
		var polished := _capture_polish(stage, mass_kg, z, jacobian, prescribed_slip_bias, limits,
			groups, mobility, qp, generalized_impulse, delta, capture)
		if not polished.ok: return polished
		qp = polished.qp
		generalized_impulse = polished.generalized_impulse
		delta = polished.delta
		capture_receipt = polished.receipt
	var next := z.duplicate()
	# Preserve exact signed-zero bytes on the zero-row path.
	if rows > 0:
		for i in n: next[i] += delta[i]
	if not _finite(next): return _failure("updated generalized velocity overflow")
	var angular_delta := delta.slice(3)
	var angular_before: PackedFloat64Array = stage.velocity
	var angular_after := next.slice(3)
	var before := 0.5 * mass_kg * M.dot(velocity_cm_body, velocity_cm_body) + RC._stage_energy(stage, angular_before)
	var after := 0.5 * mass_kg * M.dot(next.slice(0, 3), next.slice(0, 3)) + RC._stage_energy(stage, angular_after)
	var affine_work := GC.dot(stage.affine_momentum, angular_delta, 3 + count)
	var bias_work := -GC.dot(prescribed_slip_bias, qp.impulse, rows)
	var prescribed_work := affine_work + bias_work
	# Incremental kinetic difference avoids subtracting two large shaft energies.
	var incremental_change := GC.dot(z, generalized_impulse, n) + 0.5 * GC.dot(generalized_impulse, delta, n) + affine_work
	var closure := incremental_change + float(qp.dissipation) - prescribed_work
	var work_scale := maxf(1.0e-12, absf(incremental_change) + absf(affine_work) + absf(bias_work) + float(qp.dissipation))
	var totals_residual := after - before - incremental_change
	var totals_scale := maxf(1.0e-12, maxf(absf(before), absf(after)))
	var mass_residual := _mass_residual(stage.matrix, mass_kg, delta, generalized_impulse, count)
	var actual_post := PackedFloat64Array()
	var slip_residual := 0.0
	for row in rows:
		var value := prescribed_slip_bias[row]
		var row_magnitude := absf(value)
		for i in n:
			var term := jacobian[row * n + i] * next[i]
			value += term
			row_magnitude += absf(term)
		actual_post.append(value)
		# Both equivalent slip evaluations can cancel: a captured wheel may have
		# zero free/post slip while separate tire/brake A*p terms are large. Scale
		# backward error by those uncancelled terms, not only the near-zero result.
		var response_magnitude := absf(free_slip[row])
		for other in rows: response_magnitude += absf(mobility[row * rows + other] * qp.impulse[other])
		var scale := maxf(1.0e-12, maxf(row_magnitude, maxf(response_magnitude, absf(qp.post_slip[row]))))
		slip_residual = maxf(slip_residual, absf(value - qp.post_slip[row]) / scale)
		if not is_finite(row_magnitude) or not is_finite(response_magnitude): slip_residual = INF
	if not _finite(PackedFloat64Array([before, after, affine_work, bias_work, incremental_change, closure, totals_residual, mass_residual, slip_residual])) \
		or absf(closure) > RESIDUAL_RELATIVE_TOLERANCE * work_scale \
		or absf(totals_residual) > RESIDUAL_RELATIVE_TOLERANCE * totals_scale \
		or mass_residual > RESIDUAL_RELATIVE_TOLERANCE or slip_residual > RESIDUAL_RELATIVE_TOLERANCE:
		return _failure("generalized impulse, slip or energy closure could not be certified", "nonconverged")
	var result := {ok = true, status = "converged", law = LAW, fixed_centers = true, frozen_pose = true,
		velocity_cm_body = next.slice(0, 3), omega = next.slice(3, 6), spin = next.slice(6),
		delta_velocity_cm_body = delta.slice(0, 3), delta_omega = delta.slice(3, 6), delta_spin = delta.slice(6),
		generalized_impulse = generalized_impulse, impulse = qp.impulse, group_impulses = qp.group_impulses,
		free_slip = free_slip, post_slip = actual_post, mobility = mobility, qp = qp,
		kinetic_energy_before = before, kinetic_energy_after = after, kinetic_energy_change = incremental_change,
		kinetic_energy_change_from_totals = after - before, energy_totals_residual = totals_residual,
		affine_carrier_work = affine_work, prescribed_row_work = bias_work, total_prescribed_work = prescribed_work,
		dissipated_energy = qp.dissipation, energy_balance_residual = closure,
		mass_solve_relative_residual = mass_residual, slip_relative_residual = slip_residual,
		factor_rebuilt = true, work_frame = "prescribed_support_and_carrier_balance_not_visual_steering_motor_credit"}
	if not capture_receipt.is_empty(): result.capture = capture_receipt
	return result


static func _capture_mapping(capture: Dictionary, count: int, jacobian: PackedFloat64Array,
		bias: PackedFloat64Array, groups: Array) -> Dictionary:
	if capture.size() != 2 or not capture.has_all(["rotor_index", "impulse_row"]) \
		or typeof(capture.rotor_index) != TYPE_INT or typeof(capture.impulse_row) != TYPE_INT \
		or capture.rotor_index < 0 or capture.rotor_index >= count \
		or capture.impulse_row < 0 or capture.impulse_row >= bias.size():
		return _failure("capture needs one explicit rotor_index/impulse_row mapping", "invalid_capture")
	var row: int = capture.impulse_row
	var n := 6 + count
	if bias[row] != 0.0: return _failure("capture row cannot have prescribed slip bias", "invalid_capture")
	for i in n:
		if jacobian[row * n + i] != (1.0 if i == 6 + capture.rotor_index else 0.0):
			return _failure("capture row must be exactly the internal +e_sigma row", "invalid_capture")
	var found := 0
	for group: Variant in groups:
		if typeof(group) != TYPE_PACKED_INT32_ARRAY: return _failure("invalid capture constraint group", "invalid_capture")
		if group.has(row):
			if group.size() != 1: return _failure("capture row requires its own finite 1D group", "invalid_capture")
			found += 1
	if found != 1: return _failure("capture row must have exactly one constraint group", "invalid_capture")
	return {ok = true}


static func _capture_polish(stage: Dictionary, mass: float, z: PackedFloat64Array,
		jacobian: PackedFloat64Array, bias: PackedFloat64Array, limits: PackedFloat64Array,
		groups: Array, mobility: PackedFloat64Array, qp: Dictionary,
		generalized: PackedFloat64Array, delta: PackedFloat64Array, capture: Dictionary) -> Dictionary:
	var rotor: int = capture.rotor_index
	var row: int = capture.impulse_row
	var count: int = stage.axial.size()
	var coordinate := 6 + rotor
	var raw_sigma := z[coordinate] + delta[coordinate]
	var scale := absf(z[coordinate])
	for j in limits.size(): scale += absf(mobility[row * limits.size() + j] * qp.impulse[j])
	var tolerance := CAPTURE_RELATIVE_ROUNDOFF * scale
	if not is_finite(scale) or not is_finite(tolerance): return _failure("capture roundoff scale overflow", "invalid_capture")
	var receipt := {law = CAPTURE_LAW, rotor_index = rotor, impulse_row = row, polished = false,
		status = "already_zero" if raw_sigma == 0.0 else "moving_positive", raw_sigma_radps = raw_sigma,
		roundoff_envelope_radps = tolerance, impulse_before = qp.impulse[row], impulse_after = qp.impulse[row],
		impulse_limit = limits[row], impulse_correction = 0.0}
	var unchanged := {ok = true, qp = qp, generalized_impulse = generalized, delta = delta, receipt = receipt}
	if raw_sigma == 0.0:
		return unchanged
	var interior: bool = limits[row] > 0.0 and limits[row] - absf(qp.impulse[row]) > CAPTURE_RELATIVE_ROUNDOFF * limits[row]
	if not interior or absf(raw_sigma) > tolerance or absf(qp.post_slip[row]) > tolerance:
		if raw_sigma < 0.0: return _failure("finite shaft friction cannot certify nonnegative capture", "unsupported_reverse")
		return unchanged
	# Fix ONLY the desired relative increment, then solve every other free body/
	# rotor coordinate with the common mass metric. Recover the required impulse
	# in the SAME bounded friction row; it is not an additional stop impulse.
	var angular_size := 3 + count
	var held := 3 + rotor
	var free: Array[int] = [0, 1, 2]
	for i in count:
		if i != rotor: free.append(3 + i)
	var other := PackedFloat64Array()
	other.resize(z.size())
	for i in z.size():
		for j in limits.size():
			if j != row: other[i] += jacobian[j * z.size() + i] * qp.impulse[j]
	var desired := -z[coordinate]
	var reduced := PackedFloat64Array()
	reduced.resize(free.size() * free.size())
	var rhs := PackedFloat64Array()
	for i in free.size():
		rhs.append(other[3 + free[i]] - stage.matrix[free[i] * angular_size + held] * desired)
		for j in free.size(): reduced[i * free.size() + j] = stage.matrix[free[i] * angular_size + free[j]]
	var factor := GC.factor_body_local(reduced, 3, count - 1)
	if not factor.ok: return _decline_capture(unchanged, raw_sigma, "capture reduced common mass is not SPD", "nonconverged")
	var solved := GC.solve_body_local(factor, rhs, 3, count - 1)
	if solved.size() != free.size() or not _finite(solved): return _decline_capture(unchanged, raw_sigma, "capture free-coordinate solve failed", "nonconverged")
	var polished_delta := PackedFloat64Array([other[0] / mass, other[1] / mass, other[2] / mass])
	polished_delta.resize(z.size())
	polished_delta[coordinate] = desired
	for i in free.size(): polished_delta[3 + free[i]] = solved[i]
	var required := -other[coordinate]
	for i in angular_size: required += stage.matrix[held * angular_size + i] * polished_delta[3 + i]
	if not is_finite(required) or absf(required) > limits[row]:
		return _decline_capture(unchanged, raw_sigma, "exact static capture exceeds the original finite impulse capacity", "unsupported_reverse")
	var correction_rate: float = absf(required - qp.impulse[row]) * mobility[row * limits.size() + row]
	if not is_finite(correction_rate) or correction_rate > tolerance:
		return _decline_capture(unchanged, raw_sigma, "finite capture correction exceeds its floating-roundoff envelope", "nonconverged")
	var impulse: PackedFloat64Array = qp.impulse.duplicate()
	impulse[row] = required
	var recertified := _recertify(qp, mobility, bias, z, jacobian, limits, groups, impulse)
	if not recertified.ok: return _decline_capture(unchanged, raw_sigma, str(recertified.reason), "nonconverged")
	var polished_generalized := other.duplicate()
	polished_generalized[coordinate] += required
	if not _finite(polished_delta) or _mass_residual(stage.matrix, mass, polished_delta, polished_generalized, count) > RESIDUAL_RELATIVE_TOLERANCE:
		return _decline_capture(unchanged, raw_sigma, "finite static capture failed full common mass verification", "nonconverged")
	receipt.polished = true
	receipt.status = "captured_zero"
	receipt.impulse_after = required
	receipt.impulse_correction = required - qp.impulse[row]
	return {ok = true, qp = recertified, generalized_impulse = polished_generalized, delta = polished_delta, receipt = receipt}


static func _decline_capture(unchanged: Dictionary, raw_sigma: float, reason: String, status: String) -> Dictionary:
	# A failed optional zero-capture qualification does not erase valid positive
	# motion. The original QP is still verified below with its unchanged response.
	if raw_sigma > 0.0:
		unchanged.receipt.polish_declined_reason = reason
		return unchanged
	return _failure(reason, status)


## Re-certify the corrected impulse against the ORIGINAL convex objective and
## bounds, with the SAME tolerances. Refresh every dependent QP diagnostic.
static func _recertify(base: Dictionary, mobility: PackedFloat64Array, bias: PackedFloat64Array,
		z: PackedFloat64Array, jacobian: PackedFloat64Array, limits: PackedFloat64Array,
		groups: Array, impulse: PackedFloat64Array) -> Dictionary:
	var rows := limits.size()
	var validated := QP._validate_psd(mobility, rows)
	if not validated.ok: return _failure("capture original mobility failed validation", "nonconverged")
	var free_slip := bias.duplicate()
	for i in rows:
		for j in z.size(): free_slip[i] += jacobian[i * z.size() + j] * z[j]
	var y := PackedFloat64Array()
	var h := PackedFloat64Array()
	var b := PackedFloat64Array()
	h.resize(rows * rows)
	for i in rows:
		if limits[i] == 0.0 and impulse[i] != 0.0: return _failure("capture created zero-authority impulse", "nonconverged")
		y.append(impulse[i] / limits[i] if limits[i] > 0.0 else 0.0)
		b.append(limits[i] * free_slip[i] / base.objective_scale)
		for j in rows:
			var left: float = limits[i] * validated.diagonal_roots[i]
			var right: float = limits[j] * validated.diagonal_roots[j]
			h[i * rows + j] = validated.correlation[i * rows + j] * left * right / base.objective_scale
	if not _finite(y) or not _finite(h) or not _finite(b): return _failure("capture normalized verification overflow", "nonconverged")
	var certified := QP._certificate(h, b, y, limits, groups, base.kkt_tolerance_scaled)
	if not certified.ok: return _failure("capture failed global KKT/feasibility/complementarity verification", "nonconverged")
	var result := base.duplicate(true)
	var post := GC.matrix_vector(validated.matrix, impulse, rows)
	var linear := 0.0
	var quadratic := 0.0
	for i in rows:
		linear += free_slip[i] * impulse[i]
		quadratic += .5 * impulse[i] * post[i]
		post[i] += free_slip[i]
	var objective := linear + quadratic
	if not _finite(post) or not is_finite(objective) or objective > 0.0: return _failure("capture failed passive work verification", "nonconverged")
	var grouped: Array[PackedFloat64Array] = []
	for group: PackedInt32Array in groups:
		var values := PackedFloat64Array()
		for i: int in group: values.append(impulse[i])
		grouped.append(values)
	result.impulse = impulse.duplicate()
	result.group_impulses = grouped
	result.normalized_impulse = y
	result.post_slip = post
	result.linear_work = linear
	result.mobility_work = quadratic
	result.objective = objective
	result.dissipation = -objective
	result.kkt_residual_scaled = certified.stationarity
	result.complementarity_scaled = certified.complementarity
	result.feasibility_residual = certified.feasibility
	result.duality_gap = certified.duality_gap * base.objective_scale
	result.method = str(base.method) + ":finite_capture_polish"
	var correction := float(base.feasibility_roundoff_correction)
	for i in rows: correction = maxf(correction, absf(y[i] - base.normalized_impulse[i]))
	result.feasibility_roundoff_correction = correction
	if result.has("maximum_objective_increase_scaled"):
		result.maximum_objective_increase_scaled = maxf(result.maximum_objective_increase_scaled, (objective - base.objective) / base.objective_scale)
	return result


## contact_arm_cm_body ALREADY includes rho: it is the actual contact point's
## arm about live CM. Do not add rho again. Carrier nu acts about the fixed hub.
static func point_tangent(contact_arm_cm_body: PackedFloat64Array, rho_body: PackedFloat64Array,
		axis_body: PackedFloat64Array, rotor_index: int, tangent_body: PackedFloat64Array,
		rotor_count: int, carrier_rate_body := PackedFloat64Array([0.0, 0.0, 0.0]),
		ground_velocity_body := PackedFloat64Array([0.0, 0.0, 0.0])) -> Dictionary:
	if not _rotor_index(rotor_index, rotor_count) or not _vector(contact_arm_cm_body) or not _vector(rho_body) \
		or not _unit(axis_body) or not _unit(tangent_body) or not _vector(carrier_rate_body) or not _vector(ground_velocity_body):
		return _failure("invalid point tangent row geometry")
	var row := _row(rotor_count)
	var moment := M.cross(contact_arm_cm_body, tangent_body)
	for i in 3:
		row[i] = tangent_body[i]
		row[3 + i] = moment[i]
	row[6 + rotor_index] = M.dot(tangent_body, M.cross(axis_body, rho_body))
	var bias := M.dot(tangent_body, M.sub(M.cross(carrier_rate_body, rho_body), ground_velocity_body))
	return _built_row(row, bias)


## Internal brake acts only in relative sigma; carrier reaction emerges from M.
static func internal_brake(rotor_index: int, rotor_count: int) -> Dictionary:
	if not _rotor_index(rotor_index, rotor_count): return _failure("invalid internal brake row")
	var row := _row(rotor_count)
	row[6 + rotor_index] = 1.0
	return _built_row(row, 0.0)


## External resisting rotor couple: total absolute axle rate is a.omega+sigma+a.nu.
static func external_rolling(axis_body: PackedFloat64Array, rotor_index: int, rotor_count: int,
		carrier_rate_body := PackedFloat64Array([0.0, 0.0, 0.0])) -> Dictionary:
	if not _rotor_index(rotor_index, rotor_count) or not _unit(axis_body) or not _vector(carrier_rate_body):
		return _failure("invalid external rolling row")
	var row := _row(rotor_count)
	for i in 3: row[3 + i] = axis_body[i]
	row[6 + rotor_index] = 1.0
	return _built_row(row, M.dot(axis_body, carrier_rate_body))


static func _stage(stage: Dictionary) -> Dictionary:
	if typeof(stage.get("axial")) != TYPE_PACKED_FLOAT64_ARRAY or stage.axial.size() > MAX_ROTORS:
		return _failure("invalid or unbounded rotor stage")
	var count: int = stage.axial.size()
	var sizes := {carrier = 6, axial = count, transverse = count, axes = 3 * count,
		carrier_rates = 3 * count, matrix = (3 + count) * (3 + count), velocity = 3 + count, affine_momentum = 3 + count}
	for key: String in sizes:
		if typeof(stage.get(key)) != TYPE_PACKED_FLOAT64_ARRAY or stage[key].size() != sizes[key]:
			return _failure("invalid rotor stage dimensions")
	if typeof(stage.get("hold_indices")) != TYPE_PACKED_INT64_ARRAY or not stage.hold_indices.is_empty():
		return _failure("held rotor constraints require a qualified joint impulse policy", "unsupported_holds")
	# This existing validator reassembles M and affine momentum from the declared
	# component inventory/pose, then returns a fresh factor. Supplied factors are
	# never trusted, and no translational/rotor inventory is added a second time.
	var validated := RC._validate_stage(stage)
	if not validated.ok: return _failure("inconsistent rotor stage: " + str(validated.get("error", "invalid")))
	return validated


static func _response(factor: Dictionary, count: int, mass_kg: float, impulse: PackedFloat64Array) -> PackedFloat64Array:
	var out := PackedFloat64Array([impulse[0] / mass_kg, impulse[1] / mass_kg, impulse[2] / mass_kg])
	var angular := GC.solve_body_local(factor, impulse.slice(3), 3, count)
	if angular.size() != 3 + count: return PackedFloat64Array()
	out.append_array(angular)
	return out


static func _mass_residual(angular_matrix: PackedFloat64Array, mass: float, delta: PackedFloat64Array,
		impulse: PackedFloat64Array, count: int) -> float:
	var product := PackedFloat64Array([mass * delta[0], mass * delta[1], mass * delta[2]])
	product.append_array(GC.matrix_vector(angular_matrix, delta.slice(3), 3 + count))
	if not _finite(product): return INF
	var result := 0.0
	for i in impulse.size():
		# Scale by the terms before cancellation, as in a linear-solve backward
		# error. A zero generalized impulse can balance nonzero M*delta terms.
		var magnitude := absf(product[i])
		if i >= 3:
			magnitude = 0.0
			for j in 3 + count:
				magnitude += absf(angular_matrix[(i - 3) * (3 + count) + j] * delta[3 + j])
		if not is_finite(magnitude): return INF
		result = maxf(result, absf(product[i] - impulse[i]) / maxf(1e-12, maxf(magnitude, absf(impulse[i]))))
	return result


static func _row(count: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(6 + count)
	return out


static func _built_row(row: PackedFloat64Array, bias: float) -> Dictionary:
	if not _finite(row) or not is_finite(bias): return _failure("row geometry overflow")
	return {ok = true, row = row, bias = bias}


static func _rotor_index(index: int, count: int) -> bool:
	return count >= 1 and count <= MAX_ROTORS and index >= 0 and index < count


static func _vector(value: PackedFloat64Array) -> bool:
	return value.size() == 3 and _finite(value)


static func _unit(value: PackedFloat64Array) -> bool:
	return _vector(value) and absf(M.dot(value, value) - 1.0) <= 1e-12


static func _finite(value: PackedFloat64Array) -> bool:
	for number: float in value:
		if not is_finite(number): return false
	return true


static func _failure(reason: String, status := "invalid") -> Dictionary:
	return {ok = false, status = status, reason = reason, law = LAW}

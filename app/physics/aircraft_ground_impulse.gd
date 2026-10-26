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


## z=[v_CM_body(3),omega_body(3),ALL relative sigma(rad/s)]. Bias is prescribed
## slip (carrier motion minus moving support), NOT a hidden state correction.
## Static relative holds are not composed here: caller must use a qualified joint
## policy, never silently break a hold or apply another projection afterward.
static func apply(stage: Dictionary, mass_kg: float, velocity_cm_body: PackedFloat64Array,
		jacobian: PackedFloat64Array, prescribed_slip_bias: PackedFloat64Array,
		limits: PackedFloat64Array, groups: Array, iteration_budget: int = QP.MAX_ITERATIONS) -> Dictionary:
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
		var scale := maxf(1.0e-12, maxf(row_magnitude, maxf(absf(free_slip[row]), absf(qp.post_slip[row]))))
		slip_residual = maxf(slip_residual, absf(value - qp.post_slip[row]) / scale)
		if not is_finite(row_magnitude): slip_residual = INF
	if not _finite(PackedFloat64Array([before, after, affine_work, bias_work, incremental_change, closure, totals_residual, mass_residual, slip_residual])) \
		or absf(closure) > RESIDUAL_RELATIVE_TOLERANCE * work_scale \
		or absf(totals_residual) > RESIDUAL_RELATIVE_TOLERANCE * totals_scale \
		or mass_residual > RESIDUAL_RELATIVE_TOLERANCE or slip_residual > RESIDUAL_RELATIVE_TOLERANCE:
		return _failure("generalized impulse, slip or energy closure could not be certified", "nonconverged")
	return {ok = true, status = "converged", law = LAW, fixed_centers = true, frozen_pose = true,
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

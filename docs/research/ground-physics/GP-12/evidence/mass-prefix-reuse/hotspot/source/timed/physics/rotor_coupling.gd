# G2a/G2b: fixed-axis, axisymmetric rotor with speed relative to the locked aircraft.
# J is locked inertia (including the rotor); h = I*Omega*axis is additional relative momentum.
# Body: J*w_dot = M_ext - w cross (J*w+h) - I*Omega_dot*axis.
# Rotor: I*(Omega_dot + axis dot w_dot) = net_shaft_torque.
extends RefCounted
const Timing:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/metrics.gd")

const M = preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/physics/math3d.gd")
const RB = preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/physics/rigid_body.gd")
const GC := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/physics/generalized_coordinates.gd")
const Inventory := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/physics/mass_inventory.gd")
const SYSTEM_LAW := "aggregate-locked-prescribed-carrier-rotor-system-v1"
const STAGE_FORMAT := "openrc-rotor-system-stage v1"
const PROJECTION_LAW := "relative-spin-mass-metric-projection-v1"


## Pure simultaneous solve; inertia/axis are structurally valid owner configuration.
## A positive denominator means removing axial spin inertia leaves a physical carrier inertia.
static func response(body_rate: PackedFloat64Array, external_moment: PackedFloat64Array,
		inertia: PackedFloat64Array, inertia_inverse: PackedFloat64Array, axis: PackedFloat64Array,
		rotor_inertia: float, relative_speed: float, net_shaft_torque: float) -> Dictionary:
	if body_rate.size() != 3:
		return {ok = false}
	for value: float in body_rate:
		if not is_finite(value):
			return {ok = false}
	if external_moment.size() != 3:
		return {ok = false}
	for value: float in external_moment:
		if not is_finite(value):
			return {ok = false}
	if inertia.size() != 6:
		return {ok = false}
	for value: float in inertia:
		if not is_finite(value):
			return {ok = false}
	if inertia_inverse.size() != 6:
		return {ok = false}
	for value: float in inertia_inverse:
		if not is_finite(value):
			return {ok = false}
	if axis.size() != 3:
		return {ok = false}
	for value: float in axis:
		if not is_finite(value):
			return {ok = false}
	if absf(M.dot(axis, axis) - 1.0) > 1e-12:
		return {ok = false}
	# Inline the exact math3d/rigid_body scalar order. Only the returned momentum and reaction need arrays.
	var inverse_axis_x: float = inertia_inverse[0] * axis[0] + inertia_inverse[3] * axis[1] + inertia_inverse[4] * axis[2]
	var inverse_axis_y: float = inertia_inverse[3] * axis[0] + inertia_inverse[1] * axis[1] + inertia_inverse[5] * axis[2]
	var inverse_axis_z: float = inertia_inverse[4] * axis[0] + inertia_inverse[5] * axis[1] + inertia_inverse[2] * axis[2]
	var axis_inverse_axis: float = axis[0] * inverse_axis_x + axis[1] * inverse_axis_y + axis[2] * inverse_axis_z
	var denominator: float = 1.0 - rotor_inertia * axis_inverse_axis
	if not is_finite(denominator) or denominator <= 0.0 or not is_finite(rotor_inertia) or rotor_inertia <= 0.0 \
			or not is_finite(relative_speed) or relative_speed < 0.0 or not is_finite(net_shaft_torque):
		return {ok = false}
	var momentum_scale: float = rotor_inertia * relative_speed
	var momentum_x: float = axis[0] * momentum_scale
	var momentum_y: float = axis[1] * momentum_scale
	var momentum_z: float = axis[2] * momentum_scale
	var total_h_x: float = inertia[0] * body_rate[0] + inertia[3] * body_rate[1] + inertia[4] * body_rate[2] + momentum_x
	var total_h_y: float = inertia[3] * body_rate[0] + inertia[1] * body_rate[1] + inertia[5] * body_rate[2] + momentum_y
	var total_h_z: float = inertia[4] * body_rate[0] + inertia[5] * body_rate[1] + inertia[2] * body_rate[2] + momentum_z
	var cross_x: float = body_rate[1] * total_h_z - body_rate[2] * total_h_y
	var cross_y: float = body_rate[2] * total_h_x - body_rate[0] * total_h_z
	var cross_z: float = body_rate[0] * total_h_y - body_rate[1] * total_h_x
	var moment_delta_x: float = external_moment[0] - cross_x
	var moment_delta_y: float = external_moment[1] - cross_y
	var moment_delta_z: float = external_moment[2] - cross_z
	var unreacted_x: float = inertia_inverse[0] * moment_delta_x + inertia_inverse[3] * moment_delta_y + inertia_inverse[4] * moment_delta_z
	var unreacted_y: float = inertia_inverse[3] * moment_delta_x + inertia_inverse[1] * moment_delta_y + inertia_inverse[5] * moment_delta_z
	var unreacted_z: float = inertia_inverse[4] * moment_delta_x + inertia_inverse[5] * moment_delta_y + inertia_inverse[2] * moment_delta_z
	var axial_unreacted: float = axis[0] * unreacted_x + axis[1] * unreacted_y + axis[2] * unreacted_z
	var acceleration: float = (net_shaft_torque / rotor_inertia - axial_unreacted) / denominator
	var reaction_scale: float = -rotor_inertia * acceleration
	var reaction_x: float = axis[0] * reaction_scale
	var reaction_y: float = axis[1] * reaction_scale
	var reaction_z: float = axis[2] * reaction_scale
	if not is_finite(acceleration):
		return {ok = false}
	if not is_finite(reaction_x) or not is_finite(reaction_y) or not is_finite(reaction_z):
		return {ok = false}
	return {ok = true, spin_acceleration = acceleration,
		reaction = M.v3(reaction_x, reaction_y, reaction_z), momentum = M.v3(momentum_x, momentum_y, momentum_z)}


## Estimated AGGREGATE partition, not a physical split of named gear/engine parts.
## The original locked tensor is retained at the declared reference pose. Rotor
## intrinsic C=K*Id+(J-K)*a*a^T is reserved once; the body-fixed remainder must be
## SPD and physically realizable. Wheel translational/orbital mass is not added.
static func prepare_system(locked_reference: PackedFloat64Array, axial: PackedFloat64Array,
		transverse: PackedFloat64Array, reference_axes: PackedFloat64Array, partition: Dictionary) -> Dictionary:
	if not _rotors_valid(axial, transverse, reference_axes) or not Inventory.is_physical_tensor(locked_reference):
		return _failure("invalid rotor system inventory")
	if partition.size() != 4 or partition.get("kind", "") != "estimated":
		return _failure("aggregate partition must be explicitly estimated")
	for field: String in ["partition_id", "reference_pose_id", "source"]:
		if typeof(partition.get(field)) != TYPE_STRING or str(partition[field]).strip_edges().is_empty() \
				or str(partition[field]).length() > 4096:
			return _failure("aggregate partition needs bounded identity and provenance")
	var remainder := _carrier_remainder(locked_reference, axial, transverse, reference_axes)
	if not Inventory.is_physical_tensor(remainder):
		return _failure("aggregate rotor reservation leaves nonphysical carrier inertia")
	var assembled := _assemble(remainder, axial, transverse, reference_axes)
	if not assembled.ok:
		return assembled
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(SYSTEM_LAW.to_utf8_buffer())
	hash.update((";rotors=" + str(axial.size()) + ";").to_utf8_buffer())
	for value: PackedFloat64Array in [locked_reference, axial, transverse, reference_axes]:
		if not value.is_empty():
			hash.update(value.to_byte_array())
	hash.update(JSON.stringify(partition, "", true, true).to_utf8_buffer())
	return {ok = true, law = SYSTEM_LAW, identity = hash.finish().hex_encode(), partition = partition.duplicate(true),
		locked_reference = locked_reference.duplicate(), axial = axial.duplicate(), transverse = transverse.duplicate(),
		reference_axes = reference_axes.duplicate()}


## Internal coordinates are ALL relative rad/s, including wheels and shafts.
## live_locked_reference is the same reference pose tensor sampled at this stage's
## resource amount. No fuel I_dot or new flux law is introduced. Mechanical Tdot
## below excludes resource mass/energy flux, which stays with its existing owner.
## moment_external is already at live CG: the owning adapter transfers O->CG once.
## Full external rotor couples belong in that total once; internal drive/brake
## torque/reaction cancels in the total and belongs only in internal_spin_torques.
static func _profiled_evaluate_system(prepared: Dictionary, live_locked_reference: PackedFloat64Array,
		omega: PackedFloat64Array, relative_spin: PackedFloat64Array, axes: PackedFloat64Array,
		carrier_rates: PackedFloat64Array, carrier_accels: PackedFloat64Array, moment_external: PackedFloat64Array,
		external_rotor_couples: PackedFloat64Array, internal_spin_torques: PackedFloat64Array, holds: Array = []) -> Dictionary:
	if not prepared.get("ok", false) or prepared.get("law", "") != SYSTEM_LAW:
		return _failure("unprepared rotor system")
	if not Inventory.is_physical_tensor(live_locked_reference):
		return _failure("invalid live locked reference inertia")
	var remainder := _carrier_remainder(live_locked_reference, prepared.axial, prepared.transverse, prepared.reference_axes)
	var out := _evaluate_carrier(remainder, prepared.axial, prepared.transverse, omega, relative_spin, axes,
		carrier_rates, carrier_accels, moment_external, external_rotor_couples, internal_spin_torques, holds)
	if out.has("stage"):
		out.stage.system_identity = prepared.identity
	out.system_identity = prepared.identity
	return out


## Common GP-09b component assembly; WheelCoupling is only its rim-unit adapter.
## Body-fixed remainder and fixed centers; prescribed mechanism carriers are
## ideal/massless. nu_dot is the derivative in BODY coordinates; a_dot=nu cross a.
static func _profiled__evaluate_carrier(carrier: PackedFloat64Array, axial: PackedFloat64Array, transverse: PackedFloat64Array,
		omega: PackedFloat64Array, spin: PackedFloat64Array, axes: PackedFloat64Array, rates: PackedFloat64Array,
		accels: PackedFloat64Array, moment: PackedFloat64Array, external: PackedFloat64Array,
		internal: PackedFloat64Array, holds: Array = []) -> Dictionary:
	var count := axial.size()
	if not Inventory.is_physical_tensor(carrier) or not _rotors_valid(axial, transverse, axes) \
			or omega.size() != 3 or moment.size() != 3 or spin.size() != count or internal.size() != count \
			or rates.size() != 3 * count or accels.size() != 3 * count or external.size() != 3 * count \
			or not _finite(omega) or not _finite(moment) or not _finite(spin) or not _finite(internal) \
			or not _finite(rates) or not _finite(accels) or not _finite(external):
		return _failure("invalid rotor system stage")
	var constraints := _validate_holds(holds, spin)
	if not constraints.ok:
		return constraints
	var assembled := _assemble(carrier, axial, transverse, axes)
	if not assembled.ok:
		return assembled
	var locked: PackedFloat64Array = assembled.locked
	var matrix: PackedFloat64Array = assembled.matrix
	var n := 3 + count
	var affine := PackedFloat64Array()
	affine.resize(n)
	var bias := M.v3(0.0, 0.0, 0.0)
	var local_rhs := PackedFloat64Array()
	for i in count:
		var a := axes.slice(3 * i, 3 * i + 3)
		var nu := rates.slice(3 * i, 3 * i + 3)
		var nu_dot := accels.slice(3 * i, 3 * i + 3)
		var a_dot := M.cross(nu, a)
		var c_nu := _rotor_mul(a, axial[i], transverse[i], nu)
		for k in 3:
			affine[k] += c_nu[k]
		affine[3 + i] = axial[i] * M.dot(a, nu)
		bias = M.add(bias, M.add(M.add(_rotor_rate_mul(a, a_dot, axial[i], transverse[i], M.add(omega, nu)),
			_rotor_mul(a, axial[i], transverse[i], nu_dot)), M.scale(a_dot, axial[i] * spin[i])))
		local_rhs.append(M.dot(a, external.slice(3 * i, 3 * i + 3)) + internal[i] \
			- axial[i] * (M.dot(a, nu_dot) + M.dot(a_dot, omega)))
	var velocity := omega.duplicate()
	velocity.append_array(spin)
	var generalized_momentum := GC.matrix_vector(matrix, velocity, n)
	for k in n:
		generalized_momentum[k] += affine[k]
	var rhs := M.sub(M.sub(moment, bias), M.cross(omega, generalized_momentum.slice(0, 3)))
	rhs.append_array(local_rhs)
	if not _finite(rhs) or not _finite(affine):
		return _failure("rotor transport overflow")
	# Eliminate held local accelerations exactly. Their unknown static torques are
	# recovered from the full rows AFTER every other wheel/shaft participates.
	var solved := _solve_holds(matrix, rhs, constraints.indices, count)
	if not solved.ok:
		return solved
	var stage := {format = STAGE_FORMAT, law = SYSTEM_LAW, system_identity = "carrier-owned-reference",
		carrier = carrier.duplicate(), locked = locked, axial = axial.duplicate(), transverse = transverse.duplicate(),
		axes = axes.duplicate(), carrier_rates = rates.duplicate(), matrix = matrix, factor = assembled.factor,
		velocity = velocity, affine_momentum = affine, generalized_momentum = generalized_momentum,
		generalized_rhs = rhs.duplicate(), hold_indices = constraints.indices.duplicate()}
	var hold_torques: PackedFloat64Array = solved.hold_torques
	var failed := PackedInt64Array()
	for j in constraints.indices.size():
		var index: int = constraints.indices[j]
		var capacity: float = constraints.capacities[j]
		if absf(hold_torques[index]) > capacity + 1.0e-12 * maxf(1.0, maxf(capacity, absf(hold_torques[index]))):
			failed.append(index)
	if not failed.is_empty():
		return {ok = false, status = "hold_capacity_exceeded", error = "static relative hold is infeasible",
			required_hold_torques = hold_torques, failed_rotor_indices = failed, stage = stage}
	var acceleration: PackedFloat64Array = solved.acceleration
	var effective_internal := internal.duplicate()
	for i in count:
		effective_internal[i] += hold_torques[i]
	var ledger := _ledger(carrier, axial, transverse, omega, spin, axes, rates, accels, moment,
		external, effective_internal, acceleration.slice(0, 3), acceleration.slice(3))
	if not ledger.ok:
		return ledger
	ledger.angular_acceleration = acceleration.slice(0, 3)
	ledger.spin_acceleration = acceleration.slice(3)
	ledger.hold_torques = hold_torques
	ledger.stage = stage
	ledger.law = SYSTEM_LAW
	return ledger


## Pure velocity projection at fixed pose/carrier rates. Only requested spin rows
## are constrained; a finite-capacity force hold is not implicitly an infinite
## impulse lock. The owner must select/recheck holds after its event transition.
## The returned increments include ALL free spins, not only body+stopped shaft.
static func project_relative_speeds(stage: Dictionary, stop_indices: Array) -> Dictionary:
	var valid := _validate_stage(stage)
	if not valid.ok:
		return valid
	var count: int = stage.axial.size()
	var checked := _validate_indices(stop_indices, count)
	if not checked.ok:
		return checked
	var indices: PackedInt64Array = checked.indices
	var n := count + 3
	var velocity: PackedFloat64Array = stage.velocity
	var delta := PackedFloat64Array()
	delta.resize(n)
	var impulses := PackedFloat64Array()
	impulses.resize(indices.size())
	var loss := 0.0
	if not indices.is_empty():
		var mobility := PackedFloat64Array()
		mobility.resize(n * indices.size())
		for j in indices.size():
			var unit := PackedFloat64Array()
			unit.resize(n)
			unit[3 + indices[j]] = 1.0
			var column := GC.solve_body_local(valid.factor, unit, 3, count)
			if column.size() != n:
				return _failure("invalid rotor projection factor")
			for row in n:
				mobility[row * indices.size() + j] = column[row]
		var w := PackedFloat64Array()
		w.resize(indices.size() * indices.size())
		var target := PackedFloat64Array()
		for i in indices.size():
			target.append(-velocity[3 + indices[i]])
			for j in indices.size():
				w[i * indices.size() + j] = 0.5 * (mobility[(3 + indices[i]) * indices.size() + j] \
					+ mobility[(3 + indices[j]) * indices.size() + i])
		var factor := GC.cholesky_factor(w, indices.size())
		if not factor.ok:
			return _failure("dependent rotor projection constraints")
		impulses = GC.solve_cholesky(factor.lower, target, indices.size())
		if impulses.size() != indices.size():
			return _failure("rotor projection failed")
		for row in n:
			for j in indices.size():
				delta[row] += mobility[row * indices.size() + j] * impulses[j]
		for j in indices.size():
			loss -= 0.5 * impulses[j] * velocity[3 + indices[j]]
	var next := velocity.duplicate()
	for k in n:
		next[k] += delta[k]
	# Publish exact constraints only after checking the mass-metric solve residual.
	for index in indices:
		if absf(next[3 + index]) > 1.0e-11 * maxf(1.0, absf(velocity[3 + index])):
			return _failure("rotor projection constraint residual")
		next[3 + index] = 0.0
		delta[3 + index] = -velocity[3 + index]
	var work := GC.dot(stage.affine_momentum, delta, n)
	var before := _stage_energy(stage, velocity)
	var after := _stage_energy(stage, next)
	var residual := after - before - work + loss
	if not _finite(next) or not _finite(PackedFloat64Array([before, after, work, loss, residual])) or loss < 0.0 \
			or absf(residual) > 1.0e-10 * maxf(1.0, maxf(absf(before), maxf(absf(after), absf(work)))):
		return _failure("invalid rotor projection energy")
	return {ok = true, law = PROJECTION_LAW, system_identity = stage.system_identity,
		velocity = next, angular_delta = delta.slice(0, 3), spin_delta = delta.slice(3),
		constraint_impulses = impulses, kinetic_energy_before = before, kinetic_energy_after = after,
		actuator_impulse_work = work, dissipated_energy = loss, energy_balance_residual = residual}


static func _profiled__assemble(carrier: PackedFloat64Array, axial: PackedFloat64Array,
		transverse: PackedFloat64Array, axes: PackedFloat64Array) -> Dictionary:
	var locked := carrier.duplicate()
	for i in axial.size():
		_add_rotor_tensor(locked, axes.slice(3 * i, 3 * i + 3), axial[i], transverse[i])
	var n := 3 + axial.size()
	var matrix := PackedFloat64Array()
	matrix.resize(n * n)
	var tensor := PackedFloat64Array([locked[0], locked[3], locked[4], locked[3], locked[1], locked[5], locked[4], locked[5], locked[2]])
	for row in 3:
		for col in 3:
			matrix[row * n + col] = tensor[row * 3 + col]
	for i in axial.size():
		for k in 3:
			matrix[k * n + 3 + i] = axial[i] * axes[3 * i + k]
			matrix[(3 + i) * n + k] = matrix[k * n + 3 + i]
		matrix[(3 + i) * n + 3 + i] = axial[i]
	var full := GC.cholesky_factor(matrix, n)
	var factor := GC.factor_body_local(matrix, 3, axial.size())
	if not full.ok or not factor.ok:
		return _failure("rotor mass matrix/residual is not SPD")
	return {ok = true, matrix = matrix, factor = factor, locked = locked}


static func _solve_holds(matrix: PackedFloat64Array, rhs: PackedFloat64Array,
		indices: PackedInt64Array, count: int) -> Dictionary:
	var n := count + 3
	var active := PackedInt64Array([0, 1, 2])
	for i in count:
		if not indices.has(i):
			active.append(3 + i)
	var reduced := PackedFloat64Array()
	reduced.resize(active.size() * active.size())
	var reduced_rhs := PackedFloat64Array()
	for row in active.size():
		reduced_rhs.append(rhs[active[row]])
		for col in active.size():
			reduced[row * active.size() + col] = matrix[active[row] * n + active[col]]
	var factor := GC.factor_body_local(reduced, 3, active.size() - 3)
	if not factor.ok:
		return _failure("held rotor reduced matrix is not SPD")
	var free := GC.solve_body_local(factor, reduced_rhs, 3, active.size() - 3)
	if free.size() != active.size():
		return _failure("held rotor solve failed")
	var acceleration := PackedFloat64Array()
	acceleration.resize(n)
	for k in active.size():
		acceleration[active[k]] = free[k]
	var torque := PackedFloat64Array()
	torque.resize(count)
	for index in indices:
		var value := -rhs[3 + index]
		for k in n:
			value += matrix[(3 + index) * n + k] * acceleration[k]
		torque[index] = value
	if not _finite(torque):
		return _failure("static relative hold torque overflow")
	return {ok = true, acceleration = acceleration, hold_torques = torque}


static func _profiled__ledger(carrier: PackedFloat64Array, axial: PackedFloat64Array, transverse: PackedFloat64Array,
		omega: PackedFloat64Array, spin: PackedFloat64Array, axes: PackedFloat64Array, rates: PackedFloat64Array,
		accels: PackedFloat64Array, moment: PackedFloat64Array, external: PackedFloat64Array, internal: PackedFloat64Array,
		alpha: PackedFloat64Array, spin_rate: PackedFloat64Array) -> Dictionary:
	var carrier_h := RB.inertia_mul(carrier, omega)
	var momentum := carrier_h.duplicate()
	var energy := 0.5 * M.dot(omega, carrier_h)
	var energy_rate := M.dot(omega, RB.inertia_mul(carrier, alpha))
	var external_power := M.dot(omega, moment)
	var internal_power := 0.0
	var actuator_power := 0.0
	var actuator_torques := PackedFloat64Array()
	for i in axial.size():
		var a := axes.slice(3 * i, 3 * i + 3)
		var nu := rates.slice(3 * i, 3 * i + 3)
		var a_dot := M.cross(nu, a)
		var absolute := M.add(M.add(omega, nu), M.scale(a, spin[i]))
		var absolute_rate := M.add(M.add(alpha, accels.slice(3 * i, 3 * i + 3)),
			M.add(M.scale(a, spin_rate[i]), M.scale(a_dot, spin[i])))
		var h := _rotor_mul(a, axial[i], transverse[i], absolute)
		var h_geometry_rate := _rotor_rate_mul(a, a_dot, axial[i], transverse[i], absolute)
		var h_velocity_rate := _rotor_mul(a, axial[i], transverse[i], absolute_rate)
		var demand := M.sub(M.add(M.add(h_geometry_rate, h_velocity_rate), M.cross(omega, h)), external.slice(3 * i, 3 * i + 3))
		actuator_torques.append_array(demand)
		momentum = M.add(momentum, h)
		energy += 0.5 * M.dot(absolute, h)
		energy_rate += M.dot(absolute, h_velocity_rate) + 0.5 * M.dot(absolute, h_geometry_rate)
		external_power += M.dot(M.add(nu, M.scale(a, spin[i])), external.slice(3 * i, 3 * i + 3))
		internal_power += internal[i] * spin[i]
		actuator_power += M.dot(nu, demand)
	var residual := energy_rate - external_power - internal_power - actuator_power
	if not _finite(momentum) or not _finite(actuator_torques) \
			or not _finite(PackedFloat64Array([energy, energy_rate, external_power, internal_power, actuator_power, residual])):
		return _failure("rotor energy or momentum overflow")
	return {ok = true, angular_momentum = momentum, kinetic_energy = energy, kinetic_energy_rate = energy_rate,
		external_power = external_power, internal_spin_power = internal_power, actuator_power = actuator_power,
		actuator_torques = actuator_torques, power_residual = residual}


static func _stage_energy(stage: Dictionary, velocity: PackedFloat64Array) -> float:
	var count: int = stage.axial.size()
	var out := 0.5 * M.dot(velocity.slice(0, 3), RB.inertia_mul(stage.carrier, velocity.slice(0, 3)))
	for i in count:
		var absolute := M.add(M.add(velocity.slice(0, 3), stage.carrier_rates.slice(3 * i, 3 * i + 3)),
			M.scale(stage.axes.slice(3 * i, 3 * i + 3), velocity[3 + i]))
		out += 0.5 * M.dot(absolute, _rotor_mul(stage.axes.slice(3 * i, 3 * i + 3), stage.axial[i], stage.transverse[i], absolute))
	return out


static func _validate_holds(holds: Array, spin: PackedFloat64Array) -> Dictionary:
	var indices := []
	var capacities := PackedFloat64Array()
	for item: Variant in holds:
		if not item is Dictionary or item.size() != 2 or typeof(item.get("rotor_index")) != TYPE_INT \
				or typeof(item.get("capacity_nm")) not in [TYPE_FLOAT, TYPE_INT]:
			return _failure("malformed relative hold")
		var index: int = item.rotor_index
		var capacity: float = float(item.capacity_nm)
		if index < 0 or index >= spin.size() or not is_finite(capacity) or capacity < 0.0 or spin[index] != 0.0:
			return _failure("relative hold requires a valid zero-speed rotor and finite capacity")
		indices.append(index)
		capacities.append(capacity)
	var checked := _validate_indices(indices, spin.size())
	if checked.ok:
		checked.capacities = capacities
	return checked


static func _validate_indices(indices: Array, count: int) -> Dictionary:
	var packed := PackedInt64Array()
	for index: Variant in indices:
		if typeof(index) != TYPE_INT or index < 0 or index >= count or packed.has(index):
			return _failure("invalid or duplicate relative rotor constraint")
		packed.append(index)
	return {ok = true, indices = packed}


static func _profiled__validate_stage(stage: Dictionary) -> Dictionary:
	if stage.get("format", "") != STAGE_FORMAT or stage.get("law", "") != SYSTEM_LAW \
			or typeof(stage.get("system_identity")) != TYPE_STRING:
		return _failure("invalid rotor projection stage")
	for key: String in ["carrier", "axial", "transverse", "axes", "carrier_rates", "matrix", "velocity", "affine_momentum"]:
		if typeof(stage.get(key)) != TYPE_PACKED_FLOAT64_ARRAY or not _finite(stage[key]):
			return _failure("malformed rotor projection stage")
	var count: int = stage.axial.size()
	var n := 3 + count
	if not _rotors_valid(stage.axial, stage.transverse, stage.axes) or not Inventory.is_physical_tensor(stage.carrier) \
			or stage.carrier_rates.size() != 3 * count or stage.matrix.size() != n * n \
			or stage.velocity.size() != n or stage.affine_momentum.size() != n or typeof(stage.get("factor")) != TYPE_DICTIONARY:
		return _failure("invalid rotor projection layout")
	var expected := _assemble(stage.carrier, stage.axial, stage.transverse, stage.axes)
	if not expected.ok or expected.matrix != stage.matrix:
		return _failure("projection matrix differs from its component inventory")
	var affine := PackedFloat64Array()
	affine.resize(n)
	for i in count:
		var a: PackedFloat64Array = stage.axes.slice(3 * i, 3 * i + 3)
		var nu: PackedFloat64Array = stage.carrier_rates.slice(3 * i, 3 * i + 3)
		var h := _rotor_mul(a, stage.axial[i], stage.transverse[i], nu)
		for k in 3:
			affine[k] += h[k]
		affine[3 + i] = stage.axial[i] * M.dot(a, nu)
	if affine != stage.affine_momentum:
		return _failure("projection affine momentum differs from prescribed carrier rates")
	return {ok = true, factor = expected.factor}


static func _profiled__rotors_valid(axial: PackedFloat64Array, transverse: PackedFloat64Array, axes: PackedFloat64Array) -> bool:
	if transverse.size() != axial.size() or axes.size() != 3 * axial.size() or not _finite(axial) or not _finite(transverse) or not _finite(axes):
		return false
	for i in axial.size():
		if axial[i] <= 0.0 or transverse[i] <= 0.0 or 0.5 * axial[i] > transverse[i] \
				or absf(M.dot(axes.slice(3 * i, 3 * i + 3), axes.slice(3 * i, 3 * i + 3)) - 1.0) > 1.0e-12:
			return false
	return true


static func _carrier_remainder(locked: PackedFloat64Array, axial: PackedFloat64Array,
		transverse: PackedFloat64Array, axes: PackedFloat64Array) -> PackedFloat64Array:
	var carrier := locked.duplicate()
	for i in axial.size():
		_add_rotor_tensor(carrier, axes.slice(3 * i, 3 * i + 3), -axial[i], -transverse[i])
	return carrier


static func _rotor_mul(a: PackedFloat64Array, axial: float, transverse: float, value: PackedFloat64Array) -> PackedFloat64Array:
	return M.add(M.scale(value, transverse), M.scale(a, (axial - transverse) * M.dot(a, value)))


static func _rotor_rate_mul(a: PackedFloat64Array, a_dot: PackedFloat64Array, axial: float,
		transverse: float, value: PackedFloat64Array) -> PackedFloat64Array:
	return M.scale(M.add(M.scale(a_dot, M.dot(a, value)), M.scale(a, M.dot(a_dot, value))), axial - transverse)


static func _add_rotor_tensor(tensor: PackedFloat64Array, a: PackedFloat64Array, axial: float, transverse: float) -> void:
	var d := axial - transverse
	tensor[0] += transverse + d * a[0] * a[0]
	tensor[1] += transverse + d * a[1] * a[1]
	tensor[2] += transverse + d * a[2] * a[2]
	tensor[3] += d * a[0] * a[1]
	tensor[4] += d * a[0] * a[2]
	tensor[5] += d * a[1] * a[2]


static func _finite(values: PackedFloat64Array) -> bool:
	for value in values:
		if not is_finite(value):
			return false
	return true


static func _failure(message: String) -> Dictionary:
	return {ok = false, status = "invalid", error = message}

static func evaluate_system(prepared: Dictionary, live_locked_reference: PackedFloat64Array,
		omega: PackedFloat64Array, relative_spin: PackedFloat64Array, axes: PackedFloat64Array,
		carrier_rates: PackedFloat64Array, carrier_accels: PackedFloat64Array, moment_external: PackedFloat64Array,
		external_rotor_couples: PackedFloat64Array, internal_spin_torques: PackedFloat64Array, holds: Array = []) -> Dictionary:
	Timing.enter("rotor_coupling.evaluate_system")
	var measured:=_profiled_evaluate_system(prepared,live_locked_reference,omega,relative_spin,axes,carrier_rates,carrier_accels,moment_external,external_rotor_couples,internal_spin_torques,holds)
	Timing.leave()
	return measured

static func _validate_stage(stage: Dictionary) -> Dictionary:
	Timing.enter("rotor_coupling._validate_stage")
	var measured:=_profiled__validate_stage(stage)
	Timing.leave()
	return measured

static func _rotors_valid(axial: PackedFloat64Array, transverse: PackedFloat64Array, axes: PackedFloat64Array) -> bool:
	Timing.enter("rotor_coupling._rotors_valid")
	var measured:=_profiled__rotors_valid(axial,transverse,axes)
	Timing.leave()
	return measured

static func _evaluate_carrier(carrier: PackedFloat64Array, axial: PackedFloat64Array, transverse: PackedFloat64Array,
		omega: PackedFloat64Array, spin: PackedFloat64Array, axes: PackedFloat64Array, rates: PackedFloat64Array,
		accels: PackedFloat64Array, moment: PackedFloat64Array, external: PackedFloat64Array,
		internal: PackedFloat64Array, holds: Array = []) -> Dictionary:
	Timing.enter("rotor_coupling._evaluate_carrier")
	var measured:=_profiled__evaluate_carrier(carrier,axial,transverse,omega,spin,axes,rates,accels,moment,external,internal,holds)
	Timing.leave()
	return measured

static func _assemble(carrier: PackedFloat64Array, axial: PackedFloat64Array,
		transverse: PackedFloat64Array, axes: PackedFloat64Array) -> Dictionary:
	Timing.enter("rotor_coupling._assemble")
	var measured:=_profiled__assemble(carrier,axial,transverse,axes)
	Timing.leave()
	return measured

static func _ledger(carrier: PackedFloat64Array, axial: PackedFloat64Array, transverse: PackedFloat64Array,
		omega: PackedFloat64Array, spin: PackedFloat64Array, axes: PackedFloat64Array, rates: PackedFloat64Array,
		accels: PackedFloat64Array, moment: PackedFloat64Array, external: PackedFloat64Array, internal: PackedFloat64Array,
		alpha: PackedFloat64Array, spin_rate: PackedFloat64Array) -> Dictionary:
	Timing.enter("rotor_coupling._ledger")
	var measured:=_profiled__ledger(carrier,axial,transverse,omega,spin,axes,rates,accels,moment,external,internal,alpha,spin_rate)
	Timing.leave()
	return measured

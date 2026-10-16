extends RefCounted
## CR-33b: bounded, isolated rigid-body impact-energy estimates.
## This helper does not observe solver work, infer damage, or mutate a vehicle.

const M := preload("res://physics/math3d.gd")
const BASIS := "isolated_estimate"
const NORMAL_TOLERANCE := 1e-9


## Estimate one instantaneous contact in body coordinates. The 6-value inverse-inertia
## layout matches RigidBody: [Ixx, Iyy, Izz, Ixy, Ixz, Iyz].
## Required sample keys and units are explicit in their names; input_provenance requires
## nonempty `source` and `evidence_id`, plus `state_stage: accepted_tick`. The normal points away from the contacted surface,
## so negative normal velocity is closing. Only normal restitution loss is estimated.
static func estimate_contact(sample: Dictionary) -> Dictionary:
	var errors: Array[String] = _validate_contact(sample)
	if not errors.is_empty():
		return _failure(errors)

	var mass_kg: float = float(sample.mass_kg)
	var inverse_mass_kg_inv: float = float(sample.inverse_mass_kg_inv)
	var inverse_inertia: PackedFloat64Array = sample.inverse_inertia_body_kg_m2_inv
	var arm: PackedFloat64Array = sample.arm_body_m
	var normal: PackedFloat64Array = sample.normal_body_unit
	var linear_velocity: PackedFloat64Array = sample.linear_velocity_body_mps
	var angular_velocity: PackedFloat64Array = sample.angular_velocity_body_radps
	var restitution: float = float(sample.restitution)
	var input_provenance: Dictionary = sample.input_provenance
	var source: String = String(input_provenance.source)
	var evidence_id: String = String(input_provenance.evidence_id)

	var angular_jacobian: PackedFloat64Array = M.cross(arm, normal)
	var rotational_inverse_mass: PackedFloat64Array = PackedFloat64Array([
		inverse_inertia[0] * angular_jacobian[0] + inverse_inertia[3] * angular_jacobian[1] + inverse_inertia[4] * angular_jacobian[2],
		inverse_inertia[3] * angular_jacobian[0] + inverse_inertia[1] * angular_jacobian[1] + inverse_inertia[5] * angular_jacobian[2],
		inverse_inertia[4] * angular_jacobian[0] + inverse_inertia[5] * angular_jacobian[1] + inverse_inertia[2] * angular_jacobian[2],
	])
	var effective_inverse_mass_kg_inv: float = inverse_mass_kg_inv + M.dot(angular_jacobian, rotational_inverse_mass)
	if not is_finite(effective_inverse_mass_kg_inv) or effective_inverse_mass_kg_inv <= 0.0:
		return _failure(["contact effective inverse mass is not finite and positive"])
	var effective_mass_kg: float = 1.0 / effective_inverse_mass_kg_inv
	if not is_finite(effective_mass_kg) or effective_mass_kg <= 0.0:
		return _failure(["contact effective mass is not finite and positive"])

	var rotational_velocity: PackedFloat64Array = M.cross(angular_velocity, arm)
	var contact_velocity: PackedFloat64Array = M.add(linear_velocity, rotational_velocity)
	var normal_velocity_mps: float = M.dot(contact_velocity, normal)
	var tangent_velocity: PackedFloat64Array = M.sub(contact_velocity, M.scale(normal, normal_velocity_mps))
	var tangent_speed_mps: float = M.norm(tangent_velocity)
	var closing_speed_mps: float = maxf(-normal_velocity_mps, 0.0)
	if not _finite_vector3(contact_velocity) or not is_finite(normal_velocity_mps) \
			or not _finite_vector3(tangent_velocity) or not is_finite(tangent_speed_mps):
		return _failure(["contact velocity calculation overflowed or became nonfinite"])

	# Restitution only removes energy from the normal closing mode. Tangential speed is
	# diagnostic; absent a measured/accepted friction impulse, no tangential loss is added.
	var candidate_energy_j: float = 0.5 * effective_mass_kg * closing_speed_mps * closing_speed_mps \
		* (1.0 - restitution * restitution)
	if not is_finite(candidate_energy_j) or candidate_energy_j < 0.0:
		return _failure(["normal restitution energy is not finite and nonnegative"])

	var tick: int = int(sample.tick)
	var episode_id: String = String(sample.episode_id)
	return {
		"ok": true,
		"basis": BASIS,
		"contact_id": String(sample.contact_id),
		"episode_id": episode_id,
		"tick": tick,
		"effective_inverse_mass": _quantity(effective_inverse_mass_kg_inv, "kg^-1", source, evidence_id),
		"effective_mass": _quantity(effective_mass_kg, "kg", source, evidence_id),
		"contact_velocity": _quantity(contact_velocity, "m/s", source, evidence_id),
		"normal_velocity": _quantity(normal_velocity_mps, "m/s", source, evidence_id),
		"closing_normal_speed": _quantity(closing_speed_mps, "m/s", source, evidence_id),
		"tangent_velocity": _quantity(tangent_velocity, "m/s", source, evidence_id),
		"tangent_speed": _quantity(tangent_speed_mps, "m/s", source, evidence_id),
		"restitution": _quantity(restitution, "1", source, evidence_id),
		"candidate_restitution_loss_energy": _quantity(candidate_energy_j, "J", source, evidence_id),
		"provenance": {
			"kind": BASIS,
			"method": "single-contact effective-mass normal restitution estimate",
			"input_source": source,
			"input_evidence_id": evidence_id,
			"input_state_stage": String(input_provenance.state_stage),
			"accepted_work_observed": false,
			"limitations": ["no frictional loss", "no failure threshold", "no speculative or next-tick slapdown energy"],
		},
		"input_mass": _quantity(mass_kg, "kg", source, evidence_id),
	}


## Estimate each unique contact from one simultaneous episode, then apportion no more than
## the caller-supplied total budget and no more than the sum of candidate estimates.
## `budget_source` records provenance; this routine does not prove that it is solver work.
static func allocate_episode(samples: Array, accepted_total_budget_j: float, budget_source: String) -> Dictionary:
	var errors: Array[String] = []
	if not is_finite(accepted_total_budget_j) or accepted_total_budget_j < 0.0:
		errors.append("accepted_total_budget_j must be finite and nonnegative")
	if budget_source.strip_edges().is_empty():
		errors.append("budget_source must be a nonempty provenance string")
	if samples.is_empty():
		errors.append("an episode requires at least one contact sample")
	if not errors.is_empty():
		return _failure(errors)

	var estimates_by_id: Dictionary = {}
	var sorted_ids := PackedStringArray()
	var episode_id := ""
	var tick := -1
	for index: int in range(samples.size()):
		var sample_value: Variant = samples[index]
		if typeof(sample_value) != TYPE_DICTIONARY:
			return _failure(["samples[%d] must be a contact dictionary" % index])
		var estimate: Dictionary = estimate_contact(sample_value)
		if not bool(estimate.get("ok", false)):
			var estimate_errors: Array = estimate.get("errors", [])
			var prefixed: Array[String] = []
			for error_value: Variant in estimate_errors:
				prefixed.append("samples[%d]: %s" % [index, String(error_value)])
			return _failure(prefixed)
		var contact_id: String = String(estimate.contact_id)
		if estimates_by_id.has(contact_id):
			return _failure(["duplicate contact_id '%s' would double-count one simultaneous contact" % contact_id])
		if index == 0:
			episode_id = String(estimate.episode_id)
			tick = int(estimate.tick)
		elif estimate.episode_id != episode_id or int(estimate.tick) != tick:
			return _failure(["all contacts in an episode must share episode_id and accepted tick"])
		estimates_by_id[contact_id] = estimate
		sorted_ids.append(contact_id)
	sorted_ids.sort()

	var candidate_total_j: float = 0.0
	for contact_id: String in sorted_ids:
		var estimate: Dictionary = estimates_by_id[contact_id]
		var candidate: float = float(estimate.candidate_restitution_loss_energy.value)
		candidate_total_j += candidate
		if not is_finite(candidate_total_j):
			return _failure(["episode candidate energy total overflowed"])

	var allocation_cap_j: float = minf(accepted_total_budget_j, candidate_total_j)
	var scale: float = allocation_cap_j / candidate_total_j if candidate_total_j > 0.0 else 0.0
	var allocations: Array[Dictionary] = []
	var allocated_total_j: float = 0.0
	for contact_id: String in sorted_ids:
		var estimate: Dictionary = estimates_by_id[contact_id]
		var candidate: float = float(estimate.candidate_restitution_loss_energy.value)
		var allocated: float = minf(candidate, candidate * scale)
		allocated_total_j += allocated
		if not is_finite(allocated_total_j):
			return _failure(["episode allocation total overflowed"])
		allocations.append({
			"contact_id": contact_id,
			"candidate_energy": estimate.candidate_restitution_loss_energy.duplicate(true),
			"allocated_energy": _quantity(allocated, "J", budget_source, "%s:%s" % [episode_id, str(tick)]),
			"candidate_partition_fraction": 0.0,
			"accepted_budget_partition_fraction": allocated / accepted_total_budget_j if accepted_total_budget_j > 0.0 else 0.0,
			"allocation_fraction_of_candidate": allocated / candidate if candidate > 0.0 else 0.0,
		})

	# Correct only possible final floating-point ulps, preserving sorted deterministic order.
	if allocated_total_j > allocation_cap_j and not allocations.is_empty():
		var preceding_total_j: float = 0.0
		for index: int in range(allocations.size() - 1):
			preceding_total_j += float(allocations[index].allocated_energy.value)
		var final_row: Dictionary = allocations[allocations.size() - 1]
		var final_amount: float = minf(float(final_row.allocated_energy.value), maxf(0.0, allocation_cap_j - preceding_total_j))
		final_row.allocated_energy = _quantity(final_amount, "J", budget_source, "%s:%s" % [episode_id, str(tick)])
		var final_candidate: float = float(final_row.candidate_energy.value)
		final_row.allocation_fraction_of_candidate = final_amount / final_candidate if final_candidate > 0.0 else 0.0
		final_row.accepted_budget_partition_fraction = final_amount / accepted_total_budget_j if accepted_total_budget_j > 0.0 else 0.0
		allocations[allocations.size() - 1] = final_row
		allocated_total_j = preceding_total_j + final_amount

	var candidate_partition_sum: float = 0.0
	for index: int in range(allocations.size()):
		var row: Dictionary = allocations[index]
		var candidate: float = float(row.candidate_energy.value)
		var share: float = candidate / candidate_total_j if candidate_total_j > 0.0 else 0.0
		if index == allocations.size() - 1 and candidate_total_j > 0.0:
			share = maxf(0.0, 1.0 - candidate_partition_sum)
		row.candidate_partition_fraction = share
		candidate_partition_sum += share
		allocations[index] = row

	var budget_partition_sum: float = 0.0
	for row_value: Variant in allocations:
		budget_partition_sum += float(row_value.accepted_budget_partition_fraction)
	if budget_partition_sum > 1.0 and not allocations.is_empty() and accepted_total_budget_j > 0.0:
		var preceding_fraction: float = 0.0
		for index: int in range(allocations.size() - 1):
			preceding_fraction += float(allocations[index].accepted_budget_partition_fraction)
		var final_row: Dictionary = allocations[allocations.size() - 1]
		var old_final_amount: float = float(final_row.allocated_energy.value)
		var final_fraction_limit: float = maxf(0.0, 1.0 - preceding_fraction)
		var final_amount: float = minf(old_final_amount, accepted_total_budget_j * final_fraction_limit)
		final_row.allocated_energy = _quantity(final_amount, "J", budget_source, "%s:%s" % [episode_id, str(tick)])
		var final_candidate: float = float(final_row.candidate_energy.value)
		final_row.accepted_budget_partition_fraction = final_amount / accepted_total_budget_j
		final_row.allocation_fraction_of_candidate = final_amount / final_candidate if final_candidate > 0.0 else 0.0
		allocations[allocations.size() - 1] = final_row
		allocated_total_j = 0.0
		budget_partition_sum = 0.0
		for row_value: Variant in allocations:
			allocated_total_j += float(row_value.allocated_energy.value)
			budget_partition_sum += float(row_value.accepted_budget_partition_fraction)
	if allocated_total_j > allocation_cap_j or candidate_partition_sum > 1.0 or budget_partition_sum > 1.0:
		return _failure(["episode allocation exceeded its candidate or accepted budget bound"])

	var source_ids := PackedStringArray()
	for contact_id: String in sorted_ids:
		var estimate: Dictionary = estimates_by_id[contact_id]
		source_ids.append(String(estimate.provenance.input_evidence_id))
	return {
		"ok": true,
		"basis": BASIS,
		"episode_id": episode_id,
		"tick": tick,
		"candidate_total_energy": _quantity(candidate_total_j, "J", "single-snapshot contact estimates", JSON.stringify(source_ids)),
		"accepted_total_budget": _quantity(accepted_total_budget_j, "J", "caller-supplied budget; not proof of solver work", budget_source),
		"allocated_total_energy": _quantity(allocated_total_j, "J", "bounded candidate apportionment", JSON.stringify(source_ids)),
		"unallocated_budget": _quantity(maxf(0.0, accepted_total_budget_j - allocated_total_j), "J", budget_source, "%s:%s" % [episode_id, str(tick)]),
		"allocations": allocations,
		"candidate_partition_sum": candidate_partition_sum,
		"accepted_budget_partition_sum": budget_partition_sum,
		"provenance": {
			"kind": BASIS,
			"method": "proportional allocation capped by both candidate energy and supplied episode budget",
			"budget_source": budget_source,
			"accepted_work_observed": false,
			"contact_ids_sorted": sorted_ids,
			"input_evidence_ids": source_ids,
			"limitations": ["budget provenance is caller asserted", "no frictional loss", "no component failure threshold", "one accepted tick only"],
		},
	}


## Apply caller-supplied, nonnegative fractions without normalizing them. A shortfall remains
## unassigned; this function has no component-failure or survivability interpretation.
static func partition_energy(energy_budget_j: float, partitions: Array, partition_source: String) -> Dictionary:
	var errors: Array[String] = []
	if not is_finite(energy_budget_j) or energy_budget_j < 0.0:
		errors.append("energy_budget_j must be finite and nonnegative")
	if partition_source.strip_edges().is_empty():
		errors.append("partition_source must be a nonempty provenance string")
	if not errors.is_empty():
		return _failure(errors)

	var fractions_by_id: Dictionary = {}
	var sorted_ids := PackedStringArray()
	var fraction_sum: float = 0.0
	for index: int in range(partitions.size()):
		var part_value: Variant = partitions[index]
		if typeof(part_value) != TYPE_DICTIONARY:
			return _failure(["partitions[%d] must be a dictionary" % index])
		var part: Dictionary = part_value
		var target_id_value: Variant = part.get("target_id")
		var fraction_value: Variant = part.get("fraction")
		if typeof(target_id_value) != TYPE_STRING or String(target_id_value).strip_edges().is_empty():
			return _failure(["partitions[%d].target_id must be a nonempty string" % index])
		if not _is_numeric(fraction_value) or not is_finite(float(fraction_value)):
			return _failure(["partitions[%d].fraction must be finite" % index])
		var target_id: String = String(target_id_value)
		var fraction: float = float(fraction_value)
		if fraction < 0.0 or fraction > 1.0:
			return _failure(["partition fractions must be within [0, 1]"])
		if fractions_by_id.has(target_id):
			return _failure(["duplicate partition target_id '%s'" % target_id])
		fractions_by_id[target_id] = fraction
		sorted_ids.append(target_id)
	sorted_ids.sort()
	for target_id: String in sorted_ids:
		fraction_sum += float(fractions_by_id[target_id])
		if not is_finite(fraction_sum) or fraction_sum > 1.0:
			return _failure(["partition fractions must be nonnegative and sum to at most 1"])

	var rows: Array[Dictionary] = []
	var allocated_total_j: float = 0.0
	for target_id: String in sorted_ids:
		var fraction: float = float(fractions_by_id[target_id])
		var amount_j: float = energy_budget_j * fraction
		if not is_finite(amount_j):
			return _failure(["partition energy overflowed"])
		allocated_total_j += amount_j
		rows.append({
			"target_id": target_id,
			"fraction": fraction,
			"energy": _quantity(amount_j, "J", partition_source, target_id),
		})
	if not is_finite(allocated_total_j) or allocated_total_j > energy_budget_j:
		return _failure(["partition allocation exceeded its source energy"])
	return {
		"ok": true,
		"basis": BASIS,
		"source_energy": _quantity(energy_budget_j, "J", partition_source, "caller supplied"),
		"allocated_energy": _quantity(allocated_total_j, "J", partition_source, "caller partitions"),
		"unassigned_fraction": maxf(0.0, 1.0 - fraction_sum),
		"unassigned_energy": _quantity(maxf(0.0, energy_budget_j - allocated_total_j), "J", partition_source, "unassigned"),
		"fraction_sum": fraction_sum,
		"allocations": rows,
		"provenance": {"kind": BASIS, "method": "caller-supplied partition; no normalization or failure inference", "source": partition_source},
	}


static func _validate_contact(sample: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for key: String in ["contact_id", "episode_id"]:
		var string_value: Variant = sample.get(key)
		if typeof(string_value) != TYPE_STRING or String(string_value).strip_edges().is_empty():
			errors.append("%s must be a nonempty string" % key)
	if typeof(sample.get("tick")) != TYPE_INT or int(sample.tick) < 0:
		errors.append("tick must be a nonnegative accepted-tick integer")
	for key: String in ["mass_kg", "inverse_mass_kg_inv", "restitution"]:
		if not _is_numeric(sample.get(key)) or not is_finite(float(sample.get(key))):
			errors.append("%s must be a finite scalar" % key)
	if errors.is_empty():
		var mass_kg: float = float(sample.mass_kg)
		var inverse_mass_kg_inv: float = float(sample.inverse_mass_kg_inv)
		if mass_kg <= 0.0 or inverse_mass_kg_inv <= 0.0:
			errors.append("mass_kg and inverse_mass_kg_inv must be positive")
		else:
			var reciprocal_mass: float = 1.0 / mass_kg
			if not is_finite(reciprocal_mass) or absf(inverse_mass_kg_inv - reciprocal_mass) \
					> 1e-9 * maxf(absf(inverse_mass_kg_inv), absf(reciprocal_mass)):
				errors.append("inverse_mass_kg_inv must match 1 / mass_kg")
		var restitution: float = float(sample.restitution)
		if restitution < 0.0 or restitution > 1.0:
			errors.append("restitution must be passive and within [0, 1]")

	var matrix_value: Variant = sample.get("inverse_inertia_body_kg_m2_inv")
	if typeof(matrix_value) != TYPE_PACKED_FLOAT64_ARRAY or PackedFloat64Array(matrix_value).size() != 6:
		errors.append("inverse_inertia_body_kg_m2_inv must contain six symmetric-tensor values")
	elif not _positive_definite_inverse_inertia(PackedFloat64Array(matrix_value)):
		errors.append("inverse inertia must be finite, symmetric-layout and positive definite")
	for key: String in ["arm_body_m", "normal_body_unit", "linear_velocity_body_mps", "angular_velocity_body_radps"]:
		if not _finite_vector3(sample.get(key)):
			errors.append("%s must be a finite PackedFloat64Array of length 3" % key)
	if _finite_vector3(sample.get("normal_body_unit")):
		var normal_length: float = M.norm(PackedFloat64Array(sample.normal_body_unit))
		if not is_finite(normal_length) or absf(normal_length - 1.0) > NORMAL_TOLERANCE:
			errors.append("normal_body_unit must be normalized")
	var input_provenance_value: Variant = sample.get("input_provenance")
	if typeof(input_provenance_value) != TYPE_DICTIONARY:
		errors.append("input_provenance must include source, evidence_id, and state_stage")
	else:
		var input_provenance: Dictionary = input_provenance_value
		for key: String in ["source", "evidence_id", "state_stage"]:
			var value: Variant = input_provenance.get(key)
			if typeof(value) != TYPE_STRING or String(value).strip_edges().is_empty():
				errors.append("input_provenance.%s must be a nonempty string" % key)
		if typeof(input_provenance.get("state_stage")) == TYPE_STRING \
				and String(input_provenance.state_stage) != "accepted_tick":
			errors.append("input_provenance.state_stage must be accepted_tick; speculative trial states are excluded")
	return errors


static func _positive_definite_inverse_inertia(matrix: PackedFloat64Array) -> bool:
	if matrix.size() != 6:
		return false
	for value: float in matrix:
		if not is_finite(value):
			return false
	var xx: float = matrix[0]
	var yy: float = matrix[1]
	var zz: float = matrix[2]
	var xy: float = matrix[3]
	var xz: float = matrix[4]
	var yz: float = matrix[5]
	var leading_two: float = xx * yy - xy * xy
	var determinant: float = xx * (yy * zz - yz * yz) - xy * (xy * zz - xz * yz) + xz * (xy * yz - xz * yy)
	return is_finite(leading_two) and is_finite(determinant) and xx > 0.0 and leading_two > 0.0 and determinant > 0.0


static func _finite_vector3(value: Variant) -> bool:
	if typeof(value) != TYPE_PACKED_FLOAT64_ARRAY:
		return false
	var vector: PackedFloat64Array = value
	if vector.size() != 3:
		return false
	for component: float in vector:
		if not is_finite(component):
			return false
	return true


static func _is_numeric(value: Variant) -> bool:
	return typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT


static func _quantity(value: Variant, unit: String, source: String, evidence_id: String) -> Dictionary:
	return {
		"value": value,
		"unit": unit,
		"basis": BASIS,
		"provenance": {"source": source, "evidence_id": evidence_id},
	}


static func _failure(errors: Array[String]) -> Dictionary:
	return {
		"ok": false,
		"basis": BASIS,
		"errors": errors,
		"provenance": {"kind": BASIS, "accepted_work_observed": false},
	}

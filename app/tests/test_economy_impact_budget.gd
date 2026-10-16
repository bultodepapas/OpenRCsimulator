extends SceneTree

const ImpactBudget := preload("res://economy/impact_budget.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_check_central_and_off_center_effective_mass()
	_check_glancing_and_rotational_velocity()
	_check_no_separating_or_tangential_loss()
	_check_simultaneous_episode_allocation()
	_check_explicit_partitions()
	_check_invalid_inputs()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check_central_and_off_center_effective_mass() -> void:
	var central: Dictionary = ImpactBudget.estimate_contact(_sample("center", PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([-3.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([1.0, 0.0, 0.0]), 0.5))
	_check("central impact uses inverse translational mass only", central.ok \
		and _near(float(central.effective_inverse_mass.value), 0.5) \
		and _near(float(central.effective_mass.value), 2.0), str(central))
	_check("normal restitution loss matches central analytic value", central.ok \
		and _near(float(central.candidate_restitution_loss_energy.value), 6.75), str(central))
	_check("quantities retain units and isolated-estimate provenance", central.ok \
		and central.basis == "isolated_estimate" \
		and central.effective_mass.unit == "kg" \
		and central.candidate_restitution_loss_energy.unit == "J" \
		and central.provenance.accepted_work_observed == false \
		and central.candidate_restitution_loss_energy.provenance.source == "synthetic contact fixture", str(central))

	var off_center: Dictionary = ImpactBudget.estimate_contact(_sample("off-center", PackedFloat64Array([0.0, 1.0, 0.0]),
		PackedFloat64Array([-3.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([1.0, 0.0, 0.0]), 0.5))
	_check("off-center normal impulse includes r-cross-n rotational inverse mass", off_center.ok \
		and _near(float(off_center.effective_inverse_mass.value), 2.5) \
		and _near(float(off_center.effective_mass.value), 0.4) \
		and _near(float(off_center.candidate_restitution_loss_energy.value), 1.35), str(off_center))


func _check_glancing_and_rotational_velocity() -> void:
	var head_on: Dictionary = ImpactBudget.estimate_contact(_sample("head-on", PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([-5.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([1.0, 0.0, 0.0]), 0.0))
	var glancing: Dictionary = ImpactBudget.estimate_contact(_sample("glancing", PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([-3.0, 4.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([1.0, 0.0, 0.0]), 0.0))
	_check("same-speed glancing contact estimates less normal loss than head-on", head_on.ok and glancing.ok \
		and _near(float(head_on.candidate_restitution_loss_energy.value), 25.0) \
		and _near(float(glancing.candidate_restitution_loss_energy.value), 9.0) \
		and _near(float(glancing.tangent_speed.value), 4.0), "%s / %s" % [str(head_on), str(glancing)])

	var combined: Dictionary = ImpactBudget.estimate_contact(_sample("translation-rotation",
		PackedFloat64Array([0.0, 1.0, 0.0]), PackedFloat64Array([-1.0, 0.0, 0.0]),
		PackedFloat64Array([0.0, 0.0, 2.0]), PackedFloat64Array([1.0, 0.0, 0.0]), 0.0,
		1.0, 1.0, PackedFloat64Array([1.0, 1.0, 1.0, 0.0, 0.0, 0.0])))
	_check("contact velocity includes translation plus omega-cross-arm", combined.ok \
		and _near(float(combined.contact_velocity.value[0]), -3.0) \
		and _near(float(combined.normal_velocity.value), -3.0) \
		and _near(float(combined.effective_mass.value), 0.5) \
		and _near(float(combined.candidate_restitution_loss_energy.value), 2.25), str(combined))


func _check_no_separating_or_tangential_loss() -> void:
	var separating: Dictionary = ImpactBudget.estimate_contact(_sample("separating", PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([2.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([1.0, 0.0, 0.0]), 0.0))
	var tangent_only: Dictionary = ImpactBudget.estimate_contact(_sample("tangent-only", PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([0.0, 4.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([1.0, 0.0, 0.0]), 0.0))
	_check("separating motion adds no rebound or slapdown energy", separating.ok \
		and _near(float(separating.candidate_restitution_loss_energy.value), 0.0), str(separating))
	_check("tangential velocity is reported without invented frictional loss", tangent_only.ok \
		and _near(float(tangent_only.tangent_speed.value), 4.0) \
		and _near(float(tangent_only.candidate_restitution_loss_energy.value), 0.0), str(tangent_only))


func _check_simultaneous_episode_allocation() -> void:
	var first: Dictionary = _sample("z-contact", PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([-3.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([1.0, 0.0, 0.0]), 0.5)
	var second: Dictionary = _sample("a-contact", PackedFloat64Array([0.0, 1.0, 0.0]),
		PackedFloat64Array([-3.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([1.0, 0.0, 0.0]), 0.5)
	var forward: Dictionary = ImpactBudget.allocate_episode([first, second], 4.0, "synthetic accepted-work budget")
	var reverse: Dictionary = ImpactBudget.allocate_episode([second, first], 4.0, "synthetic accepted-work budget")
	_check("simultaneous allocations are sorted and independent of sample order", forward.ok and reverse.ok \
		and forward.allocations.size() == reverse.allocations.size() \
		and forward.allocations[0].contact_id == "a-contact" \
		and forward.allocations[0].contact_id == reverse.allocations[0].contact_id \
		and _near(float(forward.allocations[0].allocated_energy.value), float(reverse.allocations[0].allocated_energy.value)) \
		and _near(float(forward.allocations[1].allocated_energy.value), float(reverse.allocations[1].allocated_energy.value)), str(forward))
	_check("allocation partitions are nonnegative and stay within supplied total budget", forward.ok \
		and forward.accepted_budget_partition_sum >= 0.0 \
		and forward.accepted_budget_partition_sum <= 1.0 \
		and forward.candidate_partition_sum <= 1.0 \
		and float(forward.allocated_total_energy.value) <= 4.0, str(forward))
	_check("per-contact allocations never exceed candidate source energy", forward.ok \
		and _rows_within_candidate_and_budget(forward), str(forward))

	var larger_budget: Dictionary = ImpactBudget.allocate_episode([first, second], 100.0, "synthetic cap above candidates")
	_check("budget above candidates cannot create energy", larger_budget.ok \
		and _near(float(larger_budget.allocated_total_energy.value), 8.1, 1e-12) \
		and float(larger_budget.allocated_total_energy.value) <= float(larger_budget.candidate_total_energy.value), str(larger_budget))
	var duplicate: Dictionary = ImpactBudget.allocate_episode([first, first.duplicate(true)], 10.0, "duplicate fixture")
	_check("duplicate contact IDs are rejected before allocation", not duplicate.ok and _contains_error(duplicate, "duplicate contact_id"), str(duplicate))
	var different_tick: Dictionary = second.duplicate(true)
	different_tick.tick = int(different_tick.tick) + 1
	var mixed_ticks: Dictionary = ImpactBudget.allocate_episode([first, different_tick], 10.0, "mixed tick fixture")
	_check("an episode cannot combine contacts from different accepted ticks", not mixed_ticks.ok \
		and _contains_error(mixed_ticks, "share episode_id and accepted tick"), str(mixed_ticks))
	var negative_budget: Dictionary = ImpactBudget.allocate_episode([first], -1.0, "invalid")
	_check("negative accepted budget is rejected", not negative_budget.ok, str(negative_budget))
	var infinite_budget: Dictionary = ImpactBudget.allocate_episode([first], INF, "invalid")
	_check("nonfinite accepted budget is rejected", not infinite_budget.ok, str(infinite_budget))


func _check_explicit_partitions() -> void:
	var valid: Dictionary = ImpactBudget.partition_energy(10.0, [
		{"target_id": "wing", "fraction": 0.25},
		{"target_id": "fuselage", "fraction": 0.5},
	], "fixture-only caller partition")
	var reordered: Dictionary = ImpactBudget.partition_energy(10.0, [
		{"target_id": "fuselage", "fraction": 0.5},
		{"target_id": "wing", "fraction": 0.25},
	], "fixture-only caller partition")
	_check("caller partitions preserve unassigned energy and never normalize", valid.ok \
		and _near(float(valid.fraction_sum), 0.75) \
		and _near(float(valid.allocations[0].energy.value) + float(valid.allocations[1].energy.value), 7.5) \
		and _near(float(valid.unassigned_energy.value), 2.5), str(valid))
	_check("caller partition order does not change sorted allocations", valid.ok and reordered.ok \
		and valid.allocations[0].target_id == reordered.allocations[0].target_id \
		and valid.allocations[1].target_id == reordered.allocations[1].target_id \
		and _near(float(valid.allocations[0].energy.value), float(reordered.allocations[0].energy.value)) \
		and _near(float(valid.allocations[1].energy.value), float(reordered.allocations[1].energy.value)), str(valid))
	var decimal_order_a: Dictionary = ImpactBudget.partition_energy(9.0, [
		{"target_id": "c", "fraction": 0.7}, {"target_id": "a", "fraction": 0.1}, {"target_id": "b", "fraction": 0.2}], "decimal partition")
	var decimal_order_b: Dictionary = ImpactBudget.partition_energy(9.0, [
		{"target_id": "b", "fraction": 0.2}, {"target_id": "c", "fraction": 0.7}, {"target_id": "a", "fraction": 0.1}], "decimal partition")
	_check("decimal partition accumulation uses stable target order", decimal_order_a.ok and decimal_order_b.ok \
		and _near(float(decimal_order_a.fraction_sum), float(decimal_order_b.fraction_sum)) \
		and decimal_order_a.allocations[0].target_id == decimal_order_b.allocations[0].target_id \
		and decimal_order_a.allocations[1].target_id == decimal_order_b.allocations[1].target_id \
		and decimal_order_a.allocations[2].target_id == decimal_order_b.allocations[2].target_id, str(decimal_order_a))
	var negative: Dictionary = ImpactBudget.partition_energy(10.0, [{"target_id": "wing", "fraction": -0.1}], "bad fraction")
	var excessive: Dictionary = ImpactBudget.partition_energy(10.0, [
		{"target_id": "wing", "fraction": 0.6}, {"target_id": "tail", "fraction": 0.5}], "bad sum")
	var duplicate: Dictionary = ImpactBudget.partition_energy(10.0, [
		{"target_id": "wing", "fraction": 0.2}, {"target_id": "wing", "fraction": 0.2}], "duplicate target")
	_check("negative partition fraction is rejected", not negative.ok, str(negative))
	_check("partition sum above one is rejected", not excessive.ok, str(excessive))
	_check("duplicate partition target is rejected", not duplicate.ok, str(duplicate))
	var nonfinite_energy: Dictionary = ImpactBudget.partition_energy(INF, [], "bad energy")
	_check("nonfinite partition source energy is rejected", not nonfinite_energy.ok, str(nonfinite_energy))


func _check_invalid_inputs() -> void:
	var bad_mass: Dictionary = _sample("bad-mass", PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([-1.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([1.0, 0.0, 0.0]), 0.0)
	bad_mass.mass_kg = -2.0
	_check("negative mass is rejected", not ImpactBudget.estimate_contact(bad_mass).ok)
	var nonfinite_mass: Dictionary = _sample("nonfinite-mass", PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([-1.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([1.0, 0.0, 0.0]), 0.0)
	nonfinite_mass.mass_kg = INF
	_check("nonfinite mass is rejected", not ImpactBudget.estimate_contact(nonfinite_mass).ok)
	var mismatched_mass: Dictionary = _sample("mass-mismatch", PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([-1.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([1.0, 0.0, 0.0]), 0.0)
	mismatched_mass.inverse_mass_kg_inv = 0.25
	_check("inconsistent inverse mass is rejected", not ImpactBudget.estimate_contact(mismatched_mass).ok)
	var bad_matrix: Dictionary = _sample("bad-matrix", PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([-1.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([1.0, 0.0, 0.0]), 0.0)
	bad_matrix.inverse_inertia_body_kg_m2_inv = PackedFloat64Array([1.0, 0.0, 1.0, 0.0, 0.0, 0.0])
	_check("singular inverse inertia is rejected", not ImpactBudget.estimate_contact(bad_matrix).ok)
	var nonfinite_matrix: Dictionary = _sample("nonfinite-matrix", PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([-1.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([1.0, 0.0, 0.0]), 0.0)
	nonfinite_matrix.inverse_inertia_body_kg_m2_inv = PackedFloat64Array([INF, 1.0, 1.0, 0.0, 0.0, 0.0])
	_check("nonfinite inverse inertia is rejected", not ImpactBudget.estimate_contact(nonfinite_matrix).ok)
	var indefinite_matrix: Dictionary = _sample("indefinite-matrix", PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([-1.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([1.0, 0.0, 0.0]), 0.0)
	indefinite_matrix.inverse_inertia_body_kg_m2_inv = PackedFloat64Array([1.0, 1.0, 1.0, 2.0, 0.0, 0.0])
	_check("indefinite inverse inertia is rejected before it can produce negative energy", \
		not ImpactBudget.estimate_contact(indefinite_matrix).ok)
	var bad_normal: Dictionary = _sample("bad-normal", PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([-1.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([2.0, 0.0, 0.0]), 0.0)
	_check("unnormalized contact normal is rejected", not ImpactBudget.estimate_contact(bad_normal).ok)
	var bad_velocity: Dictionary = _sample("bad-velocity", PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([-1.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([1.0, 0.0, 0.0]), 0.0)
	bad_velocity.linear_velocity_body_mps = PackedFloat64Array([INF, 0.0, 0.0])
	_check("nonfinite linear velocity is rejected", not ImpactBudget.estimate_contact(bad_velocity).ok)
	var bad_restitution: Dictionary = _sample("bad-restitution", PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([-1.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([1.0, 0.0, 0.0]), 1.01)
	_check("active restitution above one is rejected", not ImpactBudget.estimate_contact(bad_restitution).ok)
	var negative_restitution: Dictionary = _sample("negative-restitution", PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([-1.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([1.0, 0.0, 0.0]), -0.01)
	_check("negative restitution is rejected", not ImpactBudget.estimate_contact(negative_restitution).ok)
	var missing_provenance: Dictionary = _sample("missing-provenance", PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([-1.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([1.0, 0.0, 0.0]), 0.0)
	missing_provenance.input_provenance.source = ""
	_check("missing input provenance is rejected", not ImpactBudget.estimate_contact(missing_provenance).ok)
	var speculative: Dictionary = _sample("speculative", PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([-1.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([1.0, 0.0, 0.0]), 0.0)
	speculative.input_provenance.state_stage = "speculative_slapdown"
	_check("speculative trial states are rejected", not ImpactBudget.estimate_contact(speculative).ok)
	var malformed_vector: Dictionary = _sample("malformed-vector", PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([-1.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([1.0, 0.0, 0.0]), 0.0)
	malformed_vector.arm_body_m = PackedFloat64Array([0.0, 1.0])
	_check("malformed packed vectors are rejected", not ImpactBudget.estimate_contact(malformed_vector).ok)


func _rows_within_candidate_and_budget(result: Dictionary) -> bool:
	var candidate_total: float = 0.0
	var allocated_total: float = 0.0
	var candidate_partitions: float = 0.0
	var budget_partitions: float = 0.0
	for row_value: Variant in result.allocations:
		var row: Dictionary = row_value
		var candidate: float = float(row.candidate_energy.value)
		var allocated: float = float(row.allocated_energy.value)
		if allocated < 0.0 or allocated > candidate:
			return false
		candidate_total += candidate
		allocated_total += allocated
		candidate_partitions += float(row.candidate_partition_fraction)
		budget_partitions += float(row.accepted_budget_partition_fraction)
	return allocated_total <= 4.0 and candidate_total >= allocated_total \
		and candidate_partitions <= 1.0 and budget_partitions <= 1.0


func _sample(contact_id: String, arm: PackedFloat64Array, linear_velocity: PackedFloat64Array,
		angular_velocity: PackedFloat64Array, normal: PackedFloat64Array, restitution: float,
		mass_kg: float = 2.0, inverse_mass_kg_inv: float = 0.5,
		inverse_inertia: PackedFloat64Array = PackedFloat64Array([2.0, 2.0, 2.0, 0.0, 0.0, 0.0])) -> Dictionary:
	return {
		"contact_id": contact_id,
		"episode_id": "fixture-episode",
		"tick": 42,
		"mass_kg": mass_kg,
		"inverse_mass_kg_inv": inverse_mass_kg_inv,
		"inverse_inertia_body_kg_m2_inv": inverse_inertia.duplicate(),
		"arm_body_m": arm.duplicate(),
		"normal_body_unit": normal.duplicate(),
		"linear_velocity_body_mps": linear_velocity.duplicate(),
		"angular_velocity_body_radps": angular_velocity.duplicate(),
		"restitution": restitution,
		"input_provenance": {"source": "synthetic contact fixture", "evidence_id": "fixture:%s:42" % contact_id,
			"state_stage": "accepted_tick"},
	}


func _contains_error(result: Dictionary, fragment: String) -> bool:
	for error_value: Variant in result.get("errors", []):
		if String(error_value).contains(fragment):
			return true
	return false


func _near(actual: float, expected: float, tolerance: float = 1e-12) -> bool:
	return is_finite(actual) and absf(actual - expected) <= tolerance


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		push_error("FAIL: %s — %s" % [label, detail])

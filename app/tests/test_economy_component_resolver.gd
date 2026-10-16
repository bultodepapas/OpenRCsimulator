extends SceneTree

const ComponentResolver := preload("res://economy/component_resolver.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_test_interval_boundaries()
	_test_roundoff_comparison_band()
	_test_deterministic_accumulation_and_candidate_priority()
	_test_unknown_and_missing_capacity()
	_test_duplicate_and_inconsistent_evidence()
	_test_invalid_schema_values_and_classes()
	_test_qualification_claim_stays_unverified()
	_test_held_out_synthetic_fixtures()
	_test_read_only_and_bounds()
	print("ComponentResolver: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_interval_boundaries() -> void:
	var below := ComponentResolver.resolve(_input([_component("wing", [_cause("authored_scenario", "below", 1,
		[_channel("impact_allocated_j", 1.0, 2.0, 3.0, 4.0)])])]))
	_check("strictly below threshold reports no declared exceedance", below.ok \
		and _component_row(below, "wing").outcome == "below_declared_capacity" \
		and _component_row(below, "wing").inspection_required \
		and _channel_row(below, "wing", "impact_allocated_j").comparison == "below", str(below))

	var overlap := ComponentResolver.resolve(_input([_component("wing", [_cause("authored_scenario", "overlap", 1,
		[_channel("impact_allocated_j", 3.0, 5.0, 4.0, 6.0)])])]))
	_check("overlapping intervals require inspection", overlap.ok \
		and _component_row(overlap, "wing").outcome == "inspect" \
		and _channel_row(overlap, "wing", "impact_allocated_j").comparison == "overlap", str(overlap))

	var equality := ComponentResolver.resolve(_input([_component("wing", [_cause("authored_scenario", "equal", 1,
		[_channel("impact_allocated_j", 4.0, 4.0, 4.0, 4.0)])])]))
	_check("equality remains inspect rather than claiming exceedance", equality.ok \
		and _channel_row(equality, "wing", "impact_allocated_j").outcome == "inspect", str(equality))

	var repair := ComponentResolver.resolve(_input([_component("wing", [_cause("authored_scenario", "repair", 1,
		[_channel("impact_allocated_j", 5.1, 7.0, 3.0, 5.0, "repair_candidate")])])]))
	_check("strict exceedance returns only repair candidate", repair.ok \
		and _component_row(repair, "wing").outcome == "repair_candidate" \
		and _component_row(repair, "wing").inspection_required, str(repair))

	var replace := ComponentResolver.resolve(_input([_component("wing", [_cause("authored_scenario", "replace", 1,
		[_channel("impact_allocated_j", 5.1, 7.0, 3.0, 5.0, "replace_candidate")])])]))
	_check("declared replacement action remains a candidate", replace.ok \
		and _component_row(replace, "wing").outcome == "replace_candidate", str(replace))


func _test_roundoff_comparison_band() -> void:
	var decimal_sum := ComponentResolver.resolve(_input([_component("wing", [
		_cause("authored_scenario", "decimal-a", 1, [_channel("impact_allocated_j", 0.1, 0.1, 0.3, 0.3)]),
		_cause("authored_scenario", "decimal-b", 2, [_channel("impact_allocated_j", 0.2, 0.2, 0.3, 0.3)]),
	])]))
	var decimal_channel := _channel_row(decimal_sum, "wing", "impact_allocated_j")
	_check("decimal accumulation at the declared threshold stays inspect within the roundoff band", decimal_sum.ok \
		and _component_row(decimal_sum, "wing").outcome == "inspect" \
		and decimal_channel.comparison == "overlap" \
		and is_equal_approx(float(decimal_channel.comparison_tolerance), 1.0e-12), str(decimal_sum))

	var one_ulp_above := ComponentResolver.resolve(_input([_component("wing", [
		_cause("authored_scenario", "ulp", 1, [_channel("impact_allocated_j", 0.30000000000000004,
			0.30000000000000004, 0.3, 0.3, "replace_candidate")]),
	])]))
	_check("one-ULP exceedance stays inspect", one_ulp_above.ok \
		and _component_row(one_ulp_above, "wing").outcome == "inspect" \
		and _channel_row(one_ulp_above, "wing", "impact_allocated_j").comparison == "overlap", str(one_ulp_above))

	var beyond_band := ComponentResolver.resolve(_input([_component("wing", [
		_cause("authored_scenario", "clear-gap", 1, [_channel("impact_allocated_j", 0.300000001,
			0.300000001, 0.3, 0.3, "replace_candidate")]),
	])]))
	_check("exceedance beyond the numerical band remains a declared candidate", beyond_band.ok \
		and _component_row(beyond_band, "wing").outcome == "replace_candidate" \
		and _channel_row(beyond_band, "wing", "impact_allocated_j").comparison == "exceeds", str(beyond_band))


func _test_deterministic_accumulation_and_candidate_priority() -> void:
	var first := _cause("authored_scenario", "a", 1,
		[_channel("impact_allocated_j", 2.0, 3.0, 4.0, 5.0, "repair_candidate")])
	var second := _cause("accepted_event", "event-b", 2,
		[_channel("impact_allocated_j", 4.0, 5.0, 4.0, 5.0, "repair_candidate", "isolated_estimate")])
	first.channels[0].quantity_provenance = "synthetic scenario cause A"
	second.channels[0].quantity_provenance = "isolated estimate cause B"
	var forward := ComponentResolver.resolve(_input([_component("wing", [second, first])]))
	var reverse := ComponentResolver.resolve(_input([_component("wing", [first, second])]))
	_check("unique cause intervals sum against one declared component capacity", forward.ok \
		and _component_row(forward, "wing").outcome == "repair_candidate" \
		and is_equal_approx(float(_channel_row(forward, "wing", "impact_allocated_j").quantity_low), 6.0) \
		and is_equal_approx(float(_channel_row(forward, "wing", "impact_allocated_j").quantity_high), 8.0), str(forward))
	_check("authored capacity keeps estimated quantity gameplay-labeled with provenance", forward.ok \
		and _channel_row(forward, "wing", "impact_allocated_j").evidence_class == "scenario_assumption" \
		and _channel_row(forward, "wing", "impact_allocated_j").quantity_provenance.size() == 2 \
		and _channel_row(forward, "wing", "impact_allocated_j").capacity_provenance.size() == 1, str(forward))
	_check("cause input order does not change resolution", forward.ok and reverse.ok \
		and JSON.stringify(forward, "", true, true) == JSON.stringify(reverse, "", true, true), str([forward, reverse]))

	var multichannel := _cause("authored_scenario", "multi", 3, [
		_channel("impact_allocated_j", 6.0, 7.0, 1.0, 2.0, "repair_candidate"),
		_channel("thermal_dose_k_s", 8.0, 9.0, 2.0, 3.0, "replace_candidate"),
	])
	var combined := ComponentResolver.resolve(_input([_component("wing", [multichannel])]))
	_check("replace candidate outranks repair candidate across channels", combined.ok \
		and _component_row(combined, "wing").outcome == "replace_candidate" \
		and _channel_row(combined, "wing", "impact_allocated_j").outcome == "repair_candidate" \
		and _channel_row(combined, "wing", "thermal_dose_k_s").outcome == "replace_candidate", str(combined))
	_check("resolver exposes candidates only, with no price or salvage fields", combined.ok \
		and not _component_row(combined, "wing").has("disposition") \
		and not _component_row(combined, "wing").has("salvage_minor") \
		and not _component_row(combined, "wing").has("price_minor") \
		and combined.production_billing_enabled == false, str(combined))


func _test_unknown_and_missing_capacity() -> void:
	var unknown := ComponentResolver.resolve(_input([_component("receiver", [_cause("accepted_event", "impact-1", 9, [])])]))
	_check("unknown or unpriced capacity is represented by no channel and stays inspect", unknown.ok \
		and _component_row(unknown, "receiver").outcome == "inspect" \
		and _component_row(unknown, "receiver").channels.is_empty(), str(unknown))
	_check("empty affected component also remains inspect", ComponentResolver.resolve(
		_input([_component("receiver", [])])).components[0].outcome == "inspect")

	var partial := _channel("impact_allocated_j", 1.0, 2.0, 2.0, 3.0)
	partial.erase("capacity_high")
	var malformed := ComponentResolver.resolve(_input([_component("receiver", [
		_cause("authored_scenario", "partial", 9, [partial])])]))
	_check("partially declared channel is rejected instead of guessed", not malformed.ok, str(malformed))


func _test_duplicate_and_inconsistent_evidence() -> void:
	var one := _cause("accepted_event", "event-x", 4,
		[_channel("impact_allocated_j", 1.0, 2.0, 3.0, 4.0)])
	var duplicate_cause := ComponentResolver.resolve(_input([_component("wing", [one, one.duplicate(true)])]))
	_check("duplicate cause/component rows reject double allocation", not duplicate_cause.ok, str(duplicate_cause))

	var duplicate_channel := _cause("accepted_event", "event-y", 5, [
		_channel("impact_allocated_j", 1.0, 2.0, 3.0, 4.0),
		_channel("impact_allocated_j", 1.0, 2.0, 3.0, 4.0),
	])
	_check("duplicate channels within one event/component reject", not ComponentResolver.resolve(
		_input([_component("wing", [duplicate_channel])])).ok)

	var other_capacity := _cause("accepted_event", "event-z", 6,
		[_channel("impact_allocated_j", 1.0, 2.0, 3.1, 4.0)])
	_check("conflicting repeated component/channel capacities reject", not ComponentResolver.resolve(
		_input([_component("wing", [one, other_capacity])])).ok)

	var across_components := ComponentResolver.resolve(_input([
		_component("wing", [one]), _component("spar", [one.duplicate(true)])
	]))
	_check("one event may map to two separately authored components", across_components.ok \
		and across_components.components.size() == 2, str(across_components))


func _test_invalid_schema_values_and_classes() -> void:
	var unsupported := _channel("impact_budget_guess", 1.0, 2.0, 3.0, 4.0)
	_check("unsupported channel is rejected", not ComponentResolver.resolve(_input([_component("wing", [
		_cause("authored_scenario", "bad-channel", 1, [unsupported])])])).ok)

	var wrong_unit := _channel("impact_allocated_j", 1.0, 2.0, 3.0, 4.0)
	wrong_unit.unit = "m/s"
	_check("mismatched unit is rejected", not ComponentResolver.resolve(_input([_component("wing", [
		_cause("authored_scenario", "bad-unit", 1, [wrong_unit])])])).ok)

	var negative := _channel("abrasion_j", -0.1, 1.0, 2.0, 3.0)
	_check("negative quantity is rejected", not ComponentResolver.resolve(_input([_component("wing", [
		_cause("authored_scenario", "negative", 1, [negative])])])).ok)

	var reversed := _channel("impact_allocated_j", 2.0, 1.0, 3.0, 4.0)
	_check("reversed quantity interval is rejected", not ComponentResolver.resolve(_input([_component("wing", [
		_cause("authored_scenario", "reversed", 1, [reversed])])])).ok)

	var nonfinite := _channel("impact_allocated_j", NAN, 1.0, 3.0, 4.0)
	_check("nonfinite interval endpoint is rejected", not ComponentResolver.resolve(_input([_component("wing", [
		_cause("authored_scenario", "nan", 1, [nonfinite])])])).ok)

	var missing_ref := _channel("thermal_dose_k_s", 5.0, 6.0, 1.0, 2.0)
	missing_ref.quantity_class = "independently_validated"
	_check("unverified physical evidence claim needs a reference", not ComponentResolver.resolve(_input([_component("battery", [
		_cause("authored_scenario", "missing-ref", 1, [missing_ref])])])).ok)

	var unknown_key_input := _input([_component("wing", [])])
	unknown_key_input["physical_damage"] = true
	_check("closed top-level schema rejects unknown keys", not ComponentResolver.resolve(unknown_key_input).ok)


func _test_qualification_claim_stays_unverified() -> void:
	var qualified_claim := _channel("impact_allocated_j", 8.0, 9.0, 2.0, 3.0,
		"replace_candidate", "independently_validated", "independently_validated", "claim:stik-wing-v1")
	var result := ComponentResolver.resolve(_input([_component("wing", [
		_cause("authored_scenario", "qualification-claim", 2, [qualified_claim])])]))
	var component: Dictionary = _component_row(result, "wing")
	var channel: Dictionary = _channel_row(result, "wing", "impact_allocated_j")
	_check("qualified labels produce only a candidate claim", result.ok \
		and component.outcome == "replace_candidate" \
		and component.evidence_class == "independently_validated_claim" \
		and component.qualification_claim_unverified \
		and channel.qualification_claim_unverified, str(result))
	_check("qualification and production billing remain disabled", result.ok \
		and component.qualification_verified == false \
		and result.qualification_verified == false \
		and result.production_billing_enabled == false, str(result))


func _test_held_out_synthetic_fixtures() -> void:
	# These held-out fixtures exercise deterministic interval rules only; they are not material tests.
	var brace_case := _channel("impact_allocated_j", 6.2, 6.8, 4.0, 5.5, "repair_candidate",
		"scenario_assumption", "scenario_assumption")
	var battery_case := _channel("thermal_dose_k_s", 1.2, 2.0, 3.0, 5.0, "replace_candidate",
		"scenario_assumption", "scenario_assumption")
	var result := ComponentResolver.resolve(_input([
		_component("synthetic-frame-brace", [_cause("authored_scenario", "heldout-brace-software-only", 4, [brace_case])]),
		_component("synthetic-pack-shell", [_cause("authored_scenario", "heldout-pack-software-only", 8, [battery_case])]),
	]))
	_check("software-only mechanical scenario crosses its declared interval", result.ok \
		and _component_row(result, "synthetic-frame-brace").outcome == "repair_candidate" \
		and _component_row(result, "synthetic-frame-brace").evidence_class == "scenario_assumption", str(result))
	_check("software-only thermal scenario below its declared interval adds no fire outcome", result.ok \
		and _component_row(result, "synthetic-pack-shell").outcome == "below_declared_capacity" \
		and not result.has("fire") and not _component_row(result, "synthetic-pack-shell").has("ignition"), str(result))


func _test_read_only_and_bounds() -> void:
	var input := _input([_component("wing", [_cause("authored_scenario", "stable", 1,
		[_channel("impact_allocated_j", 1.0, 2.0, 3.0, 4.0)])])])
	var before := JSON.stringify(input, "", true, true)
	var result := ComponentResolver.resolve(input)
	_check("resolver leaves caller input unchanged", result.ok and JSON.stringify(input, "", true, true) == before)

	var overflow := ComponentResolver.resolve(_input([_component("wing", [
		_cause("authored_scenario", "large-a", 1, [_channel("impact_allocated_j", 600000000000.0, 600000000000.0, 1.0, 2.0)]),
		_cause("authored_scenario", "large-b", 2, [_channel("impact_allocated_j", 600000000000.0, 600000000000.0, 1.0, 2.0)]),
	])]))
	_check("finite contributions whose sum exceeds the bound reject", not overflow.ok)

	var too_many_components: Array[Dictionary] = []
	for index: int in range(65):
		too_many_components.append(_component("part-%d" % index, []))
	_check("component bound is enforced", not ComponentResolver.resolve(_input(too_many_components)).ok)

	var too_many_causes: Array[Dictionary] = []
	for index: int in range(129):
		too_many_causes.append(_cause("authored_scenario", "scenario-%d" % index, index, []))
	_check("cause/component row bound is enforced", not ComponentResolver.resolve(_input([
		_component("part", too_many_causes)])).ok)


func _input(components: Array) -> Dictionary:
	return {
		"format": "openrc-component-evidence v1",
		"incident_id": "test-incident",
		"aircraft_id": "synthetic-aircraft",
		"source_sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
		"components": components,
	}


func _component(component_id: String, causes: Array) -> Dictionary:
	return {"component_id": component_id, "causes": causes}


func _cause(cause_kind: String, cause_id: String, tick: int, channels: Array) -> Dictionary:
	return {"cause_kind": cause_kind, "cause_id": cause_id, "tick": tick, "channels": channels}


func _channel(channel_name: String, quantity_low: float, quantity_high: float,
		capacity_low: float, capacity_high: float, over_capacity_candidate := "repair_candidate",
		quantity_class := "scenario_assumption", capacity_class := "scenario_assumption",
		qualification_ref := "") -> Dictionary:
	var unit := "K*s" if channel_name == "thermal_dose_k_s" else "J"
	return {
		"channel": channel_name,
		"unit": unit,
		"quantity_low": quantity_low,
		"quantity_high": quantity_high,
		"quantity_class": quantity_class,
		"quantity_provenance": "synthetic software-only quantity fixture",
		"capacity_low": capacity_low,
		"capacity_high": capacity_high,
		"capacity_class": capacity_class,
		"capacity_provenance": "explicit test threshold, not a material limit",
		"over_capacity_candidate": over_capacity_candidate,
		"qualification_ref": qualification_ref,
	}


func _component_row(result: Dictionary, component_id: String) -> Dictionary:
	for row_value: Variant in result.get("components", []):
		var row: Dictionary = row_value
		if row.get("component_id") == component_id:
			return row
	return {}


func _channel_row(result: Dictionary, component_id: String, channel_name: String) -> Dictionary:
	for row_value: Variant in _component_row(result, component_id).get("channels", []):
		var row: Dictionary = row_value
		if row.get("channel") == channel_name:
			return row
	return {}


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: %s — %s" % [label, detail])
	else:
		print("PASS: " + label)


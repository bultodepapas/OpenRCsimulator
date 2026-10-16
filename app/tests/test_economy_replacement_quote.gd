extends SceneTree

const ReplacementQuote = preload("res://economy/replacement_quote.gd")
const Incident = preload("res://economy/incident.gd")

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_test_known_single_propeller()
	_test_group_quantity_and_default_atom_mapping()
	_test_partial_assessment_is_not_complete()
	_test_unknown_component_price()
	_test_overlapping_packages_and_full_bundle()
	_test_unit_bound_and_search_limit()
	_test_total_loss_and_invalid_assessment()
	_test_package_candidate_preflight()
	_test_determinism_and_input_purity()
	_test_selection_archive()
	print("CR-31e replacement quote: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	print(("ok   " if ok else "FAIL ") + label + ("  " + detail if not ok and not detail.is_empty() else ""))
	if not ok:
		_failures += 1


func _test_selection_archive() -> void:
	var dossier := _dossier([_component("servo", 2, 1000)])
	var assessment := _assessment({"servo": {"disposition": "replace"}})
	var result := ReplacementQuote.quote(dossier, assessment, [_package("servo-pair", ["servo:1", "servo:0"], 1500)])
	result["format"] = "openrc-replacement-comparison v2"
	result["catalog_hash"] = "frozen-test-catalog"
	_check("selected package snapshot records sorted exact coverage and price once", result.selected_lines == [{"candidate_id": "servo-pair", "coverage_ids": ["servo:0", "servo:1"], "cost_cents": 1500}])
	_check("valid package cover remains verifiable after JSON round trip", Incident._valid_comparison_archive(JSON.parse_string(JSON.stringify(result)), "frozen-test-catalog"))
	for defect: String in ["sum", "missing_unit", "overlap", "foreign_unit", "foreign_candidate", "fractional_cost", "missing_rows", "unknown_optimum", "unfinished_optimum"]:
		var changed := result.duplicate(true)
		match defect:
			"sum": changed.total_cost_cents = 0
			"missing_unit": changed.selected_lines[0].coverage_ids.pop_back()
			"overlap": changed.selected_lines[0].coverage_ids.append("servo:0")
			"foreign_unit": changed.selected_lines[0].coverage_ids[0] = "wing:0"
			"foreign_candidate": changed.selected_lines[0].candidate_id = "unknown"
			"fractional_cost": changed.selected_lines[0].cost_cents = 1500.5
			"missing_rows": changed.erase("selected_lines")
			"unknown_optimum": changed.unknown_cost_alternative_found = true
			"unfinished_optimum": changed.search_complete = false
		_check("inconsistent selected archive rejected: " + defect, not Incident._valid_comparison_archive(changed, "frozen-test-catalog"))
	for mode: String in ["unknown", "limited"]:
		var pending := ReplacementQuote.quote(_dossier([_component("servo", 1, null if mode == "unknown" else 1000)]),
			_assessment({"servo": {"disposition": "replace"}}), [], 1 if mode == "limited" else 100000)
		pending["format"] = "openrc-replacement-comparison v2"
		pending["catalog_hash"] = "frozen-test-catalog"
		_check("unresolved selection remains null through archive: " + mode, pending.total_cost_cents == null
			and Incident._valid_comparison_archive(pending, "frozen-test-catalog"))
		if mode == "unknown":
			for contradictory_status: String in ["infeasible", "cost_out_of_range"]:
				var contradictory := pending.duplicate(true)
				contradictory.status = contradictory_status
				_check("completed unknown cover cannot claim " + contradictory_status,
					not Incident._valid_comparison_archive(contradictory, "frozen-test-catalog"))
	var legacy := result.duplicate(true)
	legacy.format = "openrc-replacement-comparison v1"
	legacy.erase("selected_lines")
	_check("legacy view-only comparison is still readable", Incident._valid_comparison_archive(legacy, "frozen-test-catalog"))


func _component(
	component_id: String,
	quantity: int,
	unit_price: Variant,
	price_basis: String = "observed",
	offer_id: Variant = null,
	notes: String = ""
) -> Dictionary:
	return {
		"id": component_id,
		"quantity": quantity,
		"physical_inventory_ids": ["inventory:" + component_id],
		"unit_minor": unit_price,
		"low_unit_minor": unit_price,
		"high_unit_minor": unit_price,
		"price_basis": price_basis,
		"offer_id": offer_id,
		"notes": notes,
	}


func _dossier(components: Array, is_complete: bool = true) -> Dictionary:
	return {
		"format": "openrc-aircraft-economics v1",
		"aircraft_id": "fixture-aircraft",
		"source_sha256": "fixture-source-sha256",
		"currency": "USD",
		"price_date": "2026-10-16",
		"valuation_kind": "fixture_snapshot",
		"complete": is_complete,
		"components": components,
		"missing": [],
	}


func _assessment(components: Dictionary, unresolved: Array = [], is_total_loss: bool = false) -> Dictionary:
	return {
		"terminal": false,
		"total_loss": is_total_loss,
		"components": components,
		"unresolved": unresolved,
	}


func _package(
	candidate_id: String,
	coverage: Array,
	cost: Variant,
	is_available: bool = true,
	is_compatible: bool = true,
	provenance: String = "explicit fixture package coverage"
) -> Dictionary:
	return {
		"id": candidate_id,
		"coverage_ids": coverage,
		"cost_cents": cost,
		"available": is_available,
		"compatible": is_compatible,
		"provenance": provenance,
	}


func _test_known_single_propeller() -> void:
	var dossier := _dossier([_component("propeller", 1, 539, "observed", "prop-offer-1", "Observed single propeller price.")])
	var assessment := _assessment({"propeller": {"disposition": "replace"}})
	var result := ReplacementQuote.quote(dossier, assessment)
	_check("known propeller replacement has a proven individual estimate", result.status == "optimal" and result.optimizer_status == "optimal" and result.total_cost_cents == 539 and result.complete and result.optimality_proven, str(result))
	_check("quote scope and required unit atom are explicit", result.coverage_scope == "replacements_only" and result.required_unit_ids == ["propeller:0"], str(result))
	_check("candidate catalog maps the opaque candidate ID to its component unit", result.candidate_catalog.size() == 1 and result.candidate_catalog[0].candidate_id == "individual-000" and result.candidate_catalog[0].component_id == "propeller" and result.candidate_catalog[0].unit_index == 0, str(result.candidate_catalog))
	_check("dossier provenance is retained with no live fit or availability claim", result.selected_provenance.size() == 1 and result.selected_provenance[0].provenance.contains("price basis: observed") and result.selected_provenance[0].provenance.contains("source offer: prop-offer-1") and result.selected_provenance[0].provenance.contains("Observed single propeller price") and not result.candidate_catalog[0].live_availability_confirmed and not result.candidate_catalog[0].physical_fit_confirmed, str(result))


func _test_group_quantity_and_default_atom_mapping() -> void:
	var dossier := _dossier([_component("servo", 3, 250, "estimated", null, "Two affected from a three-servo row.")])
	var assessment := _assessment({"servo": {"disposition": "replace", "quantity": 2}})
	var result := ReplacementQuote.quote(dossier, assessment)
	_check("group replacement expands only the affected quantity", result.status == "optimal" and result.total_cost_cents == 500 and result.required_unit_ids == ["servo:0", "servo:1"] and result.selected_candidate_ids == ["individual-000", "individual-001"], str(result))
	_check("each default candidate maps back to the source component and unit index", result.candidate_catalog.size() == 2 and result.candidate_catalog[0].component_id == "servo" and result.candidate_catalog[1].component_id == "servo" and result.candidate_catalog[0].unit_index == 0 and result.candidate_catalog[1].unit_index == 1, str(result.candidate_catalog))


func _test_partial_assessment_is_not_complete() -> void:
	var dossier := _dossier([
		_component("propeller", 1, 539),
		_component("engine", 1, 8000),
	])
	var assessment := _assessment({
		"propeller": {"disposition": "replace"},
		"engine": {"disposition": "inspect"},
	}, ["Powertrain condition remains pending inspection."])
	var result := ReplacementQuote.quote(dossier, assessment)
	_check("partial assessment can retain a known subset estimate", result.status == "optimal" and result.total_cost_cents == 539 and result.selected_candidate_ids == ["individual-000"], str(result))
	_check("partial assessment never claims a complete replacement quote", not result.assessment_complete and not result.complete and result.optimality_proven, str(result))


func _test_unknown_component_price() -> void:
	var dossier := _dossier([_component("receiver", 1, null, "estimated", null, "No exact receiver price was attached.")])
	var assessment := _assessment({"receiver": {"disposition": "replace"}})
	var result := ReplacementQuote.quote(dossier, assessment)
	_check("unknown unit valuation remains a feasible unknown-cost candidate", result.status == "unknown_cost" and result.optimizer_status == "unknown_cost" and result.candidate_catalog[0].cost_cents == null, str(result))
	_check("unknown unit price is not treated as zero or proven complete", result.total_cost_cents == null and not result.complete and not result.optimality_proven and not result.assessment_complete and result.unknown_cost_alternative_found, str(result))


func _test_overlapping_packages_and_full_bundle() -> void:
	var dossier := _dossier([
		_component("propeller", 1, 1000),
		_component("wing", 1, 1000),
	])
	var assessment := _assessment({
		"propeller": {"disposition": "replace"},
		"wing": {"disposition": "replace"},
	})
	var overlapping := [
		_package("full-overlap", ["propeller:0", "wing:0"], 500),
		_package("prop-only", ["propeller:0"], 100),
		_package("wing-only", ["wing:0"], 100),
	]
	var overlap_result := ReplacementQuote.quote(dossier, assessment, overlapping)
	_check("overlapping package coverage selects one non-overlapping exact cover", overlap_result.status == "optimal" and overlap_result.selected_candidate_ids == ["prop-only", "wing-only"] and overlap_result.total_cost_cents == 200, str(overlap_result))
	_check("selected candidates cover every replacement atom exactly once", _covers_once(overlap_result.required_unit_ids, overlap_result.selected_candidate_ids, overlap_result.candidate_catalog), str(overlap_result))

	var cheaper_bundle := [
		_package("full-bundle", ["propeller:0", "wing:0"], 750),
	]
	var bundle_result := ReplacementQuote.quote(dossier, assessment, cheaper_bundle)
	_check("a cheaper full bundle is selected once across multiple components", bundle_result.status == "optimal" and bundle_result.selected_candidate_ids == ["full-bundle"] and bundle_result.total_cost_cents == 750 and bundle_result.selected_provenance.size() == 1, str(bundle_result))
	_check("authored bundle compatibility is explicitly identified in the catalog", bundle_result.candidate_catalog.size() == 3 and bundle_result.candidate_catalog[0].candidate_kind == "authored_package_candidate" and bundle_result.candidate_catalog[0].compatibility_basis.contains("Explicit authored coverage"), str(bundle_result.candidate_catalog))


func _covers_once(required: Array, selected_ids: Array, candidate_catalog: Array) -> bool:
	var by_id: Dictionary = {}
	for candidate: Dictionary in candidate_catalog:
		by_id[candidate.candidate_id] = candidate
	var counts: Dictionary = {}
	for unit_id: String in required:
		counts[unit_id] = 0
	for candidate_id: String in selected_ids:
		if not by_id.has(candidate_id):
			return false
		for unit_id: String in by_id[candidate_id].coverage_ids:
			if not counts.has(unit_id):
				return false
			counts[unit_id] += 1
	for unit_id: String in required:
		if counts[unit_id] != 1:
			return false
	return true


func _test_unit_bound_and_search_limit() -> void:
	var too_many_dossier := _dossier([_component("servos", 65, 100)])
	var too_many_assessment := _assessment({"servos": {"disposition": "replace", "quantity": 65}})
	var bound_result := ReplacementQuote.quote(too_many_dossier, too_many_assessment)
	_check("replacement unit expansion is bounded before search", bound_result.status == "unit_bound_exceeded" and bound_result.total_cost_cents == null and not bound_result.complete and bound_result.required_unit_ids.is_empty(), str(bound_result))

	var dossier := _dossier([_component("parts", 2, 500)])
	var assessment := _assessment({"parts": {"disposition": "replace", "quantity": 2}})
	var limit_result := ReplacementQuote.quote(dossier, assessment, [], 1)
	_check("bounded optimizer search does not claim a completed quote", limit_result.status == "search_limit" and limit_result.optimizer_status == "search_limit" and not limit_result.search_complete and not limit_result.optimality_proven and not limit_result.complete, str(limit_result))


func _test_total_loss_and_invalid_assessment() -> void:
	var dossier := _dossier([_component("propeller", 1, 539)])
	var total_loss_assessment := _assessment({"propeller": {"disposition": "unrecoverable"}}, [], true)
	var total_loss_result := ReplacementQuote.quote(dossier, total_loss_assessment)
	_check("total loss is refused because this adapter cannot compare salvage", total_loss_result.status == "unsupported_total_loss" and total_loss_result.optimizer_status == "not_run" and total_loss_result.total_cost_cents == null and not total_loss_result.complete, str(total_loss_result))

	var invalid_assessment := _assessment({"propeller": {"disposition": "replace", "quantity": 1.5}})
	var invalid_result := ReplacementQuote.quote(dossier, invalid_assessment)
	_check("calculator validation runs before optimizer for malformed assessment", invalid_result.status == "invalid_assessment" and invalid_result.optimizer_status == "not_run" and not invalid_result.errors.is_empty() and not invalid_result.optimality_proven, str(invalid_result))

	var invalid_package := _package("bad-package", ["propeller:0"], NAN)
	var candidate_result := ReplacementQuote.quote(dossier, _assessment({"propeller": {"disposition": "replace"}}), [invalid_package])
	_check("unsafe package cost is rejected before optimizer input cloning", candidate_result.status == "invalid_candidates" and candidate_result.optimizer_status == "not_run" and not candidate_result.complete and not candidate_result.errors.is_empty() and candidate_result.candidate_catalog.is_empty(), str(candidate_result))


func _test_package_candidate_preflight() -> void:
	var dossier := _dossier([_component("propeller", 1, 539)])
	var assessment := _assessment({"propeller": {"disposition": "replace"}})
	var literal_package := {
		id = "literal-package",
		coverage_ids = ["propeller:0"],
		cost_cents = 400,
		available = true,
		compatible = true,
		provenance = "GDScript dictionary literal",
	}
	var literal_result := ReplacementQuote.quote(dossier, assessment, [literal_package])
	_check("valid StringName-keyed dictionary literals are accepted", literal_result.status == "optimal" and literal_result.selected_candidate_ids == ["literal-package"] and literal_result.total_cost_cents == 400, str(literal_result))

	var extra_key := _package("extra-key", ["propeller:0"], 400)
	extra_key["notes"] = "not part of the six-key contract"
	var extra_result := ReplacementQuote.quote(dossier, assessment, [extra_key])
	_check("unknown package-candidate keys are rejected", extra_result.status == "invalid_candidates" and not extra_result.errors.is_empty(), str(extra_result))

	var empty_id := _package("", ["propeller:0"], 400)
	var empty_id_result := ReplacementQuote.quote(dossier, assessment, [empty_id])
	_check("empty package candidate IDs are rejected before copying", empty_id_result.status == "invalid_candidates", str(empty_id_result))
	var empty_provenance := _package("empty-source", ["propeller:0"], 400, true, true, " ")
	var empty_provenance_result := ReplacementQuote.quote(dossier, assessment, [empty_provenance])
	_check("empty package provenance is rejected before copying", empty_provenance_result.status == "invalid_candidates", str(empty_provenance_result))
	var empty_coverage := _package("empty-coverage", [], 400)
	var empty_coverage_result := ReplacementQuote.quote(dossier, assessment, [empty_coverage])
	_check("empty package coverage is rejected before copying", empty_coverage_result.status == "invalid_candidates", str(empty_coverage_result))

	var cyclic_extra := _package("cyclic-extra", ["propeller:0"], 400)
	cyclic_extra["loop"] = cyclic_extra
	var cyclic_extra_result := ReplacementQuote.quote(dossier, assessment, [cyclic_extra])
	cyclic_extra.erase("loop")
	_check("cyclic extra fields are rejected without recursive cloning", cyclic_extra_result.status == "invalid_candidates" and not cyclic_extra_result.errors.is_empty(), str(cyclic_extra_result))

	var cyclic_coverage := _package("cyclic-coverage", ["propeller:0"], 400)
	cyclic_coverage["coverage_ids"] = [cyclic_coverage]
	var cyclic_coverage_result := ReplacementQuote.quote(dossier, assessment, [cyclic_coverage])
	cyclic_coverage["coverage_ids"] = ["propeller:0"]
	_check("cyclic coverage values are rejected without recursive cloning", cyclic_coverage_result.status == "invalid_candidates" and not cyclic_coverage_result.errors.is_empty(), str(cyclic_coverage_result))


func _test_determinism_and_input_purity() -> void:
	var dossier := _dossier([
		_component("wing", 1, 900),
		_component("propeller", 1, 700),
	])
	var assessment := _assessment({
		"wing": {"disposition": "replace"},
		"propeller": {"disposition": "replace"},
	})
	var packages := [
		_package("kit-z", ["wing:0", "propeller:0"], 1000, true, true, "authored fixture z"),
		_package("kit-a", ["propeller:0", "wing:0"], 1000, true, true, "authored fixture a"),
	]
	var dossier_before: Dictionary = dossier.duplicate(true)
	var assessment_before: Dictionary = assessment.duplicate(true)
	var packages_before: Array = packages.duplicate(true)
	var first := ReplacementQuote.quote(dossier, assessment, packages)
	var reversed_dossier := dossier.duplicate(true)
	reversed_dossier.components.reverse()
	var reversed_packages: Array = packages.duplicate(true)
	reversed_packages.reverse()
	var second := ReplacementQuote.quote(reversed_dossier, assessment, reversed_packages)
	_check("tie resolution and catalog ordering are deterministic under input reordering", first.status == second.status and first.required_unit_ids == second.required_unit_ids and first.selected_candidate_ids == second.selected_candidate_ids and first.candidate_catalog == second.candidate_catalog, str(second))
	_check("calculator and optimizer leave caller-owned dossier, assessment, and packages unchanged", dossier == dossier_before and assessment == assessment_before and packages == packages_before, "dossier=%s assessment=%s packages=%s" % [dossier == dossier_before, assessment == assessment_before, packages == packages_before])
	var no_replacements := ReplacementQuote.quote(dossier, _assessment({"propeller": {"disposition": "reuse"}, "wing": {"disposition": "reuse"}}))
	_check("no replacement decisions are reported quietly without claiming a broader repair total", no_replacements.status == "no_replacements" and no_replacements.coverage_scope == "replacements_only" and no_replacements.total_cost_cents == 0 and no_replacements.complete and no_replacements.optimality_proven, str(no_replacements))

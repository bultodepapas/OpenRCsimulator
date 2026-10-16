extends SceneTree

const PackageOptimizer := preload("res://economy/package_optimizer.gd")

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_test_bundles_and_individual_parts()
	_test_unknown_cost_only_blocks_complete_feasible_alternatives()
	_test_infeasible_and_search_limit_results()
	_test_small_cases_against_exhaustive_oracle()
	_test_ties_order_and_input_purity()
	_test_malformed_and_unsafe_inputs()
	_test_sum_above_economics_limit()
	print("CR-31d package optimizer: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	print(("ok   " if ok else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))
	if not ok:
		_failures += 1


func _candidate(
	candidate_id: String,
	coverage: Array,
	cost: Variant,
	is_available: bool = true,
	is_compatible: bool = true,
	source: String = "fixture"
) -> Dictionary:
	return {
		"id": candidate_id,
		"coverage_ids": coverage,
		"cost_cents": cost,
		"available": is_available,
		"compatible": is_compatible,
		"provenance": source,
	}


func _test_bundles_and_individual_parts() -> void:
	var required := ["wing", "tail"]
	var bundle_wins := [
		_candidate("kit", ["wing", "tail"], 800, true, true, "catalog:kit"),
		_candidate("part-tail", ["tail"], 500),
		_candidate("part-wing", ["wing"], 500),
	]
	var bundle_result := PackageOptimizer.optimize(required, bundle_wins)
	_check("a bundle can beat individual unit packages", bundle_result.status == "optimal" and bundle_result.selected_candidate_ids == ["kit"] and bundle_result.total_cost_cents == 800, str(bundle_result))

	var parts_win := [
		_candidate("kit", ["wing", "tail"], 1200),
		_candidate("part-tail", ["tail"], 600),
		_candidate("part-wing", ["wing"], 500),
	]
	var parts_result := PackageOptimizer.optimize(required, parts_win)
	_check("overlapping bundle and individual candidates form an exact cover", parts_result.status == "optimal" and parts_result.selected_candidate_ids == ["part-tail", "part-wing"] and parts_result.total_cost_cents == 1100, str(parts_result))
	_check("selected provenance is retained in sorted candidate order", parts_result.selected_provenance == [
		{"candidate_id": "part-tail", "provenance": "fixture"},
		{"candidate_id": "part-wing", "provenance": "fixture"},
	])


func _test_unknown_cost_only_blocks_complete_feasible_alternatives() -> void:
	var required := ["left", "right"]
	var candidates := [
		_candidate("bundle", ["left", "right"], 100),
		_candidate("unknown-left", ["left"], null),
	]
	var result := PackageOptimizer.optimize(required, candidates)
	_check("an unknown candidate that cannot complete an exact cover does not hide a known optimum", result.status == "optimal" and result.selected_candidate_ids == ["bundle"] and result.total_cost_cents == 100 and not result.unknown_cost_alternative_found, str(result))

	var unknown_alternative := [
		_candidate("bundle", ["left", "right"], 20),
		_candidate("left", ["left"], 5),
		_candidate("right", ["right"], 5),
		_candidate("unknown-kit", ["left", "right"], null, true, true, "unpriced source"),
	]
	var unknown_result := PackageOptimizer.optimize(required, unknown_alternative)
	_check("a complete unknown-cost alternative prevents an optimality claim", unknown_result.status == "unknown_cost" and unknown_result.unknown_cost_alternative_found and not unknown_result.optimality_proven and unknown_result.selected_candidate_ids == ["left", "right"] and unknown_result.total_cost_cents == 10, str(unknown_result))

	var unknown_only := PackageOptimizer.optimize(required, [
		_candidate("unknown-left", ["left"], null),
		_candidate("known-right", ["right"], 4),
	])
	_check("unknown-cost-only exact cover is reported without inventing a price", unknown_only.status == "unknown_cost" and unknown_only.unknown_cost_alternative_found and unknown_only.selected_candidate_ids.is_empty() and unknown_only.total_cost_cents == null and not unknown_only.optimality_proven, str(unknown_only))

	var incomplete_unknown := PackageOptimizer.optimize(required, [_candidate("unknown-left", ["left"], null)])
	_check("an unknown candidate with no feasible completion does not count as an alternative", incomplete_unknown.status == "infeasible" and not incomplete_unknown.unknown_cost_alternative_found, str(incomplete_unknown))

	var unavailable_unknown := [
		_candidate("known-left", ["left"], 3),
		_candidate("known-right", ["right"], 4),
		_candidate("unavailable-kit", ["left", "right"], null, false),
		_candidate("incompatible-kit", ["left", "right"], null, true, false),
	]
	var unavailable_result := PackageOptimizer.optimize(required, unavailable_unknown)
	_check("unavailable and incompatible unknown prices are excluded", unavailable_result.status == "optimal" and unavailable_result.selected_candidate_ids == ["known-left", "known-right"] and not unavailable_result.unknown_cost_alternative_found, str(unavailable_result))


func _test_infeasible_and_search_limit_results() -> void:
	var no_cover := PackageOptimizer.optimize(["a", "b"], [_candidate("only-a", ["a"], 1)])
	_check("no exact cover is reported as infeasible", no_cover.status == "infeasible" and no_cover.search_complete and not no_cover.optimality_proven and no_cover.selected_candidate_ids.is_empty(), str(no_cover))

	var limited_candidates := [
		_candidate("a-cheap", ["a"], 1),
		_candidate("z-costlier", ["a"], 2),
	]
	var limited := PackageOptimizer.optimize(["a"], limited_candidates, 2)
	_check("hitting the explicit search bound never claims completeness", limited.status == "search_limit" and not limited.search_complete and not limited.optimality_proven and limited.selected_candidate_ids == ["a-cheap"] and limited.total_cost_cents == 1 and limited.search_nodes == 2, str(limited))

	var empty_cover := PackageOptimizer.optimize([], [])
	_check("an empty required set has the empty zero-cost exact cover", empty_cover.status == "optimal" and empty_cover.selected_candidate_ids.is_empty() and empty_cover.total_cost_cents == 0, str(empty_cover))


func _test_small_cases_against_exhaustive_oracle() -> void:
	var fixtures: Array = [
		{
			"units": ["a", "b", "c"],
			"candidates": [
				_candidate("ab", ["a", "b"], 4),
				_candidate("b", ["b"], 3),
				_candidate("c", ["c"], 5),
				_candidate("a", ["a"], 2),
				_candidate("bc", ["b", "c"], 4),
			],
		},
		{
			"units": ["a", "b"],
			"candidates": [
				_candidate("bundle", ["a", "b"], 11),
				_candidate("unit-a", ["a"], 4),
				_candidate("unit-b", ["b"], 4),
				_candidate("unknown", ["a", "b"], null),
			],
		},
		{
			"units": ["a", "b"],
			"candidates": [
				_candidate("bundle", ["a", "b"], 3),
				_candidate("unknown-a", ["a"], null),
			],
		},
		{
			"units": ["a", "b"],
			"candidates": [
				_candidate("only-a", ["a"], 1),
				_candidate("blocked-b", ["b"], 0, false),
			],
		},
	]
	for fixture_index in range(fixtures.size()):
		var fixture: Dictionary = fixtures[fixture_index]
		var expected := _exhaustive_oracle(fixture.units, fixture.candidates)
		var actual := PackageOptimizer.optimize(fixture.units, fixture.candidates)
		_check("small fixture %d matches independent exhaustive subset oracle status" % fixture_index, actual.status == expected.status, "expected %s got %s" % [expected.status, actual.status])
		_check("small fixture %d matches oracle selected IDs" % fixture_index, actual.selected_candidate_ids == expected.selected_candidate_ids, str(actual.selected_candidate_ids) + " vs " + str(expected.selected_candidate_ids))
		_check("small fixture %d matches oracle known cost" % fixture_index, actual.total_cost_cents == expected.total_cost_cents, str(actual.total_cost_cents) + " vs " + str(expected.total_cost_cents))


func _test_ties_order_and_input_purity() -> void:
	var required := ["b", "a"]
	var candidates := [
		_candidate("z", ["b"], 2),
		_candidate("c", ["b"], 2),
		_candidate("b", ["a"], 1),
		_candidate("a", ["a"], 1),
	]
	var original_required := required.duplicate(true)
	var original_candidates := candidates.duplicate(true)
	var first := PackageOptimizer.optimize(required, candidates)
	var reordered_candidates := candidates.duplicate(true)
	reordered_candidates.reverse()
	var second := PackageOptimizer.optimize(["a", "b"], reordered_candidates)
	_check("equal-cost solutions choose the lexicographically smallest sorted candidate IDs", first.selected_candidate_ids == ["a", "c"] and first.total_cost_cents == 3, str(first))
	_check("candidate and required-unit input order do not change the result", first.status == second.status and first.selected_candidate_ids == second.selected_candidate_ids and first.total_cost_cents == second.total_cost_cents, str(second))
	_check("optimizer leaves all caller-owned inputs unchanged", required == original_required and candidates == original_candidates, "required=" + str(required) + " candidates=" + str(candidates))


func _test_malformed_and_unsafe_inputs() -> void:
	_check_invalid("duplicate required IDs", ["a", "a"], [_candidate("a", ["a"], 1)])
	_check_invalid("duplicate candidate IDs", ["a"], [_candidate("same", ["a"], 1), _candidate("same", ["a"], 2)])
	_check_invalid("duplicate coverage IDs", ["a"], [_candidate("a", ["a", "a"], 1)])
	_check_invalid("coverage outside explicit installed units", ["a"], [_candidate("a", ["other"], 1)])
	_check_invalid("fractional integer-cent cost", ["a"], [_candidate("a", ["a"], 1.5)])
	_check_invalid("NaN cost", ["a"], [_candidate("a", ["a"], NAN)])
	_check_invalid("unsafe integer cost", ["a"], [_candidate("a", ["a"], 9007199254740992)])
	_check_invalid("cost above the shared economics ceiling", ["a"], [_candidate("a", ["a"], 9000000000000001)])
	_check_invalid("negative integer-cent cost", ["a"], [_candidate("a", ["a"], -1)])
	var non_boolean_availability := _candidate("a", ["a"], 1)
	non_boolean_availability["available"] = 1
	_check_invalid("non-boolean availability", ["a"], [non_boolean_availability])
	_check_invalid("missing provenance", ["a"], [_without_provenance(_candidate("a", ["a"], 1))])
	_check_invalid("invalid search limit", ["a"], [_candidate("a", ["a"], 1)], 0)

	var maximum_economics := PackageOptimizer.optimize(["a"], [_candidate("max-economics", ["a"], PackageOptimizer.MAX_COST_CENTS)])
	_check("largest supported economics amount remains accepted", maximum_economics.status == "optimal" and maximum_economics.total_cost_cents == PackageOptimizer.MAX_COST_CENTS, str(maximum_economics))


func _test_sum_above_economics_limit() -> void:
	var too_large := PackageOptimizer.optimize(
		["a", "b"],
		[
			_candidate("a", ["a"], 5000000000000000),
			_candidate("b", ["b"], 5000000000000000),
		]
	)
	_check("a feasible total above the shared economics limit is never reported", too_large.status == "cost_out_of_range" and too_large.total_cost_cents == null and not too_large.optimality_proven, str(too_large))


func _without_provenance(candidate: Dictionary) -> Dictionary:
	var copy := candidate.duplicate(true)
	copy.erase("provenance")
	return copy


func _check_invalid(label: String, required: Array, candidates: Array, search_limit: Variant = PackageOptimizer.DEFAULT_SEARCH_LIMIT) -> void:
	var result := PackageOptimizer.optimize(required, candidates, search_limit)
	_check(label + " is rejected", result.status == "invalid_input" and not result.optimality_proven and not result.errors.is_empty(), str(result))


func _exhaustive_oracle(required: Array, candidates: Array) -> Dictionary:
	var best_found := false
	var best_cost := 0
	var best_ids: Array = []
	var unknown_cover_found := false
	var subset_count := 1 << candidates.size()
	for subset in range(subset_count):
		var covered: Dictionary = {}
		var selected_ids: Array = []
		var total_cost := 0
		var unknown_cost := false
		var overlaps := false
		var eligible := true
		for candidate_index in range(candidates.size()):
			if (subset & (1 << candidate_index)) == 0:
				continue
			var candidate: Dictionary = candidates[candidate_index]
			if not candidate.available or not candidate.compatible:
				eligible = false
				break
			selected_ids.append(candidate.id)
			for unit_id in candidate.coverage_ids:
				if covered.has(unit_id):
					overlaps = true
					break
				covered[unit_id] = true
			if overlaps:
				break
			if candidate.cost_cents == null:
				unknown_cost = true
			else:
				total_cost += int(candidate.cost_cents)
		if not eligible or overlaps or covered.size() != required.size():
			continue
		var exact := true
		for unit_id in required:
			if not covered.has(unit_id):
				exact = false
				break
		if not exact:
			continue
		selected_ids.sort()
		if unknown_cost:
			unknown_cover_found = true
		elif not best_found or total_cost < best_cost or (total_cost == best_cost and _oracle_ids_less(selected_ids, best_ids)):
			best_found = true
			best_cost = total_cost
			best_ids = selected_ids
	var status := "infeasible"
	if unknown_cover_found:
		status = "unknown_cost"
	elif best_found:
		status = "optimal"
	return {
		"status": status,
		"selected_candidate_ids": best_ids,
		"total_cost_cents": best_cost if best_found else null,
	}


func _oracle_ids_less(left: Array, right: Array) -> bool:
	var shared_size: int = mini(left.size(), right.size())
	for index in range(shared_size):
		if String(left[index]) < String(right[index]):
			return true
		if String(left[index]) > String(right[index]):
			return false
	return left.size() < right.size()

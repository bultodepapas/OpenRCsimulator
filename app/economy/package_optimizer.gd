class_name PackageOptimizer
extends RefCounted

## Pure bounded search for the least-cost exact cover of installed units.
## See docs/research/crash-damage-investigations/CR-31d/README.md for the input and result contract.

const DEFAULT_SEARCH_LIMIT: int = 100000
const MAX_SEARCH_LIMIT: int = 1000000
const MAX_REQUIRED_UNITS: int = 64
const MAX_CANDIDATES: int = 512
const MAX_COST_CENTS: int = 9000000000000000
const _CANDIDATE_KEYS: Array[String] = [
	"id", "coverage_ids", "cost_cents", "available", "compatible", "provenance",
]


static func optimize(required_unit_ids: Variant, candidates: Variant, search_limit: Variant = DEFAULT_SEARCH_LIMIT) -> Dictionary:
	var validated := _validate_inputs(required_unit_ids, candidates, search_limit)
	var errors: Array = validated.errors
	if not errors.is_empty():
		return _result("invalid_input", [], null, false, false, 0, false, errors, [])

	var unit_ids: Array = validated.unit_ids
	var unit_index: Dictionary = {}
	for index in range(unit_ids.size()):
		unit_index[unit_ids[index]] = index

	var usable_candidates: Array = []
	for raw_candidate in candidates:
		if not raw_candidate.available or not raw_candidate.compatible:
			continue
		var coverage_indices: Array = []
		for unit_id in raw_candidate.coverage_ids:
			coverage_indices.append(int(unit_index[unit_id]))
		coverage_indices.sort()
		usable_candidates.append({
			"id": raw_candidate.id,
			"coverage_indices": coverage_indices,
			"cost_cents": raw_candidate.cost_cents,
			"provenance": raw_candidate.provenance,
		})
	usable_candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.id) < String(right.id)
	)

	var candidates_by_unit: Array = []
	for _unit_index in range(unit_ids.size()):
		candidates_by_unit.append([])
	for candidate_index in range(usable_candidates.size()):
		for covered_index in usable_candidates[candidate_index].coverage_indices:
			candidates_by_unit[covered_index].append(candidate_index)

	var covered := PackedByteArray()
	covered.resize(unit_ids.size())
	covered.fill(0)
	var context := {
		"unit_count": unit_ids.size(),
		"candidates": usable_candidates,
		"candidates_by_unit": candidates_by_unit,
		"search_limit": int(search_limit),
		"search_nodes": 0,
		"limit_reached": false,
		"unknown_cover_found": false,
		"over_limit_known_cover_found": false,
		"best_found": false,
		"best_cost": 0,
		"best_ids": [],
	}
	_search(context, covered, [], 0, 0, false, false)

	var selected_ids: Array = context.best_ids.duplicate()
	var selected_provenance := _selected_provenance(selected_ids, usable_candidates)
	var status := "infeasible"
	if context.limit_reached:
		status = "search_limit"
	elif context.unknown_cover_found:
		status = "unknown_cost"
	elif context.best_found:
		status = "optimal"
	elif context.over_limit_known_cover_found:
		status = "cost_out_of_range"
	return _result(
		status,
		selected_ids,
		context.best_cost if context.best_found else null,
		status == "optimal",
		not context.limit_reached,
		int(context.search_nodes),
		bool(context.unknown_cover_found),
		[],
		selected_provenance
	)


static func _validate_inputs(required_unit_ids: Variant, candidates: Variant, search_limit: Variant) -> Dictionary:
	var errors: Array = []
	if typeof(search_limit) != TYPE_INT or int(search_limit) < 1 or int(search_limit) > MAX_SEARCH_LIMIT:
		errors.append("search_limit must be an integer from 1 to %d" % MAX_SEARCH_LIMIT)
	if typeof(required_unit_ids) != TYPE_ARRAY:
		errors.append("required_unit_ids must be an array of unique non-empty strings")
	if typeof(candidates) != TYPE_ARRAY:
		errors.append("candidates must be an array")
	if typeof(required_unit_ids) != TYPE_ARRAY or typeof(candidates) != TYPE_ARRAY:
		return {"errors": errors, "unit_ids": []}

	if required_unit_ids.size() > MAX_REQUIRED_UNITS:
		errors.append("required_unit_ids exceeds the %d-unit bound" % MAX_REQUIRED_UNITS)
		return {"errors": errors, "unit_ids": []}
	if candidates.size() > MAX_CANDIDATES:
		errors.append("candidates exceeds the %d-candidate bound" % MAX_CANDIDATES)
		return {"errors": errors, "unit_ids": []}
	var unit_seen: Dictionary = {}
	var unit_ids: Array = []
	for unit_id in required_unit_ids:
		if typeof(unit_id) != TYPE_STRING or String(unit_id).strip_edges().is_empty():
			errors.append("required_unit_ids entries must be non-empty strings")
			continue
		if unit_seen.has(unit_id):
			errors.append("required_unit_ids contains duplicate ID %s" % unit_id)
			continue
		unit_seen[unit_id] = true
		unit_ids.append(unit_id)
	unit_ids.sort()

	var candidate_ids: Dictionary = {}
	for candidate_index in range(candidates.size()):
		var candidate: Variant = candidates[candidate_index]
		if typeof(candidate) != TYPE_DICTIONARY:
			errors.append("candidate %d must be a dictionary" % candidate_index)
			continue
		if candidate.size() != _CANDIDATE_KEYS.size():
			errors.append("candidate %d must contain exactly the six documented fields" % candidate_index)
		for key in _CANDIDATE_KEYS:
			if not candidate.has(key):
				errors.append("candidate %d is missing %s" % [candidate_index, key])
		if not candidate.has("id") or typeof(candidate.id) != TYPE_STRING or String(candidate.id).strip_edges().is_empty():
			errors.append("candidate %d id must be a non-empty string" % candidate_index)
		elif candidate_ids.has(candidate.id):
			errors.append("candidate IDs must be unique: %s" % candidate.id)
		else:
			candidate_ids[candidate.id] = true
		if not candidate.has("coverage_ids") or typeof(candidate.coverage_ids) != TYPE_ARRAY:
			errors.append("candidate %d coverage_ids must be an array" % candidate_index)
		else:
			if candidate.coverage_ids.is_empty():
				errors.append("candidate %d coverage_ids must not be empty" % candidate_index)
			if candidate.coverage_ids.size() > required_unit_ids.size():
				errors.append("candidate %d coverage_ids is larger than the required-unit set" % candidate_index)
			else:
				var coverage_seen: Dictionary = {}
				for unit_id in candidate.coverage_ids:
					if typeof(unit_id) != TYPE_STRING or String(unit_id).strip_edges().is_empty():
						errors.append("candidate %d coverage IDs must be non-empty strings" % candidate_index)
						continue
					if coverage_seen.has(unit_id):
						errors.append("candidate %d repeats coverage ID %s" % [candidate_index, unit_id])
						continue
					coverage_seen[unit_id] = true
					if not unit_seen.has(unit_id):
						errors.append("candidate %d covers unrequired ID %s" % [candidate_index, unit_id])
		if candidate.has("cost_cents"):
			var cost: Variant = candidate.cost_cents
			if cost != null and (typeof(cost) != TYPE_INT or int(cost) < 0 or int(cost) > MAX_COST_CENTS):
				errors.append("candidate %d cost_cents must be null or an integer from 0 through %d" % [candidate_index, MAX_COST_CENTS])
		for flag in ["available", "compatible"]:
			if candidate.has(flag) and typeof(candidate[flag]) != TYPE_BOOL:
				errors.append("candidate %d %s must be a boolean" % [candidate_index, flag])
		if candidate.has("provenance") and (typeof(candidate.provenance) != TYPE_STRING or String(candidate.provenance).strip_edges().is_empty()):
			errors.append("candidate %d provenance must be a non-empty string" % candidate_index)
	return {"errors": errors, "unit_ids": unit_ids}


static func _search(
	context: Dictionary,
	covered: PackedByteArray,
	selected_indices: Array,
	covered_count: int,
	running_cost: int,
	amount_over_limit: bool,
	has_unknown_cost: bool
) -> void:
	if context.limit_reached:
		return
	if has_unknown_cost and context.unknown_cover_found:
		return
	if int(context.search_nodes) >= int(context.search_limit):
		context.limit_reached = true
		return
	context.search_nodes = int(context.search_nodes) + 1

	if covered_count == int(context.unit_count):
		if has_unknown_cost:
			context.unknown_cover_found = true
		elif amount_over_limit:
			context.over_limit_known_cover_found = true
		else:
			var candidate_ids := _selected_ids(selected_indices, context.candidates)
			if not context.best_found or running_cost < int(context.best_cost) or (
				running_cost == int(context.best_cost)
				and _string_arrays_less(candidate_ids, context.best_ids)
			):
				context.best_found = true
				context.best_cost = running_cost
				context.best_ids = candidate_ids
		return

	var chosen_unit := -1
	var chosen_candidates: Array = []
	for unit_index in range(int(context.unit_count)):
		if covered[unit_index] != 0:
			continue
		var choices: Array = []
		for candidate_index in context.candidates_by_unit[unit_index]:
			if _candidate_fits(context.candidates[candidate_index], covered):
				choices.append(candidate_index)
		if choices.is_empty():
			return
		if chosen_unit == -1 or choices.size() < chosen_candidates.size():
			chosen_unit = unit_index
			chosen_candidates = choices

	for candidate_index in chosen_candidates:
		if context.limit_reached or (has_unknown_cost and context.unknown_cover_found):
			return
		var candidate: Dictionary = context.candidates[candidate_index]
		var next_unknown := has_unknown_cost or candidate.cost_cents == null
		var next_cost := running_cost
		var next_over_limit := amount_over_limit
		if candidate.cost_cents != null and not next_over_limit:
			var candidate_cost := int(candidate.cost_cents)
			if candidate_cost > MAX_COST_CENTS - next_cost:
				next_over_limit = true
			else:
				next_cost += candidate_cost
		for covered_index in candidate.coverage_indices:
			covered[covered_index] = 1
		selected_indices.append(candidate_index)
		_search(
			context,
			covered,
			selected_indices,
			covered_count + candidate.coverage_indices.size(),
			next_cost,
			next_over_limit,
			next_unknown
		)
		selected_indices.pop_back()
		for covered_index in candidate.coverage_indices:
			covered[covered_index] = 0


static func _candidate_fits(candidate: Dictionary, covered: PackedByteArray) -> bool:
	for covered_index in candidate.coverage_indices:
		if covered[covered_index] != 0:
			return false
	return true


static func _selected_ids(selected_indices: Array, candidates: Array) -> Array:
	var ids: Array = []
	for candidate_index in selected_indices:
		ids.append(String(candidates[candidate_index].id))
	ids.sort()
	return ids


static func _string_arrays_less(left: Array, right: Array) -> bool:
	var shared_size: int = mini(left.size(), right.size())
	for index in range(shared_size):
		var left_id := String(left[index])
		var right_id := String(right[index])
		if left_id < right_id:
			return true
		if left_id > right_id:
			return false
	return left.size() < right.size()


static func _selected_provenance(selected_ids: Array, candidates: Array) -> Array:
	if selected_ids.is_empty():
		return []
	var by_id: Dictionary = {}
	for candidate in candidates:
		by_id[candidate.id] = candidate.provenance
	var result: Array = []
	for candidate_id in selected_ids:
		result.append({"candidate_id": candidate_id, "provenance": by_id[candidate_id]})
	return result


static func _result(
	status: String,
	selected_ids: Array,
	total_cost_cents: Variant,
	optimality_proven: bool,
	search_complete: bool,
	search_nodes: int,
	unknown_cost_alternative_found: bool,
	errors: Array,
	selected_provenance: Array
) -> Dictionary:
	return {
		"status": status,
		"selected_candidate_ids": selected_ids,
		"total_cost_cents": total_cost_cents,
		"optimality_proven": optimality_proven,
		"search_complete": search_complete,
		"search_nodes": search_nodes,
		"unknown_cost_alternative_found": unknown_cost_alternative_found,
		"errors": PackedStringArray(errors),
		"selected_provenance": selected_provenance,
	}

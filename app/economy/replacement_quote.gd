extends RefCounted

## Read-only replacement estimate adapter over an economics dossier and assessment.
## Package coverage is explicit authored input; dossier individual prices are valuation assumptions.

const Calculator = preload("res://economy/calculator.gd")
const PackageOptimizer = preload("res://economy/package_optimizer.gd")

const MAX_REQUIRED_UNITS: int = 64
const MAX_CANDIDATES: int = 512
const MAX_ID_LENGTH: int = 128
const MAX_COMPONENT_ID_LENGTH: int = 128
const MAX_COVERAGE_ID_LENGTH: int = MAX_COMPONENT_ID_LENGTH + 4
const MAX_PROVENANCE_LENGTH: int = 2048
const MAX_ERROR_COUNT: int = 16
const MAX_ERROR_LENGTH: int = 256
const MAX_CANDIDATE_CATALOG_BYTES: int = 10000
const MAX_SELECTED_PROVENANCE_CHARS: int = 16000
const _PACKAGE_KEYS: Array[String] = ["id", "coverage_ids", "cost_cents", "available", "compatible", "provenance"]
const _REPLACEMENT_ACTION: String = "replacement"


## Quote only the component units whose validated calculator line uses replacement.
## This is a snapshot estimate; it is not a purchase, inventory, availability, or fit check.
static func quote(
	dossier: Dictionary,
	assessment: Dictionary,
	package_candidates: Array = [],
	search_limit: Variant = PackageOptimizer.DEFAULT_SEARCH_LIMIT
) -> Dictionary:
	return quote_calculated(dossier, assessment, Calculator.calculate(dossier, assessment), package_candidates, search_limit)


## Same quote from a Calculator.calculate(dossier, assessment) result the caller already holds.
## Only ok, complete and replacement lines (id, action, quantity) are read.
static func quote_calculated(
	dossier: Dictionary,
	assessment: Dictionary,
	calculation: Dictionary,
	package_candidates: Array = [],
	search_limit: Variant = PackageOptimizer.DEFAULT_SEARCH_LIMIT
) -> Dictionary:
	var assessment_complete: bool = bool(calculation.get("complete", false))
	if not bool(calculation.get("ok", false)):
		return _base_result("invalid_assessment", assessment_complete, null, false, _bounded_errors(calculation.get("errors", [])))
	if bool(assessment.get("total_loss", false)):
		return _base_result(
			"unsupported_total_loss",
			assessment_complete,
			null,
			false,
			["Total-loss estimates require a broader replacement and salvage comparison."],
		)

	var components_by_id: Dictionary = {}
	for component_value: Variant in dossier.get("components", []):
		var component: Dictionary = component_value
		components_by_id[String(component["id"])] = component

	var unit_records: Array = []
	for line_value: Variant in calculation.get("lines", []):
		if typeof(line_value) != TYPE_DICTIONARY:
			continue
		var line: Dictionary = line_value
		if line.get("action") != _REPLACEMENT_ACTION:
			continue
		var component_id: Variant = line.get("id")
		if typeof(component_id) != TYPE_STRING or String(component_id).is_empty() or String(component_id).length() > MAX_COMPONENT_ID_LENGTH:
			return _base_result(
				"invalid_assessment",
				assessment_complete,
				null,
				false,
				["Replacement component ID is empty or exceeds the supported length."],
			)
		var quantity_value: Variant = line.get("quantity")
		if typeof(quantity_value) != TYPE_INT or int(quantity_value) <= 0:
			return _base_result(
				"invalid_assessment",
				assessment_complete,
				null,
				false,
				["Replacement decisions must select at least one installed unit."],
			)
		var quantity: int = int(quantity_value)
		if quantity > MAX_REQUIRED_UNITS - unit_records.size():
			return _base_result(
				"unit_bound_exceeded",
				assessment_complete,
				null,
				false,
				["Replacement quote exceeds the %d-installed-unit bound." % MAX_REQUIRED_UNITS],
			)
		if not components_by_id.has(component_id):
			return _base_result(
				"invalid_assessment",
				assessment_complete,
				null,
				false,
				["Replacement line refers to a component absent from the validated dossier."],
			)
		var component: Dictionary = components_by_id[component_id]
		for unit_index: int in range(quantity):
			unit_records.append({
				"unit_id": "%s:%d" % [component_id, unit_index],
				"component_id": component_id,
				"unit_index": unit_index,
				"component": component,
			})

	if unit_records.is_empty():
		var no_replacement_result := _base_result("no_replacements", assessment_complete, 0, assessment_complete, [])
		no_replacement_result["optimizer_status"] = "optimal"
		no_replacement_result["optimality_proven"] = true
		no_replacement_result["search_complete"] = true
		return no_replacement_result

	unit_records.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.unit_id) < String(right.unit_id)
	)
	var required_unit_ids: Array = []
	var optimizer_candidates: Array = []
	var candidate_catalog: Array = []
	for index: int in range(unit_records.size()):
		var record: Dictionary = unit_records[index]
		var component: Dictionary = record.component
		var unit_id: String = String(record.unit_id)
		required_unit_ids.append(unit_id)
		var candidate_id := "individual-%03d" % index
		var provenance := _individual_provenance(dossier, component)
		var candidate := {
			"id": candidate_id,
			"coverage_ids": [unit_id],
			"cost_cents": component.get("unit_minor"),
			# These flags make the dossier estimate feasible in the optimizer; they do not
			# establish live seller availability or a physically qualified retail fit.
			"available": true,
			"compatible": true,
			"provenance": provenance,
		}
		optimizer_candidates.append(candidate)
		candidate_catalog.append({
			"candidate_id": candidate_id,
			"candidate_kind": "dossier_individual_estimate",
			"coverage_ids": [unit_id],
			"component_id": record.component_id,
			"unit_index": record.unit_index,
			"cost_cents": component.get("unit_minor"),
			"available": true,
			"compatible": true,
			"live_availability_confirmed": false,
			"physical_fit_confirmed": false,
			"provenance": provenance,
		})

	var package_validation := _bounded_package_candidates(package_candidates, optimizer_candidates.size())
	if not bool(package_validation.ok):
		return _base_result(
			"invalid_candidates",
			assessment_complete,
			null,
			false,
			_bounded_errors(package_validation.errors),
			required_unit_ids,
		)
	for package_candidate: Dictionary in package_validation.candidates:
		optimizer_candidates.append(package_candidate)
		candidate_catalog.append({
			"candidate_id": package_candidate.id,
			"candidate_kind": "authored_package_candidate",
			"coverage_ids": package_candidate.coverage_ids.duplicate(),
			"cost_cents": package_candidate.cost_cents,
			"available": package_candidate.available,
			"compatible": package_candidate.compatible,
			"live_availability_confirmed": false,
			"compatibility_basis": "Explicit authored coverage and compatible flag; no retail fit is inferred.",
			"provenance": package_candidate.provenance,
		})

	var optimized: Dictionary = PackageOptimizer.optimize(required_unit_ids, optimizer_candidates, search_limit)
	candidate_catalog.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.candidate_id) < String(right.candidate_id)
	)
	var optimizer_status: String = String(optimized.get("status", "invalid_input"))
	var errors: Array = _bounded_errors(optimized.get("errors", []))
	var catalog_omitted: bool = false
	if optimizer_status == "invalid_input":
		# Do not echo malformed values (including NaN) back through the report-facing catalog.
		candidate_catalog.clear()
		catalog_omitted = true
	elif JSON.stringify(candidate_catalog).to_utf8_buffer().size() > MAX_CANDIDATE_CATALOG_BYTES:
		candidate_catalog.clear()
		catalog_omitted = true
	var selected_provenance: Dictionary = _bounded_selected_provenance(optimized.get("selected_provenance", []))
	var selected_lines: Array = []
	for candidate: Dictionary in optimizer_candidates:
		if candidate.id in optimized.get("selected_candidate_ids", []):
			var coverage: Array = candidate.coverage_ids.duplicate()
			coverage.sort()
			selected_lines.append({"candidate_id": candidate.id, "coverage_ids": coverage, "cost_cents": candidate.cost_cents})
	selected_lines.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.candidate_id) < String(right.candidate_id)
	)
	return {
		"status": optimizer_status,
		"optimizer_status": optimizer_status,
		"coverage_scope": "replacements_only",
		"assessment_complete": assessment_complete,
		"complete": assessment_complete and bool(optimized.get("optimality_proven", false)),
		"optimality_proven": bool(optimized.get("optimality_proven", false)),
		"search_complete": bool(optimized.get("search_complete", false)),
		"search_nodes": int(optimized.get("search_nodes", 0)),
		"unknown_cost_alternative_found": bool(optimized.get("unknown_cost_alternative_found", false)),
		"total_cost_cents": optimized.get("total_cost_cents"),
		"required_unit_ids": required_unit_ids,
		"selected_candidate_ids": optimized.get("selected_candidate_ids", []).duplicate(true),
		"selected_lines": selected_lines,
		"selected_provenance": selected_provenance.entries,
		"selected_provenance_truncated": selected_provenance.truncated,
		"candidate_catalog": candidate_catalog,
		"candidate_catalog_omitted": catalog_omitted,
		"currency": _bounded_text(dossier.get("currency", "USD"), 32),
		"price_date": _bounded_text(dossier.get("price_date", ""), 128),
		"errors": errors,
		"estimate_note": "Replacement-only snapshot estimate; not a purchase, inventory, live availability, physical-fit, complete repair total, labor, or salvage result.",
	}


static func _bounded_package_candidates(package_candidates: Array, default_count: int) -> Dictionary:
	if package_candidates.size() > MAX_CANDIDATES - default_count:
		return {"ok": false, "errors": ["Package candidates plus individual estimates exceed the %d-candidate bound." % MAX_CANDIDATES], "candidates": []}
	var candidates: Array = []
	for index: int in range(package_candidates.size()):
		var candidate_value: Variant = package_candidates[index]
		if typeof(candidate_value) != TYPE_DICTIONARY:
			return {"ok": false, "errors": ["Package candidate %d must be a dictionary." % index], "candidates": []}
		var candidate: Dictionary = candidate_value
		if candidate.size() != _PACKAGE_KEYS.size():
			return {"ok": false, "errors": ["Package candidate %d must contain exactly the six documented fields." % index], "candidates": []}
		for key: Variant in candidate.keys():
			if typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME:
				return {"ok": false, "errors": ["Package candidate %d contains an unknown field." % index], "candidates": []}
			if String(key) not in _PACKAGE_KEYS:
				return {"ok": false, "errors": ["Package candidate %d contains an unknown field." % index], "candidates": []}
		for key: String in _PACKAGE_KEYS:
			if not candidate.has(key):
				return {"ok": false, "errors": ["Package candidate %d is missing %s." % [index, key]], "candidates": []}
		var id_value: Variant = candidate.get("id")
		if typeof(id_value) != TYPE_STRING or String(id_value).strip_edges().is_empty():
			return {"ok": false, "errors": ["Package candidate %d ID must be a non-empty string." % index], "candidates": []}
		if String(id_value).length() > MAX_ID_LENGTH:
			return {"ok": false, "errors": ["Package candidate %d ID exceeds the supported length." % index], "candidates": []}
		var provenance_value: Variant = candidate.get("provenance")
		if typeof(provenance_value) != TYPE_STRING or String(provenance_value).strip_edges().is_empty():
			return {"ok": false, "errors": ["Package candidate %d provenance must be a non-empty string." % index], "candidates": []}
		if String(provenance_value).length() > MAX_PROVENANCE_LENGTH:
			return {"ok": false, "errors": ["Package candidate %d provenance exceeds %d characters." % [index, MAX_PROVENANCE_LENGTH]], "candidates": []}
		var coverage_value: Variant = candidate.get("coverage_ids")
		if typeof(coverage_value) != TYPE_ARRAY or coverage_value.is_empty() or coverage_value.size() > MAX_REQUIRED_UNITS:
			return {"ok": false, "errors": ["Package candidate %d coverage_ids must contain 1 through %d entries." % [index, MAX_REQUIRED_UNITS]], "candidates": []}
		var safe_coverage: Array = []
		for coverage_id: Variant in coverage_value:
			if typeof(coverage_id) != TYPE_STRING or String(coverage_id).strip_edges().is_empty():
				return {"ok": false, "errors": ["Package candidate %d coverage entries must be non-empty strings." % index], "candidates": []}
			if String(coverage_id).length() > MAX_COVERAGE_ID_LENGTH:
				return {"ok": false, "errors": ["Package candidate %d coverage ID exceeds the supported length." % index], "candidates": []}
			safe_coverage.append(String(coverage_id))
		var cost_value: Variant = candidate.get("cost_cents")
		if cost_value != null and (typeof(cost_value) != TYPE_INT or int(cost_value) < 0 or int(cost_value) > PackageOptimizer.MAX_COST_CENTS):
			return {"ok": false, "errors": ["Package candidate %d cost_cents must be null or an integer within the supported economics range." % index], "candidates": []}
		if typeof(candidate.get("available")) != TYPE_BOOL or typeof(candidate.get("compatible")) != TYPE_BOOL:
			return {"ok": false, "errors": ["Package candidate %d available and compatible fields must be booleans." % index], "candidates": []}
		# Rebuild from validated scalar fields and a string-only array; never deep-copy untrusted input.
		candidates.append({
			"id": String(id_value),
			"coverage_ids": safe_coverage,
			"cost_cents": cost_value,
			"available": candidate.available,
			"compatible": candidate.compatible,
			"provenance": String(provenance_value),
		})
	return {"ok": true, "errors": [], "candidates": candidates}


static func _individual_provenance(dossier: Dictionary, component: Dictionary) -> String:
	var parts: Array[String] = ["Dossier snapshot estimate; not a live offer"]
	parts.append("price basis: %s" % _bounded_text(component.get("price_basis", "unknown"), 256))
	var offer_id: String = _bounded_text(component.get("offer_id", ""), 256)
	if not offer_id.is_empty():
		parts.append("source offer: %s" % offer_id)
	var notes: String = _bounded_text(component.get("notes", ""), 1400)
	if not notes.is_empty():
		parts.append("source notes: %s" % notes)
	var price_date: String = _bounded_text(dossier.get("price_date", ""), 128)
	if not price_date.is_empty():
		parts.append("catalog snapshot date: %s" % price_date)
	return _bounded_text("; ".join(parts), MAX_PROVENANCE_LENGTH)


static func _base_result(
	status: String,
	assessment_complete: bool,
	total_cost_cents: Variant,
	complete: bool,
	errors: Array,
	required_unit_ids: Array = []
) -> Dictionary:
	return {
		"status": status,
		"optimizer_status": "not_run",
		"coverage_scope": "replacements_only",
		"assessment_complete": assessment_complete,
		"complete": complete,
		"optimality_proven": false,
		"search_complete": false,
		"search_nodes": 0,
		"unknown_cost_alternative_found": false,
		"total_cost_cents": total_cost_cents,
		"required_unit_ids": required_unit_ids.duplicate(true),
		"selected_candidate_ids": [],
		"selected_lines": [],
		"selected_provenance": [],
		"selected_provenance_truncated": false,
		"candidate_catalog": [],
		"candidate_catalog_omitted": false,
		"errors": _bounded_errors(errors),
		"estimate_note": "Replacement-only snapshot estimate; not a purchase, inventory, live availability, physical-fit, complete repair total, labor, or salvage result.",
	}


static func _bounded_errors(raw_errors: Variant) -> Array:
	if typeof(raw_errors) != TYPE_ARRAY and typeof(raw_errors) != TYPE_PACKED_STRING_ARRAY:
		return ["Result contains an invalid error list."]
	var errors: Array = []
	var limit: int = mini(raw_errors.size(), MAX_ERROR_COUNT)
	for index: int in range(limit):
		errors.append(_bounded_text(raw_errors[index], MAX_ERROR_LENGTH))
	if raw_errors.size() > MAX_ERROR_COUNT:
		errors.append("Additional errors omitted to keep this quote bounded.")
	return errors


static func _bounded_text(value: Variant, max_length: int) -> String:
	if typeof(value) != TYPE_STRING:
		return ""
	var text: String = String(value).strip_edges()
	if text.length() <= max_length:
		return text
	return text.substr(0, max_length - 1) + "…"


static func _bounded_selected_provenance(raw_provenance: Variant) -> Dictionary:
	if typeof(raw_provenance) != TYPE_ARRAY:
		return {"entries": [], "truncated": true}
	var entries: Array = []
	var per_entry_limit: int = int(MAX_SELECTED_PROVENANCE_CHARS / maxi(1, raw_provenance.size()))
	var truncated: bool = raw_provenance.size() > PackageOptimizer.MAX_REQUIRED_UNITS
	for index: int in range(mini(raw_provenance.size(), PackageOptimizer.MAX_REQUIRED_UNITS)):
		var row: Variant = raw_provenance[index]
		if typeof(row) != TYPE_DICTIONARY:
			truncated = true
			continue
		var candidate_id: String = _bounded_text(row.get("candidate_id", ""), MAX_ID_LENGTH)
		var provenance: String = _bounded_text(row.get("provenance", ""), per_entry_limit)
		if provenance != row.get("provenance", "") or candidate_id != row.get("candidate_id", ""):
			truncated = true
		entries.append({"candidate_id": candidate_id, "provenance": provenance})
	return {"entries": entries, "truncated": truncated}

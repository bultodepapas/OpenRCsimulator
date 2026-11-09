extends RefCounted
## Pure, revision-bound cost plan preparation. A selected purchase is an
## estimate, not a realized purchase or a persistent spare inventory.

const Calculator = preload("res://economy/calculator.gd")
const ReplacementQuote = preload("res://economy/replacement_quote.gd")
const RepairPlanner = preload("res://economy/repair_planner.gd")
const PackageOptimizer = preload("res://economy/package_optimizer.gd")

const FORMAT := "openrc-cost-transaction v1"
const RECEIPT_FORMAT := "openrc-cost-transaction-receipt v1"
const BOOK_FORMAT := "openrc-game-purchase-book v1"
const LABOR_FORMAT := "openrc-game-labor-policy v1"
const MAX_MINOR := 9000000000000000
const MAX_REQUEST_BYTES := 65536
const MAX_RECEIPT_BYTES := 196608
const MAX_ACTIONS := 64
const _REQUEST_KEYS := ["format", "transaction_id", "identity", "catalog_hash", "profile_hash", "recipe_hash", "purchase_book_hash", "labor_policy_hash", "expected_revision", "repair_inspection", "repair_choices", "labor_mode", "costing_basis", "shared_labor_groups", "purchase_mode", "selected_candidate_ids", "incurred_fees"]
const _PACKAGE_KEYS := ["id", "component_quantities", "cost_cents", "available", "compatible", "provenance"]
const _LABOR_KEYS := ["format", "currency", "paid_rate_minor_per_hour", "minutes_by_component", "shared_setup_minutes", "basis", "evidence"]


static func digest(value: Variant) -> String:
	return JSON.stringify(value, "", true, true).sha256_text()


## A trusted frozen book describes sold contents, not the incident's damage.
## Tokens for surviving/unneeded contents are recorded as unvalued extras.
static func package_candidates(book: Dictionary, dossier: Dictionary, assessment: Dictionary) -> Dictionary:
	if not _safe_tree(book) or not _safe_tree(dossier) or not _safe_tree(assessment) \
		or not _keys(book, ["format", "aircraft_id", "packages"]) \
		or book.get("format") != BOOK_FORMAT or book.get("aircraft_id") != dossier.get("aircraft_id") \
		or not book.get("packages") is Array or book.packages.size() > PackageOptimizer.MAX_CANDIDATES:
		return _failure("Purchase book has an invalid schema or aircraft identity.")
	var calculation := Calculator.calculate(dossier, assessment)
	if not calculation.get("ok", false):
		return _failure("Purchase requirements have an invalid assessment.")
	var components: Dictionary = {}
	for component: Dictionary in dossier.get("components", []):
		components[component.id] = component
	var requirements: Dictionary = {}
	var all_required: Dictionary = {}
	for line: Dictionary in calculation.get("lines", []):
		if line.get("action") != "replacement":
			continue
		var id: String = str(line.get("id", ""))
		var quantity: Variant = line.get("quantity")
		if not components.has(id) or typeof(quantity) != TYPE_INT or quantity <= 0 or quantity > MAX_ACTIONS:
			return _failure("Replacement requirements exceed the supported unit bound.")
		var units: Array = []
		for index: int in range(quantity):
			var unit := "%s:%d" % [id, index]
			units.append(unit)
			all_required[unit] = true
		requirements[id] = units
	if all_required.size() > MAX_ACTIONS:
		return _failure("Replacement requirements exceed the supported unit bound.")
	var candidates: Array = []
	var seen: Dictionary = {}
	var candidate_ids: Dictionary = {}
	var candidate_packages: Dictionary = {}
	for raw: Variant in book.packages:
		if not raw is Dictionary or not _keys(raw, _PACKAGE_KEYS) or not _text(raw.get("id"), 128) \
			or seen.has(raw.id) or not _text(raw.get("provenance"), 2048) \
			or not raw.get("component_quantities") is Dictionary or raw.component_quantities.is_empty() \
			or raw.component_quantities.size() > MAX_ACTIONS:
			return _failure("Purchase book contains an invalid or duplicate package.")
		seen[raw.id] = true
		if raw.cost_cents != null and not _minor(raw.cost_cents):
			return _failure("Package price must be unknown or bounded integer cents.")
		for flag: String in ["available", "compatible"]:
			if raw[flag] != null and typeof(raw[flag]) != TYPE_BOOL:
				return _failure("Package availability and compatibility must be boolean or unknown.")
		var component_ids: Array = raw.component_quantities.keys()
		component_ids.sort()
		var count := 0
		for id: Variant in component_ids:
			var amount: Variant = raw.component_quantities[id]
			if not _text(id, 128) or not components.has(id) or typeof(amount) != TYPE_INT or amount <= 0 or amount > MAX_ACTIONS - count:
				return _failure("Package contents have unknown components or exceed the unit bound.")
			count += int(amount)
		if raw.available == false or raw.compatible == false:
			continue
		var choices: Array = [[]]
		var surplus: Array = []
		for id: Variant in component_ids:
			var amount: Variant = raw.component_quantities[id]
			var needed: Array = requirements.get(id, [])
			var allocated := mini(int(amount), needed.size())
			var combinations: Array = []
			_choose_units(needed, allocated, 0, [], combinations, PackageOptimizer.MAX_CANDIDATES)
			if combinations.size() > PackageOptimizer.MAX_CANDIDATES:
				return _failure("Package allocation combinations exceed the candidate bound.")
			var expanded: Array = []
			for prefix: Array in choices:
				for choice: Array in combinations:
					expanded.append(prefix + choice)
					if expanded.size() > PackageOptimizer.MAX_CANDIDATES:
						return _failure("Package allocation combinations exceed the candidate bound.")
			choices = expanded
			for index: int in range(int(amount) - allocated):
				var extra := "extra@%s/%d" % [id, index]
				if extra.length() > ReplacementQuote.MAX_COVERAGE_ID_LENGTH or all_required.has(extra):
					return _failure("Package surplus identity exceeds its bound or collides with a requirement.")
				surplus.append(extra)
		var nonempty: Array = []
		for covered: Array in choices:
			if not covered.is_empty():
				covered.sort()
				nonempty.append(covered)
		surplus.sort()
		for covered: Array in nonempty:
			var candidate_id: String = raw.id
			if nonempty.size() > 1:
				candidate_id = String(raw.id).substr(0, 88) + "@" + digest([raw.id, covered]).substr(0, 32)
			if candidate_ids.has(candidate_id):
				return _failure("Expanded package candidate IDs collide.")
			candidate_ids[candidate_id] = true
			candidate_packages[candidate_id] = raw.id
			candidates.append({"id": candidate_id, "coverage_ids": covered, "surplus_ids": surplus.duplicate(),
				"cost_cents": raw.cost_cents, "available": raw.available, "compatible": raw.compatible,
				"provenance": raw.provenance})
			if candidates.size() > PackageOptimizer.MAX_CANDIDATES - all_required.size():
				return _failure("Expanded package candidates exceed the bounded search universe.")
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.id) < String(b.id))
	var required_ids: Array = all_required.keys()
	required_ids.sort()
	return {"ok": true, "errors": [], "candidates": candidates, "candidate_package_ids": candidate_packages,
		"required_unit_ids": required_ids, "candidate_catalog_hash": digest(candidates)}


static func _choose_units(units: Array, count: int, start: int, selected: Array, output: Array, limit: int) -> void:
	if output.size() > limit:
		return
	if selected.size() == count:
		output.append(selected.duplicate())
		return
	var remaining: int = count - selected.size()
	for index: int in range(start, units.size() - remaining + 1):
		selected.append(units[index])
		_choose_units(units, count, index + 1, selected, output, limit)
		selected.pop_back()
		if output.size() > limit:
			return


static func prepare_mode(dossier: Dictionary, assessment: Dictionary, recipe_book: Dictionary,
		context: Dictionary, labor_mode: String) -> Dictionary:
	if not context.get("identity") is Dictionary or not _safe_tree(context.identity):
		return _failure("Transaction context has no incident identity.")
	return prepare(_mode_request(context, labor_mode), dossier, assessment, recipe_book, context)


static func _mode_request(context: Dictionary, labor_mode: String) -> Dictionary:
	var request := {"format": FORMAT, "transaction_id": "auto-" + digest([context.get("identity"), context.get("revision"), labor_mode, context.get("purchase_book_hash"), context.get("labor_policy_hash")]),
		"identity": context.get("identity", {}).duplicate(true), "catalog_hash": context.get("catalog_hash", ""),
		"profile_hash": context.get("profile_hash", ""), "recipe_hash": context.get("recipe_hash", ""),
		"purchase_book_hash": context.get("purchase_book_hash", ""), "labor_policy_hash": context.get("labor_policy_hash", ""),
		"expected_revision": context.get("revision"), "repair_inspection": null, "repair_choices": [],
		"labor_mode": labor_mode, "costing_basis": "cash", "shared_labor_groups": [],
		"purchase_mode": "optimal", "selected_candidate_ids": [], "incurred_fees": []}
	return request


## One explicitly chosen book package plus individually priced uncovered
## units. Package identity comes from the exact frozen map, never a prefix.
static func prepare_package_option(dossier: Dictionary, assessment: Dictionary, recipe_book: Dictionary,
		context: Dictionary, labor_mode: String, package_id: String) -> Dictionary:
	if not _text(package_id, 128) or not context.get("identity") is Dictionary or not _safe_tree(context.identity) or not context.get("package_book") is Dictionary:
		return _failure("A trusted frozen package ID is required.")
	var adapted := package_candidates(context.package_book, dossier, assessment)
	if not adapted.get("ok", false):
		return adapted
	var required: Array = adapted.required_unit_ids
	if required.is_empty():
		return _failure("No replacement units need a package.")
	var components: Dictionary = {}
	for component: Dictionary in dossier.get("components", []):
		components[component.id] = component
	var best: Array = []
	var best_cost: Variant = null
	var considered := 0
	for candidate: Dictionary in adapted.candidates:
		if adapted.candidate_package_ids.get(candidate.id) != package_id:
			continue
		considered += 1
		if considered > MAX_ACTIONS:
			return _failure("Package option allocation choices exceed the preview bound.")
		if typeof(candidate.available) != TYPE_BOOL or not candidate.available \
			or typeof(candidate.compatible) != TYPE_BOOL or not candidate.compatible or not _minor(candidate.cost_cents):
			continue
		var cost: int = candidate.cost_cents
		var selected: Array = [candidate.id]
		var feasible := true
		for index: int in range(required.size()):
			var unit: String = required[index]
			if unit in candidate.coverage_ids:
				continue
			var split: int = unit.rfind(":")
			var id := unit.substr(0, split)
			var price: Variant = components.get(id, {}).get("unit_minor")
			if not _minor(price) or int(price) > MAX_MINOR - cost:
				feasible = false
				break
			cost += int(price)
			selected.append("individual-%03d" % index)
		if not feasible:
			continue
		selected.sort()
		if best_cost == null or cost < int(best_cost) or (cost == int(best_cost) and JSON.stringify(selected) < JSON.stringify(best)):
			best_cost = cost
			best = selected
	if best_cost == null:
		return _failure("The selected package and uncovered individual parts are not priced and eligible.")
	var request := _mode_request(context, labor_mode)
	request.transaction_id = "option-" + digest([context.identity, context.revision, labor_mode, package_id, best])
	request.purchase_mode = "explicit"
	request.selected_candidate_ids = best
	var prepared := prepare(request, dossier, assessment, recipe_book, context)
	if not prepared.get("ok", false):
		return prepared
	if prepared.receipt.purchase.total_cost_cents != best_cost:
		return _failure("Selected package arithmetic did not reconcile.")
	return prepared


static func prepare(request: Dictionary, dossier: Dictionary, current: Dictionary,
		recipe_book: Dictionary, context: Dictionary) -> Dictionary:
	if not context.get("identity") is Dictionary or not context.get("package_book") is Dictionary \
		or not context.get("labor_policy") is Dictionary or not _safe_tree(request) or not _safe_tree(current) \
		or not _safe_tree(dossier) or not _safe_tree(recipe_book) or not _safe_tree(context.identity) \
		or not _safe_tree(context.get("blocked", {})) or not _safe_tree(context.get("confirmed_replacements", {})) \
		or not _safe_tree(context.get("package_book")) \
		or not _safe_tree(context.get("labor_policy")) or not _keys(request, _REQUEST_KEYS) \
		or JSON.stringify(request).to_utf8_buffer().size() > MAX_REQUEST_BYTES:
		return _failure("Transaction has an invalid or unbounded schema.")
	if (context.has("blocked") and not context.blocked is Dictionary) \
		or (context.has("confirmed_replacements") and not context.confirmed_replacements is Dictionary):
		return _failure("Transaction restriction context is malformed.")
	if request.format != FORMAT or not _text(request.transaction_id, 128) \
		or not _keys(request.get("identity"), ["incident_id", "aircraft_id", "source_sha256"]) \
		or request.identity != context.get("identity") or request.identity.get("aircraft_id") != dossier.get("aircraft_id") \
		or request.identity.get("source_sha256") != dossier.get("source_sha256") \
		or not _text(request.identity.get("incident_id"), 128) \
		or typeof(request.expected_revision) != TYPE_INT or request.expected_revision < 0 \
		or request.expected_revision != context.get("revision"):
		return _failure("Transaction identity or expected incident revision does not match.")
	for field: String in ["catalog_hash", "profile_hash", "recipe_hash", "purchase_book_hash", "labor_policy_hash"]:
		if not _text(request.get(field), 128) or request[field] != context.get(field):
			return _failure("Transaction frozen source identity does not match: %s." % field)
	if digest(context.package_book) != request.purchase_book_hash or digest(context.labor_policy) != request.labor_policy_hash:
		return _failure("Frozen purchase book or labor policy digest does not match.")
	if request.labor_mode not in ["diy", "paid"] or request.costing_basis not in ["cash", "consumption"] \
		or request.purchase_mode not in ["optimal", "explicit"] or not request.repair_choices is Array \
		or request.repair_choices.size() > MAX_ACTIONS or not request.shared_labor_groups is Array \
		or request.shared_labor_groups.size() > MAX_ACTIONS or not request.selected_candidate_ids is Array \
		or request.selected_candidate_ids.size() > MAX_ACTIONS or not request.incurred_fees is Array \
		or request.incurred_fees.size() > MAX_ACTIONS or (request.purchase_mode == "optimal" and not request.selected_candidate_ids.is_empty()):
		return _failure("Transaction choices, mode or bounds are invalid.")
	if current.get("total_loss", false):
		return _failure("Total-loss comparison is not supported by this local transaction.")
	var original := Calculator.calculate(dossier, current)
	if not original.get("ok", false):
		return _failure("Current assessment is invalid: %s" % str(original.get("errors", [])))
	var candidate: Dictionary = current.duplicate(true)
	var selections: Array = []
	var selected_repair_ids: Dictionary = {}
	if request.repair_choices.is_empty():
		if request.repair_inspection != null or not request.shared_labor_groups.is_empty():
			return _failure("Repair inspection and shared groups require explicit repair choices.")
	else:
		if not request.repair_inspection is Dictionary or not request.repair_inspection.get("components") is Dictionary \
			or not context.get("blocked") is Dictionary or not context.get("confirmed_replacements") is Dictionary:
			return _failure("Explicit repairs require inspection and restriction evidence.")
		if not _keys(request.repair_inspection, ["format", "basis", "components"]):
			return _failure("Repair inspection contains unknown or missing fields.")
		for inspected: Variant in request.repair_inspection.components.values():
			if not _keys(inspected, ["status", "damage_class", "quantity", "replacement_comparable", "measurements", "labor_minutes", "evidence"]):
				return _failure("Repair inspection row contains unknown or missing fields.")
		var plan := RepairPlanner.plan(dossier, request.repair_inspection, recipe_book, request.labor_mode)
		if not plan.get("ok", false):
			return _failure("Repair plan is invalid: %s" % str(plan.get("errors", [])))
		for choice: Variant in request.repair_choices:
			if not choice is Dictionary or not _keys(choice, ["component_id", "option_id"]) \
				or not _text(choice.get("component_id"), 128) or not _text(choice.get("option_id"), 128) \
				or selected_repair_ids.has(choice.component_id) or not current.get("components", {}).has(choice.component_id):
				return _failure("Repair choices must name unique already-affected components.")
			var id: String = choice.component_id
			var prior: Dictionary = current.components[id]
			if prior.get("disposition") in ["replace", "unrecoverable"] or context.confirmed_replacements.has(id) \
				or context.blocked.get(id) == "replace_only":
				return _failure("Confirmed replacement or restriction cannot be downgraded to repair.")
			if context.blocked.get(id) == "repair_required" and plan.get("components", {}).get(id, {}).get("damage_class") != "structural":
				return _failure("A structural restriction requires an eligible structural repair.")
			var selection := RepairPlanner.select_option(plan, id, choice.option_id, request.costing_basis, true)
			if not selection.get("ok", false) or selection.get("decision", {}).get("disposition") != "repair":
				return _failure("Chosen repair is not a priced compatible repair: %s" % id)
			selected_repair_ids[id] = true
			selections.append(selection)
			var decision: Dictionary = selection.decision.duplicate(true)
			# Grouped cash cannot be compared row-by-row to a replacement price.
			decision.replacement_comparable = false
			for key: String in ["inspection_minor", "inspection_fee_id", "salvage_eligible"]:
				if prior.has(key):
					decision[key] = prior[key]
			candidate.components[id] = decision
		if request.repair_inspection.components.size() != selected_repair_ids.size():
			return _failure("Repair inspection scope must exactly match selected components.")
		for id: Variant in request.repair_inspection.components:
			if not selected_repair_ids.has(id):
				return _failure("Repair inspection includes an unselected component.")
	var fees: Array = candidate.get("incurred_fees", []).duplicate(true)
	for fee: Variant in request.incurred_fees:
		fees.append(fee.duplicate(true) if fee is Dictionary else fee)
	if not fees.is_empty():
		candidate["incurred_fees"] = fees
	var calculated := Calculator.calculate(dossier, candidate)
	if not calculated.get("ok", false):
		return _failure("Transaction fee or component accounting is invalid: %s" % str(calculated.get("errors", [])))
	var repair := {"component_ids": [], "selections": [], "aggregate": {}}
	var recipe_groups: Array = []
	var shared_setup: Dictionary = {}
	for group: Variant in request.shared_labor_groups:
		if group is Dictionary and group.get("scope") == "shared_setup_all_work":
			if not shared_setup.is_empty():
				return _failure("Only one shared setup may cover the combined work.")
			shared_setup = group
		else:
			recipe_groups.append(group)
	var actions := _action_snapshot(candidate)
	var default_work: Array = []
	for id: Variant in actions:
		if not selected_repair_ids.has(id):
			default_work.append(id)
	var mixed_work: bool = not selections.is_empty() and not default_work.is_empty()
	if mixed_work and int(context.labor_policy.get("shared_setup_minutes", 0)) > 0 and shared_setup.is_empty():
		return _failure("Mixed recipe and game-policy work needs explicit shared setup coverage.")
	if not shared_setup.is_empty():
		if not mixed_work or not _keys(shared_setup, ["id", "component_ids", "labor_minutes", "scope", "basis", "evidence"]) \
			or not _text(shared_setup.get("id"), 128) or not shared_setup.get("component_ids") is Array \
			or shared_setup.component_ids.size() != actions.size() or typeof(shared_setup.get("labor_minutes")) != TYPE_INT \
			or shared_setup.labor_minutes < 0 or shared_setup.labor_minutes > 60000 \
			or shared_setup.get("basis") not in ["inspection", "scenario_assumption"] \
			or not _text(shared_setup.get("evidence"), 2048):
			return _failure("Shared setup needs bounded evidence and the complete combined action scope.")
		var seen_setup: Dictionary = {}
		for id: Variant in shared_setup.component_ids:
			if not actions.has(id) or seen_setup.has(id):
				return _failure("Shared setup contains an unknown or duplicate action.")
			seen_setup[id] = true
		for group: Variant in recipe_groups:
			if group is Dictionary and group.get("scope") == "additional_setup":
				return _failure("Recipe setup cannot be charged again alongside the shared combined setup.")
	if not selections.is_empty():
		var aggregate := RepairPlanner.aggregate_selections(selections, recipe_groups, 0)
		if not aggregate.get("ok", false) or not aggregate.get("complete", false):
			return _failure("Selected repairs cannot be reconciled: %s" % str(aggregate.get("errors", [])))
		var ids: Array = selected_repair_ids.keys()
		ids.sort()
		selections.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.provenance.component_id) < String(b.provenance.component_id))
		repair = {"component_ids": ids, "selections": selections, "aggregate": aggregate}
	var adapted := package_candidates(context.package_book, dossier, candidate)
	if not adapted.get("ok", false):
		return adapted
	var purchase: Dictionary
	if request.purchase_mode == "optimal":
		purchase = ReplacementQuote.quote(dossier, candidate, adapted.candidates)
		if purchase.get("status") not in ["optimal", "no_replacements"]:
			return _failure("Automatic purchase is unresolved or its bounded search did not prove an optimum: %s." % str(purchase.get("status")))
	else:
		purchase = ReplacementQuote.quote_explicit(dossier, candidate, adapted.candidates, request.selected_candidate_ids)
		if purchase.get("status") != "selected":
			return _failure("Explicit purchase is not a priced eligible complete selection.")
	if purchase.get("selected_provenance_truncated", false):
		return _failure("Selected purchase provenance exceeds the receipt bound.")
	var selected_source_packages: Array = []
	for id: Variant in purchase.get("selected_candidate_ids", []):
		if adapted.candidate_package_ids.has(id):
			selected_source_packages.append({"candidate_id": id, "package_id": adapted.candidate_package_ids[id]})
	purchase["selected_source_packages"] = selected_source_packages
	purchase.erase("candidate_catalog")
	var labor := _policy_labor(context.labor_policy, dossier, candidate, selected_repair_ids, request.labor_mode, shared_setup)
	if not labor.get("ok", false):
		return labor
	var action_snapshot := _action_snapshot(candidate)
	var covered: Array = action_snapshot.keys()
	covered.sort()
	var receipt := {"format": RECEIPT_FORMAT, "transaction_id": request.transaction_id,
		"identity": request.identity.duplicate(true), "catalog_hash": request.catalog_hash,
		"profile_hash": request.profile_hash, "recipe_hash": request.recipe_hash,
		"purchase_book_hash": request.purchase_book_hash, "labor_policy_hash": request.labor_policy_hash,
		"candidate_catalog_hash": adapted.candidate_catalog_hash, "expected_revision": request.expected_revision,
		"request_digest": digest(request), "request": request.duplicate(true), "base_assessment": current.duplicate(true),
		"blocked_at_prepare": context.get("blocked", {}).duplicate(true),
		"confirmed_replacements_at_prepare": context.get("confirmed_replacements", {}).duplicate(true),
		"covered_component_ids": covered, "covered_decisions": action_snapshot,
		"repair": repair, "purchase": purchase, "policy_labor": labor,
		"financial_scope": "selected_estimate_not_realized_purchase"}
	receipt["receipt_digest"] = digest(receipt)
	if JSON.stringify(receipt).to_utf8_buffer().size() > MAX_RECEIPT_BYTES:
		return _failure("Transaction receipt exceeds its bounded snapshot size.")
	var report := reconcile(dossier, candidate, receipt)
	if not report.get("ok", false):
		return _failure("Prepared transaction did not reconcile: %s" % str(report.get("errors", [])))
	return {"ok": true, "errors": [], "assessment": candidate, "receipt": receipt, "report": report}


## Re-evaluate frozen inputs rather than trusting a stored digest as proof of
## arithmetic or compatibility. The checkpoint owner validates restriction
## history and binds the book, profile and incident independently.
static func verify_receipt(receipt: Variant, dossier: Dictionary, recipe_book: Dictionary, context: Dictionary) -> bool:
	if not receipt is Dictionary or not _safe_tree(receipt) or receipt.get("format") != RECEIPT_FORMAT \
		or not receipt.get("request") is Dictionary or not receipt.get("base_assessment") is Dictionary \
		or not receipt.get("blocked_at_prepare") is Dictionary or not receipt.get("confirmed_replacements_at_prepare") is Dictionary \
		or typeof(receipt.get("expected_revision")) != TYPE_INT:
		return false
	var historical: Dictionary = context.duplicate(true)
	historical["revision"] = receipt.expected_revision
	historical["blocked"] = receipt.blocked_at_prepare.duplicate(true)
	historical["confirmed_replacements"] = receipt.confirmed_replacements_at_prepare.duplicate(true)
	var prepared := prepare(receipt.request, dossier, receipt.base_assessment, recipe_book, historical)
	return prepared.get("ok", false) and prepared.get("receipt") == receipt


## Recompute the published bill from a frozen prepared plan and current facts.
## Untrusted restored receipts must first pass verify_receipt against the frozen
## context. If its action scope changed, refuse it so the caller can reprepare.
static func reconcile(dossier: Dictionary, assessment: Dictionary, receipt: Dictionary) -> Dictionary:
	if not _safe_tree(receipt) or not _safe_tree(dossier) or not _safe_tree(assessment) \
		or receipt.get("format") != RECEIPT_FORMAT or not receipt.get("receipt_digest") is String:
		return _failure("Cost receipt is malformed.")
	var frozen := receipt.duplicate(true)
	var expected: String = frozen.receipt_digest
	frozen.erase("receipt_digest")
	if digest(frozen) != expected or receipt.get("request_digest") != digest(receipt.get("request")) \
		or receipt.get("covered_decisions") != _action_snapshot(assessment) \
		or not receipt.get("purchase") is Dictionary or not receipt.get("repair") is Dictionary \
		or not receipt.get("policy_labor") is Dictionary:
		return _failure("Cost receipt digest or affected action scope no longer matches.")
	var original := Calculator.calculate(dossier, assessment)
	if not original.get("ok", false):
		return _failure("Current assessment is invalid.")
	var remainder: Dictionary = assessment.duplicate(true)
	# Suppress Calculator's empty-terminal fallback only when this transaction
	# is replacing actual assessed rows; an initially empty terminal scope stays pending.
	remainder["terminal"] = bool(assessment.get("terminal", false)) and assessment.get("components", {}).is_empty()
	var component_ids: Dictionary = {}
	for unit: Variant in receipt.purchase.get("required_unit_ids", []):
		if not unit is String or String(unit).rfind(":") <= 0:
			return _failure("Purchase requirement token is invalid.")
		component_ids[String(unit).substr(0, String(unit).rfind(":"))] = true
	for id: Variant in receipt.repair.get("component_ids", []):
		component_ids[id] = true
	var fees: Array = remainder.get("incurred_fees", []).duplicate(true)
	for id: Variant in component_ids:
		if not remainder.get("components", {}).has(id):
			return _failure("Selected component is missing from the assessment.")
		var decision: Dictionary = remainder.components[id]
		if decision.has("inspection_minor"):
			fees.append({"id": decision.get("inspection_fee_id", "component:%s:inspection" % id),
				"kind": "inspection", "amount_minor": decision.inspection_minor})
		remainder.components.erase(id)
	if not fees.is_empty():
		remainder["incurred_fees"] = fees
	var report := Calculator.calculate(dossier, remainder)
	if not report.get("ok", false):
		return _failure("Remaining incident charges do not reconcile: %s" % str(report.get("errors", [])))
	var added: Array = []
	var provenance: Dictionary = {}
	for row: Dictionary in receipt.purchase.get("selected_provenance", []):
		provenance[row.candidate_id] = row.provenance
	var coverage: Dictionary = {}
	for row: Dictionary in receipt.purchase.get("selected_coverage", []):
		coverage[row.candidate_id] = row
	var candidate_kinds: Dictionary = {}
	for row: Dictionary in receipt.purchase.get("selected_candidate_kinds", []):
		candidate_kinds[row.candidate_id] = row
	var source_packages: Dictionary = {}
	for row: Dictionary in receipt.purchase.get("selected_source_packages", []):
		if not _text(row.get("candidate_id"), 128) or not _text(row.get("package_id"), 128) or source_packages.has(row.candidate_id):
			return _failure("Selected source package identity is invalid.")
		source_packages[row.candidate_id] = row.package_id
	var components: Dictionary = {}
	for component: Dictionary in dossier.get("components", []):
		components[component.id] = component
	for row: Dictionary in receipt.purchase.get("selected_lines", []):
		if not _minor(row.get("cost_cents")) or not coverage.has(row.get("candidate_id")) or not candidate_kinds.has(row.get("candidate_id")):
			return _failure("Selected purchase line is invalid.")
		var allocation: Dictionary = coverage[row.candidate_id]
		var origin: Dictionary = candidate_kinds[row.candidate_id]
		var low: Variant = row.cost_cents
		var high: Variant = row.cost_cents
		var component_id := ""
		var package_id := ""
		var offer_id: Variant = null
		if origin.get("kind") == "dossier_individual_estimate":
			if not components.has(origin.get("component_id")) or row.coverage_ids != [origin.get("unit_id")]:
				return _failure("Individual estimate has an invalid component binding.")
			var component: Dictionary = components[origin.component_id]
			component_id = origin.component_id
			offer_id = component.get("offer_id")
			low = component.get("low_unit_minor") if component.get("low_unit_minor") != null else row.cost_cents
			high = component.get("high_unit_minor") if component.get("high_unit_minor") != null else row.cost_cents
		elif origin.get("kind") == "authored_package_candidate":
			if not source_packages.has(row.candidate_id):
				return _failure("Selected package has no frozen source identity.")
			package_id = source_packages[row.candidate_id]
		else:
			return _failure("Selected purchase provenance has an unknown candidate kind.")
		added.append({"id": _line_id("purchase", row.candidate_id), "label": component_id if not component_id.is_empty() else package_id,
			"action": "selected_purchase", "quantity": 1, "amount_minor": row.cost_cents,
			"component_id": component_id, "offer_id": offer_id, "package_id": package_id,
			"low_minor": low, "high_minor": high,
			"allocated_ids": allocation.allocated_ids.duplicate(), "overlap_ids": allocation.overlap_ids.duplicate(),
			"surplus_ids": allocation.surplus_ids.duplicate(), "provenance": provenance.get(row.candidate_id, ""),
			"price_basis": "frozen_declared_candidate"})
	var aggregate: Dictionary = receipt.repair.get("aggregate", {})
	for material: Dictionary in aggregate.get("materials", []):
		var amount: Variant = material.purchase_minor if aggregate.get("costing_basis") == "cash" else material.consumption_minor
		if not _minor(amount):
			return _failure("Selected repair material is not priced.")
		added.append({"id": _line_id("material", material.material_id), "label": material.material_id,
			"action": "repair_material", "quantity": material.package_count if aggregate.costing_basis == "cash" else material.required_units,
			"amount_minor": amount, "purchase_minor": material.purchase_minor, "consumption_minor": material.consumption_minor,
			"unit": material.unit, "source": material.source, "price_basis": "frozen_repair_recipe"})
	for work: Dictionary in aggregate.get("labor_groups", []):
		if not _minor(work.get("labor_minor")):
			return _failure("Selected repair labor is not priced.")
		added.append({"id": _line_id("repair-labor", work.id), "label": work.id,
			"action": "repair_labor", "quantity": 1, "amount_minor": work.labor_minor,
			"labor_minutes": work.labor_minutes, "labor_rate_minor_per_hour": work.labor_rate_minor_per_hour,
			"source": work.source, "price_basis": "frozen_repair_recipe"})
	for work: Dictionary in receipt.policy_labor.get("lines", []):
		added.append(work.duplicate(true))
	var used_ids: Dictionary = {}
	for line: Dictionary in report.lines:
		used_ids[line.get("id")] = true
	var sum := 0
	var low_sum := 0
	var high_sum := 0
	var high_known := true
	var unknown := false
	for line: Dictionary in added:
		if used_ids.has(line.id):
			return _failure("Selected cost line ID is ambiguous.")
		used_ids[line.id] = true
		if line.amount_minor == null:
			unknown = true
			high_known = false
		elif not _minor(line.amount_minor) or int(line.amount_minor) > MAX_MINOR - sum:
			return _failure("Selected cost total exceeds the supported range.")
		else:
			sum += int(line.amount_minor)
			var low: Variant = line.get("low_minor", line.amount_minor)
			var high: Variant = line.get("high_minor", line.amount_minor)
			if not _minor(low) or not _minor(high) or int(low) > int(line.amount_minor) or int(high) < int(line.amount_minor) or int(low) > MAX_MINOR - low_sum:
				return _failure("Selected cost price bounds are invalid.")
			low_sum += int(low)
			if int(high) > MAX_MINOR - high_sum:
				high_known = false
			else:
				high_sum += int(high)
			if low != high:
				report.range_reasons.append("%s: selected individual price bounds differ" % str(line.label))
	for field: String in ["known_subtotal_minor", "total_minor"]:
		if report.get(field) != null:
			if int(report[field]) > MAX_MINOR - sum:
				return _failure("Incident cost exceeds the supported range.")
			report[field] = int(report[field]) + sum
	if report.get("low_minor") != null:
		if int(report.low_minor) > MAX_MINOR - low_sum:
			return _failure("Incident lower bound exceeds the supported range.")
		report.low_minor = int(report.low_minor) + low_sum
	if report.get("high_minor") != null:
		if not high_known or int(report.high_minor) > MAX_MINOR - high_sum:
			report.high_minor = null
			report.range_reasons.append("Selected price upper bounds exceed the supported range or are unknown.")
		else:
			report.high_minor = int(report.high_minor) + high_sum
	if unknown:
		report["complete"] = false
		report["incident_complete"] = false
		report["total_minor"] = null
		report["high_minor"] = null
		for reason: String in receipt.policy_labor.get("unresolved", []):
			if not report.unresolved.has(reason):
				report.unresolved.append(reason)
			if not report.range_reasons.has(reason):
				report.range_reasons.append(reason)
	report.lines.append_array(added)
	report["outcome"] = original.outcome
	for field: String in ["replacement_quote_low_minor", "replacement_quote_high_minor", "replacement_quote_scope", "replacement_quote_includes"]:
		report[field] = original.get(field)
	if not receipt.purchase.get("required_unit_ids", []).is_empty():
		report["replacement_minor"] = receipt.purchase.get("total_cost_cents")
	report["selected_cost_plan"] = {"transaction_id": receipt.transaction_id,
		"receipt_digest": receipt.receipt_digest, "purchase_mode": receipt.request.purchase_mode,
		"labor_mode": receipt.request.labor_mode, "costing_basis": receipt.request.costing_basis,
		"financial_scope": receipt.financial_scope, "candidate_catalog_hash": receipt.candidate_catalog_hash}
	return report


static func _policy_labor(policy: Variant, dossier: Dictionary, assessment: Dictionary,
		selected_repairs: Dictionary, mode: String, shared_setup: Dictionary = {}) -> Dictionary:
	if not policy is Dictionary or not _keys(policy, _LABOR_KEYS) or policy.get("format") != LABOR_FORMAT \
		or policy.get("currency") != dossier.get("currency") or policy.get("basis") != "authored_game_policy" \
		or not _text(policy.get("evidence"), 2048) or not _minor(policy.get("paid_rate_minor_per_hour")) \
		or typeof(policy.get("shared_setup_minutes")) != TYPE_INT or policy.shared_setup_minutes < 0 \
		or policy.shared_setup_minutes > 60000 or not policy.get("minutes_by_component") is Dictionary \
		or policy.minutes_by_component.size() > 4096:
		return _failure("Frozen labor policy is invalid.")
	var known_components: Dictionary = {}
	for component: Dictionary in dossier.get("components", []):
		known_components[component.id] = true
	for id: Variant in policy.minutes_by_component:
		var minutes: Variant = policy.minutes_by_component[id]
		if not _text(id, 128) or not known_components.has(id) or typeof(minutes) != TYPE_INT or minutes < 0 or minutes > 60000:
			return _failure("Labor policy has invalid component minutes.")
	var work_ids: Array = []
	for id: Variant in assessment.get("components", {}):
		if assessment.components[id].get("disposition") in ["replace", "unrecoverable", "repair"] and not selected_repairs.has(id):
			work_ids.append(id)
	work_ids.sort()
	var rate: int = 0 if mode == "diy" else int(policy.paid_rate_minor_per_hour)
	var lines: Array = []
	var unresolved: Array = []
	for id: Variant in work_ids:
		var minutes: Variant = policy.minutes_by_component.get(id)
		var cost: Variant = _rate_amount(rate, int(minutes)) if minutes != null else null
		if minutes == null:
			unresolved.append("%s: authored labor time is unknown" % id)
		elif cost == null:
			return _failure("Labor amount exceeds the supported range.")
		lines.append({"id": _line_id("labor", id), "label": str(id), "action": "game_labor", "quantity": 1,
			"amount_minor": cost, "labor_minutes": minutes, "labor_rate_minor_per_hour": rate,
			"price_basis": "authored_game_policy", "provenance": policy.evidence})
	if not work_ids.is_empty():
		var setup_minutes: int = int(shared_setup.get("labor_minutes", policy.shared_setup_minutes))
		var setup: Variant = _rate_amount(rate, setup_minutes)
		if setup == null:
			return _failure("Shared setup labor exceeds the supported range.")
		lines.append({"id": _line_id("labor", "shared_setup"), "label": "shared_setup", "action": "game_labor",
			"quantity": 1, "amount_minor": setup, "labor_minutes": setup_minutes,
			"labor_rate_minor_per_hour": rate, "price_basis": "authored_game_policy",
			"provenance": shared_setup.get("evidence", policy.evidence), "scope": shared_setup.get("scope", "game_policy_work")})
	return {"ok": true, "errors": [], "mode": mode, "rounding_policy": "half_up_per_work_group",
		"lines": lines, "unresolved": unresolved}


static func _rate_amount(rate: int, minutes: int) -> Variant:
	var whole: int = rate / 60
	var remainder: int = rate % 60
	if minutes > 0 and whole > MAX_MINOR / minutes:
		return null
	var amount: int = whole * minutes
	var fractional: int = remainder * minutes
	var rounded: int = fractional / 60 + (1 if fractional % 60 >= 30 else 0)
	return null if rounded > MAX_MINOR - amount else amount + rounded


static func _action_snapshot(assessment: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var decisions: Variant = assessment.get("components", {})
	if not decisions is Dictionary:
		return result
	for id: Variant in decisions:
		if decisions[id] is Dictionary and decisions[id].get("disposition") in ["replace", "unrecoverable", "repair"]:
			result[id] = decisions[id].duplicate(true)
	return result


static func _line_id(kind: String, id: Variant) -> String:
	return "plan-%s-%s" % [kind, str(id).sha256_text().substr(0, 24)]


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "errors": [message], "assessment": {}, "receipt": {}, "report": {}}


static func _minor(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value >= 0 and value <= MAX_MINOR


static func _text(value: Variant, maximum: int) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.length() <= maximum and not value.contains("\n") and not value.contains("\r")


static func _keys(value: Variant, expected: Array) -> bool:
	if not value is Dictionary or value.size() != expected.size():
		return false
	for key: Variant in value:
		if key not in expected:
			return false
	return true


static func _safe_tree(value: Variant) -> bool:
	return _safe_node(value, 0, {"count": 0}, [])


static func _safe_node(value: Variant, depth: int, budget: Dictionary, ancestors: Array) -> bool:
	budget.count += 1
	if budget.count > 32768 or depth > 16:
		return false
	if value is Dictionary or value is Array:
		for ancestor: Variant in ancestors:
			if is_same(ancestor, value):
				return false
		ancestors.append(value)
		if value is Dictionary:
			for key: Variant in value:
				if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME] or String(key).length() > 2048 or not _safe_node(value[key], depth + 1, budget, ancestors):
					ancestors.pop_back()
					return false
		else:
			for entry: Variant in value:
				if not _safe_node(entry, depth + 1, budget, ancestors):
					ancestors.pop_back()
					return false
		ancestors.pop_back()
		return true
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT:
			return true
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_STRING, TYPE_STRING_NAME:
			return String(value).length() <= 4096
		_:
			return false

extends RefCounted
## Pure report archive codec. The digest detects changed payload bytes; it is
## not authentication, a market-price check, or a checkpoint for resuming.

const RepairDetails = preload("res://economy/repair_details.gd")
const RepairPlanner = preload("res://economy/repair_planner.gd")

const FORMAT := "openrc-accident-report-archive v1"
const MAX_PAYLOAD_BYTES := 262144
const MAX_ARCHIVE_BYTES := MAX_PAYLOAD_BYTES * 2 + 2048
const MAX_MINOR := 9000000000000000
const MAX_SAFE_INTEGER := 9007199254740991
const MAX_NODES := 65536
const MAX_DEPTH := 24
const MAX_ARRAY := 4096
const MAX_TEXT := 16384
const MAX_LINES := 384
const MAX_TEXT_ITEMS := 512
const REPORT_FIELDS := ["format", "ok", "errors", "currency", "known_subtotal_minor", "low_minor", "high_minor", "total_minor", "complete", "incident_complete", "incident_scope", "whole_build_complete", "whole_build_unresolved", "incurred_fees_minor", "incurred_fees_complete", "range_reasons", "valuation_kind", "outcome", "lines", "salvage_minor", "replacement_minor", "unresolved", "range_basis", "replacement_quote_low_minor", "replacement_quote_high_minor", "replacement_quote_scope", "replacement_quote_includes", "price_date", "assumptions", "game_assessment", "contact_summary", "journal_truncated", "contact_coverage_incomplete", "costing_available", "costing_mode", "costing_error", "purchase_package_id", "purchase_options", "cost_transactions", "quote_history", "quote_history_truncated", "active_cost_receipt", "cost_context", "inspections", "repair_choices", "replacement_comparison", "identity", "aircraft_name", "incident_id", "catalog_hash", "evidence", "confirmed_facts", "terminal", "tick", "revision", "selected_cost_plan", "individual_reference_subtotal_minor"]
const PRIVATE_FIELDS := ["package_book", "labor_policy", "recipe_book", "dossier", "candidate_catalog"]
const PLAN_FIELDS := ["transaction_id", "receipt_digest", "purchase_mode", "labor_mode", "costing_basis", "financial_scope", "candidate_catalog_hash"]
const RECEIPT_FIELDS := ["format", "transaction_id", "identity", "catalog_hash", "profile_hash", "recipe_hash", "purchase_book_hash", "labor_policy_hash", "candidate_catalog_hash", "expected_revision", "request_digest", "request", "base_assessment", "blocked_at_prepare", "confirmed_replacements_at_prepare", "covered_component_ids", "covered_decisions", "repair", "purchase", "policy_labor", "financial_scope", "receipt_digest"]
const REQUEST_FIELDS := ["format", "transaction_id", "identity", "catalog_hash", "profile_hash", "recipe_hash", "purchase_book_hash", "labor_policy_hash", "expected_revision", "repair_inspection", "repair_choices", "labor_mode", "costing_basis", "shared_labor_groups", "purchase_mode", "selected_candidate_ids", "incurred_fees"]
const ACTIONS := ["reuse", "unknown", "inspection", "repair", "replacement", "salvage_credit", "incurred_fee", "selected_purchase", "repair_material", "repair_labor", "game_labor"]


static func encode(report: Variant) -> Dictionary:
	if not report is Dictionary or not _safe_tree(report):
		return _encode_failure("Report is not bounded serializable data.")
	var payload := JSON.stringify(report, "", true, true)
	if payload.to_utf8_buffer().size() > MAX_PAYLOAD_BYTES:
		return _encode_failure("Report payload exceeds the byte limit.")
	var parsed: Variant = _parse_json(payload)
	var checked := validate_report(parsed, true, payload)
	if not checked.ok:
		return _encode_failure("Invalid current report: %s" % str(checked.errors))
	var envelope := {"format": FORMAT, "report_json": payload, "payload_sha256": payload.sha256_text()}
	var text := JSON.stringify(envelope, "", true, true)
	if text.to_utf8_buffer().size() > MAX_ARCHIVE_BYTES:
		return _encode_failure("Archive envelope exceeds the byte limit.")
	return {"ok": true, "errors": [], "text": text}


static func decode(text: Variant) -> Dictionary:
	if not text is String or text.to_utf8_buffer().size() > MAX_ARCHIVE_BYTES:
		return _decode_failure("Archive text is absent or exceeds the byte limit.")
	var value: Variant = _parse_json(text)
	if not value is Dictionary:
		return _decode_failure("Archive is not a JSON object.")
	if value.get("format") == FORMAT:
		if not _keys(value, ["format", "report_json", "payload_sha256"]) or not value.report_json is String \
			or value.report_json.to_utf8_buffer().size() > MAX_PAYLOAD_BYTES or not _hash(value.get("payload_sha256")) \
			or value.report_json.sha256_text() != value.payload_sha256:
			return _decode_failure("Archive envelope or exact payload digest is invalid.")
		var report: Variant = _parse_json(value.report_json)
		var checked := validate_report(report, true, value.report_json)
		if not checked.ok:
			return _decode_failure("Archived current report is invalid: %s" % str(checked.errors))
		return {"ok": true, "errors": [], "report": report, "legacy": false}
	if value.has("report_json") or value.has("payload_sha256"):
		return _decode_failure("Unsupported or malformed archive envelope.")
	if value.get("format") not in ["openrc-accident-report v1", "openrc-accident-report v2"] \
		or text.to_utf8_buffer().size() > MAX_PAYLOAD_BYTES:
		return _decode_failure("Unsupported archive format.")
	# Older raw reports are display-only. Do not expose unrelated embedded books.
	# Bound the complete input before duplicating or descending to remove private books.
	if not _safe_tree(value, true):
		return _decode_failure("Historical report exceeds structural bounds.")
	var legacy: Dictionary = value.duplicate(true)
	_strip_private(legacy)
	for key: Variant in legacy.keys():
		if key not in REPORT_FIELDS:
			legacy.erase(key)
	var checked := validate_report(legacy, false)
	if not checked.ok:
		return _decode_failure("Historical report is invalid: %s" % str(checked.errors))
	return {"ok": true, "errors": [], "report": legacy, "legacy": true}


static func validate_report(value: Variant, strict_current: bool = false, payload: String = "") -> Dictionary:
	if not value is Dictionary or not _safe_tree(value):
		return _validation_failure("Report is not bounded serializable data.")
	var report: Dictionary = value
	if report.get("format") not in ["openrc-accident-report v1", "openrc-accident-report v2"] \
		or not report.get("identity") is Dictionary or not report.get("lines") is Array \
		or report.lines.size() > MAX_LINES or not report.get("unresolved") is Array \
		or typeof(report.get("complete")) != TYPE_BOOL:
		return _validation_failure("Invalid report format, identity, lines or completeness.")
	if strict_current:
		if report.format != "openrc-accident-report v2":
			return _validation_failure("Current envelope requires a v2 report.")
		for key: Variant in report:
			if key not in REPORT_FIELDS:
				return _validation_failure("Current report contains an unknown field.")
		if not _identity(report.identity, bool(report.get("ok", false))) \
			or not _text(report.get("currency"), 8) or typeof(report.get("ok")) != TYPE_BOOL \
			or not _text(report.get("outcome"), 32) or not _nonnegative_int(report.get("revision"), MAX_SAFE_INTEGER) \
			or not _integer_between(report.get("tick"), -1, MAX_SAFE_INTEGER) or typeof(report.get("terminal")) != TYPE_BOOL:
			return _validation_failure("Current report identity or presentation metadata is invalid.")
		if report.get("incident_id") != report.identity.get("incident_id"):
			return _validation_failure("Report incident identity does not match.")
	if not _string_array(report.unresolved, MAX_TEXT_ITEMS, 2048):
		return _validation_failure("Unresolved items are malformed.")
	for field: String in ["errors", "assumptions", "range_reasons", "whole_build_unresolved"]:
		if report.has(field) and not _string_array(report[field], MAX_TEXT_ITEMS, 4096):
			return _validation_failure("Report text list is malformed: %s." % field)
	for field: String in ["journal_truncated", "contact_coverage_incomplete", "costing_available", "quote_history_truncated", "incident_complete", "whole_build_complete", "incurred_fees_complete"]:
		if report.has(field) and typeof(report[field]) != TYPE_BOOL:
			return _validation_failure("Report boolean is malformed: %s." % field)
	for field: String in ["known_subtotal_minor", "salvage_minor", "total_minor", "low_minor", "high_minor", "replacement_minor", "replacement_quote_low_minor", "replacement_quote_high_minor", "incurred_fees_minor", "individual_reference_subtotal_minor"]:
		if report.has(field) and report[field] != null and not _minor(report[field]):
			return _validation_failure("Report amount is invalid: %s." % field)
	if report.complete and report.get("total_minor") == null:
		return _validation_failure("A complete report needs a total.")
	if strict_current and (report.complete != (report.get("total_minor") != null) \
		or not _minor(report.get("known_subtotal_minor")) or (report.complete and report.total_minor != report.known_subtotal_minor)):
		return _validation_failure("Completeness, known subtotal and total do not agree.")
	if report.get("low_minor") != null and report.get("high_minor") != null and int(report.low_minor) > int(report.high_minor):
		return _validation_failure("Report price bounds are reversed.")
	if report.get("total_minor") != null and ((report.get("low_minor") != null and int(report.total_minor) < int(report.low_minor)) \
		or (report.get("high_minor") != null and int(report.total_minor) > int(report.high_minor))):
		return _validation_failure("Report total lies outside its stated price bounds.")
	var sum := 0
	var line_ids: Dictionary = {}
	var line_actions: Dictionary = {}
	for row: Variant in report.lines:
		if not row is Dictionary or not _valid_line(row, strict_current):
			return _validation_failure("Report contains an invalid line item.")
		if strict_current:
			var pair := "%s\u001f%s" % [row.id, row.action]
			if line_actions.has(pair) or (line_ids.has(row.id) and String(row.id).begins_with("plan-")):
				return _validation_failure("Report contains an ambiguous duplicate line.")
			line_actions[pair] = true
			line_ids[row.id] = row
			var amount: Variant = row.get("amount_minor")
			if amount == null and row.has("inspection_minor"):
				amount = row.inspection_minor
			if amount != null:
				if int(amount) > 0 and sum > MAX_MINOR - int(amount):
					return _validation_failure("Report line total exceeds the supported range.")
				sum += int(amount)
				if sum < -MAX_MINOR:
					return _validation_failure("Report line total is outside the supported range.")
	if strict_current and sum != int(report.known_subtotal_minor):
		return _validation_failure("Known subtotal does not equal its itemized lines.")
	if strict_current:
		var has_plan_lines := false
		for row: Dictionary in report.lines:
			if row.action in ["selected_purchase", "repair_material", "repair_labor", "game_labor"]:
				has_plan_lines = true
		if (has_plan_lines or (report.has("cost_context") and (not report.cost_context is Dictionary or not report.cost_context.is_empty()))) \
			and not report.has("selected_cost_plan"):
			return _validation_failure("Selected plan evidence is missing.")
		if report.has("costing_error") and not _text(report.costing_error, 4096, true):
			return _validation_failure("Costing error is not bounded text.")
		if report.get("costing_available") == true and report.ok == true \
			and (not report.has("costing_error") or (report.costing_error == "" and not report.has("selected_cost_plan"))):
			return _validation_failure("A successful costing result needs its selected receipt.")
		if report.get("costing_available") == true and report.complete and not report.has("selected_cost_plan"):
			return _validation_failure("An unavailable cost plan cannot certify a complete estimate.")
		if report.has("selected_cost_plan") and report.complete and report.get("incident_scope") == "assessed_components" \
			and report.get("range_basis") == "component_price_bounds" and not _complete_line_range(report.lines, report):
			return _validation_failure("Complete selected-plan bounds do not match their itemized prices.")
	if not _validate_optional_lists(report, strict_current):
		return _validation_failure("Report evidence or history is malformed.")
	if report.has("game_assessment") and not _validate_game(report.game_assessment):
		return _validation_failure("Game assessment or scoped outcomes are malformed.")
	if report.has("replacement_comparison") and not _validate_comparison(report.replacement_comparison, report.get("catalog_hash", "")):
		return _validation_failure("Replacement comparison is malformed.")
	if strict_current and report.has("selected_cost_plan") and not _validate_active_plan(report, line_ids):
		return _validation_failure("Selected plan, receipt and itemized charges do not reconcile.")
	if strict_current and report.has("active_cost_receipt") and not report.has("selected_cost_plan") \
		and (not report.active_cost_receipt is Dictionary or not report.active_cost_receipt.is_empty()):
		return _validation_failure("An active receipt has no selected plan.")
	if strict_current and not _raw_receipt_digests(payload if not payload.is_empty() else JSON.stringify(report, "", true, true), report):
		return _validation_failure("A saved transaction or request digest does not match its exact JSON bytes.")
	return {"ok": true, "errors": []}


static func _valid_line(row: Dictionary, strict: bool) -> bool:
	if strict and (not _text(row.get("id"), 128) or row.get("action") not in ACTIONS \
		or not row.has("amount_minor") or not _positive_int(row.get("quantity"), 1000000000)):
		return false
	if row.has("id") and not _text(row.id, 128):
		return false
	if row.has("action") and not _text(row.action, 32):
		return false
	if row.has("quantity") and not _positive_int(row.quantity, 1000000000):
		return false
	for field: String in ["amount_minor", "low_minor", "high_minor"]:
		if row.has(field) and row[field] != null and not _signed_minor(row[field]):
			return false
	for field: String in ["inspection_minor", "baseline_unit_minor", "offer_amount_minor", "purchase_minor", "consumption_minor", "labor_rate_minor_per_hour"]:
		if row.has(field) and row[field] != null and not _minor(row[field]):
			return false
	if row.has("labor_minutes") and row.labor_minutes != null and not _nonnegative_int(row.labor_minutes, 60000):
		return false
	if row.has("sold_package_quantity") and not _positive_int(row.sold_package_quantity, 1000000):
		return false
	if row.has("reused_quantity") and not _nonnegative_int(row.reused_quantity, 1000000):
		return false
	if row.has("replacement_comparable") and typeof(row.replacement_comparable) != TYPE_BOOL:
		return false
	if row.has("offer_id") and row.offer_id != null and not _text(row.offer_id, 2048):
		return false
	for field: String in ["label", "component_id", "package_id", "price_basis", "condition", "credit_basis", "fee_kind", "unit", "scope", "notes", "provenance", "game_scope_note", "source_url", "observed_on", "seller_domain", "availability", "price_kind", "product_name", "product_brand", "product_sku", "package_description"]:
		if row.has(field) and not _text(row[field], 4096, true):
			return false
	if row.has("source") and not _source(row.source):
		return false
	if row.has("allocated_ids") or row.has("overlap_ids") or row.has("surplus_ids"):
		var used := {}
		for field: String in ["allocated_ids", "overlap_ids", "surplus_ids"]:
			if not _unique_strings(row.get(field), 64, 132):
				return false
			for id: String in row[field]:
				if used.has(id):
					return false
				used[id] = true
	if row.get("amount_minor") != null:
		var amount: int = int(row.amount_minor)
		if (amount < 0 and row.get("action") != "salvage_credit") or (amount > 0 and row.get("action") == "salvage_credit"):
			return false
		if row.get("low_minor") != null and int(row.low_minor) > amount:
			return false
		if row.get("high_minor") != null and int(row.high_minor) < amount:
			return false
	if strict and row.get("action") == "selected_purchase":
		if not _minor(row.get("amount_minor")) or not _text(row.get("provenance"), 2048) \
			or not row.has_all(["allocated_ids", "overlap_ids", "surplus_ids", "component_id", "package_id"]):
			return false
		if (str(row.component_id).is_empty()) == (str(row.package_id).is_empty()):
			return false
		if row.get("offer_id") != null and (not _text(row.get("source_url"), 2048) or not _text(row.get("observed_on"), 128)):
			return false
	if strict and row.get("action") in ["repair_material", "repair_labor"] and not _source(row.get("source")):
		return false
	if strict and row.get("action") == "game_labor" and (not _text(row.get("provenance"), 2048) or row.get("price_basis") != "authored_game_policy"):
		return false
	return true


static func _validate_optional_lists(report: Dictionary, strict: bool) -> bool:
	if report.has("evidence"):
		if not report.evidence is Array or report.evidence.size() > 128:
			return false
		for entry: Variant in report.evidence:
			if not entry is Dictionary or not _text(entry.get("format"), 128) or not _text(entry.get("event_id"), 2048):
				return false
	if report.has("contact_summary") and not _summary_map(report.contact_summary):
		return false
	if report.has("confirmed_facts") and not report.confirmed_facts is Dictionary:
		return false
	if report.has("purchase_options"):
		if not report.purchase_options is Array or report.purchase_options.size() > 8:
			return false
		var ids := {}
		for option: Variant in report.purchase_options:
			if not option is Dictionary or not _keys(option, ["id", "label", "total_minor"]) \
				or not _text(option.get("id"), 128, true) or ids.has(option.id) \
				or not _text(option.get("label"), 2048) or (option.total_minor != null and not _minor(option.total_minor)):
				return false
			ids[option.id] = true
	for field: String in ["inspections", "repair_choices"]:
		if not report.has(field):
			continue
		if not report[field] is Array or report[field].size() > 16:
			return false
		for entry: Variant in report[field]:
			if not entry is Dictionary or not _text(entry.get("inspection_id"), 128):
				return false
			if field == "inspections":
				if entry.get("format") != "openrc-accident-inspection v1" or not entry.get("components") is Dictionary \
					or entry.get("basis") not in ["inspection", "scenario_assumption"] or not _text(entry.get("evidence"), 2048):
					return false
				for id: Variant in entry.components:
					if not _text(id, 128) or not _valid_decision(entry.components[id], true):
						return false
			elif not entry.get("provenance") is Dictionary or not _text(entry.get("recipe_book_sha256"), 128) \
				or entry.get("labor_mode") not in ["diy", "paid"] or entry.get("costing_basis") not in ["cash", "consumption"]:
				return false
	for field: String in ["cost_transactions", "quote_history"]:
		if not report.has(field):
			continue
		if not report[field] is Array or report[field].size() > (16 if field == "cost_transactions" else 8):
			return false
		var seen := {}
		for entry: Variant in report[field]:
			if not entry is Dictionary or not _text(entry.get("transaction_id"), 128) or seen.has(entry.transaction_id):
				return false
			seen[entry.transaction_id] = true
			if strict and (not _valid_receipt(entry) or entry.identity != report.identity or entry.catalog_hash != report.get("catalog_hash")):
				return false
	return true


static func _summary_map(value: Variant) -> bool:
	if not value is Dictionary or value.size() > 4096:
		return false
	for id: Variant in value:
		var row: Variant = value[id]
		if not _text(id, 128) or not row is Dictionary \
			or not _keys(row, ["first_tick", "latest_tick", "evidence_revision", "recommendation", "reason", "event_id", "source", "peaks"]) \
			or not _nonnegative_int(row.first_tick, MAX_SAFE_INTEGER) or not _nonnegative_int(row.latest_tick, MAX_SAFE_INTEGER) \
			or int(row.first_tick) > int(row.latest_tick) or not _nonnegative_int(row.evidence_revision, MAX_SAFE_INTEGER) \
			or row.recommendation not in ["clear", "scope_clear", "inspect", "repair", "replace"] \
			or not _text(row.reason, 2048, true) or not _text(row.event_id, 2048, true) \
			or not _text(row.source, 32, true) or not row.peaks is Dictionary:
			return false
		for channel: Variant in row.peaks:
			if not _text(channel, 128) or typeof(row.peaks[channel]) not in [TYPE_INT, TYPE_FLOAT] \
				or not is_finite(float(row.peaks[channel])) or float(row.peaks[channel]) < 0.0:
				return false
	return true


static func _validate_game(value: Variant) -> bool:
	if not value is Dictionary or value.get("format") != "openrc-game-assessment v1" \
		or value.get("basis") != "scenario_assumption" or not _text(value.get("profile_id"), 256) \
		or not _text(value.get("policy_version"), 128) or not _hash(value.get("profile_sha256")) \
		or not _summary_map(value.get("components")):
		return false
	if value.has("current_outcomes"):
		if not value.current_outcomes is Dictionary or value.current_outcomes.size() > 4096:
			return false
		for id: Variant in value.current_outcomes:
			var outcome: Variant = value.current_outcomes[id]
			if not _text(id, 128) or not outcome is Dictionary \
				or not _keys(outcome, ["action", "reason", "service_minor", "quantity_scope", "basis"]) \
				or outcome.action not in ["scope_clear", "repair", "replace"] \
				or not _text(outcome.reason, 4096, true) or not _text(outcome.quantity_scope, 2048) \
				or outcome.basis != "scenario_assumption" or (outcome.service_minor != null and not _minor(outcome.service_minor)):
				return false
	if value.has("scoped_receipts"):
		if not value.scoped_receipts is Array or value.scoped_receipts.size() > 128:
			return false
		for receipt: Variant in value.scoped_receipts:
			if not receipt is Dictionary or not _keys(receipt, ["format", "component_id", "evidence_revision", "observations", "action", "service_minor", "basis", "profile_sha256", "policy_version", "floor_receipt_id", "service_basis", "receipt_id"]) \
				or receipt.format != "openrc-game-scope-receipt v1" or not _text(receipt.component_id, 128) \
				or not _positive_int(receipt.evidence_revision, MAX_SAFE_INTEGER) or not receipt.observations is Array \
				or receipt.observations.is_empty() or receipt.observations.size() > 16 \
				or receipt.action not in ["scope_clear", "repair", "replace"] or receipt.basis != "scenario_assumption" \
				or receipt.profile_sha256 != value.profile_sha256 or not _hash(receipt.receipt_id) \
				or not _text(receipt.policy_version, 128) or not _text(receipt.floor_receipt_id, 128, true) \
				or not _text(receipt.service_basis, 2048) or (receipt.service_minor != null and not _minor(receipt.service_minor)):
				return false
			for observation: Variant in receipt.observations:
				if not observation is Dictionary or not observation.get("event") is Dictionary \
					or observation.get("action") not in ["scope_clear", "repair", "replace"]:
					return false
	return true


static func _valid_decision(value: Variant, inspection: bool = false) -> bool:
	if not value is Dictionary or value.get("disposition") not in ["reuse", "replace", "repair", "inspect", "unknown", "unrecoverable"]:
		return false
	var allowed := ["disposition", "quantity", "repair_minor", "inspection_minor", "inspection_fee_id", "replacement_comparable", "salvage_eligible"]
	if inspection:
		allowed.append_array(["evidence", "damage_flags"])
	for key: Variant in value:
		if key not in allowed:
			return false
	if value.has("quantity") and not _positive_int(value.quantity, 1000000):
		return false
	for field: String in ["repair_minor", "inspection_minor"]:
		if value.has(field) and not _minor(value[field]):
			return false
	if value.has("inspection_fee_id") and not _text(value.inspection_fee_id, 128):
		return false
	for field: String in ["replacement_comparable", "salvage_eligible"]:
		if value.has(field) and typeof(value[field]) != TYPE_BOOL:
			return false
	if inspection and (not _text(value.get("evidence"), 2048) or not _unique_strings(value.get("damage_flags"), 5, 128)):
		return false
	return true


static func _valid_assessment(value: Variant) -> bool:
	if not value is Dictionary or not value.get("components") is Dictionary or value.components.size() > 4096 \
		or typeof(value.get("terminal")) != TYPE_BOOL or typeof(value.get("total_loss")) != TYPE_BOOL \
		or not _string_array(value.get("unresolved"), 4096, 2048):
		return false
	for key: Variant in value:
		if key not in ["components", "terminal", "total_loss", "unresolved", "incurred_fees", "complete_build_replacement_feasible"]:
			return false
	for id: Variant in value.components:
		if not _text(id, 128) or not _valid_decision(value.components[id]):
			return false
	if value.has("complete_build_replacement_feasible") and typeof(value.complete_build_replacement_feasible) != TYPE_BOOL:
		return false
	return not value.has("incurred_fees") or _valid_fees(value.incurred_fees)


static func _valid_fees(value: Variant) -> bool:
	if not value is Array or value.size() > 64:
		return false
	var seen := {}
	for fee: Variant in value:
		if not fee is Dictionary or not _keys(fee, ["id", "kind", "amount_minor"]) \
			or not _text(fee.id, 128) or seen.has(fee.id) or fee.kind not in ["inspection", "retrieval", "setup", "other"] \
			or (fee.amount_minor != null and not _minor(fee.amount_minor)):
			return false
		seen[fee.id] = true
	return true


static func _validate_comparison(value: Variant, catalog_hash: Variant) -> bool:
	if not value is Dictionary or value.get("format") not in ["openrc-replacement-comparison v1", "openrc-replacement-comparison v2", "openrc-replacement-comparison v3"] \
		or value.get("catalog_hash") != catalog_hash or value.get("coverage_scope") != "replacements_only":
		return false
	return _valid_purchase(value, false, value.format == "openrc-replacement-comparison v1")


static func _valid_purchase(value: Variant, receipt: bool, legacy: bool = false) -> bool:
	if not value is Dictionary or value.get("status") not in (["optimal", "selected", "no_replacements"] if receipt else ["optimal", "unknown_cost", "unknown_eligibility", "search_limit", "infeasible", "cost_out_of_range"]):
		return false
	for field: String in ["assessment_complete", "complete", "optimality_proven", "search_complete", "unknown_cost_alternative_found", "selected_provenance_truncated"]:
		if typeof(value.get(field)) != TYPE_BOOL:
			return false
	if value.has("unknown_eligibility_alternative_found") and typeof(value.unknown_eligibility_alternative_found) != TYPE_BOOL:
		return false
	if not _unique_strings(value.get("required_unit_ids"), 64, 132) or not _unique_strings(value.get("selected_candidate_ids"), 64, 128) \
		or not value.get("selected_provenance") is Array or value.selected_provenance.size() != value.selected_candidate_ids.size() \
		or (value.get("total_cost_cents") != null and not _minor(value.total_cost_cents)):
		return false
	var provenance := {}
	for row: Variant in value.selected_provenance:
		if not row is Dictionary or not _keys(row, ["candidate_id", "provenance"]) \
			or row.candidate_id not in value.selected_candidate_ids or provenance.has(row.candidate_id) or not _text(row.provenance, 2048):
			return false
		provenance[row.candidate_id] = true
	if receipt and value.get("selected_provenance_truncated"):
		return false
	if value.status == "no_replacements":
		return receipt and value.required_unit_ids.is_empty() and value.selected_candidate_ids.is_empty() and value.total_cost_cents == 0 \
			and value.get("selected_lines", []) == [] and value.get("selected_coverage", []) == []
	if value.optimality_proven != (value.status == "optimal") \
		or (value.optimality_proven and (value.total_cost_cents == null or not value.search_complete)):
		return false
	if not receipt and value.complete != (value.assessment_complete and value.optimality_proven):
		return false
	if value.status == "selected" and (not receipt or value.get("optimality_scope") != "explicit_selection" or not value.search_complete):
		return false
	if value.status == "optimal" and (value.unknown_cost_alternative_found or value.get("unknown_eligibility_alternative_found", false)):
		return false
	if value.status == "unknown_cost" and not value.unknown_cost_alternative_found:
		return false
	if value.status == "unknown_eligibility" and not value.get("unknown_eligibility_alternative_found", false):
		return false
	if value.status == "search_limit" and value.search_complete:
		return false
	if legacy:
		return true
	if not value.get("selected_lines") is Array or value.selected_lines.size() != value.selected_candidate_ids.size():
		return false
	if value.selected_lines.is_empty():
		return not receipt and value.total_cost_cents == null and value.status != "optimal"
	if value.total_cost_cents == null:
		return false
	var lines := {}
	var total := 0
	for row: Variant in value.selected_lines:
		if not row is Dictionary or not _keys(row, ["candidate_id", "coverage_ids", "cost_cents"]) \
			or row.candidate_id not in value.selected_candidate_ids or lines.has(row.candidate_id) \
			or not _unique_strings(row.coverage_ids, 64, 132) or row.coverage_ids.is_empty() \
			or not _minor(row.cost_cents) or int(row.cost_cents) > MAX_MINOR - total:
			return false
		total += int(row.cost_cents)
		lines[row.candidate_id] = row
	if total != int(value.total_cost_cents):
		return false
	if not value.has("selected_coverage"):
		# Historical v2 comparisons had exact disjoint cover only.
		var covered := {}
		for row: Dictionary in value.selected_lines:
			for unit: String in row.coverage_ids:
				if unit not in value.required_unit_ids or covered.has(unit):
					return false
				covered[unit] = true
		return not receipt and covered.size() == value.required_unit_ids.size()
	if not value.selected_coverage is Array or value.selected_coverage.size() != lines.size():
		return false
	var coverage := {}
	for row: Variant in value.selected_coverage:
		if not row is Dictionary or not _keys(row, ["candidate_id", "allocated_ids", "overlap_ids", "surplus_ids"]) \
			or not lines.has(row.candidate_id) or coverage.has(row.candidate_id):
			return false
		coverage[row.candidate_id] = row
	var ids: Array = value.selected_candidate_ids.duplicate()
	ids.sort()
	var assigned := {}
	for id: String in ids:
		var row: Dictionary = coverage.get(id, {})
		var supplied := {}
		for field: String in ["allocated_ids", "overlap_ids", "surplus_ids"]:
			if not _unique_strings(row.get(field), 64, 132):
				return false
			for unit: String in row[field]:
				if supplied.has(unit):
					return false
				supplied[unit] = true
				if field == "surplus_ids":
					if unit in value.required_unit_ids:
						return false
				elif unit not in value.required_unit_ids or (field == "allocated_ids" and assigned.has(unit)) \
					or (field == "overlap_ids" and not assigned.has(unit)):
					return false
				elif field == "allocated_ids":
					assigned[unit] = true
		var required_supplied: Array = row.allocated_ids + row.overlap_ids
		required_supplied.sort()
		var line_units: Array = lines[id].coverage_ids.duplicate()
		line_units.sort()
		if required_supplied != line_units:
			return false
	return assigned.size() == value.required_unit_ids.size()


static func _valid_receipt(receipt: Variant) -> bool:
	if not receipt is Dictionary or not _keys(receipt, RECEIPT_FIELDS) \
		or receipt.format != "openrc-cost-transaction-receipt v1" or not _text(receipt.transaction_id, 128) \
		or not _identity(receipt.identity, true) or not _nonnegative_int(receipt.expected_revision, MAX_SAFE_INTEGER) \
		or receipt.financial_scope != "selected_estimate_not_realized_purchase" \
		or not _valid_assessment(receipt.base_assessment) \
		or not _unique_strings(receipt.covered_component_ids, 64, 128) \
		or not receipt.covered_decisions is Dictionary or receipt.covered_decisions.size() != receipt.covered_component_ids.size():
		return false
	for field: String in ["catalog_hash", "profile_hash", "recipe_hash", "purchase_book_hash", "labor_policy_hash", "candidate_catalog_hash", "request_digest", "receipt_digest"]:
		if not _hash(receipt[field]):
			return false
	for id: String in receipt.covered_component_ids:
		if not receipt.covered_decisions.has(id) or not _valid_decision(receipt.covered_decisions[id]) \
			or receipt.covered_decisions[id].disposition not in ["repair", "replace", "unrecoverable"]:
			return false
	for field: String in ["blocked_at_prepare", "confirmed_replacements_at_prepare"]:
		if not receipt[field] is Dictionary or receipt[field].size() > 4096:
			return false
		for id: Variant in receipt[field]:
			if not _text(id, 128):
				return false
			if field == "blocked_at_prepare" and receipt[field][id] not in ["repair_required", "replace_only"]:
				return false
			if field == "confirmed_replacements_at_prepare" and receipt[field][id] != true:
				return false
	var request: Variant = receipt.request
	if not request is Dictionary or not _keys(request, REQUEST_FIELDS) or request.format != "openrc-cost-transaction v1" \
		or request.transaction_id != receipt.transaction_id or request.identity != receipt.identity \
		or request.expected_revision != receipt.expected_revision or request.labor_mode not in ["diy", "paid"] \
		or request.costing_basis not in ["cash", "consumption"] or request.purchase_mode not in ["optimal", "explicit"] \
		or not _unique_strings(request.selected_candidate_ids, 64, 128) or not _valid_fees(request.incurred_fees) \
		or not request.repair_choices is Array or request.repair_choices.size() > 64 \
		or not request.shared_labor_groups is Array or request.shared_labor_groups.size() > 64:
		return false
	for field: String in ["catalog_hash", "profile_hash", "recipe_hash", "purchase_book_hash", "labor_policy_hash"]:
		if request[field] != receipt[field]:
			return false
	var choices := {}
	for choice: Variant in request.repair_choices:
		if not choice is Dictionary or not _keys(choice, ["component_id", "option_id"]) \
			or not _text(choice.component_id, 128) or choices.has(choice.component_id) or not _text(choice.option_id, 128):
			return false
		choices[choice.component_id] = true
	if choices.is_empty():
		if request.repair_inspection != null or not request.shared_labor_groups.is_empty():
			return false
	else:
		if not request.repair_inspection is Dictionary or not _keys(request.repair_inspection, ["format", "basis", "components"]) \
			or request.repair_inspection.format != "openrc-repair-inspection v1" \
			or request.repair_inspection.basis not in ["inspection", "scenario_assumption"] \
			or not request.repair_inspection.components is Dictionary or request.repair_inspection.components.size() != choices.size():
			return false
		for id: Variant in request.repair_inspection.components:
			var row: Variant = request.repair_inspection.components[id]
			if not choices.has(id) or not row is Dictionary or not _keys(row, ["status", "damage_class", "quantity", "replacement_comparable", "measurements", "labor_minutes", "evidence"]) \
				or row.status != "inspected" or row.damage_class not in ["covering_only", "structural", "unknown"] \
				or not _positive_int(row.quantity, 1000000) or typeof(row.replacement_comparable) != TYPE_BOOL \
				or not row.measurements is Dictionary or not _nonnegative_int(row.labor_minutes, 60000) or not _text(row.evidence, 2048):
				return false
			for key: Variant in row.measurements:
				if not _text(key, 128) or not _nonnegative_int(row.measurements[key], 1000000000):
					return false
	if not _valid_purchase(receipt.purchase, true) or not _valid_purchase_origins(receipt.purchase) \
		or not _valid_repair(receipt.repair, request) or not _valid_policy_labor(receipt.policy_labor, request.labor_mode):
		return false
	if request.purchase_mode == "optimal" and receipt.purchase.status not in ["optimal", "no_replacements"]:
		return false
	if request.purchase_mode == "explicit" and (receipt.purchase.status != "selected" or request.selected_candidate_ids != receipt.purchase.selected_candidate_ids):
		return false
	return true


static func _valid_purchase_origins(purchase: Dictionary) -> bool:
	if not purchase.get("selected_candidate_kinds") is Array or not purchase.get("selected_source_packages") is Array \
		or purchase.selected_candidate_kinds.size() != purchase.selected_candidate_ids.size():
		return false
	var kinds := {}
	for row: Variant in purchase.selected_candidate_kinds:
		if not row is Dictionary or row.get("candidate_id") not in purchase.selected_candidate_ids or kinds.has(row.get("candidate_id")):
			return false
		if row.get("kind") == "dossier_individual_estimate":
			if not _keys(row, ["candidate_id", "kind", "component_id", "unit_id"]) \
				or not _text(row.component_id, 128) or not _text(row.unit_id, 132):
				return false
		elif row.get("kind") == "authored_package_candidate":
			if not _keys(row, ["candidate_id", "kind"]):
				return false
		else:
			return false
		kinds[row.candidate_id] = row
	var packages := {}
	for row: Variant in purchase.selected_source_packages:
		if not row is Dictionary or not _keys(row, ["candidate_id", "package_id"]) \
			or not kinds.has(row.candidate_id) or kinds[row.candidate_id].kind != "authored_package_candidate" \
			or packages.has(row.candidate_id) or not _text(row.package_id, 128):
			return false
		packages[row.candidate_id] = true
	for id: Variant in kinds:
		if kinds[id].kind == "authored_package_candidate" and not packages.has(id):
			return false
	return true


static func _valid_policy_labor(value: Variant, mode: String) -> bool:
	if not value is Dictionary or value.get("ok") != true or value.get("mode") != mode \
		or value.get("rounding_policy") != "half_up_per_work_group" \
		or not value.get("lines") is Array or value.lines.size() > 65 \
		or not _string_array(value.get("unresolved"), 64, 2048):
		return false
	var ids := {}
	for row: Variant in value.lines:
		if not row is Dictionary or not _valid_line(row, true) or row.action != "game_labor" or ids.has(row.id) \
			or not _minor(row.get("labor_rate_minor_per_hour")) or (mode == "diy" and row.labor_rate_minor_per_hour != 0):
			return false
		ids[row.id] = true
		if row.get("labor_minutes") == null:
			if row.get("amount_minor") != null or value.unresolved.is_empty():
				return false
		else:
			var expected: Variant = _mul_div(int(row.labor_rate_minor_per_hour), int(row.labor_minutes), 60, false)
			if expected == null or row.get("amount_minor") != expected:
				return false
	return true


static func _valid_repair(value: Variant, request: Dictionary) -> bool:
	if not value is Dictionary or not _keys(value, ["component_ids", "selections", "aggregate"]) \
		or not _unique_strings(value.component_ids, 64, 128) or not value.selections is Array \
		or value.selections.size() != value.component_ids.size() or not value.aggregate is Dictionary:
		return false
	if value.component_ids.is_empty():
		return value.selections.is_empty() and value.aggregate.is_empty() and request.repair_choices.is_empty()
	if value.component_ids.size() != request.repair_choices.size():
		return false
	var selected := {}
	for choice: Dictionary in request.repair_choices:
		selected[choice.component_id] = choice.option_id
	for selection: Variant in value.selections:
		if not selection is Dictionary or selection.get("ok") != true or not selection.get("decision") is Dictionary \
			or not selection.get("provenance") is Dictionary or selection.get("labor_mode") != request.labor_mode \
			or selection.get("costing_basis") != request.costing_basis:
			return false
		var provenance: Dictionary = selection.provenance
		var component: Variant = provenance.get("component_id")
		if not selected.has(component) or provenance.get("recipe_id") != selected[component] \
			or selection.decision.get("disposition") != "repair" or not _positive_int(selection.decision.get("quantity"), 1000000) \
			or not _minor(selection.decision.get("repair_minor")) or selection.decision.repair_minor != provenance.get("repair_minor"):
			return false
		var normalized: Dictionary = RepairDetails._normalize_materials(provenance, request.costing_basis)
		if not normalized.has("materials") or int(normalized.selected_material_minor) > MAX_MINOR - int(normalized.labor_minor) \
			or int(normalized.selected_material_minor) + int(normalized.labor_minor) != int(selection.decision.repair_minor):
			return false
		selected.erase(component)
	if not selected.is_empty():
		return false
	var aggregate: Dictionary = value.aggregate
	# Reconcile grouped material and labor against the saved selections and
	# evidenced group scopes, without consulting any current recipe book.
	var recipe_groups := []
	for group: Variant in request.shared_labor_groups:
		if not group is Dictionary:
			return false
		if group.get("scope") != "shared_setup_all_work":
			recipe_groups.append(group)
	var recomputed := RepairPlanner.aggregate_selections(_semantic_integers(value.selections), _semantic_integers(recipe_groups), 0)
	if not recomputed.get("ok", false) or recomputed != _semantic_integers(aggregate):
		return false
	if aggregate.get("ok") != true or aggregate.get("complete") != true or aggregate.get("costing_basis") != request.costing_basis \
		or aggregate.get("labor_mode") != request.labor_mode or aggregate.get("rounding_policy") != "v1_ceiling_per_material_and_labor_group" \
		or not aggregate.get("materials") is Array or aggregate.materials.size() > 4096 \
		or not aggregate.get("labor_groups") is Array or aggregate.labor_groups.size() > 128 \
		or aggregate.get("incurred_fees_minor") != 0:
		return false
	var cash := 0
	var consumed := 0
	var material_ids := {}
	for row: Variant in aggregate.materials:
		if not row is Dictionary or not _text(row.get("material_id"), 128) or material_ids.has(row.material_id) \
			or not _text(row.get("unit"), 64) or not _positive_int(row.get("required_units"), 1000000000) \
			or not _positive_int(row.get("package_units"), 1000000000) or not _minor(row.get("package_price_minor")) \
			or not _positive_int(row.get("package_count"), 1000000000) or not _minor(row.get("purchase_minor")) \
			or not _minor(row.get("consumption_minor")) or not _source(row.get("source")):
			return false
		material_ids[row.material_id] = true
		var count: int = (int(row.required_units) + int(row.package_units) - 1) / int(row.package_units)
		var price: int = int(row.package_price_minor)
		var used: Variant = _mul_div(price, int(row.required_units), int(row.package_units), true)
		if count != int(row.package_count) or (count > 0 and price > MAX_MINOR / count) or price * count != int(row.purchase_minor) \
			or used == null or used != row.consumption_minor or int(row.purchase_minor) > MAX_MINOR - cash \
			or int(row.consumption_minor) > MAX_MINOR - consumed:
			return false
		cash += int(row.purchase_minor)
		consumed += int(row.consumption_minor)
	var labor := 0
	var labor_ids := {}
	for row: Variant in aggregate.labor_groups:
		if not row is Dictionary or not _text(row.get("id"), 256) or labor_ids.has(row.id) \
			or not _unique_strings(row.get("component_ids"), 64, 128) or row.component_ids.is_empty() \
			or not _nonnegative_int(row.get("labor_minutes"), 60000) or not _minor(row.get("labor_rate_minor_per_hour")) \
			or not _minor(row.get("labor_minor")) or not _source(row.get("source")):
			return false
		labor_ids[row.id] = true
		for id: String in row.component_ids:
			if id not in value.component_ids:
				return false
		var amount: Variant = _mul_div(int(row.labor_rate_minor_per_hour), int(row.labor_minutes), 60, true)
		if amount == null or amount != row.labor_minor or int(amount) > MAX_MINOR - labor:
			return false
		labor += int(amount)
	if cash > MAX_MINOR - labor or consumed > MAX_MINOR - labor:
		return false
	return aggregate.get("material_purchase_minor") == cash and aggregate.get("material_consumption_minor") == consumed \
		and aggregate.get("labor_minor") == labor and aggregate.get("cash_total_minor") == cash + labor \
		and aggregate.get("consumption_total_minor") == consumed + labor \
		and aggregate.get("total_minor") == (cash + labor if request.costing_basis == "cash" else consumed + labor)


static func _validate_active_plan(report: Dictionary, lines: Dictionary) -> bool:
	var plan: Variant = report.get("selected_cost_plan")
	var receipt: Variant = report.get("active_cost_receipt")
	var context: Variant = report.get("cost_context")
	if not plan is Dictionary or not _keys(plan, PLAN_FIELDS) or not _valid_receipt(receipt) \
		or not context is Dictionary or not _keys(context, ["profile_hash", "recipe_hash", "purchase_book_hash", "labor_policy_hash"]) \
		or plan.transaction_id != receipt.transaction_id or plan.receipt_digest != receipt.receipt_digest \
		or plan.candidate_catalog_hash != receipt.candidate_catalog_hash or plan.financial_scope != receipt.financial_scope \
		or plan.purchase_mode != receipt.request.purchase_mode or plan.labor_mode != receipt.request.labor_mode \
		or plan.costing_basis != receipt.request.costing_basis or report.get("costing_mode") != plan.labor_mode \
		or receipt.identity != report.identity or receipt.catalog_hash != report.get("catalog_hash") \
		or int(receipt.expected_revision) > int(report.revision):
		return false
	for field: String in ["profile_hash", "recipe_hash", "purchase_book_hash", "labor_policy_hash"]:
		if context[field] != receipt[field]:
			return false
	if report.has("game_assessment") and report.game_assessment.get("profile_sha256") != receipt.profile_hash:
		return false
	if report.has("incident_complete") and report.incident_complete != report.complete:
		return false
	var purchase: Dictionary = receipt.purchase
	var coverage := {}
	var provenance := {}
	var kinds := {}
	var packages := {}
	for row: Dictionary in purchase.get("selected_coverage", []): coverage[row.candidate_id] = row
	for row: Dictionary in purchase.get("selected_provenance", []): provenance[row.candidate_id] = row.provenance
	for row: Dictionary in purchase.get("selected_candidate_kinds", []): kinds[row.candidate_id] = row
	for row: Dictionary in purchase.get("selected_source_packages", []): packages[row.candidate_id] = row.package_id
	var expected := {}
	for row: Dictionary in purchase.get("selected_lines", []):
		var id := _line_id("purchase", row.candidate_id)
		if not lines.has(id) or not coverage.has(row.candidate_id) or not provenance.has(row.candidate_id) or not kinds.has(row.candidate_id):
			return false
		var line: Dictionary = lines[id]
		if line.get("action") != "selected_purchase" or line.get("amount_minor") != row.cost_cents \
			or line.get("provenance") != provenance[row.candidate_id]:
			return false
		for field: String in ["allocated_ids", "overlap_ids", "surplus_ids"]:
			if line.get(field) != coverage[row.candidate_id][field]:
				return false
		var kind: Dictionary = kinds[row.candidate_id]
		if kind.kind == "dossier_individual_estimate":
			if line.get("component_id") != kind.component_id or line.get("package_id") != "" or row.coverage_ids != [kind.unit_id]:
				return false
		elif line.get("package_id") != packages.get(row.candidate_id) or line.get("component_id") != "":
			return false
		expected[id] = true
	if not purchase.required_unit_ids.is_empty() and report.get("replacement_minor") != purchase.total_cost_cents:
		return false
	var aggregate: Dictionary = receipt.repair.aggregate
	for material: Dictionary in aggregate.get("materials", []):
		var id := _line_id("material", material.material_id)
		var amount: Variant = material.purchase_minor if plan.costing_basis == "cash" else material.consumption_minor
		if not lines.has(id) or lines[id].get("action") != "repair_material" or lines[id].get("amount_minor") != amount \
			or lines[id].get("source") != material.source or lines[id].get("purchase_minor") != material.purchase_minor \
			or lines[id].get("consumption_minor") != material.consumption_minor:
			return false
		expected[id] = true
	for work: Dictionary in aggregate.get("labor_groups", []):
		var id := _line_id("repair-labor", work.id)
		if not lines.has(id) or lines[id].get("action") != "repair_labor" or lines[id].get("amount_minor") != work.labor_minor \
			or lines[id].get("labor_minutes") != work.labor_minutes or lines[id].get("labor_rate_minor_per_hour") != work.labor_rate_minor_per_hour \
			or lines[id].get("source") != work.source:
			return false
		expected[id] = true
	for work: Dictionary in receipt.policy_labor.lines:
		if not lines.has(work.id):
			return false
		for field: Variant in work:
			if lines[work.id].get(field) != work[field]:
				return false
		expected[work.id] = true
	for id: Variant in lines:
		if lines[id].get("action") in ["selected_purchase", "repair_material", "repair_labor", "game_labor"] and not expected.has(id):
			return false
	var frozen_fees: Array = receipt.base_assessment.get("incurred_fees", []).duplicate(true)
	frozen_fees.append_array(receipt.request.incurred_fees)
	var covered := {}
	for unit: String in purchase.required_unit_ids:
		var split := unit.rfind(":")
		if split <= 0:
			return false
		covered[unit.substr(0, split)] = true
	for component: String in receipt.repair.component_ids:
		covered[component] = true
	for component: Variant in covered:
		var decision: Variant = receipt.covered_decisions.get(component)
		if not decision is Dictionary:
			return false
		if decision.has("inspection_minor"):
			frozen_fees.append({"id": decision.get("inspection_fee_id", "component:%s:inspection" % component),
				"kind": "inspection", "amount_minor": decision.inspection_minor})
	var seen_fees := {}
	for fee: Dictionary in frozen_fees:
		if seen_fees.has(fee.id):
			return false
		seen_fees[fee.id] = true
		if not lines.has(fee.id) or lines[fee.id].get("action") != "incurred_fee" \
			or lines[fee.id].get("fee_kind") != fee.kind or lines[fee.id].get("amount_minor") != fee.amount_minor:
			return false
	return true


static func _complete_line_range(lines: Array, report: Dictionary) -> bool:
	var low := 0
	var high := 0
	for line: Dictionary in lines:
		var amount: Variant = line.get("amount_minor")
		var lower: Variant = line.get("low_minor", amount)
		var upper: Variant = line.get("high_minor", amount)
		# Some historical or special rows do not state comparable bounds.
		if not _minor(lower) or not _minor(upper):
			return true
		if int(lower) > MAX_MINOR - low or int(upper) > MAX_MINOR - high:
			return true
		low += int(lower)
		high += int(upper)
	return report.get("low_minor") == low and report.get("high_minor") == high


static func _mul_div(value: int, units: int, divisor: int, ceil_result: bool) -> Variant:
	if value < 0 or units < 0 or divisor <= 0:
		return null
	var whole: int = value / divisor
	var remainder: int = value % divisor
	if units > 0 and whole > MAX_MINOR / units:
		return null
	var amount: int = whole * units
	var fraction: int = remainder * units
	var rounded: int = fraction / divisor
	var rest: int = fraction % divisor
	if (ceil_result and rest > 0) or (not ceil_result and rest * 2 >= divisor):
		rounded += 1
	return null if rounded > MAX_MINOR - amount else amount + rounded


static func _semantic_integers(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key: Variant in value:
			result[key] = _semantic_integers(value[key])
		return result
	if value is Array:
		var result := []
		for item: Variant in value:
			result.append(_semantic_integers(item))
		return result
	if value is float and is_finite(value) and floor(value) == value and absf(value) <= float(MAX_SAFE_INTEGER):
		return int(value)
	return value


static func _identity(value: Variant, needs_source: bool) -> bool:
	if not value is Dictionary or not _keys(value, ["incident_id", "aircraft_id", "source_sha256"]) \
		or not _text(value.get("incident_id"), 128) or not _text(value.get("aircraft_id"), 128) \
		or not _text(value.get("source_sha256"), 128, not needs_source):
		return false
	return not needs_source or _hash(value.source_sha256)


static func _source(value: Variant) -> bool:
	if not value is Dictionary or value.is_empty() or value.size() > 64:
		return false
	for key: Variant in value:
		if not _text(key, 128):
			return false
		var field: Variant = value[key]
		match typeof(field):
			TYPE_NIL, TYPE_BOOL, TYPE_INT:
				pass
			TYPE_FLOAT:
				if not is_finite(field):
					return false
			TYPE_STRING:
				if field.length() > 4096:
					return false
			_:
				return false
	return true


static func _line_id(kind: String, value: Variant) -> String:
	return "plan-%s-%s" % [kind, str(value).sha256_text().substr(0, 24)]


static func _hash(value: Variant) -> bool:
	if not value is String or value.length() != 64:
		return false
	for code: int in value.to_ascii_buffer():
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
			return false
	return true


static func _text(value: Variant, maximum: int, allow_empty: bool = false) -> bool:
	return value is String and value.length() <= maximum and (allow_empty or not value.strip_edges().is_empty())


static func _integer_between(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) == TYPE_INT:
		return int(value) >= minimum and int(value) <= maximum
	if typeof(value) == TYPE_FLOAT:
		return is_finite(value) and value == floor(value) and value >= float(minimum) and value <= float(maximum)
	return false


static func _minor(value: Variant) -> bool:
	return _integer_between(value, 0, MAX_MINOR)


static func _signed_minor(value: Variant) -> bool:
	return _integer_between(value, -MAX_MINOR, MAX_MINOR)


static func _positive_int(value: Variant, maximum: int) -> bool:
	return _integer_between(value, 1, maximum)


static func _nonnegative_int(value: Variant, maximum: int) -> bool:
	return _integer_between(value, 0, maximum)


static func _keys(value: Variant, expected: Array) -> bool:
	if not value is Dictionary or value.size() != expected.size():
		return false
	for key: Variant in value:
		if key not in expected:
			return false
	return true


static func _string_array(value: Variant, count: int, length: int) -> bool:
	if not value is Array or value.size() > count:
		return false
	for entry: Variant in value:
		if not _text(entry, length):
			return false
	return true


static func _unique_strings(value: Variant, count: int, length: int) -> bool:
	if not _string_array(value, count, length):
		return false
	var seen := {}
	for item: String in value:
		if seen.has(item):
			return false
		seen[item] = true
	return true


## Hash the actual receipt/request substrings. JSON.parse_string turns every
## numeric token into a float, so re-serializing parsed data changes valid
## receipt hashes (and coercing all integral floats would lose information).
static func _raw_receipt_digests(payload: String, report: Dictionary) -> bool:
	var fields := _raw_object_fields(payload, 0)
	if fields.is_empty():
		return false
	if report.has("active_cost_receipt") and not report.active_cost_receipt.is_empty():
		if not fields.has("active_cost_receipt") or not _raw_receipt_digest(payload, fields.active_cost_receipt, report.active_cost_receipt):
			return false
	for name: String in ["cost_transactions", "quote_history"]:
		if not report.has(name):
			continue
		if not fields.has(name):
			return false
		var positions := _raw_array_values(payload, int(fields[name].start))
		if positions.size() != report[name].size():
			return false
		for index: int in range(positions.size()):
			if not _raw_receipt_digest(payload, positions[index], report[name][index]):
				return false
	return true


static func _raw_receipt_digest(payload: String, span: Dictionary, receipt: Dictionary) -> bool:
	var start := int(span.start)
	var end := int(span.end)
	var fields := _raw_object_fields(payload, start)
	if not fields.has("receipt_digest") or not fields.has("request"):
		return false
	var digest_field: Dictionary = fields.receipt_digest
	var request_field: Dictionary = fields.request
	# The canonical producer sorts keys and emits compact JSON. Remove the
	# digest member and its preceding comma, preserving all other exact bytes.
	var key_start := int(digest_field.key_start)
	if key_start <= start or payload[key_start - 1] != ",":
		return false
	var unsigned := payload.substr(start, key_start - 1 - start) + payload.substr(int(digest_field.end), end - int(digest_field.end))
	var request := payload.substr(int(request_field.start), int(request_field.end) - int(request_field.start))
	return unsigned.sha256_text() == receipt.receipt_digest and request.sha256_text() == receipt.request_digest


static func _raw_object_fields(text: String, start: int) -> Dictionary:
	var result := {}
	if start < 0 or start >= text.length() or text[start] != "{":
		return result
	var i := _skip_space(text, start + 1)
	while i < text.length() and text[i] != "}":
		var key_start := i
		var key_end := _raw_string_end(text, i)
		if key_end < 0:
			return {}
		var key: Variant = _parse_json(text.substr(i, key_end - i))
		if not key is String or result.has(key):
			return {}
		i = _skip_space(text, key_end)
		if i >= text.length() or text[i] != ":":
			return {}
		var value_start := _skip_space(text, i + 1)
		var value_end := _raw_value_end(text, value_start)
		if value_end < 0:
			return {}
		result[key] = {"key_start": key_start, "start": value_start, "end": value_end}
		i = _skip_space(text, value_end)
		if i < text.length() and text[i] == ",":
			i = _skip_space(text, i + 1)
		elif i >= text.length() or text[i] != "}":
			return {}
	return result


static func _raw_array_values(text: String, start: int) -> Array:
	var result := []
	if start < 0 or start >= text.length() or text[start] != "[":
		return result
	var i := _skip_space(text, start + 1)
	while i < text.length() and text[i] != "]":
		var end := _raw_value_end(text, i)
		if end < 0:
			return []
		result.append({"start": i, "end": end})
		i = _skip_space(text, end)
		if i < text.length() and text[i] == ",":
			i = _skip_space(text, i + 1)
		elif i >= text.length() or text[i] != "]":
			return []
	return result


static func _raw_value_end(text: String, start: int) -> int:
	if start >= text.length():
		return -1
	if text[start] == '"':
		return _raw_string_end(text, start)
	if text[start] in ["{", "["]:
		var stack: Array[String] = []
		var i := start
		while i < text.length():
			var ch := text[i]
			if ch == '"':
				i = _raw_string_end(text, i)
				if i < 0:
					return -1
				continue
			if ch == "{" or ch == "[":
				stack.append(ch)
			elif ch == "}" or ch == "]":
				if stack.is_empty() or (ch == "}" and stack.back() != "{") or (ch == "]" and stack.back() != "["):
					return -1
				stack.pop_back()
				if stack.is_empty():
					return i + 1
			i += 1
		return -1
	var i := start
	while i < text.length() and text[i] not in [",", "}", "]", " ", "\t", "\r", "\n"]:
		i += 1
	return i if i > start else -1


static func _raw_string_end(text: String, start: int) -> int:
	if start >= text.length() or text[start] != '"':
		return -1
	var i := start + 1
	while i < text.length():
		if text[i] == "\\":
			i += 2
		elif text[i] == '"':
			return i + 1
		else:
			i += 1
	return -1


static func _skip_space(text: String, start: int) -> int:
	var i := start
	while i < text.length() and text[i] in [" ", "\t", "\r", "\n"]:
		i += 1
	return i


static func _parse_json(text: String) -> Variant:
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return null
	return parser.data


static func _safe_tree(value: Variant, allow_private: bool = false) -> bool:
	return _safe_node(value, 0, {"count": 0}, [], allow_private)


static func _safe_node(value: Variant, depth: int, budget: Dictionary, ancestors: Array, allow_private: bool) -> bool:
	budget.count += 1
	if budget.count > MAX_NODES or depth > MAX_DEPTH:
		return false
	if value is Dictionary or value is Array:
		if value.size() > MAX_ARRAY:
			return false
		for ancestor: Variant in ancestors:
			if is_same(ancestor, value):
				return false
		ancestors.append(value)
		if value is Dictionary:
			for key: Variant in value:
				if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME] or String(key).length() > 256 \
					or (not allow_private and String(key) in PRIVATE_FIELDS) \
					or not _safe_node(value[key], depth + 1, budget, ancestors, allow_private):
					ancestors.pop_back()
					return false
		else:
			for item: Variant in value:
				if not _safe_node(item, depth + 1, budget, ancestors, allow_private):
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
			return String(value).length() <= MAX_TEXT
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			if value.size() > MAX_ARRAY or budget.count + value.size() > MAX_NODES:
				return false
			for item: Variant in value:
				if not _safe_node(item, depth + 1, budget, ancestors, allow_private):
					return false
			return true
		_:
			return false


static func _strip_private(value: Variant) -> void:
	if value is Dictionary:
		for key: Variant in value.keys():
			if key in PRIVATE_FIELDS:
				value.erase(key)
			else:
				_strip_private(value[key])
	elif value is Array:
		for item: Variant in value:
			_strip_private(item)


static func _encode_failure(message: String) -> Dictionary:
	return {"ok": false, "errors": [message], "text": ""}


static func _decode_failure(message: String) -> Dictionary:
	return {"ok": false, "errors": [message], "report": {}, "legacy": false}


static func _validation_failure(message: String) -> Dictionary:
	return {"ok": false, "errors": [message]}

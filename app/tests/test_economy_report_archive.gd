extends SceneTree

const Archive = preload("res://economy/report_archive.gd")
const Incident = preload("res://economy/incident.gd")
const Transaction = preload("res://economy/cost_transaction.gd")
const Calculator = preload("res://economy/calculator.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	_test_real_report()
	_test_integrity_and_metadata()
	_test_fees()
	_test_grouped_repair()
	_test_legacy_and_limits()
	print("report archive: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _check(label: String, condition: bool, detail: Variant = "") -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL %s: %s" % [label, str(detail)])


func _owner() -> RefCounted:
	var ledger := Incident.new()
	ledger.begin("jensen-das-ugly-stik-60", "")
	ledger._assessment.components["propeller"] = {"disposition": "replace", "quantity": 1}
	ledger._last_tick = 1
	ledger._queue_assessment(1)
	ledger.evaluate_pending()
	return ledger


func _fixture() -> Dictionary:
	return _report_for(_owner())


func _report_for(ledger: RefCounted) -> Dictionary:
	var report: Dictionary = ledger.report.duplicate(true)
	report["active_cost_receipt"] = ledger._active_cost_receipt.duplicate(true)
	report["cost_context"] = {"profile_hash": ledger._profile_hash, "recipe_hash": ledger._recipe_hash,
		"purchase_book_hash": ledger._purchase_book_hash, "labor_policy_hash": ledger._labor_policy_hash}
	return report


func _test_real_report() -> void:
	var report := _fixture()
	_check("real current report has an automatic selected plan", report.has("selected_cost_plan") and not report.active_cost_receipt.is_empty(), report)
	var encoded := Archive.encode(report)
	_check("real current report encodes", encoded.ok, encoded.get("errors"))
	if not encoded.ok:
		return
	var decoded := Archive.decode(encoded.text)
	_check("real current report decodes without legacy fallback", decoded.ok and not decoded.legacy and decoded.report.total_minor == report.total_minor, decoded.get("errors"))
	if decoded.ok:
		var receipt: Dictionary = decoded.report.active_cost_receipt.duplicate(true)
		var expected: String = receipt.receipt_digest
		receipt.erase("receipt_digest")
		var normalized: Dictionary = _integerize(receipt)
		_check("parsed receipt preserves canonical transaction digest", Transaction.digest(normalized) == expected, [Transaction.digest(normalized), expected])
		_check("parsed request preserves canonical transaction digest", Transaction.digest(normalized.request) == receipt.request_digest)


func _wrap(report: Dictionary) -> String:
	var payload := JSON.stringify(report, "", true, true)
	return JSON.stringify({"format": Archive.FORMAT, "report_json": payload, "payload_sha256": payload.sha256_text()}, "", true, true)


func _rejected(label: String, report: Dictionary) -> void:
	var result := Archive.decode(_wrap(report))
	_check(label, not result.ok, result.get("errors"))


func _test_integrity_and_metadata() -> void:
	var report := _fixture()
	var encoded := Archive.encode(report)
	if not encoded.ok:
		_check("integrity fixture encodes", false, encoded.errors)
		return
	var envelope: Dictionary = JSON.parse_string(encoded.text)
	var corrupted := envelope.duplicate(true)
	corrupted.report_json = corrupted.report_json.replace("propeller", "prOpeller")
	_check("altered payload bytes reject", not Archive.decode(JSON.stringify(corrupted)).ok)
	_check("truncated outer JSON rejects", not Archive.decode(encoded.text.substr(0, encoded.text.length() - 1)).ok)
	corrupted = envelope.duplicate(true)
	corrupted.payload_sha256 = "0".repeat(64)
	_check("wrong payload hash rejects", not Archive.decode(JSON.stringify(corrupted)).ok)
	corrupted = envelope.duplicate(true)
	corrupted.extra = true
	_check("unknown envelope members reject", not Archive.decode(JSON.stringify(corrupted)).ok)
	corrupted = envelope.duplicate(true)
	corrupted.format = "openrc-accident-report v2"
	_check("envelope cannot masquerade as legacy raw report", not Archive.decode(JSON.stringify(corrupted)).ok)
	var bad := report.duplicate(true)
	bad.erase("active_cost_receipt")
	_rejected("historyless automatic plan needs its active receipt", bad)
	bad = report.duplicate(true)
	bad.erase("cost_context")
	_rejected("plan needs frozen source context", bad)
	bad = report.duplicate(true)
	bad.cost_context.profile_hash = "0".repeat(64)
	_rejected("plan profile mismatch rejects", bad)
	bad = report.duplicate(true)
	bad.erase("selected_cost_plan")
	bad.erase("active_cost_receipt")
	_rejected("selected lines cannot silently lose their plan", bad)
	bad.lines = []
	bad.cost_context = {}
	for field: String in ["known_subtotal_minor", "total_minor", "low_minor", "high_minor"]: bad[field] = 0
	_rejected("successful zero-work estimate cannot silently lose its plan", bad)
	bad.costing_error = "unavailable"
	_rejected("a costing error cannot certify a complete zero estimate", bad)
	bad.complete = false
	bad.incident_complete = false
	bad.total_minor = null
	bad.low_minor = null
	bad.high_minor = null
	bad.erase("game_assessment")
	bad.unresolved = ["The cost plan is unavailable."]
	_check("genuinely incomplete unavailable plans remain readable", Archive.decode(_wrap(bad)).ok)
	bad = report.duplicate(true)
	bad.costing_error = "A replacement option was refused; the previous valid plan is retained."
	_check("a refused option may retain the complete valid selected plan", Archive.decode(_wrap(bad)).ok)
	bad = report.duplicate(true)
	bad.active_cost_receipt.covered_decisions.propeller.quantity = 2
	_rejected("rehashing outer payload cannot hide changed covered decision", bad)
	bad = report.duplicate(true)
	bad.active_cost_receipt.transaction_id = "changed"
	bad.active_cost_receipt.request.transaction_id = "changed"
	bad.selected_cost_plan.transaction_id = "changed"
	_rejected("rehashing outer payload cannot hide changed request", bad)
	bad = report.duplicate(true)
	bad.quote_history = [bad.active_cost_receipt.duplicate(true)]
	bad.quote_history[0].covered_decisions.propeller.quantity = 2
	_rejected("retained history also needs its original receipt digest", bad)
	bad = report.duplicate(true)
	bad.total_minor += 1
	_rejected("complete total must match lines", bad)
	bad = report.duplicate(true)
	bad.low_minor = 0
	_rejected("forged low bound rejects", bad)
	bad = report.duplicate(true)
	bad.high_minor += 1
	_rejected("forged high bound rejects", bad)
	bad = report.duplicate(true)
	bad.lines.append(bad.lines[0].duplicate(true))
	_rejected("duplicate lines reject", bad)
	bad = report.duplicate(true)
	bad.total_minor = true
	_rejected("bool is not money", bad)
	bad = report.duplicate(true)
	for line: Dictionary in bad.lines:
		if line.action == "selected_purchase":
			line.quantity = 0
	_rejected("zero purchase quantity rejects", bad)
	bad = report.duplicate(true)
	for line: Dictionary in bad.lines:
		if line.action == "selected_purchase":
			line.provenance = ""
	_rejected("missing purchase provenance rejects", bad)
	bad = report.duplicate(true)
	bad.active_cost_receipt.purchase.selected_coverage[0].allocated_ids = [true]
	_rejected("malformed nested allocation rejects", bad)
	bad = report.duplicate(true)
	bad.evidence = [{"format": "synthetic event", "event_id": "precision", "velocity": PackedFloat64Array([0.12345678901234566, -3.141592653589793, 1.0])}]
	var precise := Archive.encode(bad)
	var roundtrip := Archive.decode(precise.text) if precise.ok else {}
	_check("finite packed vectors preserve high precision", precise.ok and roundtrip.get("ok", false) and roundtrip.report.evidence[0].velocity[0] == bad.evidence[0].velocity[0], precise.get("errors"))


func _test_fees() -> void:
	var ledger := _owner()
	ledger._assessment["incurred_fees"] = [{"id": "inspection-old", "kind": "inspection", "amount_minor": 500}]
	ledger._active_cost_receipt = {}
	ledger._queue_assessment(2)
	ledger.evaluate_pending()
	var report := _report_for(ledger)
	var encoded := Archive.encode(report)
	_check("base assessment fee survives automatic quote", encoded.ok and report.active_cost_receipt.base_assessment.incurred_fees[0].amount_minor == 500, encoded.get("errors"))
	if encoded.ok:
		var bad := report.duplicate(true)
		for line: Dictionary in bad.lines:
			if line.id == "inspection-old":
				line.amount_minor = 0
		for field: String in ["known_subtotal_minor", "total_minor", "low_minor", "high_minor", "incurred_fees_minor"]:
			if bad.get(field) != null:
				bad[field] -= 500
		_rejected("balanced totals cannot erase frozen baseline fee", bad)
	ledger = _owner()
	ledger._assessment.components.propeller.inspection_minor = 300
	ledger._assessment.components.propeller.inspection_fee_id = "prop-fee"
	ledger._queue_assessment(2)
	ledger.evaluate_pending()
	report = _report_for(ledger)
	encoded = Archive.encode(report)
	_check("covered component inspection fee survives selection", encoded.ok, encoded.get("errors"))
	if encoded.ok:
		var bad := report.duplicate(true)
		for line: Dictionary in bad.lines:
			if line.id == "prop-fee":
				line.amount_minor = 0
		for field: String in ["known_subtotal_minor", "total_minor", "low_minor", "high_minor", "incurred_fees_minor"]:
			if bad.get(field) != null:
				bad[field] -= 300
		_rejected("balanced totals cannot erase covered component fee", bad)
	ledger = _owner()
	ledger._assessment["incurred_fees"] = [{"id": "unknown-fee", "kind": "inspection", "amount_minor": null}]
	ledger._active_cost_receipt = {}
	ledger._queue_assessment(2)
	ledger.evaluate_pending()
	report = _report_for(ledger)
	encoded = Archive.encode(report)
	_check("unknown incurred fee stays unknown", encoded.ok and report.total_minor == null and not report.complete, encoded.get("errors"))
	if encoded.ok:
		var bad := report.duplicate(true)
		for line: Dictionary in bad.lines:
			if line.id == "unknown-fee":
				line.amount_minor = 0
		_rejected("unknown incurred fee cannot become free", bad)
	ledger = _owner()
	ledger._assessment["incurred_fees"] = [{"id": "later-fee", "kind": "inspection", "amount_minor": 200}]
	ledger._queue_assessment(2)
	ledger.evaluate_pending()
	report = _report_for(ledger)
	encoded = Archive.encode(report)
	_check("new remainder fee is allowed beside earlier receipt", encoded.ok and report.incident_complete and report.incurred_fees_minor == 200 and not report.active_cost_receipt.base_assessment.has("incurred_fees"), encoded.get("errors"))


func _test_grouped_repair() -> void:
	var identity := {"incident_id": "synthetic", "aircraft_id": "fixture", "source_sha256": "a".repeat(64)}
	var parts := []
	for id: String in ["wing_a", "wing_b"]:
		parts.append({"id": id, "quantity": 1, "physical_inventory_ids": ["parent-" + id], "unit_minor": 5000,
			"low_unit_minor": 5000, "high_unit_minor": 5000, "price_basis": "fixture_allowance", "offer_id": null})
	var dossier := {"format": "openrc-aircraft-economics v2", "aircraft_id": "fixture", "source_sha256": "a".repeat(64),
		"currency": "USD", "price_date": "2026-11-09", "valuation_kind": "fixture", "complete": true,
		"missing": [], "components": parts}
	var book := {"format": "openrc-game-purchase-book v1", "aircraft_id": "fixture", "packages": []}
	var policy := {"format": "openrc-game-labor-policy v1", "currency": "USD", "paid_rate_minor_per_hour": 6000,
		"minutes_by_component": {"wing_a": 30, "wing_b": 30}, "shared_setup_minutes": 5,
		"basis": "authored_game_policy", "evidence": "Synthetic scenario."}
	var context := {"identity": identity, "catalog_hash": "b".repeat(64), "profile_hash": "c".repeat(64),
		"recipe_hash": "d".repeat(64), "purchase_book_hash": Transaction.digest(book),
		"labor_policy_hash": Transaction.digest(policy), "revision": 4, "package_book": book,
		"labor_policy": policy, "blocked": {}, "confirmed_replacements": {}}
	var source := {"kind": "fixture", "source_name": "fixture", "evidence": "synthetic", "price_minor": 1000,
		"currency": "USD", "source_url": "https://example.test/pack", "observed_on": "2026-11-09", "availability": "fixture"}
	var recipes := {"format": "openrc-repair-recipes v1", "currency": "USD", "recipes": [{"id": "patch", "label": "Patch", "repair_unit": "units",
		"damage_classes": ["covering_only"], "compatible_components": {"fixture": ["wing_a", "wing_b"]},
		"materials": [{"id": "film", "requirement_key": "units", "unit": "unit", "package_units": 10, "package_price_minor": 1000, "source": source}],
		"labor": {"diy_rate_minor_per_hour": 0, "paid_rate_minor_per_hour": 6000,
			"diy_provenance": {"kind": "fixture", "description": "DIY"},
			"paid_provenance": {"kind": "fixture", "description": "paid", "rate_minor_per_hour": 6000}}}]}
	var current := {"components": {"wing_a": {"disposition": "inspect"}, "wing_b": {"disposition": "inspect"}},
		"terminal": false, "total_loss": false, "unresolved": []}
	var inspected := {}
	for item: Array in [["wing_a", 4], ["wing_b", 3]]:
		inspected[item[0]] = {"status": "inspected", "damage_class": "covering_only", "quantity": 1,
			"replacement_comparable": false, "measurements": {"units": item[1]}, "labor_minutes": 30, "evidence": "Synthetic explicit inspection."}
	var request := {"format": Transaction.FORMAT, "transaction_id": "grouped", "identity": identity,
		"catalog_hash": context.catalog_hash, "profile_hash": context.profile_hash, "recipe_hash": context.recipe_hash,
		"purchase_book_hash": context.purchase_book_hash, "labor_policy_hash": context.labor_policy_hash,
		"expected_revision": 4, "repair_inspection": {"format": "openrc-repair-inspection v1", "basis": "scenario_assumption", "components": inspected},
		"repair_choices": [{"component_id": "wing_a", "option_id": "patch"}, {"component_id": "wing_b", "option_id": "patch"}],
		"labor_mode": "paid", "costing_basis": "cash", "shared_labor_groups": [{"id": "shared", "component_ids": ["wing_a", "wing_b"],
		"labor_minutes": 30, "scope": "shared_complete_work", "basis": "scenario_assumption", "evidence": "One shared job."}],
		"purchase_mode": "optimal", "selected_candidate_ids": [], "incurred_fees": [{"id": "fee", "kind": "inspection", "amount_minor": 500}]}
	var prepared := Transaction.prepare(request, dossier, current, recipes, context)
	_check("synthetic shared repair computes 1000 material + 3000 labor + 500 fee", prepared.ok and prepared.report.total_minor == 4500, prepared.get("errors"))
	if not prepared.ok:
		return
	var report: Dictionary = prepared.report.duplicate(true)
	report.merge({"format": "openrc-accident-report v2", "identity": identity, "incident_id": identity.incident_id, "aircraft_name": "Fixture", "catalog_hash": context.catalog_hash,
		"revision": 4, "tick": 4, "terminal": false, "costing_available": true, "costing_error": "", "costing_mode": "paid",
		"active_cost_receipt": prepared.receipt, "cost_context": {"profile_hash": context.profile_hash, "recipe_hash": context.recipe_hash,
		"purchase_book_hash": context.purchase_book_hash, "labor_policy_hash": context.labor_policy_hash}}, true)
	var encoded := Archive.encode(report)
	_check("grouped repair and paid work encode", encoded.ok, encoded.get("errors"))
	if encoded.ok:
		var decoded := Archive.decode(encoded.text)
		_check("grouped repair and paid work round-trip", decoded.ok and decoded.report.total_minor == 4500, decoded.get("errors"))
		var bad := report.duplicate(true)
		bad.active_cost_receipt.repair.aggregate.materials[0].required_units = 6
		bad.active_cost_receipt.repair.aggregate.materials[0].consumption_minor = 600
		bad.active_cost_receipt.repair.aggregate.material_consumption_minor = 600
		bad.active_cost_receipt.repair.aggregate.consumption_total_minor = 3600
		bad.active_cost_receipt.erase("receipt_digest")
		bad.active_cost_receipt.receipt_digest = Transaction.digest(bad.active_cost_receipt)
		bad.selected_cost_plan.receipt_digest = bad.active_cost_receipt.receipt_digest
		for line: Dictionary in bad.lines:
			if line.action == "repair_material": line.consumption_minor = 600
		_rejected("rehashed grouped material must equal both saved selections", bad)
	request.shared_labor_groups[0].scope = "additional_setup"
	prepared = Transaction.prepare(request, dossier, current, recipes, context)
	_check("additional setup retains both 30-minute tasks", prepared.ok and prepared.report.total_minor == 10500, prepared.get("errors"))
	if prepared.ok:
		report = prepared.report.duplicate(true)
		report.merge({"format": "openrc-accident-report v2", "identity": identity, "incident_id": identity.incident_id,
			"aircraft_name": "Fixture", "catalog_hash": context.catalog_hash, "revision": 4, "tick": 4,
			"terminal": false, "costing_available": true, "costing_error": "", "costing_mode": "paid",
			"active_cost_receipt": prepared.receipt, "cost_context": {"profile_hash": context.profile_hash,
			"recipe_hash": context.recipe_hash, "purchase_book_hash": context.purchase_book_hash,
			"labor_policy_hash": context.labor_policy_hash}}, true)
		encoded = Archive.encode(report)
		_check("additional setup scope round-trips", encoded.ok and Archive.decode(encoded.text).ok, encoded.get("errors"))
	source["fixture_float"] = 1.0
	prepared = Transaction.prepare(request, dossier, current, recipes, context)
	_check("transaction accepts an integral float in source metadata", prepared.ok, prepared.get("errors"))
	if prepared.ok:
		report = prepared.report.duplicate(true)
		report.merge({"format": "openrc-accident-report v2", "identity": identity, "incident_id": identity.incident_id,
			"aircraft_name": "Fixture", "catalog_hash": context.catalog_hash, "revision": 4, "tick": 4,
			"terminal": false, "costing_available": true, "costing_error": "", "costing_mode": "paid",
			"active_cost_receipt": prepared.receipt, "cost_context": {"profile_hash": context.profile_hash,
			"recipe_hash": context.recipe_hash, "purchase_book_hash": context.purchase_book_hash,
			"labor_policy_hash": context.labor_policy_hash}}, true)
		encoded = Archive.encode(report)
		_check("exact receipt hash preserves an original integral float", encoded.ok and Archive.decode(encoded.text).ok, encoded.get("errors"))


func _test_legacy_and_limits() -> void:
	var report := _fixture()
	report.erase("active_cost_receipt")
	report.erase("cost_context")
	report["dossier"] = {"secret": "unrelated frozen book"}
	report["unrelated"] = "not part of report"
	report.evidence = [{"format": "old event", "event_id": "event", "candidate_catalog": {"junk": 1}}]
	var historical := Archive.decode(JSON.stringify(report, "", true, true))
	_check("actual raw v2 report remains historical view-only", historical.ok and historical.legacy, historical.get("errors"))
	if historical.ok:
		_check("arbitrary books and unknown fields are removed", not historical.report.has("dossier") and not historical.report.has("unrelated") and not historical.report.evidence[0].has("candidate_catalog"))
	var old := {"format": "openrc-accident-report v1", "identity": {}, "lines": [], "unresolved": [], "complete": false, "total_minor": null}
	historical = Archive.decode(JSON.stringify(old))
	_check("bounded raw v1 report stays readable", historical.ok and historical.legacy, historical.get("errors"))
	var bad := _fixture()
	bad.unresolved = []
	for i: int in range(513): bad.unresolved.append("pending")
	_check("top-level text lists have a 512-item bound", not Archive.encode(bad).ok)
	bad = _fixture()
	bad.lines = []
	for i: int in range(385): bad.lines.append({"id": str(i), "action": "reuse", "quantity": 1, "amount_minor": 0})
	_check("top-level lines have a 384-item bound", not Archive.encode(bad).ok)
	bad = _fixture()
	bad.unresolved = ["x".repeat(16384), "x".repeat(16384), "x".repeat(16384), "x".repeat(16384), "x".repeat(16384), "x".repeat(16384), "x".repeat(16384), "x".repeat(16384), "x".repeat(16384), "x".repeat(16384), "x".repeat(16384), "x".repeat(16384), "x".repeat(16384), "x".repeat(16384), "x".repeat(16384), "x".repeat(16384), "x".repeat(16384)]
	_check("payload byte limit rejects oversized reports", not Archive.encode(bad).ok)
	bad = _fixture()
	var cycle := []
	cycle.append(cycle)
	bad["evidence"] = cycle
	_check("cyclic data rejects without recursion", not Archive.encode(bad).ok)
	var deep: Variant = {}
	for i: int in range(30): deep = {"next": deep}
	old["dossier"] = deep
	_check("deep legacy books are bounded before removal", not Archive.decode(JSON.stringify(old)).ok)


func _integerize(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key: Variant in value:
			result[key] = _integerize(value[key])
		return result
	if value is Array:
		var result := []
		for item: Variant in value:
			result.append(_integerize(item))
		return result
	if value is float and is_finite(value) and floor(value) == value and absf(value) <= 9007199254740991.0:
		return int(value)
	return value

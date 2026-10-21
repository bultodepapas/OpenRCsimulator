extends SceneTree

const Incident := preload("res://economy/incident.gd")
const RepairDetails := preload("res://economy/repair_details.gd")

const COMPONENT_ID := "covered_airframe_and_installation_hardware"
const REPAIR_EVIDENCE := "Inspected a measured film patch; structure intact. Synthetic test fixture."

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_test_basis_and_labor_matrix()
	_test_identity_binding_and_json_roundtrip()
	_test_offer_metadata_compatibility()
	_test_supersession_and_ambiguity()
	_test_malformed_optional_data()
	print("economy repair details: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_basis_and_labor_matrix() -> void:
	var expected := {
		"diy|cash": 2299,
		"diy|consumption": 14,
		"paid|cash": 4549,
		"paid|consumption": 2264,
	}
	for labor_mode: String in ["diy", "paid"]:
		for costing_basis: String in ["cash", "consumption"]:
			var fixture := _repair_fixture(labor_mode, costing_basis, "choice-%s-%s" % [labor_mode, costing_basis])
			var ledger: RefCounted = fixture.ledger
			var report: Dictionary = ledger.report
			var normalized: Array[Dictionary] = RepairDetails.normalize(report)
			var key := labor_mode + "|" + costing_basis
			var expected_repair: int = expected[key]
			_check("real incident choice applies for " + key, fixture.applied.get("ok", false), str(fixture.applied))
			_check("latest explicit choice normalizes for " + key, normalized.size() == 1, str(normalized))
			if normalized.size() != 1:
				continue
			var row: Dictionary = normalized[0]
			var line := _line(report, COMPONENT_ID)
			_check("selected subtotal matches planner basis for " + key, row.repair_minor == expected_repair)
			_check("inspection fee stays separate from the selected subtotal for " + key,
				row.inspection_minor == 137 and row.line_minor == expected_repair + 137
				and line.get("amount_minor") == expected_repair + 137)
			_check("cash and consumption values survive together for " + key,
				row.materials.size() == 1 and row.materials[0].purchase_minor == 2299
				and row.materials[0].consumption_minor == 14)
			_check("labor mode, minutes, rate and cost are preserved for " + key,
				row.labor_mode == labor_mode and row.labor_minutes == 30
				and row.labor_rate_minor_per_hour == (0 if labor_mode == "diy" else 4500)
				and row.labor_minor == (0 if labor_mode == "diy" else 2250))
			_check("inspection evidence and material source provenance are retained for " + key,
				row.inspection_basis == "scenario_assumption" and row.inspection_evidence == REPAIR_EVIDENCE
				and row.inspection_measurements.covering_area_milli_sq_in == 10500
				and row.materials[0].source.source_name == "Vortex Hobbies"
				and row.materials[0].source.source_url.begins_with("https://")
				and row.labor_source.description is String)


func _test_identity_binding_and_json_roundtrip() -> void:
	var fixture := _repair_fixture("paid", "consumption", "identity-choice")
	var report: Dictionary = fixture.ledger.report.duplicate(true)
	var normalized: Array[Dictionary] = RepairDetails.normalize(report)
	var roundtrip_value: Variant = JSON.parse_string(JSON.stringify(report, "", true, true))
	var roundtrip_rows: Array[Dictionary] = RepairDetails.normalize(roundtrip_value)
	_check("JSON-roundtripped incident archive preserves its selected repair detail",
		normalized.size() == 1 and roundtrip_rows.size() == 1
		and roundtrip_rows[0].repair_minor == normalized[0].repair_minor
		and roundtrip_rows[0].inspection_minor == normalized[0].inspection_minor
		and roundtrip_rows[0].materials[0].purchase_minor == normalized[0].materials[0].purchase_minor
		and roundtrip_rows[0].materials[0].source.source_name == normalized[0].materials[0].source.source_name)
	for field: String in ["incident_id", "aircraft_id", "source_sha256", "catalog_hash"]:
		var mismatched: Dictionary = report.duplicate(true)
		mismatched.inspections[0][field] = "different-%s" % field
		_check("receipt %s must match the report identity" % field,
			RepairDetails.normalize(mismatched).is_empty())
	var mismatched_catalog: Dictionary = report.duplicate(true)
	mismatched_catalog.catalog_hash = "different-catalog-hash"
	_check("receipt catalog hash must match the report catalog snapshot",
		RepairDetails.normalize(mismatched_catalog).is_empty())
	var mismatched_aircraft: Dictionary = report.duplicate(true)
	mismatched_aircraft.repair_choices[0].provenance.aircraft_id = "another-aircraft"
	_check("choice provenance aircraft must match the report identity",
		RepairDetails.normalize(mismatched_aircraft).is_empty())


func _test_offer_metadata_compatibility() -> void:
	var fixture := _repair_fixture("paid", "cash", "offer-metadata")
	var report: Dictionary = fixture.ledger.report.duplicate(true)
	var line := _line(report, COMPONENT_ID)
	line["product_name"] = "Illustrative product name"
	line["product_brand"] = "Illustrative brand"
	line["product_sku"] = "EXAMPLE-SKU"
	line["package_description"] = "One repair kit"
	line["sold_package_quantity"] = 1
	line["offer_amount_minor"] = 1299
	_check("frozen offer metadata does not invalidate selected repair details",
		RepairDetails.normalize(report).size() == 1
		and RepairDetails.normalize(report)[0].repair_minor == 4549)


func _test_supersession_and_ambiguity() -> void:
	var fixture := _repair_fixture("paid", "cash", "initial-choice")
	var report: Dictionary = fixture.ledger.report.duplicate(true)
	_check("initial choice is current before a later inspection", RepairDetails.normalize(report).size() == 1)
	var later_manual := _receipt(fixture.ledger, "later-manual-repair")
	later_manual.components[COMPONENT_ID] = {
		"disposition": "repair", "quantity": 1, "repair_minor": 2000, "inspection_minor": 137,
		"damage_flags": [], "evidence": "Later explicit manual repair decision.",
	}
	var applied: Dictionary = fixture.ledger.apply_inspection(later_manual)
	_check("later manual repair inspection is accepted", applied.get("ok", false), str(applied))
	_check("old recipe choice is hidden when a newer receipt owns the current repair line",
		_line(fixture.ledger.report, COMPONENT_ID).get("action") == "repair"
		and RepairDetails.normalize(fixture.ledger.report).is_empty())

	var replaced_fixture := _repair_fixture("paid", "cash", "replacement-choice")
	var later_replacement := _receipt(replaced_fixture.ledger, "later-replacement")
	later_replacement.components[COMPONENT_ID] = {
		"disposition": "replace", "quantity": 1, "damage_flags": [],
		"evidence": "Later explicit replacement decision.",
	}
	var replacement_applied: Dictionary = replaced_fixture.ledger.apply_inspection(later_replacement)
	_check("later replacement inspection is accepted", replacement_applied.get("ok", false), str(replacement_applied))
	_check("superseded repair choice is hidden after the current action becomes replacement",
		_line(replaced_fixture.ledger.report, COMPONENT_ID).get("action") == "replacement"
		and RepairDetails.normalize(replaced_fixture.ledger.report).is_empty())

	var duplicate: Dictionary = fixture.ledger.report.duplicate(true)
	duplicate.repair_choices.append(duplicate.repair_choices[0].duplicate(true))
	_check("duplicate choice records are treated as ambiguous and hidden", RepairDetails.normalize(duplicate).is_empty())
	var action_mismatch: Dictionary = _repair_fixture("diy", "cash", "action-mismatch").ledger.report.duplicate(true)
	_line(action_mismatch, COMPONENT_ID).action = "replacement"
	_check("choice is hidden if the current calculator line no longer says repair", RepairDetails.normalize(action_mismatch).is_empty())


func _test_malformed_optional_data() -> void:
	var fixture := _repair_fixture("diy", "cash", "malformed-data")
	var bad_amount: Dictionary = fixture.ledger.report.duplicate(true)
	_line(bad_amount, COMPONENT_ID).amount_minor = NAN
	_check("non-finite current line amount cannot create a repair detail", RepairDetails.normalize(bad_amount).is_empty())

	var bad_material: Dictionary = fixture.ledger.report.duplicate(true)
	bad_material.repair_choices[0].provenance.materials[0].purchase_minor = NAN
	_check("non-finite package amount is omitted", RepairDetails.normalize(bad_material).is_empty())
	bad_material = fixture.ledger.report.duplicate(true)
	bad_material.repair_choices[0].provenance.materials[0].package_price_minor = 2299.5
	_check("fractional cents are omitted", RepairDetails.normalize(bad_material).is_empty())

	var mismatched: Dictionary = fixture.ledger.report.duplicate(true)
	mismatched.repair_choices[0].provenance.repair_minor += 1
	_check("mismatched provenance subtotal is omitted", RepairDetails.normalize(mismatched).is_empty())

	var malformed_archive: Dictionary = fixture.ledger.report.duplicate(true)
	malformed_archive.repair_choices = "malformed optional archive field"
	_check("malformed optional choice history does not throw or show an amount", RepairDetails.normalize(malformed_archive).is_empty())
	malformed_archive = fixture.ledger.report.duplicate(true)
	malformed_archive.inspections = "malformed optional archive field"
	_check("malformed optional receipt history does not throw or show an amount", RepairDetails.normalize(malformed_archive).is_empty())


func _repair_fixture(labor_mode: String, costing_basis: String, inspection_id: String) -> Dictionary:
	var ledger := Incident.new()
	ledger.begin("jensen-das-ugly-stik-60", "")
	ledger._last_tick = 20
	ledger._queue_assessment(20)
	var receipt_value := _receipt(ledger, inspection_id)
	receipt_value.components[COMPONENT_ID].inspection_minor = 137
	var repair_inspection := {
		"format": "openrc-repair-inspection v1",
		"basis": "scenario_assumption",
		"components": {
			COMPONENT_ID: {
				"status": "inspected",
				"damage_class": "covering_only",
				"quantity": 1,
				"replacement_comparable": false,
				"measurements": {"covering_area_milli_sq_in": 10500},
				"labor_minutes": 30,
				"evidence": REPAIR_EVIDENCE,
			},
		},
	}
	var applied: Dictionary = ledger.apply_repair_choice(receipt_value, repair_inspection, COMPONENT_ID,
		"covering-film-patch", labor_mode, costing_basis)
	return {"ledger": ledger, "applied": applied}


func _receipt(ledger: RefCounted, inspection_id: String) -> Dictionary:
	var context: Dictionary = ledger.inspection_context()
	var receipt := {
		"format": "openrc-accident-inspection v1",
		"inspection_id": inspection_id,
		"incident_id": context.identity.incident_id,
		"aircraft_id": context.identity.aircraft_id,
		"source_sha256": context.identity.source_sha256,
		"catalog_hash": context.catalog_hash,
		"expected_revision": context.revision,
		"full_inspection": true,
		"total_loss": false,
		"basis": "scenario_assumption",
		"evidence": "Deterministic scenario test; not physical validation.",
		"components": {},
	}
	for component: Dictionary in ledger.dossier.components:
		receipt.components[component.id] = {
			"disposition": "reuse",
			"quantity": component.quantity,
			"damage_flags": [],
			"evidence": "Explicit scenario component conclusion.",
		}
	return receipt


func _line(report: Dictionary, component_id: String) -> Dictionary:
	var lines: Variant = report.get("lines", [])
	if not lines is Array:
		return {}
	for value: Variant in lines:
		if value is Dictionary and value.get("id") == component_id:
			return value
	return {}


func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL " + label + " " + detail)

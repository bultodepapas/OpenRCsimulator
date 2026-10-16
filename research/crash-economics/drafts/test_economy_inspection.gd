extends SceneTree
const Incident = preload("res://economy/incident.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	var ledger := Incident.new()
	ledger.begin("jensen-das-ugly-stik-60", "")
	ledger._last_tick = 10
	ledger._assessment.unresolved = ["Crash inspection pending; component survival is not yet established."]
	ledger._queue_assessment(10)
	var first := receipt(ledger, "assessment-1")
	first.components.fuselage_servos = row("reuse", 2)
	var result := ledger.apply_inspection(first)
	check("explicit full assessment applies", result.get("ok", false))
	check("two inspected servos deduct once from baseline loss", ledger.report.get("total_minor") == 92635 and ledger.report.get("salvage_minor") == 6798)
	var before := ledger.report.duplicate(true)
	check("duplicate inspection is idempotent", ledger.apply_inspection(first).get("duplicate", false) and ledger.report == before)
	var forged := first.duplicate(true)
	forged.components.fuselage_servos.quantity = 3
	check("ID cannot be reused with different conclusions", not ledger.apply_inspection(forged).get("ok", true) and ledger.report == before)
	var stale := receipt(ledger, "stale")
	stale.expected_revision -= 1
	check("stale assessment cannot overwrite newer evidence", not ledger.apply_inspection(stale).get("ok", true) and ledger.report == before)
	var wrong := receipt(ledger, "wrong")
	wrong.source_sha256 = "0".repeat(64)
	check("other physical configuration cannot receive credits", not ledger.apply_inspection(wrong).get("ok", true))
	var omitted := receipt(ledger, "omitted")
	omitted.components.erase("receiver")
	check("full inspection must include every row", not ledger.apply_inspection(omitted).get("ok", true))
	var later := receipt(ledger, "heat-evidence")
	later.components.fuselage_servos.damage_flags = ["thermal_damage"]
	check("later evidenced heat damage revokes salvage", ledger.apply_inspection(later).get("ok", false) and ledger.report.get("salvage_minor") == 0 and ledger.report.get("total_minor") == 99433)
	var undo := receipt(ledger, "undo-heat")
	undo.components.fuselage_servos = row("reuse", 2)
	check("removing flags cannot restore previously disqualified salvage", not ledger.apply_inspection(undo).get("ok", true))
	var damaged_pack := receipt(ledger, "damaged-pack")
	damaged_pack.components.receiver_battery = row("reuse", 1)
	damaged_pack.components.receiver_battery.damage_flags = ["lipo_damage"]
	check("explicit damaged-pack conclusion forbids reuse without requiring flame", not ledger.apply_inspection(damaged_pack).get("ok", true))
	ledger._confirmed_facts.propeller_strike = {tick = 10}
	var prop := receipt(ledger, "repair-prop")
	prop.components.propeller = row("repair", 1)
	prop.components.propeller.repair_minor = 1
	check("confirmed broken prop cannot be cheaply repaired", not ledger.apply_inspection(prop).get("ok", true))
	var fractional := receipt(ledger, "fractional")
	fractional.components.receiver.quantity = 0.5
	check("fractional installed units rejected", not ledger.apply_inspection(fractional).get("ok", true))
	ledger._assessment.unresolved.append("Contact journal limit reached; inspection required.")
	check("full inspection retains missing-history uncertainty", ledger.apply_inspection(receipt(ledger, "overflow")).get("ok", false) and ledger.report.get("total_minor") == null)
	check("receipt provenance is frozen in report", ledger.report.get("inspections", []).size() == 3 and str(ledger.report.get("assumptions")).contains("scenario_assumption"))
	var report_copy := ledger.report.duplicate(true)
	for i in range(ledger._inspections.size(), Incident.MAX_INSPECTIONS):
		check("bounded history accepts distinct receipt %d" % i, ledger.apply_inspection(receipt(ledger, "bounded-%d" % i)).get("ok", false))
	report_copy = ledger.report.duplicate(true)
	check("history overflow is atomic", not ledger.apply_inspection(receipt(ledger, "over-limit")).get("ok", true) and ledger.report == report_copy)
	ledger.begin("jensen-das-ugly-stik-60", "")
	check("reset clears receipts and non-reuse flags", ledger._inspections.is_empty() and ledger._reuse_blocked.is_empty() and ledger.report.is_empty())
	print("%d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func receipt(ledger: RefCounted, id: String) -> Dictionary:
	var context: Dictionary = ledger.inspection_context()
	var value := {format = "openrc-accident-inspection v1", inspection_id = id,
		incident_id = context.identity.incident_id, aircraft_id = context.identity.aircraft_id,
		source_sha256 = context.identity.source_sha256, catalog_hash = context.catalog_hash,
		expected_revision = context.revision, full_inspection = true, total_loss = true,
		basis = "scenario_assumption", evidence = "Deterministic test fixture, not physical validation.", components = {}}
	# begin() supports an omitted caller hash, while receipts always bind the loaded source.
	if value.source_sha256.is_empty():
		ledger._identity.source_sha256 = ledger.dossier.source_sha256
		value.source_sha256 = ledger.dossier.source_sha256
	for component: Dictionary in ledger.dossier.components:
		value.components[component.id] = row("replace", component.quantity)
	return value

func row(disposition: String, quantity: int) -> Dictionary:
	return {disposition = disposition, quantity = quantity, damage_flags = [], evidence = "Explicit scenario component conclusion."}

func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL " + label)

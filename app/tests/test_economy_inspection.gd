extends SceneTree
const Incident = preload("res://economy/incident.gd")
const AircraftData = preload("res://physics/aircraft_data.gd")
const ContactContract = preload("res://physics/aircraft_contact_contract.gd")
const ContactEvents = preload("res://sim/aircraft_contact_events.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_test_repair_choices()
	_test_corsair_damage()
	var ledger := Incident.new()
	ledger.begin("jensen-das-ugly-stik-60", "")
	ledger._last_tick = 10
	ledger._assessment.unresolved = ["Crash inspection pending; component survival is not yet established."]
	ledger._queue_assessment(10)
	var first := receipt(ledger, "assessment-1")
	first.components.fuselage_servos = row("reuse", 2)
	var result: Dictionary = ledger.apply_inspection(first)
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
	for field: String in ["incident_id", "aircraft_id", "catalog_hash"]:
		var mismatch := receipt(ledger, "wrong-" + field)
		mismatch[field] = "different"
		check("identity mismatch is atomic: " + field, not ledger.apply_inspection(mismatch).get("ok", true) and ledger.report == before)
	for flags: Array in [["unknown_flag"], ["thermal_damage", "thermal_damage"], ["structural_damage"]]:
		var invalid_flags := receipt(ledger, "bad-flags")
		invalid_flags.components.receiver = row("reuse", 1)
		invalid_flags.components.receiver.damage_flags = flags
		check("unknown, duplicate or contradictory structural flags rejected", not ledger.apply_inspection(invalid_flags).get("ok", true) and ledger.report == before)
	var bad_comparator_type := receipt(ledger, "bad-comparator-type")
	bad_comparator_type.components.receiver.replacement_comparable = "false"
	check("replacement comparability receipt field requires a boolean", not ledger.apply_inspection(bad_comparator_type).get("ok", true) and ledger.report == before)
	var misplaced_comparator := receipt(ledger, "misplaced-comparator")
	misplaced_comparator.components.receiver.replacement_comparable = false
	check("replacement comparability receipt field requires an explicit repair", not ledger.apply_inspection(misplaced_comparator).get("ok", true) and ledger.report == before)
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
	ledger._queue_assessment(30)
	ledger._last_tick = 30
	ledger._assessment.unresolved = ["Impact or surface contact requires structural inspection."]
	var partial := receipt(ledger, "partial-inspection")
	partial.full_inspection = false
	partial.components = {"receiver": row("reuse", 1)}
	check("partial receipt cannot invent a whole-aircraft writeoff", not ledger.apply_inspection(partial).get("ok", true))
	partial.total_loss = false
	check("partial receipt preserves unresolved structural inspection", ledger.apply_inspection(partial).get("ok", false) and not ledger.report.get("complete", true) and ledger.report.get("total_minor") == null)
	print("%d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func _test_repair_choices() -> void:
	var ledger := Incident.new()
	ledger.begin("jensen-das-ugly-stik-60", "")
	ledger._last_tick = 20
	ledger._queue_assessment(20)
	var receipt_value := receipt(ledger, "film-repair")
	receipt_value.total_loss = false
	for id: String in receipt_value.components:
		receipt_value.components[id].disposition = "reuse"
	var component_id := "covered_airframe_and_installation_hardware"
	var priced_components: Array = ledger.dossier.components
	for index: int in range(priced_components.size()):
		var part: Dictionary = priced_components[index]
		if part.id == component_id:
			part.unit_minor = 100
			part.low_unit_minor = 100
			part.high_unit_minor = 100
			priced_components[index] = part
	ledger.dossier.components = priced_components
	receipt_value.components[component_id].inspection_minor = 125
	var repair_inspection := {format = "openrc-repair-inspection v1", basis = "scenario_assumption",
		components = {component_id: {status = "inspected", damage_class = "covering_only", quantity = 1,
			replacement_comparable = false, measurements = {covering_area_milli_sq_in = 10500},
			labor_minutes = 30, evidence = "Inspected 10.5 sq in patch; structure intact. Synthetic test case."}}}
	var result: Dictionary = ledger.apply_repair_choice(receipt_value, repair_inspection, component_id, "covering-film-patch", "paid", "consumption")
	if not result.get("ok", false):
		printerr(result)
	var repair_line: Dictionary = {}
	for line: Dictionary in ledger.report.get("lines", []):
		if line.get("id") == component_id:
			repair_line = line
	check("incomparable replacement keeps selected repair and inspection amounts exact", result.get("ok", false) and ledger.report.get("complete", false) and ledger.report.get("total_minor") == 2389 and ledger.report.get("replacement_minor") == null and repair_line.get("action") == "repair" and repair_line.get("amount_minor") == 2389 and ledger.report.inspections[0].components[component_id].replacement_comparable == false)
	check("repair source and recipe identity frozen alongside report", ledger.report.get("repair_choices", []).size() == 1 and ledger.report.repair_choices[0].recipe_book_sha256.length() == 64)
	var before := ledger.report.duplicate(true)
	check("duplicate repair choice never bills or appends provenance twice", ledger.apply_repair_choice(receipt_value, repair_inspection, component_id, "covering-film-patch", "paid", "consumption").get("duplicate", false) and ledger.report == before)
	var changed := repair_inspection.duplicate(true)
	changed.components[component_id].measurements.covering_area_milli_sq_in = 10501
	check("same rounded price with different repair evidence cannot reuse receipt ID", not ledger.apply_repair_choice(receipt_value, changed, component_id, "covering-film-patch", "paid", "consumption").get("ok", true) and ledger.report == before)
	var structural := receipt(ledger, "structural-contradiction")
	structural.total_loss = false
	structural.components[component_id].damage_flags = ["structural_damage"]
	check("structural flag cannot be hidden by covering-only planner input", not ledger.apply_repair_choice(structural, repair_inspection, component_id, "covering-film-patch", "diy", "cash").get("ok", true) and ledger.report == before)
	ledger.archive_path = "user://test_economy_inspection.json"
	check("inspection and recipe provenance persist outside physics callbacks", ledger.flush() == OK)
	var reader := Incident.new()
	reader.archive_path = ledger.archive_path
	var archived: Dictionary = reader.load_archive()
	check("archive keeps repair amount, unmatched scope and inspection fee", archived.get("repair_choices", []).size() == 1 and archived.repair_choices[0].costing_basis == "consumption" and archived.get("total_minor") == 2389 and archived.get("replacement_minor") == null and archived.inspections[0].components[component_id].replacement_comparable == false)
	for field: String in ["inspections", "repair_choices"]:
		var broken := archived.duplicate(true)
		broken[field] = "malformed optional provenance"
		var file := FileAccess.open(ledger.archive_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(broken))
		file.close()
		check("archive rejects malformed " + field, reader.load_archive().is_empty())
	DirAccess.remove_absolute(ledger.archive_path)

func receipt(ledger: RefCounted, id: String) -> Dictionary:
	var context: Dictionary = ledger.inspection_context()
	var value := {format = "openrc-accident-inspection v1", inspection_id = id,
		incident_id = context.identity.incident_id, aircraft_id = context.identity.aircraft_id,
		source_sha256 = context.identity.source_sha256, catalog_hash = context.catalog_hash,
		expected_revision = context.revision, full_inspection = true, total_loss = true,
		basis = "scenario_assumption", evidence = "Deterministic test fixture, not physical validation.", components = {}}
	for component: Dictionary in ledger.dossier.components:
		value.components[component.id] = row("replace", component.quantity)
	return value

## F4U-11-R2: accepted events open local inspections; only an explicit disposition
## can price an airframe/control replacement. These are software scenarios.
func _test_corsair_damage() -> void:
	var loaded := AircraftData.load_file("res://data/aircraft/f4u_corsair_250.json")
	check("Corsair damage fixtures load the physical model", loaded.ok)
	if not loaded.ok: return
	var bindings := ContactContract.describe(loaded.model, true)
	var cases := {
		"probe_wing_left_tip": ["wing_left", "aileron_servo_left", "flap_servos_left", "wing_joiner"],
		"probe_gull_right_bottom": ["wing_right", "wing_joiner", "flap_servos_right", "gear_main_right", "retract_air"],
		"probe_stabilizer_left_aft": ["horizontal_tail", "elevator_servos", "fuselage_rear"],
		"probe_fin_aft_upper": ["vertical_tail", "rudder_servo", "fuselage_rear"],
	}
	for probe_id: String in cases:
		var ledger := Incident.new()
		ledger.begin("f4u-corsair-250", "")
		var index := -1
		for i in bindings.hull_probes.size():
			if bindings.hull_probes[i].id == probe_id: index = i
		check(probe_id + " is an accepted contact identity", index >= 0)
		if index < 0: continue
		var events: Array = ContactEvents.hull_events([{index = index, new = true, depth_m = 0.001}], bindings, PackedStringArray(), 10).events
		ledger.observe({tick = 10, events = events}, bindings, false)
		ledger.evaluate_pending()
		var expected: Dictionary = {}
		for id: String in cases[probe_id]: expected[id] = {disposition = "inspect"}
		check(probe_id + " inspects exactly the local installation", ledger._assessment.components == expected)
		check(probe_id + " cannot turn presentation damage into a bill", ledger.report.get("known_subtotal_minor") == 0 and ledger.report.get("total_minor") == null)
		if probe_id == "probe_wing_left_tip":
			var decision := receipt(ledger, "one-left-servo")
			decision.full_inspection = false
			decision.total_loss = false
			decision.components = {"aileron_servo_left": row("replace", 1)}
			check("one inspected left servo costs one proxy, not all ten", ledger.apply_inspection(decision).ok and ledger.report.known_subtotal_minor == 10339)
			check("right controls remain untouched by left-only inspection", not ledger._assessment.components.has("aileron_servo_right") and not ledger._assessment.components.has("flap_servos_right"))
		var saved := ledger.checkpoint(10, bindings)
		var restored := Incident.new()
		restored.begin("f4u-corsair-250", "")
		var prepared := restored.prepare_restore(saved, 10, bindings)
		if not prepared.get("ok", false): print(prepared)
		check(probe_id + " damage matrix survives checkpoint validation", prepared.get("ok", false))
		if prepared.get("ok", false):
			restored.commit_restore(prepared)
			check(probe_id + " restores the same report", restored.report == ledger.report)
	# Legacy/self-referencing lists must never downgrade the mandatory propeller
	# decision, either when observed or when checkpoint evidence is reconstructed.
	for self_reference: bool in [false, true]:
		var ledger := Incident.new()
		ledger.begin("f4u-corsair-250", "")
		if self_reference: ledger.dossier.propeller_inspection_ids.append("propeller")
		var strike := ContactEvents.strike_event({tick = 10, rpm = 4000.0,
			point_ned = PackedFloat64Array([0.0, 0.0, 0.0]), velocity_ned = PackedFloat64Array([1.0, 0.0, 0.0])}, 10, "test", bindings)
		ledger.observe({tick = 10, events = [strike]}, bindings, false)
		ledger.evaluate_pending()
		check("Corsair strike retains one replacement, self-reference=%s" % self_reference,
			ledger._assessment.components.propeller == {disposition = "replace", quantity = 1})
		check("Corsair strike inspects engine without automatically purchasing it",
			ledger._assessment.components.engine_moki_s250.disposition == "inspect" and ledger.report.total_minor == null)
		var saved := ledger.checkpoint(10, bindings)
		check("Corsair propeller evidence restores without downgrade", ledger.prepare_restore(saved, 10, bindings).get("ok", false))
		var before := ledger.report.duplicate(true)
		ledger.observe({tick = 10, events = [strike]}, bindings, false)
		ledger.evaluate_pending()
		check("Corsair repeated strike never rebills", ledger.report == before)


func row(disposition: String, quantity: int) -> Dictionary:
	return {disposition = disposition, quantity = quantity, damage_flags = [], evidence = "Explicit scenario component conclusion."}

func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL " + label)

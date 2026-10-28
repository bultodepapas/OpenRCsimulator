extends SceneTree
const Incident = preload("res://economy/incident.gd")
const StateCodec = preload("res://economy/checkpoint.gd")
const Events = preload("res://sim/aircraft_contact_events.gd")
const Settlement = preload("res://economy/settlement.gd")
const MainScene = preload("res://main.tscn")
var checks := 0
var failures := 0


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL: " + label)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Variant = MainScene.instantiate()
	main.crash_effects_enabled = false
	main.accident_archive_path = "user://test_economy_checkpoint.json"
	root.add_child(main)
	main.set_process(false)
	var session: Variant = main.session
	session.input_enabled = false
	session.set_physics_process(false)
	session.sim.set_physics_process(false)
	var bindings: Dictionary = session.contact_contract()
	_unit_cases(bindings)
	_repair_cases(bindings)
	_settlement_cases()
	var healthy: Dictionary = main.checkpoint()
	check("healthy visual checkpoint is nonempty and keeps its existing format",
		not healthy.is_empty() and healthy.get("format") == "openrc-visual-checkpoint v1")
	var ledger: Variant = main._accident_incident
	var tick: int = session.sim.tick
	var event: Dictionary = Events.hull_events([{index = 0, new = true, depth_m = 0.001}], bindings, PackedStringArray(), tick).events[0]
	ledger.observe({tick = tick, events = [event]}, bindings, false)
	ledger.evaluate_pending()
	var receipt := _receipt(ledger, "pair-inspection", "replace", ["electrical_damage"])
	check("paired fixture accepts explicit receiver inspection", ledger.apply_inspection(receipt).ok)
	var before: Dictionary = ledger.report.duplicate(true)
	var paired: Dictionary = main.checkpoint()
	check("damaged active flight pairs physics and economics", paired.get("format") == StateCodec.ENVELOPE)
	if not paired.is_empty():
		var initial_state: PackedFloat64Array = session.sim.state.duplicate()
		var restored: Dictionary = main.restore_checkpoint(bytes_to_var(var_to_bytes(paired)))
		check("paired native checkpoint restores", restored.get("ok", false))
		check("paired restore preserves exact physics", session.sim.state == initial_state)
		check("paired restore preserves report identity and receipt", ledger.report == before)
		main._on_accident_contacts()
		main._update_accident_report()
		check("paired history does not acquire a legacy missing-history caveat", ledger.report == before)
		check("restored inspection ID remains idempotent", ledger.apply_inspection(receipt).get("duplicate", false))
		var invalid: Dictionary = paired.duplicate(true)
		invalid.economy.ledger.revision += 1
		check("tampered outer payload is atomic", not main.restore_checkpoint(invalid).ok and ledger.report == before and session.sim.state == initial_state)
		invalid = paired.duplicate(true)
		invalid.economy.presentation = {ground_stable = true, settled_pending = true}
		invalid = StateCodec.seal(invalid)
		check("cannot display settled cost before required dwell", not main.restore_checkpoint(invalid).ok and ledger.report == before)
		var invalid_physics: Dictionary = paired.duplicate(true)
		invalid_physics.visual.physics.configuration = "invalid-owner-configuration"
		# Seal both envelopes to exercise the physics owner's rejection after economics preflight.
		var VC = preload("res://app_state/visual_checkpoint.gd")
		invalid_physics.visual.payload_sha256 = VC._payload_sha256(invalid_physics.visual.physics, invalid_physics.visual.timeline, invalid_physics.visual.field_identity)
		invalid_physics = StateCodec.seal(invalid_physics)
		check("physics rejection retains live economics", not main.restore_checkpoint(invalid_physics).ok and ledger.report == before and session.sim.state == initial_state)
		ledger._catalog_hash = "changed-catalog"
		check("price refresh refuses resume before altering physics", not main.restore_checkpoint(paired).ok and session.sim.state == initial_state)
		ledger._catalog_hash = before.catalog_hash
		check("legacy physics checkpoint still restores", session.restore_checkpoint(session.checkpoint()))
		check("legacy restore resets paired-history marker", not main._accident_paired_history)
	main.queue_free()
	await process_frame
	await process_frame
	DirAccess.remove_absolute("user://test_economy_checkpoint.json")
	DirAccess.remove_absolute("user://test_economy_checkpoint.json.tmp")
	print("economics checkpoint: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _unit_cases(bindings: Dictionary) -> void:
	var ledger := Incident.new()
	ledger.begin("jensen-das-ugly-stik-60", "")
	var empty := ledger.checkpoint(0, bindings)
	check("healthy ledger captures without fabricating damage", not empty.is_empty() and empty.revision == 0)
	var raw := {tick = 10, rpm = 6000.0, point_ned = PackedFloat64Array([0, 0, 0]), velocity_ned = PackedFloat64Array([8, 0, 0])}
	var strike := Events.strike_event(raw, 10, "checkpoint-test", bindings)
	ledger.observe({tick = 10, events = [strike]}, bindings, false)
	ledger.evaluate_pending()
	var first := _receipt(ledger, "first", "replace", ["electrical_damage"])
	var applied := ledger.apply_inspection(first)
	if not applied.ok:
		print(applied)
	check("fixture inspection succeeds", applied.ok)
	var original := ledger.report.duplicate(true)
	var saved := ledger.checkpoint(10, bindings)
	check("active damaged ledger captures", not saved.is_empty())
	var destination := Incident.new()
	destination.begin("jensen-das-ugly-stik-60", "")
	var staged := destination.prepare_restore(bytes_to_var(var_to_bytes(saved)), 10, bindings)
	check("prepare is detached and accepts native roundtrip", staged.ok and destination.report.is_empty())
	if staged.ok:
		destination.commit_restore(staged)
		check("restored ledger calculates identical report", destination.report == original)
		check("restored receipt deduplicates", destination.apply_inspection(first).get("duplicate", false))
		destination.observe({tick = 10, events = [strike]}, bindings, false)
		destination.evaluate_pending()
		check("duplicate contact cannot rebill after restore", destination.report == original)
		check("thermal/electrical restrictions survive restore", not destination.apply_inspection(_receipt(destination, "undo", "reuse", [])).ok)
	for field: String in ["catalog_hash", "recipe_hash", "bindings_hash"]:
		var bad := saved.duplicate(true)
		bad[field] = "changed"
		check("reject changed " + field, not destination.prepare_restore(StateCodec.seal(bad), 10, bindings).ok)
	check("reject wrong paired tick", not destination.prepare_restore(saved, 11, bindings).ok)
	var bad := saved.duplicate(true)
	bad.journal.append(bad.journal[0])
	check("reject duplicate journal even with a recomputed digest", not destination.prepare_restore(StateCodec.seal(bad), 10, bindings).ok)
	bad = saved.duplicate(true)
	bad.blocked.clear()
	check("reject erased inspection restrictions", not destination.prepare_restore(StateCodec.seal(bad), 10, bindings).ok)
	bad = saved.duplicate(true)
	bad.assessment.components.receiver.quantity = 0
	check("reject zeroed inspected quantity", not destination.prepare_restore(StateCodec.seal(bad), 10, bindings).ok)
	bad = saved.duplicate(true)
	bad.assessment.components.erase("receiver")
	check("reject erased inspected decision", not destination.prepare_restore(StateCodec.seal(bad), 10, bindings).ok)
	bad = saved.duplicate(true)
	bad.assessment.components.erase("propeller")
	check("reject erased confirmed propeller decision", not destination.prepare_restore(StateCodec.seal(bad), 10, bindings).ok)
	bad = saved.duplicate(true)
	bad.assessment.total_loss = true
	check("reject total loss without a full inspection", not destination.prepare_restore(StateCodec.seal(bad), 10, bindings).ok)
	bad = saved.duplicate(true)
	bad.assessment.unresolved.clear()
	check("partial inspection cannot erase strike caveat", not destination.prepare_restore(StateCodec.seal(bad), 10, bindings).ok)
	bad = saved.duplicate(true)
	bad.assessment.components.receiver = {disposition = "repair", quantity = 1, repair_minor = 0}
	check("reject changed decision outside receipt evidence", not destination.prepare_restore(StateCodec.seal(bad), 10, bindings).ok)
	bad = saved.duplicate(true)
	bad.assessment.components.propeller = {disposition = "reuse", quantity = 1}
	check("reject reuse of confirmed broken prop", not destination.prepare_restore(StateCodec.seal(bad), 10, bindings).ok)
	bad = saved.duplicate(true)
	bad.inspections.append(bad.inspections[0])
	check("reject duplicate inspection history", not destination.prepare_restore(StateCodec.seal(bad), 10, bindings).ok)
	bad = saved.duplicate(true)
	bad.assessment_tick = 11
	check("reject evidence ahead of owner clock", not destination.prepare_restore(StateCodec.seal(bad), 10, bindings).ok)
	bad = saved.duplicate(true)
	bad.unexpected = true
	check("reject unknown schema fields", not destination.prepare_restore(StateCodec.seal(bad), 10, bindings).ok)
	bad = saved.duplicate(true)
	bad.assessment.components.receiver.inspection_minor = NAN
	check("reject nonfinite native inputs", not destination.prepare_restore(bad, 10, bindings).ok)
	check("reject objects without deserializing them", not StateCodec.native_data({object = RefCounted.new()}))
	var cyclic: Array = []
	cyclic.append(cyclic)
	check("cyclic native container is bounded", not StateCodec.native_data(cyclic))
	cyclic.clear()
	ledger.terminal = true
	ledger._assessment.terminal = true
	check("terminal crash remains archive-only until crash state can resume", ledger.checkpoint(10, bindings).is_empty())
	# Separate diagnostic overflow facts remain resumable without dropping their caveat.
	ledger.begin("jensen-das-ugly-stik-60", "")
	for tick in range(1, 131):
		var event: Dictionary = Events.hull_events([{index = 0, new = true, depth_m = 0.001}], bindings, PackedStringArray(), tick).events[0]
		ledger.observe({tick = tick, events = [event]}, bindings, false)
	ledger.evaluate_pending()
	check("bounded overflow ledger roundtrips", destination.prepare_restore(ledger.checkpoint(130, bindings), 130, bindings).ok)
	ledger.begin("jensen-das-ugly-stik-60", "")
	ledger.observe({tick = 5, events = [], active_hull_ids = PackedStringArray(["legacy-active"])}, bindings, false, true)
	ledger.evaluate_pending()
	check("legacy active contact records missing history without inventing an impact", ledger.journal.is_empty() and str(ledger.report.unresolved).contains("earlier damage history"))
	bad = ledger.checkpoint(5, bindings)
	bad.assessment.unresolved.clear()
	check("legacy missing-history damage cannot become a zero bill", not ledger.prepare_restore(StateCodec.seal(bad), 5, bindings).ok)


func _receipt(ledger: Variant, id: String, disposition: String, flags: Array) -> Dictionary:
	var context: Dictionary = ledger.inspection_context()
	return {format = "openrc-accident-inspection v1", inspection_id = id,
		incident_id = context.identity.incident_id, aircraft_id = context.identity.aircraft_id,
		source_sha256 = context.identity.source_sha256, catalog_hash = context.catalog_hash,
		expected_revision = context.revision, full_inspection = false, total_loss = false,
		basis = "scenario_assumption", evidence = "Checkpoint arithmetic fixture, not physical evidence.",
		components = {"receiver": {disposition = disposition, quantity = 1, damage_flags = flags, evidence = "Explicit fixture."}}}


func _repair_cases(bindings: Dictionary) -> void:
	var ledger := Incident.new()
	ledger.begin("jensen-das-ugly-stik-60", "")
	var event: Dictionary = Events.hull_events([{index = 0, new = true, depth_m = 0.001}], bindings, PackedStringArray(), 20).events[0]
	ledger.observe({tick = 20, events = [event]}, bindings, false)
	var no_inspection := ledger.checkpoint(20, bindings)
	no_inspection.assessment.unresolved.clear()
	check("uninspected hull contact cannot become a complete zero bill", not ledger.prepare_restore(StateCodec.seal(no_inspection), 20, bindings).ok)
	var mapped_contact := ledger.checkpoint(20, bindings)
	check("CR-39d mapped hull contact checkpoints its part inspection", mapped_contact.assessment.components.get("covered_airframe_and_installation_hardware") == {disposition = "inspect"}
		and ledger.prepare_restore(mapped_contact, 20, bindings).ok)
	mapped_contact.assessment.components["receiver"] = {disposition = "inspect"}
	check("CR-39d unmapped part cannot claim a contact-derived inspection", not ledger.prepare_restore(StateCodec.seal(mapped_contact), 20, bindings).ok)
	var component := "covered_airframe_and_installation_hardware"
	var priced_components: Array = ledger.dossier.components
	for index: int in range(priced_components.size()):
		var part: Dictionary = priced_components[index]
		if part.id == component:
			part.unit_minor = 100
			part.low_unit_minor = 100
			part.high_unit_minor = 100
			priced_components[index] = part
	ledger.dossier.components = priced_components
	var receipt := _receipt(ledger, "checkpoint-film", "reuse", [])
	receipt.components = {component: {disposition = "inspect", quantity = 1, inspection_minor = 77, damage_flags = [], evidence = "Fixture: intact structure, covering tear."}}
	var inspected := {format = "openrc-repair-inspection v1", basis = "scenario_assumption",
		components = {component: {status = "inspected", damage_class = "covering_only", quantity = 1,
			replacement_comparable = false, measurements = {covering_area_milli_sq_in = 10500},
			labor_minutes = 30, evidence = "Synthetic measured patch, not physical qualification."}}}
	var applied := ledger.apply_repair_choice(receipt, inspected, component, "covering-film-patch", "paid", "consumption")
	var repair_line: Dictionary = {}
	for line: Dictionary in ledger.report.get("lines", []):
		if line.get("id") == component:
			repair_line = line
	check("repair checkpoint keeps known incomparable repair and inspection subtotal", applied.ok and ledger.report.get("known_subtotal_minor") == 2341 and ledger.report.get("total_minor") == null and ledger.report.get("replacement_minor") == null and not ledger.report.get("complete", true) and repair_line.get("action") == "repair" and repair_line.get("amount_minor") == 2341 and ledger._assessment.components[component].replacement_comparable == false)
	var original := ledger.report.duplicate(true)
	var saved := ledger.checkpoint(20, bindings)
	var other := Incident.new()
	other.begin("jensen-das-ugly-stik-60", "")
	var staged := other.prepare_restore(bytes_to_var(var_to_bytes(saved)), 20, bindings)
	check("selected repair checkpoint validates", staged.ok)
	if staged.ok:
		other.commit_restore(staged)
		check("repair subtotal, scope flag and source provenance survive cross-scope restore", other.report == original and other.report.repair_choices.size() == 1 and other.report.get("known_subtotal_minor") == 2341 and other.report.get("total_minor") == null and other.report.get("replacement_minor") == null and other._assessment.components[component].replacement_comparable == false)
		check("repeating restored repair choice remains idempotent", other.apply_repair_choice(receipt, inspected, component, "covering-film-patch", "paid", "consumption").get("duplicate", false) and other.report == original)
		var bad := saved.duplicate(true)
		bad.repair_choices.append(bad.repair_choices[0])
		check("duplicate repair provenance is rejected", not other.prepare_restore(StateCodec.seal(bad), 20, bindings).ok)
		bad = saved.duplicate(true)
		bad.repair_choices[0].recipe_book_sha256 = "different-book"
		check("repair provenance pins its recipe book", not other.prepare_restore(StateCodec.seal(bad), 20, bindings).ok)
		for field: String in ["component_id", "option_id"]:
			bad = saved.duplicate(true)
			bad.repair_choices[0][field] = "receiver"
			check("repair provenance binds " + field, not other.prepare_restore(StateCodec.seal(bad), 20, bindings).ok)
		bad = saved.duplicate(true)
		bad.repair_choices[0].provenance.repair_minor = 0
		check("repair provenance cannot invent a different price", not other.prepare_restore(StateCodec.seal(bad), 20, bindings).ok)
	# The alternate replacement choice must also retain legitimate provenance.
	receipt = _receipt(ledger, "checkpoint-replace", "reuse", [])
	receipt.components = {component: {disposition = "inspect", quantity = 1, damage_flags = [], evidence = "Explicit replacement fixture."}}
	check("replacement option is accepted", ledger.apply_repair_choice(receipt, inspected, component, "replace", "diy", "cash").ok)
	check("replacement option checkpoint validates", other.prepare_restore(ledger.checkpoint(20, bindings), 20, bindings).ok)
	# A complete explicit inspection can resolve ordinary contact caveats.
	receipt = _receipt(ledger, "checkpoint-full", "reuse", [])
	receipt.full_inspection = true
	receipt.components = {}
	for part: Dictionary in ledger.dossier.components:
		receipt.components[part.id] = {disposition = "reuse", quantity = part.quantity, damage_flags = [], evidence = "Synthetic full inspection."}
	check("complete explicit inspection resolves contact uncertainty", ledger.apply_inspection(receipt).ok and ledger._assessment.unresolved.is_empty())
	check("resolved full inspection checkpoint remains valid", other.prepare_restore(ledger.checkpoint(20, bindings), 20, bindings).ok)


func _settlement_cases() -> void:
	var gate := Settlement.new()
	for tick in range(12):
		gate.observe(tick, 0.1, true, 0.0, 0.0)
	var saved := gate.checkpoint()
	check("partial landing dwell checkpoint validates", Settlement.valid_checkpoint(saved, 11))
	var other := Settlement.new()
	other.restore_checkpoint(saved)
	var equal := true
	for tick in range(12, 23):
		equal = (gate.observe(tick, 0.1, true, 0.0, 0.0) == other.observe(tick, 0.1, true, 0.0, 0.0)) and equal
	check("restored dwell settles at the same accepted tick", equal and gate.checkpoint() == other.checkpoint())
	check("settled state validates", Settlement.valid_checkpoint(gate.checkpoint(), 23))
	saved.stable_elapsed_s = INF
	check("reject nonfinite settlement clock", not Settlement.valid_checkpoint(saved, 11))

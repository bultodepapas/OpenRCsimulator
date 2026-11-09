extends SceneTree
const Incident = preload("res://economy/incident.gd")
const Catalog = preload("res://economy/catalog.gd")
const Assessment = preload("res://economy/damage_assessment.gd")
const Events = preload("res://sim/aircraft_contact_events.gd")
const Aircraft = preload("res://physics/aircraft_data.gd")
const Contact = preload("res://physics/aircraft_contact_contract.gd")
const State = preload("res://economy/checkpoint.gd")
var checks := 0
var failures := 0
var bindings: Dictionary
var loaded: Dictionary


func check(name: String, value: bool, detail: Variant = "") -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL %s: %s" % [name, detail])


func _initialize() -> void:
	var physical := Aircraft.load_file("res://data/aircraft/jensen_ugly_stik_60.json")
	bindings = Contact.describe(physical.model, true)
	loaded = Catalog.load_legacy_for("jensen-das-ugly-stik-60", "")
	var profile := {format = Assessment.FORMAT, profile_id = "fixture", policy_version = Assessment.POLICY,
		source_sha256 = loaded.dossier.source_sha256, basis = "authored_game_policy", assumptions = ["Synthetic game fixture; not physical evidence."], zones = []}
	for row: Array in [[0, "receiver"], [1, "receiver_battery"]]:
		profile.zones.append({source = "hull", probe_id = bindings.hull_probes[row[0]].id, component_ids = [row[1]],
			response = {kind = "channel_bands", channel = "depth_m", clear_below = 0.003, replace_at = 0.025, terminal_replace = true}})
	profile.zones.append({source = "propeller", probe_id = bindings.get("rotor_id", "propeller/single"), component_ids = ["propeller"],
		response = {kind = "replace_on_impact"}})
	loaded.damage_profile = profile
	check("synthetic profile validates", Assessment.validate(profile, loaded.dossier, loaded.dossier.source_sha256).ok)
	var actual := Catalog.load_for("jensen-das-ugly-stik-60", "")
	check("production catalog loads valid versioned game profile", actual.ok and Assessment.validate(actual.damage_profile, actual.dossier, actual.dossier.source_sha256).ok, actual.get("errors"))
	_test_persistent()
	_test_reimpact()
	_test_overflow()
	_test_water_and_restore()
	_test_terminal_rule()
	_test_game_scope_and_archive()
	_test_refusals_and_full_inspection()
	_test_grouped_clearance_and_prop_fee()
	print("crash incident evidence: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func ledger() -> RefCounted:
	var value := Incident.new()
	value.begin_with_catalog(loaded, "jensen-das-ugly-stik-60", "")
	return value


func hull(tick: int, index: int, depth: float, persistent := false) -> Dictionary:
	var previous := PackedStringArray([bindings.hull_probes[index].id]) if persistent else PackedStringArray()
	return Events.hull_events([{index = index, new = not persistent, depth_m = depth}], bindings, previous, tick).events[0]


func receipt(value: RefCounted, id: String, rows: Dictionary) -> Dictionary:
	var context: Dictionary = value.inspection_context()
	var components := {}
	for part: String in rows:
		components[part] = {disposition = rows[part], quantity = 1, damage_flags = [], evidence = "Synthetic scenario fixture."}
	return {format = "openrc-accident-inspection v1", inspection_id = id,
		incident_id = context.identity.incident_id, aircraft_id = context.identity.aircraft_id,
		source_sha256 = context.identity.source_sha256, catalog_hash = context.catalog_hash,
		expected_revision = context.revision, full_inspection = false, total_loss = false,
		basis = "scenario_assumption", evidence = "Synthetic fixture.", components = components}


func _test_persistent() -> void:
	var value := ledger()
	for tick in range(1, 151):
		var e := hull(tick, 0, 0.001, tick > 1)
		value.observe({tick = tick, events = [e]}, bindings, false)
	value.evaluate_pending()
	check("150 benign persistent samples remain quiet and bounded", not value.has_damage() and value.report.is_empty() and value.journal.size() == 1 and value._seen.size() <= Incident.MAX_EVENTS)
	var old := hull(1, 0, 0.001)
	var before := var_to_bytes(value.checkpoint(150, bindings))
	check("evicted event is stale rather than presumed duplicate", value.observe({tick = 1, events = [old]}, bindings, false).status == "stale_unverifiable" and var_to_bytes(value.checkpoint(150, bindings)) == before)
	var e := hull(151, 0, 0.03, true)
	value.observe({tick = 151, events = [e]}, bindings, false)
	value.evaluate_pending()
	check("later persistent peak produces one game-policy replacement", value._summaries.receiver.peaks.depth_m == 0.03 and value._assessment.components.receiver.disposition == "replace" and value.report.known_subtotal_minor == 9999, value.report.get("errors"))
	var revision: int = value._revision
	var conflict := e.duplicate(true)
	conflict.measure.depth_m = 0.04
	check("conflicting duplicate is atomically rejected", value.observe({tick = 151, events = [conflict]}, bindings, false).status == "conflicting_duplicate" and value._revision == revision and value._summaries.receiver.peaks.depth_m == 0.03)
	check("exact duplicate is a no-op", value.observe({tick = 151, events = [e]}, bindings, false).status == "duplicate" and value._revision == revision)
	var ended: Dictionary = Events.hull_events([], bindings, PackedStringArray([bindings.hull_probes[0].id]), 152).events[0]
	value.observe({tick = 152, events = [ended]}, bindings, false)
	check("ended contact cannot undo prior replacement", value._assessment.components.receiver.disposition == "replace" and value._summaries.receiver.recommendation == "replace")
	var saved: Dictionary = value.checkpoint(152, bindings)
	var copy := ledger()
	var prepared: Dictionary = copy.prepare_restore(saved, 152, bindings)
	check("persistent peak and replay proofs checkpoint", prepared.ok, prepared)
	if prepared.ok:
		copy.commit_restore(prepared)
		check("restored canonical summary matches", copy._summaries == value._summaries and copy._seen == value._seen)


func _test_reimpact() -> void:
	var value := ledger()
	value.observe({tick = 1, events = [hull(1, 0, 0.01), hull(1, 1, 0.01)]}, bindings, false)
	value.evaluate_pending()
	var clearance := receipt(value, "clearance", {receiver = "reuse", receiver_battery = "reuse"})
	clearance.components.receiver.inspection_minor = 500
	check("scoped clearance accepted", value.apply_inspection(clearance).ok)
	value.observe({tick = 2, events = [hull(2, 0, 0.01)]}, bindings, false)
	value.evaluate_pending()
	check("later impact reopens only affected clearance and keeps incurred fee", value._assessment.components.receiver.disposition == "inspect" and value._assessment.components.receiver.inspection_minor == 500 and value._assessment.components.receiver_battery.disposition == "reuse" and value._inspections.size() == 1)
	var conflicting_fee := receipt(value, "different-fee", {receiver = "replace"})
	conflicting_fee.components.receiver.inspection_minor = 501
	check("a second ambiguous fee is rejected", not value.apply_inspection(conflicting_fee).ok)
	var replace := receipt(value, "replace", {receiver = "replace"})
	check("explicit replacement accepted", value.apply_inspection(replace).ok)
	value.observe({tick = 3, events = [hull(3, 0, 0.01)]}, bindings, false)
	value.evaluate_pending()
	check("later inspection does not downgrade replacement", value._assessment.components.receiver.disposition == "replace")
	check("later receipt cannot downgrade replacement", not value.apply_inspection(receipt(value, "undo", {receiver = "reuse"})).ok)
	var saved: Dictionary = value.checkpoint(3, bindings)
	var other := ledger()
	var prepared: Dictionary = other.prepare_restore(saved, 3, bindings)
	check("reimpact checkpoint validates", prepared.ok, prepared)
	if prepared.ok:
		other.commit_restore(prepared)
		check("reimpact and unrelated receipt survive restore", other._assessment == value._assessment and other._inspections == value._inspections)


func _test_overflow() -> void:
	var value := ledger()
	for tick in range(1, 131):
		value.observe({tick = tick, events = [hull(tick, 0, 0.001)]}, bindings, false)
	check("diagnostic overflow alone does not open an accident", value._journal_overflow and not value.has_damage())
	value.observe({tick = 131, events = [hull(131, 1, 0.03)]}, bindings, false)
	value.evaluate_pending()
	check("late mapped component survives journal overflow", value.journal.size() <= Incident.MAX_EVENTS and value._assessment.components.receiver_battery.disposition == "replace" and value._journal_overflow)
	var saved: Dictionary = value.checkpoint(131, bindings)
	var prepared: Dictionary = ledger().prepare_restore(saved, 131, bindings)
	check("late mapped summary survives checkpoint", prepared.ok, prepared)
	if not saved.is_empty():
		saved.journal_overflow = false
		check("tampered truncation flag is rejected", not ledger().prepare_restore(State.seal(saved), 131, bindings).ok)


func _test_water_and_restore() -> void:
	var value := ledger()
	var water := Events._base_event("impact", "lake", "lake:test:water", "new", 1, "test", "terminal")
	water.merge({"lake_id": "test", "material": "water", "probe_source": "propeller", "probe_id": bindings.get("rotor_id", "propeller/single"), "point_index": -1, "time_fraction": 0.5, "response_status": "terminal"})
	check("qualified propeller-water fixture validates", Events.validate_events([water], 1, bindings))
	value.observe({tick = 1, events = [water]}, bindings, true)
	value.evaluate_pending()
	check("water touch records exposure without inventing broken propeller", value._confirmed_facts.has("water_exposure") and not value._confirmed_facts.has("propeller_strike") and value._assessment.components.propeller.disposition == "inspect")
	var restored := ledger()
	restored.observe({tick = 10, events = []}, bindings, false, true)
	restored.evaluate_pending()
	check("clear unpaired restore stays quiet", restored._prior_history_unknown and not restored.has_damage() and restored.report.is_empty())
	restored.observe({tick = 11, events = [hull(11, 0, 0.01)]}, bindings, false)
	restored.evaluate_pending()
	check("later incident discloses missing prior history", str(restored.report.unresolved).contains("earlier damage history"))
	var strike := {tick = 3, rpm = 6000.0, point_ned = PackedFloat64Array([0, 0, 0]), velocity_ned = PackedFloat64Array([8, 0, 0])}
	var late := ledger()
	late.observe({tick = 10, events = [], prop_strike = strike}, bindings, false, true)
	late.evaluate_pending()
	check("earlier prop latch survives later unpaired restore", late._confirmed_facts.has("restored_propeller_strike") and late._assessment.components.propeller.disposition == "replace" and str(late.report.unresolved).contains("earlier damage history"))
	var invalid := ledger()
	invalid.observe({tick = 1, events = [{invalid = true}]}, bindings, true)
	invalid.evaluate_pending()
	check("invalid payload is rejected while terminal state remains visible", invalid.terminal and invalid.journal.is_empty() and str(invalid.report.unresolved).contains("invalid"))


func _test_terminal_rule() -> void:
	var event := {source = "scenery", probe_source = "hull", probe_id = bindings.hull_probes[0].id,
		event_type = "impact", lifecycle = "new", response = "dissipative_impulse", measure = {depth_m = 0.001}}
	check("nonterminal scenery impact follows bands", Assessment.resolve(loaded.damage_profile, event).recommendation == "clear")
	event.response = "terminal"
	check("same local terminal contact follows terminal game rule", Assessment.resolve(loaded.damage_profile, event).recommendation == "replace")


func _test_game_scope_and_archive() -> void:
	var value := ledger()
	value.observe({tick = 1, events = [hull(1, 0, 0.01)]}, bindings, false)
	value.evaluate_pending()
	check("inspection-band contact is initially unresolved", value._assessment.components.receiver.disposition == "inspect" and not value.report.complete)
	value.observe({tick = 2, events = [hull(2, 0, 0.03, true)]}, bindings, false)
	value.evaluate_pending()
	check("same episode escalation resolves its local caveat", value._assessment.components.receiver.disposition == "replace" and not value._assessment.unresolved.has("Impact or surface contact requires structural inspection."))
	var provisional := receipt(value, "manual-reassessment", {receiver = "reuse"})
	check("manual inspection may revise provisional game candidate", value.apply_inspection(provisional).ok and value._assessment.components.receiver.disposition == "reuse")
	value.observe({tick = 3, events = [hull(3, 0, 0.03)]}, bindings, false)
	value.evaluate_pending()
	check("subsequent supported contact invalidates the revised clearance", value._assessment.components.receiver.disposition == "replace")
	var unknown := ledger()
	unknown.observe({tick = 1, events = [hull(1, 2, 0.01)]}, bindings, false)
	unknown.observe({tick = 2, events = [hull(2, 0, 0.03)]}, bindings, false)
	unknown.evaluate_pending()
	check("unmapped contact remains unresolved after unrelated replacement", unknown._unmapped_evidence and unknown._assessment.unresolved.has("Impact or surface contact requires structural inspection."))
	var terminal := ledger()
	var event := Events._base_event("impact", "hull", bindings.hull_probes[0].id, "new", 1, "fixture", "terminal")
	event["point_index"] = 0
	terminal.observe({tick = 1, events = [event]}, bindings, true)
	terminal.evaluate_pending()
	check("mapped terminal game outcome resolves only its local scope", terminal.report.complete and terminal.report.total_minor == 9999 and str(terminal.report.assumptions).contains("game assumptions"), terminal.report.get("unresolved"))
	var snapshot := ledger()
	snapshot.observe({tick = 1, events = [hull(1, 0, 0.01)]}, bindings, false)
	snapshot.evaluate_pending()
	check("archive fixture accepts three replacement decisions", snapshot.apply_inspection(receipt(snapshot, "archive-parts", {receiver = "replace", receiver_battery = "replace", propeller = "replace"})).ok)
	var packages := [
		{id = "bundle-a", coverage_ids = ["receiver:0", "receiver_battery:0"], surplus_ids = ["spare-a"], cost_cents = 100, available = true, compatible = true, provenance = "Synthetic package A."},
		{id = "bundle-b", coverage_ids = ["receiver_battery:0", "propeller:0"], surplus_ids = [], cost_cents = 100, available = true, compatible = true, provenance = "Synthetic package B."},
	]
	var quote: Dictionary = snapshot.compare_replacements(packages)
	quote.erase("candidate_catalog")
	quote["format"] = "openrc-replacement-comparison v3"
	quote["catalog_hash"] = snapshot._catalog_hash
	snapshot.report.replacement_comparison = quote
	snapshot.archive_path = "user://test_crash_cost_incident_archive.json"
	check("overlapping package comparison saves", quote.status == "optimal" and quote.total_cost_cents == 200 and snapshot.flush() == OK, quote)
	var reader := ledger()
	reader.archive_path = snapshot.archive_path
	var archived: Dictionary = reader.load_archive()
	check("overlap and surplus snapshot reopens", not archived.is_empty() and archived.replacement_comparison.selected_coverage == quote.selected_coverage, archived)
	DirAccess.remove_absolute(snapshot.archive_path)


func _test_refusals_and_full_inspection() -> void:
	var no_mapping: Dictionary = loaded.duplicate(true)
	no_mapping.dossier.contact_components = {}
	var unbound := Incident.new()
	unbound.begin_with_catalog(no_mapping, "jensen-das-ugly-stik-60", "")
	unbound.observe({tick = 1, events = [hull(1, 2, 0.01)]}, bindings, false)
	unbound.evaluate_pending()
	var all_parts := receipt(unbound, "full-after-unbound", {})
	all_parts.full_inspection = true
	for part: Dictionary in unbound.dossier.components:
		all_parts.components[part.id] = {disposition = "reuse", quantity = part.quantity, damage_flags = [], evidence = "Synthetic full inspection."}
	check("full inspection resolves a wholly unbound contact", unbound.apply_inspection(all_parts).ok and unbound.report.complete and not unbound.report.contact_coverage_incomplete, unbound.report.get("unresolved"))
	var value := ledger()
	value.observe({tick = 1, events = [hull(1, 2, 0.01, true)]}, bindings, false)
	value.evaluate_pending()
	check("first unmatched persistent contact has a revision", value._unmapped_evidence and value._unmapped_revision == value._revision and not value.checkpoint(1, bindings).is_empty())
	var full := receipt(value, "full-after-unmapped", {})
	full.full_inspection = true
	for part: Dictionary in value.dossier.components:
		full.components[part.id] = {disposition = "reuse", quantity = part.quantity, damage_flags = [], evidence = "Synthetic full inspection."}
	check("full inspection resolves historical unmapped scope", value.apply_inspection(full).ok and not value.report.contact_coverage_incomplete)
	value.observe({tick = 2, events = [hull(2, 0, 0.01)]}, bindings, false)
	value.evaluate_pending()
	value.observe({tick = 3, events = [hull(3, 0, 0.03, true)]}, bindings, false)
	value.evaluate_pending()
	check("later mapped inspection can resolve after historical full inspection", not value._assessment.unresolved.has("Impact or surface contact requires structural inspection.") and not value.report.contact_coverage_incomplete)
	check("resolved historical unmapped evidence checkpoints", not value.checkpoint(3, bindings).is_empty())
	var oversized := ledger()
	var too_many := []
	too_many.resize(65)
	check("oversized terminal batch rejects evidence but publishes terminal state", oversized.observe({tick = 1, events = too_many}, bindings, true).status == "overflow" and oversized.terminal and oversized.journal.is_empty() and oversized._evidence_overflow)
	var amendments := ledger()
	var rejected := false
	for index in bindings.hull_probes.size():
		for phase: String in ["new", "persistent", "ended"]:
			var event := Events._base_event("hull_contact", "hull", bindings.hull_probes[index].id, phase, 1, "fixture", "contact")
			event["point_index"] = index
			var result: Dictionary = amendments.observe({tick = 1, events = [event]}, bindings, amendments._tick_event_count == 64)
			if result.status == "overflow":
				rejected = true
				break
		if rejected:
			break
	check("terminal same-tick amendment overflow retains prior accepted state", rejected and amendments.terminal and amendments._tick_event_count == 64 and amendments._evidence_overflow)
	var conflict := ledger()
	var first := hull(1, 0, 0.01)
	conflict.observe({tick = 1, events = [first]}, bindings, false)
	var saved_summary: Dictionary = conflict._summaries.duplicate(true)
	first.measure.depth_m = 0.02
	check("conflicting terminal notification rejects payload but records terminal boundary", conflict.observe({tick = 1, events = [first]}, bindings, true).status == "conflicting_duplicate" and conflict.terminal and conflict._summaries == saved_summary)


func _test_grouped_clearance_and_prop_fee() -> void:
	var grouped: Dictionary = loaded.duplicate(true)
	for part: Dictionary in grouped.dossier.components:
		if part.id == "receiver_battery":
			part.quantity = 2
	grouped.damage_profile.zones[0].component_ids = ["fuselage_servos"]
	grouped.damage_profile.zones[1].component_ids = ["receiver_battery"]
	var value := Incident.new()
	value.begin_with_catalog(grouped, "jensen-das-ugly-stik-60", "")
	value.observe({tick = 1, events = [hull(1, 0, 0.03), hull(1, 1, 0.03)]}, bindings, false)
	value.evaluate_pending()
	var reason := "A grouped component needs a quantity-specific inspection."
	check("multiple grouped candidates remain scoped inspection", value._assessment.unresolved.has(reason) and value._assessment.components.fuselage_servos.disposition == "inspect" and value._assessment.components.receiver_battery.disposition == "inspect")
	check("first grouped unit receipt is accepted", value.apply_inspection(receipt(value, "group-one", {fuselage_servos = "replace"})).ok)
	check("one resolved group does not clear another", value._assessment.unresolved.has(reason))
	check("second grouped unit receipt is accepted", value.apply_inspection(receipt(value, "group-two", {receiver_battery = "replace"})).ok)
	check("grouped caveat clears after each affected group is resolved", not value._assessment.unresolved.has(reason))
	check("grouped decisions survive checkpoint", not value.checkpoint(1, bindings).is_empty())
	var prop := ledger()
	prop.observe({tick = 1, events = [hull(1, 0, 0.01)]}, bindings, false)
	prop.evaluate_pending()
	var inspected := receipt(prop, "prop-fee", {propeller = "reuse"})
	inspected.components.propeller.inspection_minor = 500
	check("prop inspection fee is recorded", prop.apply_inspection(inspected).ok)
	var strike := Events.strike_event({tick = 2, rpm = 6000.0, point_ned = PackedFloat64Array([0, 0, 0]), velocity_ned = PackedFloat64Array([8, 0, 0])}, 2, "test", bindings)
	prop.observe({tick = 2, events = [strike]}, bindings, false)
	prop.evaluate_pending()
	check("prop strike preserves incurred inspection fee", prop._assessment.components.propeller.disposition == "replace" and prop._assessment.components.propeller.inspection_minor == 500 and prop.report.known_subtotal_minor >= 1039)
	check("prop replacement and fee survive checkpoint", not prop.checkpoint(2, bindings).is_empty())
	var historical := ledger()
	var old_strike := Events.strike_event({tick = 1, rpm = 6000.0, point_ned = PackedFloat64Array([0, 0, 0]), velocity_ned = PackedFloat64Array([8, 0, 0])}, 1, "test", bindings)
	historical.observe({tick = 1, events = [old_strike]}, bindings, false)
	historical.evaluate_pending()
	var full := receipt(historical, "full-after-prop", {})
	full.full_inspection = true
	for part: Dictionary in historical.dossier.components:
		full.components[part.id] = {disposition = "replace" if part.id == "propeller" else "reuse", quantity = part.quantity, damage_flags = [], evidence = "Synthetic full inspection."}
	check("full inspection resolves older prop inspection", historical.apply_inspection(full).ok)
	historical.observe({tick = 2, events = [hull(2, 0, 0.01)]}, bindings, false)
	historical.evaluate_pending()
	check("new unrelated contact does not resurrect old prop caveat in checkpoint", not historical.checkpoint(2, bindings).is_empty())
	var later_strike := Events.strike_event({tick = 3, rpm = 6000.0, point_ned = PackedFloat64Array([0, 0, 0]), velocity_ned = PackedFloat64Array([8, 0, 0])}, 3, "test", bindings)
	historical.observe({tick = 3, events = [later_strike]}, bindings, false)
	var updated: Dictionary = historical.checkpoint(3, bindings)
	check("new strike reopens prop-related inspection", not updated.is_empty() and updated.fact_revisions.propeller_strike > full.expected_revision + 1 and updated.assessment.unresolved.has("Propeller strike: inspect the powertrain, shaft and mount before return to service."))

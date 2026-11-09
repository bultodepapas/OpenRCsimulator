extends SceneTree
const Incident = preload("res://economy/incident.gd")
const Catalog = preload("res://economy/catalog.gd")
const Assessment = preload("res://economy/damage_assessment.gd")
const Events = preload("res://sim/aircraft_contact_events.gd")
const Aircraft = preload("res://physics/aircraft_data.gd")
const Contact = preload("res://physics/aircraft_contact_contract.gd")
const State = preload("res://economy/checkpoint.gd")
const Transaction = preload("res://economy/cost_transaction.gd")
var checks := 0
var failures := 0
var stik: Dictionary
var stik_bindings: Dictionary


func check(label: String, passed: bool, detail: Variant = "") -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL %s: %s" % [label, detail])


func _initialize() -> void:
	stik = Catalog.load_for("jensen-das-ugly-stik-60", "")
	stik_bindings = physical("res://data/aircraft/jensen_ugly_stik_60.json")
	check("real Jensen v2 profile loads", stik.get("ok", false), stik.get("errors"))
	if not stik.get("ok", false):
		quit(1)
		return
	_test_prop_scope()
	_test_local_persistence()
	_test_multiple_contacts()
	_test_cadence_and_missing_channel()
	_test_corrected_reimpact()
	_test_avanti()
	_test_grouped_followup()
	_test_choices()
	print("round2 incident: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func physical(path: String) -> Dictionary:
	var aircraft := Aircraft.load_file(path)
	return Contact.describe(aircraft.model, true)


func owner(loaded: Dictionary = stik, id := "jensen-das-ugly-stik-60") -> RefCounted:
	var value := Incident.new()
	value.begin_with_catalog(loaded, id, "")
	return value


func index_of(bindings: Dictionary, id: String) -> int:
	for i in bindings.hull_probes.size():
		if bindings.hull_probes[i].id == id:
			return i
	return -1


func hull(bindings: Dictionary, id: String, tick: int, depth: float, previous := false, normal_speed: Variant = null) -> Dictionary:
	var index := index_of(bindings, id)
	var row := {index = index, new = not previous, depth_m = depth}
	if normal_speed != null:
		row["normal_speed_mps"] = normal_speed
	var active := PackedStringArray([id]) if previous else PackedStringArray()
	return Events.hull_events([row], bindings, active, tick).events[0]


func strike(bindings: Dictionary, tick: int, rpm: float, speed: float) -> Dictionary:
	return Events.strike_event({tick = tick, rpm = rpm, point_ned = PackedFloat64Array([0, 0, 0]),
		velocity_ned = PackedFloat64Array([speed, 0, 0])}, tick, "round2-fixture", bindings)


func impact(bindings: Dictionary, id: String, tick: int, speed: float, glancing := false) -> Dictionary:
	var index := index_of(bindings, id)
	var event := Events._base_event("impact", "hull", id, "new", tick, "round2-fixture", "terminal")
	event["point_index"] = index
	event["velocity_ned"] = PackedFloat64Array([speed, 0, 0]) if glancing else PackedFloat64Array([0, 0, speed])
	event["normal_ned"] = PackedFloat64Array([0, 0, -1])
	event["measure"] = {"speed_mps": speed, "down_speed_mps": 0.0 if glancing else speed}
	return event


func receipt(value: RefCounted, id: String, component: String, action: String) -> Dictionary:
	var ctx: Dictionary = value.inspection_context()
	return {format = "openrc-accident-inspection v1", inspection_id = id, incident_id = ctx.identity.incident_id,
		aircraft_id = ctx.identity.aircraft_id, source_sha256 = ctx.identity.source_sha256,
		catalog_hash = ctx.catalog_hash, expected_revision = ctx.revision, full_inspection = false,
		total_loss = false, basis = "scenario_assumption", evidence = "Synthetic scoped inspection.",
		components = {component: {disposition = action, quantity = 1, damage_flags = [], evidence = "Synthetic conclusion."}}}


func _test_prop_scope() -> void:
	var value := owner()
	var event := strike(stik_bindings, 1, 5000.0, 5.0)
	value.observe({tick = 1, events = [event]}, stik_bindings, false)
	value.evaluate_pending()
	var prop: Dictionary = value._assessment.components.get("propeller", {})
	check("normal prop contact replaces only prop and scopes related checks", prop.get("disposition") == "replace" and not value._assessment.components.has("engine_and_muffler") and value.report.total_minor == 539, value.report)
	check("scoped clears make no salvage claim", value.report.salvage_minor == 0 and value.report.game_assessment.current_outcomes.engine_and_muffler.action == "scope_clear" and str(value.report.game_assessment.current_outcomes.engine_and_muffler.quantity_scope).contains("not a physical"))
	var saved: Dictionary = value.checkpoint(1, stik_bindings)
	var copy := owner()
	var prepared: Dictionary = copy.prepare_restore(saved, 1, stik_bindings)
	check("prop scope, selected cost and proof prepare after checkpoint", prepared.get("ok", false), prepared)
	if prepared.get("ok", false):
		copy.commit_restore(prepared)
		check("prop scope and receipt survive restore without salvage", copy.report.total_minor == value.report.total_minor and copy._game_receipts == value._game_receipts and not copy._assessment.components.has("engine_and_muffler"))
	var medium := owner()
	medium.observe({tick = 1, events = [strike(stik_bindings, 1, 7000, 15)]}, stik_bindings, false)
	medium.evaluate_pending()
	check("middle prop band produces authored grouped service", medium._assessment.components.engine_and_muffler.get("disposition") == "repair" and medium._assessment.components.engine_and_muffler.repair_minor == 2500 and medium.report.total_minor == 5539, medium.report)
	var known := receipt(medium, "manual-engine", "engine_and_muffler", "reuse")
	check("explicit inspection can revise provisional game service", medium.apply_inspection(known).ok)
	medium.observe({tick = 2, events = [strike(stik_bindings, 2, 7000, 15)]}, stik_bindings, false)
	medium.evaluate_pending()
	check("new prop impact reopens an explicit earlier clearance", medium._assessment.components.engine_and_muffler.disposition == "inspect")


func _test_local_persistence() -> void:
	var value := owner()
	var name := "probe_wing_left_tip"
	value.observe({tick = 1, events = [hull(stik_bindings, name, 1, 0.01)]}, stik_bindings, false)
	value.evaluate_pending()
	value.archive_path = "user://round2-peak-evidence.json"
	check("initial game assessment archives", value.flush(true) == OK)
	var revision: int = value._revision
	var receipts: int = value._game_receipts.size()
	check("middle wing contact yields one local service", value._assessment.components.airframe_wing.disposition == "repair" and value.report.total_minor == 2299, value.report)
	for tick in range(2, 82):
		value.observe({tick = tick, events = [hull(stik_bindings, name, tick, 0.01 + tick * 0.0001, true)]}, stik_bindings, false)
		value.evaluate_pending()
		value.flush()
	check("same-band growing scrape retains peak without receipt/revision churn", value._revision == revision and value._game_receipts.size() == receipts and value._summaries.airframe_wing.peaks.depth_m > 0.018 and value.report.total_minor == 2299)
	check("new persistent peak reaches the published report", value.report.contact_summary.airframe_wing.peaks.depth_m == value._summaries.airframe_wing.peaks.depth_m)
	check("same-revision evidence is periodically flushed", float(value.load_archive().contact_summary.airframe_wing.peaks.depth_m) > 0.016)
	check("new persistent peak survives forced archive and reopen", value.flush(true) == OK and is_equal_approx(float(value.load_archive().contact_summary.airframe_wing.peaks.depth_m), value._summaries.airframe_wing.peaks.depth_m))
	DirAccess.remove_absolute(value.archive_path)
	value.observe({tick = 82, events = [hull(stik_bindings, name, 82, 0.03, true)]}, stik_bindings, false)
	value.evaluate_pending()
	check("crossing the severe band replaces the current local scope once", value._assessment.components.airframe_wing.disposition == "replace" and value._game_receipts.size() == receipts)
	var saved: Dictionary = value.checkpoint(82, stik_bindings)
	check("local repair escalation checkpoints", not saved.is_empty())
	var protected := owner()
	var head := "probe_engine_head"
	protected.observe({tick = 1, events = [hull(stik_bindings, head, 1, 0.001, false, 4.0)]}, stik_bindings, false)
	protected.evaluate_pending()
	check("real nonterminal hull normal channel drives service", protected._assessment.components.engine_and_muffler.disposition == "repair" and protected.report.total_minor == 2500 and str(protected.report.game_assessment.current_outcomes.engine_and_muffler.reason).contains("prior accepted"), protected.report)


func _test_multiple_contacts() -> void:
	var simultaneous := owner()
	var one := hull(stik_bindings, "probe_wing_left_tip", 1, 0.01)
	var two := hull(stik_bindings, "probe_wing_right_tip", 1, 0.01)
	simultaneous.observe({tick = 1, events = [two, one]}, stik_bindings, false)
	simultaneous.evaluate_pending()
	var amended := owner()
	amended.observe({tick = 1, events = [one]}, stik_bindings, false)
	amended.observe({tick = 1, events = [two]}, stik_bindings, false)
	amended.evaluate_pending()
	check("two same-component probes aggregate one repair", simultaneous._assessment.components.airframe_wing == amended._assessment.components.airframe_wing and simultaneous.report.total_minor == 2299 and amended.report.total_minor == 2299)
	check("equal-action probes use one canonical scope witness", simultaneous._game_receipts[0].observations.size() == 1 and amended._game_receipts[0].observations.size() == 1 and simultaneous._game_receipts[0].observations == amended._game_receipts[0].observations)
	for swapped: bool in [false, true]:
		var value := owner()
		var severe := hull(stik_bindings, "probe_wing_left_tip", 1, 0.03)
		var clear := hull(stik_bindings, "probe_wing_right_tip", 1, 0.001)
		value.observe({tick = 1, events = [clear, severe] if swapped else [severe, clear]}, stik_bindings, false)
		value.evaluate_pending()
		check("clear companion contact never erases severe outcome %s" % swapped, value._assessment.components.airframe_wing.disposition == "replace")


func _test_cadence_and_missing_channel() -> void:
	var names := []
	for zone: Dictionary in stik.damage_profile.zones:
		if zone.source == "hull" and zone.component_ids == ["airframe_wing"]:
			names.append(zone.probe_id)
	names.sort()
	check("cadence tape covers more than 16 observations", names.size() >= 3)
	var expected := {}
	for cadence: int in [1, 2, 8]:
		var value := owner()
		value._identity.incident_id = "round2-cadence"
		for tick in range(1, 9):
			var events := []
			for name: String in names:
				events.append(hull(stik_bindings, name, tick, 0.01 + tick * 0.0001 if tick < 5 else 0.03 + tick * 0.0001, tick > 1))
			value.observe({tick = tick, events = events}, stik_bindings, false)
			if tick % cadence == 0:
				value.evaluate_pending()
		value.evaluate_pending()
		var compared: Dictionary = value.report.duplicate(true)
		if expected.is_empty():
			expected = compared
		check("same accepted tape has identical published report at cadence %d" % cadence, compared == expected, {receipts = value._game_receipts.size(), revision = value._revision})
		check("cadence result keeps severe wing and cumulative peak %d" % cadence, value._assessment.components.airframe_wing.disposition == "replace" and value._summaries.airframe_wing.peaks.depth_m > 0.03 and value._game_receipts.size() == 1)
		value.archive_path = "user://round2-cadence-%d.json" % cadence
		check("cadence archive writes and reopens %d" % cadence, value.flush(true) == OK and not value.load_archive().is_empty())
		var persisted: Dictionary = value.load_archive()
		if not has_meta("cadence_archive"):
			set_meta("cadence_archive", persisted)
		check("same accepted tape has identical archived report at cadence %d" % cadence, persisted == get_meta("cadence_archive"))
		DirAccess.remove_absolute(value.archive_path)
	for publish_first: bool in [false, true]:
		var value := owner()
		var id := "probe_wing_left_tip"
		value.observe({tick = 1, events = [hull(stik_bindings, id, 1, 0.01)]}, stik_bindings, false)
		if publish_first:
			value.evaluate_pending()
		var index := index_of(stik_bindings, id)
		var missing: Dictionary = Events.hull_events([{index = index, new = false}], stik_bindings, PackedStringArray([id]), 2).events[0]
		value.observe({tick = 2, events = [missing]}, stik_bindings, false)
		value.evaluate_pending()
		check("missing persistent channel remains unresolved with prior publication %s" % publish_first, value._assessment.components.airframe_wing.disposition == "inspect" and value._scope_unresolved.has("airframe_wing") and not value.report.complete)
	var two_component_expected := {}
	for cadence: int in [1, 2]:
		var value := owner()
		value._identity.incident_id = "round2-two-components"
		value.observe({tick = 1, events = [hull(stik_bindings, "probe_wing_left_tip", 1, 0.01)]}, stik_bindings, false)
		if cadence == 1:
			value.evaluate_pending()
		value.observe({tick = 2, events = [hull(stik_bindings, "probe_tail_skid", 2, 0.01)]}, stik_bindings, false)
		value.evaluate_pending()
		if two_component_expected.is_empty():
			two_component_expected = value.report.duplicate(true)
		check("different components retain canonical receipt order at cadence %d" % cadence, value.report == two_component_expected and value._game_receipts.size() == 2)
	var amendment_expected := {}
	for clear_first: bool in [false, true]:
		var value := owner()
		value._identity.incident_id = "round2-clear-amendment"
		var clear := hull(stik_bindings, "probe_wing_left_tip", 1, 0.001)
		var damage := hull(stik_bindings, "probe_tail_skid", 1, 0.01)
		value.observe({tick = 1, events = [clear if clear_first else damage]}, stik_bindings, false)
		value.evaluate_pending()
		value.observe({tick = 1, events = [damage if clear_first else clear]}, stik_bindings, false)
		value.evaluate_pending()
		if amendment_expected.is_empty():
			amendment_expected = value.report.duplicate(true)
		check("clear and damaging same-tick amendments are order independent %s" % clear_first, value.report == amendment_expected)


func _test_corrected_reimpact() -> void:
	var value := owner()
	var name := "probe_wing_left_tip"
	value.observe({tick = 1, events = [hull(stik_bindings, name, 1, 0.03)]}, stik_bindings, false)
	value.evaluate_pending()
	check("manual correction accepts provisional replacement revision", value.apply_inspection(receipt(value, "correct", "airframe_wing", "reuse")).ok)
	value.observe({tick = 2, events = [hull(stik_bindings, name, 2, 0.01)]}, stik_bindings, false)
	value.evaluate_pending()
	check("milder new impact does not resurrect superseded replacement", value._assessment.components.airframe_wing.disposition == "inspect")


func _test_avanti() -> void:
	var loaded := Catalog.load_for("sebart-avanti-s-a200-p100rx", "")
	var bindings := physical("res://data/aircraft/sebart_avanti_s_a200.json")
	var name := "probe_belly_station_plus_six"
	check("Avanti rear witness is configured", loaded.get("ok", false) and index_of(bindings, name) >= 0, loaded.get("errors"))
	if not loaded.get("ok", false) or index_of(bindings, name) < 0: return
	var mild := owner(loaded, "sebart-avanti-s-a200-p100rx")
	var event := impact(bindings, name, 1, 3)
	check("Avanti terminal impact fixture is accepted", Events.validate_events([event], 1, bindings))
	mild.observe({tick = 1, events = [event]}, bindings, true)
	mild.evaluate_pending()
	check("mild rearbody service leaves turbine and accessories scoped-clear", mild._assessment.components.airframe_fuselage.disposition == "repair" and not mild._assessment.components.has("engine_main") and not mild._assessment.components.has("turbine_accessories") and mild.report.game_assessment.current_outcomes.engine_main.action == "scope_clear", mild.report)
	check("mild scenario uses one local service amount", mild.report.total_minor == 2500, mild.report)
	var strong := owner(loaded, "sebart-avanti-s-a200-p100rx")
	strong.observe({tick = 1, events = [impact(bindings, name, 1, 42)]}, bindings, true)
	strong.evaluate_pending()
	check("strong direct rearbody evidence resolves disjoint turbine, accessory and structure", strong._assessment.components.engine_main.disposition == "replace" and strong._assessment.components.turbine_accessories.disposition == "replace" and strong._assessment.components.airframe_fuselage.disposition == "replace" and strong.report.total_minor == 458000, strong.report)
	var normal := Assessment.resolve(loaded.damage_profile, impact(bindings, name, 1, 10))
	var glancing := Assessment.resolve(loaded.damage_profile, impact(bindings, name, 1, 10, true))
	check("same speed direct versus glancing uses inward normal proxy", normal.actions.airframe_fuselage.recommendation == "repair" and glancing.actions.airframe_fuselage.recommendation == "clear")
	var missing := impact(bindings, name, 1, 10)
	missing.erase("normal_ned")
	check("missing normal stays unknown", Assessment.resolve(loaded.damage_profile, missing).actions.engine_main.recommendation == "inspect")


func _test_grouped_followup() -> void:
	var loaded := Catalog.load_for("p51d-mustang-120", "")
	var bindings := physical("res://data/aircraft/p51d_mustang_120.json")
	check("P51 grouped fixture loads", loaded.get("ok", false) and bindings.get("ok", false), loaded.get("errors"))
	if not loaded.get("ok", false) or not bindings.get("ok", false): return
	var middle := owner(loaded, "p51d-mustang-120")
	middle.observe({tick = 1, events = [strike(bindings, 1, 7000, 15)]}, bindings, false)
	middle.evaluate_pending()
	check("grouped middle followup is one labeled group service", middle._assessment.components.muffler_pair.disposition == "repair" and middle._assessment.components.muffler_pair.quantity == 2 and str(middle.report.game_assessment.current_outcomes.muffler_pair.quantity_scope).contains("count is unknown"), middle.report)
	var high := owner(loaded, "p51d-mustang-120")
	high.observe({tick = 1, events = [strike(bindings, 1, 21000, 50)]}, bindings, false)
	high.evaluate_pending()
	check("grouped severe followup leaves quantity unresolved", high._assessment.components.muffler_pair.disposition == "inspect" and high.report.total_minor == null and str(high.report.unresolved).contains("quantity-specific"), high.report)


func _test_choices() -> void:
	var value := owner()
	value.observe({tick = 1, events = [hull(stik_bindings, "probe_wing_left_tip", 1, 0.03)]}, stik_bindings, false)
	value.evaluate_pending()
	var original: Dictionary = value.report.duplicate(true)
	check("default automatic purchase and labor are present", value.report.get("costing_available", false) and value.report.get("costing_mode") == "diy" and value.report.has("selected_cost_plan"))
	var selected: Dictionary = value.set_costing_mode("paid")
	check("paid mode is an accepted new revision", selected.get("ok", false) and value.report.costing_mode == "paid" and value.report.revision > original.revision and value.report.known_subtotal_minor > original.known_subtotal_minor, selected)
	var saved: Dictionary = value.checkpoint(1, stik_bindings)
	var other := owner()
	var prepared: Dictionary = other.prepare_restore(saved, 1, stik_bindings)
	check("paid plan and frozen book survive checkpoint preparation", prepared.get("ok", false), prepared)
	if prepared.get("ok", false):
		other.commit_restore(prepared)
		check("paid selected plan survives restore", other.report.costing_mode == "paid" and other.report.known_subtotal_minor == value.report.known_subtotal_minor)
	var before: Dictionary = value.report.duplicate(true)
	check("unsupported mode does not mutate bill", not value.set_costing_mode("unknown").get("ok", true) and value.report == before)
	var revision: int = value._revision
	var history_count: int = value._quote_history.size()
	check("reselecting the current mode is idempotent", value.set_costing_mode("paid").get("duplicate", false) and value._revision == revision and value._quote_history.size() == history_count)
	var package_id := "stik-complete-airframe-game-package"
	var chosen: Dictionary = value.set_purchase_package(package_id)
	check("explicit package is selected from the frozen book", chosen.get("ok", false) and value.report.purchase_package_id == package_id and value.report.costing_available, chosen)
	revision = value._revision
	history_count = value._quote_history.size()
	check("reselecting the current package is idempotent", value.set_purchase_package(package_id).get("duplicate", false) and value._revision == revision and value._quote_history.size() == history_count)
	check("automatic purchase can be reselected", value.set_purchase_package("").get("ok", false))
	var all_changed := true
	for i in range(20):
		var mode := "diy" if i % 2 == 0 else "paid"
		all_changed = value.set_costing_mode(mode).get("ok", false) and all_changed
	check("many quote toggles stay usable with bounded history", all_changed and value._quote_history.size() <= 8 and value._quote_history_truncated and value.report.quote_history_truncated)
	value.archive_path = "user://round2-choice-evidence.json"
	check("selection revision is archived", value.flush(true) == OK and value.load_archive().revision == value.report.revision)
	DirAccess.remove_absolute(value.archive_path)
	saved = value.checkpoint(1, stik_bindings)
	other = owner()
	prepared = other.prepare_restore(saved, 1, stik_bindings)
	check("bounded quote choices survive paired restore", prepared.get("ok", false), prepared)
	if prepared.get("ok", false):
		other.commit_restore(prepared)
		check("restored quote history and selected bill agree", other._quote_history == value._quote_history and other._quote_history_truncated and other.report.costing_mode == value.report.costing_mode and other.report.known_subtotal_minor == value.report.known_subtotal_minor)
	var candidate: Dictionary = Transaction.prepare_mode(value.dossier, value._assessment, value._recipe_book, value.cost_transaction_context(), value._costing_mode)
	var request: Dictionary = candidate.receipt.request.duplicate(true)
	request.transaction_id = "round2-explicit-fee"
	request.incurred_fees = [{id = "inspection-one", kind = "inspection", amount_minor = 500}]
	var total_before: int = value.report.known_subtotal_minor
	var accepted: Dictionary = value.apply_cost_transaction(request)
	check("explicit transaction records an incurred fee once", accepted.get("ok", false) and value.report.known_subtotal_minor == total_before + 500, accepted)
	revision = value._revision
	check("replaying an identical transaction is idempotent", value.apply_cost_transaction(request).get("duplicate", false) and value._revision == revision)
	var conflicting: Dictionary = request.duplicate(true)
	conflicting.incurred_fees[0].amount_minor = 600
	check("conflicting duplicate is rejected atomically", not value.apply_cost_transaction(conflicting).get("ok", true) and value._revision == revision and value.report.known_subtotal_minor == total_before + 500)
	saved = value.checkpoint(1, stik_bindings)
	other = owner()
	prepared = other.prepare_restore(saved, 1, stik_bindings)
	check("explicit fee and transaction survive paired restore", prepared.get("ok", false), prepared)
	if prepared.get("ok", false):
		other.commit_restore(prepared)
		check("restored fee remains charged once", other._assessment.incurred_fees == [{id = "inspection-one", kind = "inspection", amount_minor = 500}] and other.report.known_subtotal_minor == value.report.known_subtotal_minor)
	var forged: Dictionary = saved.duplicate(true)
	forged.cost_transactions[0].purchase.selected_lines[0].cost_cents = 1
	forged.cost_transactions[0].erase("receipt_digest")
	forged.cost_transactions[0].receipt_digest = Transaction.digest(forged.cost_transactions[0])
	forged = State.seal(forged)
	check("recomputed digest cannot forge a historical cost receipt", not owner().prepare_restore(forged, 1, stik_bindings).get("ok", true))
	var stale: Dictionary = Transaction.prepare_mode(value.dossier, value._assessment, value._recipe_book, value.cost_transaction_context(), value._costing_mode).receipt.request.duplicate(true)
	stale.transaction_id = "round2-stale-choice"
	value.observe({tick = 2, events = [strike(stik_bindings, 2, 5000, 5)]}, stik_bindings, false)
	value.evaluate_pending()
	revision = value._revision
	var after_contact: Dictionary = value.report.duplicate(true)
	check("new accepted evidence rejects a stale choice atomically", not value.apply_cost_transaction(stale).get("ok", true) and value._revision == revision and value.report == after_contact)

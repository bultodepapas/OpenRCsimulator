extends SceneTree

const MainScene = preload("res://main.tscn")
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
const Session = preload("res://sim/flight_session.gd")
const HullContact = preload("res://physics/hull_contact.gd")
const Incident = preload("res://economy/incident.gd")
const Events = preload("res://sim/aircraft_contact_events.gd")
const ARCHIVE := "user://test_accident_integration.json"
var checks := 0
var failures := 0
var audio_playback_refs: Array[WeakRef] = []


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
	print(("ok   " if passed else "FAIL ") + label)


func _initialize() -> void:
	_run.call_deferred()


func _make(enabled: bool, aircraft_id := "jensen-das-ugly-stik-60", effects := false) -> Variant:
	var main: Variant = MainScene.instantiate()
	main.aircraft_id = aircraft_id
	main.crash_effects_enabled = effects
	main.accident_reports_enabled = enabled
	main.accident_archive_path = ARCHIVE
	root.add_child(main)
	main.set_process(false)
	main.session.input_enabled = false
	main.session.set_physics_process(false)
	main.session.sim.set_physics_process(false)
	return main


func _run() -> void:
	DirAccess.remove_absolute(ARCHIVE)
	var enabled: Variant = _make(true)
	var disabled: Variant = _make(false)
	var session: Variant = enabled.session
	var other: Variant = disabled.session
	var incident: Variant = enabled._accident_incident
	check("report exists independently of VFX and holds crash for deliberate restart", incident != null and enabled._crash_director == null and not session.crash_auto_restart)
	session.reset()
	other.reset()
	session.sim.set_paused(false)
	other.sim.set_paused(false)
	for i in 100:
		session.sim.step()
		other.sim.step()
	check("read-only economics preserves healthy float64 state exactly", session.sim.state == other.sim.state and session.sim.aux == other.sim.aux and session.sim.modes == other.sim.modes)
	check("healthy flight has no accident report", incident.report.is_empty())
	session.start_choice = Session.START_RUNWAY
	session.reset()
	var parked_state: PackedFloat64Array = session.sim.state.duplicate()
	session.sim.reset(_nose_over(session))
	session.sim.set_paused(false)
	for i in 240:
		session.sim.inputs[3] = 1.0
		session._physics_process(session.sim.dt())
		if not session.prop_strike.is_empty() or not session.crash.is_empty():
			break
		session.sim.step()
	check("production prop strike continues flight with engine stopped", not session.prop_strike.is_empty() and session.crash.is_empty() and not session.engine_running)
	check("accepted contact does not calculate, publish or save a report", incident.report.is_empty() and not enabled._accident_report._content_visible and not FileAccess.file_exists(ARCHIVE))
	enabled._update_accident_report()
	var prop_line := _component_line(incident.report, "propeller")
	check("confirmed propeller is priced once at USD 5.39", prop_line.get("amount_minor") == 539 and _component_count(incident.report, "propeller") == 1)
	var comparison: Dictionary = incident.report.get("replacement_comparison", {})
	check("production prop strike derives a bounded parts-only comparison", comparison.get("status") == "optimal" and comparison.get("total_cost_cents") == 539
		and comparison.get("coverage_scope") == "replacements_only" and comparison.get("required_unit_ids") == ["propeller:0"])
	check("modeled observations produce a scoped game estimate", comparison.get("assessment_complete", false)
		and comparison.get("complete", false) and incident.report.get("total_minor") == 7838
		and incident.report.get("game_assessment", {}).get("basis") == "scenario_assumption")
	var before_comparison: Dictionary = incident.report.duplicate(true)
	var authored_option: Dictionary = incident.compare_replacements([{id = "synthetic-discount", coverage_ids = ["propeller:0"],
		cost_cents = 400, available = true, compatible = true, provenance = "Software fixture; no retail price or physical-fit claim."}])
	check("explicit package comparison can choose a cheaper complete cover", authored_option.get("selected_candidate_ids") == ["synthetic-discount"] and authored_option.get("total_cost_cents") == 400)
	check("comparing an alternative cannot rebill or apply it", incident.report == before_comparison)
	check("priced part freezes its source and compatibility notes", str(prop_line.get("source_url", "")).begins_with("https://") and prop_line.get("observed_on") == "2026-10-15" and not str(prop_line.get("notes", "")).is_empty())
	check("local powertrain and wing services retain authored game scope", incident.report.get("complete", false)
		and _component_line(incident.report, "engine_and_muffler").get("amount_minor") == 2500
		and _component_line(incident.report, "engine_mount").get("amount_minor") == 2500
		and _component_line(incident.report, "airframe_wing").get("amount_minor") == 2299
		and incident.report.game_assessment.current_outcomes.engine_and_muffler.basis == "scenario_assumption")
	var revision: int = incident.report.get("revision", -1)
	enabled._on_accident_contacts()
	enabled._update_accident_report()
	check("repeated notification cannot bill the prop twice", incident.report.get("revision") == revision and incident.report.get("known_subtotal_minor") == before_comparison.known_subtotal_minor and _component_count(incident.report, "propeller") == 1)
	check("flight writes the archive off the frame (CR-22e)", incident.async_archive)
	check("snapshot persists outside accepted physics callbacks", incident.flush() == OK and incident.wait_for_archive() == OK and FileAccess.file_exists(ARCHIVE))
	check("background archive bytes equal the synchronous encoding", FileAccess.get_file_as_string(ARCHIVE) == Incident.ReportArchive.encode(incident.report).text)
	var reader := Incident.new()
	reader.archive_path = ARCHIVE
	check("stored report reopens with frozen catalog identity", reader.load_archive().get("catalog_hash") == incident.report.get("catalog_hash"))
	var archived_receipt: Dictionary = reader.load_archive().get("active_cost_receipt", {})
	check("default automatic plan archives its receipt without requiring a player selection", not archived_receipt.is_empty()
		and archived_receipt.get("receipt_digest") == incident.report.get("selected_cost_plan", {}).get("receipt_digest")
		and archived_receipt.get("transaction_id") == incident.report.get("selected_cost_plan", {}).get("transaction_id")
		and incident.report.get("cost_transactions", []).is_empty() and incident.report.get("quote_history", []).is_empty())
	var archived_comparison: Dictionary = reader.load_archive().get("replacement_comparison", {})
	check("archive preserves the comparison snapshot without repricing", archived_comparison.get("total_cost_cents") == comparison.total_cost_cents
		and archived_comparison.get("status") == comparison.status and archived_comparison.get("selected_provenance") == comparison.selected_provenance
		and archived_comparison.get("required_unit_ids") == comparison.required_unit_ids and archived_comparison.get("catalog_hash") == comparison.catalog_hash)
	_test_archive_integrity(incident, reader)
	for defect: String in ["negative_amount", "wrong_catalog", "false_complete", "zero_sum", "empty_coverage"]:
		var malformed: Dictionary = incident.report.duplicate(true)
		if defect == "negative_amount":
			malformed.replacement_comparison.total_cost_cents = -1
		elif defect == "wrong_catalog":
			malformed.replacement_comparison.catalog_hash = "different-catalog"
		elif defect == "zero_sum":
			malformed.replacement_comparison.total_cost_cents = 0
		elif defect == "empty_coverage":
			malformed.replacement_comparison.selected_lines[0].coverage_ids = []
		else:
			malformed.replacement_comparison.complete = not malformed.replacement_comparison.complete
		var file := FileAccess.open(ARCHIVE, FileAccess.WRITE)
		file.store_string(JSON.stringify(malformed))
		file.close()
		check("malformed archived comparison is rejected: " + defect, reader.load_archive().is_empty())
	var archive_file := FileAccess.open(ARCHIVE, FileAccess.WRITE)
	archive_file.store_string(JSON.stringify(incident.report))
	archive_file.close()
	var saved_report: Dictionary = incident.report.duplicate(true)
	check("invalid checkpoint cannot discard current costs", not session.restore_checkpoint({}) and incident.report == saved_report)
	var checkpoint: Dictionary = session.checkpoint()
	check("valid physics checkpoint restores", session.restore_checkpoint(checkpoint))
	enabled._update_accident_report()
	check("restored prop latch is costed once with explicit missing-history caveat", incident.report.get("known_subtotal_minor") == 539 and str(incident.report.get("unresolved", [])).contains("earlier damage history"))
	session.sim.set_paused(false)
	_test_landing(enabled, parked_state)
	_crash(session)
	enabled._update_accident_report()
	check("terminal production contact opens persistent report", not session.crash.is_empty() and incident.terminal and enabled._accident_report._report_panel.visible)
	check("unknown structural damage does not invent total loss or servo salvage", incident.report.get("total_minor") == null and incident.report.get("salvage_minor") == 0 and incident.report.get("outcome") != "total_loss")
	var original_hash: String = session.aircraft.input_identity.sha256
	var before_reload: Dictionary = incident.report.duplicate(true)
	session.aircraft.input_identity.sha256 = "developer-reload-test"
	enabled._on_accident_contacts()
	check("source changes quarantine contacts without catalog, publication or archive work in callback", enabled._accident_reload_pending and enabled._accident_source_hash == original_hash and incident.report == before_reload)
	enabled._update_accident_report()
	check("frame-boundary rebind refuses stale prices for a changed aircraft", incident.report.get("outcome") == "unavailable" and incident.report.get("total_minor") == null and enabled._accident_source_hash == "developer-reload-test")
	session.aircraft.input_identity.sha256 = original_hash
	enabled._on_accident_contacts()
	enabled._update_accident_report()
	session.reset()
	check("restart clears only current ledger and keeps archived report", incident.report.is_empty() and not incident.last_report.is_empty() and enabled._accident_report._restore_button.visible)
	check("archived report reopening is view-only", enabled._accident_report._archived)
	_test_bounds(session)
	_test_cadence(session)
	_test_variant_strikes()
	await _test_terminal_determinism()
	_retire_main(enabled)
	_retire_main(disabled)
	await process_frame
	await process_frame
	var cleanup_started := Time.get_ticks_usec()
	var remaining_playbacks := _remaining_audio_playbacks()
	while remaining_playbacks > 0 and Time.get_ticks_usec() - cleanup_started < 1000000:
		await process_frame
		remaining_playbacks = _remaining_audio_playbacks()
	check("integration audio playbacks drain within one second after scene teardown", remaining_playbacks == 0)
	DirAccess.remove_absolute(ARCHIVE)
	DirAccess.remove_absolute(ARCHIVE + ".tmp")
	print("CR-30/32: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _test_archive_integrity(incident: RefCounted, reader: RefCounted) -> void:
	var saved_text := FileAccess.get_file_as_string(ARCHIVE)
	var envelope: Variant = JSON.parse_string(saved_text)
	var enveloped: bool = envelope is Dictionary and envelope.get("format") == "openrc-accident-report-archive v1" and envelope.get("report_json") is String
	check("new saved reports use a bounded exact-payload integrity envelope", enveloped)
	if not enveloped:
		return
	var accepted: Dictionary = reader.last_report.duplicate(true)
	for defect: String in ["payload_byte", "reconciled_total", "selected_digest", "missing_receipt", "receipt_amount", "wrong_context", "nested_shape"]:
		var modified: Dictionary = envelope.duplicate(true)
		var payload: Dictionary = JSON.parse_string(modified.report_json)
		match defect:
			"payload_byte", "reconciled_total": payload.total_minor = int(payload.total_minor) + 1
			"selected_digest": payload.selected_cost_plan.receipt_digest = "f".repeat(64)
			"missing_receipt": payload.erase("active_cost_receipt")
			"receipt_amount": payload.active_cost_receipt.purchase.total_cost_cents = int(payload.active_cost_receipt.purchase.total_cost_cents) + 1
			"wrong_context": payload.cost_context.purchase_book_hash = "f".repeat(64)
			"nested_shape": payload.lines[0].allocated_ids = "not-an-array"
		modified.report_json = JSON.stringify(payload, "", true, true)
		if defect != "payload_byte":
			modified.payload_sha256 = String(modified.report_json).sha256_text()
		var file := FileAccess.open(ARCHIVE, FileAccess.WRITE)
		file.store_string(JSON.stringify(modified, "", true, true))
		file.close()
		check("changed saved report is refused without replacing accepted history: " + defect, reader.load_archive().is_empty() and reader.last_report == accepted and not reader.archive_load_error.is_empty())
	var historical: Dictionary = incident.report.duplicate(true)
	historical.erase("active_cost_receipt")
	historical.erase("cost_context")
	var file := FileAccess.open(ARCHIVE, FileAccess.WRITE)
	file.store_string(JSON.stringify(historical, "", true, true))
	file.close()
	var loaded: Dictionary = reader.load_archive()
	check("historical raw report remains view-only and visibly unverified", not loaded.is_empty() and loaded.get("archive_legacy_unverified", false) and loaded.get("total_minor") == historical.get("total_minor"))
	file = FileAccess.open(ARCHIVE, FileAccess.WRITE)
	file.store_string(saved_text)
	file.close()
	check("refused corrupt reads preserve the saved valid quote", not reader.load_archive().is_empty() and reader.archive_load_error.is_empty())


## CR-22e: the runtime writes on a worker thread from a copy; failure, retry and dirty tracking keep the synchronous contract.
func _test_async_archive(session: Variant, bindings: Dictionary) -> void:
	var ledger := Incident.new()
	ledger.async_archive = true
	ledger.begin("jensen-das-ugly-stik-60", str(session.aircraft.input_identity.sha256))
	ledger.observe({tick = 1, events = [_strike(1, bindings)]}, bindings, false)
	ledger.archive_path = "user://missing_accident_directory_%d/report.json" % Time.get_ticks_usec()
	var started: bool = ledger.flush() == OK and ledger._archive_task_id >= 0
	check("background archive failure is reported once, not retried every frame", started and ledger.wait_for_archive() != OK
		and ledger.flush() != OK and ledger._archive_task_id < 0 and ledger._dirty)
	ledger.archive_path = ARCHIVE
	DirAccess.remove_absolute(ARCHIVE)
	check("explicit archival retries a failed background write synchronously", not ledger.archive().is_empty()
		and ledger.load_archive().get("revision") == ledger.report.revision and not ledger._dirty)
	ledger.observe({tick = 2, events = []}, bindings, true) # Terminal: a new full revision.
	var second_started: bool = ledger.flush() == OK and ledger._archive_task_id >= 0
	var written_revision: int = ledger.report.revision
	ledger._queue_assessment(3) # A newer accepted revision arrives while the copy is being written.
	ledger.evaluate_pending()
	check("a report changed during a background write stays dirty and is written next", second_started
		and ledger.wait_for_archive() == OK and ledger._dirty and ledger.load_archive().get("revision") == written_revision
		and ledger.flush() == OK and ledger.wait_for_archive() == OK and not ledger._dirty
		and ledger.load_archive().get("revision") == ledger.report.revision)
	ledger.archive()


func _test_bounds(session: Variant) -> void:
	var ledger := Incident.new()
	ledger.begin("jensen-das-ugly-stik-60", str(session.aircraft.input_identity.sha256))
	var bindings: Dictionary = session.contact_contract()
	for tick in range(1, Incident.MAX_EVENTS + 3):
		var event: Dictionary = Events.hull_events([{index = 0, new = true, depth_m = 0.001}], bindings, PackedStringArray(), tick).events[0]
		ledger.observe({tick = tick, events = [event]}, bindings, false)
	var late_tick := Incident.MAX_EVENTS + 3
	ledger.observe({tick = late_tick, events = [_strike(late_tick, bindings)]}, bindings, false)
	ledger.evaluate_pending()
	check("contact journal is bounded and duplicate parts stay one purchase", ledger.journal.size() <= Incident.MAX_EVENTS and ledger._journal_overflow and ledger.report.get("known_subtotal_minor") == 539)
	check("late prop strike survives a full journal with bounded separate evidence", ledger.report.confirmed_facts.propeller_strike.tick == late_tick and ledger._seen.size() == Incident.MAX_EVENTS)
	var revision: int = ledger.report.revision
	ledger.observe({tick = late_tick, events = [_strike(late_tick, bindings)]}, bindings, false)
	ledger.evaluate_pending()
	check("overflow strike duplicates cannot change valuation or grow dedup memory", ledger.report.revision == revision and ledger._seen.size() == Incident.MAX_EVENTS)
	var bank := _lake_event(late_tick + 1, "bank_ground", bindings)
	ledger.observe({tick = late_tick + 1, events = [bank]}, bindings, true)
	ledger.evaluate_pending()
	check("lake-bank ground impact does not invent water exposure", not ledger.report.confirmed_facts.has("water_exposure") and not str(ledger.report.unresolved).contains("Water exposure"))
	var water := _lake_event(late_tick + 2, "water", bindings)
	ledger.observe({tick = late_tick + 2, events = [water]}, bindings, true)
	ledger.evaluate_pending()
	check("late water exposure survives full history and retains its evidence", ledger.report.confirmed_facts.get("water_exposure", {}).get("material") == "water" and str(ledger.report.unresolved).contains("Water exposure") and ledger.journal.size() <= Incident.MAX_EVENTS and ledger._journal_overflow)
	check("journal truncation is disclosed without discarding bounded summaries", ledger.report.get("journal_truncated", false) and str(ledger.report.get("assumptions", [])).contains("diagnostic event journal is truncated") and ledger.report.get("total_minor") == null)
	ledger.begin("jensen-das-ugly-stik-60", "mismatched-aircraft")
	ledger.observe({tick = 1, events = []}, bindings, true)
	ledger.evaluate_pending()
	check("source mismatch cannot misprice a modified aircraft", ledger.report.get("outcome") == "unavailable" and ledger.report.get("total_minor") == null)
	ledger.archive_path = "user://missing_accident_directory_%d/report.json" % Time.get_ticks_usec()
	check("archive failure is reported without repeated per-frame writes", ledger.flush() != OK and ledger.flush() != OK)
	ledger.archive_path = ARCHIVE
	ledger.archive()
	check("explicit archival retries a previous failed write", ledger.flush() == OK and not ledger.load_archive().is_empty())
	_test_async_archive(session, bindings)
	ledger.begin("jensen-das-ugly-stik-60", str(session.aircraft.input_identity.sha256))
	ledger.observe({tick = 1, events = [{invalid = true}]}, bindings, true)
	ledger.evaluate_pending()
	check("invalid contact evidence still presents a terminal inspection report", ledger.terminal and ledger.report.get("total_minor") == null)
	var corrupt := FileAccess.open(ARCHIVE, FileAccess.WRITE)
	corrupt.store_string('{"format":"openrc-accident-report v1","lines":"invalid"}')
	corrupt.close()
	check("malformed saved report is refused", ledger.load_archive().is_empty())
	var startup: Variant = _make(true)
	check("corrupt saved report is disclosed without blocking a new flight", startup.startup_error.is_empty()
		and startup._accident_incident.report.is_empty() and not startup._accident_incident.archive_load_error.is_empty()
		and startup._accident_report._restore_button.visible and startup._accident_report._restore_button.disabled
		and startup._accident_report._restore_button.text.contains("Saved accident report unavailable"))
	_retire_main(startup)
	ledger.begin("jensen-das-ugly-stik-60", str(session.aircraft.input_identity.sha256))
	ledger.archive_path = ARCHIVE
	ledger.observe({tick = 1, events = [_strike(1, bindings)]}, bindings, false)
	check("reset/archive publishes pending accepted damage without needing a frame", ledger.archive().get("known_subtotal_minor") == 539)


func _strike(tick: int, bindings: Dictionary) -> Dictionary:
	return Events.strike_event({tick = tick, rpm = 4000.0, point_ned = PackedFloat64Array([0.0, 0.0, 0.0]),
		velocity_ned = PackedFloat64Array([1.0, 0.0, 0.0])}, tick, HullContact.law(), bindings)


func _component_line(report: Dictionary, component: String) -> Dictionary:
	for line: Dictionary in report.get("lines", []):
		if line.get("component_id", line.get("id")) == component:
			return line
	return {}


func _component_count(report: Dictionary, component: String) -> int:
	var count := 0
	for line: Dictionary in report.get("lines", []):
		if line.get("component_id", line.get("id")) == component:
			count += 1
	return count


func _test_variant_strikes() -> void:
	for spec: Array in [["stik-glow-55ax-2t", 539, "apc-lp12070"], ["stik-glow-fs64v-4t", 1165, "ma-k14x6"], ["gp-extra-300s-60", 539, "apc-lp12060"]]:
		var main: Variant = _make(true, spec[0])
		var session: Variant = main.session
		session.start_choice = Session.START_RUNWAY
		session.reset()
		check("variant glow start accepts the configured runway state: " + spec[0], session.glow_start())
		session.sim.state = _nose_over(session)
		# Controlled endpoint fixture: just penetrate the disc, retaining the initialized
		# glow continuous state. This tests contact-to-report plumbing, not a flight trajectory.
		var depth: float = HullContact.prop_disc_depth(session.sim.state, session._prop_disc).depth
		session.sim.state[RB.POS + 2] += 0.001 - depth
		session.sim.previous = session.sim.state.duplicate()
		session.sim.set_paused(false)
		session._physics_process(session.sim.dt())
		main._update_accident_report()
		var report: Dictionary = main._accident_incident.report
		check("variant production prop strike remains nonterminal: " + spec[0], not session.prop_strike.is_empty() and session.crash.is_empty())
		check("variant prices its own propeller once: " + spec[0], report.get("known_subtotal_minor") == spec[1])
		var prop_line := _component_line(report, "propeller")
		check("variant retains source identity and scoped game estimate: " + spec[0], prop_line.get("offer_id") == spec[2]
			and str(prop_line.get("source_url", "")).begins_with("https://") and report.get("total_minor") == spec[1]
			and report.get("game_assessment", {}).get("basis") == "scenario_assumption")
		if spec[0] == "stik-glow-fs64v-4t":
			check("sold-out manufacturer offer stays labeled in report", str(prop_line.get("availability", "")).to_lower().contains("sold out"))
		_retire_main(main)


func _lake_event(tick: int, material: String, bindings: Dictionary) -> Dictionary:
	var event := Events._base_event("impact", "lake", "lake:test:%s" % material, "new", tick, "lake-terminal-v1", "terminal")
	event.merge({"lake_id": "test", "material": material, "probe_source": "hull", "probe_id": str(bindings.hull_probes[0].id),
		"point_index": 0, "time_fraction": 0.5, "response_status": "terminal"})
	check("lake fixture uses valid accepted-event contract (%s)" % material, Events.validate_events([event], tick, bindings))
	return event


func _test_cadence(session: Variant) -> void:
	var expected: Dictionary = {}
	var bindings: Dictionary = session.contact_contract()
	for fps in [30, 60, 144]:
		var ledger := Incident.new()
		ledger.begin("jensen-das-ugly-stik-60", str(session.aircraft.input_identity.sha256))
		ledger._identity.incident_id = "cadence-integration-fixture"
		var frame_clock := 0
		for tick in range(1, 961):
			var events: Array = []
			if tick == 1 or tick == 15:
				events.append(_strike(tick, bindings))
			ledger.observe({tick = tick, events = events}, bindings, tick >= 900)
			frame_clock += fps
			if frame_clock >= 240:
				frame_clock -= 240
				ledger.evaluate_pending()
		ledger.evaluate_pending()
		var comparable: Dictionary = ledger.report.duplicate(true)
		comparable.erase("identity")
		comparable.erase("incident_id")
		if expected.is_empty():
			expected = comparable
		check("30/60/144 Hz publication keeps amounts, evidence, tick and revision identical (%d Hz)" % fps, comparable == expected)


func _test_landing(main: Variant, parked_state: PackedFloat64Array) -> void:
	var session: Variant = main.session
	session.sim.state = parked_state.duplicate()
	session.sim.previous = parked_state.duplicate()
	session.sim.inputs.fill(0.0)
	for tick in 1920:
		session.sim.step()
		if main._accident_settled_pending:
			break
	check("settlement queues presentation without opening UI inside accepted ticks", main._accident_settled_pending and not main._accident_report._report_panel.visible)
	var resting_state: PackedFloat64Array = session.sim.state.duplicate()
	session.sim.state[RB.VEL] = 1.0
	main._on_accident_contacts()
	main._update_accident_report()
	check("movement before publication cancels a stale landed card", not main._accident_settled_pending and not main._accident_report._report_panel.visible)
	session.sim.state = resting_state
	session.sim.previous = resting_state.duplicate()
	for tick in 1920:
		session.sim.step()
		if tick % 8 == 0:
			main._update_accident_report()
		if main._accident_report._report_panel.visible:
			break
	check("nonterminal prop damage opens a large report after supported rest", session.crash.is_empty() and main._accident_report._report_panel.visible and not main._accident_report._terminal)
	check("landing presentation preserves the inspection subtotal and no restart action", main._accident_incident.report.get("known_subtotal_minor") == 539 and not main._accident_report._restart_button.visible)
	var state: PackedFloat64Array = session.sim.state.duplicate()
	state[RB.VEL] = 1.0
	session.sim.state = state
	main._on_accident_contacts()
	main._update_accident_report()
	check("renewed movement collapses automatic report without clearing costs or changing physics", not main._accident_report._report_panel.visible and main._accident_report._restore_button.visible and session.sim.state == state and main._accident_incident.report.get("known_subtotal_minor") == 539)


func _nose_over(session: Variant) -> PackedFloat64Array:
	var s: PackedFloat64Array = session.sim.state.duplicate()
	var disc := HullContact.prop_disc(session.aircraft.model.propulsion)
	var q := RB._att(s)
	var pitch := 0.0
	while pitch > -0.6:
		pitch -= 0.002
		var qn := M.q_mul(q, M.q_from_euler(0, pitch, 0))
		for k in 4:
			s[RB.ATT + k] = qn[k]
		if HullContact.prop_disc_depth(s, disc).depth > -0.01:
			break
	var forward := M.q_rotate(M.q_conj(RB._att(s)), M.v3(4.0, 0.0, 0.3))
	for k in 3:
		s[RB.VEL + k] = forward[k]
	return s


func _crash(session: Variant) -> void:
	var s: PackedFloat64Array = session.sim.state.duplicate()
	var hull: PackedFloat64Array = session.aircraft.model.crash_hull
	var deepest := -INF
	for i in range(0, hull.size(), 3):
		deepest = maxf(deepest, M.q_rotate(RB._att(s), hull.slice(i, i + 3))[2])
	s[RB.POS + 2] = -deepest + 0.001
	var velocity := M.q_rotate(M.q_conj(RB._att(s)), PackedFloat64Array([0.0, 0.0, 20.0]))
	for k in 3:
		s[RB.VEL + k] = velocity[k]
		s[RB.RATE + k] = 0.0
	session.sim.state = s
	session.sim.previous = s.duplicate()
	session.sim.previous[RB.POS + 2] -= 0.05
	session._physics_process(session.sim.dt())


## CR-39h: one production hull crash, with crash effects on/off and different publication
## cadences, must yield the same report; only the incident identity may differ.
func _test_terminal_determinism() -> void:
	var expected: Dictionary = {}
	for spec: Array in [[false, 1], [true, 1], [false, 5]]:
		var main: Variant = _make(true, "jensen-das-ugly-stik-60", spec[0])
		var session: Variant = main.session
		session.reset()
		main._accident_incident._identity.incident_id = "terminal-integration-fixture"
		session.sim.set_paused(false)
		for tick in 10:
			session.sim.step()
			if tick % spec[1] == 0:
				main._update_accident_report()
		_crash(session)
		for frame in spec[1]:
			main._update_accident_report()
		var report: Dictionary = main._accident_incident.report.duplicate(true)
		var amount: String = main._accident_report.find_child("ReportAmount", true, false).text
		report.erase("identity")
		report.erase("incident_id")
		var label := "effects %s, publication every %d" % ["on" if spec[0] else "off", spec[1]]
		check("terminal hull crash has the effects director only when requested (%s)" % label, (main._crash_director != null) == spec[0])
		check("terminal hull crash headlines a scoped game estimate (%s)" % label, not session.crash.is_empty() and report.get("terminal", false)
			and report.get("known_subtotal_minor") == 6000 and amount == "US$60.00")
		var tail := _component_line(report, "airframe_tail")
		check("terminal hull crash prices the mapped tail game allowance (%s)" % label,
			tail.get("action") == "selected_purchase" and tail.get("amount_minor") == 6000)
		if expected.is_empty():
			expected = report
		check("terminal crash report is independent of effects and publication cadence (%s)" % label, report == expected)
		_retire_main(main)
		await process_frame


func _retire_main(main: Node) -> void:
	_collect_audio_playbacks(main, audio_playback_refs)
	main.queue_free()


func _collect_audio_playbacks(node: Node, refs: Array[WeakRef]) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		if node.has_stream_playback():
			refs.append(weakref(node.get_stream_playback()))
	for child in node.get_children():
		_collect_audio_playbacks(child, refs)


func _remaining_audio_playbacks() -> int:
	var remaining := 0
	for ref in audio_playback_refs:
		if ref.get_ref() != null:
			remaining += 1
	return remaining

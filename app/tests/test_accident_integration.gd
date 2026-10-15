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


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
	print(("ok   " if passed else "FAIL ") + label)


func _initialize() -> void:
	_run.call_deferred()


func _make(enabled: bool, aircraft_id := "jensen-das-ugly-stik-60") -> Variant:
	var main: Variant = MainScene.instantiate()
	main.aircraft_id = aircraft_id
	main.crash_effects_enabled = false
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
	check("confirmed propeller is priced once at USD 5.39", incident.report.get("known_subtotal_minor") == 539)
	var prop_line: Dictionary = {}
	for line: Dictionary in incident.report.get("lines", []):
		if line.get("id") == "propeller":
			prop_line = line
	check("priced part freezes its source and compatibility notes", str(prop_line.get("source_url", "")).begins_with("https://") and prop_line.get("observed_on") == "2026-10-15" and not str(prop_line.get("notes", "")).is_empty())
	check("shaft and engine inspection prevents a false total or upper cost bound", incident.report.get("total_minor") == null and incident.report.get("high_minor") == null and not incident.report.get("complete", true))
	var revision: int = incident.report.get("revision", -1)
	enabled._on_accident_contacts()
	enabled._update_accident_report()
	check("repeated notification cannot bill the prop twice", incident.report.get("revision") == revision and incident.report.get("known_subtotal_minor") == 539)
	check("snapshot persists outside accepted physics callbacks", incident.flush() == OK and FileAccess.file_exists(ARCHIVE))
	var reader := Incident.new()
	reader.archive_path = ARCHIVE
	check("stored report reopens with frozen catalog identity", reader.load_archive().get("catalog_hash") == incident.report.get("catalog_hash"))
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
	enabled.queue_free()
	disabled.queue_free()
	await process_frame
	await process_frame
	DirAccess.remove_absolute(ARCHIVE)
	DirAccess.remove_absolute(ARCHIVE + ".tmp")
	print("CR-30/32: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


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
	check("contact journal is bounded and duplicate parts stay one purchase", ledger.journal.size() == Incident.MAX_EVENTS and ledger.report.get("known_subtotal_minor") == 539)
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
	check("late water exposure survives full history and retains its evidence", ledger.report.confirmed_facts.get("water_exposure", {}).get("material") == "water" and str(ledger.report.unresolved).contains("Water exposure") and ledger.journal.size() == Incident.MAX_EVENTS)
	check("journal overflow remains explicit incomplete evidence", str(ledger.report.get("unresolved", [])).contains("journal limit") and ledger.report.get("total_minor") == null)
	ledger.begin("jensen-das-ugly-stik-60", "mismatched-aircraft")
	ledger.observe({tick = 1, events = []}, bindings, true)
	ledger.evaluate_pending()
	check("source mismatch cannot misprice a modified aircraft", ledger.report.get("outcome") == "unavailable" and ledger.report.get("total_minor") == null)
	ledger.archive_path = "user://missing_accident_directory_%d/report.json" % Time.get_ticks_usec()
	check("archive failure is reported without repeated per-frame writes", ledger.flush() != OK and ledger.flush() != OK)
	ledger.archive_path = ARCHIVE
	ledger.archive()
	check("explicit archival retries a previous failed write", ledger.flush() == OK and not ledger.load_archive().is_empty())
	ledger.begin("jensen-das-ugly-stik-60", str(session.aircraft.input_identity.sha256))
	ledger.observe({tick = 1, events = [{invalid = true}]}, bindings, true)
	ledger.evaluate_pending()
	check("invalid contact evidence still presents a terminal inspection report", ledger.terminal and ledger.report.get("total_minor") == null)
	var corrupt := FileAccess.open(ARCHIVE, FileAccess.WRITE)
	corrupt.store_string('{"format":"openrc-accident-report v1","lines":"invalid"}')
	corrupt.close()
	check("malformed saved report is refused", ledger.load_archive().is_empty())
	ledger.begin("jensen-das-ugly-stik-60", str(session.aircraft.input_identity.sha256))
	ledger.archive_path = ARCHIVE
	ledger.observe({tick = 1, events = [_strike(1, bindings)]}, bindings, false)
	check("reset/archive publishes pending accepted damage without needing a frame", ledger.archive().get("known_subtotal_minor") == 539)


func _strike(tick: int, bindings: Dictionary) -> Dictionary:
	return Events.strike_event({tick = tick, rpm = 4000.0, point_ned = PackedFloat64Array([0.0, 0.0, 0.0]),
		velocity_ned = PackedFloat64Array([1.0, 0.0, 0.0])}, tick, HullContact.law(), bindings)


func _test_variant_strikes() -> void:
	for spec: Array in [["stik-glow-55ax-2t", 539, "apc-lp12070"], ["stik-glow-fs64v-4t", 1165, "ma-k14x6"]]:
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
		var prop_line: Dictionary = {}
		for line: Dictionary in report.get("lines", []):
			if line.get("id") == "propeller":
				prop_line = line
		check("variant retains selected source identity and inspection uncertainty: " + spec[0], prop_line.get("offer_id") == spec[2] and str(prop_line.get("source_url", "")).begins_with("https://") and report.get("total_minor") == null and report.get("high_minor") == null)
		if spec[0] == "stik-glow-fs64v-4t":
			check("sold-out manufacturer offer stays labeled in report", str(prop_line.get("availability", "")).to_lower().contains("sold out"))
		main.queue_free()


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

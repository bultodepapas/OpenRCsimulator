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


func _make(enabled: bool) -> Variant:
	var main: Variant = MainScene.instantiate()
	main.aircraft_id = "jensen-das-ugly-stik-60"
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
	session.sim.reset(_nose_over(session))
	session.sim.set_paused(false)
	for i in 240:
		session.sim.inputs[3] = 1.0
		session._physics_process(session.sim.dt())
		if not session.prop_strike.is_empty() or not session.crash.is_empty():
			break
		session.sim.step()
	check("production prop strike continues flight with engine stopped", not session.prop_strike.is_empty() and session.crash.is_empty() and not session.engine_running)
	check("confirmed propeller is priced once at USD 5.39", incident.report.get("known_subtotal_minor") == 539)
	check("shaft and engine inspection prevents a false complete repair total", incident.report.get("total_minor") == null and not incident.report.get("complete", true))
	var revision: int = incident.report.get("revision", -1)
	enabled._on_accident_contacts()
	check("repeated notification cannot bill the prop twice", incident.report.get("revision") == revision and incident.report.get("known_subtotal_minor") == 539)
	check("snapshot persists outside accepted physics callbacks", incident.flush() == OK and FileAccess.file_exists(ARCHIVE))
	var reader := Incident.new()
	reader.archive_path = ARCHIVE
	check("stored report reopens with frozen catalog identity", reader.load_archive().get("catalog_hash") == incident.report.get("catalog_hash"))
	var saved_report: Dictionary = incident.report.duplicate(true)
	check("invalid checkpoint cannot discard current costs", not session.restore_checkpoint({}) and incident.report == saved_report)
	var checkpoint: Dictionary = session.checkpoint()
	check("valid physics checkpoint restores", session.restore_checkpoint(checkpoint))
	check("restored prop latch is costed once with explicit missing-history caveat", incident.report.get("known_subtotal_minor") == 539 and str(incident.report.get("unresolved", [])).contains("earlier damage history"))
	session.sim.set_paused(false)
	_crash(session)
	check("terminal production contact opens persistent report", not session.crash.is_empty() and incident.terminal and enabled._accident_report._report_panel.visible)
	check("unknown structural damage does not invent total loss or servo salvage", incident.report.get("total_minor") == null and incident.report.get("salvage_minor") == 0 and incident.report.get("outcome") != "total_loss")
	session.reset()
	check("restart clears only current ledger and keeps archived report", incident.report.is_empty() and not incident.last_report.is_empty() and enabled._accident_report._restore_button.visible)
	check("archived report reopening is view-only", enabled._accident_report._archived)
	_test_bounds(session)
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
		var strike := {tick = tick, rpm = 4000.0, point_ned = PackedFloat64Array([0.0, 0.0, 0.0]), velocity_ned = PackedFloat64Array([1.0, 0.0, 0.0])}
		var event := Events.strike_event(strike, tick, HullContact.law(), bindings)
		ledger.observe({tick = tick, events = [event]}, bindings, false)
	check("contact journal is bounded and duplicate parts stay one purchase", ledger.journal.size() == Incident.MAX_EVENTS and ledger.report.get("known_subtotal_minor") == 539)
	check("journal overflow remains explicit incomplete evidence", str(ledger.report.get("unresolved", [])).contains("journal limit") and ledger.report.get("total_minor") == null)
	ledger.begin("jensen-das-ugly-stik-60", "mismatched-aircraft")
	ledger.observe({tick = 1, events = []}, bindings, true)
	check("source mismatch cannot misprice a modified aircraft", ledger.report.get("outcome") == "unavailable" and ledger.report.get("total_minor") == null)
	ledger.archive_path = ARCHIVE
	var corrupt := FileAccess.open(ARCHIVE, FileAccess.WRITE)
	corrupt.store_string('{"format":"openrc-accident-report v1","lines":"invalid"}')
	corrupt.close()
	check("malformed saved report is refused", ledger.load_archive().is_empty())


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

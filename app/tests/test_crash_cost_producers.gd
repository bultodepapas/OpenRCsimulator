extends SceneTree
## Constructed accepted-endpoint integration fixture; no injected final dispositions.
const Session := preload("res://sim/flight_session.gd")
const Incident := preload("res://economy/incident.gd")
const Events := preload("res://sim/aircraft_contact_events.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const StatisticsAdapter := preload("res://statistics/fixed_wing_adapter.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	var session := Session.new()
	session.soft_hull_contacts = true
	session.setup()
	root.add_child(session)
	session.input_enabled = false
	session.crash_auto_restart = false
	_check("extra observation disabled by default", not session.cost_observations_enabled)
	session.cost_observations_enabled = true
	var stats := StatisticsAdapter.new()
	stats.configure(session, "jensen-das-ugly-stik-60", func(_sample: Dictionary) -> void: pass)
	var stats_before := stats.sample()
	var tiny_support := Events.support_event(0, .000005, 0.0, .1, 1, session.contact_contract())
	_check("statistics fixture starts clear and includes a real tiny proxy", not stats_before.ground_contact and not stats_before.supported and not tiny_support.is_empty())
	session._contact_events.append(tiny_support)
	var stats_after := stats.sample()
	_check("cost proxy does not change statistics contact/support", stats_before.ground_contact == stats_after.ground_contact and stats_before.supported == stats_after.supported and stats_before.incident == stats_after.incident)
	session._contact_events.clear()
	var ledger := Incident.new()
	ledger.begin("jensen-das-ugly-stik-60", str(session.aircraft.input_identity.sha256))
	session.contact_events_changed.connect(func() -> void:
		ledger.observe(session.contact_events(), session.contact_contract(), not session.crash.is_empty()))
	# A settled runway start supplies ordinary accepted support observations, not limit events.
	session.sim.state = RB.make_state(M.v3(0, 0, -.245), M.v3(0, 0, 0), M.q_identity(), M.v3(0, 0, 0))
	session.sim.previous = session.sim.state.duplicate()
	session.sim.tick = 1
	session._on_sim_stepped(1, session.sim.dt(), session.sim.state, PackedFloat64Array(), session.sim.inputs, session.sim.aux)
	var snapshot := session.contact_events()
	var support_count := 0
	for event: Dictionary in snapshot.events:
		if event.format == Events.SUPPORT_FORMAT:
			support_count += 1
			_check("gear producer preserves endpoint channel only", event.measure.has("compression_m") and event.measure.has("travel_limit_m") and not event.measure.has("normal_speed_mps"))
	_check("ordinary support goes through accepted session producer", support_count > 0)
	ledger.evaluate_pending()
	_check("ordinary shallow support stays quiet", not ledger.has_damage() and ledger.report.is_empty())
	# A known accepted terminal gear observation is local. Keep the body's frame frozen.
	session.sim.state = RB.make_state(M.v3(0, 0, -.10), M.v3(0, 0, 2), M.q_identity(), M.v3(0, 0, 0))
	session.sim.previous = session.sim.state.duplicate()
	session.sim.tick = 2
	session._on_sim_stepped(2, 2 * session.sim.dt(), session.sim.state, PackedFloat64Array(), session.sim.inputs, session.sim.aux)
	var before: PackedFloat64Array = session.sim.state.duplicate()
	var engine_before: bool = session.engine_running
	var aux_before: PackedFloat64Array = session.sim.aux.duplicate()
	session._crash(session._gear_limit_impact(session.sim.state))
	ledger.evaluate_pending()
	_check("crash evidence does not alter frozen body/rotor/engine", session.sim.state == before and session.sim.aux == aux_before and session.engine_running == engine_before)
	_check("automatic producer creates priced local decision", ledger.report.get("known_subtotal_minor", 0) >= 3500)
	var prop_count := 0
	for event: Dictionary in session.contact_events().events:
		if event.event_type == "strike":
			prop_count += 1
			_check("terminal prop is an observation, not continued flight", event.format == Events.TERMINAL_PROP_FORMAT and event.response == "terminal")
	_check("terminal coincidence retains one prop fact", prop_count == 1)
	_check("terminal facts validate together", Events.validate_events(session.contact_events().events, session.sim.tick, session.contact_contract()))
	var support := Events.support_event(0, .01, 0.0, .1, 5, session.contact_contract())
	_check("support v2 strict valid", Events.validate_events([support], 5, session.contact_contract()))
	var invalid := support.duplicate(true)
	invalid.format = Events.FORMAT
	_check("v2 support cannot bypass closed v1", not Events.validate_events([invalid], 5, session.contact_contract()))
	if not support.is_empty():
		invalid = support.duplicate(true)
		invalid.measure.compression_m = true
		_check("boolean support measurement rejected", not Events.validate_events([invalid], 5, session.contact_contract()))
	session.free()
	print("%d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL " + label)

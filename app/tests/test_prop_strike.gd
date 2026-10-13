# E3d2: a turning propeller that reaches the field breaks and stops the engine without ending the flight (research 04
# §6 anchor: "a prop-strike-only test keeps the airframe and stops the engine"); takeoff runs never strike.
# Run: godot --headless --path . --script res://tests/test_prop_strike.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Session := preload("res://sim/flight_session.gd")
const HullContact := preload("res://physics/hull_contact.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")

var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print(("ok   " if ok else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))


func _initialize() -> void:
	_geometry()
	var field: Dictionary = FieldLoader.load_from().field
	# Every runway-qualified propeller aircraft (the session refuses a runway start for the others).
	for id: String in Session.RUNWAY_AIRCRAFT_IDS:
		_takeoff_clearance(id, field)
	_nose_over(field)
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _geometry() -> void:
	var disc := HullContact.prop_disc({diameter = 0.30, offset = PackedFloat64Array([-0.40, 0.0, 0.05])})
	_check("the disc sits at the thrust hub (body FRD)", disc.hub == PackedFloat64Array([0.40, 0.0, -0.05]) and is_equal_approx(disc.radius, 0.15))
	var level := RB.make_state(M.v3(0, 0, -1.0), M.v3(0, 0, 0), M.q_from_euler(0, 0, 0), M.v3(0, 0, 0))
	var low := HullContact.prop_disc_depth(level, disc)
	_check("level: the lowest blade tip is one radius below the hub", is_equal_approx(low.depth, -1.0 - 0.05 + 0.15), str(low.depth))
	var nose_down := RB.make_state(M.v3(0, 0, -1.0), M.v3(0, 0, 0), M.q_from_euler(0, -PI / 2.0, 0), M.v3(0, 0, 0))
	var flat := HullContact.prop_disc_depth(nose_down, disc)
	_check("nose straight down: the whole rim is at hub depth", absf(flat.depth - (-1.0 + 0.40)) < 1e-9, str(flat.depth))
	_check("a turbine has no propeller disc", HullContact.prop_disc({kind = "turbine", offset = PackedFloat64Array([0.9, 0, 0])}).is_empty())


func _session(id: String, field: Dictionary) -> Node:
	var session: Node = Session.new()
	session.input_enabled = false
	session.setup(str(Catalog.entry(id).data), id)
	root.add_child(session)
	session.set_field(field)
	session.start_choice = Session.START_RUNWAY
	session.soft_hull_contacts = true
	session.reset()
	return session


func _takeoff_clearance(id: String, field: Dictionary) -> void:
	var session := _session(id, field)
	_check("%s runway start solves" % id, session.start_error.is_empty() and session.is_flyable(), session.start_error)
	var disc := HullContact.prop_disc(session.aircraft.model.propulsion)
	var clearance := -float(HullContact.prop_disc_depth(session.sim.state, disc).depth)
	_check("%s propeller clears the runway at rest" % id, clearance > 0.0, "%.3f m" % clearance)
	# Glow runway starts park with the engine stopped; start it before the takeoff run.
	if session.glow_is_active():
		_check("%s runway starter succeeds" % id, session.glow_start())
	session.sim.set_paused(false)
	for tick in 480:
		session.sim.inputs[3] = 1.0
		session._physics_process(session.sim.dt())
		if not session.crash.is_empty():
			break
		session.sim.step()
	_check("%s full-throttle takeoff run does not strike the propeller" % id, session.prop_strike.is_empty() and session.engine_running and session.crash.is_empty(),
		"strike %s, crash %s" % [str(session.prop_strike.get("tick", "-")), str(session.crash.get("why", "-"))])
	session.free()


func _nose_over(field: Dictionary) -> void:
	var session := _session("jensen-das-ugly-stik-60", field)
	var rest: PackedFloat64Array = session.sim.state.duplicate()
	var disc := HullContact.prop_disc(session.aircraft.model.propulsion)
	# Pitch the resting airplane nose-down about its main wheels until the blade tips sit 1 cm above the runway,
	# rolling at 4 m/s with the engine at full power: the classic landing nose-over.
	var q := RB._att(rest)
	var pitch := 0.0
	var s := rest.duplicate()
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
	var run := func() -> Dictionary:
		session.reset()
		session.sim.reset(s)
		session.sim.set_paused(false)
		var struck_at := -1
		for tick in 240:
			session.sim.inputs[3] = 1.0
			session._physics_process(session.sim.dt())
			if struck_at < 0 and not session.prop_strike.is_empty():
				struck_at = tick
			if not session.crash.is_empty():
				break
			session.sim.step()
		return {struck_at = struck_at, strike = session.prop_strike.duplicate(), running = session.engine_running,
			crash = session.crash.duplicate(), state = session.sim.state.duplicate(), rpm = session.sim.aux[Session.AUX_RPM]}
	var first: Dictionary = run.call()
	_check("a nose-over at full power strikes the propeller", first.struck_at >= 0, "tick %d" % first.struck_at)
	_check("the strike records its rpm and place", float(first.strike.get("rpm", 0.0)) >= HullContact.STRIKE_MIN_RPM and (first.strike.get("point_ned", PackedFloat64Array()) as PackedFloat64Array).size() == 3)
	_check("the strike stops the engine", not first.running and float(first.rpm) < HullContact.STRIKE_MIN_RPM, "rpm %.0f" % float(first.rpm))
	_check("a prop strike alone is not a crash", first.crash.is_empty(), str(first.crash.get("why", "")))
	_check("a prop strike repeats exactly", (run.call() as Dictionary).state == first.state)
	session.soft_hull_contacts = false
	session.reset()
	session.sim.reset(s)
	session.sim.set_paused(false)
	for tick in 60:
		session._physics_process(session.sim.dt())
		if not session.crash.is_empty():
			break
		session.sim.step()
	_check("the legacy route never registers a prop strike", session.prop_strike.is_empty())
	session.free()

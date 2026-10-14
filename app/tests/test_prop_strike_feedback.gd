# E3d2: in the production flight scene a prop strike breaks the blades, throws blade fragments, keeps the flight
# going; a later crash keeps the propeller broken on the wreck; restart restores everything. US-V11: the Stik keeps
# its hub and shows splintered stubs, on the flying model, through the blur and on the wreck.
# Run: godot --headless --path . --script res://tests/test_prop_strike_feedback.gd
extends SceneTree

const MainScene = preload("res://main.tscn")
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
const Session = preload("res://sim/flight_session.gd")
const HullContact = preload("res://physics/hull_contact.gd")

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print(("ok   " if ok else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Variant = MainScene.instantiate()
	main.set("aircraft_id", "jensen-das-ugly-stik-60")
	root.add_child(main)
	await process_frame
	var session: Variant = main.get("session")
	var director: Variant = main.get("_crash_director")
	if session == null or director == null or not session.soft_hull_contacts:
		_check("production scene with soft contacts", false)
		_finish(main)
		return
	session.input_enabled = false
	session.set_physics_process(false)
	session.start_choice = Session.START_RUNWAY
	session.reset()
	director.update(session.sim.dt())
	var propeller: Node3D = main.get("_airplane").propeller
	var blades := propeller.get_node("propeller_blades") as Node3D
	var stubs := propeller.get_node("propeller_stubs") as Node3D
	var blur: Variant = main.get_node_or_null("PropellerBlur")
	_check("blades are visible before the strike, stubs hidden", propeller.visible and blades.visible and not stubs.visible)
	var s := _nose_over(session)
	session.sim.reset(s)
	session.sim.set_paused(false)
	var chips_seen := false
	for tick in 240:
		session.sim.inputs[3] = 1.0
		session._physics_process(session.sim.dt())
		director.update(session.sim.dt())
		chips_seen = chips_seen or director.effects.blade_chips.emitting
		if not session.crash.is_empty():
			break
		session.sim.step()
	_check("the nose-over strikes the propeller in production", not session.prop_strike.is_empty())
	_check("the broken blades disappear and the stubs stay on the hub", propeller.visible and not blades.visible and stubs.visible)
	if blur != null:
		for rpm in [9000.0, 0.0]:
			blur.update(rpm)
			_check("the blur keeps the broken blades hidden at %.0f rpm" % rpm, not blades.visible and stubs.visible
				and not blur.get("_disc").visible)
	_check("blade fragments fly", chips_seen)
	_check("the flight goes on with the engine stopped", session.crash.is_empty() and not session.engine_running)
	_check("the crash aftermath stays idle", not director.active)
	_check("particle budget still holds", int(director.effects.stats().particles) <= 700, str(director.effects.stats().particles))
	# A crash after the strike: arm a 20 m/s descent onto the hull from the current state.
	var crash_state: PackedFloat64Array = session.sim.state.duplicate()
	var hull: PackedFloat64Array = session.aircraft.model.crash_hull
	var deepest := -INF
	for i in range(0, hull.size(), 3):
		deepest = maxf(deepest, M.q_rotate(RB._att(crash_state), hull.slice(i, i + 3))[2])
	crash_state[RB.POS + 2] = -deepest + 0.001 # the lowest hull point 1 mm into the field
	var v_body := M.q_rotate(M.q_conj(RB._att(crash_state)), PackedFloat64Array([0.0, 0.0, 20.0]))
	for k in 3:
		crash_state[RB.VEL + k] = v_body[k]
		crash_state[RB.RATE + k] = 0.0
	var before := crash_state.duplicate()
	before[RB.POS + 2] -= 0.05
	session.sim.state = crash_state
	session.sim.previous = before
	session._physics_process(session.sim.dt())
	director.update(session.sim.dt())
	_check("a later crash starts the aftermath", director.active, str(session.crash.get("why", "no crash")))
	if director.active:
		_check("the crash report remembers the broken propeller", bool(director.report.get("prop_broken", false))
			and (director.report.cause.factors as Array).has("after a prop strike"), CrashCause_line(director))
		var prop_group: Dictionary = {}
		for group: Dictionary in director.wreck._groups:
			if String(group.kind) == "propeller":
				prop_group = group
		var twin_blades: Node3D = null
		var twin_stubs: Node3D = null
		for member: Node3D in prop_group.get("members", []):
			twin_blades = twin_blades if twin_blades != null else member.find_child("propeller_blades", true, false) as Node3D
			twin_stubs = twin_stubs if twin_stubs != null else member.find_child("propeller_stubs", true, false) as Node3D
		_check("the wreck does not throw the broken propeller again", not prop_group.is_empty() and not bool(prop_group.detached))
		_check("the wreck shows the same stubs", twin_blades != null and twin_stubs != null and not twin_blades.visible and twin_stubs.visible)
		director.wreck._process(0.5) # release every scheduled section before summing
		var mass := 0.0
		for body: RigidBody3D in director.wreck._bodies:
			if body.visible:
				mass += body.mass
		_check("wreck mass stays conserved", absf(mass - float(session.sim.mass)) < 0.001, "%.4f vs %.4f" % [mass, float(session.sim.mass)])
	session.reset()
	director.update(session.sim.dt())
	if blur != null:
		blur.update(0.0)
	_check("restart restores the propeller and clears the strike", propeller.visible and blades.visible and not stubs.visible
		and session.prop_strike.is_empty() and session.engine_running)
	_check("restart unbreaks the wreck twin's propeller", director.wreck._hidden_members.is_empty())
	_finish(main)


func CrashCause_line(director: Variant) -> String:
	return str(director.report.get("cause", {}).get("factors", []))


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


func _finish(main: Variant) -> void:
	main.queue_free()
	await process_frame
	await process_frame
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures else 0)

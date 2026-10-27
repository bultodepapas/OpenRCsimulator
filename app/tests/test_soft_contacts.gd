# E3d1: soft crash-hull contacts (docs/plans/crash-realism.md, research 04 §6 anchors). A wingtip brush and a belly
# slide continue the flight; a 10 m/s nose-in and a deep crush end it; flight away from the ground and the default
# (off) route are unchanged.
# Run: godot --headless --path . --script res://tests/test_soft_contacts.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const HullContact := preload("res://physics/hull_contact.gd")
const Severity := preload("res://render/crash/severity.gd")
const AVANTI := "res://data/aircraft/sebart_avanti_s_a200.json"
const AVANTI_ID := "sebart-avanti-s-a200-p100rx"

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + "  " + detail)
	if not ok:
		_failures += 1


func _initialize() -> void:
	_check("terminal cut equals the CR-08b C2 boundary", HullContact.TERMINAL_J_PER_KG == Severity.CLASS_CUTS_J_PER_KG[1])
	_check("contact frequency respects ω·dt ≤ 0.25 at 240 Hz", HullContact.OMEGA_RAD_S / 240.0 <= 0.25 + 1e-12)
	var stik := _session()
	_default_is_legacy(stik)
	_loads_shape(stik)
	_wingtip_brush(stik)
	_nose_in(stik)
	_depth_backstop(stik)
	_airborne_identity(stik)
	_determinism(stik)
	_identity(stik)
	_cached_contact_refresh(stik)
	stik.free()
	var avanti := _session(AVANTI, AVANTI_ID)
	_belly_slide(avanti)
	avanti.free()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures else 0)


func _session(path := "", id := "") -> Node:
	var session := FlightSession.new()
	if path.is_empty():
		session.setup()
	else:
		session.setup(path, id)
	root.add_child(session)
	session.input_enabled = false
	session.reset()
	return session


## A state whose lowest hull point (for this attitude) sits `clearance` above the field.
func _state_above(session: Node, clearance: float, yaw: float, pitch: float, roll: float, v_ned: PackedFloat64Array,
		rates := M.v3(0, 0, 0)) -> PackedFloat64Array:
	var q := M.q_from_euler(yaw, pitch, roll)
	var hull: PackedFloat64Array = session.aircraft.model.crash_hull
	var lowest := -INF
	for i in range(0, hull.size(), 3):
		lowest = maxf(lowest, M.q_rotate(q, hull.slice(i, i + 3))[2])
	return RB.make_state(M.v3(0, 0, -(lowest + clearance)), M.q_rotate(M.q_conj(q), v_ned), q, rates)


## Steps the real session tick (crash check, then integration) and reports the first contact and crash ticks.
func _run(session: Node, s: PackedFloat64Array, soft: bool, ticks: int) -> Dictionary:
	session.soft_hull_contacts = soft
	session.reset()
	session.sim.reset(s)
	session.sim.set_paused(false)
	var first_contact := -1
	var crashed_at := -1
	var max_depth := 0.0
	for t in ticks:
		session._physics_process(session.sim.dt())
		if not session.crash.is_empty():
			crashed_at = t
			break
		# Finite-fuel sessions prepare geometry only; force coefficients are sampled per stage from live mass properties.
		# The contact indicator needs geometry and states only, so use the same representation without requesting forces.
		if first_contact < 0 and not HullContact.contacts(session.sim.previous, session.sim.state, session._hull_contact).is_empty():
			first_contact = t
		max_depth = maxf(max_depth, _deepest(session, session.sim.state))
		session.sim.step()
	return {first_contact = first_contact, crashed_at = crashed_at, max_depth = max_depth, state = session.sim.state.duplicate()}


func _deepest(session: Node, s: PackedFloat64Array) -> float:
	var hull: PackedFloat64Array = session.aircraft.model.crash_hull
	var q := RB._att(s)
	var deepest := -INF
	for i in range(0, hull.size(), 3):
		deepest = maxf(deepest, s[RB.POS + 2] + M.q_rotate(q, hull.slice(i, i + 3))[2])
	return deepest


func _default_is_legacy(session: Node) -> void:
	_check("soft contacts are off by default", not session.soft_hull_contacts)
	var brush := _state_above(session, 0.01, 0.0, 0.0, deg_to_rad(40.0), M.v3(15, 0, 0.5))
	var legacy := _run(session, brush, false, 120)
	_check("default route: a wingtip brush is still a crash (D9d)", legacy.crashed_at >= 0 and session.crash.impact.trigger == "hull_contact")


func _loads_shape(session: Node) -> void:
	var prepared: Dictionary = session._hull_contact
	_check("hull contact is prepared for the Stik", not prepared.is_empty() and prepared.stiffness.size() == session.aircraft.model.crash_hull.size() / 3)
	var names: PackedStringArray = session.aircraft.model.crash_hull_components
	var hull: PackedFloat64Array = session.aircraft.model.crash_hull
	# GP-07b: the drawn-model hull has no belly point (the wheels always touch first); compare with the point nearest
	# the CG, whose effective mass is the largest.
	var nearest := 0
	for i in names.size():
		if M.norm(hull.slice(3 * i, 3 * i + 3)) < M.norm(hull.slice(3 * nearest, 3 * nearest + 3)):
			nearest = i
	var tip_k: float = prepared.stiffness[names.find("left_wing_tip")]
	var belly_k: float = prepared.stiffness[nearest]
	var bound: float = float(prepared.mass) * HullContact.OMEGA_RAD_S * HullContact.OMEGA_RAD_S
	var bounded := true
	for k: float in prepared.stiffness:
		bounded = bounded and k > 0.0 and k <= bound * (1.0 + 1e-12)
	_check("every point is no stiffer than the whole mass at the contact frequency", bounded)
	_check("a wingtip (small effective mass) is softer than the point nearest the CG", tip_k < 0.5 * belly_k,
		"tip %.0f, %s %.0f N/m" % [tip_k, names[nearest], belly_k])
	var air := _state_above(session, 0.5, 0.0, 0.0, 0.0, M.v3(15, 0, 0))
	_check("no load above the ground", HullContact.loads(air, prepared).is_empty())
	var sunk := _state_above(session, -0.005, 0.0, 0.0, 0.0, M.v3(3, 0, 0))
	var loads := HullContact.loads(sunk, prepared)
	_check("the sunk lowest level point is pushed up (body −z)", loads.size() == 6 and loads[2] < 0.0)
	_check("friction opposes the slide (body −x)", loads.size() == 6 and loads[0] < 0.0)
	var mu_ok := loads.size() == 6 and absf(loads[0]) <= HullContact.FRICTION_MU * absf(loads[2]) + 1e-9
	_check("friction stays inside the Coulomb bound", mu_ok)
	var rising := sunk.duplicate()
	rising[RB.VEL + 2] = -20.0 # leaving the ground fast: the damper must not pull it back
	_check("a damper never pulls into the ground", HullContact.loads(rising, prepared).is_empty() or HullContact.loads(rising, prepared)[2] <= 0.0)


func _wingtip_brush(session: Node) -> void:
	# Research 04 anchor: a wingtip touched at walking pace rocks back. Bank 40°, 15 m/s, sinking 0.5 m/s.
	var brush := _state_above(session, 0.01, 0.0, 0.0, deg_to_rad(40.0), M.v3(15, 0, 0.5))
	var soft := _run(session, brush, true, 72)
	_check("wingtip brush touches the ground", soft.first_contact >= 0, "first contact tick %d" % soft.first_contact)
	_check("wingtip brush does not end the flight", soft.crashed_at < 0, "crashed at %d" % soft.crashed_at)
	_check("wingtip brush penetrates only a few centimetres", soft.max_depth < 0.03, "max depth %.4f m" % soft.max_depth)


func _nose_in(session: Node) -> void:
	# Research 04 anchor: a nose-in at 10 m/s is a crash.
	var nose := _state_above(session, 0.01, 0.0, -PI / 2.0, 0.0, M.v3(0, 0, 10))
	var hit := _run(session, nose, true, 48)
	_check("10 m/s vertical nose-in ends the flight", hit.crashed_at >= 0)
	if hit.crashed_at >= 0:
		var impact: Variant = session.crash.impact
		var names: PackedStringArray = session.aircraft.model.crash_hull_components
		_check("the crash names the spinner and the impact rule", impact.point_index >= 0 and names[impact.point_index] == "spinner" and impact.soft_rule == "impact",
			"%s %s" % [names[impact.point_index] if impact.point_index >= 0 else "?", impact.soft_rule])


func _depth_backstop(session: Node) -> void:
	var prepared: Dictionary = session._hull_contact
	var before := _state_above(session, 0.0, 0.0, 0.0, 0.0, M.v3(0, 0, 0))
	var crushed := before.duplicate()
	crushed[RB.POS + 2] += HullContact.CRASH_DEPTH_M + 0.01
	before[RB.POS + 2] += HullContact.CRASH_DEPTH_M - 0.01 # already touching: not a new impact
	var hit := HullContact.terminal(before, crushed, prepared)
	_check("a crush deeper than the backstop is a crash", int(hit.index) >= 0 and hit.rule == "depth")
	# Already touching on the previous tick and still pressing down hard: not a new impact (the depth rule watches it).
	var pressing := _state_above(session, -0.01, 0.0, 0.0, 0.0, M.v3(0, 0, 10)) # only the lowest level point, 1 cm deep
	var still := pressing.duplicate()
	still[RB.POS + 2] += 0.005
	_check("a point already in contact is not graded as a new impact", int(HullContact.terminal(pressing, still, prepared).index) < 0)


func _airborne_identity(session: Node) -> void:
	var cruise := _state_above(session, 30.0, 0.0, 0.0, 0.0, M.v3(15, 0, 0))
	var off := _run(session, cruise, false, 240)
	var on := _run(session, cruise, true, 240)
	_check("one second of flight away from the ground is bit-identical with soft contacts on", off.state == on.state)


func _identity(session: Node) -> void:
	session.soft_hull_contacts = false
	session.reset()
	var legacy_config: String = session._checkpoint_configuration()
	var legacy_meta: Dictionary = session.trace_meta()
	session.soft_hull_contacts = true
	var soft_config: String = session._checkpoint_configuration()
	var soft_meta: Dictionary = session.trace_meta()
	_check("legacy trace metadata has no contact-law key", not legacy_meta.has("hull_contact_model"))
	_check("soft trace metadata records the contact law", soft_meta.get("hull_contact_model", "") == HullContact.law())
	_check("soft contacts change the checkpoint configuration", soft_config != legacy_config)
	var checkpoint: Dictionary = session.checkpoint()
	session.soft_hull_contacts = false
	_check("a soft-contact checkpoint is refused by a legacy session", not checkpoint.is_empty() and not session.restore_checkpoint(checkpoint))
	session.soft_hull_contacts = true
	_check("the same session restores its own checkpoint", session.restore_checkpoint(checkpoint))
	_check("the contact law names its constants", HullContact.law().contains("omega=60") and HullContact.law().contains("terminal_j_per_kg=2.5"))
	session.soft_hull_contacts = false
	session.reset()


func _cached_contact_refresh(session: Node) -> void:
	session.soft_hull_contacts = false
	session.reset()
	var brush := _state_above(session, -0.005, 0.0, 0.0, deg_to_rad(40.0), M.v3(0, 0, 0))
	session.sim.reset(brush)
	session.sim.set_paused(false)
	var expected: Array = HullContact.contacts(session.sim.previous, session.sim.state, session._hull_contact)
	_check("same-tick contact fixture touches the hull", not expected.is_empty())
	session.soft_hull_contacts = true
	var ready: bool = session._session_after_input()
	_check("same-tick mode enable preserves the flight", ready and session.crash.is_empty())
	_check("same-tick mode enable refreshes presentation contacts", session.soft_contacts == expected)
	session.sim.state = _state_above(session, 0.02, 0.0, 0.0, deg_to_rad(40.0), M.v3(0, 0, 0))
	expected = HullContact.contacts(session.sim.previous, session.sim.state, session._hull_contact)
	session._session_after_input()
	_check("same-tick state change refreshes presentation contacts", session.soft_contacts == expected)
	session.soft_hull_contacts = false
	session.reset()


func _determinism(session: Node) -> void:
	var brush := _state_above(session, 0.01, 0.0, 0.0, deg_to_rad(40.0), M.v3(15, 0, 0.5))
	_check("a soft contact run repeats exactly", _run(session, brush, true, 120).state == _run(session, brush, true, 120).state)


func _belly_slide(session: Node) -> void:
	# Research 04 anchor: a belly at 1 m/s sink slides to a stop. The Vantage Jet has no landing gear.
	_check("Vantage Jet session loads", session.aircraft.get("ok", false))
	session.sim.inputs[3] = 0.0
	var belly := _state_above(session, 0.01, 0.0, 0.0, 0.0, M.v3(12, 0, 1.0))
	var slide := _run(session, belly, true, 1440)
	var end: PackedFloat64Array = slide.state
	var speed := M.norm(RB._slice3(end, RB.VEL))
	_check("belly landing at 1 m/s sink does not end the flight", slide.crashed_at < 0, "crashed at %d" % slide.crashed_at)
	_check("the belly slide brings the airplane to a stop", speed < 1.0, "speed after 6 s %.2f m/s" % speed)
	_check("the slide stays finite", _finite(end))
	_check("the belly stays near the surface", absf(_deepest(session, end)) < 0.05, "deepest point %.4f m" % _deepest(session, end))


func _finite(s: PackedFloat64Array) -> bool:
	for value in s:
		if not is_finite(value):
			return false
	return true

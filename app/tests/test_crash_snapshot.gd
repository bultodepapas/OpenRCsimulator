# CR-01a: known rigid-point kinematics, detector ordering and session lifecycle.
extends SceneTree

const Impact = preload("res://physics/impact_snapshot.gd")
const FlightSession = preload("res://sim/flight_session.gd")
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")

var _count: int = 0
var _failures: int = 0


func _check(label: String, ok: bool) -> void:
	_count += 1
	if not ok:
		_failures += 1
	print(("ok   " if ok else "FAIL ") + label)


func _near(a: PackedFloat64Array, b: PackedFloat64Array) -> bool:
	return a.size() == b.size() and M.norm(M.sub(a, b)) < 1e-12


func _state(down: float = 0.0) -> PackedFloat64Array:
	return RB.make_state(M.v3(10, 20, down), M.v3(3, 4, 2), M.q_identity(), M.v3(2, 0, 0))


func _initialize() -> void:
	var s: PackedFloat64Array = _state()
	var hull: PackedFloat64Array = PackedFloat64Array([0, 1, 0, 0, -1, 0])
	var hit: Impact.Snapshot = Impact.hull_contact(s, 42, hull)
	_check("typed hull trigger and observed tick", hit.trigger == "hull_contact" and hit.tick == 42)
	_check("first simultaneous point is in data order", hit.point_index == 0 and hit.component_name.is_empty())
	_check("hull point translated to world", _near(hit.point_ned, M.v3(10, 21, 0)))
	_check("point velocity includes omega cross r", _near(hit.velocity_ned, M.v3(3, 4, 4)))
	_check("point speed differs from CG speed", absf(hit.speed_mps - sqrt(41.0)) < 1e-12)
	_check("down velocity is signed into flat ground", hit.down_speed_mps == 4.0)
	_check("flat ground normal points up", hit.normal_ned == M.v3(0, 0, -1))
	_check("hull kinematics known, gear compression unknown", hit.has_kinematics and not hit.has_compression)
	_check("description uses point speed and detected timing", hit.description().contains("point speed 6.4 m/s at detected tick"))
	var saved_state: PackedFloat64Array = hit.detected_state.duplicate()
	s[0] = -10
	hull[1] = -10
	_check("snapshot owns state and geometry", hit.detected_state == saved_state and hit.body_point == M.v3(0, 1, 0))

	s = RB.make_state(M.v3(10, 20, 0), M.v3(3, 0, 2), M.q_from_euler(PI/2, 0, 0), M.v3(0, 0, 2))
	hit = Impact.hull_contact(s, 3, PackedFloat64Array([1, 0, 0]))
	_check("rotated world contact position", _near(hit.point_ned, M.v3(10, 21, 0)))
	_check("rotate velocity after body-rate contribution", _near(hit.velocity_ned, M.v3(-2, 3, 2)))
	s = _state()
	s[RB.VEL+2] = -5
	hit = Impact.hull_contact(s, 0, PackedFloat64Array([0, 1, 0]))
	_check("already touching but moving upward stays negative", hit.down_speed_mps == -3)
	for down in [-1e-12, 0.0, 1e-12]:
		hit = Impact.hull_contact(_state(down), 0, PackedFloat64Array([0, 0, 0]))
		_check("exact hull >= zero boundary %s" % down, (hit.point_index == 0) == (down >= 0))
	hit = Impact.hull_contact(_state(), 0, PackedFloat64Array([0, 0, -1, 0, 1, 0, 0, 2, 1]))
	_check("skips clear point; chooses first contact, not deepest", hit.point_index == 1)
	hit = Impact.hull_contact(_state(), 0, PackedFloat64Array())
	_check("unknown hull point explicit", hit.point_index == -1 and not hit.has_kinematics and hit.point_ned.is_empty())
	s = _state()
	s[RB.RATE] = 1e308
	hit = Impact.hull_contact(s, 0, PackedFloat64Array([0, 2, 0]))
	_check("overflowed kinematics unavailable, no infinity leaked", not hit.has_kinematics and hit.velocity_ned.is_empty() and is_finite(hit.speed_mps))

	var gear: Dictionary = {reach = 1.0, contacts = [
		{name = "left", position = M.v3(0, -1, .2), max_compression = .1},
		{name = "right", position = M.v3(0, 1, .2), max_compression = .1}]}
	hit = Impact.gear_limit(_state(-.1), 7, gear)
	_check("gear exactly at travel is not a limit trigger", hit.point_index == -1 and not hit.has_compression)
	hit = Impact.gear_limit(_state(-.09), 8, gear)
	_check("gear trigger names first failing leg", hit.trigger == "gear_limit" and hit.component_name == "left" and hit.point_index == 0)
	_check("gear compression and travel exact", hit.has_compression and absf(hit.compression_m-.11) < 1e-12 and hit.travel_limit_m == .1)
	_check("deforming wheel kinematics explicitly unknown", not hit.has_kinematics and hit.point_ned.is_empty() and hit.velocity_ned.is_empty())
	_check("gear cause states travel limit, not structural collapse", hit.description() == "landing gear travel limit (left)")
	gear.contacts[0].position[0] = 100
	_check("gear reference coordinate owned", hit.body_point[0] == 0)
	hit = Impact.gear_limit(_state(), 0, {})
	_check("no gear leaves fields unavailable", hit.point_index == -1 and not hit.has_compression)
	hit = Impact.gear_limit(_state(-2), 0, gear)
	_check("gear reach guard preserved", hit.point_index == -1)

	_session_checks()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures else 0)


func _session_checks() -> void:
	var session: Node = FlightSession.new()
	session.setup()
	root.add_child(session)
	session.input_enabled = false
	var checkpoint: Dictionary = session.checkpoint()
	var body: PackedFloat64Array = _state(-.05)
	session.sim.state = body.duplicate()
	session.sim.previous = body.duplicate()
	session.sim.tick = 12
	session.sim.set_paused(false)
	session._physics_process(session.sim.dt())
	_check("session detects hull before simultaneously collapsed gear", session.crash.impact.trigger == "hull_contact")
	var hit: Impact.Snapshot = session.crash.impact
	_check("snapshot captures current tick and body", hit.tick == 12 and hit.detected_state == body)
	_check("diagnostic does not move simulation to a guessed impact pose", session.sim.state == body and session.sim.tick == 12)
	_check("legacy crash speed remains CG speed", absf(session.crash.speed-sqrt(29.0)) < 1e-12)
	_check("legacy crash sink calculation preserved", session.crash.sink == 0.0)
	_check("existing readout uses typed cause", session.crash.why == hit.description() and session.pause_reason.contains(hit.description()))
	var ticks_left: int = session.crash.ticks_left
	session.hold("cr01a-test")
	for i in 4:
		session._physics_process(session.sim.dt())
	_check("menu hold preserves snapshot and countdown", session.crash.impact == hit and session.crash.ticks_left == ticks_left)
	session.release("cr01a-test")
	session._physics_process(session.sim.dt())
	_check("crash countdown preserves the same observed snapshot", session.crash.impact == hit and session.crash.ticks_left == ticks_left-1)
	session.reset()
	_check("manual restart clears an active snapshot", session.crash.is_empty())
	session.sim.state = body.duplicate()
	session.sim.previous = body.duplicate()
	session._physics_process(session.sim.dt())
	_check("second crash exists before checkpoint restore", not session.crash.is_empty())
	_check("restore clears transient crash snapshot", session.restore_checkpoint(checkpoint) and session.crash.is_empty())
	session.reset()
	session.sim.state = _state(-.10)
	session.sim.previous = session.sim.state.duplicate()
	session.sim.set_paused(false)
	session._physics_process(session.sim.dt())
	_check("real gear-limit snapshot", session.crash.impact.trigger == "gear_limit" and session.crash.impact.component_name == "main_left")
	_check("gear readout has no invented contact speed", not session.crash.why.contains("point speed"))
	for i in 360:
		session._physics_process(session.sim.dt())
	_check("automatic restart still lasts 360 ticks", session.crash.is_empty() and session.sim.tick == 0 and not session.sim.paused)
	_check("retained diagnostic remains an owned old observation", hit.tick == 12 and hit.detected_state == body)
	session.free()

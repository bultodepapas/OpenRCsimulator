## CR-AUD-02 regression (collision audit 2026-11-17): a nonterminal helicopter body contact with frangible scenery is
## no longer dropped. The detector reports it beside the (empty) terminal impact and the session applies the shared
## bounded scenery response inside the accepted step. Constructed 240 Hz, 2 m/s crossing of a 20 mm box; not a
## material-strength or flown-trajectory claim.
extends SceneTree

const Session := preload("res://sim/helicopter_flight_session.gd")
const Detector := preload("res://physics/rotorcraft/impact_detector.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
const SceneryCollision := preload("res://sim/scenery_collision.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if not condition:
		failures += 1
	print("%s %s %s" % ["ok  " if condition else "FAIL", label, detail])


func _world(north: float, east: float, down: float, response: String) -> Dictionary:
	var proxies: Array[Dictionary] = []
	CollisionWorld._add_box_at_down(proxies, "fixture", "rc_track", "tyre_stack", response,
		north, east, down, 0.010, 0.010, 0.003, 0.0)
	return {"format": CollisionWorld.FORMAT, "identity": "heli-scenery-response-" + response, "cell_size_m": 32.0,
		"proxies": proxies, "bins": CollisionWorld._build_bins(proxies)}


func _fuselage_point(prepared: Dictionary) -> PackedFloat64Array:
	for probe: Dictionary in prepared.probes:
		var point: PackedFloat64Array = probe.point
		if str(probe.component) == "fuselage" and point[0] > 0.0 and point[2] > 0.0:
			return point
	return PackedFloat64Array()


func _session(world: Dictionary) -> Node:
	var session: Node = Session.new()
	session.physics_enabled = false
	session.input_enabled = false
	root.add_child(session)
	_check("session %s sets up" % world.get("identity", "open"), session.setup() and session.set_collision_world(world)
		and session.reset())
	return session


func _run() -> void:
	var probe_session := _session({})
	var prepared: Dictionary = probe_session._impact_geometry
	var chosen := _fuselage_point(prepared)
	_check("a lower-front fuselage probe exists", chosen.size() == 3, str(chosen))
	probe_session.free()
	if chosen.size() != 3:
		_finish()
		return
	var start := PackedFloat64Array([5.0, 5.0, -10.0, 2.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var n: float = start[0] + chosen[0] + 1.0 / 240.0
	var e: float = start[1] + chosen[1]
	var d: float = start[2] + chosen[2]
	var soft := _world(n, e, d, "frangible_impulse")

	# Detector: the nonterminal contact is reported, the terminal impact stays empty.
	var loaded_session := _session({})
	var aircraft: Dictionary = loaded_session.aircraft
	var end: PackedFloat64Array = start.duplicate()
	end[0] += 2.0 / 240.0
	var continuous := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var phase := PackedFloat64Array([0.0, 0.0])
	var detected: Dictionary = Detector.evaluate(start, end, continuous, aircraft.context, aircraft.skids,
		PackedFloat64Array(), phase, soft, prepared)
	_check("detector reports the frangible contact as nonterminal", bool(detected.get("ok", false))
		and detected.impact.is_empty() and detected.get("nonterminal_scenery") is SceneryCollision.Event, str(detected.keys()))
	var hard: Dictionary = Detector.evaluate(start, end, continuous, aircraft.context, aircraft.skids,
		PackedFloat64Array(), phase, _world(n, e, d, "hard_terminal"), prepared)
	_check("a hard box stays a terminal fuselage impact without a nonterminal report",
		str(hard.get("impact", {}).get("component", "")) == "fuselage" and not hard.has("nonterminal_scenery"))
	var open: Dictionary = Detector.evaluate(start, end, continuous, aircraft.context, aircraft.skids,
		PackedFloat64Array(), phase, {}, prepared)
	_check("open air reports neither", open.impact.is_empty() and not open.has("nonterminal_scenery"))
	loaded_session.free()

	# Session: one accepted tick through the box versus the same tick in open air.
	var north_speed := {}
	for label: String in ["open", "soft"]:
		var session := _session({} if label == "open" else soft)
		var state: PackedFloat64Array = session.sim.state.duplicate()
		for index in RB.SIZE:
			state[index] = start[index]
		session.sim.state = state
		session.sim.previous = state.duplicate()
		var before: int = session.sim.tick
		session.sim.step()
		var accepted: bool = session.sim.tick == before + 1 and session.sim.fault_reason.is_empty()
		_check("%s tick is accepted without fault or crash" % label, accepted and session.crash.is_empty(),
			"%s %s" % [session.sim.fault_reason, str(session.crash)])
		var q: PackedFloat64Array = RB._att(session.sim.state)
		north_speed[label] = M.q_rotate(q, RB._slice3(session.sim.state, RB.VEL))[0]
		session.free()
	_check("the frangible contact slows the accepted body (bounded dissipative response)",
		float(north_speed.get("soft", INF)) < float(north_speed.get("open", -INF)) - 0.3
		and float(north_speed.get("soft", -INF)) > -2.0, str(north_speed))
	_finish()


func _finish() -> void:
	print("CR-AUD-02 helicopter scenery response: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)

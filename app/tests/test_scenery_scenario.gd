# The runway scenario stays flyable: the same runway start and scripted pilot as app/scenery/runway_scenario.gd, flown
# headless for 12 s. Catches physics or data changes that would break the visual scenario before any capture runs.
# Run: godot --headless --path . --script res://tests/test_scenery_scenario.gd
extends SceneTree

const FieldLoader = preload("res://data/field_loader.gd")
const FlightSession = preload("res://sim/flight_session.gd")
const Catalog = preload("res://app_state/aircraft_catalog.gd")
const GroundStart = preload("res://physics/ground_start.gd")
const TakeoffPilot = preload("res://scenery/takeoff_pilot.gd")
const M = preload("res://physics/math3d.gd")

var _failures := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	var field: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH).field
	var session := FlightSession.new()
	session.setup(Catalog.entry(Catalog.DEFAULT_ID).data)
	session.set_field(field)
	root.add_child(session)
	var start := GroundStart.threshold(field)
	_check("the field has a runway threshold", start.ok)
	_check("the runway start solves (E3b2)", session.reset_on_runway(start.north, start.east, start.heading))
	var sim: Node = session.sim
	sim.set_paused(true)
	session.input_enabled = false
	var lift_off := -1.0
	var max_heading_err := 0.0
	var idle_speed := 0.0
	var phases := {}
	for i in roundi(12.0 / sim.dt()):
		var t: float = sim.time()
		var out := TakeoffPilot.step(t, sim.state, start.heading)
		phases[out.phase] = true
		session.commands = out.commands
		sim.inputs = session._inputs()
		sim.step()
		var s: PackedFloat64Array = sim.state
		var speed := sqrt(s[3] * s[3] + s[4] * s[4] + s[5] * s[5])
		if t < TakeoffPilot.IDLE_S:
			idle_speed = maxf(idle_speed, speed)
		if lift_off < 0.0 and not session.touches_ground(s) and -s[2] > 1.0:
			lift_off = sim.time()
		max_heading_err = maxf(max_heading_err, absf(wrapf(M.q_to_euler(s.slice(6, 10))[0] - start.heading, -PI, PI)))
		if session.touches_ground(s) and -s[2] < -0.5:
			_check("no ground strike", false, "at t = %.2f s" % sim.time())
			break
	var s: PackedFloat64Array = sim.state
	_check("still while idling (max %s m/s)" % str(idle_speed), idle_speed < 0.01)
	_check("lifts off between 4 and 8 s (%.2f s)" % lift_off, lift_off > 4.0 and lift_off < 8.0)
	_check("airborne and climbing at 12 s (%.1f m)" % -s[2], -s[2] > 20.0)
	_check("runway heading held within 5° (%.2f°)" % rad_to_deg(max_heading_err), rad_to_deg(max_heading_err) < 5.0)
	_check("every phase flown", phases.has("idle") and phases.has("roll") and phases.has("climb"))
	session.free()
	print("all scenery scenario checks passed" if _failures == 0 else "%d scenery scenario checks failed" % _failures)
	quit(1 if _failures > 0 else 0)

# EX-08-R1: static support and takeoff regression for the provisional Extra runway start.
# breakaway_factor=1.25 is a shared E3b1 engineering estimate borrowed from Stik,
# not an Extra measurement or physical validation.
# Run from the repository root:
# godot --headless --path app --script res://tests/test_extra_runway.gd
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const GroundStart := preload("res://physics/ground_start.gd")
const Ground := preload("res://physics/ground_contact.gd")
const RB := preload("res://physics/rigid_body.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var loaded := FieldLoader.load_from()
	_check("default field loads", loaded.ok, str(loaded.get("errors", [])))
	if not loaded.ok:
		quit(1)
		return
	var field: Dictionary = loaded.field
	var spot := GroundStart.threshold(field)
	_check("default runway threshold resolves", spot.ok, str(spot))
	if not spot.ok:
		quit(1)
		return
	for rate in [240, 480]:
		_run_rate(int(rate), field)
	print("Extra runway: %d checks, %d failed; factor is estimated, not measured" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _run_rate(rate: int, field: Dictionary) -> void:
	Engine.physics_ticks_per_second = rate
	var session := Flight.new()
	session.input_enabled = false
	session.crash_auto_restart = false
	session.setup("res://data/aircraft/gp_extra_300s_60.json", "gp-extra-300s-60")
	_check("%d Hz Extra data prepares" % rate, session.is_flyable(), session.start_error)
	_check("%d Hz default field installs" % rate, session.set_field(field), session.surface_error)
	session.start_choice = Flight.START_RUNWAY
	session.reset()
	var started: bool = session.is_flyable() and session.start_error.is_empty()
	_check("%d Hz runway equilibrium starts" % rate, started and session.sim.tick == 0
		and session.sim.fault_reason.is_empty(), session.start_error + " " + session.sim.fault_reason)
	if not started:
		session.free()
		return
	var start: PackedFloat64Array = session.sim.state.duplicate()
	var initial_anchors: PackedFloat64Array = _anchor_flags(session)
	_check("%d Hz all three wheel anchors begin stuck" % rate,
		initial_anchors.size() == 3 and initial_anchors[0] == 1.0 and initial_anchors[1] == 1.0 and initial_anchors[2] == 1.0,
		str(initial_anchors))
	var dt: float = session.sim.dt()
	_check("%d Hz uses the requested solver step" % rate, is_equal_approx(dt, 1.0 / rate))
	for _tick in roundi(6.0 / dt):
		session.sim.step()
		session._physics_process(dt)
		if not session.sim.fault_reason.is_empty() or not session.crash.is_empty() or not session.prop_strike.is_empty():
			break
	var idle: PackedFloat64Array = session.sim.state
	var idle_speed := _speed(idle)
	var idle_drift := sqrt((idle[RB.POS] - start[RB.POS]) ** 2 + (idle[RB.POS + 1] - start[RB.POS + 1]) ** 2)
	_check("%d Hz six-second idle stays parked" % rate,
		session.sim.tick == roundi(6.0 / dt) and idle_speed < 1e-5 and idle_drift < 1e-5
		and _anchor_flags(session) == initial_anchors and session.sim.fault_reason.is_empty()
		and session.crash.is_empty() and session.prop_strike.is_empty(),
		"speed %.8f m/s, drift %.8f m, crash=%s prop_strike=%s fault=%s" % [idle_speed, idle_drift,
			str(session.crash), str(session.prop_strike), session.sim.fault_reason])
	var inputs: PackedFloat64Array = session.sim.inputs.duplicate()
	inputs[1] = 0.35
	inputs[3] = 1.0
	session.sim.inputs = inputs
	var airborne_tick := -1
	for tick in roundi(3.0 / dt):
		session.sim.step()
		session._physics_process(dt)
		if airborne_tick < 0 and _airborne(session):
			airborne_tick = tick + 1
		if not session.sim.fault_reason.is_empty() or not session.crash.is_empty() or not session.prop_strike.is_empty():
			break
	var finish: PackedFloat64Array = session.sim.state
	var altitude_gain := start[RB.POS + 2] - finish[RB.POS + 2]
	var final_anchors := _anchor_flags(session)
	_check("%d Hz 3 s takeoff clears runway with session crash/prop-strike checks" % rate,
		airborne_tick >= 0 and _speed(finish) > 15.0 and altitude_gain > 1.0
		and final_anchors.size() == 3 and final_anchors[0] == 0.0 and final_anchors[1] == 0.0 and final_anchors[2] == 0.0
		and session.sim.fault_reason.is_empty() and session.crash.is_empty() and session.prop_strike.is_empty(),
		"lifted at %.3f s; speed %.2f m/s, altitude +%.2f m, anchors=%s, crash=%s, prop_strike=%s, fault=%s" % [
			airborne_tick * dt, _speed(finish), altitude_gain, str(final_anchors), str(session.crash),
			str(session.prop_strike), session.sim.fault_reason])
	session.free()


func _anchor_flags(session: Node) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	for i in session.anchor_count():
		result.append(session.sim.aux[Flight.AUX_ANCHORS + i * Ground.ANCHOR_STRIDE + 2])
	return result


func _airborne(session: Node) -> bool:
	for compression in session.gear_compressions(session.sim.state):
		if compression > 0.0:
			return false
	return true


func _speed(state: PackedFloat64Array) -> float:
	return sqrt(state[RB.VEL] ** 2 + state[RB.VEL + 1] ** 2 + state[RB.VEL + 2] ** 2)


func _check(label: String, passed: bool, detail := "") -> void:
	checks += 1
	print(("ok   " if passed else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not passed:
		failures += 1

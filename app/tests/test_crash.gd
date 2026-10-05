# D9d: ground contact → crash → freeze (impact shown) → clean restart, from any attitude.
# Run: godot --headless --path . --script res://tests/test_crash.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const FlightSession := preload("res://sim/flight_session.gd")

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + "  " + detail)
	if not ok:
		_failures += 1


func _at(alt: float, yaw: float, pitch: float, roll: float) -> PackedFloat64Array:
	return RB.make_state(M.v3(0, 0, -alt), M.v3(10, 0, 0), M.q_from_euler(yaw, pitch, roll), M.v3(0, 0, 0))


func _initialize() -> void:
	var session := FlightSession.new()
	session.setup()
	root.add_child(session)
	session.input_enabled = false
	session.reset()

	# The hull: level, the wheels hang 0.25 m below the thrust line; inverted, the fin top is 0.26 m above it.
	_check("level at 0.30 m: clear of the ground", not session.touches_ground(_at(0.30, 0.0, 0.0, 0.0)))
	_check("level at 0.20 m: the wheels touch", session.touches_ground(_at(0.20, 0.0, 0.0, 0.0)))
	_check("inverted at 0.35 m: clear", not session.touches_ground(_at(0.35, 0.0, 0.0, PI)))
	_check("inverted at 0.20 m: the fin touches", session.touches_ground(_at(0.20, 0.0, 0.0, PI)))
	_check("knife edge at 0.70 m: the down wing tip touches", session.touches_ground(_at(0.70, 0.0, 0.0, PI / 2.0)))
	_check("knife edge at 0.85 m: clear", not session.touches_ground(_at(0.85, 0.0, 0.0, PI / 2.0)))
	_check("vertical dive at 0.30 m: the spinner touches", session.touches_ground(_at(0.30, 0.0, -PI / 2.0, 0.0)))

	# Crash from 100 random attitudes and velocities just above the ground: detected, frozen, then a clean restart.
	var rng := RandomNumberGenerator.new()
	rng.seed = 61
	var start: PackedFloat64Array = session.start.state
	var ok_all := true
	var detail := ""
	for i in 100:
		# Any attitude and rates; the velocity points at the ground (NED down 2–15 m/s), expressed in body axes.
		var q := M.q_from_euler(rng.randf_range(-PI, PI), rng.randf_range(-1.5, 1.5), rng.randf_range(-PI, PI))
		var v_ned := M.v3(rng.randf_range(-20, 20), rng.randf_range(-20, 20), rng.randf_range(2.0, 15.0))
		var s := RB.make_state(M.v3(rng.randf_range(-50, 50), rng.randf_range(-50, 50), -rng.randf_range(1.0, 3.0)),
			M.q_rotate(M.q_conj(q), v_ned), q, M.v3(rng.randf_range(-6, 6), rng.randf_range(-6, 6), rng.randf_range(-6, 6)))
		session.sim.reset(s)
		session.sim.set_paused(false)
		var crashed_at := -1
		for t in 2400:
			session._physics_process(session.sim.dt()) # the session's tick: crash check, freeze countdown, restart
			if crashed_at >= 0 and session.crash.is_empty():
				break # restarted this tick
			if crashed_at < 0 and not session.crash.is_empty():
				crashed_at = t
				var finite: bool = is_finite(session.crash.speed) and is_finite(session.crash.sink)
				ok_all = ok_all and finite and session.pause_reason.begins_with("CRASH")
			if not session.sim.paused:
				session.sim.step()
		var restarted: bool = session.sim.state == start and session.sim.tick == 0 and not session.sim.paused and session.pause_reason == ""
		if crashed_at < 0 or not restarted:
			ok_all = false
			detail = "case %d: crashed at tick %d, restarted %s" % [i, crashed_at, restarted]
			break
	_check("100 random crashes: detected, impact finite and shown, then restart at the trimmed start", ok_all, detail)

	# The freeze lasts 1.5 s of physics ticks, and R (reset) skips it.
	session.sim.reset(_at(0.1, 0.0, 0.0, 0.0))
	session.sim.set_paused(false)
	session._physics_process(session.sim.dt())
	var held := 0
	while not session.crash.is_empty():
		session._physics_process(session.sim.dt())
		held += 1
	_check("crash freeze = 1.5 s (360 ticks)", held == 360, "%d ticks" % held)
	session.sim.reset(_at(0.1, 0.0, 0.0, 0.0))
	session.sim.set_paused(false)
	session._physics_process(session.sim.dt())
	session.reset()
	_check("R during the freeze restarts at once", session.crash.is_empty() and not session.sim.paused and session.pause_reason == "")

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)

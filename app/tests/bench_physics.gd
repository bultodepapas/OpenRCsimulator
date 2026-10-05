# Physics cost per 240 Hz tick of the real flight session (ROADMAP rule 7: every aero step reports µs/tick).
# NOT a test (timing depends on the machine): run it before and after a physics change.
# Run: godot --headless --path . --script res://tests/bench_physics.gd
extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const TICKS := 2400 # 10 s of flight


func _initialize() -> void:
	var session := FlightSession.new()
	session.setup()
	root.add_child(session)
	session.input_enabled = false
	session.reset()
	var best := 1e30
	for run in 3:
		session.reset()
		var t0 := Time.get_ticks_usec()
		for i in TICKS:
			session.sim.step()
		best = minf(best, float(Time.get_ticks_usec() - t0) / TICKS)
	print("physics: %.1f µs per tick (best of 3 × %d ticks; budget 500 µs on the owner's slowest machine)" % [best, TICKS])
	quit()

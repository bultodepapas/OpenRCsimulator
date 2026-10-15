# P51-26: best-of-7 wall time of Slipstream.loads for the P-51 at one powered sideslipping state (2,000 calls each).
# Shared-host timing: compare interleaved runs only. Run against app/ or a disposable copy with --path.
extends SceneTree
const AircraftData := preload("res://physics/aircraft_data.gd")
const Slipstream := preload("res://physics/slipstream.gd")
const Air := preload("res://physics/air_data.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
func _initialize() -> void:
	var model: Dictionary = AircraftData.load_file("res://data/aircraft/p51d_mustang_120.json").model
	var s := RB.make_state(M.v3(0, 0, -100), M.v3(28.0, 1.2, 1.5), M.q_identity(), M.v3(0.1, 0.05, 0.08))
	var air := Air.compute(s, M.v3(0, 0, 0), 1.225)
	var d := { elevator = -0.02, aileron_right = 0.01, aileron_left = -0.01, rudder = 0.03 }
	var best := INF
	for rep in 7:
		var t0 := Time.get_ticks_usec()
		for i in 2000:
			Slipstream.loads(s, air, d, model, 5200.0, 1.225)
		best = minf(best, float(Time.get_ticks_usec() - t0) / 2000.0)
	print("Slipstream.loads best-of-7: %.2f us/call (x4 RK stages = %.1f us/tick)" % [best, 4.0 * best])
	quit(0)

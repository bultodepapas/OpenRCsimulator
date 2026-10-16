extends SceneTree
# P51-26: P-51 slipstream cost, segmented against the legacy centroid law, best of 7 × 2000 calls.
const AircraftData := preload("res://physics/aircraft_data.gd")
const Slipstream := preload("res://physics/slipstream.gd")
const Aero := preload("res://physics/aero.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const Air := preload("res://physics/air_data.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

func _best(f: Callable) -> float:
	var best := INF
	for rep in 7:
		var t0 := Time.get_ticks_usec()
		for i in 2000:
			f.call()
		best = minf(best, float(Time.get_ticks_usec() - t0) / 2000.0)
	return best

func _initialize() -> void:
	var model: Dictionary = AircraftData.load_file("res://data/aircraft/p51d_mustang_120.json").model
	var legacy: Dictionary = model.duplicate(true)
	legacy.propulsion.slipstream.erase("propeller_sidewash")
	var s := RB.make_state(M.v3(0, 0, -100), M.v3(28.0, 1.2, 1.5), M.q_identity(), M.v3(0.1, 0.05, 0.08))
	var air := Air.compute(s, M.v3(0, 0, 0), 1.225)
	var d := { elevator = -0.02, aileron_right = 0.01, aileron_left = -0.01, rudder = 0.03 }
	var wake := Aero.wing_wake_velocity(s, air, d, model)
	var tail: Dictionary = model.surfaces.horizontal
	print("segmented loads   %.2f us" % _best(func(): Slipstream.loads(s, air, d, model, 5200.0, 1.225, wake)))
	print("legacy loads      %.2f us" % _best(func(): Slipstream.loads(s, air, d, legacy, 5200.0, 1.225, wake)))
	print("tail law (1 eval) %.2f us" % _best(func(): Aero._tail_surface_from_flow(M.v3(28, 1, 2), M.v3(-1.2, 0.1, -0.2), d, tail, model.surfaces, 0.1, false, 1.225, wake)))
	print("thrust_torque     %.2f us" % _best(func(): Propulsion.thrust_torque(air.v_air, 5200.0, model.propulsion, 1.225)))
	print("normal_force      %.2f us" % _best(func(): Propulsion.normal_force(air.v_air, 5200.0, model.propulsion, 1.225)))
	print("wing_wake_velocity %.2f us" % _best(func(): Aero.wing_wake_velocity(s, air, d, model)))
	quit(0)

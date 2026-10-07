# E0b3b: whole-session cost with/without the neutral-geometry experimental test fixture.
# Not an aircraft calibration or handling test. Run headless with --script pointing to this file.
extends SceneTree
const Flight = preload("res://sim/flight_session.gd")
const Fixture = preload("res://tests/test_wash_profile.gd")
const AD = preload("res://physics/aircraft_data.gd")
const Air = preload("res://physics/air_data.gd")
const Aero = preload("res://physics/aero.gd")
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
const TICKS: int = 120


func _initialize() -> void:
	var data: Dictionary = AD.validate_and_derive(Fixture.combined_raw())
	if not data.ok:
		quit(1)
		return
	var failed: bool = false
	for regime: String in ["forward", "stall", "static", "spin", "reverse_fade", "reverse_off"]:
		for enabled: bool in [false, true]:
			var flight: Node = Flight.new()
			flight.setup()
			root.add_child(flight)
			flight.input_enabled = false
			flight.aircraft.model = data.model.duplicate(true)
			if not enabled:
				flight.aircraft.model.propulsion.erase("slipstream")
			var s: PackedFloat64Array = flight.sim.state.duplicate()
			var speed: float = 0.0 if regime == "static" else 15.0
			if regime.begins_with("reverse"):
				var vi0: float = data.model.propulsion.max_rpm/60.0*data.model.propulsion.diameter*sqrt(2*data.model.propulsion.ct[1]/PI)
				speed = (-0.15 if regime == "reverse_fade" else -0.3)*vi0
			if regime == "spin":
				s[RB.RATE] = 0.5
				s[RB.RATE+1] = -0.3
				s[RB.RATE+2] = 1.5
			var alpha: float = deg_to_rad(15.0 if regime in ["stall", "spin"] else (0.0 if regime.begins_with("reverse") else 3.0))
			s[RB.POS+2] = -100.0
			s[RB.VEL] = speed*cos(alpha)
			s[RB.VEL+2] = speed*sin(alpha)
			flight.sim.state = s
			flight.sim.previous = s.duplicate()
			flight.sim.aux[0] = data.model.propulsion.max_rpm
			flight.sim.aux[flight.downwash_index()] = Aero.wing_lift_coefficient(s,
				Air.compute(s, M.v3(0, 0, 0), 1.225), flight._deflections(flight.sim.aux), data.model)
			var snapshot: Dictionary = flight.sim.checkpoint()
			var values: Array[float] = []
			for sample in 5:
				if not flight.sim.restore_checkpoint(snapshot):
					failed = true
				var started: int = Time.get_ticks_usec()
				for tick in TICKS:
					flight.sim.step()
				values.append(float(Time.get_ticks_usec()-started)/TICKS)
				failed = failed or not flight.sim.fault_reason.is_empty() or flight.sim.tick != int(snapshot.tick) + TICKS
			values.sort()
			print("E0b3b experimental %s wash=%s median=%.1f us/tick samples=%s" % [regime, enabled, values[2], values])
			flight.free()
	print("completed without simulation faults: ", not failed)
	quit(1 if failed else 0)

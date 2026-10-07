# E0b5: paired instant/transport cost on the same uncalibrated profile fixture.
extends SceneTree
const Flight = preload("res://sim/flight_session.gd")
const Fixture = preload("res://tests/test_wash_transport.gd")
const RB = preload("res://physics/rigid_body.gd")
const Aero = preload("res://physics/aero.gd")
const Air = preload("res://physics/air_data.gd")
const TICKS: int = 120

func _initialize() -> void:
	var rows: Array = []
	for regime: String in ["forward", "stall", "static", "spin", "reverse_fade", "reverse_off"]:
		for enabled: bool in [false, true]:
			var flight: Node = Flight.new()
			if not Fixture.configure(flight):
				quit(1)
				return
			if not enabled:
				flight.aircraft.model.propulsion.slipstream.erase("transport_speed_floor")
			flight.reset()
			var s: PackedFloat64Array = flight.sim.state.duplicate()
			var speed: float = 0.0 if regime == "static" else 15.0
			if regime.begins_with("reverse"):
				var prop: Dictionary = flight.aircraft.model.propulsion
				var vi0: float = prop.max_rpm/60.0*prop.diameter*sqrt(2*prop.ct[1]/PI)
				speed = (-0.15 if regime == "reverse_fade" else -0.3)*vi0
			var alpha: float = deg_to_rad(15.0 if regime in ["stall", "spin"] else (0.0 if regime.begins_with("reverse") else 3.0))
			s[RB.POS+2] = -100.0
			s[RB.VEL] = speed*cos(alpha)
			s[RB.VEL+2] = speed*sin(alpha)
			if regime == "spin":
				s[RB.RATE] = 0.5
				s[RB.RATE+1] = -0.3
				s[RB.RATE+2] = 1.5
			flight.sim.aux[0] = flight.aircraft.model.propulsion.max_rpm
			flight.sim.aux[flight.downwash_index()] = Aero.wing_lift_coefficient(s,
				Air.compute(s, PackedFloat64Array([0,0,0]), 1.225), flight._deflections(flight.sim.aux), flight.aircraft.model)
			flight.sim.continuous = flight._settled_wash(s, flight.sim.aux)
			if not flight.sim.reset(s):
				quit(1)
				return
			var cp: Dictionary = flight.sim.checkpoint()
			var times: Array[float] = []
			for batch: int in 6:
				if not flight.sim.restore_checkpoint(cp):
					quit(1)
					return
				var begin: int = Time.get_ticks_usec()
				for tick: int in TICKS:
					flight.sim.step()
				if flight.sim.tick != TICKS or not flight.sim.fault_reason.is_empty():
					quit(1)
					return
				if batch > 0: # warm-up excluded
					times.append(float(Time.get_ticks_usec()-begin)/TICKS)
			times.sort()
			rows.append({regime = regime, transport = enabled, median_us = times[2], batches_us = times})
			print("E0b5 %s transport=%s median %.1f us/tick" % [regime, enabled, times[2]])
			flight.free()
	var path: String = OS.get_cmdline_user_args()[0]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({format = "openrc-e0b5-transport-cost v1", ticks_per_batch = TICKS,
		cpu = OS.get_processor_name(), godot = Engine.get_version_info().string, rows = rows}, "\t", true, true)+"\n")
	quit()

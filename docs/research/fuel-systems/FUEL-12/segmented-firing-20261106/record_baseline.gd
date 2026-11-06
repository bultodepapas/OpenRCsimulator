extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const Log := preload("res://sim/flight_log.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
var failed := false
func _initialize() -> void:
	for spec: Array in [["55ax-exhaust", "stik-glow-55ax-2t", true], ["fs64-exhaust", "stik-glow-fs64v-4t", true],
		["extra-exhaust", "gp-extra-300s-60", true], ["55ax-control", "stik-glow-55ax-2t", false]]:
		var flight := Flight.new()
		flight.input_enabled = false
		flight.crash_auto_restart = false
		flight.setup(Catalog.entry(spec[1]).data)
		var install: Dictionary = flight.aircraft.model.propulsion.glow
		var fill: float = (install.unusable_fuel_kg + (2.0e-6 if spec[1] == "stik-glow-fs64v-4t" else 1.0e-6)) / install.capacity_fuel_kg if spec[2] else 1.0
		if not flight.set_fuel_start_fill(fill): failed = true
		flight.reset()
		var logger := Log.new(flight)
		var path := "C:/DEVELOPMENT/OpenRCsimulator/tmp/glow-counter-a4/flights/" + str(spec[0]) + ".orfl"
		if logger.start(path) != OK:
			printerr(logger.failure)
			failed = true
		else:
			logger.mark("near-reserve exhaustion" if spec[2] else "event-free control")
			for tick: int in 32:
				flight.sim.step()
				if not flight.sim.fault_reason.is_empty():
					printerr(flight.sim.fault_reason)
					failed = true
					break
			if logger.stop() != OK: failed = true
			print(spec[0], " baseline ticks=", flight.sim.tick)
		logger = null
		flight.free()
	print("GLOW_BASELINES_COMPLETE=", not failed)
	quit(1 if failed else 0)

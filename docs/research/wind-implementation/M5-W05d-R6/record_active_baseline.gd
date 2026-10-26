## Uses the existing recorder and R5 authored workload; no custom recording format.
extends "res://tests/bench_spatial_wind.gd"

func _initialize() -> void:
	var output := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output = argument.trim_prefix("--out=")
	if output.is_empty():
		quit(1)
		return
	var flight := FlightSession.new()
	flight.setup(AircraftCatalog.data_for("gp-extra-300s-60", "ideal"))
	root.add_child(flight)
	flight.commands = Commands.neutral_commands()
	var weather := _session_weather_config("spatial-v5-gusts-thermals-24")
	if not flight.setup_weather(weather.config):
		flight.free()
		quit(1)
		return
	flight.reset()
	var logger := FlightLog.new(flight)
	if not _session_start_is_valid(flight) or logger.start(output) != OK:
		flight.free()
		quit(1)
		return
	logger.mark("active gust and mature thermal; deterministic input tape")
	for tick in 480:
		flight.sim.inputs[0] = 0.025 if tick < 240 else -0.025
		flight.sim.inputs[1] = 0.01
		flight.sim.inputs[2] = -0.005
		flight.sim.inputs[3] = 0.45
		flight.sim.step()
		if not flight.sim.fault_reason.is_empty() or flight.sim.tick != tick + 1:
			logger.stop("failed workload")
			flight.free()
			quit(1)
			return
		if tick == 239:
			logger.mark("reverse aileron at gust peak")
	var accepted := _session_state_is_finite(flight) and flight.crash.is_empty() and logger.stop() == OK
	flight.free()
	print("active baseline recorded: 480 ticks; accepted=", accepted)
	quit(0 if accepted else 1)

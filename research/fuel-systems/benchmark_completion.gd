## Paired source-checkout timing probe; setup/import excluded, identical absolute command tape.
extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const TICKS := 600
const REPEATS := 5
var output_path := ""
var aircraft_path := "res://data/aircraft/stik_glow_61fx_2t.json"

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output_path = argument.trim_prefix("--out=")
		elif argument.begins_with("--aircraft="):
			aircraft_path = argument.trim_prefix("--aircraft=")
	if output_path.is_empty() or FileAccess.file_exists(output_path):
		printerr("Use --out=<new absolute JSON path>")
		quit(2)
		return
	var runs: Array = []
	var failed := false
	for fill: float in [1.0, 0.1]:
		var flight: Node = Flight.new()
		flight.input_enabled = false
		flight.setup(aircraft_path)
		flight.set_fuel_start_fill(fill)
		flight.reset()
		var initial: Dictionary = flight.checkpoint()
		if not flight.is_flyable() or initial.is_empty():
			failed = true
			flight.free()
			continue
		for repeat: int in range(-1, REPEATS):
			if not flight.restore_checkpoint(initial):
				failed = true
				break
			var started: int = Time.get_ticks_usec()
			for tick: int in TICKS:
				flight.sim.inputs[0] = 0.05 if tick < 120 else (-0.05 if tick < 240 else 0.0)
				flight.sim.inputs[1] = -0.02 if tick < 300 else 0.02
				flight.sim.inputs[2] = 0.0
				flight.sim.inputs[3] = 0.5 if tick < 300 else 0.35
				flight.sim.step()
			var elapsed: int = Time.get_ticks_usec() - started
			if not flight.sim.fault_reason.is_empty() or flight.sim.tick != TICKS:
				failed = true
			if repeat >= 0:
				runs.append({fill=fill,repeat=repeat,ticks=flight.sim.tick,elapsed_usec=elapsed,
					usec_per_tick=float(elapsed)/TICKS,fault=flight.sim.fault_reason})
		flight.free()
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({format="openrc-fuel-cost v1",engine=Engine.get_version_info().string,
		aircraft_path=aircraft_path,ticks=TICKS,repeats=REPEATS,initial_warmup_runs=1,failed=failed,runs=runs,
		scope="headless physics only; setup/import/recording excluded; same absolute tape; not target GPU qualification"},"\t",true,true))
	file.close()
	print("Fuel cost: %s; %s" % [str(not failed),output_path])
	quit(1 if failed else 0)

# G2a: serialized simulation-step batch means; no renderer or trim cost in the timed interval.
extends SceneTree
const Flight = preload("res://sim/flight_session.gd")
const Wind = preload("res://physics/wind_config.gd")
const PATH: String = "res://data/aircraft/p51d_mustang_120.json"
const BATCH: int = 240
const SAMPLES: int = 7


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	var output: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output = argument.substr(6)
	if output.is_empty():
		printerr("--out=absolute-report.json required")
		quit(1)
		return
	var cases: Array[Dictionary] = []
	for weather: String in ["calm", "hot-high"]:
		for fixture: String in ["trim", "punch"]:
			for mode: String in ["split", "coupled-rk4"]:
				var flight: Flight = Flight.new()
				flight.setup_shaft_integrator(mode)
				flight.setup_weather(Wind.preset(weather))
				flight.setup(PATH)
				flight.input_enabled = false
				var means: Array[float] = []
				for sample: int in SAMPLES:
					flight.reset()
					if fixture == "punch":
						flight.sim.inputs[3] = 0.8
					for tick: int in BATCH:
						flight.sim.step()
					var before: int = Time.get_ticks_usec()
					for tick: int in BATCH:
						flight.sim.step()
					means.append(float(Time.get_ticks_usec() - before) / BATCH)
					if flight.sim.tick != 2 * BATCH or not flight.sim.fault_reason.is_empty():
						printerr("cost flight fault: ", flight.sim.fault_reason)
						flight.free()
						quit(1)
						return
				var ordered: Array[float] = means.duplicate()
				ordered.sort()
				cases.append({weather = weather, fixture = fixture, integrator = mode, samples_usec_per_tick = means,
					median_batch_mean_usec = ordered[SAMPLES / 2], endpoint_rpm = flight.sim.aux[0]})
				flight.free()
	var report: Dictionary = {format = "openrc-coupled-shaft-cost v1", engine = Engine.get_version_info().string,
		cpu = OS.get_processor_name(), logical_cpus = OS.get_processor_count(), samples = SAMPLES, ticks_per_sample = BATCH,
		warmup_ticks_per_sample = BATCH, tick_hz = 240, timing_scope = "median of seven simulation-step batch means; no individual tick tails or renderer", cases = cases}
	var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	file.close()
	print("Eight serial P-51 simulation-step cost cases recorded.")
	quit(0)

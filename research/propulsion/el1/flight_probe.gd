# EL1d/e software qualification. The synthetic pilot below is a test fixture, not flight assistance.
extends SceneTree
const Flight = preload("res://sim/flight_session.gd")
const Recorder = preload("res://sim/recorder.gd")
const M = preload("res://physics/math3d.gd")
const Prop = preload("res://physics/propulsion.gd")
var failures: int = 0


func make_flight(config: String) -> Node:
	var flight: Node = Flight.new()
	flight.setup(config if config.begins_with("res://") else "res://data/aircraft/synthetic_stik_electric_%s.json" % config)
	flight.input_enabled = false
	flight.set_start_altitude(150.0)
	flight.reset()
	return flight


func run_scenario(config: String, scenario: String, output: String) -> Dictionary:
	var flight: Node = make_flight(config)
	if not flight.is_flyable():
		failures += 1
		flight.free()
		return {ok = false, message = "trim refused"}
	var start_pitch: float = M.q_to_euler(flight.sim.state.slice(6, 10))[1]
	var recorder: RefCounted = Recorder.new(flight.sim, flight.electrical_state)
	recorder.start(flight.trace_meta())
	for tick: int in 7200:
		var s: PackedFloat64Array = flight.sim.state
		var angles: PackedFloat64Array = M.q_to_euler(s.slice(6, 10))
		var t: float = flight.sim.time()
		if scenario != "level":
			var pitch_target: float = start_pitch + (0.06 if scenario == "climb" else 0.0)
			var roll_target: float = 0.35 if scenario == "turn" and t >= 1.0 else 0.0
			var beta: float = M.atan2_(s[4], M.sqrt_(s[3] * s[3] + s[5] * s[5]))
			var duty: float = flight.start.throttle + (0.2 if scenario == "climb" else 0.08 if scenario == "turn" else 0.0)
			if scenario == "chop" and t >= 5.0 and t < 15.0:
				duty = 0.0
				pitch_target = -0.10
			flight.commands = {roll = clampf(0.8 * (roll_target - angles[2]) - 0.3 * s[10], -1.0, 1.0),
				pitch = clampf(1.2 * (pitch_target - angles[1]) - 0.6 * s[11], -1.0, 1.0),
				yaw = clampf(10.0 * beta, -1.0, 1.0), throttle = clampf(duty, 0.0, 1.0)}
			flight.sim.inputs = flight._inputs()
		flight.sim.step()
		if not flight.sim.fault_reason.is_empty() or flight.sim.tick != tick + 1:
			break
	var trace: RefCounted = recorder.trace
	var rows: int = trace.row_count()
	var last: int = rows - 1
	var complete: bool = flight.sim.tick == 7200 and flight.sim.fault_reason.is_empty() and rows == 7201
	var saved: bool = trace.save(output.path_join(config + "-" + scenario + ".csv")) == OK
	var result: Dictionary = {ok = complete and saved, tick = flight.sim.tick, fault = flight.sim.fault_reason,
		rows = rows, altitude_change_m = trace.value(last, "alt_m") - trace.value(0, "alt_m"),
		final_rpm = flight.sim.aux[0], final_speed_mps = trace.value(last, "speed_mps"),
		final_yaw_deg = trace.value(last, "yaw_deg"), final_roll_deg = trace.value(last, "roll_deg"),
		checkpoint_sha256 = var_to_bytes(flight.checkpoint()).hex_encode().sha256_text()}
	if not result.ok:
		failures += 1
	recorder.detach()
	flight.free()
	return result


func refinement(config: String, rate: int) -> Dictionary:
	Engine.physics_ticks_per_second = rate
	var flight: Node = make_flight(config)
	flight.sim.inputs[3] += 0.03
	for tick: int in rate / 2:
		flight.sim.step()
	var ok: bool = flight.sim.tick == rate / 2 and flight.sim.fault_reason.is_empty()
	var result: Dictionary = {ok = ok, body = Array(flight.sim.state), rpm = flight.sim.aux[0]}
	if not ok:
		failures += 1
	flight.free()
	return result


func cost(config: String, coast: bool) -> Dictionary:
	var flight: Node = make_flight(config)
	if coast:
		flight.engine_running = false
	for tick: int in 240:
		flight.sim.step()
	var warm: Dictionary = flight.checkpoint()
	var samples: Array[float] = []
	for batch: int in 40:
		if not flight.restore_checkpoint(warm):
			failures += 1
			flight.free()
			return {ok = false, message = "warm checkpoint refused"}
		var before: int = Time.get_ticks_usec()
		for tick: int in 120:
			flight.sim.step()
		samples.append(float(Time.get_ticks_usec() - before) / 120.0)
	samples.sort()
	var result: Dictionary = {ok = flight.sim.fault_reason.is_empty() and flight.sim.tick == 360,
		median_us_per_tick = (samples[19] + samples[20]) * 0.5, p95_us_per_tick = samples[37],
		batch_ticks = 120, batches = 40, warmup_ticks = 240, sorted_batch_us_per_tick = samples,
		restored_before_each_batch = true,
		fingerprint = var_to_bytes(flight.checkpoint()).hex_encode().sha256_text()}
	# Source-only cost is reported separately; it is not the whole-tick budget.
	var prop: Dictionary = flight.aircraft.model.propulsion
	if Prop.is_electric(prop):
		var before: int = Time.get_ticks_usec()
		var sink: float = 0.0
		for sample: int in 10000:
			sink += Prop.electric_source_state(5000.0, 0.6, prop).motor_current_a
		result.source_us_per_call = float(Time.get_ticks_usec() - before) / 10000.0
		result.source_sink = sink
	if not result.ok:
		failures += 1
	flight.free()
	return result


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] not in ["flight", "refinement", "cost"]:
		printerr("usage: -- flight|refinement|cost ABSOLUTE_OUTPUT_DIRECTORY")
		quit(2)
		return
	var result: Dictionary = {format = "openrc-electric-session-proof v1", mode = args[0], cases = {}}
	for config: String in ["4s", "6s"]:
		if args[0] == "flight":
			for scenario: String in ["level", "turn", "climb", "chop"]:
				result.cases[config + "-" + scenario] = run_scenario(config, scenario, args[1])
		elif args[0] == "refinement":
			for rate: int in [120, 240, 480, 960, 1920]:
				result.cases[config + "-" + str(rate)] = refinement(config, rate)
		else:
			for coast: bool in [false, true]:
				result.cases[config + ("-coast" if coast else "-powered")] = cost(config, coast)
	if args[0] == "cost":
		for model: String in ["jensen_ugly_stik_60", "gp_extra_300s_60", "p51d_mustang_120", "sebart_avanti_s_a200"]:
			result.cases[model] = cost("res://data/aircraft/%s.json" % model, false)
	var file: FileAccess = FileAccess.open(args[1].path_join(args[0] + ".json"), FileAccess.WRITE)
	if file == null:
		failures += 1
	else:
		file.store_string(JSON.stringify(result, "\t", true, true) + "\n")
	print("EL1 session probe: %d cases, %d failed" % [result.cases.size(), failures])
	quit(1 if failures else 0)

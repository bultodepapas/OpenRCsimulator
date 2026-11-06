extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Log := preload("res://sim/flight_log.gd")
const Reader := preload("res://tools/flight_log_cli.gd")
const RB := preload("res://physics/rigid_body.gd")
const Air := preload("res://physics/air_data.gd")
const DATA := "res://data/aircraft/gp_extra_300s_60.json"
const ON_TICK := 48
const OFF_TICK := 168
const TOTAL_TICKS := 480
var out_dir := ""
var quick := false
var failures := 0
var cases: Array = []
var signatures: Dictionary = {}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out_dir = arg.substr(6)
		if arg == "--quick": quick = true
	if out_dir.is_empty():
		printerr("Expected --out=<new directory>")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	call_deferred("run")

func check(label: String, value: bool) -> bool:
	if not value:
		failures += 1
		printerr("FAIL ", label)
	return value

func numeric(flight: Node) -> PackedByteArray:
	var all := PackedByteArray()
	for key in ["state", "aux", "continuous", "modes", "inputs", "last_loads"]:
		all.append_array(flight.sim.get(key).to_byte_array())
	return all

func exact_replay(path: String) -> Dictionary:
	var read: Dictionary = Reader.inspect(path)
	if not check("complete recording: " + path, read.get("ok", false)):
		return {ok = false, error = read.get("error", "inspect failed")}
	var replay: Dictionary = Reader.prepare_replay(read.header)
	if not check("prepare exact replay", replay.get("ok", false)):
		return {ok = false, error = replay.get("error", "prepare failed")}
	var flight: Node = replay.flight
	var observer := Log.new(flight)
	var stream := FileAccess.open(path, FileAccess.READ)
	stream.seek(8)
	Log.read_packet(stream)
	var first := true
	var ticks := 0
	var mismatch := ""
	while stream.get_position() < stream.get_length():
		var packet: Dictionary = Log.read_packet(stream)
		if not packet.get("ok", false):
			mismatch = "packet read failed"
			break
		var block: Dictionary = packet.value
		if block.kind == "footer": break
		for row: Dictionary in block.rows:
			if first:
				first = false
				continue
			for key in row.intervention: flight.sim.set(key, row.intervention[key].duplicate())
			flight.sim.inputs = row.inputs.duplicate()
			flight.sim.step()
			ticks += 1
			mismatch = Reader.disagreement(row, observer._sample({}))
			if not mismatch.is_empty(): break
		if not mismatch.is_empty(): break
	stream.close()
	check("all exact replay ticks", mismatch.is_empty() and ticks == TOTAL_TICKS)
	flight.free()
	return {ok = mismatch.is_empty() and ticks == TOTAL_TICKS, ticks = ticks,
		complete = read.get("complete", false), solver_changed = replay.get("solver_changed", false), mismatch = mismatch}

func run_case(speed: float, profile: String, amplitude: float, tag: String) -> void:
	var flight := Flight.new()
	flight.input_enabled = false
	flight.crash_auto_restart = false
	flight.setup_stage_backend("gdscript_reference")
	flight.setup(DATA)
	flight.rate_profile = profile
	flight.set_start_altitude(100.0)
	var trim: Dictionary = flight.trim_at(speed, "level")
	if not check(tag + " trim", trim.get("ok", false)):
		flight.free()
		return
	flight.reset()
	if not check(tag + " ready", flight.is_flyable() and flight.sim.fault_reason.is_empty()):
		flight.free()
		return
	var path := out_dir.path_join(tag + ".orfl")
	var logger := Log.new(flight)
	if not check(tag + " record", logger.start(path) == OK):
		flight.free()
		return
	var csv := FileAccess.open(out_dir.path_join(tag + ".csv"), FileAccess.WRITE)
	csv.store_line("tick,t_s,raw_roll,cmd_roll,surface_roll,aileron_deg,p_radps,q_radps,r_radps,V_mps,alpha_rad,beta_rad,rpm,altitude_m")
	var sha := HashingContext.new()
	sha.start(HashingContext.HASH_SHA256)
	var max_p := 0.0
	var max_surface := 0.0
	var release_p := 0.0
	var initial: Dictionary = flight.mass_properties().duplicate(true)
	var init_rho: float = flight.air_density(flight.sim.state)
	var initial_trims: Dictionary = flight.trims.duplicate(true)
	var initial_throttle: float = flight.start.throttle
	for k in TOTAL_TICKS:
		var command: float = amplitude if k >= ON_TICK and k < OFF_TICK else 0.0
		flight.commands = {roll = command, pitch = 0.0, yaw = 0.0, throttle = initial_throttle}
		flight.raw = flight.commands.duplicate()
		flight.sim.inputs = flight._inputs()
		if k == ON_TICK: logger.mark("pulse begins")
		if k == OFF_TICK: logger.mark("pulse ends")
		flight.sim.step()
		if not check(tag + " accepted tick", flight.sim.fault_reason.is_empty() and flight.sim.tick == k + 1): break
		var state: PackedFloat64Array = flight.sim.state
		var surf: Dictionary = flight.surfaces()
		var air: Dictionary = Air.compute(state, flight.wind_at(flight.sim.time()), flight.air_density(state))
		var actual_angle: float = surf.roll * flight.aircraft.model.controls.throw_deg.aileron
		csv.store_csv_line(PackedStringArray([str(k + 1), "%.17f" % flight.sim.time(), "%.17f" % command,
			"%.17f" % flight.sim.inputs[0], "%.17f" % surf.roll, "%.17f" % actual_angle,
			"%.17f" % state[RB.RATE], "%.17f" % state[RB.RATE + 1], "%.17f" % state[RB.RATE + 2],
			"%.17f" % air.V, "%.17f" % air.alpha, "%.17f" % air.beta,
			"%.17f" % flight.sim.aux[Flight.AUX_RPM], "%.17f" % -state[RB.POS + 2]]))
		sha.update(numeric(flight))
		if k >= ON_TICK and k < OFF_TICK:
			max_p = maxf(max_p, absf(state[RB.RATE]))
			max_surface = maxf(max_surface, absf(actual_angle))
		if k == OFF_TICK - 1: release_p = state[RB.RATE]
	check(tag + " stop recording", logger.stop() == OK)
	csv.close()
	var dynamics_sha := sha.finish().hex_encode()
	signatures[tag] = dynamics_sha
	var row := {case = tag, speed_mps = speed, rate_profile = profile, raw_roll = amplitude,
		initial_mass_kg = initial.mass_kg, initial_cg_body_m = Array(initial.cg_body_m),
		initial_rho_kg_m3 = init_rho, trims = initial_trims, initial_throttle = initial_throttle,
		pulse_ticks = [ON_TICK, OFF_TICK], dt_s = flight.sim.dt(), total_ticks = flight.sim.tick,
		peak_abs_p_during_pulse_deg_s = rad_to_deg(max_p), max_abs_surface_during_pulse_deg = max_surface,
		release_p_deg_s = rad_to_deg(release_p), dynamics_sha256 = dynamics_sha, recording = path}
	flight.free()
	row.exact_replay = exact_replay(path)
	cases.append(row)
	print("PULSE ", tag, " peak_deg_s=", row.peak_abs_p_during_pulse_deg_s, " exact=", row.exact_replay.ok)

func run() -> void:
	if quick:
		run_case(22.0, "normal", 1.0, "smoke_normal_right")
	else:
		for speed in [15.0, 22.0]:
			for direction in [-1.0, 1.0]:
				var side := "left" if direction < 0.0 else "right"
				for profile in ["normal", "full"]:
					run_case(speed, profile, direction, "%d_%s_%s" % [int(speed), profile, side])
		for direction in [-1.0, 1.0]:
			var side := "left" if direction < 0.0 else "right"
			run_case(22.0, "sport", direction, "22_sport_" + side)
			var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA))
			var rate: float = data.controls.rates.normal.aileron.value
			run_case(22.0, "full", direction * rate, "22_matched_" + side)
			check("sport/full same physics " + side, signatures["22_sport_" + side] == signatures["22_full_" + side])
			check("equal actual command same physics " + side, signatures["22_matched_" + side] == signatures["22_normal_" + side])
	check("requested case count", cases.size() == (1 if quick else 12))
	var report := {format = "extra-character-pulses-v1", source_commit = "2e2e3492e67d30635cc4e727025581e2848cdf2e",
		engine = Engine.get_version_info().string, backend = "gdscript_reference", failures = failures,
		interpretation = "Unchanged production physics, deterministic short control pulses; no physical calibration or timing claim.",
		cases = cases}
	var file := FileAccess.open(out_dir.path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t", true, true))
	file.close()
	print("EXTRA_CHARACTER_PULSES_COMPLETE failures=", failures, " cases=", cases.size())
	quit(1 if failures else 0)

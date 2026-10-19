## FUEL-12 matched command tapes at full/low launch fill; exact replay of each log.
## This is numerical evidence. Different launch trims are recorded, not hidden.
extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const Log := preload("res://sim/flight_log.gd")
const Reader := preload("res://tools/flight_log_cli.gd")
const RB := preload("res://physics/rigid_body.gd")
const TICKS := 600
var destination := ""
var failures := 0


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			destination = argument.trim_prefix("--out=")
	if destination.is_empty() or DirAccess.dir_exists_absolute(destination):
		printerr("Use --out=<new absolute directory>; evidence is never overwritten")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(destination)
	call_deferred("run")


func run() -> void:
	var results: Array = []
	for path: String in ["res://data/aircraft/stik_glow_61fx_2t.json", "res://data/aircraft/stik_glow_fs64v_4t.json",
		"res://data/aircraft/gp_extra_300s_60.json", "res://data/aircraft/p51d_mustang_120.json", "res://data/aircraft/sebart_avanti_s_a200.json"]:
		var full: Node = Flight.new()
		full.input_enabled = false
		full.setup(path)
		if not full.is_flyable() or not full.finite_fuel_is_active():
			failures += 1
			results.append({path = path, ok = false, error = "finite aircraft did not prepare"})
			full.free()
			continue
		var tape_start: PackedFloat64Array = full.sim.inputs.duplicate()
		var pair: Array = []
		for fill: float in [1.0, 0.1]:
			var flight: Node = full if fill == 1.0 else Flight.new()
			if fill != 1.0:
				flight.input_enabled = false
				flight.setup(path)
				flight.set_fuel_start_fill(fill)
				flight.reset()
			var log_path: String = destination.path_join(path.get_file().get_basename() + ("-full.orfl" if fill == 1.0 else "-low.orfl"))
			var initial: Dictionary = flight.mass_properties()
			var initial_body: PackedFloat64Array = flight.sim.state.duplicate()
			var logger := Log.new(flight)
			var ok: bool = flight.is_flyable() and logger.start(log_path) == OK
			var started: int = Time.get_ticks_usec()
			for tick: int in TICKS if ok else 0:
				flight.sim.inputs = tape_start.duplicate()
				flight.sim.inputs[0] = 0.08 if tick < 120 else (-0.08 if tick < 240 else 0.0)
				flight.sim.inputs[1] = -0.02 if tick < 300 else 0.02
				flight.sim.inputs[3] = 0.5 if tick < 300 else 0.35
				flight.sim.step()
				if tick == 120:
					logger.mark("roll reversal")
				if tick == 300:
					logger.mark("pitch and throttle change")
				if not flight.sim.fault_reason.is_empty():
					ok = false
					break
			var elapsed: int = Time.get_ticks_usec() - started
			ok = logger.stop() == OK and ok
			var final: Dictionary = flight.mass_properties()
			var final_body: PackedFloat64Array = flight.sim.state.duplicate()
			var replay: Dictionary = exact_replay(log_path) if ok else {ok = false}
			ok = ok and replay.ok
			if not ok:
				failures += 1
			pair.append({ok = ok, fill = fill, ticks = flight.sim.tick, dt_s = flight.sim.dt(),
				initial_mass_kg = initial.get("mass_kg", 0.0), final_mass_kg = final.get("mass_kg", 0.0),
				initial_fuel_kg = initial.get("fuel_remaining_kg", 0.0), final_fuel_kg = final.get("fuel_remaining_kg", 0.0),
				initial_cg_body_m = Array(initial.get("cg_body_m", PackedFloat64Array())), final_cg_body_m = Array(final.get("cg_body_m", PackedFloat64Array())),
				initial_state = Array(initial_body), final_state = Array(final_body),
				elapsed_usec = elapsed, observer_usec = logger.observer_usec, peak_buffer_rows = logger.peak_buffer_rows,
				fault = flight.sim.fault_reason, log_file = log_path.get_file(), exact_replay = replay})
			print("%s fill %.1f: %s, %d ticks" % [path.get_file(), fill, str(ok), flight.sim.tick])
			flight.free()
		results.append({path = path, source = path, command_tape = "same absolute commands at same ticks; separate selected-fill launch trims", runs = pair})
	var report := {format = "openrc-fuel-completion-evidence v1", software_only = true,
		comparison = "Full/10% fill paired launches; launch trim/body/internal state may differ and are included. Not exact equivalence or physical validation.",
		solver_sha256 = Log.solver_identity(), ticks = TICKS, failures = failures, aircraft = results}
	var output := FileAccess.open(destination.path_join("verification.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t", true, true))
	output.close()
	print("FUEL-12: %d failures; %s" % [failures, destination])
	quit(1 if failures else 0)


func exact_replay(path: String) -> Dictionary:
	var inspected: Dictionary = Reader.inspect(path)
	if not inspected.get("ok", false):
		return {ok = false, error = "incomplete log"}
	var prepared: Dictionary = Reader.prepare_replay(inspected.header)
	if not prepared.get("ok", false):
		return {ok = false, error = prepared.get("error", "restore failed")}
	var observer := Log.new(prepared.flight)
	var stream := FileAccess.open(path, FileAccess.READ)
	stream.seek(8)
	Log.read_packet(stream)
	var rows := 0
	var ok := true
	var difference := ""
	while stream.get_position() < stream.get_length() and ok:
		var packet: Dictionary = Log.read_packet(stream)
		if not packet.get("ok", false):
			ok = false
			break
		var block: Dictionary = packet.value
		if block.kind == "footer":
			break
		for row: Dictionary in block.rows:
			if rows > 0:
				prepared.flight.sim.inputs = row.inputs.duplicate()
				prepared.flight.sim.step()
			difference = Reader.disagreement(row, observer._sample({}))
			rows += 1
			if not difference.is_empty():
				ok = false
				break
	stream.close()
	prepared.flight.free()
	return {ok = ok and rows == TICKS + 1, rows = rows, difference = difference, complete = true, solver_changed = false}

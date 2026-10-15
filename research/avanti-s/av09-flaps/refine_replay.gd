## Research-only ORFL replay at a selected fixed physics rate.
## CLI and FlightLog validation remain authoritative; this harness only sets the
## engine tick rate before invoking the same native preflight/replay helpers.
extends SceneTree

const CLI := preload("res://tools/flight_log_cli.gd")
const FlightLog := preload("res://sim/flight_log.gd")

var _options: Dictionary = {}
var _error := ""


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		_options[pair[0]] = pair[1] if pair.size() > 1 else true
	var physics_ticks: int = int(_options.get("physics-ticks", 0))
	if physics_ticks not in [240, 480]:
		printerr("AV-09 native replay accepts only --physics-ticks=240 or 480")
		quit(2)
		return
	Engine.physics_ticks_per_second = physics_ticks
	call_deferred("_run")


func _run() -> void:
	for key: String in ["log", "out", "mode"]:
		if typeof(_options.get(key)) != TYPE_STRING or str(_options[key]).is_empty():
			_finish("Required: --log=<file.orfl> --out=<new-folder> --mode=exact|candidate --physics-ticks=240|480")
			return
	var mode: String = str(_options.mode)
	if mode not in ["exact", "candidate"]:
		_finish("--mode must be exact or candidate")
		return
	var candidate_path: String = str(_options.get("candidate", ""))
	if (mode == "candidate") != (not candidate_path.is_empty()):
		_finish("candidate mode requires --candidate; exact mode forbids it")
		return
	var output_dir: String = str(_options.out)
	if DirAccess.dir_exists_absolute(output_dir) or FileAccess.file_exists(output_dir):
		_finish("Refusing to overwrite replay output: " + output_dir)
		return
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		_finish("Cannot create replay output directory")
		return
	var checked: Dictionary = CLI.inspect(str(_options.log), false)
	if not checked.get("ok", false) or not checked.get("complete", false):
		_finish(str(checked.get("error", "Research replay requires a complete verified ORFL")))
		return
	var header: Dictionary = checked.header
	var source_sha256: String = FileAccess.get_sha256(str(_options.log))
	var prepared: Dictionary = CLI.prepare_replay(header, candidate_path)
	if not prepared.get("ok", false):
		_finish(str(prepared.get("error", "Replay preflight failed")))
		return
	var flight: Node = prepared.flight
	var candidate_identity: Dictionary = flight.aircraft.get("input_identity", {})
	var csv_path: String = output_dir.path_join("flight.csv")
	var report_path: String = output_dir.path_join("replay.json")
	var csv := FileAccess.open(csv_path, FileAccess.WRITE)
	if csv == null:
		flight.free()
		_finish("Cannot create replay CSV")
		return
	csv.store_csv_line(CLI.columns(header.layout))
	var input := FileAccess.open(str(_options.log), FileAccess.READ)
	if input == null:
		csv.close()
		flight.free()
		_remove_if_exists(csv_path)
		_finish("Cannot open replay source")
		return
	input.seek(8)
	var packet: Dictionary = FlightLog.read_packet(input)
	if not packet.get("ok", false):
		input.close()
		csv.close()
		flight.free()
		_remove_if_exists(csv_path)
		_finish(str(packet.get("error", "Cannot read ORFL header")))
		return
	var observer: RefCounted = FlightLog.new(flight)
	var first := true
	var completed_rows := 0
	while input.get_position() < input.get_length():
		packet = FlightLog.read_packet(input)
		if not packet.get("ok", false):
			_error = str(packet.get("error", "ORFL packet read failed"))
			break
		var value: Dictionary = packet.value
		if value.get("kind") == "footer":
			break
		for row: Dictionary in value.rows:
			var output: Dictionary = row
			if not first:
				for key: String in row.intervention:
					flight.sim.set(key, row.intervention[key].duplicate())
				flight.sim.inputs = row.inputs.duplicate()
				flight.sim.step()
				if not flight.sim.fault_reason.is_empty() or flight.sim.tick != row.tick:
					_error = "Replay stopped at tick %d: %s" % [row.tick, flight.sim.fault_reason]
					break
				output = observer._sample(row.intervention)
				output.raw = row.raw
				output.sticks = row.sticks
			else:
				output = observer._sample({})
				output.raw = row.raw
				output.sticks = row.sticks
			if mode == "exact" and not first:
				_error = CLI.disagreement(row, output)
				if not _error.is_empty():
					break
			CLI.write_row(csv, output, float(header.dt_s), int(checked.first_tick))
			first = false
			completed_rows += 1
		if not _error.is_empty():
			break
	input.close()
	if csv.get_error() != OK and _error.is_empty():
		_error = "CSV write failed; discard output"
	csv.close()
	flight.free()
	if _error.is_empty() and FileAccess.get_sha256(str(_options.log)) != source_sha256:
		_error = "Source ORFL changed during replay"
	var report: Dictionary = {
		"status": "ok" if _error.is_empty() else "error",
		"error": _error,
		"format": "openrc-flight-log-report v1",
		"source": str(_options.log),
		"source_sha256": source_sha256,
		"rows": completed_rows,
		"first_tick": checked.first_tick,
		"final_tick": checked.footer.final_tick,
		"dt_s": header.dt_s,
		"complete": checked.complete,
		"mode": mode,
		"metadata": header.metadata,
		"events": checked.events,
		"baseline_solver_sha256": header.solver_sha256,
		"current_solver_sha256": FlightLog.solver_identity(),
		"solver_changed": header.solver_sha256 != FlightLog.solver_identity(),
		"baseline_build": header.build,
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"candidate": candidate_path,
		"candidate_identity": candidate_identity,
		"comparison_method": "Native current-solver exact replay at the recorded tick rate." if mode == "exact" else "Open-loop candidate replay using the recorded accepted initial state and tick-indexed input tape; same solver and tick rate.",
	}
	var report_file := FileAccess.open(report_path, FileAccess.WRITE)
	if report_file == null:
		_remove_if_exists(csv_path)
		printerr("Cannot write replay report")
		quit(1)
		return
	report_file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	report_file.close()
	if not _error.is_empty():
		printerr(_error)
		quit(1)
	else:
		print("AV-09 native replay %s: %d rows at %d Hz" % [mode, completed_rows, Engine.physics_ticks_per_second])
		quit(0)


func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _finish(error: String) -> void:
	printerr(error)
	quit(1)

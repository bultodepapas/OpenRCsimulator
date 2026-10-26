## GP-08 changed-source preservation check using the existing flight-log API.
## Candidate experiment, not historical exact replay or physical validation.
extends SceneTree
const CLI := preload("res://tools/flight_log_cli.gd")
const Log := preload("res://sim/flight_log.gd")
var options := {}

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		if pair.size() == 2: options[pair[0]] = pair[1]
	call_deferred("_run")

func _run() -> void:
	if not options.has_all(["log", "candidate", "report"]) or FileAccess.file_exists(options.report):
		printerr("Required --log=<complete.orfl> --candidate=<same-aircraft.json> --report=<new.json>")
		quit(2)
		return
	var checked: Dictionary = CLI.inspect(options.log)
	if not checked.get("ok", false) or not checked.get("complete", false):
		printerr("Complete validated baseline required")
		quit(1)
		return
	var prepared: Dictionary = CLI.prepare_replay(checked.header, options.candidate)
	if not prepared.get("ok", false):
		printerr(prepared.get("error", "Candidate preparation failed"))
		quit(1)
		return
	var flight: Node = prepared.flight
	var observer: RefCounted = Log.new(flight)
	var stream := FileAccess.open(options.log, FileAccess.READ)
	stream.seek(8)
	Log.read_packet(stream)
	var first := true
	var rows := 0
	var error := ""
	while stream.get_position() < stream.get_length() and error.is_empty():
		var packet: Dictionary = Log.read_packet(stream)
		if not packet.get("ok", false):
			error = packet.get("error", "Packet rejected")
			break
		if packet.value.kind == "footer": break
		for row: Dictionary in packet.value.rows:
			if not first:
				for key: String in row.intervention:
					flight.sim.set(key, row.intervention[key].duplicate())
				flight.sim.inputs = row.inputs.duplicate()
				flight.sim.step()
				if not flight.sim.fault_reason.is_empty() or flight.sim.tick != row.tick:
					error = "Candidate stopped at tick %d: %s" % [row.tick, flight.sim.fault_reason]
					break
			var actual: Dictionary = observer._sample({} if first else row.intervention)
			error = CLI.disagreement(row, actual)
			if not error.is_empty(): break
			rows += 1
			first = false
	stream.close()
	var report := {format = "openrc-gp08-candidate-numeric-preservation v1",
		mode = "candidate_preservation", status = "ok" if error.is_empty() else "error",
		complete = error.is_empty() and rows == checked.rows, rows_checked = rows,
		expected_rows = checked.rows, error = error, engine = Engine.get_version_info().string,
		baseline_sha256 = FileAccess.get_sha256(options.log),
		baseline_solver_sha256 = checked.header.solver_sha256, current_solver_sha256 = Log.solver_identity(),
		solver_changed = checked.header.solver_sha256 != Log.solver_identity(),
		aircraft_identity = flight.aircraft.get("input_identity", {}),
		fields_checked = ["state", "loads", "inputs", "aux", "continuous", "modes", "air", "mass"],
		method = "Existing CLI.prepare_replay explicit candidate; identical frozen aircraft configuration and post-conditioning input/intervention tape; existing CLI.disagreement compares every native numeric array byte, including the initial sample. Changed-source experiment, not a historical exact replay certificate."}
	flight.free()
	var output := FileAccess.open(options.report, FileAccess.WRITE)
	if output == null:
		printerr("Cannot write report")
		quit(1)
		return
	output.store_string(JSON.stringify(report, "\t", true, true))
	output.close()
	print("GP-08 numeric preservation: complete=", report.complete, "; rows=", rows)
	quit(0 if report.complete else 1)

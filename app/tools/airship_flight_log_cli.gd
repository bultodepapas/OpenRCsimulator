## BL-08: verify an RC blimp flight log by exact replay and export an offline CSV view.
## godot --headless --path app --script res://tools/airship_flight_log_cli.gd -- --log=<file.orfl> --report=<new.json> [--csv=<new.csv>]
## Exit 0 only for a complete file that replays byte-exactly with the same session identity.
extends SceneTree

const AirshipLog := preload("res://sim/airship/flight_log.gd")
const FlightLogCli := preload("res://tools/flight_log_cli.gd")

const COLUMNS := ["tick", "time_s", "roll", "pitch", "yaw", "throttle", "north_m", "east_m", "down_m", "u_mps", "v_mps", "w_mps",
	"q0", "q1", "q2", "q3", "p_radps", "q_radps", "r_radps", "motor_port", "motor_starboard", "motor_stern", "motor_lateral",
	"vector_port_rad", "vector_starboard_rad", "vector_stern_rad", "fin_0_rad", "fin_1_rad", "fin_2_rad", "soc"]

var options := {}


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		options[pair[0]] = pair[1] if pair.size() > 1 else true
	_run.call_deferred()


func _run() -> void:
	for key in ["log", "report"]:
		if typeof(options.get(key)) != TYPE_STRING or str(options[key]).is_empty():
			printerr("Required: --log=<file.orfl> --report=<new.json> [--csv=<new.csv>]")
			quit(1)
			return
	for key in ["report", "csv"]:
		if typeof(options.get(key)) == TYPE_STRING and FileAccess.file_exists(str(options[key])):
			printerr("Output already exists: " + str(options[key]))
			quit(1)
			return
	var report := AirshipLog.verify(str(options.log))
	if report.ok and typeof(options.get("csv")) == TYPE_STRING:
		var csv_error := write_csv(str(options.log), str(options.csv))
		if not csv_error.is_empty():
			report.ok = false
			report.error = csv_error
	var write_error: Error = FlightLogCli.write_report_file(str(options.report), JSON.stringify(report, "\t", true, true) + "\n")
	if write_error != OK:
		printerr("Cannot write report %s (error %d)." % [str(options.report), write_error])
		quit(1)
		return
	if report.ok:
		print("Airship flight log: %d rows replayed exactly (solver_changed %s)." % [report.rows, report.solver_changed])
	else:
		printerr("Airship flight log refused: " + str(report.error))
	quit(0 if report.ok else 1)


static func write_csv(log_path: String, csv_path: String) -> String:
	var read := AirshipLog.inspect(log_path)
	if not read.ok:
		return str(read.get("error", "unreadable log"))
	var file := FileAccess.open(csv_path, FileAccess.WRITE)
	if file == null:
		return "Cannot create CSV (%d)." % FileAccess.get_open_error()
	file.store_line(",".join(COLUMNS))
	var head: Dictionary = read.header
	var dt := float(head.dt_s)
	var first := int(head.checkpoint.tick)
	var cont := int(head.layout.continuous)
	for i in read.ticks.size():
		var tick := int(read.ticks[i])
		var row := PackedStringArray([str(tick), "%.6f" % (float(tick - first) * dt)])
		for value: float in read.sticks.slice(4 * i, 4 * i + 4):
			row.append("%.6f" % value)
		for value: float in read.states.slice(13 * i, 13 * i + 13):
			row.append("%.12f" % value)
		for value: float in read.continuous.slice(cont * i, cont * i + cont):
			row.append("%.12f" % value)
		file.store_line(",".join(row))
	file.flush()
	var error := file.get_error()
	file.close()
	return "" if error == OK else "CSV write failed; discard incomplete output."

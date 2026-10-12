# AV-16 follow-up: distinguish body rotation from a flown loop without retuning the aircraft.
extends "envelope_probe.gd"


func _initialize() -> void:
	var output := ""
	var hz := 240
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
		elif argument.begins_with("--hz="):
			hz = int(argument.trim_prefix("--hz="))
	if output.is_empty() or hz not in [240, 480]:
		quit(2)
		return
	Engine.physics_ticks_per_second = hz
	var session := _new_session()
	var report := {schema = "openrc-avanti-pitch-sweep-v1", aircraft_id = AVANTI_ID,
		physics_hz = hz, errors = [], cases = [],
		interpretation = "Eight-second open-loop input sensitivity, not a pilot-flown maneuver or a calibrated aerobatic envelope."}
	for direction: int in [-1, 1]:
		for magnitude: float in [0.05, 0.10, 0.15, 0.25]:
			var amplitude := float(direction) * magnitude
			var pilot := func(t: float, _state: PackedFloat64Array) -> Dictionary:
				return Maneuvers._pulse(t, 0.2, 8.0, {pitch = amplitude, throttle_delta = 1.0})
			var case_id := "pitch_%+.2f_50" % amplitude
			var result := _run_flight_case(session, case_id, "level", 50.0, 8.0, 500.0, pilot)
			if result.has("trace"):
				result.summary.trajectory = _trajectory(result.trace)
				result.summary.pitch_command = amplitude
				var samples: Array = []
				for row in range(0, result.trace.row_count(), roundi(0.1 * hz)):
					samples.append([result.trace.value(row, "t_s"), result.trace.value(row, "north_m"),
						result.trace.value(row, "east_m"), result.trace.value(row, "alt_m")])
				result.summary.trajectory_samples = samples
				result.summary.sample_columns = ["time_s", "north_m", "east_m", "altitude_m"]
			if not result.summary.get("complete", false):
				report.errors.append(case_id)
			report.cases.append(result.summary)
	report.completed = report.cases.size() == 8 and report.errors.is_empty()
	_write_json(output, report)
	print("AV-16 pitch sweep: %d cases, %d errors" % [report.cases.size(), report.errors.size()])
	session.free()
	quit(0 if report.completed else 1)

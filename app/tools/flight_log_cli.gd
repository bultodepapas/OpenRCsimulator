## FL-03: bounded offline export and verified/open-loop replay. No live user settings.
extends SceneTree

const Log := preload("res://sim/flight_log.gd")
const Flight := preload("res://sim/flight_session.gd")
const Data := preload("res://physics/aircraft_data.gd")
const RB := preload("res://physics/rigid_body.gd")
var options := {}
var report := {status = "error", error = "Not started", format = "openrc-flight-log-report v1"}


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		options[pair[0]] = pair[1] if pair.size() > 1 else true
	call_deferred("_run")


func _run() -> void:
	for key in ["log", "csv", "report"]:
		if typeof(options.get(key)) != TYPE_STRING or str(options[key]).is_empty():
			_finish("Required: --log=<file.orfl> --csv=<new.csv> --report=<new.json> [--replay] [--candidate=<aircraft.json>]")
			return
	for key in ["csv", "report"]:
		if FileAccess.file_exists(options[key]):
			# Never replace reports, including with an error report.
			printerr("Output already exists: " + str(options[key]))
			quit(1)
			return
	if ProjectSettings.globalize_path(options.csv).simplify_path().to_lower() == ProjectSettings.globalize_path(options.report).simplify_path().to_lower():
		printerr("CSV and report must have different output paths.")
		quit(1)
		return
	if options.has("candidate") and (not options.has("replay") or typeof(options.candidate) != TYPE_STRING):
		_finish("--candidate requires --replay and a JSON path.")
		return
	if options.has("recover") and options.has("replay"):
		_finish("Recovery exports diagnostics only; replay requires a complete file.")
		return
	var checked := inspect(str(options.log), options.has("recover"))
	if not checked.ok:
		_finish(checked.error)
		return
	var header: Dictionary = checked.header
	report.merge({source = str(options.log), source_sha256 = FileAccess.get_sha256(options.log),
		rows = checked.rows, first_tick = checked.first_tick, final_tick = checked.footer.final_tick,
		dt_s = header.dt_s, complete = checked.complete, recovery_reason = checked.get("recovery_reason", ""), metadata = header.metadata, events = checked.events,
		events_omitted = checked.get("events_omitted", 0),
		baseline_solver_sha256 = header.solver_sha256, current_solver_sha256 = Log.solver_identity(),
		solver_changed = header.solver_sha256 != Log.solver_identity(), baseline_build = header.build,
		observer_usec = checked.footer.observer_usec, peak_buffer_rows = checked.footer.peak_buffer_rows}, true)
	var flight: Node = null
	if options.has("replay"):
		var prepared := prepare_replay(header, str(options.get("candidate", "")))
		if not prepared.ok:
			_finish(prepared.error)
			return
		flight = prepared.flight
		report.mode = "candidate" if options.has("candidate") else "exact"
		report.candidate = str(options.get("candidate", ""))
		report.candidate_identity = flight.aircraft.get("input_identity", {})
		report.comparison_method = "Open-loop: baseline body/internal initial state and post-conditioning input tape; candidate aircraft mass/inertia/configuration and current solver. Not a newly trimmed flight or pilot adaptation." if options.has("candidate") \
			else "Byte-exact comparison of every recorded numeric physics/air sample on the recorded solver."
	else:
		report.mode = "export"
	var csv := FileAccess.open(options.csv, FileAccess.WRITE)
	if csv == null:
		if flight != null: flight.free()
		_finish("Cannot create CSV output.")
		return
	csv.store_csv_line(columns(header.layout))
	var file := FileAccess.open(options.log, FileAccess.READ)
	file.seek(8)
	Log.read_packet(file) # already validated in the first pass
	var observer: RefCounted = Log.new(flight) if flight != null else null
	var first := true
	var error := ""
	while file.get_position() < file.get_length():
		if not checked.complete and file.get_position() >= checked.prefix_end: break
		var packet := Log.read_packet(file)
		if not packet.ok:
			error = packet.error
			break
		if packet.value.kind == "footer": break
		for row: Dictionary in packet.value.rows:
			var output := row
			if flight != null and not first:
				for key: String in row.intervention:
					flight.sim.set(key, row.intervention[key].duplicate())
				flight.sim.inputs = row.inputs.duplicate()
				flight.sim.step()
				if not flight.sim.fault_reason.is_empty() or flight.sim.tick != row.tick:
					error = "Replay stopped at tick %d: %s" % [row.tick, flight.sim.fault_reason]
					break
				output = observer._sample(row.intervention)
				output.raw = row.raw
				output.sticks = row.sticks
			if flight != null and first:
				output = observer._sample({})
				output.raw = row.raw
				output.sticks = row.sticks
			if flight != null and not options.has("candidate"):
				error = disagreement(row, output)
				if not error.is_empty(): break
			write_row(csv, output, float(header.dt_s), int(checked.first_tick))
			first = false
		if not error.is_empty(): break
	if csv.get_error() != OK:
		error = "CSV write failed; discard incomplete output."
	csv.close()
	file.close()
	if flight != null: flight.free()
	if error.is_empty() and FileAccess.get_sha256(options.log) != report.source_sha256:
		error = "Source changed during export/replay. Discard CSV."
	_finish(error)


## A complete preflight walks bounded packets before any flight or CSV is created.
static func inspect(path: String, recover := false) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {ok = false, error = "Cannot open flight log."}
	if file.get_length() > Log.MAX_BYTES + Log.MAX_PACKET * 2 or file.get_buffer(8).get_string_from_ascii() != Log.MAGIC:
		return {ok = false, error = "Invalid flight-log magic or file size."}
	var packet := Log.read_packet(file)
	if not packet.ok: return packet
	var header: Dictionary = packet.value
	if header.get("kind") != "header" or header.get("format") != Log.FORMAT:
		return {ok = false, error = "Unsupported flight-log header."}
	for key in ["metadata", "checkpoint", "aircraft", "collision_world", "lake", "weather", "layout", "build"]:
		if not header.get(key) is Dictionary: return {ok = false, error = "Missing header dictionary: " + key}
	for key in ["engine", "solver_sha256", "aircraft_path", "ground_field_id", "shaft_integrator"]:
		if typeof(header.get(key)) != TYPE_STRING: return {ok = false, error = "Missing header string: " + key}
	if typeof(header.get("soft_hull_contacts")) != TYPE_BOOL or not header.get("ground_surfaces") is PackedFloat64Array \
			or header.aircraft.get("ok") != true or not header.aircraft.get("model") is Dictionary:
		return {ok = false, error = "Invalid aircraft or environment header."}
	if typeof(header.get("dt_s")) != TYPE_FLOAT or not is_finite(header.dt_s) or header.dt_s <= 0.0 \
			or not header.checkpoint.get("simulation") is Dictionary:
		return {ok = false, error = "Invalid timestep or initial checkpoint."}
	var layout: Dictionary = header.layout
	for key in ["state", "loads", "inputs", "aux", "continuous", "modes"]:
		if typeof(layout.get(key)) != TYPE_INT or layout[key] < 0 or layout[key] > 4096:
			return {ok = false, error = "Invalid sample layout."}
	if layout.state != 13 or layout.loads != 6 or layout.inputs not in [4, 5, 6, 7] or layout.aux < 4 or layout.modes < 1:
		return {ok = false, error = "Unsupported sample layout."}
	var snapshot: Dictionary = header.checkpoint.simulation
	if snapshot.get("dt") != header.dt_s:
		return {ok = false, error = "Header/checkpoint timestep disagreement."}
	if typeof(snapshot.get("tick")) != TYPE_INT or snapshot.tick < 0 or snapshot.tick > 9007199254740991:
		return {ok = false, error = "Invalid starting tick."}
	var next_tick: int = snapshot.tick
	var rows := 0
	var events: Array = []
	var events_omitted := 0
	var chain := Log.sha256(packet.digest)
	var prefix_end: int = file.get_position()
	while file.get_position() < file.get_length():
		packet = Log.read_packet(file)
		if not packet.ok:
			return _incomplete(header, rows, next_tick, events, prefix_end, packet.error, events_omitted) if recover and rows > 0 else packet
		var value: Dictionary = packet.value
		if value.get("kind") == "footer":
			if typeof(value.get("rows")) != TYPE_INT or typeof(value.get("final_tick")) != TYPE_INT \
					or value.get("rows") != rows or rows < 1 or value.get("final_tick") != next_tick - 1 \
					or value.get("chain_sha256") != chain.hex_encode() or file.get_position() != file.get_length() \
					or typeof(value.get("observer_usec")) != TYPE_INT or typeof(value.get("peak_buffer_rows")) != TYPE_INT:
				return {ok = false, error = "Invalid footer, missing/reordered blocks or trailing bytes."}
			return {ok = true, complete = true, header = header, footer = value, rows = rows, first_tick = snapshot.tick, events = events, events_omitted = events_omitted}
		if value.get("kind") != "block" or not value.get("rows") is Array or not value.get("events") is Array \
				or value.rows.size() > Log.CHUNK_TICKS or value.events.size() > Log.CHUNK_TICKS:
			return {ok = false, error = "Invalid bounded data block."}
		for row: Variant in value.rows:
			var why := validate_row(row, layout, next_tick)
			if not why.is_empty(): return {ok = false, error = why}
			if rows == 0:
				if not snapshot.get("last_loads") is PackedFloat64Array or row.loads.to_byte_array() != snapshot.last_loads.to_byte_array():
					return {ok = false, error = "Initial loads disagree with checkpoint."}
				for key in ["state", "inputs", "aux", "continuous", "modes"]:
					if not snapshot.has(key) or var_to_bytes(row[key]) != var_to_bytes(snapshot[key]):
						return {ok = false, error = "Initial sample disagrees with checkpoint: " + key}
			next_tick += 1
			rows += 1
			if rows > Log.MAX_TICKS + 1: return {ok = false, error = "Too many flight samples."}
		for event: Variant in value.events:
			if not event is Dictionary or typeof(event.get("tick")) != TYPE_INT \
					or event.tick < snapshot.tick or event.tick > next_tick \
					or typeof(event.get("kind")) != TYPE_STRING or typeof(event.get("detail")) != TYPE_STRING:
				return {ok = false, error = "Invalid flight event."}
			# Report summaries are bounded even under an abusive event stream.
			if events.size() < 10000: events.append(event)
			else: events_omitted += 1
		chain = Log.sha256(chain + packet.digest)
		prefix_end = file.get_position()
	if recover and rows > 0:
		return _incomplete(header, rows, next_tick, events, prefix_end, "Missing footer.", events_omitted)
	return {ok = false, error = "Missing footer: interrupted or incomplete flight log; exact replay refused."}


static func _incomplete(header: Dictionary, rows: int, next_tick: int, events: Array, prefix_end: int, reason: String, events_omitted: int) -> Dictionary:
	return {ok = true, complete = false, recovery_reason = reason, prefix_end = prefix_end,
		header = header, rows = rows, first_tick = header.checkpoint.simulation.tick, events = events, events_omitted = events_omitted,
		footer = {final_tick = next_tick - 1, observer_usec = -1, peak_buffer_rows = -1}}


static func validate_row(row: Variant, layout: Dictionary, tick: int) -> String:
	if not row is Dictionary or row.get("kind") != "sample" or typeof(row.get("tick")) != TYPE_INT or row.tick != tick:
		return "Nonconsecutive or malformed tick %d." % tick
	# FUEL-06 logs add a "mass" block (layout.mass = 4); older logs have none.
	for key in ["state", "loads", "inputs", "aux", "continuous", "raw", "sticks", "air"] + (["mass"] if layout.has("mass") else []):
		var size: int = layout.get(key, 6 if key == "air" else 4)
		if not row.get(key) is PackedFloat64Array or row[key].size() != size:
			return "Invalid %s layout at tick %d." % [key, tick]
		for value: float in row[key]:
			if not is_finite(value): return "Nonfinite %s at tick %d." % [key, tick]
	if not row.get("modes") is PackedInt64Array or row.modes.size() != layout.modes or not row.get("intervention") is Dictionary:
		return "Invalid modes/intervention."
	for key: Variant in row.intervention:
		if key not in ["state", "previous", "aux", "continuous", "modes"]:
			return "Unknown intervention field."
		var data: Variant = row.intervention[key]
		var size: int = layout.state if key == "previous" else layout[key]
		if typeof(data) != (TYPE_PACKED_INT64_ARRAY if key == "modes" else TYPE_PACKED_FLOAT64_ARRAY) or data.size() != size:
			return "Invalid intervention array."
		if key != "modes":
			for number: float in data:
				if not is_finite(number): return "Nonfinite intervention."
	return ""


static func prepare_replay(header: Dictionary, candidate := "") -> Dictionary:
	if header.engine != Engine.get_version_info().string:
		return {ok = false, error = "Engine version differs; use the recorded engine."}
	if candidate.is_empty() and (header.solver_sha256 == "unavailable-export" or Log.solver_identity() == "unavailable-export"):
		return {ok = false, error = "Source fingerprint unavailable. Export remains available; exact replay requires a source build."}
	if candidate.is_empty() and header.solver_sha256 != Log.solver_identity():
		return {ok = false, error = "Solver sources differ. Exact replay refused; use explicit --candidate for an experiment."}
	if absf(header.dt_s - 1.0 / Engine.physics_ticks_per_second) > 1e-15:
		return {ok = false, error = "Physics tick rate differs."}
	var aircraft: Dictionary = header.aircraft if candidate.is_empty() else Data.load_file(candidate)
	if not aircraft.get("ok", false): return {ok = false, error = "Candidate aircraft data invalid."}
	var flight := Flight.new()
	flight.input_enabled = false
	flight.crash_auto_restart = false
	flight.soft_hull_contacts = header.soft_hull_contacts
	flight.setup(header.aircraft_path, "", aircraft)
	flight.ground_surfaces = header.ground_surfaces.duplicate()
	flight.ground_field_id = header.ground_field_id
	var ready: bool = flight.setup_shaft_integrator(header.shaft_integrator) \
		and flight.setup_weather(header.weather) and flight.set_collision_world(header.collision_world) and flight.set_lake_context(header.lake)
	flight.reset()
	var checkpoint: Dictionary = header.checkpoint.duplicate(true)
	if not candidate.is_empty():
		var candidate_checkpoint: Dictionary = flight.checkpoint()
		if candidate_checkpoint.is_empty(): ready = false
		else:
			# Open-loop counterfactual: identical body/internal initial state, candidate mass/configuration.
			# Existing restore validates laws, wheel identities, typed layouts and admissibility.
			checkpoint.configuration = candidate_checkpoint.configuration
			for key in ["mass", "inertia", "gravity"]:
				checkpoint.simulation[key] = candidate_checkpoint.simulation[key]
			# wheel_profiles.json gains rows when other aircraft are added. Adopt the candidate's file identity,
			# but keep the recorded canonical profile of this aircraft (wheel_profile_sha256), which restore checks.
			if checkpoint.has("wheel_profile_input_sha256") and candidate_checkpoint.has("wheel_profile_input_sha256"):
				checkpoint.wheel_profile_input_sha256 = candidate_checkpoint.wheel_profile_input_sha256
	if not ready or not flight.restore_checkpoint(checkpoint):
		flight.free()
		return {ok = false, error = "Recorded configuration/checkpoint is incompatible with the selected aircraft or solver."}
	return {ok = true, flight = flight}


static func disagreement(expected: Dictionary, actual: Dictionary) -> String:
	for key in ["state", "loads", "inputs", "aux", "continuous", "modes", "air"] + (["mass"] if expected.has("mass") else []):
		if not actual.has(key) or expected[key].to_byte_array() != actual[key].to_byte_array():
			return "First exact replay divergence at tick %d in %s; no equivalence claimed." % [expected.tick, key]
	return ""


static func columns(layout: Dictionary) -> PackedStringArray:
	var result := PackedStringArray(["tick", "t_s", "loads_t_s"])
	result.append_array(PackedStringArray(RB.STATE_LAYOUT))
	result.append_array(PackedStringArray(["Fx_N", "Fy_N", "Fz_N", "Mx_Nm", "My_Nm", "Mz_Nm", "cmd_roll", "cmd_pitch", "cmd_yaw", "cmd_throttle"]))
	if layout.inputs in [6, 7]: result.append_array(PackedStringArray(["cmd_gear_down", "cmd_wheel_brake"]))
	if layout.inputs in [5, 7]: result.append("cmd_flaps")
	result.append_array(PackedStringArray(["engine_rpm", "srv_roll", "srv_pitch", "srv_yaw"]))
	for i in range(4, layout.aux): result.append("aux_%d" % i)
	for i in layout.continuous: result.append("continuous_%d" % i)
	for prefix in ["raw", "stick"]:
		for axis in ["roll", "pitch", "yaw", "throttle"]: result.append(prefix + "_" + axis)
	result.append_array(PackedStringArray(["tas_mps", "alpha_rad", "beta_rad", "wind_north_mps", "wind_east_mps", "wind_down_mps"]))
	if layout.has("mass"):
		result.append_array(PackedStringArray(["mass_kg", "cg_offset_x_m", "cg_offset_y_m", "cg_offset_z_m"]))
	for i in layout.modes: result.append("mode_%d" % i)
	return result


static func write_row(file: FileAccess, row: Dictionary, dt: float, _first_tick: int) -> void:
	var values := PackedStringArray([str(row.tick), JSON.stringify(row.tick * dt, "", false, true),
		JSON.stringify(maxi(0, row.tick - 1) * dt, "", false, true)])
	for key in ["state", "loads", "inputs", "aux", "continuous", "raw", "sticks", "air"] + (["mass"] if row.has("mass") else []):
		for value: float in row[key]: values.append(JSON.stringify(value, "", false, true))
	for mode: int in row.modes: values.append(str(mode))
	file.store_csv_line(values)


static func write_report_file(path: String, encoded: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		var open_error: Error = FileAccess.get_open_error()
		return open_error if open_error != OK else ERR_FILE_CANT_OPEN
	var stored: bool = file.store_string(encoded)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if not stored and write_error == OK:
		write_error = ERR_FILE_CANT_WRITE
	return write_error


func _finish(error: String) -> void:
	report.error = error
	report.status = "ok" if error.is_empty() else "error"
	if typeof(options.get("report")) == TYPE_STRING and not FileAccess.file_exists(options.report):
		var encoded: String = JSON.stringify(report, "\t", true, true) + "\n"
		var write_error: Error = write_report_file(str(options.report), encoded)
		if write_error != OK:
			error = "Cannot write report %s: %s (error %d)." % [str(options.report), error_string(write_error), write_error]
			report.error = error
			report.status = "error"
	if not error.is_empty(): printerr(error)
	else: print("Flight log %s: %d rows verified." % [report.mode, report.rows])
	quit(0 if error.is_empty() else 1)

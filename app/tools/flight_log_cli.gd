## FL-03: bounded offline export and verified/open-loop replay. No live user settings.
extends SceneTree

const Log := preload("res://sim/flight_log.gd")
const Flight := preload("res://sim/flight_session.gd")
const Data := preload("res://physics/aircraft_data.gd")
const RB := preload("res://physics/rigid_body.gd")
const REFERENCE_STAGE_BACKEND := "gdscript_reference"
const NATIVE_STAGE_BACKEND := "native"
const STAGE_CHECKPOINT_FORMAT := "openrc-flight-checkpoint v14"
var options := {}
var report := {status = "error", error = "Not started", format = "openrc-flight-log-report v1"}


## Current tools can be rebound to older solvers whose FlightSession has no backend API.
static func _session_stage_backend(session: Object) -> Variant:
	return session.call("stage_backend_identity") if session.has_method("stage_backend_identity") \
		else {backend = REFERENCE_STAGE_BACKEND}


static func _valid_stage_backend(identity: Variant) -> bool:
	if not identity is Dictionary or typeof(identity.get("backend")) != TYPE_STRING:
		return false
	if identity.backend == REFERENCE_STAGE_BACKEND:
		return identity.size() == 1
	if identity.backend != NATIVE_STAGE_BACKEND or identity.size() != 6 \
			or typeof(identity.get("backend_version")) != TYPE_STRING or identity.backend_version.is_empty() \
			or typeof(identity.get("abi_version")) != TYPE_INT or identity.abi_version <= 0:
		return false
	for key: String in ["binary_sha256", "source_sha256", "lock_sha256"]:
		if typeof(identity.get(key)) != TYPE_STRING or identity[key].length() != 64 \
				or not identity[key].is_valid_hex_number():
			return false
	return true


## A missing identity is a historical reference log. A present one must be well formed and
## agree with the native checkpoint wrapper, including when a candidate replay unwraps it.
static func recorded_stage_backend(header: Dictionary) -> Dictionary:
	var identity: Variant = header.get("stage_backend", {backend = REFERENCE_STAGE_BACKEND})
	if not _valid_stage_backend(identity):
		return {ok = false, error = "Invalid recorded stage backend identity."}
	var checkpoint: Variant = header.get("checkpoint")
	if not checkpoint is Dictionary:
		return {ok = false, error = "Missing stage checkpoint."}
	var native: bool = identity.backend == NATIVE_STAGE_BACKEND
	var wrapped: bool = checkpoint.get("format") == STAGE_CHECKPOINT_FORMAT
	if wrapped != native:
		return {ok = false, error = "Stage backend and checkpoint wrapper disagree."}
	if wrapped:
		if typeof(checkpoint.get("stage_physics_format")) != TYPE_STRING \
				or checkpoint.stage_physics_format.is_empty() or checkpoint.stage_physics_format == STAGE_CHECKPOINT_FORMAT \
				or not _valid_stage_backend(checkpoint.get("stage_backend")) or checkpoint.stage_backend != identity:
			return {ok = false, error = "Invalid native stage checkpoint identity."}
	elif checkpoint.has("stage_physics_format") or checkpoint.has("stage_backend"):
		return {ok = false, error = "Unexpected stage checkpoint fields."}
	return {ok = true, identity = identity.duplicate(true)}


static func solver_changed(recorded_solver: String, current_solver: String,
		recorded_backend: Dictionary, current_backend: Dictionary,
		recorded_kind := "source-tree-v1", current_kind := "source-tree-v1") -> bool:
	return recorded_solver == "unavailable-export" or current_solver == "unavailable-export" \
		or recorded_kind != current_kind or recorded_solver != current_solver or recorded_backend != current_backend


## The reader is also rebound to older source trees whose FlightLog predates
## package replay identities. Their historical source fingerprint still works.
static func _current_replay_identity() -> Dictionary:
	var script: Script = Log
	if script.has_method("replay_solver_identity") and script.has_method("replay_identity_kind"):
		var digest: Variant = script.call("replay_solver_identity")
		var kind: Variant = script.call("replay_identity_kind")
		if typeof(digest) == TYPE_STRING and typeof(kind) == TYPE_STRING:
			return {sha256 = digest, kind = kind}
		return {sha256 = "unavailable-export", kind = "unavailable"}
	var digest := Log.solver_identity()
	return {sha256 = digest, kind = "source-tree-v1" if digest != "unavailable-export" else "unavailable"}


static func recorded_replay_identity(header: Dictionary) -> Dictionary:
	var kind: Variant = header.get("solver_identity_kind", "source-tree-v1")
	var digest: Variant = header.get("solver_sha256")
	if typeof(kind) != TYPE_STRING or kind not in ["source-tree-v1", "packaged-executable-v1"] \
			or typeof(digest) != TYPE_STRING:
		return {ok = false, error = "Invalid recorded solver identity."}
	if digest == "unavailable-export":
		if kind != "source-tree-v1": return {ok = false, error = "Invalid recorded solver identity."}
	elif digest.length() != 64 or not digest.is_valid_hex_number():
		return {ok = false, error = "Invalid recorded solver identity."}
	return {ok = true, kind = kind, sha256 = digest}


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
	var recorded_backend: Dictionary = recorded_stage_backend(header).identity
	var current_identity := _current_replay_identity()
	var recorded_identity := recorded_replay_identity(header)
	var current_solver: String = current_identity.sha256
	# Export does not run a flight; compare to this tool's reference default until
	# replay selects and verifies an actual stage below.
	var current_backend := {backend = REFERENCE_STAGE_BACKEND}
	report.merge({source = str(options.log), source_sha256 = FileAccess.get_sha256(options.log),
		rows = checked.rows, first_tick = checked.first_tick, final_tick = checked.footer.final_tick,
		dt_s = header.dt_s, complete = checked.complete, recovery_reason = checked.get("recovery_reason", ""), metadata = header.metadata, events = checked.events,
		events_omitted = checked.get("events_omitted", 0),
		baseline_solver_sha256 = header.solver_sha256, current_solver_sha256 = current_solver,
		baseline_solver_identity_kind = recorded_identity.kind, current_solver_identity_kind = current_identity.kind,
		solver_changed = solver_changed(header.solver_sha256, current_solver, recorded_backend, current_backend,
			recorded_identity.kind, current_identity.kind),
		baseline_build = header.build, baseline_stage_backend = recorded_backend, current_stage_backend = current_backend,
		observer_usec = checked.footer.observer_usec, peak_buffer_rows = checked.footer.peak_buffer_rows}, true)
	var flight: Node = null
	if options.has("replay"):
		var prepared := prepare_replay(header, str(options.get("candidate", "")))
		if not prepared.ok:
			_finish(prepared.error)
			return
		flight = prepared.flight
		var active_backend: Dictionary = prepared.stage_backend
		report.current_stage_backend = active_backend
		report.solver_changed = solver_changed(header.solver_sha256, current_solver, recorded_backend, active_backend,
			recorded_identity.kind, current_identity.kind)
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
	csv.store_csv_line(columns(header.layout, header.metadata))
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
	var backend := recorded_stage_backend(header)
	if not backend.ok: return backend
	for key in ["engine", "solver_sha256", "aircraft_path", "ground_field_id", "shaft_integrator"]:
		if typeof(header.get(key)) != TYPE_STRING: return {ok = false, error = "Missing header string: " + key}
	var solver := recorded_replay_identity(header)
	if not solver.ok: return solver
	# GP-07c: logs recorded before the airframe friction table have no airframe_surfaces (soft ones are refused by the
	# contact-law identity anyway); a present one must be a flat table.
	if typeof(header.get("soft_hull_contacts")) != TYPE_BOOL or not header.get("ground_surfaces") is PackedFloat64Array \
			or not header.get("airframe_surfaces", PackedFloat64Array()) is PackedFloat64Array \
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
	var input_contract := input_names(layout, header.metadata)
	if not input_contract.ok:
		return input_contract
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
	var recorded_backend := recorded_stage_backend(header)
	if not recorded_backend.ok: return recorded_backend
	var recorded_identity := recorded_replay_identity(header)
	if not recorded_identity.ok: return recorded_identity
	if header.engine != Engine.get_version_info().string:
		return {ok = false, error = "Engine version differs; use the recorded engine."}
	var current_identity := _current_replay_identity()
	if candidate.is_empty() and (recorded_identity.sha256 == "unavailable-export" \
			or current_identity.sha256 == "unavailable-export" or current_identity.kind == "unavailable"):
		return {ok = false, error = "Solver fingerprint unavailable. Exact replay requires the recorded verified source or package."}
	if candidate.is_empty() and (recorded_identity.kind != current_identity.kind \
			or recorded_identity.sha256 != current_identity.sha256):
		return {ok = false, error = "Solver identity differs. Exact replay refused; use explicit --candidate for an experiment."}
	if absf(header.dt_s - 1.0 / Engine.physics_ticks_per_second) > 1e-15:
		return {ok = false, error = "Physics tick rate differs."}
	var aircraft: Dictionary = header.aircraft if candidate.is_empty() else Data.load_file(candidate)
	if not aircraft.get("ok", false): return {ok = false, error = "Candidate aircraft data invalid."}
	var flight := Flight.new()
	var requested_backend: String = str(recorded_backend.identity.backend) if candidate.is_empty() else REFERENCE_STAGE_BACKEND
	if flight.has_method("setup_stage_backend"):
		if not flight.call("setup_stage_backend", requested_backend):
			flight.free()
			return {ok = false, error = "Recorded stage backend could not be selected."}
	elif requested_backend != REFERENCE_STAGE_BACKEND:
		flight.free()
		return {ok = false, error = "This solver cannot select the recorded native stage backend."}
	flight.input_enabled = false
	flight.crash_auto_restart = false
	flight.soft_hull_contacts = header.soft_hull_contacts
	flight.setup(header.aircraft_path, "", aircraft)
	flight.ground_surfaces = header.ground_surfaces.duplicate()
	# GP-07c: by name, so this shared CLI still compiles against an older accepted solver (tools/companions/rebind.py
	# replays the current tools with app/sim from the accepted revision, which has no airframe table).
	flight.set("airframe_surfaces", header.get("airframe_surfaces", PackedFloat64Array()))
	flight.ground_field_id = header.ground_field_id
	var ready: bool = flight.setup_shaft_integrator(header.shaft_integrator) \
		and flight.setup_weather(header.weather) and flight.set_collision_world(header.collision_world) and flight.set_lake_context(header.lake)
	flight.reset()
	var active_backend: Variant = _session_stage_backend(flight)
	var expected_backend: Dictionary = recorded_backend.identity if candidate.is_empty() else {backend = REFERENCE_STAGE_BACKEND}
	if not _valid_stage_backend(active_backend) or active_backend != expected_backend:
		flight.free()
		return {ok = false, error = "Selected stage backend does not match the recorded or requested identity."}
	var checkpoint: Dictionary = header.checkpoint.duplicate(true)
	if not candidate.is_empty():
		if checkpoint.get("format") == STAGE_CHECKPOINT_FORMAT:
			checkpoint.format = checkpoint.stage_physics_format
			checkpoint.erase("stage_physics_format")
			checkpoint.erase("stage_backend")
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
	if _session_stage_backend(flight) != expected_backend:
		flight.free()
		return {ok = false, error = "Stage backend changed while restoring the checkpoint."}
	var recorded := input_names(header.layout, header.metadata)
	var installed := input_names({inputs = flight.sim.inputs.size()}, flight.trace_meta())
	if not recorded.ok or not installed.ok or recorded.names != installed.names:
		flight.free()
		return {ok = false, error = "Recorded input roles differ from the selected aircraft; replay refused."}
	return {ok = true, flight = flight, stage_backend = expected_backend.duplicate(true)}


static func disagreement(expected: Dictionary, actual: Dictionary) -> String:
	for key in ["state", "loads", "inputs", "aux", "continuous", "modes", "air"] + (["mass"] if expected.has("mass") else []):
		if not actual.has(key) or expected[key].to_byte_array() != actual[key].to_byte_array():
			return "First exact replay divergence at tick %d in %s; no equivalence claimed." % [expected.tick, key]
	return ""


## GP-12: an input width does not identify its roles. Historical logs without
## input_layout retain their original 4/5/6/7-column interpretation. A declared
## layout is authoritative only after validation; never silently relabel it.
## The versioned fixed-brake branch is reader support, not aircraft admission.
const FIXED_BRAKE_INPUT_LAW := "fixed-gear-shared-wheel-brake-input-v1"


static func input_names(layout: Dictionary, metadata: Dictionary = {}) -> Dictionary:
	var width: Variant = layout.get("inputs")
	if typeof(width) != TYPE_INT or width not in [4, 5, 6, 7]:
		return {ok = false, error = "Unsupported recorded input width."}
	var expected := PackedStringArray(["roll", "pitch", "yaw", "throttle"])
	var fixed_brake: bool = metadata.has("fixed_brake_input_law") or metadata.has("wheel_brake_input_index")
	if fixed_brake:
		if typeof(metadata.get("fixed_brake_input_law")) != TYPE_STRING \
				or metadata.fixed_brake_input_law != FIXED_BRAKE_INPUT_LAW \
				or typeof(metadata.get("wheel_brake_input_index")) != TYPE_INT \
				or metadata.wheel_brake_input_index != 4 or width not in [5, 6] \
				or not metadata.has("input_layout"):
			return {ok = false, error = "Invalid fixed-gear brake input contract."}
		for key: String in ["gear_law", "gear_aux_index", "gear_trace_schema", "recording_start_gear"]:
			if metadata.has(key):
				return {ok = false, error = "Conflicting fixed-brake and retractable gear input contracts."}
		expected.append("wheel_brake")
		if width == 6:
			expected.append("flaps")
	else:
		if width in [6, 7]:
			expected.append_array(PackedStringArray(["gear_down", "wheel_brake"]))
		if width in [5, 7]:
			expected.append("flaps")
	for key: String in ["gear_law", "gear_aux_index", "gear_trace_schema", "recording_start_gear"]:
		if metadata.has(key) and not expected.has("gear_down"):
			return {ok = false, error = "Gear metadata disagrees with recorded input roles."}
	for key: String in ["flap_law", "flap_aux_index", "flap_input_index", "flap_trace_schema", "flap_max_angle_deg", "recording_start_flap"]:
		if metadata.has(key) and not expected.has("flaps"):
			return {ok = false, error = "Flap metadata disagrees with recorded input roles."}
	if metadata.has("flap_input_index") and (typeof(metadata.flap_input_index) != TYPE_INT \
			or metadata.flap_input_index != expected.find("flaps")):
		return {ok = false, error = "Flap input index disagrees with recorded input roles."}
	if metadata.has("input_layout"):
		var raw: Variant = metadata.input_layout
		if typeof(raw) != TYPE_STRING or raw.length() > 256:
			return {ok = false, error = "Invalid recorded input layout encoding."}
		var parser := JSON.new()
		if parser.parse(raw) != OK:
			return {ok = false, error = "Invalid recorded input layout JSON."}
		var decoded: Variant = parser.data
		if not decoded is Array or decoded.size() != expected.size():
			return {ok = false, error = "Recorded input layout width disagrees with its contract."}
		for i in expected.size():
			if typeof(decoded[i]) != TYPE_STRING or decoded[i] != expected[i]:
				return {ok = false, error = "Unsupported or conflicting recorded input roles."}
	return {ok = true, names = expected}


static func columns(layout: Dictionary, metadata: Dictionary = {}) -> PackedStringArray:
	var contract := input_names(layout, metadata)
	if not contract.ok:
		return PackedStringArray()
	var result := PackedStringArray(["tick", "t_s", "loads_t_s"])
	result.append_array(PackedStringArray(RB.STATE_LAYOUT))
	result.append_array(PackedStringArray(["Fx_N", "Fy_N", "Fz_N", "Mx_Nm", "My_Nm", "Mz_Nm"]))
	for role: String in contract.names:
		result.append("cmd_" + role)
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

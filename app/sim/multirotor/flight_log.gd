## DR-17: bounded, opt-in multirotor black box. It reuses the checksummed `.orfl` packet container of
## sim/flight_log.gd under its own format, so fixed-wing and airship tools refuse these files. Read-only observer:
## no evaluations and no input writes. The header carries the full session checkpoint envelope at recording start
## (body, shafts, pack, controller block, modes, inputs and the kernel clock), so a recording may start mid-flight.
## Each row is one accepted tick: the pilot frame that drove the interval ending at that tick, then the accepted end
## frame (body, continuous, aux, modes) and that tick's kernel events. `verify` restores the header envelope in a
## fresh session and feeds the recorded PILOT tape (the controller reruns with fresh feedback; recorded motor
## commands are never replayed), comparing every frame byte for byte. Exact replay is same build and platform only.
extends RefCounted

const OrflContainer := preload("res://sim/flight_log.gd")
const BuildInfo := preload("res://app_state/build_info.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")
const SessionScript := preload("res://sim/multirotor/session.gd")

const FORMAT := "openrc-multirotor-flight-log v1"
const REPORT_FORMAT := "openrc-multirotor-flight-log-report v1"
const CHUNK_TICKS := 240
const MAX_TICKS := 240 * 60 * 60
const MAX_BYTES := 512 * 1024 * 1024
const PILOT := 9
const STATE := 13
const AUX := 31
const MODES := 8
## Admitted [pilot, aux, modes] row widths: free flight, and a race session (race action plus the race suffixes).
const LAYOUTS := [[9, 31, 8], [10, 40, 18]]

var recording := false
var path := ""
var note := ""
var failure := ""
var rows_written := 0
var header: Dictionary = {}
var _session: Node
var _file: FileAccess
var _ticks := PackedInt64Array()
var _pilot := PackedFloat64Array()
var _states := PackedFloat64Array()
var _conts := PackedFloat64Array()
var _aux := PackedFloat64Array()
var _modes := PackedInt64Array()
var _events: Array = []
var _chain := PackedByteArray()
var _start_tick := 0
var _last_tick := 0
var _stopping := false


func _init(session: Node) -> void:
	_session = session


## context: {field_path} of the flown field, so a replay rebuilds the same terrain and obstacles.
func start(context: Dictionary = {field_path = ""}, destination := "") -> Error:
	if recording:
		return ERR_ALREADY_IN_USE
	if _session == null or not _session.prepared or not str(_session.fault_reason).is_empty() or not _session.crash.is_empty():
		return _failed("Flight log requires a prepared multirotor flight without a fault or crash.", ERR_UNAVAILABLE)
	var envelope: Dictionary = _session.checkpoint()
	if envelope.is_empty():
		return _failed("Flight log cannot capture the session checkpoint.", ERR_UNAVAILABLE)
	path = destination
	if path.is_empty():
		path = "user://flight_logs/multirotor-%s-%d.orfl" % [Time.get_datetime_string_from_system(true).replace(":", "-"), Time.get_ticks_usec()]
	if FileAccess.file_exists(path):
		return _failed("Flight log already exists: " + path, ERR_ALREADY_EXISTS)
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	if err != OK:
		return _failed("Cannot create flight-log directory (%d)." % err, err)
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		return _failed("Cannot open flight log (%d)." % FileAccess.get_open_error(), ERR_CANT_CREATE)
	failure = ""
	rows_written = 0
	_stopping = false
	_chain.clear()
	_clear_buffers()
	_start_tick = int(_session.sim.tick)
	_last_tick = _start_tick
	var solver := OrflContainer.replay_identity()
	header = {
		kind = "header", format = FORMAT, created_utc = Time.get_datetime_string_from_system(true),
		dt_s = _session.sim.dt(), engine = Engine.get_version_info().string, build = BuildInfo.current(),
		solver_sha256 = solver.sha256, solver_identity_kind = solver.kind,
		session = _session.identity(), options = _session.options.duplicate(true),
		field_path = str(context.get("field_path", "")), collision_identity = _session.collision_identity(),
		checkpoint = envelope,
		layout = {pilot = _session.input_size(), state = STATE, continuous = _session.sim.continuous.size(),
			aux = _session.sim.aux.size(), modes = _session.sim.modes.size()},
		input_boundary = "pilot frame [roll, pitch, yaw, throttle, arm, mode, source generation, source ready, actions] driving the interval that ends at the row tick",
		state_boundary = "accepted tick end: body [n e d u v w q0 q1 q2 q3 p q r], continuous, controller aux and modes",
	}
	_file.store_buffer(OrflContainer.MAGIC.to_ascii_buffer())
	if not _write_packet(header):
		return ERR_FILE_CANT_WRITE
	recording = true
	_session.tick_advanced.connect(_ticked)
	_session.pause_changed.connect(_paused)
	_session.crashed.connect(_crashed)
	_session.depleted.connect(_depleted)
	_session.faulted.connect(_faulted)
	_session.resetting.connect(_resetting)
	note = "Flight log REC: " + ProjectSettings.globalize_path(path)
	print(note)
	return OK


func seconds() -> float:
	return float(_last_tick - _start_tick) / float(SessionScript.FIXED_HZ)


func mark(label := "pilot marker") -> void:
	if recording:
		_event("marker", label.left(160))


func stop(reason := "stopped") -> Error:
	if not recording or _stopping:
		return OK if failure.is_empty() else ERR_FILE_CANT_WRITE
	_stopping = true
	_event("stop", reason.left(160))
	_flush()
	if recording:
		_write_packet({kind = "footer", rows = rows_written, first_tick = _start_tick, final_tick = _last_tick, reason = reason.left(160),
			chain_sha256 = _chain.hex_encode()})
	_disconnect()
	recording = false
	if _file != null:
		_file.close()
		_file = null
	if failure.is_empty():
		note = "Flight log saved: %s (%d ticks)" % [ProjectSettings.globalize_path(path), rows_written]
		print(note)
	return OK if failure.is_empty() else ERR_FILE_CANT_WRITE


func _ticked(tick: int, _time_s: float) -> void:
	if not recording:
		return
	if tick != _last_tick + 1:
		_failed("Flight log stopped: nonconsecutive simulation ticks; file is incomplete.", ERR_INVALID_DATA)
		return
	var sim: Node = _session.sim
	_ticks.append(tick)
	_pilot.append_array(sim.inputs)
	_states.append_array(sim.state)
	_conts.append_array(sim.continuous)
	_aux.append_array(sim.aux)
	_modes.append_array(sim.modes)
	for located: Dictionary in sim.last_events:
		_events.append({tick = tick, kind = "kernel", event = located.duplicate(true)})
	_last_tick = tick
	if _ticks.size() >= CHUNK_TICKS:
		_flush()
	if recording and tick - _start_tick >= MAX_TICKS:
		stop("recording limit reached")


func _paused(value: bool, reason: String) -> void:
	_event("pause" if value else "resume", reason.left(160))


func _crashed(reason: String) -> void:
	# The terminal tick is accepted and recorded; the aftermath keeps flying with the drive cut.
	_event("crash", reason.left(160))


func _depleted() -> void:
	_event("depleted", "pack depleted")


func _faulted(reason: String) -> void:
	if recording:
		stop("simulation fault: " + reason)


func _resetting() -> void:
	stop("session reset, restore or configuration change")


func _event(kind: String, detail: String) -> void:
	if not recording:
		return
	_events.append({tick = int(_session.sim.tick), kind = kind, detail = detail})
	if _events.size() >= CHUNK_TICKS:
		_flush()


func _flush() -> void:
	if not recording or (_ticks.is_empty() and _events.is_empty()):
		return
	var count := _ticks.size()
	if _write_packet({kind = "block", ticks = _ticks, pilot = _pilot, states = _states, continuous = _conts, aux = _aux,
			modes = _modes, events = _events}):
		rows_written += count
	_clear_buffers()
	if recording and not _stopping and _file.get_position() >= MAX_BYTES - 2 * OrflContainer.MAX_PACKET:
		stop("recording byte limit reached")


func _clear_buffers() -> void:
	_ticks = PackedInt64Array()
	_pilot = PackedFloat64Array()
	_states = PackedFloat64Array()
	_conts = PackedFloat64Array()
	_aux = PackedFloat64Array()
	_modes = PackedInt64Array()
	_events = []


func _write_packet(value: Dictionary) -> bool:
	var payload := var_to_bytes(value)
	if payload.is_empty() or payload.size() > OrflContainer.MAX_PACKET:
		_failed("Flight log packet exceeds bounded format.", ERR_INVALID_DATA)
		return false
	if _file.get_position() + payload.size() + 36 > MAX_BYTES:
		_failed("Flight log byte limit exceeded; file is incomplete.", ERR_FILE_CANT_WRITE)
		return false
	var digest := OrflContainer.sha256(payload)
	_file.store_32(payload.size())
	_file.store_buffer(digest)
	_file.store_buffer(payload)
	_file.flush()
	if _file.get_error() != OK:
		_failed("Flight log disk write failed; file is incomplete.", ERR_FILE_CANT_WRITE)
		return false
	_chain = OrflContainer.sha256(_chain + digest)
	return true


func _disconnect() -> void:
	for pair in [[_session.tick_advanced, _ticked], [_session.pause_changed, _paused], [_session.crashed, _crashed],
			[_session.depleted, _depleted], [_session.faulted, _faulted], [_session.resetting, _resetting]]:
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])


## A write or bound failure marks the recording incomplete. It never touches accepted physics.
func _failed(message: String, code: Error) -> Error:
	failure = message
	note = message
	recording = false
	if _session != null:
		_disconnect()
	if _file != null:
		_file.close()
		_file = null
	printerr(message)
	return code


## Bounded read of a whole file: header, blocks and footer, with packet checksums and the chain hash. A truncated
## or damaged file returns the recoverable prefix with complete = false and an error.
static func inspect(file_path: String) -> Dictionary:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return {ok = false, complete = false, error = "Cannot open flight log: " + file_path}
	if file.get_length() < 8 or file.get_buffer(8).get_string_from_ascii() != OrflContainer.MAGIC:
		return {ok = false, complete = false, error = "Not an .orfl flight log."}
	var first := OrflContainer.read_packet(file)
	if not first.ok:
		return {ok = false, complete = false, error = first.error}
	var head: Dictionary = first.value
	if head.get("kind") != "header" or head.get("format") != FORMAT:
		return {ok = false, complete = false, error = "Not an %s file (format %s)." % [FORMAT, str(head.get("format", "?"))]}
	var layout: Variant = head.get("layout")
	# Free flight records the nine-value pilot frame; a race session adds the race action and the race suffixes.
	if typeof(layout) != TYPE_DICTIONARY or int(layout.get("state", -1)) != STATE or int(layout.get("continuous", 0)) <= 0 \
			or [int(layout.get("pilot", -1)), int(layout.get("aux", -1)), int(layout.get("modes", -1))] not in LAYOUTS:
		return {ok = false, complete = false, error = "Unsupported flight-log layout."}
	var cont_size := int(layout.continuous)
	var pilot_size := int(layout.pilot)
	var aux_size := int(layout.aux)
	var modes_size := int(layout.modes)
	var chain := OrflContainer.sha256(PackedByteArray() + first.digest)
	var out := {ok = true, complete = false, header = head, ticks = PackedInt64Array(), pilot = PackedFloat64Array(),
		states = PackedFloat64Array(), continuous = PackedFloat64Array(), aux = PackedFloat64Array(), modes = PackedInt64Array(),
		events = [], footer = {}}
	while file.get_position() < file.get_length():
		var packet := OrflContainer.read_packet(file)
		if not packet.ok:
			out.error = packet.error
			return out
		var value: Dictionary = packet.value
		if value.get("kind") == "footer":
			# The footer reports the chain over the header and blocks, before its own digest.
			out.footer = value
			out.complete = str(value.get("chain_sha256", "")) == chain.hex_encode() and int(value.get("rows", -1)) == out.ticks.size() \
				and file.get_position() == file.get_length()
			break
		chain = OrflContainer.sha256(chain + packet.digest)
		if value.get("kind") != "block":
			out.error = "Unknown packet kind."
			return out
		if typeof(value.get("ticks")) != TYPE_PACKED_INT64_ARRAY or typeof(value.get("pilot")) != TYPE_PACKED_FLOAT64_ARRAY \
				or typeof(value.get("states")) != TYPE_PACKED_FLOAT64_ARRAY or typeof(value.get("continuous")) != TYPE_PACKED_FLOAT64_ARRAY \
				or typeof(value.get("aux")) != TYPE_PACKED_FLOAT64_ARRAY or typeof(value.get("modes")) != TYPE_PACKED_INT64_ARRAY \
				or typeof(value.get("events")) != TYPE_ARRAY:
			out.error = "Malformed block."
			return out
		var ticks: PackedInt64Array = value.ticks
		var count := ticks.size()
		if value.pilot.size() != count * pilot_size or value.states.size() != count * STATE \
				or value.continuous.size() != count * cont_size or value.aux.size() != count * aux_size \
				or value.modes.size() != count * modes_size:
			out.error = "Malformed block."
			return out
		out.ticks.append_array(ticks)
		out.pilot.append_array(value.pilot)
		out.states.append_array(value.states)
		out.continuous.append_array(value.continuous)
		out.aux.append_array(value.aux)
		out.modes.append_array(value.modes)
		out.events.append_array(value.events)
	if not out.complete and not out.has("error"):
		out.error = "Missing or inconsistent footer: interrupted or incomplete flight log; exact replay refused."
	return out


## Replay through a fresh session. Without overrides: exact mode (same data, options, field, obstacles and solver
## identity; restore the header envelope; feed every recorded pilot frame; compare every accepted frame and its
## kernel events byte for byte). With overrides (for example {prepared_data = ...} or {rates = ...}): candidate mode,
## the same pilot tape through the changed controller/plant, reporting trajectory deltas; never an exact claim.
static func verify(file_path: String, overrides: Dictionary = {}) -> Dictionary:
	var candidate := not overrides.is_empty()
	var report := {format = REPORT_FORMAT, log = file_path, ok = false, complete = false, solver_changed = true,
		identity_match = false, exact = false, mode = "candidate" if candidate else "exact", rows = 0, first_mismatch_tick = -1,
		error = "", recorded_crash = "", replayed_crash = ""}
	if candidate:
		report.max_position_delta_m = 0.0
		report.max_rate_delta_radps = 0.0
		report.final_position_delta_m = 0.0
	var read := inspect(file_path)
	if not read.ok or not read.complete:
		report.error = str(read.get("error", "incomplete flight log"))
		return report
	report.complete = true
	var head: Dictionary = read.header
	report.solver_changed = str(head.get("solver_sha256", "")) != str(OrflContainer.replay_identity().sha256)
	report.rows = read.ticks.size()
	var field := {}
	if not str(head.get("field_path", "")).is_empty():
		var loaded := FieldLoader.load_from(str(head.field_path))
		if not loaded.ok:
			report.error = "Recorded field cannot be loaded: " + "; ".join(loaded.errors)
			return report
		field = loaded.field
	var session: Node = SessionScript.new()
	var result := _replay(session, field, head, read, report, overrides)
	session.free()
	return result


static func _replay(session: Node, field: Dictionary, head: Dictionary, read: Dictionary, report: Dictionary,
		overrides: Dictionary = {}) -> Dictionary:
	var candidate := not overrides.is_empty()
	if typeof(head.get("options")) != TYPE_DICTIONARY or typeof(head.get("checkpoint")) != TYPE_DICTIONARY \
			or typeof(head.get("session")) != TYPE_DICTIONARY:
		report.error = "Recorded header is malformed."
		return report
	if not str(head.get("collision_identity", "")).is_empty():
		# RC-TRACK: a flight recorded with the RC car circuit had its dressing in the obstacle inventory; a candidate
		# that overrides the circuit gets the matching inventory (terrain and obstacles stay one decision).
		var recorded_track: Variant = overrides.get("rc_track", head.options.get("rc_track", {}))
		var built: Dictionary = CollisionSetup.build(field, recorded_track if typeof(recorded_track) == TYPE_DICTIONARY else {})
		if not built.ok or str(built.world.get("identity", "")) != str(head.collision_identity) or not session.set_collision_world(built.world):
			report.error = "Recorded obstacle inventory differs from the current field."
			return report
	var options: Dictionary = head.options.duplicate(true)
	options.merge(overrides.duplicate(true), true)
	if not session.prepare(field, options):
		report.error = "Recorded configuration is refused: " + str(session.load_error)
		return report
	var envelope: Dictionary = head.checkpoint.duplicate(true)
	report.identity_match = not candidate and var_to_bytes(session.identity()) == var_to_bytes(head.session) \
		and var_to_bytes(envelope.get("identity", {})) == var_to_bytes(head.session)
	if not candidate and not report.identity_match:
		report.error = "Session identity (law, controller, rates, data, start, weather or field) differs from the recording."
		return report
	if candidate:
		# A candidate deliberately crosses identities: it starts from the recorded frame under the changed law.
		envelope.identity = session.identity()
	if not session.restore_checkpoint(envelope):
		report.error = "Recorded checkpoint is refused" + (" by the candidate configuration." if candidate else ".")
		return report
	if session.paused and not session.resume():
		report.error = "Recorded checkpoint cannot resume: " + str(session.pause_reason)
		return report
	var cont_size := int(head.layout.continuous)
	var pilot_size := int(head.layout.pilot)
	var aux_size := int(head.layout.aux)
	var modes_size := int(head.layout.modes)
	var pilot: PackedFloat64Array = read.pilot
	var states: PackedFloat64Array = read.states
	var conts: PackedFloat64Array = read.continuous
	var aux: PackedFloat64Array = read.aux
	var modes: PackedInt64Array = read.modes
	var kernel_events := {}
	var recorded_crash := {}
	for event: Variant in read.events:
		if typeof(event) != TYPE_DICTIONARY:
			continue
		if event.get("kind") == "kernel" and typeof(event.get("event")) == TYPE_DICTIONARY:
			var at := int(event.tick)
			if not kernel_events.has(at):
				kernel_events[at] = []
			kernel_events[at].append(event.event)
			if recorded_crash.is_empty() and event.event.get("type") == "crash":
				recorded_crash = {tick = at, reason = str(event.event.get("reason", ""))}
	var envelope_crash: Dictionary = head.checkpoint.get("crash", {})
	if recorded_crash.is_empty() and not envelope_crash.is_empty():
		recorded_crash = {tick = int(envelope_crash.tick), reason = str(envelope_crash.reason)}
	for i in read.ticks.size():
		var tick := int(read.ticks[i])
		if not session.tick_input(pilot.slice(pilot_size * i, pilot_size * i + pilot_size)):
			report.first_mismatch_tick = tick
			report.error = "Replay refused a recorded tick: " + str(session.pause_reason)
			return report
		var sim: Node = session.sim
		if candidate:
			var dn: float = sim.state[0] - states[STATE * i]
			var de: float = sim.state[1] - states[STATE * i + 1]
			var dd: float = sim.state[2] - states[STATE * i + 2]
			var dp: float = sim.state[10] - states[STATE * i + 10]
			var dq: float = sim.state[11] - states[STATE * i + 11]
			var dr: float = sim.state[12] - states[STATE * i + 12]
			var position_delta := sqrt(dn * dn + de * de + dd * dd)
			report.max_position_delta_m = maxf(float(report.max_position_delta_m), position_delta)
			report.max_rate_delta_radps = maxf(float(report.max_rate_delta_radps), sqrt(dp * dp + dq * dq + dr * dr))
			report.final_position_delta_m = position_delta
			continue
		var events_match := var_to_bytes(_plain(sim.last_events)) == var_to_bytes(_plain(kernel_events.get(tick, [])))
		if sim.tick != tick or not events_match \
				or sim.state.to_byte_array() != states.slice(STATE * i, STATE * i + STATE).to_byte_array() \
				or sim.continuous.to_byte_array() != conts.slice(cont_size * i, cont_size * i + cont_size).to_byte_array() \
				or sim.aux.to_byte_array() != aux.slice(aux_size * i, aux_size * i + aux_size).to_byte_array() \
				or sim.modes.to_byte_array() != modes.slice(modes_size * i, modes_size * i + modes_size).to_byte_array():
			report.first_mismatch_tick = tick
			report.error = "Replay diverged from the recorded frame." if events_match else "Replay events differ from the recording."
			return report
	var replayed_crash: Dictionary = session.crash
	report.recorded_crash = str(recorded_crash.get("reason", ""))
	report.replayed_crash = str(replayed_crash.get("reason", ""))
	if candidate:
		report.ok = true
		return report
	if recorded_crash.is_empty() != replayed_crash.is_empty() or report.recorded_crash != report.replayed_crash \
			or (not recorded_crash.is_empty() and int(recorded_crash.tick) != int(replayed_crash.tick)):
		report.error = "Replay terminal outcome differs from the recording."
		return report
	if report.solver_changed:
		report.error = "Every frame matched, but the solver identity changed: not an exact replay."
		return report
	report.exact = true
	report.ok = true
	return report


static func _plain(events: Array) -> Array:
	var out: Array = []
	for event: Variant in events:
		out.append(event.duplicate(true) if typeof(event) == TYPE_DICTIONARY else event)
	return out

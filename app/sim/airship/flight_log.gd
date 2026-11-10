## BL-08: bounded, opt-in RC blimp black box. It reuses the checksummed `.orfl` packet container of
## sim/flight_log.gd under its own format, so fixed-wing tools refuse these files. Read-only observer: no
## evaluations and no input writes. Each row is one accepted tick: the clean sticks [roll, pitch, yaw, throttle]
## that drove the interval ending at that tick, then the end state and continuous block. `verify` replays a
## complete file from its checkpoint through a fresh session and compares every row byte for byte.
extends RefCounted

const OrflContainer := preload("res://sim/flight_log.gd")
const BuildInfo := preload("res://app_state/build_info.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")
const SessionScript := preload("res://sim/airship/session.gd")

const FORMAT := "openrc-airship-flight-log v1"
const REPORT_FORMAT := "openrc-airship-flight-log-report v1"
const CHUNK_TICKS := 240
const MAX_TICKS := 240 * 60 * 60
const MAX_BYTES := 512 * 1024 * 1024
const STATE := 13
const STICKS := 4

var recording := false
var path := ""
var note := ""
var failure := ""
var rows_written := 0
var header: Dictionary = {}
var _session: Node
var _file: FileAccess
var _ticks := PackedInt64Array()
var _sticks := PackedFloat64Array()
var _states := PackedFloat64Array()
var _conts := PackedFloat64Array()
var _events: Array = []
var _chain := PackedByteArray()
var _start_tick := 0
var _last_tick := 0
var _stopping := false


func _init(session: Node) -> void:
	_session = session


## context: {field_path} of the flown field, so a replay rebuilds the same terrain and obstacles.
func start(context: Dictionary = {}, destination := "") -> Error:
	if recording:
		return ERR_ALREADY_IN_USE
	if not _session.prepared or not str(_session.fault_reason).is_empty() or not _session.crash.is_empty():
		return _failed("Flight log requires a prepared blimp flight without a fault or crash.", ERR_UNAVAILABLE)
	path = destination
	if path.is_empty():
		path = "user://flight_logs/airship-%s-%d.orfl" % [Time.get_datetime_string_from_system(true).replace(":", "-"), Time.get_ticks_usec()]
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
	_start_tick = _session.sim.tick
	_last_tick = _start_tick
	var solver := OrflContainer.replay_identity()
	header = {
		kind = "header", format = FORMAT, created_utc = Time.get_datetime_string_from_system(true),
		dt_s = _session.sim.dt(), engine = Engine.get_version_info().string, build = BuildInfo.current(),
		solver_sha256 = solver.sha256, solver_identity_kind = solver.kind,
		session = _session.identity(), options = _session.options.duplicate(true),
		field_path = str(context.get("field_path", "")), collision_identity = _session.collision_identity(),
		checkpoint = {tick = _start_tick, state = _session.sim.state.duplicate(), continuous = _session.sim.continuous.duplicate()},
		layout = {sticks = STICKS, state = STATE, continuous = _session.sim.continuous.size()},
		input_boundary = "clean sticks [roll, pitch, yaw, throttle] driving the interval that ends at the row tick",
		state_boundary = "accepted tick end: body [n e d u v w q0 q1 q2 q3 p q r] and continuous [motor x4, vector x3, fin x3, soc]",
	}
	_file.store_buffer(OrflContainer.MAGIC.to_ascii_buffer())
	if not _write_packet(header):
		return ERR_FILE_CANT_WRITE
	recording = true
	_session.tick_advanced.connect(_ticked)
	_session.pause_changed.connect(_paused)
	_session.crashed.connect(_crashed)
	_session.faulted.connect(_faulted)
	_session.resetting.connect(_resetting)
	note = "Flight log REC: " + ProjectSettings.globalize_path(path)
	print(note)
	return OK


func seconds() -> float:
	return float(_last_tick - _start_tick) * float(_session.sim.dt())


func mark(label := "pilot marker") -> void:
	if recording:
		_event("marker", label.left(160))


func stop(reason := "stopped") -> Error:
	if not recording or _stopping:
		return OK if failure.is_empty() else ERR_FILE_CANT_WRITE
	_stopping = true
	_event("stop", reason)
	_flush()
	if recording:
		_write_packet({kind = "footer", rows = rows_written, first_tick = _start_tick, final_tick = _last_tick, reason = reason,
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
	_ticks.append(tick)
	_sticks.append_array(_session.sim.inputs)
	_states.append_array(_session.sim.state)
	_conts.append_array(_session.sim.continuous)
	_last_tick = tick
	if _ticks.size() >= CHUNK_TICKS:
		_flush()
	if recording and tick - _start_tick >= MAX_TICKS:
		stop("recording limit reached")


func _paused(value: bool, reason: String) -> void:
	_event("pause" if value else "resume", reason.left(160))


func _crashed(reason: String) -> void:
	# The terminal tick is still accepted and recorded; the paused flight then stops ticking.
	_event("crash", reason.left(160))


func _faulted(reason: String) -> void:
	if recording:
		stop("simulation fault: " + reason)


func _resetting() -> void:
	stop("session reset or configuration change")


func _event(kind: String, detail: String) -> void:
	if not recording:
		return
	# The session tick: an event raised inside an accepted tick (crash, its pause) carries that tick.
	_events.append({tick = int(_session.sim.tick), kind = kind, detail = detail})
	if _events.size() >= CHUNK_TICKS:
		_flush()


func _flush() -> void:
	if not recording or (_ticks.is_empty() and _events.is_empty()):
		return
	var count := _ticks.size()
	if _write_packet({kind = "block", ticks = _ticks, sticks = _sticks, states = _states, continuous = _conts, events = _events}):
		rows_written += count
	_clear_buffers()
	if recording and not _stopping and _file.get_position() >= MAX_BYTES - 2 * OrflContainer.MAX_PACKET:
		stop("recording byte limit reached")


func _clear_buffers() -> void:
	_ticks = PackedInt64Array()
	_sticks = PackedFloat64Array()
	_states = PackedFloat64Array()
	_conts = PackedFloat64Array()
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
			[_session.faulted, _faulted], [_session.resetting, _resetting]]:
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])


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


## Bounded read of a whole file: header, blocks and footer, with packet checksums and the chain hash.
static func inspect(file_path: String) -> Dictionary:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return {ok = false, error = "Cannot open flight log: " + file_path}
	if file.get_length() < 8 or file.get_buffer(8).get_string_from_ascii() != OrflContainer.MAGIC:
		return {ok = false, error = "Not an .orfl flight log."}
	var first := OrflContainer.read_packet(file)
	if not first.ok:
		return {ok = false, error = first.error}
	var head: Dictionary = first.value
	if head.get("kind") != "header" or head.get("format") != FORMAT:
		return {ok = false, error = "Not an %s file (format %s)." % [FORMAT, str(head.get("format", "?"))]}
	var chain := OrflContainer.sha256(PackedByteArray() + first.digest)
	var out := {ok = true, complete = false, header = head, ticks = PackedInt64Array(), sticks = PackedFloat64Array(),
		states = PackedFloat64Array(), continuous = PackedFloat64Array(), events = [], footer = {}}
	var layout: Dictionary = head.layout
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
		var ticks: PackedInt64Array = value.ticks
		var count := ticks.size()
		if value.sticks.size() != count * int(layout.sticks) or value.states.size() != count * int(layout.state) \
				or value.continuous.size() != count * int(layout.continuous):
			out.error = "Malformed block."
			return out
		out.ticks.append_array(ticks)
		out.sticks.append_array(value.sticks)
		out.states.append_array(value.states)
		out.continuous.append_array(value.continuous)
		out.events.append_array(value.events)
	if not out.complete and not out.has("error"):
		out.error = "Missing or inconsistent footer: interrupted or incomplete flight log; exact replay refused."
	return out



## Exact replay through a fresh session: same data, options, field, obstacles and solver identity, then every
## recorded stick row from the checkpoint, comparing state and continuous bytes at each accepted tick.
static func verify(file_path: String) -> Dictionary:
	var report := {format = REPORT_FORMAT, log = file_path, ok = false, complete = false, solver_changed = true,
		identity_match = false, exact = false, rows = 0, first_mismatch_tick = -1, error = ""}
	var read := inspect(file_path)
	if not read.ok or not read.complete:
		report.error = str(read.get("error", "incomplete flight log"))
		return report
	report.complete = true
	var head: Dictionary = read.header
	report.solver_changed = str(head.solver_sha256) != str(OrflContainer.replay_identity().sha256)
	report.rows = read.ticks.size()
	var field := {}
	if not str(head.field_path).is_empty():
		var loaded := FieldLoader.load_from(str(head.field_path))
		if not loaded.ok:
			report.error = "Recorded field cannot be loaded: " + "; ".join(loaded.errors)
			return report
		field = loaded.field
	var session: Node = SessionScript.new()
	var result := _replay(session, field, head, read, report)
	session.free()
	return result


static func _replay(session: Node, field: Dictionary, head: Dictionary, read: Dictionary, report: Dictionary) -> Dictionary:
	if not str(head.collision_identity).is_empty():
		var built: Dictionary = CollisionSetup.build(field)
		if not built.ok or str(built.world.get("identity", "")) != str(head.collision_identity) or not session.set_collision_world(built.world):
			report.error = "Recorded obstacle inventory differs from the current field."
			return report
	if not session.prepare(field, head.options):
		report.error = "Recorded configuration is refused: " + str(session.load_error)
		return report
	report.identity_match = var_to_bytes(session.identity()) == var_to_bytes(head.session)
	if not report.identity_match:
		report.error = "Session identity (law, mixer, data, layout, weather or field) differs from the recording."
		return report
	if not session.restore_checkpoint(head.checkpoint.state, head.checkpoint.continuous):
		report.error = "Recorded checkpoint is refused."
		return report
	var layout: Dictionary = head.layout
	var cont_size := int(layout.continuous)
	var sticks: PackedFloat64Array = read.sticks
	var states: PackedFloat64Array = read.states
	var conts: PackedFloat64Array = read.continuous
	for i in read.ticks.size():
		if not session.tick_once(sticks.slice(STICKS * i, STICKS * i + STICKS)):
			report.first_mismatch_tick = int(read.ticks[i])
			report.error = "Replay refused a recorded tick: " + str(session.pause_reason)
			return report
		if session.sim.state.to_byte_array() != states.slice(STATE * i, STATE * i + STATE).to_byte_array() \
				or session.sim.continuous.to_byte_array() != conts.slice(cont_size * i, cont_size * i + cont_size).to_byte_array():
			report.first_mismatch_tick = int(read.ticks[i])
			report.error = "Replay diverged from the recorded state."
			return report
	# Terminal outcome: the same crash at the same tick, or none (obstacle and contact code outside the solver
	# fingerprint can change it without changing any recorded state).
	var recorded_crash := {}
	for event: Dictionary in read.events:
		if event.kind == "crash":
			recorded_crash = event
			break
	var offset := int(head.checkpoint.tick)
	var replayed_crash: Dictionary = session.crash
	report.recorded_crash = str(recorded_crash.get("detail", ""))
	report.replayed_crash = str(replayed_crash.get("reason", "")).left(160)
	if recorded_crash.is_empty() != replayed_crash.is_empty() or report.recorded_crash != report.replayed_crash \
			or (not recorded_crash.is_empty() and int(recorded_crash.tick) != int(replayed_crash.tick) + offset):
		report.error = "Replay terminal outcome differs from the recording."
		return report
	report.exact = true
	report.ok = true
	return report

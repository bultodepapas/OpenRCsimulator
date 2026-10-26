## AFC-02: fixed-roster diagnostic capture. Reuses the bounded .orfl writer;
## this manifest is not a fleet checkpoint or an AI decision-replay format.
extends RefCounted

const Log := preload("res://sim/flight_log.gd")
const BuildInfo := preload("res://app_state/build_info.gd")
const FORMAT := "openrc-companion-capture v1"
const MAX_TICKS := 28800 # 120 simulated seconds, independent of render rate.
const MAX_STREAMS := 4
const MAX_MANIFEST_BYTES := 256 * 1024

var _active := false
var _directory := ""
var _failure := ""
var _last_tick := 0
var _max_ticks := MAX_TICKS
var _pending_reason := ""
var _manifest: Dictionary = {}
var _summary: Dictionary = {}
var _sessions: Array[Node] = []
var _logs: Array[RefCounted] = []
var _ids: Array[String] = []


func start(player: Node, agents: Array[Node], metadata: Dictionary, destination: String,
		max_ticks: int = MAX_TICKS) -> Dictionary:
	if _active:
		return _refuse("A companion capture is already active.")
	if agents.is_empty() or agents.size() + 1 > MAX_STREAMS or max_ticks < 1 or max_ticks > MAX_TICKS:
		return _refuse("Capture requires 1–3 companions and a duration of 1–28,800 ticks.")
	var sessions: Array[Node] = [player]
	var ids: Array[String] = ["player"]
	for agent: Node in agents:
		if not is_instance_valid(agent) or not agent.failure.is_empty():
			return _refuse("Capture requires a healthy fixed roster.")
		sessions.append(agent.session)
		ids.append("companion-%d" % int(agent.slot_id))
	for session: Node in sessions:
		if not is_instance_valid(session) or not session.physics_enabled or session.sim.tick != 0 \
				or not session.crash.is_empty() or not session.sim.fault_reason.is_empty() \
				or not is_equal_approx(session.sim.dt(), 1.0 / 240.0):
			return _refuse("Start a companion capture at the common 240 Hz launch boundary, before the first tick.")
	if destination.strip_edges().is_empty() or destination.length() > 4096:
		return _refuse("Capture requires a new absolute output directory.")
	var directory := ProjectSettings.globalize_path(destination).simplify_path()
	if not directory.is_absolute_path() or DirAccess.dir_exists_absolute(directory) or FileAccess.file_exists(directory):
		return _refuse("Capture directory must be new and absolute: " + directory)
	var parent_error := DirAccess.make_dir_recursive_absolute(directory.get_base_dir())
	if parent_error != OK:
		return _refuse("Cannot create the capture parent directory (%d)." % parent_error)
	var directory_error := DirAccess.make_dir_absolute(directory)
	if directory_error != OK:
		return _refuse("Cannot reserve the new capture directory (%d)." % directory_error)
	_directory = directory
	_failure = ""
	_pending_reason = ""
	_last_tick = 0
	_max_ticks = max_ticks
	_sessions = sessions
	_ids = ids
	_summary.clear()
	var roster: Array[Dictionary] = []
	for index: int in sessions.size():
		roster.append({id = ids[index], generation = 0, local_tick_origin = 0,
			aircraft_identity = sessions[index].aircraft.input_identity.duplicate(true),
			log = ids[index] + ".orfl"})
	_manifest = {format = FORMAT, kind = "manifest", complete = false,
		capture_id = "%s-%d" % [Time.get_datetime_string_from_system(true), Time.get_ticks_usec()],
		engine = Engine.get_version_info().string, build = BuildInfo.current(),
		physics_hz = 240, dt_s = 1.0 / 240.0, global_tick_origin = 0,
		max_ticks = max_ticks, max_streams = MAX_STREAMS, max_bytes_per_stream = Log.MAX_BYTES,
		max_buffer_rows_per_stream = Log.CHUNK_TICKS, roster = roster,
		admission = metadata.duplicate(true), source_sha256 = _source_hashes(),
		source_scope = "Selected capture/admission scripts; full solver identity is in each .orfl header. Not a complete application build hash.",
		rng_state = "Exact session RNG state is in each .orfl initial checkpoint; pilot phase uses the admitted slot and seed.",
		generation_scope = "Generation zero within this capture only; membership changes close the capture.",
		replay_scope = {per_session_inputs = "Use existing .orfl verification; do not infer fleet equivalence.",
			fleet_restore = false, decision_replay = false, shared_world_replay = false},
		scope = "Fixed-roster diagnostic capture. A final summary is required to establish a complete common-clock capture."}
	var manifest_error := _write_json_new("manifest.json", _manifest)
	if manifest_error != OK:
		_sessions.clear()
		_ids.clear()
		_failure = "Cannot write capture manifest (%d)." % manifest_error
		return _refuse(_failure)
	_active = true
	for index: int in sessions.size():
		var writer := Log.new(sessions[index])
		_logs.append(writer)
		if writer.start(_directory.path_join(ids[index] + ".orfl")) != OK:
			_failure = "Cannot start %s capture: %s" % [ids[index], writer.failure]
			stop("capture startup failed", false)
			return _refuse(_failure)
	# Attach the monitor LAST: manager drives all AI, their log callbacks run,
	# then the player's log callback records its accepted row before we finalize.
	player.sim.stepped.connect(_stepped)
	for session: Node in _sessions:
		session.resetting.connect(_resetting)
		session.sim.faulted.connect(_faulted)
		session.scenery_damage_changed.connect(_world_changed)
	print("Companion capture REC: " + _directory)
	return {ok = true, errors = PackedStringArray()}


func status() -> Dictionary:
	return {active = _active, complete = bool(_summary.get("complete", false)),
		error = _failure, directory = _directory, last_tick = _last_tick,
		max_ticks = _max_ticks, summary = _summary.duplicate(true)}


func mark(label := "pilot marker") -> void:
	if not _active: return
	for writer: RefCounted in _logs:
		writer.mark(label.left(160))
		if not writer.recording or not writer.failure.is_empty():
			_pending_reason = "Capture writer failed while recording a marker."
	if not _pending_reason.is_empty(): stop("capture marker failed", false)


func stop(reason := "stopped", valid := true) -> Dictionary:
	if not _active:
		return status()
	_active = false
	_disconnect()
	if not _pending_reason.is_empty():
		_failure = _pending_reason
	valid = valid and _failure.is_empty()
	var streams: Array[Dictionary] = []
	for index: int in _logs.size():
		var writer: RefCounted = _logs[index]
		var stopped: Error = writer.stop(reason.left(160))
		var aligned: bool = is_instance_valid(_sessions[index]) and _closing_tick(_sessions[index]) == _last_tick \
			and writer.rows_written == _last_tick + 1
		var complete: bool = stopped == OK and writer.failure.is_empty() and aligned
		valid = valid and complete
		if not complete and _failure.is_empty():
			_failure = "Capture stream %s ended early or outside the common tick boundary." % _ids[index]
		var path: String = _directory.path_join(_ids[index] + ".orfl")
		var input := FileAccess.open(path, FileAccess.READ)
		var bytes: int = input.get_length() if input != null else 0
		if input != null: input.close()
		var digest := FileAccess.get_sha256(path) if bytes > 0 else ""
		if digest.is_empty():
			complete = false
			valid = false
			if _failure.is_empty(): _failure = "Cannot fingerprint capture stream " + _ids[index]
		streams.append({id = _ids[index], generation = 0, log = _ids[index] + ".orfl",
			complete = complete, final_tick = writer.rows_written - 1, rows = writer.rows_written,
			session_tick = _closing_tick(_sessions[index]) if is_instance_valid(_sessions[index]) else -1,
			bytes = bytes, sha256 = digest, error = writer.failure})
	valid = valid and _logs.size() == _sessions.size()
	_summary = {format = FORMAT, kind = "summary", capture_id = _manifest.capture_id,
		complete = valid, reason = reason.left(160), error = _failure, final_tick = _last_tick,
		manifest_sha256 = FileAccess.get_sha256(_directory.path_join("manifest.json")), streams = streams,
		replay_scope = _manifest.replay_scope.duplicate(true)}
	var written := _write_json_new("summary.json", _summary)
	if written != OK:
		_failure = "Cannot write capture summary (%d); capture is incomplete." % written
		_summary.complete = false
		_summary.error = _failure
	# Do not retain the large .orfl headers or references to retired sessions.
	_logs.clear()
	_sessions.clear()
	_ids.clear()
	_manifest.clear()
	print("Companion capture closed: %s (complete=%s, tick=%d)" % [_directory, str(_summary.complete), _last_tick])
	if not _failure.is_empty(): printerr(_failure)
	return status()


func _stepped(tick: int, _time: float, _state: PackedFloat64Array,
		_loads: PackedFloat64Array, _inputs: PackedFloat64Array, _aux: PackedFloat64Array) -> void:
	if not _active: return
	if tick != _last_tick + 1:
		_pending_reason = "Capture observed nonconsecutive player ticks."
	_last_tick = tick
	for index: int in _sessions.size():
		var session: Node = _sessions[index]
		if not _logs[index].recording or not _logs[index].failure.is_empty():
			_pending_reason = "Capture writer stopped early: " + _ids[index]
		if session.sim.tick != tick or not session.crash.is_empty() or not session.sim.fault_reason.is_empty():
			_pending_reason = "Capture fleet stopped sharing a healthy tick boundary: " + _ids[index]
	if not _pending_reason.is_empty():
		stop("fleet capture interrupted", false)
	elif tick >= _max_ticks:
		stop("capture duration reached")


static func _closing_tick(session: Node) -> int:
	var closing: Dictionary = session.reset_closing_context() if session.has_method("reset_closing_context") else {}
	return int(closing.tick) if not closing.is_empty() else session.sim.tick


func _resetting() -> void:
	stop("session reset or configuration change")


func _faulted(reason: String) -> void:
	_pending_reason = "Simulation fault during capture: " + reason.left(160)
	# A fault can occur inside the manager callback before the player's log row.
	# Finish after that signal stack; a rejected player step has no stepped signal.
	call_deferred("_stop_pending")


func _world_changed() -> void:
	_pending_reason = "Shared scenery changed; this capture does not encode fleet world events."
	call_deferred("_stop_pending")


func _stop_pending() -> void:
	if _active and not _pending_reason.is_empty():
		stop("fleet capture interrupted", false)


func _disconnect() -> void:
	if not _sessions.is_empty() and is_instance_valid(_sessions[0]):
		if _sessions[0].sim.stepped.is_connected(_stepped): _sessions[0].sim.stepped.disconnect(_stepped)
	for session: Node in _sessions:
		if not is_instance_valid(session): continue
		if session.resetting.is_connected(_resetting): session.resetting.disconnect(_resetting)
		if session.sim.faulted.is_connected(_faulted): session.sim.faulted.disconnect(_faulted)
		if session.scenery_damage_changed.is_connected(_world_changed): session.scenery_damage_changed.disconnect(_world_changed)


func _write_json_new(name: String, value: Dictionary) -> Error:
	var path := _directory.path_join(name)
	if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path): return ERR_ALREADY_EXISTS
	var bytes := (JSON.stringify(value, "\t") + "\n").to_utf8_buffer()
	if bytes.size() > MAX_MANIFEST_BYTES: return ERR_OUT_OF_MEMORY
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_buffer(bytes)
	file.flush()
	var result := file.get_error()
	file.close()
	return result


static func _source_hashes() -> Dictionary:
	var result := {}
	for path: String in ["res://ai/companions/fleet_record.gd", "res://ai/companions/manager.gd",
			"res://ai/companions/agent.gd", "res://ai/companions/pilot.gd",
			"res://ai/companions/circuit_controller.gd", "res://sim/flight_log.gd",
			"res://ai/companions/config.gd", "res://ai/companions/profile_loader.gd",
			"res://ai/companions/airspace.gd", "res://main.gd"]:
		result[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "unavailable"
	return result


func _refuse(message: String) -> Dictionary:
	if not _active: _failure = message
	return {ok = false, errors = PackedStringArray([message])}

## Bounded offline replay of a fixed companion roster from nonzero-tick ORFL streams.
## This is a research seam only; it is not called by Main or the production manager.
extends RefCounted

const Log := preload("res://sim/flight_log.gd")
const Reader := preload("res://tools/flight_log_cli.gd")
const CheckpointJson := preload("res://sim/checkpoint_json.gd")
const Candidate := preload("res://../research/ai-companions/checkpoints/fleet_checkpoint_candidate.gd")

const FORMAT := "openrc-offline-fleet-decision-replay v1"
const CAPTURE_MANIFEST := "decision-replay.json"
const STOP_REASON := "offline fleet decision replay complete"
const MAX_STREAMS := 4
const MAX_REPLAY_ROWS := Candidate.MAX_FUTURE_TICKS + 1
const MAX_STREAM_BYTES := 64 * 1024 * 1024
const MAX_TOTAL_STREAM_BYTES := 128 * 1024 * 1024
const MAX_CARRIER_BYTES := 256 * 1024
const MAX_EVENTS := 10000 # Reader.inspect reports, but does not retain, later events.
const SAMPLE_KEYS := ["kind", "tick", "state", "inputs", "aux", "continuous", "modes", "loads",
	"intervention", "raw", "sticks", "air"]
const SAMPLE_MASS_KEYS := SAMPLE_KEYS + ["mass"]
const EVENT_KEYS := ["tick", "kind", "detail"]
const AXES := ["roll", "pitch", "yaw", "throttle"]


## Open one ORFL writer per session at an already accepted, nonzero common tick.
## destination must be a new absolute directory; no existing capture is overwritten.
static func start_capture(fixture: Dictionary, record: Dictionary, destination: String) -> Dictionary:
	var refusal := _fixture_refusal(fixture, record)
	if not refusal.is_empty():
		return {ok = false, reason = refusal}
	var directory := _new_directory(destination)
	if not directory.ok:
		return directory
	var sessions: Array[Node] = [fixture.player]
	var ids: Array[String] = ["player"]
	for index in fixture.manager.agents.size():
		sessions.append(fixture.manager.agents[index].session)
		ids.append("companion-%d" % index)
	var paths := {}
	var writers: Array = []
	for index in sessions.size():
		var path: String = directory.path.path_join(ids[index] + ".orfl")
		var writer: Variant = Log.new(sessions[index])
		var result: Error = writer.start(path)
		if result != OK:
			for started: Variant in writers:
				started.stop("capture startup failed")
			return {ok = false, reason = "could not start %s ORFL writer: %s" % [ids[index], writer.failure]}
		writers.append(writer)
		paths[ids[index]] = path
	return {ok = true, directory = directory.path, paths = paths, ids = ids, writers = writers,
		capture_tick = record.capture_tick}


## Stop each writer and return a source-bound, losslessly serializable capture manifest.
static func finish_capture(capture: Dictionary, record: Dictionary,
		reason: String = STOP_REASON) -> Dictionary:
	if not capture.get("ok", false) or not capture.has_all(["paths", "ids", "writers", "capture_tick"]):
		return {ok = false, reason = "capture handle is malformed"}
	if typeof(reason) != TYPE_STRING or reason.is_empty() or reason.to_utf8_buffer().size() > 160:
		return {ok = false, reason = "capture stop reason is outside the bounded event schema"}
	var failed := ""
	for index in capture.writers.size():
		var writer: Variant = capture.writers[index]
		var stop_error: Error = writer.stop(reason)
		if stop_error != OK or not writer.failure.is_empty():
			failed = "%s writer failed: %s" % [capture.ids[index], writer.failure]
	if not failed.is_empty():
		return {ok = false, reason = failed}
	var made := create_manifest(record, capture.paths)
	if not made.ok:
		return made
	var text := CheckpointJson.encode(made.manifest)
	if text.is_empty() or text.to_utf8_buffer().size() > MAX_CARRIER_BYTES:
		return {ok = false, reason = "decision manifest exceeds the bounded lossless carrier"}
	var manifest_path: String = capture.directory.path_join(CAPTURE_MANIFEST)
	if FileAccess.file_exists(manifest_path):
		return {ok = false, reason = "decision manifest path already exists"}
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		return {ok = false, reason = "cannot create decision manifest"}
	file.store_string(text)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		return {ok = false, reason = "decision manifest write failed"}
	return {ok = true, manifest = made.manifest, manifest_path = manifest_path,
		paths = capture.paths.duplicate(true), checks = made.checks}


## Hash and inspect the complete expected ORFL set without loading its rows into memory.
static func create_manifest(record: Dictionary, paths: Dictionary) -> Dictionary:
	var basic := _record_refusal(record)
	if not basic.is_empty():
		return {ok = false, reason = basic}
	var ids := _record_stream_ids(record)
	if not _path_map_valid(paths, ids):
		return {ok = false, reason = "ORFL stream map is malformed or roster IDs do not match"}
	var entries: Array[Dictionary] = []
	var checks: Array[Dictionary] = []
	var total_bytes := 0
	var common_solver := ""
	var common_engine := ""
	var expected_final: int = record.capture_tick + record.future_player_tape.size()
	for stable_id: String in ids:
		var path: String = paths[stable_id]
		var stream_sha_before: String = FileAccess.get_sha256(path)
		var checked := _inspect_stream(path, stable_id, record.capture_tick, expected_final,
			record.future_player_tape.size() + 1)
		if not checked.ok:
			return checked
		if stream_sha_before.is_empty() or FileAccess.get_sha256(path) != stream_sha_before:
			return {ok = false, reason = "%s ORFL changed during manifest inspection" % stable_id}
		if checked.header.dt_s != record.dt or checked.header.engine != Engine.get_version_info().string:
			return {ok = false, reason = "%s ORFL clock/engine differs from the checkpoint" % stable_id}
		total_bytes += checked.bytes
		if checked.bytes > MAX_STREAM_BYTES or total_bytes > MAX_TOTAL_STREAM_BYTES:
			return {ok = false, reason = "ORFL byte limits are exceeded"}
		var header: Dictionary = checked.header
		if common_engine.is_empty():
			common_engine = str(header.engine)
			common_solver = str(header.solver_sha256)
		elif header.engine != common_engine or header.solver_sha256 != common_solver:
			return {ok = false, reason = "fleet ORFL engine/source identities differ"}
		var expected_checkpoint: Dictionary = _record_checkpoint(record, stable_id)
		if expected_checkpoint.is_empty() or var_to_bytes(header.checkpoint) != var_to_bytes(expected_checkpoint):
			return {ok = false, reason = "%s ORFL start checkpoint differs from the fleet sidecar" % stable_id}
		if stable_id == "player":
			var tape_refusal := _player_tape_refusal(path, record)
			if not tape_refusal.is_empty():
				return {ok = false, reason = tape_refusal}
		var events: Array = checked.info.events
		entries.append({
			"id": stable_id,
			"file": path.get_file(),
			"sha256": stream_sha_before,
			"bytes": checked.bytes,
			"rows": checked.info.rows,
			"first_tick": checked.info.first_tick,
			"final_tick": checked.info.footer.final_tick,
			"event_count": events.size(),
			"event_sha256": _hash(var_to_bytes(events)),
		})
		checks.append({"id": stable_id, "rows": checked.info.rows, "events": events.size(), "bytes": checked.bytes})
	var profile_identity: Dictionary = record.get("profile_identity", {})
	if common_engine != str(record.engine.get("string", "")) \
			or common_solver != str(profile_identity.get("solver_sha256", "")):
		return {ok = false, reason = "ORFL engine/solver identity differs from the fleet checkpoint profile"}
	var manifest := {
		"format": FORMAT,
		"record_sha256": _hash(var_to_bytes(record)),
		"source_hashes": record.source_hashes.duplicate(true),
		"capture_tick": record.capture_tick,
		"final_tick": expected_final,
		"tick_count": record.future_player_tape.size(),
		"physics_hz": record.physics_hz,
		"dt": record.dt,
		"engine": common_engine,
		"solver_sha256": common_solver,
		"roster": ids,
		"streams": entries,
	}
	var encoded := CheckpointJson.encode(manifest)
	if encoded.is_empty() or encoded.to_utf8_buffer().size() > MAX_CARRIER_BYTES:
		return {ok = false, reason = "decision manifest exceeds the bounded lossless carrier"}
	return {ok = true, manifest = manifest, checks = checks}


## Validate current bytes/packets/events against the frozen manifest before restoring a candidate.
static func validate_manifest(manifest: Dictionary, record: Dictionary, paths: Dictionary) -> Dictionary:
	if not _manifest_schema_valid(manifest):
		return {ok = false, reason = "decision manifest schema is malformed"}
	var carrier_text := CheckpointJson.encode(manifest)
	if carrier_text.is_empty() or carrier_text.to_utf8_buffer().size() > MAX_CARRIER_BYTES:
		return {ok = false, reason = "decision manifest exceeds the bounded lossless carrier"}
	var basic := _record_refusal(record)
	if not basic.is_empty():
		return {ok = false, reason = basic}
	var ids := _record_stream_ids(record)
	if not _path_map_valid(paths, ids) or manifest.roster != ids:
		return {ok = false, reason = "decision manifest roster or stream map differs"}
	if manifest.record_sha256 != _hash(var_to_bytes(record)) or manifest.source_hashes != record.source_hashes \
			or manifest.capture_tick != record.capture_tick \
			or manifest.tick_count != record.future_player_tape.size() \
			or manifest.final_tick != record.capture_tick + record.future_player_tape.size() \
			or manifest.physics_hz != record.physics_hz or manifest.dt != record.dt \
			or manifest.engine != str(record.engine.get("string", "")) \
			or manifest.engine != Engine.get_version_info().string \
			or manifest.solver_sha256 != str(record.profile_identity.get("solver_sha256", "")):
		return {ok = false, reason = "decision manifest is not bound to this fleet checkpoint"}
	var total_bytes := 0
	var checks: Array[Dictionary] = []
	for index in ids.size():
		var stable_id: String = ids[index]
		var entry: Dictionary = manifest.streams[index]
		var path: String = paths[stable_id]
		if entry.id != stable_id or entry.file != path.get_file():
			return {ok = false, reason = "%s ORFL filename/identity differs" % stable_id}
		var actual_bytes: int = _file_size(path)
		if actual_bytes < 1 or actual_bytes > MAX_STREAM_BYTES:
			return {ok = false, reason = "%s ORFL file size is outside bounds" % stable_id}
		total_bytes += actual_bytes
		if total_bytes > MAX_TOTAL_STREAM_BYTES or actual_bytes != entry.bytes \
				or FileAccess.get_sha256(path) != entry.sha256:
			return {ok = false, reason = "%s ORFL bytes changed after manifest creation" % stable_id}
		var checked := _inspect_stream(path, stable_id, record.capture_tick, manifest.final_tick,
			record.future_player_tape.size() + 1)
		if not checked.ok:
			return checked
		if checked.header.dt_s != record.dt:
			return {ok = false, reason = "%s ORFL timestep differs from the checkpoint" % stable_id}
		var events: Array = checked.info.events
		if checked.info.rows != entry.rows or events.size() != entry.event_count \
				or _hash(var_to_bytes(events)) != entry.event_sha256:
			return {ok = false, reason = "%s ORFL rows/events differ from the frozen manifest" % stable_id}
		if checked.header.engine != manifest.engine or checked.header.solver_sha256 != manifest.solver_sha256:
			return {ok = false, reason = "%s ORFL engine/source identity differs" % stable_id}
		var expected_checkpoint: Dictionary = _record_checkpoint(record, stable_id)
		if expected_checkpoint.is_empty() or var_to_bytes(checked.header.checkpoint) != var_to_bytes(expected_checkpoint):
			return {ok = false, reason = "%s ORFL start checkpoint differs from the fleet sidecar" % stable_id}
		if stable_id == "player":
			var tape_refusal := _player_tape_refusal(path, record)
			if not tape_refusal.is_empty():
				return {ok = false, reason = tape_refusal}
		if _file_size(path) != entry.bytes or FileAccess.get_sha256(path) != entry.sha256:
			return {ok = false, reason = "%s ORFL changed during manifest preflight" % stable_id}
		checks.append({"id": stable_id, "rows": checked.info.rows, "events": events.size(), "bytes": actual_bytes})
	return {ok = true, checks = checks}


## Validate first, stage/restore a fresh detached fleet, explicitly unpause it offline, then replay
## from the player's recorded ORFL rows while Manager recomputes companion decisions.
static func restore_and_replay(fixture: Dictionary, expected_paths: Dictionary, manifest: Dictionary,
		record: Dictionary, field: Dictionary, world: Dictionary, source_hashes: Dictionary,
		destination: String) -> Dictionary:
	var verified := validate_manifest(manifest, record, expected_paths)
	if not verified.ok:
		return verified
	var record_check := Candidate.validate_record(record, fixture, field, world, source_hashes,
		record.future_player_tape.size())
	if not record_check.ok:
		return record_check
	var output_directory := _validate_new_directory(destination)
	if not output_directory.ok:
		return output_directory
	var restored := Candidate.restore_disposable_candidate(fixture, record, field, world,
		source_hashes, record.future_player_tape.size())
	if not restored.ok:
		return restored
	var unpaused := _unpause_offline(fixture)
	if not unpaused:
		return {ok = false, reason = "detached restored fleet failed explicit offline-unpause preflight"}
	var capture := start_capture(fixture, record, output_directory.path)
	if not capture.ok:
		return capture
	var expected_reader := OrflCursor.new()
	var opened := expected_reader.open(str(expected_paths.player))
	if not opened.ok:
		_stop_capture(capture, "expected player stream refused")
		return opened
	var first := expected_reader.next_sample()
	if not first.ok or first.row.tick != record.capture_tick:
		expected_reader.close()
		_stop_capture(capture, "expected initial player sample refused")
		return {ok = false, reason = "expected player stream has no matching initial sample"}
	var physical: Array[PackedByteArray] = []
	var commands: Array[PackedByteArray] = []
	var failure := ""
	for offset in record.future_player_tape.size():
		var next := expected_reader.next_sample()
		if not next.ok:
			failure = "expected player stream ended at future tick %d" % offset
			break
		var row: Dictionary = next.row
		var packet: Dictionary = record.future_player_tape[offset]
		if not _row_matches_recorded_control(row, packet):
			failure = "player ORFL controls differ from checkpoint tape at tick %d" % row.tick
			break
		var staged := _stage_player_row(fixture.player, row)
		if not staged.ok or not fixture.player._session_after_input():
			failure = "player replay input/session guard refused tick %d" % row.tick
			break
		fixture.player.sim.step()
		if fixture.player.sim.tick != row.tick or not fixture.player.sim.fault_reason.is_empty() \
				or not _healthy_aligned(fixture, row.tick):
			failure = "fleet stopped at non-healthy common tick %d" % row.tick
			break
		physical.append(var_to_bytes(_physical_frame(fixture)))
		commands.append(var_to_bytes(_command_frame(fixture, source_hashes)))
	var end_row := expected_reader.next_sample()
	if failure.is_empty() and end_row.ok:
		failure = "expected player stream contains rows beyond the bounded checkpoint interval"
	expected_reader.close()
	if failure.is_empty():
		var stable_sources := Candidate._source_manifest_is_current(source_hashes)
		var stable_streams := validate_manifest(manifest, record, expected_paths)
		if not stable_sources:
			failure = "source/data identity changed during decision replay"
		elif not stable_streams.ok:
			failure = str(stable_streams.get("reason", "expected ORFL changed during decision replay"))
	var finish := finish_capture(capture, record, STOP_REASON)
	if not finish.ok and failure.is_empty():
		failure = str(finish.get("reason", "candidate capture failed"))
	if not failure.is_empty():
		return {ok = false, reason = failure, physical = physical, commands = commands,
			capture = finish}
	var compared := compare_stream_sets(expected_paths, finish.paths, finish.manifest, record)
	if not compared.ok:
		return {ok = false, reason = compared.reason, physical = physical, commands = commands,
			capture = finish, comparison = compared}
	return {ok = true, physical = physical, commands = commands, capture = finish,
		comparison = compared, unpaused = true}


## Compare complete ORFL streams field-by-field, including controls, interventions, and every retained event.
static func compare_stream_sets(expected_paths: Dictionary, actual_paths: Dictionary,
	manifest: Dictionary, record: Dictionary) -> Dictionary:
	var expected_check := validate_manifest(manifest, record, expected_paths)
	if not expected_check.ok:
		return expected_check
	var actual_check := create_manifest(record, actual_paths)
	if not actual_check.ok:
		return actual_check
	var stream_rows := 0
	for stable_id: String in _record_stream_ids(record):
		var left := OrflCursor.new()
		var right := OrflCursor.new()
		var open_left := left.open(str(expected_paths[stable_id]))
		var open_right := right.open(str(actual_paths[stable_id]))
		if not open_left.ok or not open_right.ok:
			left.close()
			right.close()
			return {ok = false, reason = "%s ORFL stream could not be reopened" % stable_id}
		var rows_for_stream := 0
		while true:
			var expected := left.next_sample()
			var actual := right.next_sample()
			if not expected.ok or not actual.ok:
				if expected.ok != actual.ok:
					left.close()
					right.close()
					return {ok = false, reason = "%s ORFL row counts differ" % stable_id}
				break
			var why := row_disagreement(expected.row, actual.row)
			if not why.is_empty():
				left.close()
				right.close()
				return {ok = false, reason = "%s %s" % [stable_id, why]}
			rows_for_stream += 1
		left.close()
		right.close()
		var left_info := Reader.inspect(str(expected_paths[stable_id]), false)
		var right_info := Reader.inspect(str(actual_paths[stable_id]), false)
		if not left_info.ok or not right_info.ok \
				or not _headers_equivalent(left_info.header, right_info.header) \
				or not _footers_equivalent(left_info.footer, right_info.footer):
			return {ok = false, reason = "%s ORFL header/footer fields differ" % stable_id}
		if not left_info.ok or not right_info.ok or not _events_equal(left_info.events, right_info.events):
			return {ok = false, reason = "%s ORFL event streams differ" % stable_id}
		if left_info.events_omitted != 0 or right_info.events_omitted != 0:
			return {ok = false, reason = "%s event comparison exceeded the retained event bound" % stable_id}
		stream_rows += rows_for_stream
	var stable_expected := validate_manifest(manifest, record, expected_paths)
	var stable_actual := create_manifest(record, actual_paths)
	if not stable_expected.ok or not stable_actual.ok:
		return {ok = false, reason = "ORFL stream changed during complete row/event comparison"}
	return {ok = true, streams = _record_stream_ids(record).size(), rows_compared = stream_rows,
		per_stream_rows = record.future_player_tape.size() + 1,
		events_compared = true,
		comparison_exclusions = ["header.created_utc", "header.metadata launch provenance (restore replaces it with unknown)",
			"footer.chain_sha256 (header timestamp participates)", "footer.observer_usec", "footer.peak_buffer_rows"]}


static func row_disagreement(expected: Dictionary, actual: Dictionary) -> String:
	if not _sample_schema_valid(expected) or not _sample_schema_valid(actual):
		return "has a sample with unknown/malformed recorded fields"
	if expected.tick != actual.tick or expected.kind != actual.kind:
		return "sample identity differs at tick %d" % expected.tick
	var physical := Reader.disagreement(expected, actual)
	if not physical.is_empty():
		return physical
	for key: String in ["raw", "sticks"]:
		if expected[key].to_byte_array() != actual[key].to_byte_array():
			return "first ORFL divergence at tick %d in %s" % [expected.tick, key]
	if var_to_bytes(expected.intervention) != var_to_bytes(actual.intervention):
		return "first ORFL divergence at tick %d in intervention" % expected.tick
	return ""


static func _inspect_stream(path: String, stable_id: String, first_tick: int,
	final_tick: int, expected_rows: int) -> Dictionary:
	if typeof(path) != TYPE_STRING or path.is_empty() or path.length() > 4096 \
			or not FileAccess.file_exists(path):
		return {ok = false, reason = "%s ORFL path is missing or outside the path bound" % stable_id}
	var bytes := _file_size(path)
	if bytes <= 0 or bytes > MAX_STREAM_BYTES:
		return {ok = false, reason = "%s ORFL exceeds the per-stream byte bound" % stable_id}
	var info := Reader.inspect(path, false)
	if not info.get("ok", false) or not info.get("complete", false):
		return {ok = false, reason = "%s ORFL is incomplete or invalid: %s" % [stable_id, info.get("error", "incomplete") ]}
	if info.get("events_omitted", 0) != 0 or not info.get("events") is Array \
			or info.events.size() > MAX_EVENTS:
		return {ok = false, reason = "%s ORFL event stream exceeds the comparison bound" % stable_id}
	if info.rows != expected_rows or info.rows < 2 or info.rows > MAX_REPLAY_ROWS \
			or info.first_tick != first_tick or info.footer.final_tick != final_tick:
		return {ok = false, reason = "%s ORFL tick extent/row count differs from the checkpoint interval" % stable_id}
	var header: Dictionary = info.header
	if header.checkpoint.simulation.tick != first_tick:
		return {ok = false, reason = "%s ORFL header checkpoint tick differs" % stable_id}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {ok = false, reason = "%s ORFL cannot be opened for strict sample validation" % stable_id}
	file.seek(8)
	var header_packet := Log.read_packet(file)
	var malformed: bool = not header_packet.ok
	while not malformed and file.get_position() < file.get_length():
		var packet := Log.read_packet(file)
		if not packet.ok:
			malformed = true
			break
		if packet.value.get("kind") == "footer":
			break
		for row: Variant in packet.value.get("rows", []):
			if not _sample_schema_valid(row):
				malformed = true
				break
		for event: Variant in packet.value.get("events", []):
			if not event is Dictionary or not Candidate.exact_keys(event, EVENT_KEYS) \
					or typeof(event.tick) != TYPE_INT or typeof(event.kind) != TYPE_STRING \
					or typeof(event.detail) != TYPE_STRING:
				malformed = true
				break
		if malformed:
			break
	file.close()
	if malformed:
		return {ok = false, reason = "%s ORFL contains a sample/event outside the exact replay schema" % stable_id}
	return {ok = true, info = info, header = header, bytes = bytes}


static func _sample_schema_valid(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var expected := SAMPLE_MASS_KEYS if value.has("mass") else SAMPLE_KEYS
	if not Candidate.exact_keys(value, expected):
		return false
	if value.get("kind") != "sample" or typeof(value.get("tick")) != TYPE_INT:
		return false
	for key: String in ["state", "inputs", "aux", "continuous", "modes", "loads", "raw", "sticks", "air"]:
		if not value.has(key):
			return false
	if not value.intervention is Dictionary:
		return false
	return true


static func _manifest_schema_valid(value: Dictionary) -> bool:
	if not Candidate.exact_keys(value, ["format", "record_sha256", "source_hashes", "capture_tick",
		"final_tick", "tick_count", "physics_hz", "dt", "engine", "solver_sha256", "roster", "streams"]):
		return false
	if value.get("format") != FORMAT or typeof(value.get("record_sha256")) != TYPE_STRING \
			or value.record_sha256.length() != 64 or not value.get("source_hashes") is Dictionary \
			or typeof(value.get("capture_tick")) != TYPE_INT or value.capture_tick < 1 \
			or typeof(value.get("final_tick")) != TYPE_INT or value.final_tick <= value.capture_tick \
			or typeof(value.get("tick_count")) != TYPE_INT or value.tick_count < 1 \
			or value.tick_count > Candidate.MAX_FUTURE_TICKS \
			or value.final_tick != value.capture_tick + value.tick_count \
			or typeof(value.get("physics_hz")) != TYPE_INT or value.physics_hz != 240 \
			or typeof(value.get("dt")) != TYPE_FLOAT or value.dt != 1.0 / 240.0 \
			or typeof(value.get("engine")) != TYPE_STRING or typeof(value.get("solver_sha256")) != TYPE_STRING \
			or not value.get("roster") is Array or not value.get("streams") is Array:
		return false
	if value.roster.is_empty() or value.roster.size() > MAX_STREAMS \
			or value.streams.size() != value.roster.size():
		return false
	for index in value.streams.size():
		var stream: Variant = value.streams[index]
		if not stream is Dictionary or not Candidate.exact_keys(stream,
			["id", "file", "sha256", "bytes", "rows", "first_tick", "final_tick", "event_count", "event_sha256"]):
			return false
		if typeof(stream.id) != TYPE_STRING or typeof(stream.file) != TYPE_STRING \
				or typeof(stream.sha256) != TYPE_STRING or stream.sha256.length() != 64 \
				or typeof(stream.bytes) != TYPE_INT or stream.bytes <= 0 or stream.bytes > MAX_STREAM_BYTES \
				or typeof(stream.rows) != TYPE_INT or stream.rows < 2 or stream.rows > MAX_REPLAY_ROWS \
				or typeof(stream.first_tick) != TYPE_INT or stream.first_tick != value.capture_tick \
				or typeof(stream.final_tick) != TYPE_INT or stream.final_tick != value.final_tick \
				or typeof(stream.event_count) != TYPE_INT or stream.event_count < 0 or stream.event_count > MAX_EVENTS \
				or typeof(stream.event_sha256) != TYPE_STRING or stream.event_sha256.length() != 64:
			return false
	return true


static func _record_refusal(record: Dictionary) -> String:
	if record.get("format") != Candidate.RECORD_FORMAT or record.get("scope") != Candidate.SCOPE \
			or typeof(record.get("capture_tick")) != TYPE_INT \
			or record.capture_tick < 1 or typeof(record.get("future_player_tape")) != TYPE_ARRAY \
			or record.future_player_tape.is_empty() or record.future_player_tape.size() > Candidate.MAX_FUTURE_TICKS \
			or typeof(record.get("source_hashes")) != TYPE_DICTIONARY \
			or typeof(record.get("physics_hz")) != TYPE_INT or record.physics_hz != 240 \
			or typeof(record.get("dt")) != TYPE_FLOAT or record.dt != 1.0 / 240.0 \
			or typeof(record.get("engine")) != TYPE_DICTIONARY or typeof(record.get("profile_identity")) != TYPE_DICTIONARY \
			or typeof(record.get("player")) != TYPE_DICTIONARY or typeof(record.get("roster")) != TYPE_ARRAY:
		return "fleet checkpoint is not a bounded nonzero-tick fixed-roster record"
	if record.capture_tick + record.future_player_tape.size() > 9007199254740991:
		return "fleet replay tick extent exceeds exact integer range"
	for packet: Variant in record.future_player_tape:
		if not Candidate.packet_valid(packet):
			return "fleet checkpoint contains an invalid future player control packet"
	return ""


static func _record_stream_ids(record: Dictionary) -> Array[String]:
	var ids: Array[String] = ["player"]
	if not record.get("roster") is Array or record.roster.is_empty() or record.roster.size() + 1 > MAX_STREAMS:
		return []
	for value: Variant in record.roster:
		if not value is Dictionary or typeof(value.get("stable_id")) != TYPE_STRING:
			return []
		ids.append(value.stable_id)
	if ids != ["player", "companion-0", "companion-1"]:
		return []
	return ids


static func _record_checkpoint(record: Dictionary, stable_id: String) -> Dictionary:
	if stable_id == "player":
		return record.player.get("session_checkpoint", {}) if record.get("player") is Dictionary else {}
	for agent: Variant in record.get("roster", []):
		if agent is Dictionary and agent.get("stable_id") == stable_id:
			return agent.get("session_checkpoint", {})
	return {}


static func _path_map_valid(paths: Dictionary, ids: Array[String]) -> bool:
	if ids.is_empty() or paths.size() != ids.size():
		return false
	for stable_id: String in ids:
		if not paths.has(stable_id) or typeof(paths[stable_id]) != TYPE_STRING \
				or str(paths[stable_id]).is_empty() or str(paths[stable_id]).length() > 4096:
			return false
	for key: Variant in paths:
		if typeof(key) != TYPE_STRING or not ids.has(str(key)):
			return false
	return true


static func _fixture_refusal(fixture: Dictionary, record: Dictionary) -> String:
	var basic := _record_refusal(record)
	if not basic.is_empty():
		return basic
	if not fixture.has_all(["player", "manager"]) or not fixture.player is Node or not fixture.manager is Node:
		return "capture fixture is incomplete"
	if fixture.player.sim.tick != record.capture_tick or fixture.manager._player != fixture.player \
			or fixture.manager.agents.size() + 1 > MAX_STREAMS or fixture.manager.agents.size() != record.roster.size():
		return "capture fixture and checkpoint roster are not aligned at the recorded tick"
	if fixture.manager.accepted_ticks != record.capture_tick or fixture.manager._snapshot_tick != -1 \
			or fixture.manager._removed or fixture.manager._damage_dirty:
		return "capture manager has a stale clock, removal, or pending shared-world change"
	if fixture.player.sim.paused or fixture.player.sim.fault_reason != "" or not fixture.player.crash.is_empty():
		return "capture player is paused or unhealthy"
	for index in fixture.manager.agents.size():
		var agent: Node = fixture.manager.agents[index]
		if agent.session.sim.tick != record.capture_tick or agent.failure != "" \
				or not agent.session.crash.is_empty() or not agent.session.sim.fault_reason.is_empty():
			return "capture companion %d is not a healthy common-tick member" % index
	return ""


static func _new_directory(destination: String) -> Dictionary:
	var valid := _validate_new_directory(destination)
	if not valid.ok:
		return valid
	var created := DirAccess.make_dir_absolute(valid.path)
	if created != OK:
		return {ok = false, reason = "capture directory reservation failed"}
	return valid


static func _validate_new_directory(destination: String) -> Dictionary:
	if typeof(destination) != TYPE_STRING or destination.strip_edges().is_empty() or destination.length() > 4096:
		return {ok = false, reason = "capture destination is outside the path bound"}
	var absolute: String = ProjectSettings.globalize_path(destination).simplify_path()
	if not absolute.is_absolute_path() or DirAccess.dir_exists_absolute(absolute) or FileAccess.file_exists(absolute):
		return {ok = false, reason = "capture destination must be a new absolute directory"}
	var parent_error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if parent_error != OK:
		return {ok = false, reason = "capture parent directory could not be created"}
	return {ok = true, path = absolute}


static func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	var size: int = file.get_length()
	file.close()
	return size


static func _stop_capture(capture: Dictionary, reason: String) -> void:
	for writer: Variant in capture.get("writers", []):
		if writer.recording:
			writer.stop(reason)


static func _unpause_offline(fixture: Dictionary) -> bool:
	var sessions: Array[Node] = [fixture.player]
	for agent: Node in fixture.manager.agents:
		sessions.append(agent.session)
	for session: Node in sessions:
		if not session.sim.paused or session.input_enabled or not session.holds.is_empty():
			return false
	for session: Node in sessions:
		session.pause_reason = ""
		session.sim.set_paused(false)
	for session: Node in sessions:
		if session.sim.paused:
			return false
	return true


static func _row_matches_recorded_control(row: Dictionary, packet: Dictionary) -> bool:
	if not _sample_schema_valid(row) or row.raw.size() != 4 or row.sticks.size() != 4:
		return false
	for index in AXES.size():
		var key: String = AXES[index]
		if typeof(packet.get(key)) not in [TYPE_INT, TYPE_FLOAT] \
				or row.raw[index] != float(packet[key]) or row.sticks[index] != float(packet[key]):
			return false
	return true


static func _player_tape_refusal(path: String, record: Dictionary) -> String:
	var cursor := OrflCursor.new()
	var opened := cursor.open(path)
	if not opened.ok:
		return "player ORFL could not be opened for tape binding"
	var initial := cursor.next_sample()
	if not initial.ok or initial.row.tick != record.capture_tick:
		cursor.close()
		return "player ORFL has no initial checkpoint sample"
	for offset in record.future_player_tape.size():
		var next := cursor.next_sample()
		if not next.ok or not _row_matches_recorded_control(next.row, record.future_player_tape[offset]):
			cursor.close()
			return "player ORFL controls differ from checkpoint tape at future tick %d" % offset
	var extra := cursor.next_sample()
	cursor.close()
	if extra.ok:
		return "player ORFL contains rows beyond checkpoint tape"
	return ""


static func _stage_player_row(player: Node, row: Dictionary) -> Dictionary:
	if not _sample_schema_valid(row) or row.tick != player.sim.tick + 1 \
			or row.inputs.size() != player.sim.inputs.size():
		return {ok = false, reason = "player row tick/input schema differs"}
	for key: String in row.intervention:
		if key not in ["state", "previous", "aux", "continuous", "modes"]:
			return {ok = false, reason = "player row contains unsupported simulation intervention"}
		player.sim.set(key, row.intervention[key].duplicate())
	player.raw = _controls_dictionary(row.raw)
	player.commands = _controls_dictionary(row.sticks)
	player.sim.inputs = row.inputs.duplicate()
	if player.gear_is_retractable():
		player._gear_requested_down = row.inputs[4] == 1.0
		player._wheel_brake_demand = row.inputs[5]
	if player.flaps_available():
		player._flap_requested = row.inputs[player.flap_input_index()]
	return {ok = true}


static func _controls_dictionary(values: PackedFloat64Array) -> Dictionary:
	return {"roll": values[0], "pitch": values[1], "yaw": values[2], "throttle": values[3]}


static func _healthy_aligned(fixture: Dictionary, tick: int) -> bool:
	if fixture.player.sim.tick != tick or fixture.manager.accepted_ticks != tick \
			or fixture.manager._snapshot_tick != -1 or fixture.manager._removed \
			or fixture.manager.agents.size() != Candidate.COMPANION_COUNT:
		return false
	for index in fixture.manager.agents.size():
		var agent: Node = fixture.manager.agents[index]
		if agent.session.sim.tick != tick or not agent.failure.is_empty() \
				or not agent.session.crash.is_empty() or not agent.session.sim.fault_reason.is_empty():
			return false
	return true


static func _physical_frame(fixture: Dictionary) -> Array:
	var sessions: Array[Node] = [fixture.player]
	for agent: Node in fixture.manager.agents:
		sessions.append(agent.session)
	var frame: Array = []
	for session: Node in sessions:
		frame.append([session.sim.tick, session.sim.state, session.sim.previous, session.sim.aux,
			session.sim.inputs, session.sim.continuous, session.sim.modes, session.sim.last_loads,
			session.contact_events(), session.scenery_damage()])
	return frame


static func _command_frame(fixture: Dictionary, source_hashes: Dictionary) -> Array:
	var frame: Array = []
	frame.append([fixture.player.commands, fixture.player.raw, fixture.player.trims, fixture.player.sim.inputs,
		fixture.player._gear_requested_down, fixture.player._wheel_brake_demand, fixture.player._flap_requested])
	for agent: Node in fixture.manager.agents:
		frame.append([agent.slot_id, agent.failure, agent._last_command, agent._accepted_trim,
			agent._weather_rms, agent.session.commands, agent.session.raw, agent.session.trims,
			agent.session.sim.inputs, Candidate.controller_state(agent, source_hashes)])
	frame.append([fixture.manager.accepted_ticks, fixture.manager.observation_batches,
		fixture.manager._snapshot_tick, fixture.manager._damage_dirty])
	return frame


static func _events_equal(left: Array, right: Array) -> bool:
	if left.size() != right.size() or left.size() > MAX_EVENTS or right.size() > MAX_EVENTS:
		return false
	for index in left.size():
		if not left[index] is Dictionary or not right[index] is Dictionary \
				or not Candidate.exact_keys(left[index], EVENT_KEYS) or not Candidate.exact_keys(right[index], EVENT_KEYS) \
				or var_to_bytes(left[index]) != var_to_bytes(right[index]):
			return false
	return true


static func _headers_equivalent(left: Dictionary, right: Dictionary) -> bool:
	var expected := left.duplicate(true)
	var actual := right.duplicate(true)
	# Capture wall-clock time is intentionally not part of deterministic simulation identity.
	expected.erase("created_utc")
	actual.erase("created_utc")
	var expected_metadata: Dictionary = expected.get("metadata", {}).duplicate(true)
	var actual_metadata: Dictionary = actual.get("metadata", {}).duplicate(true)
	# FlightSession deliberately clears source-launch provenance on restore; physical profile data still compares.
	for key: String in ["scenario", "selected_start_choice", "launch_choice", "launch_kind", "launch_field_id",
		"launch_trim_throttle", "launch_state", "launch_aux", "launch_ground_anchors",
		"launch_engine_running", "launch_error"]:
		expected_metadata.erase(key)
		actual_metadata.erase(key)
	expected.metadata = expected_metadata
	actual.metadata = actual_metadata
	return var_to_bytes(expected) == var_to_bytes(actual)


static func _footers_equivalent(left: Dictionary, right: Dictionary) -> bool:
	var expected := left.duplicate(true)
	var actual := right.duplicate(true)
	# Packet-chain hashes include the differing header timestamp. Observer cost and buffer peaks are measurements.
	for key: String in ["chain_sha256", "observer_usec", "peak_buffer_rows"]:
		expected.erase(key)
		actual.erase(key)
	return var_to_bytes(expected) == var_to_bytes(actual)


static func _hash(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()


class OrflCursor extends RefCounted:
	var file: FileAccess
	var block_rows: Array = []
	var row_index := 0
	var finished := false

	func open(path: String) -> Dictionary:
		close()
		file = FileAccess.open(path, FileAccess.READ)
		if file == null:
			return {ok = false, reason = "ORFL cursor cannot open stream"}
		file.seek(8)
		var header := Log.read_packet(file)
		if not header.ok or header.value.get("kind") != "header":
			close()
			return {ok = false, reason = "ORFL cursor found no valid header"}
		return {ok = true, header = header.value}

	func next_sample() -> Dictionary:
		if file == null or finished:
			return {ok = false, reason = "ORFL cursor is exhausted"}
		while row_index >= block_rows.size():
			var packet := Log.read_packet(file)
			if not packet.ok:
				finished = true
				return {ok = false, reason = packet.get("error", "ORFL packet refused")}
			if packet.value.get("kind") == "footer":
				finished = true
				return {ok = false, reason = "ORFL footer reached"}
			if packet.value.get("kind") != "block" or not packet.value.get("rows") is Array:
				finished = true
				return {ok = false, reason = "ORFL block schema refused"}
			block_rows = packet.value.rows
			row_index = 0
			if block_rows.is_empty():
				continue
		var row: Variant = block_rows[row_index]
		row_index += 1
		return {ok = true, row = row}

	func close() -> void:
		if file != null:
			file.close()
		file = null
		block_rows.clear()
		row_index = 0
		finished = false

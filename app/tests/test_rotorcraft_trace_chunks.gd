extends SceneTree

const Recorder := preload("res://sim/rotorcraft_recorder.gd")
const Store := preload("res://sim/trace_chunk_store.gd")
const Publisher := preload("res://sim/manual_trace_save.gd")

class CollisionProxy extends RefCounted:
	var trace: RefCounted
	func _init(value: RefCounted) -> void: trace = value
	func save(path: String) -> Error:
		var error: Error = trace.save(path)
		if error != OK: return error
		var occupied := FileAccess.open(path.get_base_dir().path_join("helicopter.csv"), FileAccess.WRITE)
		if occupied == null: return FileAccess.get_open_error()
		occupied.store_string("occupied")
		occupied.close()
		return OK

class TestRecorder extends "res://sim/rotorcraft_recorder.gd":
	var output_dir := ""
	var collide := false
	func _save_automatic() -> Dictionary:
		return Publisher.save(CollisionProxy.new(trace) if collide else trace, "helicopter", output_dir, "fixture")

class Simulation extends Node:
	signal stepped(tick: int, time_s: float, state: PackedFloat64Array, loads: PackedFloat64Array, inputs: PackedFloat64Array, aux: PackedFloat64Array)
	var tick := 0
	var state := PackedFloat64Array([0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0])
	var last_loads := PackedFloat64Array([0, 0, 0, 0, 0, 0])
	var inputs := PackedFloat64Array([0, 0, 0, 0])
	var aux := PackedFloat64Array()
	var continuous := PackedFloat64Array([0, 0, 0, 0, 0, 0])
	func dt() -> float: return 1.0 / 240.0
	func time() -> float: return tick * dt()
	func step() -> void:
		tick += 1
		state[0] = tick * 0.125
		continuous[0] = tick * 0.25
		stepped.emit(tick, time(), state, last_loads, inputs, aux)

class Gate extends RefCounted:
	var entered := Semaphore.new()
	var release := Semaphore.new()
	func phase(name: String, index: int) -> Error:
		if name == "before_write" and index == 0:
			entered.post()
			release.wait()
		return OK

class FailingWriter extends RefCounted:
	var entered := Semaphore.new()
	var release := Semaphore.new()
	var blocked := true
	var fail := true
	func phase(name: String, index: int) -> Error:
		if name == "before_write" and index == 0:
			if blocked:
				blocked = false
				entered.post()
				release.wait()
			if fail: return ERR_FILE_CANT_WRITE
		return OK

class CleanupFailure extends RefCounted:
	func phase(name: String, _index: int) -> Error:
		return ERR_FILE_CANT_WRITE if name == "discard_before_cleanup" else OK

var checks := 0
var failures := 0
var folder := ""

func check(label: String, condition: bool) -> void:
	checks += 1
	print(("ok   " if condition else "FAIL ") + label)
	if not condition: failures += 1

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var base := OS.get_environment("OPENRC_HELI_TEST_OUT")
	if base.is_empty(): base = "user://rotorcraft-trace-tests"
	folder = base.path_join("run-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	check("create isolated output", DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)) == OK)
	_test_exact_rows_and_csv()
	_test_large_csv_batch()
	_test_backpressure_and_retry()
	_test_async_write_failure()
	_test_unavailable_spool_root()
	_test_cleanup_warning()
	_test_malformed_latch()
	print("Rotorcraft trace chunks: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func _append(trace: RefCounted, tick: int) -> bool:
	var dt := 1.0 / 240.0
	var body := PackedFloat64Array()
	for i in 13: body.append((tick - i * 0.125) / 7.0)
	var loads := PackedFloat64Array([tick * 0.3, -0.0, 1.0e-120, 1.0e120, 3.141592653589793, -1.0])
	var inputs := PackedFloat64Array([tick * 0.001, -0.25, 0.125, 0.75])
	var continuous := PackedFloat64Array([tick * 0.1, 0.2, -0.3, 0.4, -0.5, 0.6])
	if tick % 2 == 0: continuous.append_array(PackedFloat64Array([1, -2, 3, -4, 5, -6, 7, -8]))
	return trace.record(tick, tick * dt, body, loads, inputs, continuous, dt, PackedFloat64Array([1, 0, 1, 0.5, -0.0, 4.0]))

func _test_exact_rows_and_csv() -> void:
	var baseline := Recorder.FlightRows.new()
	var chunked := Recorder.FlightRows.new()
	var metadata := {"zeta": [1, 2], "alpha": "round-trip", "dt_s": 1.0 / 240.0}
	baseline.meta = metadata.duplicate(true)
	chunked.meta = metadata.duplicate(true)
	check("small chunk configuration", chunked.enable_chunk_storage(folder.path_join("exact"), 2) == OK)
	var accepted := true
	for tick in 17:
		accepted = _append(baseline, tick) and _append(chunked, tick) and accepted
		if chunked._store != null:
			accepted = chunked._store.drain() == OK and accepted
	check("seventeen rows accepted through eight boundaries", accepted and baseline.row_count() == 17 and chunked.row_count() == 17 and chunked._store.row_count() == 16 and chunked._tail.size() == Recorder.FlightRows.COLUMNS.size())
	var same := true
	for index in 17:
		same = same and baseline.row(index).to_byte_array() == chunked.row(index).to_byte_array()
	check("every logical row retains exact float64 bits and order", same)
	check("explicit rows compatibility materializes complete history", baseline.rows.to_byte_array() == chunked.rows.to_byte_array() and int(chunked.row(0)[0]) == 0 and int(chunked.row(16)[0]) == 16)
	check("tail and read cache remain within one chunk each", chunked._tail.size() <= 2 * Recorder.FlightRows.COLUMNS.size() and chunked._store._cached_values.size() <= 2 * Recorder.FlightRows.COLUMNS.size())
	var baseline_path := folder.path_join("baseline.csv")
	var chunked_path := folder.path_join("chunked.csv")
	check("baseline and chunked CSV save", baseline.save(baseline_path) == OK and chunked.save(chunked_path) == OK)
	check("CSV metadata, precision, columns and rows are byte-identical", FileAccess.get_file_as_bytes(baseline_path) == FileAccess.get_file_as_bytes(chunked_path))
	var spool_dir: String = chunked.recovery_directory()
	var first := spool_dir.path_join("chunk-0000000000000000.bin")
	var original := FileAccess.get_file_as_bytes(first)
	var alias := spool_dir + "/../" + spool_dir.get_file() + "/chunk-0000000000000000.bin"
	if OS.has_feature("windows"): alias = alias.to_upper().replace("/", "\\")
	check("spool directory, destination and dot-dot alias are rejected before truncation", chunked.save(spool_dir) == ERR_INVALID_PARAMETER and chunked.save(first) == ERR_INVALID_PARAMETER and chunked.save(alias) == ERR_INVALID_PARAMETER and FileAccess.get_file_as_bytes(first) == original and chunked.rows.to_byte_array() == baseline.rows.to_byte_array())
	var sibling := spool_dir + "-external.csv"
	check("adjacent path with a shared prefix remains a valid destination", chunked.save(sibling) == OK and FileAccess.get_file_as_bytes(sibling) == FileAccess.get_file_as_bytes(baseline_path))
	var damaged := FileAccess.open(first, FileAccess.WRITE)
	damaged.store_string("corrupt")
	damaged.close()
	chunked._store._cached_index = -1
	var failed_output := folder.path_join("damaged.csv")
	check("read failure removes partial output and is exposed", chunked.save(failed_output) != OK and chunked.read_error() != OK and not FileAccess.file_exists(failed_output))
	var repaired := FileAccess.open(first, FileAccess.WRITE)
	repaired.store_buffer(original)
	repaired.close()
	check("restored chunk can be retried without changing rows", chunked.save(failed_output) == OK and FileAccess.get_file_as_bytes(failed_output) == FileAccess.get_file_as_bytes(baseline_path))
	check("explicit clear removes owned spool", chunked.clear() == OK and not DirAccess.dir_exists_absolute(spool_dir) and chunked.row_count() == 0)
	var limit := Recorder.FlightRows.new()
	check("default limit fits one MiB", limit.enable_chunk_storage(folder.path_join("limit")) == OK and limit._chunk_rows == int(1048576 / (Recorder.FlightRows.COLUMNS.size() * 8)) and limit._chunk_rows <= 4096)
	limit.clear()

func _test_large_csv_batch() -> void:
	var trace := Recorder.FlightRows.new()
	trace.meta = {"dt_s": 1.0 / 240.0}
	var accepted := true
	for tick in 200: accepted = _append(trace, tick) and accepted
	var output := folder.path_join("large.csv")
	var saved: bool = trace.save(output) == OK
	var contents := FileAccess.get_file_as_string(output)
	var lines := contents.split("\n", false)
	var first_row := 0
	while first_row < lines.size() and lines[first_row].begins_with("# "): first_row += 1
	first_row += 1 # column header
	var exact: bool = accepted and saved and contents.length() > 65536 and lines.size() - first_row == 200
	if exact:
		for index in 200:
			var fields := lines[first_row + index].split(",")
			var expected: PackedFloat64Array = trace.row(index)
			if fields.size() != expected.size():
				exact = false
				break
			for column in fields.size():
				if fields[column] != JSON.stringify(expected[column], "", true, true):
					exact = false
					break
			if not exact: break
	check("CSV retains original full-precision formatting across batches", exact)

func _test_backpressure_and_retry() -> void:
	var sim := Simulation.new()
	root.add_child(sim)
	var recorder := TestRecorder.new(sim)
	recorder.start({"trace_capture_complete": true}, true)
	var gate := Gate.new()
	recorder.trace._chunk_rows = 2
	recorder.trace._store = Store.new(Recorder.FlightRows.COLUMNS, 2, folder.path_join("busy"), gate)
	sim.step()
	sim.step()
	gate.entered.wait()
	for i in 4: sim.step()
	var prefix: PackedByteArray = recorder.trace.rows.to_byte_array()
	var generation: int = recorder.recording_generation
	check("queue backpressure stops before accepting the next tick", not recorder.recording and recorder.trace.storage_error() == ERR_BUSY and recorder.trace.row_count() == 6 and recorder.trace.last_tick() == 5 and recorder.trace._tail.size() == 2 * Recorder.FlightRows.COLUMNS.size())
	check("backpressure remains visible with unsaved prefix", recorder.note.contains("INCOMPLETE") and recorder.has_unsaved_recording())
	gate.release.post()
	var blocker := folder.path_join("busy-blocker")
	var file := FileAccess.open(blocker, FileAccess.WRITE)
	file.store_string("file")
	file.close()
	recorder.output_dir = blocker
	recorder.start({}, true)
	check("start retry failure preserves prior generation and exact prefix", not recorder.recording and recorder.recording_generation == generation and recorder.has_unsaved_recording() and recorder.trace.rows.to_byte_array() == prefix)
	var output := folder.path_join("incomplete.csv")
	check("explicit retry saves accepted prefix", recorder.stop(output) == OK and not recorder.has_unsaved_recording() and recorder.note.contains("INCOMPLETE"))
	var text := FileAccess.get_file_as_string(output)
	check("incomplete CSV metadata cannot claim completion", text.contains("# trace_capture_complete: false\n") and text.contains("# trace_capture_last_tick: 5\n") and text.contains("# trace_capture_stop_reason: \"chunk storage error "))
	var lines := text.split("\n", false)
	check("saved prefix contains exactly six ordered rows", lines.size() >= 6 and int(float(lines[lines.size()-6].get_slice(",", 0))) == 0 and int(float(lines[lines.size()-1].get_slice(",", 0))) == 5)
	var old_dir: String = recorder.trace.recovery_directory()
	recorder.start({"next": true}, true)
	check("new generation clears old spool and records one current sample", recorder.recording and recorder.recording_generation == generation + 1 and recorder.trace.row_count() == 1 and int(recorder.trace.row(0)[0]) == sim.tick and not DirAccess.dir_exists_absolute(old_dir))
	recorder.recording = false
	check("explicit discard clears new generation", recorder.discard_unsaved(recorder.recording_generation) and recorder.trace.row_count() == 0)
	recorder.detach()
	sim.free()

func _test_async_write_failure() -> void:
	var sim := Simulation.new()
	root.add_child(sim)
	var recorder := TestRecorder.new(sim)
	recorder.start({}, true)
	var writer := FailingWriter.new()
	recorder.trace._chunk_rows = 2
	recorder.trace._store = Store.new(Recorder.FlightRows.COLUMNS, 2, folder.path_join("io"), writer)
	sim.step()
	sim.step()
	writer.entered.wait()
	writer.release.post()
	check("spool reports worker write failure", recorder.trace._store.drain() == ERR_FILE_CANT_WRITE)
	sim.step()
	var prefix: PackedByteArray = recorder.trace.rows.to_byte_array()
	check("asynchronous error refuses next sample before tail fills", not recorder.recording and recorder.trace.storage_error() == ERR_FILE_CANT_WRITE and recorder.trace.row_count() == 3 and recorder.trace.last_tick() == 2 and recorder.note.contains("INCOMPLETE"))
	var blocker := folder.path_join("io-blocker")
	var blocked_file := FileAccess.open(blocker, FileAccess.WRITE)
	blocked_file.store_string("file")
	blocked_file.close()
	var output := blocker.path_join("io-retry.csv")
	check("failed output retains all accepted bytes and does not mark the spool saved", recorder.stop(output) != OK and recorder.has_unsaved_recording() and recorder.trace.rows.to_byte_array() == prefix and not FileAccess.file_exists(output) and not recorder.trace._store._saved)
	recorder.output_dir = folder.path_join("io-published")
	recorder.collide = true
	check("publication collision retains the spool for another retry", recorder.stop() == ERR_ALREADY_EXISTS and recorder.has_unsaved_recording() and not recorder.trace._store._saved and recorder.trace.rows.to_byte_array() == prefix)
	recorder.collide = false
	var retried: Error = recorder.stop()
	var published := recorder.note.get_slice(": ", 1).get_slice(" (", 0)
	check("automatic retry publishes incomplete prefix despite the still-failing spool", retried == OK and writer.fail and recorder.note.contains("INCOMPLETE") and recorder.trace._store._saved and FileAccess.get_file_as_string(published).contains("# trace_capture_last_tick: 2\n"))
	var path: String = recorder.trace.recovery_directory()
	check("saved queued chunks can be explicitly cleared", recorder.trace.clear() == OK and (path.is_empty() or not DirAccess.dir_exists_absolute(path)))
	recorder.detach()
	sim.free()

func _test_unavailable_spool_root() -> void:
	var blocker := folder.path_join("spool-root-file")
	var blocked_file := FileAccess.open(blocker, FileAccess.WRITE)
	blocked_file.store_string("not a directory")
	blocked_file.close()
	var sim := Simulation.new()
	root.add_child(sim)
	var recorder := TestRecorder.new(sim)
	recorder.start({}, true)
	recorder.trace._chunk_rows = 2
	recorder.trace._store = Store.new(Recorder.FlightRows.COLUMNS, 2, blocker)
	sim.step()
	sim.step()
	var spool_error: Error = recorder.trace._store.drain()
	sim.step()
	var prefix: PackedByteArray = recorder.trace.rows.to_byte_array()
	check("unavailable spool root stops before the next sample", spool_error != OK and not recorder.recording and recorder.trace.row_count() == 3 and recorder.trace.last_tick() == 2 and recorder.trace.storage_error() != OK)
	var output := folder.path_join("root-fallback.csv")
	var saved: Error = recorder.stop(output)
	var lines := FileAccess.get_file_as_string(output).split("\n", false)
	var exact: bool = saved == OK and recorder.note.contains("INCOMPLETE") and recorder.trace.rows.to_byte_array() == prefix and lines.size() >= 3
	if exact:
		for index in 3:
			var fields := lines[lines.size() - 3 + index].split(",")
			var values: PackedFloat64Array = recorder.trace.row(index)
			if fields.size() != values.size(): exact = false; break
			for column in fields.size():
				if fields[column] != JSON.stringify(values[column], "", true, true): exact = false; break
			if not exact: break
	check("writable CSV preserves the exact accepted prefix while spool remains unavailable", exact and FileAccess.get_file_as_string(blocker) == "not a directory")
	check("unavailable spool recording can be cleared after publication", recorder.trace.clear() == OK)
	recorder.detach()
	sim.free()

func _test_cleanup_warning() -> void:
	var sim := Simulation.new()
	root.add_child(sim)
	var recorder := TestRecorder.new(sim)
	recorder.start({}, true)
	recorder.trace._chunk_rows = 2
	recorder.trace._store = Store.new(Recorder.FlightRows.COLUMNS, 2, folder.path_join("cleanup"), CleanupFailure.new())
	sim.step()
	sim.step()
	check("cleanup fixture publishes a chunk", recorder.trace._store.drain() == OK and not recorder.trace.recovery_directory().is_empty())
	recorder.recording = false
	var generation: int = recorder.recording_generation
	var discarded: bool = recorder.discard_unsaved(generation)
	var cleanup_path: String = recorder.trace.last_cleanup_path()
	check("committed discard clears logical ownership and reports retained tombstone", discarded and not recorder.has_unsaved_recording() and recorder.trace.row_count() == 0 and recorder.trace.last_cleanup_error() == ERR_FILE_CANT_WRITE and not cleanup_path.is_empty() and DirAccess.dir_exists_absolute(cleanup_path) and recorder.note.contains(cleanup_path) and recorder.note.contains("cleanup pending"))
	recorder.start({}, true)
	check("later start preserves the pending-cleanup status", recorder.recording and recorder.note.contains(cleanup_path) and recorder.note.contains("cleanup pending"))
	recorder.recording = false
	recorder.discard_unsaved(recorder.recording_generation)
	recorder.detach()
	sim.free()

func _test_malformed_latch() -> void:
	var sim := Simulation.new()
	root.add_child(sim)
	var recorder := Recorder.new(sim)
	recorder.start({})
	sim.inputs[0] = NAN
	sim.step()
	check("malformed telemetry remains a permanent rejection", not recorder.recording and recorder.trace.storage_error() == OK and recorder.stop(folder.path_join("invalid.csv")) == ERR_INVALID_DATA and recorder.has_unsaved_recording())
	check("malformed recording can only be explicitly discarded", recorder.discard_unsaved(recorder.recording_generation))
	recorder.detach()
	sim.free()

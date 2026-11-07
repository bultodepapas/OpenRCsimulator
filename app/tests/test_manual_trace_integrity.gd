extends SceneTree

const Publisher := preload("res://sim/manual_trace_save.gd")
const Recovery := preload("res://ui/trace_recovery.gd")
const UiDriver := preload("res://tests/ui_driver.gd")

class RecoveryApp extends "res://app_root.gd":
	func _request_app_quit() -> void: pass

class AirRecorder extends "res://sim/recorder.gd":
	var output_dir := ""
	var timestamp := "2026-01-02T03-04-05"
	func _save_automatic() -> Dictionary:
		return Publisher.save(trace, "trace", output_dir, timestamp)

class HeliRecorder extends "res://sim/rotorcraft_recorder.gd":
	var output_dir := ""
	var timestamp := "2026-01-02T03-04-05"
	func _save_automatic() -> Dictionary:
		return Publisher.save(trace, "helicopter", output_dir, timestamp)

class AirInput extends "res://main.gd":
	func _trace_meta() -> Dictionary: return {}

class HeliInput extends "res://helicopter_main.gd":
	pass

class InputSession extends Node:
	var sim: Node
	func trace_meta() -> Dictionary: return {}

class FakeSimulation extends Node:
	signal stepped(tick: int, time_s: float, state: PackedFloat64Array, loads: PackedFloat64Array, inputs: PackedFloat64Array, aux: PackedFloat64Array)
	var tick := 0
	var state := PackedFloat64Array([0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0])
	var last_loads := PackedFloat64Array([0, 0, 0, 0, 0, 0])
	var inputs := PackedFloat64Array([0, 0, 0, 0])
	var aux := PackedFloat64Array([0, 0, 0, 0])
	var continuous := PackedFloat64Array([0, 0, 0, 0, 0, 0])
	func time() -> float: return tick * dt()
	func dt() -> float: return 1.0 / 240.0
	func step() -> void:
		tick += 1
		state[0] = tick
		stepped.emit(tick, time(), state, last_loads, inputs, aux)

class TextWriter extends RefCounted:
	var content: String
	var collide := false
	var fail := false
	func _init(text: String) -> void: content = text
	func save(path: String) -> Error:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null: return FileAccess.get_open_error()
		var written := file.store_string(content)
		file.flush()
		var error := file.get_error()
		file.close()
		if collide:
			var other := FileAccess.open(path.get_base_dir().path_join("trace.csv"), FileAccess.WRITE)
			other.store_string("occupied")
			other.close()
		if fail: return ERR_FILE_CANT_WRITE
		return error if not written or error != OK else OK

var checks := 0
var failures := 0
var folder := ""

func check(label: String, passed: bool) -> void:
	checks += 1
	print(("ok   " if passed else "FAIL ") + label)
	if not passed: failures += 1

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	folder = "user://openrc-manual-trace-tests/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	check("fresh isolated test directory", DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)) == OK)
	var sim := FakeSimulation.new()
	root.add_child(sim)
	_test_recorder(AirRecorder.new(sim), sim, "trace")
	_test_recorder(HeliRecorder.new(sim), sim, "helicopter")
	_test_input(AirInput.new(), AirRecorder.new(sim), sim, "trace")
	_test_input(HeliInput.new(), HeliRecorder.new(sim), sim, "helicopter")
	_test_publication()
	sim.free()
	await _test_recovery_ui()
	print("Manual trace integrity: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func _rows(recorder: RefCounted, prefix: String) -> PackedByteArray:
	return (recorder.trace._rows if prefix == "trace" else recorder.trace.rows).to_byte_array()

func _path(note: String) -> String:
	return note.get_slice(": ", 1).get_slice(" (", 0)

func _test_recorder(recorder: RefCounted, sim: FakeSimulation, prefix: String) -> void:
	var output: String = folder.path_join(prefix)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var flat := output.path_join(prefix + "-2026-01-02T03-04-05.csv")
	var legacy := FileAccess.open(flat, FileAccess.WRITE)
	legacy.store_string("legacy")
	legacy.close()
	var occupied := output.path_join(prefix + "-2026-01-02T03-04-05")
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(occupied))
	var marker := FileAccess.open(occupied.path_join(prefix + ".csv"), FileAccess.WRITE)
	marker.store_string("prior")
	marker.close()
	recorder.output_dir = output
	recorder.start({"test": "first"})
	for i in 10: sim.step()
	check(prefix + " first save succeeds", recorder.stop() == OK)
	var first := _path(recorder.note)
	var first_bytes := FileAccess.get_file_as_bytes(first)
	check(prefix + " complete first output and old files survive", first_bytes.size() > 100 and FileAccess.get_file_as_string(flat) == "legacy" and FileAccess.get_file_as_string(occupied.path_join(prefix + ".csv")) == "prior")
	recorder.start({"test": "second"})
	check(prefix + " second save succeeds at identical timestamp", recorder.stop() == OK)
	var second := _path(recorder.note)
	check(prefix + " unique paths preserve first bytes", first != second and FileAccess.get_file_as_bytes(first) == first_bytes and FileAccess.get_file_as_bytes(second) != first_bytes)
	recorder.timestamp = "2025-01-02T03-04-05"
	recorder.start({"test": "rollback"})
	check(prefix + " clock rollback saves independently", recorder.stop() == OK and FileAccess.get_file_as_bytes(first) == first_bytes)
	var blocker := folder.path_join(prefix + "-blocker")
	var block_file := FileAccess.open(blocker, FileAccess.WRITE)
	block_file.store_string("block")
	block_file.close()
	recorder.output_dir = blocker
	recorder.start({"test": "unsaved"})
	for i in 10: sim.step()
	var original := _rows(recorder, prefix)
	var generation: int = recorder.recording_generation
	check(prefix + " failed save retains generation", recorder.stop() != OK and recorder.has_unsaved_recording() and _rows(recorder, prefix) == original)
	var recovery := Recovery.new()
	check(prefix + " departure detects unsaved failure", not recovery.save_if_recording(recorder).ok and recovery.has_pending(recorder))
	recorder.start({"test": "refused"})
	check(prefix + " start retry failure retains exact rows", recorder.recording_generation == generation and not recorder.recording and _rows(recorder, prefix) == original and recovery.has_pending(recorder))
	check(prefix + " repeated retry retains exact rows", not recovery.retry(recorder, generation).ok and _rows(recorder, prefix) == original)
	recorder.output_dir = output
	check(prefix + " explicit retry succeeds", recovery.retry(recorder, generation).ok and not recorder.has_unsaved_recording() and _rows(recorder, prefix) == original)
	recorder.start({"test": "replacement"})
	check(prefix + " stale callbacks cannot affect new generation", recorder.recording_generation == generation + 1 and not recovery.discard(recorder, generation) and not recovery.retry(recorder, generation).ok and recorder.has_unsaved_recording())
	recorder.output_dir = blocker
	check(prefix + " next failure is retained", recorder.stop() != OK and not recovery.save_if_recording(recorder).ok)
	var next_generation: int = recorder.recording_generation
	check(prefix + " explicit discard releases exactly that generation", recovery.discard(recorder, next_generation) and not recorder.has_unsaved_recording() and recorder.trace.row_count() == 0)
	recorder.output_dir = output
	recorder.start({"test": "explicit path"})
	check(prefix + " explicit path still overwrites", recorder.stop(flat) == OK and FileAccess.get_file_as_string(flat) != "legacy" and FileAccess.get_file_as_bytes(first) == first_bytes)
	recorder.detach()

func _test_input(flight: Node, recorder: RefCounted, sim: FakeSimulation, prefix: String) -> void:
	var session := InputSession.new()
	session.sim = sim
	flight.session = session
	flight.recorder = recorder
	var blocker := folder.path_join(prefix + "-input-blocker")
	var block_file := FileAccess.open(blocker, FileAccess.WRITE)
	block_file.store_string("block")
	block_file.close()
	recorder.output_dir = blocker
	var event := InputEventKey.new()
	event.physical_keycode = KEY_T
	event.pressed = true
	flight._unhandled_input(event)
	sim.step()
	var generation: int = recorder.recording_generation
	var original := _rows(recorder, prefix)
	flight._unhandled_input(event) # T stops and the automatic write fails.
	flight._unhandled_input(event) # T retries; failure must retain the first generation.
	check(prefix + " actual T handler preserves failed recording", not recorder.recording and recorder.recording_generation == generation and _rows(recorder, prefix) == original and recorder.has_unsaved_recording())
	recorder.output_dir = folder.path_join(prefix + "-input-success")
	flight._unhandled_input(event)
	check(prefix + " actual T handler retries before new recording", recorder.recording and recorder.recording_generation == generation + 1 and recorder.has_unsaved_recording())
	recorder.detach()
	flight.free()
	session.free()

func _test_recovery_ui() -> void:
	var ui := UiDriver.new(self)
	var app := RecoveryApp.new()
	app.user_args = PackedStringArray(["--quick-flight"])
	app.preferences_path = "user://test_manual_trace_recovery_ui.cfg"
	root.add_child(app)
	await ui.settle()
	check("recovery UI quick flight started", app.flight != null)
	if app.flight == null:
		await ui.close_app(app)
		return
	var flight: Node = app.flight
	var session: Node = flight.session
	flight.recorder.detach()
	var recorder := AirRecorder.new(session.sim, session.electrical_state, session.mass_properties)
	flight.recorder = recorder
	var blocker := folder.path_join("ui-blocker")
	var file := FileAccess.open(blocker, FileAccess.WRITE)
	file.store_string("block")
	file.close()
	recorder.output_dir = blocker
	var key := InputEventKey.new()
	key.physical_keycode = KEY_T
	key.pressed = true
	flight._unhandled_input(key)
	await process_frame
	var generation := recorder.recording_generation
	app.quit_app()
	await ui.settle()
	var dialog: ConfirmationDialog = app.get("_trace_recovery_dialog")
	var saved_rows := recorder.trace._rows.to_byte_array()
	check("failed exit opens recovery for real recorder", dialog != null and not recorder.recording and recorder.has_unsaved_recording() and saved_rows.size() > 0 and app._trace_recovery.has_pending(recorder))
	if dialog != null: dialog.confirmed.emit() # Stay
	await ui.settle()
	check("Stay keeps the flight and pending generation", app.flight == flight and recorder.recording_generation == generation and recorder.trace._rows.to_byte_array() == saved_rows and app._trace_recovery.has_pending(recorder))
	var resume := InputEventKey.new()
	resume.physical_keycode = KEY_P
	resume.pressed = true
	flight._unhandled_input(resume)
	flight._unhandled_input(key)
	check("Resume then T preserves failed rows", not recorder.recording and recorder.recording_generation == generation and recorder.trace._rows.to_byte_array() == saved_rows and app._trace_recovery.has_pending(recorder))
	recorder.output_dir = folder.path_join("ui-saved")
	check("recovery Retry persists those rows", app._trace_recovery.retry(recorder, generation).ok and not recorder.has_unsaved_recording() and recorder.trace._rows.to_byte_array() == saved_rows)
	flight._unhandled_input(key)
	check("T starts a new generation after Retry", recorder.recording and recorder.recording_generation == generation + 1)
	recorder.recording = false
	recorder.discard_unsaved(recorder.recording_generation)
	await ui.close_app(app)

func _thread_save(gate: Semaphore, index: int, output: String) -> Dictionary:
	gate.wait()
	return Publisher.save(TextWriter.new("writer-%d" % index), "concurrent", output, "same")

func _test_publication() -> void:
	var output := folder.path_join("concurrent")
	var gate := Semaphore.new()
	var threads: Array[Thread] = []
	for i in 12:
		var thread := Thread.new()
		threads.append(thread)
		check("thread %d starts" % i, thread.start(_thread_save.bind(gate, i, output)) == OK)
	for i in threads.size(): gate.post()
	var paths := {}
	var contents := {}
	for thread: Thread in threads:
		var result: Dictionary = thread.wait_to_finish()
		if result.error == OK:
			paths[result.path] = true
			contents[FileAccess.get_file_as_string(result.path)] = true
	check("concurrent equal timestamp reservations preserve twelve unique files", paths.size() == 12 and contents.size() == 12)
	var failed := TextWriter.new("partial")
	failed.fail = true
	var failed_result := Publisher.save(failed, "trace", folder.path_join("failed-write"), "fixed")
	check("writer failure is returned and unpublished", failed_result.error == ERR_FILE_CANT_WRITE and failed_result.path.is_empty() and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(folder.path_join("failed-write/trace-fixed"))))
	var collision := TextWriter.new("staged")
	collision.collide = true
	var collision_root := folder.path_join("publication-collision")
	var collision_result := Publisher.save(collision, "trace", collision_root, "fixed")
	check("publication collision preserves occupied bytes", collision_result.error == ERR_ALREADY_EXISTS and FileAccess.get_file_as_string(collision_root.path_join("trace-fixed/trace.csv")) == "occupied")

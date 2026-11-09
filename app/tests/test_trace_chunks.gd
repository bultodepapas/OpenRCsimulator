## C7: exact logical history through interactive raw chunks; no physics changes.
extends SceneTree
const Trace := preload("res://sim/trace.gd")
const Store := preload("res://sim/trace_chunk_store.gd")
const Recorder := preload("res://sim/recorder.gd")
const Session := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Weather := preload("res://physics/wind_config.gd")

class BlockWriter extends RefCounted:
	var entered := Semaphore.new()
	var release := Semaphore.new()
	func phase(name: String, index: int) -> Error:
		if name == "before_write" and index == 0:
			entered.post()
			release.wait()
		return OK

class FakeSim extends Node:
	signal stepped(tick: int, time_s: float, state: PackedFloat64Array, loads: PackedFloat64Array, inputs: PackedFloat64Array, aux: PackedFloat64Array)
	var tick := 0
	var state := PackedFloat64Array([10, -20, -30, 15, 0, 0, 1, 0, 0, 0, 0, 0, 0])
	var last_loads := PackedFloat64Array([0, 0, 0, 0, 0, 0])
	var inputs := PackedFloat64Array([0.125, -0.25, 0, 0.75])
	var aux := PackedFloat64Array([0, 0, 0, 0])
	var continuous := PackedFloat64Array()
	func dt() -> float: return 1.0 / 240.0
	func time() -> float: return tick * dt()
	func step() -> void:
		tick += 1
		state[0] = tick
		stepped.emit(tick, time(), state, last_loads, inputs, aux)

class FailCleanup extends RefCounted:
	func phase(name: String, _index: int) -> Error:
		return ERR_FILE_CANT_WRITE if name == "discard_before_cleanup" else OK

var checks := 0
var failures := 0
var directory := ""

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL " + label)

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	directory = "user://trace-chunk-tests/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_base_and_pressure()
	_cleanup_notice()
	var session: Node = Session.new()
	session.input_enabled = false
	session.setup()
	root.add_child(session)
	for entry in Catalog.airplane_flyable_entries():
		session.aircraft_path = entry.data
		check("reload " + entry.id, session.reload().begins_with("aircraft reloaded:"))
		_compare_session(session, str(entry.id), true)
	# Weather timing and initial-state reconstruction must survive each spill too.
	session.aircraft_path = "res://data/aircraft/jensen_ugly_stik_60.json"
	check("reload weather fixture", session.reload().begins_with("aircraft reloaded:"))
	for config in [Weather.preset("gusty"), Weather.spatial_defaults()]:
		session.reset()
		check("weather accepted", session.setup_weather(config))
		session.reset()
		_compare_session(session, "weather-%d" % checks, false)
	session.queue_free()
	await process_frame
	print("trace chunks: %d checks, %d failed" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _cleanup_notice() -> void:
	var sim := FakeSim.new()
	var recorder := Recorder.new(sim)
	recorder.start({}, true)
	recorder.trace._chunk_row_limit = 2
	recorder.trace._chunk_store = Store.new(recorder.trace.columns(), 2, directory, FailCleanup.new())
	for i in 2: sim.step()
	check("cleanup fixture saved", recorder.stop(directory.path_join("cleanup-first.csv")) == OK)
	recorder.start({})
	var pending := recorder.trace.last_cleanup_path
	check("committed cleanup failure reported", recorder.recording and recorder.trace.last_cleanup_error != OK
		and not pending.is_empty() and recorder.note.contains("cleanup pending"))
	check("second fixture saved", recorder.stop(directory.path_join("cleanup-second.csv")) == OK)
	recorder.start({})
	check("cleanup notice survives another generation", recorder.trace.last_cleanup_path == pending
		and recorder.trace.last_cleanup_error != OK and recorder.note.contains(pending))
	recorder.detach()
	recorder.trace.clear()
	# Remove only this fixture's known residual names, after checking their scope.
	check("cleanup fixture stays in reserved root", pending.begins_with(ProjectSettings.globalize_path(directory) + "/.discard-"))
	if pending.begins_with(ProjectSettings.globalize_path(directory) + "/.discard-"):
		var chunk := pending.path_join("spool/chunk-%016d.bin" % 0)
		if FileAccess.file_exists(chunk): DirAccess.remove_absolute(chunk)
		if DirAccess.dir_exists_absolute(pending.path_join("spool")): DirAccess.remove_absolute(pending.path_join("spool"))
		DirAccess.remove_absolute(pending)
	check("resolved cleanup notice clears", recorder.trace.clear() == OK and recorder.trace.last_cleanup_error == OK)
	sim.free()

func _same_rows(a: RefCounted, b: RefCounted) -> bool:
	if a.row_count() != b.row_count() or a.columns() != b.columns(): return false
	var left := PackedFloat64Array()
	var right := PackedFloat64Array()
	for row_index in a.row_count():
		for column in a.columns():
			left.append(a.value(row_index, column))
			right.append(b.value(row_index, column))
	return left.to_byte_array() == right.to_byte_array()

func _base_and_pressure() -> void:
	var sim := FakeSim.new()
	var reference := Trace.new()
	var candidate := Trace.new()
	candidate.enable_chunk_storage(directory, 4)
	for tick in 29:
		sim.tick = tick
		sim.state[0] = tick
		reference.record(tick, sim.time(), sim.state, sim.last_loads, sim.inputs, sim.aux)
		candidate.record(tick, sim.time(), sim.state, sim.last_loads, sim.inputs, sim.aux)
		if candidate._chunk_store != null: check("drain", candidate._chunk_store.drain() == OK)
	check("all float64 bits", _same_rows(reference, candidate))
	check("bounded tail", candidate._rows.size() <= 4 * candidate.columns().size())
	check("continuous across chunks", candidate.is_continuous() and candidate.gaps().is_empty())
	check("exact CSV", candidate.to_csv() == reference.to_csv())
	var path := directory.path_join("base.csv")
	check("save", candidate.save(path) == OK and FileAccess.get_file_as_string(path) == reference.to_csv())
	var spool := candidate.recovery_directory()
	var collision := spool.path_join("../" + spool.get_file()).path_join("chunk-%016d.bin" % 0)
	check("own spool cannot be export destination", candidate.save(collision) == ERR_INVALID_PARAMETER)
	check("rejected collision preserves raw rows", _same_rows(reference, candidate))
	var damaged := FileAccess.open(spool.path_join("chunk-%016d.bin" % 0), FileAccess.READ_WRITE)
	damaged.store_8(0)
	damaged.close()
	check("corrupt storage refuses numeric read", is_nan(candidate.value(0, "tick")))
	check("corrupt storage never reports continuity", not candidate.is_continuous() and candidate.gaps() == PackedInt64Array([-1]))
	check("corrupt storage refuses CSV", candidate.to_csv().is_empty() and candidate.save(directory.path_join("corrupt.csv")) != OK)
	check("partial corrupt export removed", not FileAccess.file_exists(directory.path_join("corrupt.csv")))
	var unrelated_path := spool.path_join("not-owned.txt")
	var unrelated := FileAccess.open(unrelated_path, FileAccess.WRITE)
	unrelated.store_string("preserve")
	unrelated.close()
	check("cleanup failure is visible", candidate.clear() != OK and candidate._chunk_store != null)
	check("cleanup preserves unrelated file", FileAccess.get_file_as_string(unrelated_path) == "preserve")
	DirAccess.remove_absolute(unrelated_path)
	check("cleanup retries", candidate.clear() == OK)
	check("clear releases spool", not DirAccess.dir_exists_absolute(spool) and candidate.row_count() == 0)
	sim.tick = 0
	var recorder := Recorder.new(sim)
	recorder.start({}, true)
	recorder.trace._chunk_row_limit = 2
	var blocker := BlockWriter.new()
	recorder.trace._chunk_store = Store.new(recorder.trace.columns(), 2, directory, blocker)
	for tick in 6:
		sim.step()
		if sim.tick == 2: blocker.entered.wait()
	check("pressure stops capture", not recorder.recording and recorder.trace.storage_error() == ERR_BUSY)
	check("exact accepted prefix", recorder.trace.row_count() == 6 and recorder.trace.value(5, "tick") == 5)
	check("visible incomplete reason", recorder.note.begins_with("INCOMPLETE") and recorder.trace.meta.trace_capture_complete == false)
	var prefix := recorder.trace.to_csv()
	blocker.release.post()
	check("retry saves prefix", recorder.stop(directory.path_join("pressure.csv")) == OK)
	check("saved prefix remains incomplete", recorder.note.begins_with("INCOMPLETE") and FileAccess.get_file_as_string(directory.path_join("pressure.csv")) == prefix)
	check("prefix flags present", prefix.contains("# trace_capture_complete: false\n") and prefix.contains("# trace_capture_last_tick: 5.0\n"))
	var old_spool := recorder.trace.recovery_directory()
	recorder.start({})
	check("new generation releases saved spool", recorder.recording and recorder.trace.row_count() == 1 and not DirAccess.dir_exists_absolute(old_spool))
	recorder.detach()
	# A failed spool must not prevent exporting retained rows somewhere writable.
	var bad_root := directory.path_join("not-a-directory")
	var blocker_file := FileAccess.open(bad_root, FileAccess.WRITE)
	blocker_file.store_string("preserve")
	blocker_file.close()
	sim.tick = 0
	var failed_spool := Recorder.new(sim)
	failed_spool.start({}, true)
	failed_spool.trace._chunk_row_limit = 2
	failed_spool.trace._chunk_directory = bad_root
	for i in 2: sim.step()
	check("spool fault witnessed", failed_spool.trace._chunk_store.drain() != OK)
	sim.step()
	check("spool failure stops recording", not failed_spool.recording and failed_spool.trace.row_count() == 3)
	var retained_csv := failed_spool.trace.to_csv()
	var backup := directory.path_join("spool-failure.csv")
	check("export bypasses failed spool", failed_spool.stop(backup) == OK and FileAccess.get_file_as_string(backup) == retained_csv)
	check("failed spool blocker preserved", FileAccess.get_file_as_string(bad_root) == "preserve")
	failed_spool.detach()
	failed_spool.trace.clear()
	sim.free()

func _compare_session(session: Node, label: String, mass_enabled: bool) -> void:
	var reference := Trace.new()
	var candidate := Trace.new()
	reference.electrical_sample = session.electrical_state
	candidate.electrical_sample = session.electrical_state
	reference.meta = session.trace_meta().duplicate(true)
	if mass_enabled: reference.meta.mass_trace_schema = "openrc-mass-sample v1"
	candidate.meta = reference.meta.duplicate(true)
	candidate.enable_chunk_storage(directory, 4)
	for tick in 13:
		if tick > 0: session.sim.step()
		var mass: Dictionary = session.mass_properties() if mass_enabled else {}
		for trace in [reference, candidate]:
			trace.record(session.sim.tick, session.sim.time(), session.sim.state, session.sim.last_loads,
				session.sim.inputs, session.sim.aux, session.sim.continuous.duplicate(), mass)
		if candidate._chunk_store != null: check("drain " + label, candidate._chunk_store.drain() == OK)
		if tick == 5:
			var mid := directory.path_join("mid-" + label + ".csv")
			check("save active prefix " + label, candidate.save(mid) == OK and FileAccess.get_file_as_string(mid) == reference.to_csv())
	check("13 rows " + label, candidate.row_count() == 13 and reference.row_count() == 13)
	check("exact every field " + label, _same_rows(reference, candidate))
	check("exact schema CSV " + label, candidate.to_csv() == reference.to_csv())
	check("first-sample continuity " + label, not candidate._invalid_weather and candidate.is_continuous())
	candidate.meta.visual_timeline = "[{\"tick\":12,\"visual\":\"test\"}]"
	reference.meta.visual_timeline = candidate.meta.visual_timeline
	check("late visual metadata " + label, candidate.to_csv() == reference.to_csv())
	var path := directory.path_join(label + ".csv")
	check("saved schema " + label, candidate.save(path) == OK and FileAccess.get_file_as_string(path) == reference.to_csv())
	candidate.meta.trace_capture_complete = false
	check("failure metadata " + label, candidate.to_csv().contains("# trace_capture_complete: false\n"))
	candidate.clear()

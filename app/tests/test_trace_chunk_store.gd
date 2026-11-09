extends SceneTree

const Store = preload("res://sim/trace_chunk_store.gd")
var checks := 0
var failures := 0
var base := ""


class Gate extends RefCounted:
	var entered := Semaphore.new()
	var release := Semaphore.new()
	var block := false
	var delay_ms := 0
	var failures_left := 0
	var fail_recovery := false
	var mutate_path := ""
	var directory_ready := Semaphore.new()
	var block_after_directory := false
	var fail_discard_before := false
	var fail_cleanup := false
	var replace_on_cleanup := ""
	func phase(name: String, index: int) -> Error:
		if name == "before_write":
			entered.post()
			if block and index == 0:
				release.wait()
			if delay_ms > 0:
				OS.delay_msec(delay_ms)
		if name == "after_flush" and failures_left > 0:
			failures_left -= 1
			return ERR_FILE_CANT_WRITE
		if name == "recovery_after_flush" and fail_recovery:
			return ERR_FILE_CANT_WRITE
		if name == "after_directory" and block_after_directory:
			directory_ready.post()
			release.wait()
		if name == "discard_before_rename" and fail_discard_before:
			return ERR_FILE_CANT_WRITE
		if name == "discard_before_cleanup" and fail_cleanup:
			return ERR_FILE_CANT_WRITE
		if name == "discard_before_cleanup" and not replace_on_cleanup.is_empty():
			var root := DirAccess.open(replace_on_cleanup)
			root.include_hidden = true
			root.list_dir_begin()
			while true:
				var entry := root.get_next()
				if entry.is_empty(): break
				if entry.begins_with(".discard-"):
					var path := replace_on_cleanup.path_join(entry).path_join("spool/chunk-0000000000000000.bin")
					var replacement := FileAccess.open(path, FileAccess.WRITE)
					replacement.store_string("foreign replacement")
					replacement.close()
			root.list_dir_end()
		if name == "recovery_before_copy" and not mutate_path.is_empty():
			var file := FileAccess.open(mutate_path, FileAccess.WRITE)
			if file == null:
				return FileAccess.get_open_error()
			file.store_buffer(PackedByteArray([0, 1, 2]))
			file.close()
		return OK


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, condition: bool) -> void:
	checks += 1
	if condition:
		print("ok ", label)
	else:
		failures += 1
		printerr("FAIL ", label)


func _wait_entered(gate: Gate) -> bool:
	for attempt in 300:
		if gate.entered.try_wait():
			return true
		await create_timer(0.01).timeout
	return false


func _wait_signal(semaphore: Semaphore) -> bool:
	for attempt in 300:
		if semaphore.try_wait():
			return true
		await create_timer(0.01).timeout
	return false


func _wait_error(store: RefCounted) -> Error:
	for attempt in 300:
		var err: Error = store.write_error()
		if err != OK:
			return err
		await create_timer(0.01).timeout
	return OK


func _run() -> void:
	var parent := ProjectSettings.globalize_path("res://../tmp/memory-chunks-20261108/cases")
	var err := DirAccess.make_dir_recursive_absolute(parent)
	if err != OK and err != ERR_ALREADY_EXISTS:
		printerr("cannot create test parent: ", err)
		quit(2)
		return
	base = parent.path_join("case-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	err = DirAccess.make_dir_absolute(base)
	if err != OK:
		printerr("cannot reserve test directory: ", err)
		quit(2)
		return
	await _queue_and_bits()
	await _failure_retry()
	await _foreign_collision(false)
	await _foreign_collision(true)
	await _recovery_and_corruption()
	_discard_transactions()
	await _teardown()
	check("all test-owned paths are removed", DirAccess.remove_absolute(base) == OK)
	if "--keep-fixture" in OS.get_cmdline_user_args():
		var fixture := Store.new(["tick", "t_s"], 2, parent)
		var fixture_header := "# format: openrc-trace v3\ntick,t_s\n"
		var fixture_error: Error = fixture.append_chunk(PackedFloat64Array([0.0, 0.0, 1.0, 0.004166667]), fixture_header)
		if fixture_error == OK:
			fixture_error = fixture.drain()
		var fixture_path: String = fixture.directory_path()
		fixture = null
		check("requested recovery fixture is retained", fixture_error == OK and not fixture_path.is_empty())
		print("trace recovery fixture: ", fixture_path)
	print("trace chunk store: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _queue_and_bits() -> void:
	var invalid := Store.new([], 1, base)
	check("invalid schema refuses admission", invalid.append_chunk(PackedFloat64Array([1.0]), "header\n") == ERR_INVALID_PARAMETER)
	var too_large := Store.new(["x"], 4097, base)
	check("chunk row limit is enforced", too_large.append_chunk(PackedFloat64Array(), "header\n") == ERR_INVALID_PARAMETER)
	var gate := Gate.new()
	gate.block = true
	var store := Store.new(["tick", "value"], 2, base, gate)
	check("incomplete chunks are rejected", store.append_chunk(PackedFloat64Array([1.0]), "header\n") == ERR_INVALID_PARAMETER)
	check("CSV header must match the stored schema", store.append_chunk(PackedFloat64Array([0,0,1,1]), "tick,other\n") == ERR_INVALID_PARAMETER)
	var original := PackedByteArray([
		0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,128,
		0,0,0,0,0,0,240,63, 1,0,0,0,0,0,248,127])
	var first := original.to_float64_array()
	var second := PackedFloat64Array([2.0, 3.5, 3.0, 4.5])
	check("first full chunk is accepted", store.append_chunk(first, "# first\ntick,value\n") == OK)
	check("worker reaches the blocked writer", await _wait_entered(gate))
	first[0] = 42.0
	check("second full chunk is accepted while first is in flight", store.append_chunk(second, "# second\ntick,value\n") == OK)
	check("queue cap includes the in-flight chunk", store.append_chunk(second, "tick,value\n") == ERR_BUSY and store.row_count() == 4)
	check("buffered byte count includes both queued chunks", store.buffered_bytes() == 64)
	check("queued rows preserve original bits despite caller mutation", store.row(0).to_byte_array() == original.slice(0, 16) \
		and store.row(1).to_byte_array() == original.slice(16, 32) and store.read_error() == OK)
	check("invalid row returns empty and explicit error", store.row(4).is_empty() and store.read_error() == ERR_INVALID_PARAMETER)
	gate.release.post()
	check("drain publishes accepted chunks", store.drain() == OK)
	check("published rows preserve signed zero and NaN payload bits", store.row(0).to_byte_array() == original.slice(0, 16) \
		and store.row(1).to_byte_array() == original.slice(16, 32) and store.read_error() == OK)
	check("second persisted chunk stays ordered", store.row(3) == PackedFloat64Array([3.0, 4.5]))
	check("one decoded chunk remains cached", store.buffered_bytes() == 32)
	check("last header reflects the latest accepted chunk", store.last_header() == "# second\ntick,value\n")
	check("worker restarts after drain", store.append_chunk(PackedFloat64Array([4,5,6,7]), "# third\ntick,value\n") == OK \
		and store.drain() == OK and store.row_count() == 6 and store.row(4) == PackedFloat64Array([4,5]))
	check("explicit discard deletes owned spool", store.discard() == OK)


func _failure_retry() -> void:
	var gate := Gate.new()
	gate.failures_left = 1
	var store := Store.new(["tick", "value"], 2, base, gate)
	var values := PackedFloat64Array([0, 1, 2, 3])
	check("fault fixture accepted", store.append_chunk(values, "tick,value\n") == OK)
	check("asynchronous flush failure is visible", await _wait_error(store) == ERR_FILE_CANT_WRITE)
	check("failed chunk stays readable and further appends refuse it", store.row(1) == PackedFloat64Array([2,3]) \
		and store.append_chunk(values, "tick,value\n") == ERR_FILE_CANT_WRITE)
	var path: String = store.directory_path()
	check("failed staged packet is retained for retry", FileAccess.file_exists(path.path_join("stage/chunk-0000000000000000.bin.partial")))
	check("explicit drain retries and publishes failed chunk", store.drain() == OK \
		and store.write_error() == OK and store.row_count() == 2 and store.row(1) == PackedFloat64Array([2,3]))
	check("retry cleanup succeeds", store.discard() == OK)


func _foreign_collision(partial: bool) -> void:
	var gate := Gate.new()
	gate.block_after_directory = true
	var store := Store.new(["tick"], 1, base, gate)
	check("collision fixture accepted", store.append_chunk(PackedFloat64Array([7]), "tick\n") == OK)
	check("collision fixture reserves its spool", await _wait_signal(gate.directory_ready))
	var dir: String = store.directory_path()
	var name := "stage/chunk-0000000000000000.bin.partial" if partial else "chunk-0000000000000000.bin"
	var path := dir.path_join(name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("foreign")
	file.close()
	gate.block_after_directory = false
	gate.release.post()
	check("foreign chunk or partial collision is refused", await _wait_error(store) == ERR_ALREADY_EXISTS \
		and FileAccess.get_file_as_string(path) == "foreign")
	check("foreign collision prevents discard and preserves queued data", store.discard() == ERR_BUSY \
		and store.row(0) == PackedFloat64Array([7]) and FileAccess.get_file_as_string(path) == "foreign")
	check("collision can be removed and queued work retried", DirAccess.remove_absolute(path) == OK \
		and store.drain() == OK and store.row(0) == PackedFloat64Array([7]))
	check("collision fixture discards its spool", store.discard() == OK and store.cleanup_error() == OK)


func _recovery_and_corruption() -> void:
	var header := "# format: openrc-trace v3\n# recovery_complete: true\n# trace_capture_complete: true\ntick,value\n"
	var a := Store.new(["tick", "value"], 2, base)
	var b := Store.new(["tick", "value"], 2, base)
	var first := PackedFloat64Array([0,0.125,1,0.25])
	var second := PackedFloat64Array([2,0.5,3,0.75])
	check("two independent sessions accept matching schemas", a.append_chunk(first, header) == OK \
		and a.append_chunk(second, header) == OK and b.append_chunk(first, header) == OK \
		and b.append_chunk(second, header) == OK)
	check("independent sessions drain", a.drain() == OK and b.drain() == OK)
	var a_dir: String = a.directory_path()
	var b_dir: String = b.directory_path()
	var a_second := a_dir.path_join("chunk-0000000000000001.bin")
	var b_second := b_dir.path_join("chunk-0000000000000001.bin")
	check("session identities differ", a_dir != b_dir)
	var enormous := b_dir.path_join("chunk-9999999999999999.bin")
	var large_index := FileAccess.open(enormous, FileAccess.WRITE)
	large_index.close()
	var gap_dest := base.path_join("gap-recovery")
	var gap: Dictionary = Store.recover_csv(b_dir, gap_dest)
	check("large sparse index is handled without allocating an index-sized array", gap.error != OK \
		and not gap.complete and gap.rows == 4 and not gap.path.is_empty())
	check("test removes sparse recovery artifacts", DirAccess.remove_absolute(gap.path) == OK \
		and DirAccess.remove_absolute(gap_dest) == OK and DirAccess.remove_absolute(enormous) == OK)
	check("test mutation swaps a same-schema packet", DirAccess.copy_absolute(b_second, a_second) == OK)
	check("live read refuses a different session", a.row(2).is_empty() and a.read_error() == ERR_FILE_CORRUPT)
	var dest := base.path_join("recovery")
	var recovered: Dictionary = Store.recover_csv(a_dir, dest)
	check("recovery reports mixed session and keeps the valid prefix", not recovered.complete \
		and recovered.error == ERR_FILE_CORRUPT and recovered.rows == 2 and not recovered.path.is_empty())
	var text := FileAccess.get_file_as_string(recovered.path)
	check("recovered CSV retains format first and incomplete markers", text.begins_with("# format: openrc-trace v3\n# recovery_complete: false\n# trace_capture_complete: false\n") \
		and not text.contains("# recovery_complete: true") and text.count("# recovery_complete:") == 1 \
		and not text.contains("# trace_capture_complete: true") and text.count("# trace_capture_complete:") == 1 \
		and text.contains("0,0.125000000\n1,0.250000000\n"))
	var reader := FileAccess.open(recovered.path, FileAccess.READ)
	reader.get_line()
	reader.get_line()
	reader.get_line()
	check("standard CSV reader accepts recovered columns and values", reader.get_csv_line() == PackedStringArray(["tick", "value"]) \
		and reader.get_csv_line() == PackedStringArray(["0", "0.125000000"]) \
		and reader.get_csv_line() == PackedStringArray(["1", "0.250000000"]))
	reader.close()
	var collision: Dictionary = Store.recover_csv(a_dir, dest)
	check("recovery refuses an existing destination without changing it", collision.error == ERR_ALREADY_EXISTS \
		and FileAccess.get_file_as_string(recovered.path) == text)
	check("test recovered output removes its own file", DirAccess.remove_absolute(recovered.path) == OK \
		and DirAccess.remove_absolute(dest) == OK)
	var fail_gate := Gate.new()
	fail_gate.fail_recovery = true
	var fail_dest := base.path_join("failed-recovery")
	var output_failure: Dictionary = Store.recover_csv(a_dir, fail_dest, fail_gate)
	check("recovery flush failure publishes no final file or row count", output_failure.error == ERR_FILE_CANT_WRITE \
		and output_failure.path.is_empty() and output_failure.rows == 0 \
		and not FileAccess.file_exists(fail_dest.path_join("recovered.csv")) \
		and not FileAccess.file_exists(fail_dest.path_join("recovered.partial")))
	check("failed recovery leaves only its reserved empty directory", DirAccess.remove_absolute(fail_dest) == OK)
	var first_path := a_dir.path_join("chunk-0000000000000000.bin")
	var mutation := Gate.new()
	mutation.mutate_path = first_path
	var changed_dest := base.path_join("changed-recovery")
	var changed: Dictionary = Store.recover_csv(a_dir, changed_dest, mutation)
	check("source mutation between recovery passes cannot publish a CSV", changed.error == ERR_FILE_CORRUPT \
		and changed.rows == 0 and changed.path.is_empty() \
		and not FileAccess.file_exists(changed_dest.path_join("recovered.csv")) \
		and not FileAccess.file_exists(changed_dest.path_join("recovered.partial")))
	check("changed recovery retains only its empty reserved directory", DirAccess.remove_absolute(changed_dest) == OK)
	check("truncated packet is an explicit read error", a.row(0).is_empty() and a.read_error() == ERR_FILE_CORRUPT)
	var broken: Dictionary = Store.recover_csv(a_dir, base.path_join("broken"))
	check("a corrupt first packet cannot export a prefix", broken.error == ERR_FILE_CORRUPT and broken.rows == 0 \
		and broken.path.is_empty() and not broken.complete)
	var unknown := a_dir.path_join("unowned.txt")
	var file := FileAccess.open(unknown, FileAccess.WRITE)
	file.store_string("keep")
	file.close()
	var corrupt_first := FileAccess.get_file_as_bytes(first_path)
	var foreign_second := FileAccess.get_file_as_bytes(a_second)
	check("failed discard preserves unknown and all chunk bytes", a.discard() != OK and FileAccess.file_exists(unknown) \
		and FileAccess.get_file_as_bytes(first_path) == corrupt_first and FileAccess.get_file_as_bytes(a_second) == foreign_second)
	check("remove only test-mutated files and the unknown sentinel", DirAccess.remove_absolute(unknown) == OK \
		and DirAccess.remove_absolute(first_path) == OK and DirAccess.remove_absolute(a_second) == OK)
	check("discard succeeds after explicit cleanup of test mutations", a.discard() == OK and a.cleanup_error() == OK)
	check("second spool cleans up", b.discard() == OK)


func _discard_transactions() -> void:
	var gate := Gate.new()
	var store := Store.new(["tick"], 1, base, gate)
	check("discard transaction fixture drains", store.append_chunk(PackedFloat64Array([9]), "tick\n") == OK and store.drain() == OK)
	var dir: String = store.directory_path()
	gate.fail_discard_before = true
	check("failed disposal rename retains all readable data", store.discard() == ERR_FILE_CANT_WRITE \
		and store.row(0) == PackedFloat64Array([9]) and store.directory_path() == dir)
	gate.fail_discard_before = false
	gate.fail_cleanup = true
	check("post-rename cleanup failure is a committed logical discard", store.discard() == OK \
		and store.cleanup_error() == ERR_FILE_CANT_WRITE and not store.cleanup_path().is_empty() \
		and store.row(0).is_empty())
	var container: String = store.cleanup_path()
	var spool := container.path_join("spool")
	check("cleanup failure leaves the isolated owned spool", FileAccess.file_exists(spool.path_join("chunk-0000000000000000.bin")))
	check("test removes the isolated fixture explicitly", DirAccess.remove_absolute(spool.path_join("chunk-0000000000000000.bin")) == OK \
		and DirAccess.remove_absolute(spool.path_join("stage")) == OK and DirAccess.remove_absolute(spool) == OK \
		and DirAccess.remove_absolute(container) == OK)
	var mutation := Gate.new()
	mutation.replace_on_cleanup = base
	var changed := Store.new(["tick"], 1, base, mutation)
	check("post-preflight replacement fixture drains", changed.append_chunk(PackedFloat64Array([3]), "tick\n") == OK \
		and changed.drain() == OK)
	check("discard preserves a replaced packet after preflight", changed.discard() == OK \
		and changed.cleanup_error() != OK and not changed.cleanup_path().is_empty())
	container = changed.cleanup_path()
	spool = container.path_join("spool")
	check("replacement bytes survive cleanup", FileAccess.get_file_as_string(spool.path_join("chunk-0000000000000000.bin")) == "foreign replacement")
	check("test removes the preserved replacement explicitly", DirAccess.remove_absolute(spool.path_join("chunk-0000000000000000.bin")) == OK \
		and DirAccess.remove_absolute(spool) == OK and DirAccess.remove_absolute(container) == OK)


func _teardown() -> void:
	var gate := Gate.new()
	gate.delay_ms = 150
	var store := Store.new(["tick"], 1, base, gate)
	check("teardown fixture accepts chunk", store.append_chunk(PackedFloat64Array([7]), "tick\n") == OK)
	check("teardown begins while worker is active", await _wait_entered(gate))
	var reference: WeakRef = weakref(store)
	store = null
	check("last reference joins worker without a reference cycle", reference.get_ref() == null)
	var found := ""
	var dir := DirAccess.open(base)
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty(): break
		if name.begins_with("trace-"): found = base.path_join(name)
	dir.list_dir_end()
	check("unsaved teardown retains published prefix", not found.is_empty() \
		and FileAccess.file_exists(found.path_join("chunk-0000000000000000.bin")))
	check("test removes its retained unsaved prefix", DirAccess.remove_absolute(found.path_join("chunk-0000000000000000.bin")) == OK \
		and DirAccess.remove_absolute(found.path_join("stage")) == OK \
		and DirAccess.remove_absolute(found) == OK)
	var saved := Store.new(["tick"], 1, base)
	check("saved fixture drains", saved.append_chunk(PackedFloat64Array([1]), "tick\n") == OK and saved.drain() == OK)
	var saved_dir: String = saved.directory_path()
	saved.mark_saved()
	saved = null
	check("saved teardown removes its owned spool", not DirAccess.dir_exists_absolute(saved_dir))
	var replaced := Store.new(["tick"], 1, base)
	check("saved replacement fixture drains", replaced.append_chunk(PackedFloat64Array([1]), "tick\n") == OK and replaced.drain() == OK)
	var replaced_dir: String = replaced.directory_path()
	var replaced_path := replaced_dir.path_join("chunk-0000000000000000.bin")
	var file := FileAccess.open(replaced_path, FileAccess.WRITE)
	file.store_string("foreign replacement")
	file.close()
	replaced.mark_saved()
	replaced = null
	check("saved teardown preserves a replaced packet", FileAccess.get_file_as_string(replaced_path) == "foreign replacement")
	check("test removes the saved replacement explicitly", DirAccess.remove_absolute(replaced_path) == OK \
		and DirAccess.remove_absolute(replaced_dir) == OK)
	var resumed := Store.new(["tick"], 1, base)
	check("append-after-save fixture drains", resumed.append_chunk(PackedFloat64Array([1]), "tick\n") == OK and resumed.drain() == OK)
	resumed.mark_saved()
	check("append after marking saved accepts a new chunk", resumed.append_chunk(PackedFloat64Array([2]), "tick\n") == OK and resumed.drain() == OK)
	var resumed_dir: String = resumed.directory_path()
	resumed = null
	check("append revokes saved cleanup on teardown", DirAccess.dir_exists_absolute(resumed_dir) \
		and FileAccess.file_exists(resumed_dir.path_join("chunk-0000000000000001.bin")))
	check("test removes resumed spool", DirAccess.remove_absolute(resumed_dir.path_join("chunk-0000000000000000.bin")) == OK \
		and DirAccess.remove_absolute(resumed_dir.path_join("chunk-0000000000000001.bin")) == OK \
		and DirAccess.remove_absolute(resumed_dir.path_join("stage")) == OK \
		and DirAccess.remove_absolute(resumed_dir) == OK)

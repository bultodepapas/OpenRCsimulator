extends SceneTree
## AC-13: the Creator store — hash-addressed objects, one pointer as commit point, compare-and-swap,
## drafts, recovery, published revisions, archive, quota, fault stages, tampering and the
## single-writer process lock (in one process and across two real processes).
## Everything is generated here under one temporary folder in user://, removed at the end.

const Store := preload("res://workshop/creator/store.gd")
const ProcessLock := preload("res://workshop/creator/process_lock.gd")
const CreatorBytes := preload("res://workshop/creator/bytes.gd")
const R := preload("res://workshop/creator/result.gd")
const Limits := preload("res://workshop/creator/limits.gd")
const Compiler := preload("res://workshop/creator/compiler.gd")
const Definition := preload("res://workshop/creator/definition.gd")
const Authoring := preload("res://workshop/creator/authoring.gd")

const ID_A := "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
const ID_B := "bbbbbbbb-bbbb-4bbb-9bbb-bbbbbbbbbbbb"
const ID_C := "cccccccc-cccc-4ccc-accc-cccccccccccc"
const ID_D := "dddddddd-dddd-4ddd-bddd-dddddddddddd"
const SHA_NOWHERE := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

var checks := 0
var failures := 0
var _base := ""
var _peers := 0
var _section_started := 0


func _initialize() -> void:
	var started := Time.get_ticks_msec()
	_section_started = started
	_base = "user://creator_store_test_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(_abs(_base))
	_test_lock()
	_section("lock, one process")
	_test_roots()
	_test_drafts()
	_section("roots and drafts")
	_test_two_instances()
	_test_recovery()
	_section("instances and recovery")
	_test_aircraft()
	_section("published aircraft")
	_test_archive()
	_test_quota()
	_section("archive and quota")
	_test_fault_stages()
	_section("fault stages")
	_test_tampering()
	_section("tampering")
	_test_forged_records()
	_section("forged records")
	_test_processes()
	_section("lock, two processes")
	_remove_tree(_abs(_base))
	check("temporary roots removed", not DirAccess.dir_exists_absolute(_abs(_base)))
	print("Creator store: elapsed %.1f s" % ((Time.get_ticks_msec() - started) / 1000.0))
	print("Creator store: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


# --- Process lock in one process ---------------------------------------------------------------

func _test_lock() -> void:
	var root := _abs(_base + "/lock_a")
	var ports := ProcessLock.candidate_ports(root)
	var distinct := {}
	var in_range := true
	for port: int in ports:
		distinct[port] = true
		in_range = in_range and port >= ProcessLock.PORT_FIRST and port < ProcessLock.PORT_FIRST + ProcessLock.PORT_COUNT
	check("lock: eight distinct candidate ports", ports.size() == 8 and distinct.size() == 8)
	check("lock: candidates below the ephemeral ranges", in_range and ProcessLock.PORT_FIRST + ProcessLock.PORT_COUNT <= 32768)
	check("lock: candidates are deterministic", ports == ProcessLock.candidate_ports(root))
	check("lock: user:// and absolute spellings are one root", ProcessLock.identity(_base + "/lock_a") == ProcessLock.identity(root))
	check("lock: trailing slash and backslashes are one root",
		ProcessLock.identity(root + "/") == ProcessLock.identity(root) and ProcessLock.identity(root.replace("/", "\\")) == ProcessLock.identity(root))
	check("lock: another root has another identity", ProcessLock.identity(root + "x") != ProcessLock.identity(root)
		and ProcessLock.candidate_ports(root + "x") != ports)
	check("lock: banner names protocol and root", ProcessLock.banner(root) == "openrc-creator-lock v1 %s\n" % ProcessLock.identity(root)
		and CreatorBytes.is_sha256(ProcessLock.identity(root)))
	var relative: Dictionary = ProcessLock.acquire("relative/root")
	check("lock: relative root is an error", relative.status == "error" and relative.lock == null)

	var first: Dictionary = ProcessLock.acquire(root)
	check("lock: acquired", first.status == "acquired" and first.lock != null and first.lock.is_held() and ports.has(int(first.port)))
	if first.lock == null:
		return
	check("lock: holder answers with the banner", _banner_from(int(first.port)) == ProcessLock.banner(root))
	check("lock: holder keeps answering", _banner_from(int(first.port)) == ProcessLock.banner(root))
	var second: Dictionary = ProcessLock.acquire(root)
	check("lock: second acquire in this process is busy", second.status == "busy" and second.lock == null and second.port == first.port)
	var spelled: Dictionary = ProcessLock.acquire(_base + "/lock_a/")
	check("lock: another spelling of the root is busy too", spelled.status == "busy")
	var other: Dictionary = ProcessLock.acquire(root + "_other")
	check("lock: another root is independent", other.status == "acquired")
	if other.lock != null:
		other.lock.release()
	first.lock.release()
	check("lock: released", not first.lock.is_held())
	first.lock.release()
	var again: Dictionary = ProcessLock.acquire(root)
	check("lock: acquired again after release", again.status == "acquired")
	again.clear()  # The lock object is freed without release().
	var after_free: Dictionary = ProcessLock.acquire(root)
	check("lock: freed lock releases itself", after_free.status == "acquired")
	if after_free.lock != null:
		after_free.lock.release()

	# Other software on the candidate ports, and holders this process does not know about.
	root = _abs(_base + "/lock_b")
	ports = ProcessLock.candidate_ports(root)
	var line := ProcessLock.banner(root)
	var holder := _fake_holder(ports[0], line)
	if holder.ok:
		var began := Time.get_ticks_msec()
		var busy: Dictionary = ProcessLock.acquire(root)
		check("lock: a holder on the first candidate is busy", busy.status == "busy" and busy.port == ports[0])
		check("lock: busy is reported at once", Time.get_ticks_msec() - began < 1000)
	_stop_fake(holder)
	var foreign := _fake_holder(ports[0], ProcessLock.banner(root + "_elsewhere"))
	if foreign.ok:
		var skipped: Dictionary = ProcessLock.acquire(root)
		check("lock: another root's banner is skipped", skipped.status == "acquired" and skipped.port == ports[1])
		if skipped.lock != null:
			skipped.lock.release()
	_stop_fake(foreign)
	var silent := TCPServer.new()
	if silent.listen(ports[0], "127.0.0.1") == OK:
		var skipped: Dictionary = ProcessLock.acquire(root)
		check("lock: a silent listener is skipped", skipped.status == "acquired" and skipped.port == ports[1])
		if skipped.lock != null:
			skipped.lock.release()
	silent.stop()
	var settled := _fake_holder(ports[3], line)
	if settled.ok:
		var began := Time.get_ticks_msec()
		var yielded: Dictionary = ProcessLock.acquire(root)
		check("lock: a settled holder on a higher candidate wins", yielded.status == "busy" and yielded.port == ports[3])
		check("lock: the newcomer waited for it to yield first", Time.get_ticks_msec() - began >= ProcessLock.YIELD_MSEC)
	_stop_fake(settled)
	var blockers: Array[TCPServer] = []
	var all_blocked := true
	for port: int in ports:
		var blocker := TCPServer.new()
		all_blocked = all_blocked and blocker.listen(port, "127.0.0.1") == OK
		blockers.append(blocker)
	if all_blocked:
		var none: Dictionary = ProcessLock.acquire(root)
		check("lock: no free candidate is unsupported, never an unsafe lock", none.status == "unsupported" and none.lock == null)
	for blocker: TCPServer in blockers:
		blocker.stop()
	var free_again: Dictionary = ProcessLock.acquire(root)
	check("lock: first candidate again once everything left", free_again.status == "acquired" and free_again.port == ports[0])
	if free_again.lock != null:
		free_again.lock.release()


# --- Roots and drafts -------------------------------------------------------------------------

func _test_roots() -> void:
	for bad: String in ["C:/somewhere/store", "/tmp/store", "user://", "user://../escape", "user://a/../b", "user://a b",
			"user://a\\b", "res://store", "user://a//b", "user://c:/x", ""]:
		var refused: Dictionary = Store.open(bad)
		check("root refused: '%s'" % bad, not refused.ok and _code(refused) == R.WRITE_FAILED)
	check("unknown fault stage refused", not Store.open(_base + "/never", {fault_stage = "nowhere"}).ok)
	check("bad quota refused", not Store.open(_base + "/never", {quota_bytes = 0}).ok)
	check("refused opens create nothing", not DirAccess.dir_exists_absolute(_abs(_base + "/never")))

	var viewer_root := _base + "/viewer"
	var viewed: Dictionary = Store.open(viewer_root, {read_only = true})
	check("read-only open of a missing root", viewed.ok and not viewed.value.is_writer() and viewed.value.lock_status() == "read_only"
		and viewed.value.generation() == 0 and viewed.value.list_drafts(true).is_empty())
	check("read-only open writes nothing", not DirAccess.dir_exists_absolute(_abs(viewer_root)))
	check("read-only instance refuses to save", _code(viewed.value.save_draft(_draft(ID_A, "A", {}, PackedByteArray(), ""), "")) == R.ROOT_LOCK_BUSY)


func _test_drafts() -> void:
	var root := _base + "/drafts"
	var absolute := _abs(root)
	var opened: Dictionary = Store.open(root)
	check("empty root opens", opened.ok and opened.diagnostics.is_empty())
	if not opened.ok:
		return
	var store: RefCounted = opened.value
	check("empty root: writer with the lock", store.is_writer() and store.lock_status() == "acquired")
	check("empty root: generation 0 and no entries", store.generation() == 0 and store.list_drafts(true).is_empty()
		and store.list_aircraft(true).is_empty() and store.list_recovery().is_empty())
	check("empty root: pointer and first index on disk", FileAccess.file_exists(absolute + "/current.json")
		and not FileAccess.file_exists(absolute + "/previous.json") and _objects(absolute).size() == 1)
	check("empty root: stored bytes are the first index", store.stored_bytes() == _tree_bytes(absolute + "/objects"))

	var source := _bytes(5000, 11)
	var snapshot := {"step": "weight_balance", "span": 1.5, "count": 3, "flags": [true, false, null],
		"raw": {"wing/span": "1,5", "note": "Ñandú 雪\nsecond line"}, "nested": [[1, 2], {"deep": -0.0}]}
	var expected := {"step": "weight_balance", "span": 1.5, "count": 3.0, "flags": [true, false, null],
		"raw": {"wing/span": "1,5", "note": "Ñandú 雪\nsecond line"}, "nested": [[1.0, 2.0], {"deep": 0.0}]}
	var saved: Dictionary = store.save_draft(_draft(ID_A, "Ñandú trainer", snapshot, source, "Trainer v2.stl", ID_C), "")
	check("draft saved", saved.ok and saved.value.draft_id == ID_A and saved.value.generation == 1
		and CreatorBytes.is_sha256(saved.value.record_sha256))
	if not saved.ok:
		print(R.texts(saved))
		store.close()
		return
	var first_sha: String = saved.value.record_sha256
	var listed: Array = store.list_drafts()
	check("draft listed", listed.size() == 1 and listed[0].draft_id == ID_A and listed[0].name == "Ñandú trainer"
		and listed[0].aircraft_uuid == ID_C and listed[0].record_sha256 == first_sha and listed[0].archived == false
		and typeof(listed[0].updated_unix) == TYPE_INT and listed[0].updated_unix > 1700000000)
	var loaded: Dictionary = store.load_draft(ID_A)
	check("draft loads", loaded.ok)
	if loaded.ok:
		check("draft round trip: fields", loaded.value.draft_id == ID_A and loaded.value.name == "Ñandú trainer"
			and loaded.value.aircraft_uuid == ID_C and loaded.value.source_file_name == "Trainer v2.stl"
			and loaded.value.record_sha256 == first_sha)
		check("draft round trip: snapshot", loaded.value.snapshot == expected)
		check("draft round trip: exact source bytes", loaded.value.source_bytes == source)
	var record_bytes := _object(absolute, first_sha)
	check("record object is named by its exact bytes", CreatorBytes.sha256(record_bytes) == first_sha)
	var record: Dictionary = CreatorBytes.decode(record_bytes, Store.DRAFT_INTEGERS, Limits.DRAFT_BYTES)
	check("record object decodes", record.ok)
	if record.ok:
		var data: Dictionary = record.value.data
		check("record: closed key set", data.keys().size() == Store.DRAFT_KEYS.size() and data.format == Store.DRAFT_FORMAT)
		check("record: source is a blob reference", data.source.sha256 == CreatorBytes.sha256(source)
			and data.source.byte_length == source.size() and data.source.media_type == Store.MEDIA_SOURCE)
		check("record: re-encoding gives the same bytes", CreatorBytes.encode(data, Limits.DRAFT_BYTES).value.bytes == record_bytes)
	var record_text := record_bytes.get_string_from_utf8()
	check("record holds no path or URL", not record_text.contains(absolute) and not record_text.contains("user:")
		and not record_text.contains("objects/"))
	check("source object holds the exact bytes", _object(absolute, CreatorBytes.sha256(source)) == source)
	check("previous pointer kept", FileAccess.file_exists(absolute + "/previous.json"))
	check("staging is empty after a commit", _files(absolute + "/staging").is_empty())

	var before := _tree(absolute)
	var same: Dictionary = store.save_draft(_draft(ID_A, "Ñandú trainer", snapshot, source, "Trainer v2.stl", ID_C), first_sha)
	check("identical save is a no-op", same.ok and same.value.record_sha256 == first_sha and same.value.generation == 1
		and _tree(absolute) == before)
	if loaded.ok:
		var resaved: Dictionary = store.save_draft(loaded.value, first_sha)
		check("saving what was loaded is a no-op", resaved.ok and resaved.value.record_sha256 == first_sha and store.generation() == 1)
	check("must-not-exist on an existing draft conflicts",
		_code(store.save_draft(_draft(ID_A, "Other", {}, PackedByteArray(), ""), "")) == R.SAVE_CONFLICT)
	check("expected hash on a missing draft conflicts",
		_code(store.save_draft(_draft(ID_B, "Other", {}, PackedByteArray(), ""), first_sha)) == R.SAVE_CONFLICT)
	check("malformed expected hash conflicts",
		_code(store.save_draft(_draft(ID_A, "Other", {}, PackedByteArray(), ""), "not-a-hash")) == R.SAVE_CONFLICT)
	check("conflicts change nothing", store.generation() == 1 and _tree(absolute) == before)

	snapshot["span"] = 1.6
	var updated: Dictionary = store.save_draft(_draft(ID_A, "Ñandú trainer", snapshot, source, "Trainer v2.stl", ID_C), first_sha)
	check("draft updated with the right hash", updated.ok and updated.value.record_sha256 != first_sha and updated.value.generation == 2)
	check("stale hash conflicts after the update",
		_code(store.save_draft(_draft(ID_A, "Ñandú trainer", {"late": true}, source, "Trainer v2.stl", ID_C), first_sha)) == R.SAVE_CONFLICT)
	check("the older record keeps its bytes", _object(absolute, first_sha) == record_bytes)
	check("the update is what loads", store.load_draft(ID_A).value.snapshot.span == 1.6)
	check("unknown draft is reported", _code(store.load_draft(ID_D)) == R.DEPENDENCY_MISSING)
	var unnamed: Dictionary = store.save_draft(_draft(ID_B, "No model yet", {"step": "import"}, PackedByteArray(), ""), "")
	check("draft without a model file", unnamed.ok and store.load_draft(ID_B).value.source_bytes.is_empty()
		and store.list_drafts().size() == 2)

	before = _tree(absolute)
	var generation: int = store.generation()
	var hostile := {
		"upper-case id": _draft(ID_A.to_upper(), "X", {}, PackedByteArray(), ""),
		"version 1 uuid": _draft("aaaaaaaa-aaaa-1aaa-8aaa-aaaaaaaaaaaa", "X", {}, PackedByteArray(), ""),
		"aircraft id that is no uuid": _draft(ID_D, "X", {}, PackedByteArray(), "", "my-plane"),
		"empty name": _draft(ID_D, "", {}, PackedByteArray(), ""),
		"blank name": _draft(ID_D, "   ", {}, PackedByteArray(), ""),
		"name too long": _draft(ID_D, "n".repeat(Limits.NAME_CHARACTERS + 1), {}, PackedByteArray(), ""),
		"name with a line break": _draft(ID_D, "two\nlines", {}, PackedByteArray(), ""),
		"file name with a drive path": _draft(ID_D, "X", {}, source, "C:/models/plane.stl"),
		"file name with a parent path": _draft(ID_D, "X", {}, source, "../plane.stl"),
		"file name with a backslash": _draft(ID_D, "X", {}, source, "models\\plane.stl"),
		"file name that is a URL": _draft(ID_D, "X", {}, source, "https://example.org/plane.stl"),
		"file name too long": _draft(ID_D, "X", {}, source, "f".repeat(Limits.SOURCE_FILE_NAME_CHARACTERS + 1)),
		"snapshot with infinity": _draft(ID_D, "X", {"v": INF}, PackedByteArray(), ""),
		"snapshot with NaN": _draft(ID_D, "X", {"v": [NAN]}, PackedByteArray(), ""),
		"snapshot with an object": _draft(ID_D, "X", {"v": RefCounted.new()}, PackedByteArray(), ""),
		"snapshot with a packed array": _draft(ID_D, "X", {"v": PackedFloat64Array([1.0])}, PackedByteArray(), ""),
		"snapshot with a control character": _draft(ID_D, "X", {"v": "bell" + char(7)}, PackedByteArray(), ""),
		"snapshot with a non-text key": _draft(ID_D, "X", {1: "x"}, PackedByteArray(), ""),
		"snapshot with an unsafe integer": _draft(ID_D, "X", {"v": 9007199254740993}, PackedByteArray(), ""),
	}
	for label: String in hostile:
		check("draft refused: " + label, _code(store.save_draft(hostile[label], "")) == R.RECORD_INVALID)
	var incomplete := _draft(ID_D, "X", {}, PackedByteArray(), "")
	incomplete.erase("snapshot")
	check("draft refused: missing member", _code(store.save_draft(incomplete, "")) == R.RECORD_INVALID)
	var wrong_type := _draft(ID_D, "X", {}, PackedByteArray(), "")
	wrong_type["source_bytes"] = "text"
	check("draft refused: source that is not bytes", _code(store.save_draft(wrong_type, "")) == R.RECORD_INVALID)
	var deep: Variant = "leaf"
	for level: int in Limits.JSON_DEPTH + 2:
		deep = [deep]
	check("draft refused: nested too deeply", _code(store.save_draft(_draft(ID_D, "X", {"v": deep}, PackedByteArray(), ""), "")) == R.RECORD_INVALID)
	var many: Array = []
	many.resize(Limits.JSON_VALUES + 10)
	many.fill(0.5)
	check("draft refused: more values than the reader accepts",
		_code(store.save_draft(_draft(ID_D, "X", {"v": many}, PackedByteArray(), ""), "")) == R.RECORD_INVALID)
	var bulky := _draft(ID_D, "X", {"note": "x".repeat(Limits.DRAFT_BYTES)}, PackedByteArray(), "")
	check("draft refused: larger than the draft limit", _code(store.save_draft(bulky, "")) == R.SOURCE_LIMIT)
	var oversized := PackedByteArray()
	oversized.resize(Limits.MODEL_SOURCE_BYTES + 1)
	check("draft refused: model file over the limit",
		_code(store.save_draft(_draft(ID_D, "X", {}, oversized, "big.stl"), "")) == R.SOURCE_LIMIT)
	oversized = PackedByteArray()
	check("refused drafts change nothing", store.generation() == generation and _tree(absolute) == before)

	store.close()
	check("closed instance: not a writer", not store.is_writer() and store.lock_status() == "read_only")
	check("closed instance still reads", store.load_draft(ID_A).ok)
	check("closed instance refuses to save", _code(store.save_draft(_draft(ID_D, "X", {}, PackedByteArray(), ""), "")) == R.ROOT_LOCK_BUSY)
	var reopened: Dictionary = Store.open(root)
	check("reopen: same accepted state", reopened.ok and reopened.diagnostics.is_empty() and reopened.value.generation() == generation
		and reopened.value.list_drafts().size() == 2 and not reopened.value.recovered_from_previous())
	if reopened.ok:
		check("reopen: stored bytes match the disk", reopened.value.stored_bytes() == _tree_bytes(absolute + "/objects"))
		check("reopen: draft loads", reopened.value.load_draft(ID_A).value.source_bytes == source)
		reopened.value.close()


func _test_two_instances() -> void:
	var root := _base + "/shared_in_process"
	var first: RefCounted = _open(root)
	if first == null:
		return
	var second_opened: Dictionary = Store.open(root)
	check("second instance opens", second_opened.ok)
	if not second_opened.ok:
		first.close()
		return
	var second: RefCounted = second_opened.value
	check("second instance is read-only and says why", not second.is_writer() and second.lock_status() == "busy"
		and second_opened.diagnostics.size() == 1 and second_opened.diagnostics[0].code == R.ROOT_LOCK_BUSY
		and second_opened.diagnostics[0].severity == R.SEVERITY_WARNING and not R.has_errors(second_opened.diagnostics))
	var saved: Dictionary = first.save_draft(_draft(ID_A, "Alpha", {"v": 1}, _bytes(300, 1), "a.stl"), "")
	check("first instance writes", saved.ok)
	var absolute := _abs(root)
	var before := _tree(absolute)
	check("second: save refused", _code(second.save_draft(_draft(ID_B, "Beta", {}, PackedByteArray(), ""), "")) == R.ROOT_LOCK_BUSY)
	check("second: recovery refused", _code(second.save_recovery(_draft(ID_B, "Beta", {}, PackedByteArray(), ""), "")) == R.ROOT_LOCK_BUSY)
	check("second: clear recovery refused", _code(second.clear_recovery(ID_A, "")) == R.ROOT_LOCK_BUSY)
	check("second: archive refused", _code(second.set_archived("draft", ID_A, true)) == R.ROOT_LOCK_BUSY)
	check("second: refused writes touch nothing", _tree(absolute) == before)
	check("second: holds the state it opened", second.generation() == 0 and second.list_drafts().is_empty())
	second.close()
	second_opened = Store.open(root)
	second = second_opened.value
	check("second sees the first's write after reopening", second_opened.ok and not second.is_writer() and second.generation() == 1
		and second.list_drafts().size() == 1 and second.load_draft(ID_A).ok)
	check("reader reports the stored bytes of the index", second.stored_bytes() == first.stored_bytes())
	second.close()
	var viewer: Dictionary = Store.open(root, {read_only = true})
	check("explicit read-only instance", viewer.ok and viewer.value.lock_status() == "read_only" and viewer.diagnostics.is_empty()
		and viewer.value.list_drafts().size() == 1)
	first.close()
	var taken: Dictionary = Store.open(root)
	check("the lock passes on after close", taken.ok and taken.value.is_writer())
	if taken.ok:
		taken.value.close()


func _test_recovery() -> void:
	var root := _base + "/recovery"
	var store: RefCounted = _open(root)
	if store == null:
		return
	var source := _bytes(900, 5)
	var named: Dictionary = store.save_draft(_draft(ID_A, "Alpha", {"edit": 1}, source, "a.stl"), "")
	var slot: Dictionary = store.save_recovery(_draft(ID_A, "Alpha", {"edit": 2}, source, "a.stl"), "")
	check("recovery saved", named.ok and slot.ok and slot.value.record_sha256 != named.value.record_sha256)
	check("recovery is not a named draft", store.list_drafts(true).size() == 1
		and store.list_drafts()[0].record_sha256 == named.value.record_sha256)
	var slots: Array = store.list_recovery()
	check("recovery listed", slots.size() == 1 and slots[0].draft_id == ID_A and slots[0].record_sha256 == slot.value.record_sha256
		and typeof(slots[0].updated_unix) == TYPE_INT and slots[0].updated_unix > 1700000000 and slots[0].keys().size() == 3)
	check("recovery and draft load independently", store.load_recovery(ID_A).value.snapshot.edit == 2.0
		and store.load_draft(ID_A).value.snapshot.edit == 1.0 and store.load_recovery(ID_A).value.record_sha256 == slot.value.record_sha256)
	var generation: int = store.generation()
	check("identical recovery is a no-op", store.save_recovery(_draft(ID_A, "Alpha", {"edit": 2}, source, "a.stl"),
		slot.value.record_sha256).value.record_sha256 == slot.value.record_sha256 and store.generation() == generation)
	check("recovery: must-not-exist conflicts", _code(store.save_recovery(_draft(ID_A, "Alpha", {"edit": 3}, source, "a.stl"), "")) == R.SAVE_CONFLICT)
	var newer: Dictionary = store.save_recovery(_draft(ID_A, "Alpha", {"edit": 3}, source, "a.stl"), slot.value.record_sha256)
	check("recovery replaced with the right hash", newer.ok)
	check("recovery: stale hash conflicts",
		_code(store.save_recovery(_draft(ID_A, "Alpha", {"edit": 4}, source, "a.stl"), slot.value.record_sha256)) == R.SAVE_CONFLICT)
	check("clear with a stale hash is refused", _code(store.clear_recovery(ID_A, slot.value.record_sha256)) == R.SAVE_CONFLICT
		and _code(store.clear_recovery(ID_A, "")) == R.SAVE_CONFLICT)
	check("the newer recovery survived", store.load_recovery(ID_A).value.snapshot.edit == 3.0)
	var orphan_slot: Dictionary = store.save_recovery(_draft(ID_B, "", {"new": true}, PackedByteArray(), ""), "")
	check("recovery of a draft that was never saved", orphan_slot.ok and store.load_recovery(ID_B).value.name == ""
		and _code(store.load_draft(ID_B)) == R.DEPENDENCY_MISSING)
	slots = store.list_recovery()
	var slot_ids: Array = slots.map(func(row: Dictionary) -> String: return row.draft_id)
	slot_ids.sort()
	check("the never-saved draft's backup is listed with its identity", slots.size() == 2 and slot_ids == [ID_A, ID_B]
		and store.load_recovery(str(slots[0].draft_id)).value.record_sha256 == slots[0].record_sha256
		and store.load_recovery(str(slots[1].draft_id)).value.record_sha256 == slots[1].record_sha256)
	check("recovery list is newest first", slots[0].updated_unix >= slots[1].updated_unix)
	var viewer: Dictionary = Store.open(root, {read_only = true})
	check("a read-only instance lists backups without reading blobs", viewer.ok and viewer.value.list_recovery() == slots)
	var cleared: Dictionary = store.clear_recovery(ID_A, newer.value.record_sha256)
	check("clear with the current hash", cleared.ok and _code(store.load_recovery(ID_A)) == R.DEPENDENCY_MISSING)
	check("a cleared backup leaves the list", store.list_recovery().size() == 1 and store.list_recovery()[0].draft_id == ID_B
		and store.list_recovery()[0].record_sha256 == orphan_slot.value.record_sha256)
	generation = store.generation()
	check("clearing an empty slot is success without a write", store.clear_recovery(ID_A, newer.value.record_sha256).ok
		and store.generation() == generation)
	check("the named draft is untouched", store.load_draft(ID_A).value.snapshot.edit == 1.0)
	check("cleared recovery keeps its bytes", not _object(_abs(root), newer.value.record_sha256).is_empty())
	store.close()
	var reopened: RefCounted = _open(root)
	if reopened != null:
		check("recovery persists", reopened.load_recovery(ID_B).ok and _code(reopened.load_recovery(ID_A)) == R.DEPENDENCY_MISSING
			and reopened.list_recovery().size() == 1 and reopened.list_recovery()[0].draft_id == ID_B)
		reopened.close()


# --- Published aircraft -----------------------------------------------------------------------

func _test_aircraft() -> void:
	var uuid: String = Authoring.new_uuid()
	var definition: Dictionary = Definition.template()
	definition["aircraft_uuid"] = uuid
	var compiled: Dictionary = Compiler.compile_candidate(definition)
	check("the template compiles for publication", compiled.ok)
	if not compiled.ok:
		print(R.texts(compiled))
		return
	var raw: PackedByteArray = compiled.value.raw_bytes()
	var normal: Dictionary = Definition.validate_complete(definition).value
	var source := _bytes(4000, 21)
	var root := _base + "/aircraft"
	var absolute := _abs(root)
	var store: RefCounted = _open(root)
	if store == null:
		return
	var publication := {aircraft_uuid = uuid, name = "Trainer", definition = normal, raw_bytes = raw, source_bytes = source,
		source_file_name = "trainer.glb", placement = {"scale": 0.001, "axes": ["x", "z"], "datum": [0.1, 0, 0]},
		bindings = {}, appearance = {"mode": "original"}, snapshot = {"step": "review_test"}}
	check("first publication with a stale revision conflicts", _code(store.publish_aircraft(publication, 1)) == R.SAVE_CONFLICT)
	var first: Dictionary = store.publish_aircraft(publication, 0)
	check("revision 1 published", first.ok and first.value.revision == 1 and first.value.aircraft_uuid == uuid
		and first.value.generation == 1)
	if not first.ok:
		print(R.texts(first))
		store.close()
		return
	check("repeating the publication conflicts instead of adding a revision",
		_code(store.publish_aircraft(publication, 0)) == R.SAVE_CONFLICT and store.list_aircraft()[0].revisions == 1)
	var listed: Array = store.list_aircraft()
	check("aircraft listed", listed.size() == 1 and listed[0].aircraft_uuid == uuid and listed[0].name == "Trainer"
		and listed[0].revision == 1 and listed[0].revisions == 1 and listed[0].record_sha256 == first.value.record_sha256
		and listed[0].archived == false and listed[0].created_unix > 1700000000)
	var loaded: Dictionary = store.load_aircraft(uuid)
	check("aircraft loads", loaded.ok)
	if loaded.ok:
		var value: Dictionary = loaded.value
		check("aircraft: exact compiled bytes", value.raw_bytes == raw and value.raw_sha256 == CreatorBytes.sha256(raw))
		check("aircraft: exact source bytes", value.source_bytes == source and value.source_file_name == "trainer.glb")
		check("aircraft: definition", value.definition.aircraft_uuid == uuid and value.definition.wing.span == 1.5
			and CreatorBytes.encode(value.definition).value.bytes == value.definition_bytes
			and value.definition_sha256 == CreatorBytes.sha256(value.definition_bytes))
		check("aircraft: definition identity is the compiler's", value.definition_sha256 == compiled.value.definition_sha256())
		check("aircraft: members", value.placement == {"scale": 0.001, "axes": ["x", "z"], "datum": [0.1, 0.0, 0.0]}
			and value.bindings == {} and value.appearance == {"mode": "original"} and value.snapshot == {"step": "review_test"})
		check("aircraft: identity fields", value.aircraft_uuid == uuid and value.revision == 1 and value.name == "Trainer"
			and value.record_sha256 == first.value.record_sha256 and value.created_unix == listed[0].created_unix)
		check("aircraft: stored bytes still load as this aircraft", Store._aircraft_bytes_problem(value.raw_bytes, uuid).is_empty())
	var record: Dictionary = CreatorBytes.decode(_object(absolute, first.value.record_sha256), Store.AIRCRAFT_INTEGERS, Limits.DRAFT_BYTES)
	check("aircraft record: closed keys and blob references", record.ok and record.value.data.keys().size() == Store.AIRCRAFT_KEYS.size()
		and record.value.data.aircraft.sha256 == CreatorBytes.sha256(raw) and record.value.data.aircraft.media_type == Store.MEDIA_AIRCRAFT
		and record.value.data.definition.media_type == Store.MEDIA_DEFINITION and record.value.data.source.byte_length == source.size())

	var second_publication: Dictionary = publication.duplicate(true)
	second_publication["name"] = "Trainer mk2"
	second_publication["snapshot"] = {"step": "review_test", "edit": 2}
	check("stale expected revision conflicts", _code(store.publish_aircraft(second_publication, 0)) == R.SAVE_CONFLICT
		and _code(store.publish_aircraft(second_publication, 2)) == R.SAVE_CONFLICT)
	var second: Dictionary = store.publish_aircraft(second_publication, 1)
	check("revision 2 published", second.ok and second.value.revision == 2)
	listed = store.list_aircraft()
	check("list shows the current revision", listed.size() == 1 and listed[0].revision == 2 and listed[0].revisions == 2
		and listed[0].name == "Trainer mk2" and listed[0].record_sha256 == second.value.record_sha256)
	check("history stays loadable", store.load_aircraft(uuid, 1).value.name == "Trainer" and store.load_aircraft(uuid, 2).value.name == "Trainer mk2"
		and store.load_aircraft(uuid).value.revision == 2 and store.load_aircraft(uuid, 1).value.record_sha256 == first.value.record_sha256)
	check("missing revision and aircraft are reported", _code(store.load_aircraft(uuid, 3)) == R.DEPENDENCY_MISSING
		and _code(store.load_aircraft(uuid, -1)) == R.DEPENDENCY_MISSING and _code(store.load_aircraft(ID_D)) == R.DEPENDENCY_MISSING)

	var before := _tree(absolute)
	var generation: int = store.generation()
	var other_uuid: String = Authoring.new_uuid()
	var refusals := {}
	var wrong_uuid: Dictionary = publication.duplicate(true)
	wrong_uuid["aircraft_uuid"] = other_uuid
	wrong_uuid["definition"] = {}
	refusals["compiled bytes of another aircraft"] = wrong_uuid
	var wrong_definition: Dictionary = publication.duplicate(true)
	wrong_definition["definition"]["aircraft_uuid"] = other_uuid
	refusals["definition of another aircraft"] = wrong_definition
	var upper: Dictionary = publication.duplicate(true)
	upper["aircraft_uuid"] = uuid.to_upper()
	refusals["upper-case uuid"] = upper
	var not_aircraft: Dictionary = publication.duplicate(true)
	not_aircraft["raw_bytes"] = ('{"format":"openrc-aircraft v2","model":{"id":"user-aircraft-%s"}}' % uuid).to_utf8_buffer()
	refusals["a record that is no aircraft"] = not_aircraft
	var stock: Dictionary = publication.duplicate(true)
	stock["raw_bytes"] = FileAccess.get_file_as_bytes("res://data/aircraft/jensen_ugly_stik_60.json")
	refusals["a stock aircraft's bytes"] = stock
	var garbage: Dictionary = publication.duplicate(true)
	garbage["raw_bytes"] = PackedByteArray([0x7B, 0x22, 0xFF, 0xFE, 0x00, 0x22, 0x3A, 0x31, 0x65, 0x39, 0x39, 0x39, 0x7D])
	refusals["bytes that are not text"] = garbage
	var overflow: Dictionary = publication.duplicate(true)
	overflow["raw_bytes"] = '{"format":"openrc-aircraft v2","mass":1e999}'.to_utf8_buffer()
	refusals["a record with an overflowing number"] = overflow
	var empty_raw: Dictionary = publication.duplicate(true)
	empty_raw["raw_bytes"] = PackedByteArray()
	refusals["no compiled bytes"] = empty_raw
	var no_source: Dictionary = publication.duplicate(true)
	no_source["source_bytes"] = PackedByteArray()
	refusals["no model file"] = no_source
	var unnamed: Dictionary = publication.duplicate(true)
	unnamed["name"] = ""
	refusals["no name"] = unnamed
	var path_name: Dictionary = publication.duplicate(true)
	path_name["source_file_name"] = "/home/pilot/trainer.glb"
	refusals["a path as file name"] = path_name
	var bad_member: Dictionary = publication.duplicate(true)
	bad_member["placement"] = {"scale": INF}
	refusals["a non-finite placement"] = bad_member
	var missing_member: Dictionary = publication.duplicate(true)
	missing_member.erase("bindings")
	refusals["a missing member"] = missing_member
	for label: String in refusals:
		var expected_revision := 0 if label in ["compiled bytes of another aircraft"] else 2
		check("publication refused: " + label, _code(store.publish_aircraft(refusals[label], expected_revision)) == R.RECORD_INVALID)
	check("refused publications change nothing", store.generation() == generation and _tree(absolute) == before
		and store.list_aircraft().size() == 1)
	check("stock bytes exist for the test", not (stock["raw_bytes"] as PackedByteArray).is_empty())
	store.close()
	var reopened: RefCounted = _open(root)
	if reopened != null:
		check("published aircraft persist", reopened.list_aircraft()[0].revisions == 2 and reopened.load_aircraft(uuid, 1).value.raw_bytes == raw)
		reopened.close()


# --- Archive and quota ------------------------------------------------------------------------

func _test_archive() -> void:
	var root := _base + "/aircraft"
	var absolute := _abs(root)
	var store: RefCounted = _open(root)
	if store == null:
		return
	check("archive: the published aircraft is there", store.list_aircraft().size() == 1)
	if store.list_aircraft().is_empty():
		store.close()
		return
	var uuid: String = store.list_aircraft()[0].aircraft_uuid
	var record_sha: String = store.list_aircraft()[0].record_sha256
	var draft: Dictionary = store.save_draft(_draft(ID_A, "Alpha", {"v": 1}, _bytes(200, 3), "a.stl"), "")
	var objects := _objects(absolute)
	var hidden: Dictionary = store.set_archived("aircraft", uuid, true)
	check("aircraft archived", hidden.ok and hidden.value.archived == true and store.list_aircraft().is_empty())
	check("archived aircraft is listed on request", store.list_aircraft(true).size() == 1 and store.list_aircraft(true)[0].archived == true
		and store.list_aircraft(true)[0].record_sha256 == record_sha)
	check("archived aircraft still loads, every revision", store.load_aircraft(uuid).ok and store.load_aircraft(uuid, 1).ok)
	var generation: int = store.generation()
	check("archiving twice writes nothing", store.set_archived("aircraft", uuid, true).ok and store.generation() == generation)
	check("draft archived", store.set_archived("draft", ID_A, true).ok and store.list_drafts().is_empty()
		and store.list_drafts(true)[0].archived == true and store.load_draft(ID_A).ok)
	var kept: Dictionary = store.save_draft(_draft(ID_A, "Alpha", {"v": 2}, _bytes(200, 3), "a.stl"), draft.value.record_sha256)
	check("saving an archived draft keeps it archived", kept.ok and store.list_drafts().is_empty())
	check("archive deletes nothing", _contains_all(_objects(absolute), objects))
	check("aircraft restored", store.set_archived("aircraft", uuid, false).ok and store.list_aircraft().size() == 1
		and store.list_aircraft()[0].record_sha256 == record_sha and store.list_aircraft()[0].revisions == 2)
	check("draft restored", store.set_archived("draft", ID_A, false).ok and store.list_drafts().size() == 1
		and store.list_drafts()[0].record_sha256 == kept.value.record_sha256)
	check("unknown entries and kinds are refused", _code(store.set_archived("draft", ID_D, true)) == R.DEPENDENCY_MISSING
		and _code(store.set_archived("aircraft", ID_D, true)) == R.DEPENDENCY_MISSING
		and _code(store.set_archived("skin", ID_A, true)) == R.RECORD_INVALID)
	store.close()


func _test_quota() -> void:
	var root := _base + "/quota"
	var absolute := _abs(root)
	var store: RefCounted = _open(root)
	if store == null:
		return
	var source := _bytes(2000, 9)
	var named: Dictionary = store.save_draft(_draft(ID_A, "Alpha", {"edit": 0}, source, "a.stl"), "")
	var used: int = store.stored_bytes()
	check("stored bytes are the bytes on disk", named.ok and used == _tree_bytes(absolute + "/objects"))
	store.close()

	var quota := used + 6000
	var opened: Dictionary = Store.open(root, {quota_bytes = quota})
	check("store opens with a quota", opened.ok and opened.value.quota_bytes() == quota)
	if not opened.ok:
		return
	store = opened.value
	var before := _tree(absolute)
	var generation: int = store.generation()
	var too_big: Dictionary = store.save_draft(_draft(ID_B, "Beta", {}, _bytes(8000, 4), "b.stl"), "")
	check("a write that would cross the quota is refused", _code(too_big) == R.STORAGE_QUOTA and too_big.diagnostics[0].arguments.size() == 3)
	check("refused before anything is written", _tree(absolute) == before and store.generation() == generation
		and store.stored_bytes() == used and not store.needs_reopen())
	check("the previous state is intact", store.load_draft(ID_A).value.source_bytes == source and store.list_drafts().size() == 1)
	var grown: Dictionary = store.save_draft(_draft(ID_B, "Beta", {}, _bytes(8000, 4), "b.stl"), "")
	check("the same write is refused again", _code(grown) == R.STORAGE_QUOTA and _tree(absolute) == before)

	# Recovery saves near the quota: each one adds a record and an index until one no longer fits.
	var slot_sha := ""
	var accepted := 0
	var refused := false
	for edit: int in range(1, 40):
		var slot: Dictionary = store.save_recovery(_draft(ID_A, "Alpha", {"edit": edit}, source, "a.stl"), slot_sha)
		if slot.ok:
			slot_sha = slot.value.record_sha256
			accepted = edit
			continue
		refused = _code(slot) == R.STORAGE_QUOTA
		break
	check("recovery saves fit until the quota", accepted >= 2 and refused)
	check("stored bytes never pass the quota", store.stored_bytes() <= quota and _tree_bytes(absolute + "/objects") <= quota)
	before = _tree(absolute)
	generation = store.generation()
	for attempt: int in 3:
		refused = refused and _code(store.save_recovery(_draft(ID_A, "Alpha", {"edit": 100 + attempt}, source, "a.stl"), slot_sha)) == R.STORAGE_QUOTA
	check("repeated recovery saves at the quota write nothing", refused and _tree(absolute) == before and store.generation() == generation)
	check("the last accepted recovery is intact", store.load_recovery(ID_A).value.snapshot.edit == float(accepted)
		and store.load_recovery(ID_A).value.record_sha256 == slot_sha)
	check("the named draft is intact", store.load_draft(ID_A).value.snapshot.edit == 0.0)
	store.close()

	opened = Store.open(root, {quota_bytes = quota})
	check("reopening at the quota shows the same state", opened.ok and opened.value.generation() == generation
		and opened.value.load_recovery(ID_A).value.record_sha256 == slot_sha)
	if opened.ok:
		opened.value.close()
	store = _open(root)
	if store != null:
		var later: Dictionary = store.save_recovery(_draft(ID_A, "Alpha", {"edit": 500}, source, "a.stl"), slot_sha)
		check("a larger quota accepts the save", later.ok and _contains_all(_objects(absolute), before.keys().filter(
			func(path: String) -> bool: return path.begins_with("objects/"))))
		store.close()


# --- Fault stages -----------------------------------------------------------------------------

func _test_fault_stages() -> void:
	var root := _base + "/faults"
	var absolute := _abs(root)
	var store: RefCounted = _open(root)
	if store == null:
		return
	check("every documented stage is listed", Store.FAULT_STAGES.size() == 12 and not store.set_fault_stage("nowhere"))
	var edit := 1
	var saved: Dictionary = store.save_draft(_draft(ID_A, "Alpha", {"edit": edit}, _bytes(1200, edit), "a.stl"), "")
	var accepted_sha: String = saved.value.record_sha256
	for stage: String in Store.FAULT_STAGES:
		var old_edit := edit
		var old_generation: int = store.generation()
		var old_objects := _objects(absolute)
		edit += 1
		check("%s: stage armed" % stage, store.set_fault_stage(stage))
		var crashed: Dictionary = store.save_draft(_draft(ID_A, "Alpha", {"edit": edit}, _bytes(1200, edit), "a.stl"), accepted_sha)
		check("%s: the save reports a failure" % stage, _code(crashed) == R.WRITE_FAILED and store.needs_reopen())
		check("%s: uncertain outcome is marked only where it is one" % stage,
			bool(crashed.get("uncertain", false)) == (stage == Store.FAULT_READBACK_LOST))
		check("%s: the instance refuses further writes" % stage,
			_code(store.save_draft(_draft(ID_B, "Beta", {}, PackedByteArray(), ""), "")) == R.WRITE_FAILED
			and _code(store.set_archived("draft", ID_A, true)) == R.WRITE_FAILED)
		store.close()
		var reopened: Dictionary = Store.open(root)
		check("%s: reopens" % stage, reopened.ok)
		if not reopened.ok:
			print(R.texts(reopened))
			return
		store = reopened.value
		var committed := Store.FAULT_STAGES_COMMITTED.has(stage)
		var now: Dictionary = store.load_draft(ID_A)
		if committed:
			check("%s: exactly the new state" % stage, now.ok and now.value.snapshot.edit == float(edit)
				and now.value.source_bytes == _bytes(1200, edit) and store.generation() == old_generation + 1
				and store.list_drafts().size() == 1 and now.value.record_sha256 != accepted_sha)
		else:
			check("%s: exactly the old state" % stage, now.ok and now.value.snapshot.edit == float(old_edit)
				and now.value.source_bytes == _bytes(1200, old_edit) and store.generation() == old_generation
				and store.list_drafts().size() == 1 and now.value.record_sha256 == accepted_sha)
		var from_previous: bool = stage == Store.FAULT_MID_CURRENT_REPLACE
		check("%s: restoring from the previous pointer is reported only when it happened" % stage,
			store.recovered_from_previous() == from_previous and (reopened.diagnostics.size() == 1) == from_previous)
		check("%s: nothing accepted was lost" % stage, _contains_all(_objects(absolute), old_objects))
		check("%s: staging is cleared by the next writer" % stage, _files(absolute + "/staging").is_empty())
		check("%s: pointers agree with the accepted state" % stage, _pointer(absolute).generation == store.generation())
		accepted_sha = now.value.record_sha256
		edit += 1
		var next: Dictionary = store.save_draft(_draft(ID_A, "Alpha", {"edit": edit}, _bytes(1200, edit), "a.stl"), accepted_sha)
		check("%s: a later normal save works" % stage, next.ok and store.load_draft(ID_A).value.snapshot.edit == float(edit)
			and not store.needs_reopen() and not store.recovered_from_previous())
		if not next.ok:
			print(R.texts(next))
			store.close()
			return
		accepted_sha = next.value.record_sha256
	store.close()
	var armed: Dictionary = Store.open(root, {fault_stage = Store.FAULT_BEFORE_INDEX_WRITE})
	check("a stage can be armed when opening", armed.ok and _code(armed.value.set_archived("draft", ID_A, true)) == R.WRITE_FAILED
		and armed.value.needs_reopen())
	if armed.ok:
		armed.value.close()
	var clean: RefCounted = _open(root)
	if clean != null:
		check("an index-only transaction interrupted before its index changes nothing", clean.list_drafts().size() == 1
			and clean.load_draft(ID_A).value.record_sha256 == accepted_sha)
		clean.close()


# --- Tampering --------------------------------------------------------------------------------

func _test_tampering() -> void:
	# Flip a byte in an object the last transaction added.
	var seeded := _seed("tamper_flip_latest")
	var path := _object_path(seeded.absolute, seeded.a2)
	var bytes := _read(path)
	bytes[bytes.size() / 2] ^= 0x01
	_write(path, bytes)
	var current_bytes := _read(seeded.absolute + "/current.json")
	var opened: Dictionary = Store.open(seeded.root)
	check("flipped latest object: opens from the previous pointer and says so", opened.ok and opened.value.recovered_from_previous()
		and opened.diagnostics.size() == 1 and opened.diagnostics[0].code == R.WRITE_FAILED
		and opened.diagnostics[0].severity == R.SEVERITY_WARNING and opened.value.is_writer())
	if opened.ok:
		var store: RefCounted = opened.value
		check("flipped latest object: the state before the last change", store.generation() == 2
			and store.load_draft(ID_A).value.record_sha256 == seeded.a1 and store.load_draft(ID_B).ok)
		check("flipped latest object: damaged bytes preserved", _read(path) == bytes)
		check("flipped latest object: the refused pointer is kept aside", _has_bytes(seeded.absolute + "/damaged", current_bytes))
		var again: Dictionary = store.save_draft(_draft(ID_A, "Alpha", {"v": 2.0}, _bytes(650, 3), "alpha.stl"), seeded.a1)
		check("flipped latest object: saving the same content again repairs it", again.ok and again.value.record_sha256 == seeded.a2
			and store.load_draft(ID_A).ok and _has_bytes(seeded.absolute + "/damaged", bytes))
		store.close()
	var clean: Dictionary = Store.open(seeded.root)
	check("flipped latest object: the next open is clean", clean.ok and clean.diagnostics.is_empty() and clean.value.generation() == 3)
	if clean.ok:
		clean.value.close()

	# Flip a byte in an older object: only its own entry is affected.
	seeded = _seed("tamper_flip_old")
	path = _object_path(seeded.absolute, seeded.b1)
	bytes = _read(path)
	bytes[10] ^= 0x40
	_write(path, bytes)
	opened = Store.open(seeded.root)
	check("flipped older object: the store opens on its current state", opened.ok and not opened.value.recovered_from_previous()
		and opened.value.generation() == 3)
	if opened.ok:
		var store: RefCounted = opened.value
		var damaged: Dictionary = store.load_draft(ID_B)
		check("flipped older object: its draft is refused", _code(damaged) == R.RECORD_INVALID and not damaged.has("value"))
		check("flipped older object: other drafts load", store.load_draft(ID_A).ok)
		check("flipped older object: bytes preserved", _read(path) == bytes)
		var healed: Dictionary = store.save_draft(_draft(ID_B, "Beta", {"v": 1.0}, _bytes(700, 2), "beta.stl"), seeded.b1)
		check("flipped older object: identical save is still a no-op on the list", healed.ok and healed.value.record_sha256 == seeded.b1)
		var replaced: Dictionary = store.save_draft(_draft(ID_B, "Beta", {"v": 5.0}, _bytes(700, 2), "beta.stl"), seeded.b1)
		check("flipped older object: a new save replaces the damaged entry", replaced.ok and store.load_draft(ID_B).value.snapshot.v == 5.0)
		store.close()

	# Truncate a payload the last transaction added, and one it did not.
	seeded = _seed("tamper_truncate")
	var latest_source := CreatorBytes.sha256(_bytes(650, 3))
	_write(_object_path(seeded.absolute, latest_source), _bytes(650, 3).slice(0, 300))
	opened = Store.open(seeded.root)
	check("truncated latest payload: restored from the previous pointer", opened.ok and opened.value.recovered_from_previous()
		and opened.value.load_draft(ID_A).value.record_sha256 == seeded.a1)
	if opened.ok:
		opened.value.close()
	seeded = _seed("tamper_truncate_old")
	var old_source := CreatorBytes.sha256(_bytes(700, 2))
	_write(_object_path(seeded.absolute, old_source), _bytes(700, 2).slice(0, 699))
	opened = Store.open(seeded.root)
	check("truncated older payload: confined to its draft", opened.ok and not opened.value.recovered_from_previous()
		and _code(opened.value.load_draft(ID_B)) == R.RECORD_INVALID and opened.value.load_draft(ID_A).ok)
	if opened.ok:
		opened.value.close()

	# Delete objects.
	seeded = _seed("tamper_delete")
	var index_sha: String = _pointer(seeded.absolute).index.sha256
	DirAccess.remove_absolute(_object_path(seeded.absolute, index_sha))
	opened = Store.open(seeded.root, {read_only = true})
	var before := _tree(seeded.absolute)
	check("deleted index: a reader falls back in memory", opened.ok and opened.value.recovered_from_previous()
		and opened.value.generation() == 2 and opened.diagnostics.size() == 1)
	check("deleted index: a reader writes nothing", _tree(seeded.absolute) == before)
	opened = Store.open(seeded.root)
	check("deleted index: the writer restores the previous pointer", opened.ok and opened.value.recovered_from_previous()
		and opened.value.generation() == 2 and _read(seeded.absolute + "/current.json") == _read(seeded.absolute + "/previous.json"))
	if opened.ok:
		opened.value.close()
	seeded = _seed("tamper_delete_old")
	DirAccess.remove_absolute(_object_path(seeded.absolute, seeded.b1))
	opened = Store.open(seeded.root)
	check("deleted older record: the store still opens", opened.ok and opened.diagnostics.is_empty() and opened.value.list_drafts().size() == 2)
	if opened.ok:
		check("deleted older record: reported as missing", _code(opened.value.load_draft(ID_B)) == R.DEPENDENCY_MISSING
			and opened.value.load_draft(ID_A).ok)
		opened.value.close()

	# Corrupt current.json in many ways: each falls back to the valid previous pointer, quietly.
	seeded = _seed("tamper_pointer")
	var good_pointer := _read(seeded.absolute + "/current.json").get_string_from_utf8()
	var previous_generation: int = 2
	var hostile_pointers := {
		"garbage": "{{{ not json".to_utf8_buffer(),
		"empty file": PackedByteArray(),
		"binary": PackedByteArray([0xFF, 0xFE, 0x00, 0x01, 0x80]),
		"NUL bytes": PackedByteArray([0, 0, 0, 0]),
		"byte-order mark": _join(PackedByteArray([0xEF, 0xBB, 0xBF]), good_pointer.to_utf8_buffer()),
		"array": "[]\n".to_utf8_buffer(),
		"oversized": (good_pointer.strip_edges() + " ".repeat(Limits.STORE_POINTER_BYTES)).to_utf8_buffer(),
		"fractional generation": good_pointer.replace('"generation":3', '"generation":3.5').to_utf8_buffer(),
		"float generation": good_pointer.replace('"generation":3', '"generation":3.0').to_utf8_buffer(),
		"exponent generation": good_pointer.replace('"generation":3', '"generation":3e0').to_utf8_buffer(),
		"negative generation": good_pointer.replace('"generation":3', '"generation":-3').to_utf8_buffer(),
		"huge generation": good_pointer.replace('"generation":3', '"generation":9007199254740993').to_utf8_buffer(),
		"overflowing generation": good_pointer.replace('"generation":3', '"generation":1e999').to_utf8_buffer(),
		"endless digits": good_pointer.replace('"generation":3', '"generation":' + "9".repeat(400)).to_utf8_buffer(),
		"text generation": good_pointer.replace('"generation":3', '"generation":"3"').to_utf8_buffer(),
		"leading zero": good_pointer.replace('"generation":3', '"generation":03').to_utf8_buffer(),
		"other generation than its index": good_pointer.replace('"generation":3', '"generation":4').to_utf8_buffer(),
		"duplicate key": good_pointer.replace('"generation":3', '"generation":3,"generation":3').to_utf8_buffer(),
		"unknown key": good_pointer.replace('"generation":3', '"extra":1,"generation":3').to_utf8_buffer(),
		"missing key": good_pointer.replace('"generation":3,', '').to_utf8_buffer(),
		"wrong format": good_pointer.replace("pointer v1", "pointer v2").to_utf8_buffer(),
		"path as hash": good_pointer.replace(_index_sha_of(good_pointer), "../../../../outside/secret" + "a".repeat(38)).to_utf8_buffer(),
		"upper-case hash": good_pointer.replace(_index_sha_of(good_pointer), _index_sha_of(good_pointer).to_upper()).to_utf8_buffer(),
		"index length off by one": good_pointer.replace('"byte_length":', '"byte_length":1').to_utf8_buffer(),
		"wrong media type": good_pointer.replace("creator-index+json", "creator-draft+json").to_utf8_buffer(),
		"bad transaction id": good_pointer.replace('"transaction_id":"', '"transaction_id":"X').to_utf8_buffer(),
	}
	check("pointer fixtures differ from the good pointer", good_pointer.contains('"generation":3'))
	for label: String in hostile_pointers:
		var fixture: PackedByteArray = hostile_pointers[label]
		_write(seeded.absolute + "/current.json", fixture)
		opened = Store.open(seeded.root)
		var passed: bool = opened.ok and opened.value.recovered_from_previous() and opened.value.generation() == previous_generation \
			and opened.value.load_draft(ID_A).value.record_sha256 == seeded.a1
		if passed and not fixture.is_empty():
			passed = _has_bytes(seeded.absolute + "/damaged", fixture)
		check("hostile current.json falls back: " + label, passed)
		if opened.ok:
			opened.value.close()
	opened = Store.open(seeded.root)
	check("after the fallbacks: writable and clean", opened.ok and opened.diagnostics.is_empty() and opened.value.is_writer())
	if opened.ok:
		var written: Dictionary = opened.value.save_draft(_draft(ID_A, "Alpha", {"v": 9.0}, _bytes(600, 1), "alpha.stl"), seeded.a1)
		check("after the fallbacks: a save works", written.ok and opened.value.generation() == previous_generation + 1)
		opened.value.close()

	# Both pointers corrupt: refused, nothing written, nothing promoted.
	seeded = _seed("tamper_both")
	_write(seeded.absolute + "/current.json", "{}".to_utf8_buffer())
	_write(seeded.absolute + "/previous.json", '{"generation":1e999}'.to_utf8_buffer())
	before = _tree(seeded.absolute)
	opened = Store.open(seeded.root)
	check("both pointers corrupt: refused", not opened.ok and _code(opened) == R.RECORD_INVALID and not opened.has("value"))
	check("both pointers corrupt: every byte preserved", _tree(seeded.absolute) == before)
	var viewer: Dictionary = Store.open(seeded.root, {read_only = true})
	check("both pointers corrupt: refused for a reader too", not viewer.ok and _tree(seeded.absolute) == before)
	var lock: Dictionary = ProcessLock.acquire(seeded.absolute)
	check("both pointers corrupt: the lock was released", lock.status == "acquired")
	if lock.lock != null:
		lock.lock.release()
	DirAccess.remove_absolute(seeded.absolute + "/current.json")
	DirAccess.remove_absolute(seeded.absolute + "/previous.json")
	before = _tree(seeded.absolute)
	opened = Store.open(seeded.root)
	check("pointers deleted, objects present: refused, not reinitialized", not opened.ok and _tree(seeded.absolute) == before)

	# An orphan index with a higher generation is never promoted.
	seeded = _seed("tamper_orphan")
	var orphan: Dictionary = _index(seeded.absolute)
	orphan["generation"] = 999
	orphan["transaction_id"] = ID_D
	orphan["drafts"] = {}
	var orphan_written: Dictionary = CreatorBytes.encode(orphan)
	_write(_object_path(seeded.absolute, orphan_written.value.sha256), orphan_written.value.bytes)
	_write(seeded.absolute + "/pointer-999.json", _pointer_bytes(999, orphan_written.value, ID_D))
	_write(seeded.absolute + "/staging/leftover.tmp", _bytes(100, 1))
	opened = Store.open(seeded.root)
	check("orphan index: ignored", opened.ok and opened.diagnostics.is_empty() and opened.value.generation() == 3
		and opened.value.list_drafts().size() == 2)
	if opened.ok:
		check("orphan index: its bytes stay and count against the quota",
			FileAccess.file_exists(_object_path(seeded.absolute, orphan_written.value.sha256))
			and opened.value.stored_bytes() == _tree_bytes(seeded.absolute + "/objects"))
		check("stale staging file removed by the writer", not FileAccess.file_exists(seeded.absolute + "/staging/leftover.tmp"))
		opened.value.close()
	var lonely := _base + "/tamper_orphan_only"
	_write(_object_path(_abs(lonely), orphan_written.value.sha256), orphan_written.value.bytes)
	before = _tree(_abs(lonely))
	opened = Store.open(lonely)
	check("orphan index alone: not promoted and not overwritten", not opened.ok and _tree(_abs(lonely)) == before)

	# A first start that was interrupted after its index object is completed.
	var interrupted := _base + "/tamper_first_start"
	var genesis: Dictionary = Store._genesis()
	_write(_object_path(_abs(interrupted), genesis.index_sha256), genesis.index_bytes)
	opened = Store.open(interrupted)
	check("interrupted first start: completed", opened.ok and opened.value.is_writer() and opened.value.generation() == 0
		and FileAccess.file_exists(_abs(interrupted) + "/current.json"))
	if opened.ok:
		opened.value.close()

	# A stale instance never overwrites: the pointer moved under it.
	seeded = _seed("tamper_stale")
	var stale: RefCounted = _open(seeded.root)
	if stale != null:
		var older := _read(seeded.absolute + "/previous.json")
		_write(seeded.absolute + "/current.json", older)
		before = _tree(seeded.absolute)
		var conflict: Dictionary = stale.save_draft(_draft(ID_A, "Alpha", {"v": 7.0}, _bytes(650, 3), "alpha.stl"), seeded.a2)
		check("stale instance: conflict", _code(conflict) == R.SAVE_CONFLICT)
		check("stale instance: nothing overwritten", _tree(seeded.absolute) == before)
		check("stale instance: every other mutation conflicts too", _code(stale.set_archived("draft", ID_B, true)) == R.SAVE_CONFLICT
			and _code(stale.save_recovery(_draft(ID_B, "", {}, PackedByteArray(), ""), "")) == R.SAVE_CONFLICT)
		stale.close()
		var fresh: RefCounted = _open(seeded.root)
		if fresh != null:
			check("stale instance: a reopened store continues from the disk", fresh.generation() == 2
				and fresh.save_draft(_draft(ID_A, "Alpha", {"v": 7.0}, _bytes(650, 3), "alpha.stl"), seeded.a1).ok)
			fresh.close()

	# A folder of the store that is a file.
	var blocked := _base + "/tamper_tree"
	_write(_abs(blocked) + "/objects", _bytes(10, 1))
	opened = Store.open(blocked)
	check("objects folder that is a file: refused", not opened.ok and _code(opened) == R.WRITE_FAILED)


func _index_sha_of(pointer_text: String) -> String:
	var at := pointer_text.find('"sha256":"') + 10
	return pointer_text.substr(at, 64)


# --- Forged but hash-consistent records --------------------------------------------------------

func _test_forged_records() -> void:
	# Each forgery is a complete chain: record -> index -> pointer, all hashes right. Only the
	# schema checks can refuse it. The forged index names a predecessor that does not exist, so the
	# open cannot tell which records are new and the record checks run when the entry is loaded.
	var seeded := _seed("forged")
	var absolute: String = seeded.absolute
	var honest_pointer := _read(absolute + "/current.json")
	var honest: Dictionary = _index(absolute)
	var honest_record: Dictionary = CreatorBytes.decode(_object(absolute, seeded.a2), Store.DRAFT_INTEGERS, Limits.DRAFT_BYTES).value.data

	var record_forgeries := {
		"unknown key": func(record: Dictionary) -> void: record["path"] = "C:/Users/pilot/model.stl",
		"missing key": func(record: Dictionary) -> void: record.erase("snapshot"),
		"wrong format": func(record: Dictionary) -> void: record["format"] = "openrc-creator-draft v2",
		"path-like file name": func(record: Dictionary) -> void: record["source_file_name"] = "../../outside/model.stl",
		"URL file name": func(record: Dictionary) -> void: record["source_file_name"] = "file:///etc/passwd",
		"oversized name": func(record: Dictionary) -> void: record["name"] = "n".repeat(Limits.NAME_CHARACTERS + 1),
		"another draft's identity": func(record: Dictionary) -> void: record["draft_id"] = ID_B,
		"another name than the list": func(record: Dictionary) -> void: record["name"] = "Mallory",
		"source hash that is a path": func(record: Dictionary) -> void: record["source"]["sha256"] = "../" + "a".repeat(61),
		"source larger than any model": func(record: Dictionary) -> void: record["source"]["byte_length"] = Limits.MODEL_SOURCE_BYTES + 1,
		"source of another media type": func(record: Dictionary) -> void: record["source"]["media_type"] = "text/html",
		"source reference with an extra key": func(record: Dictionary) -> void: record["source"]["url"] = "https://example.org/m.stl",
		"source that is missing": func(record: Dictionary) -> void: record["source"]["sha256"] = SHA_NOWHERE,
		"snapshot that is a list": func(record: Dictionary) -> void: record["snapshot"] = [],
	}
	for label: String in record_forgeries:
		var record: Dictionary = honest_record.duplicate(true)
		(record_forgeries[label] as Callable).call(record)
		var written: Dictionary = CreatorBytes.encode(record, Limits.DRAFT_BYTES)
		_write(_object_path(absolute, written.value.sha256), written.value.bytes)
		var index: Dictionary = _next(honest)
		index["drafts"][ID_A]["record"] = {"sha256": written.value.sha256, "byte_length": written.value.bytes.size(), "media_type": Store.MEDIA_DRAFT}
		_forge(absolute, index)
		var opened: Dictionary = Store.open(seeded.root, {read_only = true})
		var passed: bool = opened.ok and not opened.value.recovered_from_previous() and opened.value.generation() == 4
		if passed:
			var loaded: Dictionary = opened.value.load_draft(ID_A)
			passed = not loaded.ok and not loaded.has("value") and _code(loaded) in [R.RECORD_INVALID, R.DEPENDENCY_MISSING] \
				and opened.value.load_draft(ID_B).ok
		check("forged draft record refused when loaded: " + label, passed)

	# The same forgeries as the last transaction of an honest chain: refused when opening.
	var forged_record: Dictionary = honest_record.duplicate(true)
	forged_record["unknown"] = true
	var forged_written: Dictionary = CreatorBytes.encode(forged_record, Limits.DRAFT_BYTES)
	_write(_object_path(absolute, forged_written.value.sha256), forged_written.value.bytes)
	var honest_reference: Dictionary = _pointer_of(honest_pointer).index
	var chained: Dictionary = _next(honest, honest_reference)
	chained["drafts"][ID_A]["record"] = {"sha256": forged_written.value.sha256, "byte_length": forged_written.value.bytes.size(), "media_type": Store.MEDIA_DRAFT}
	_forge(absolute, chained)
	var refused: Dictionary = Store.open(seeded.root, {read_only = true})
	check("forged record in the last transaction: current pointer refused, previous used",
		refused.ok and refused.value.recovered_from_previous() and refused.value.generation() == 2)
	var ghost := {"name": "Ghost", "aircraft_uuid": "", "archived": false, "updated_unix": 1700000000,
		"record": {"sha256": SHA_NOWHERE, "byte_length": 321, "media_type": Store.MEDIA_DRAFT}}
	var missing: Dictionary = _next(honest, honest_reference)
	missing["drafts"][ID_C] = ghost
	_forge(absolute, missing)
	refused = Store.open(seeded.root, {read_only = true})
	check("index naming a missing blob in the last transaction: previous used",
		refused.ok and refused.value.recovered_from_previous() and refused.value.generation() == 2)
	missing = _next(honest)
	missing["drafts"][ID_C] = ghost
	_forge(absolute, missing)
	var confined: Dictionary = Store.open(seeded.root, {read_only = true})
	check("index naming a missing blob elsewhere: only that entry fails", confined.ok and not confined.value.recovered_from_previous()
		and confined.value.list_drafts().size() == 3 and _code(confined.value.load_draft(ID_C)) == R.DEPENDENCY_MISSING
		and confined.value.load_draft(ID_B).ok)

	# Forged indexes: hash-consistent with their pointer, refused by the index schema.
	var index_forgeries := {
		"unknown key": func(index: Dictionary) -> void: index["note"] = "x",
		"missing key": func(index: Dictionary) -> void: index.erase("recovery"),
		"wrong format": func(index: Dictionary) -> void: index["format"] = "openrc-creator-index v9",
		"draft key that is a path": func(index: Dictionary) -> void: index["drafts"]["../../escape"] = index["drafts"][ID_A],
		"draft key in upper case": func(index: Dictionary) -> void: index["drafts"][ID_C.to_upper()] = index["drafts"][ID_A],
		"draft with an unknown key": func(index: Dictionary) -> void: index["drafts"][ID_A]["path"] = "x",
		"draft without a name": func(index: Dictionary) -> void: index["drafts"][ID_A]["name"] = "",
		"draft with an oversized name": func(index: Dictionary) -> void: index["drafts"][ID_A]["name"] = "n".repeat(Limits.NAME_CHARACTERS + 1),
		"draft with a control character in its name": func(index: Dictionary) -> void: index["drafts"][ID_A]["name"] = "a\tb",
		"draft archived as text": func(index: Dictionary) -> void: index["drafts"][ID_A]["archived"] = "no",
		"record hash that is a path": func(index: Dictionary) -> void: index["drafts"][ID_A]["record"]["sha256"] = "..%2F" + "b".repeat(59),
		"record larger than any draft": func(index: Dictionary) -> void: index["drafts"][ID_A]["record"]["byte_length"] = Limits.DRAFT_BYTES + 1,
		"record of length zero": func(index: Dictionary) -> void: index["drafts"][ID_A]["record"]["byte_length"] = 0,
		"record of the wrong media type": func(index: Dictionary) -> void: index["drafts"][ID_A]["record"]["media_type"] = Store.MEDIA_SOURCE,
		"recovery with an unknown key": func(index: Dictionary) -> void: index["recovery"][ID_A] = {"record": index["drafts"][ID_A]["record"], "updated_unix": 1, "name": "x"},
		"aircraft without revisions": func(index: Dictionary) -> void: index["aircraft"][ID_C] = {"name": "X", "archived": false, "current_revision": 0, "revisions": []},
		"aircraft whose current revision is not its last": func(index: Dictionary) -> void: index["aircraft"][ID_C] = {"name": "X", "archived": false, "current_revision": 2,
			"revisions": [{"revision": 1, "created_unix": 1, "record": {"sha256": SHA_NOWHERE, "byte_length": 9, "media_type": Store.MEDIA_REVISION}}]},
		"aircraft with a gap in its revisions": func(index: Dictionary) -> void: index["aircraft"][ID_C] = {"name": "X", "archived": false, "current_revision": 1,
			"revisions": [{"revision": 2, "created_unix": 1, "record": {"sha256": SHA_NOWHERE, "byte_length": 9, "media_type": Store.MEDIA_REVISION}}]},
		"no predecessor after the first generation": func(index: Dictionary) -> void: index["predecessor"] = null,
		"negative stored bytes": func(index: Dictionary) -> void: index["stored_bytes"] = -1,
		"generation other than the pointer's": func(index: Dictionary) -> void: index["generation"] = 5,
		"transaction other than the pointer's": func(index: Dictionary) -> void: index["transaction_id"] = ID_C,
	}
	for label: String in index_forgeries:
		var index: Dictionary = _next(honest)
		(index_forgeries[label] as Callable).call(index)
		var forged := _forge(absolute, index)
		var opened: Dictionary = Store.open(seeded.root, {read_only = true})
		check("forged index refused: " + label, forged and opened.ok and opened.value.recovered_from_previous()
			and opened.value.generation() == 2 and opened.value.load_draft(ID_A).value.record_sha256 == seeded.a1)
	# Number spellings and duplicate keys cannot be produced by the writer: raw index text.
	var honest_text := _object(absolute, _pointer_of(honest_pointer).index.sha256).get_string_from_utf8()
	var raw_forgeries := {
		"duplicate key": honest_text.replace('"generation":3', '"generation":3,"generation":3'),
		"fractional generation": honest_text.replace('"generation":3', '"generation":3.0'),
		"overflowing stored bytes": honest_text.replace('"stored_bytes":', '"stored_bytes":1e999,"x":'),
		"fractional time": honest_text.replace('"updated_unix":', '"updated_unix":0.5,"y":'),
		"invalid text": honest_text.replace("Alpha", "Al#pha"),
	}
	check("raw index fixtures differ from the honest index", honest_text.contains('"generation":3') and honest_text.contains("Alpha"))
	for label: String in raw_forgeries:
		var raw: PackedByteArray = str(raw_forgeries[label]).to_utf8_buffer()
		if label == "invalid text":
			raw[raw.find(0x23)] = 0xFF
		var written := {"sha256": CreatorBytes.sha256(raw), "bytes": raw}
		_write(_object_path(absolute, written.sha256), raw)
		_write(absolute + "/current.json", _pointer_bytes(3, written, _pointer_of(honest_pointer).transaction_id))
		var opened: Dictionary = Store.open(seeded.root, {read_only = true})
		check("forged index text refused: " + label, opened.ok and opened.value.recovered_from_previous() and opened.value.generation() == 2)

	# The honest pointer still works: nothing above changed an accepted object.
	_write(absolute + "/current.json", honest_pointer)
	var restored: Dictionary = Store.open(seeded.root)
	check("the honest pointer is still valid after every forgery", restored.ok and restored.diagnostics.is_empty()
		and restored.value.generation() == 3 and restored.value.load_draft(ID_A).value.record_sha256 == seeded.a2)
	if restored.ok:
		restored.value.close()


# --- Two real processes -----------------------------------------------------------------------

func _test_processes() -> void:
	var root := _base + "/two_processes"
	var absolute := _abs(root)
	var held: Dictionary = ProcessLock.acquire(absolute)
	check("processes: this process holds the lock", held.status == "acquired")
	var second := _peer(root, "try", ID_C, 20)
	var report := _await_report(second, 40.0)
	check("processes: the second process ran", report.get("opened") == true)
	check("processes: the second process sees busy while the first holds", report.get("lock_status") == "busy" and report.get("writer") == false)
	check("processes: the second process cannot save", report.get("save") == R.ROOT_LOCK_BUSY)
	check("processes: the second process wrote nothing", not FileAccess.file_exists(absolute + "/current.json"))
	if held.lock != null:
		held.lock.release()

	var holder := _peer(root, "hold", ID_D, 40)
	report = _await_report(holder, 40.0)
	check("processes: a new process becomes the writer after the release", report.get("writer") == true
		and report.get("lock_status") == "acquired" and report.get("save") == "ok")
	var refused: Dictionary = ProcessLock.acquire(absolute)
	check("processes: this process now sees busy", refused.status == "busy" and refused.lock == null
		and ProcessLock.candidate_ports(absolute).has(int(refused.port)))
	var viewer: Dictionary = Store.open(root)
	check("processes: the store opens read-only beside the other writer", viewer.ok and not viewer.value.is_writer()
		and viewer.value.lock_status() == "busy")
	if viewer.ok:
		check("processes: the other process's commit is readable", viewer.value.load_draft(ID_D).ok
			and viewer.value.load_draft(ID_D).value.source_bytes == PackedByteArray([7, 7, 7]))
		check("processes: saving here is refused", _code(viewer.value.save_draft(_draft(ID_A, "A", {}, PackedByteArray(), ""), "")) == R.ROOT_LOCK_BUSY)
		viewer.value.close()

	# Kill the holder: no clean release. The OS closes its listener.
	var killed := OS.kill(int(holder.pid))
	var regained: Dictionary = {}
	var deadline := Time.get_ticks_msec() + 15000
	var waited := Time.get_ticks_msec()
	while Time.get_ticks_msec() < deadline:
		regained = ProcessLock.acquire(absolute)
		if regained.status == "acquired":
			break
		OS.delay_msec(100)
	check("processes: the lock is free after the holder is killed", killed == OK and regained.get("status") == "acquired")
	print("  lock regained %d ms after the kill" % (Time.get_ticks_msec() - waited))
	if regained.get("lock") != null:
		regained.lock.release()
	var writer: RefCounted = _open(root)
	if writer != null:
		check("processes: the killed writer's commit is the accepted state", writer.is_writer() and writer.generation() == 1
			and writer.load_draft(ID_D).ok)
		check("processes: this process writes again", writer.save_draft(_draft(ID_A, "A", {}, PackedByteArray(), ""), "").ok)
		writer.close()


## Starts the pinned engine as a second process on the peer script.
func _peer(root: String, mode: String, draft_id: String, seconds: int) -> Dictionary:
	_peers += 1
	var out := "%s/peer_%d.json" % [_base, _peers]
	var arguments := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--audio-driver", "Dummy", "--script", "res://tests/creator_store_peer.gd", "--",
		"--root=" + root, "--out=" + out, "--mode=" + mode, "--draft=" + draft_id, "--seconds=%d" % seconds])
	return {pid = OS.create_process(OS.get_executable_path(), arguments), out = _abs(out)}


func _await_report(peer: Dictionary, seconds: float) -> Dictionary:
	if int(peer.pid) <= 0:
		return {}
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if FileAccess.file_exists(str(peer.out)):
			var parser := JSON.new()
			if parser.parse(FileAccess.get_file_as_string(str(peer.out))) == OK and parser.data is Dictionary:
				return parser.data
		OS.delay_msec(50)
	return {}


# --- Helpers ----------------------------------------------------------------------------------

func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL: " + label)


func _section(label: String) -> void:
	var now := Time.get_ticks_msec()
	print("  %s: %d ms" % [label, now - _section_started])
	_section_started = now


func _abs(path: String) -> String:
	return ProjectSettings.globalize_path(path).replace("\\", "/").trim_suffix("/")


func _code(result: Dictionary) -> String:
	if result.get("ok", false) or (result.get("diagnostics", []) as Array).is_empty():
		return ""
	return str(result.diagnostics[0].code)


func _open(root: String) -> RefCounted:
	var opened: Dictionary = Store.open(root)
	check("store opens: " + root.get_file(), opened.ok and opened.value.is_writer())
	if not opened.ok:
		print(R.texts(opened))
		return null
	return opened.value


func _draft(draft_id: String, name: String, snapshot: Dictionary, source: PackedByteArray, file_name: String,
		aircraft_uuid: String = "") -> Dictionary:
	return {draft_id = draft_id, name = name, aircraft_uuid = aircraft_uuid, snapshot = snapshot,
		source_bytes = source, source_file_name = file_name}


## Deterministic pseudo-random bytes.
func _bytes(count: int, seed_value: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(count)
	var state := seed_value * 7919 + 17
	for index: int in count:
		state = (state * 1103515245 + 12345) & 0x7FFFFFFF
		bytes[index] = (state >> 16) & 0xFF
	return bytes


func _join(first: PackedByteArray, second: PackedByteArray) -> PackedByteArray:
	var joined := first.duplicate()
	joined.append_array(second)
	return joined


## A store with drafts A (saved twice; the second save is the last transaction) and B.
## Generation 3; previous.json names generation 2, where A is at its first save.
func _seed(name: String) -> Dictionary:
	var root := _base + "/" + name
	var facts := {root = root, absolute = _abs(root), a1 = "", b1 = "", a2 = ""}
	var store: RefCounted = _open(root)
	if store == null:
		return facts
	var a1: Dictionary = store.save_draft(_draft(ID_A, "Alpha", {"v": 1.0}, _bytes(600, 1), "alpha.stl"), "")
	var b1: Dictionary = store.save_draft(_draft(ID_B, "Beta", {"v": 1.0}, _bytes(700, 2), "beta.stl"), "")
	var a2: Dictionary = store.save_draft(_draft(ID_A, "Alpha", {"v": 2.0}, _bytes(650, 3), "alpha.stl"), a1.value.record_sha256)
	check("seed %s" % name, a1.ok and b1.ok and a2.ok and store.generation() == 3)
	facts.a1 = a1.value.record_sha256
	facts.b1 = b1.value.record_sha256
	facts.a2 = a2.value.record_sha256
	store.close()
	return facts


func _object_path(absolute: String, sha: String) -> String:
	return "%s/objects/%s/%s" % [absolute, sha.substr(0, 2), sha]


func _object(absolute: String, sha: String) -> PackedByteArray:
	return _read(_object_path(absolute, sha))


func _read(path: String) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(path)


func _write(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not bytes.is_empty():
		file.store_buffer(bytes)
	file.close()


func _pointer_of(bytes: PackedByteArray) -> Dictionary:
	return CreatorBytes.decode(bytes, Store.POINTER_INTEGERS).value.data


func _pointer(absolute: String) -> Dictionary:
	return _pointer_of(_read(absolute + "/current.json"))


func _index(absolute: String) -> Dictionary:
	return CreatorBytes.decode(_object(absolute, _pointer(absolute).index.sha256), Store.INDEX_INTEGERS).value.data


func _pointer_bytes(generation: int, index_written: Dictionary, transaction: String) -> PackedByteArray:
	return CreatorBytes.encode({"format": Store.POINTER_FORMAT, "generation": generation, "transaction_id": transaction,
		"index": {"sha256": index_written.sha256, "byte_length": (index_written.bytes as PackedByteArray).size(),
		"media_type": Store.MEDIA_INDEX}}).value.bytes


## A copy of the seed's index as the next generation. Its predecessor is a reference to nothing
## unless one is given, so an open cannot tell which records are new.
func _next(honest: Dictionary, predecessor: Variant = null) -> Dictionary:
	var index: Dictionary = honest.duplicate(true)
	index["generation"] = 4
	index["transaction_id"] = ID_D
	index["predecessor"] = predecessor if predecessor != null else \
		{"sha256": SHA_NOWHERE, "byte_length": 500, "media_type": Store.MEDIA_INDEX}
	return index


## Writes a forged index object and a pointer (generation 4, transaction ID_D) that names it.
## Returns false when the index cannot be encoded.
func _forge(absolute: String, index: Dictionary) -> bool:
	var written: Dictionary = CreatorBytes.encode(index)
	if not written.ok:
		return false
	_write(_object_path(absolute, written.value.sha256), written.value.bytes)
	_write(absolute + "/current.json", _pointer_bytes(4, written.value, ID_D))
	return true


## Relative path -> SHA-256 of every file below `absolute`.
func _tree(absolute: String, prefix: String = "") -> Dictionary:
	var found := {}
	var directory := DirAccess.open(absolute)
	if directory == null:
		return found
	directory.include_hidden = true
	directory.list_dir_begin()
	while true:
		var entry := directory.get_next()
		if entry.is_empty():
			break
		if directory.current_is_dir():
			found.merge(_tree(absolute + "/" + entry, prefix + entry + "/"))
		else:
			found[prefix + entry] = CreatorBytes.sha256(_read(absolute + "/" + entry))
	directory.list_dir_end()
	return found


func _tree_bytes(absolute: String) -> int:
	var total := 0
	var directory := DirAccess.open(absolute)
	if directory == null:
		return 0
	directory.list_dir_begin()
	while true:
		var entry := directory.get_next()
		if entry.is_empty():
			break
		if directory.current_is_dir():
			total += _tree_bytes(absolute + "/" + entry)
		else:
			total += _read(absolute + "/" + entry).size()
	directory.list_dir_end()
	return total


func _files(absolute: String) -> Array:
	return _tree(absolute).keys()


## Relative paths of every object file.
func _objects(absolute: String) -> Array:
	var paths: Array = []
	for path: String in _tree(absolute + "/objects"):
		paths.append("objects/" + path)
	return paths


func _contains_all(have: Array, wanted: Array) -> bool:
	for item: Variant in wanted:
		if not have.has(item):
			return false
	return true


## True when some file directly in `folder` holds exactly these bytes.
func _has_bytes(folder: String, bytes: PackedByteArray) -> bool:
	return _tree(folder).values().has(CreatorBytes.sha256(bytes))


func _banner_from(port: int) -> String:
	var peer := StreamPeerTCP.new()
	if peer.connect_to_host("127.0.0.1", port) != OK:
		return ""
	var received := PackedByteArray()
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		var status := peer.get_status()
		if status == StreamPeerTCP.STATUS_CONNECTED and peer.get_available_bytes() > 0:
			received.append_array(peer.get_partial_data(peer.get_available_bytes())[1])
		elif status != StreamPeerTCP.STATUS_CONNECTED and status != StreamPeerTCP.STATUS_CONNECTING:
			break
		if received.has(0x0A):
			break
		OS.delay_msec(1)
	peer.disconnect_from_host()
	return received.get_string_from_ascii()


## A listener that answers like a lock holder, without the lock object: a process this one does
## not know about. `ok` is false when the port could not be bound.
func _fake_holder(port: int, line: String) -> Dictionary:
	var server := TCPServer.new()
	var fake := {ok = server.listen(port, "127.0.0.1") == OK, server = server, responder = null, thread = null}
	if fake.ok:
		var responder := ProcessLock.Responder.new()
		responder.server = server
		responder.line = line.to_ascii_buffer()
		var thread := Thread.new()
		thread.start(responder.run)
		fake.responder = responder
		fake.thread = thread
	return fake


func _stop_fake(fake: Dictionary) -> void:
	if fake.thread != null:
		fake.responder.halt()
		fake.thread.wait_to_finish()
	fake.server.stop()


func _remove_tree(absolute: String) -> void:
	# Only the test's own folder under user://.
	if not absolute.begins_with(_abs(_base)) or not _base.begins_with("user://creator_store_test_"):
		return
	var directory := DirAccess.open(absolute)
	if directory == null:
		return
	directory.include_hidden = true
	directory.list_dir_begin()
	while true:
		var entry := directory.get_next()
		if entry.is_empty():
			break
		if directory.current_is_dir():
			_remove_tree(absolute + "/" + entry)
		else:
			DirAccess.remove_absolute(absolute + "/" + entry)
	directory.list_dir_end()
	DirAccess.remove_absolute(absolute)

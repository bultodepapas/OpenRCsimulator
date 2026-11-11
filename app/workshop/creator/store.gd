extends RefCounted
## Durable local store of the Aircraft Creator (AC-13; ADR-02..06, ADR-11).
##
## Layout under one root (default `user://aircraft_creator`):
##   objects/<first two hex>/<sha256>   immutable blobs, named by the SHA-256 of their exact bytes
##   current.json                       pointer to the accepted root index: the only commit point
##   previous.json                      the pointer accepted before the last commit
##   staging/                           private temporary files, never read as data
##   damaged/                           files moved aside because their bytes were not what their
##                                      name or role promised; kept for diagnosis, never read
## A record never holds a path or URL. Blobs are named by `{sha256, byte_length, media_type}` and a
## file name is built only from a validated hash. Every record is written once through
## `CreatorBytes.encode` and read through `CreatorBytes.decode` with closed key sets.
##
## One process writes: `open` takes the root's `ProcessLock`; without it the instance is read-only.
## Every mutation is one transaction: compare with what this instance last accepted and with the
## caller's expected hash or revision, check the quota, write and read back each new object, write
## the new index, copy the accepted pointer to previous.json, replace current.json, read it back.
## Nothing accepted is ever deleted, pruned or rewritten: archive only hides, and history, old
## drafts and old indexes keep their bytes. Objects that no accepted index names are never used.
##
## Durability: an interrupted-process guarantee. A killed process leaves the old or the new
## accepted state, never a mix. On Windows the engine replaces a file by remove-then-rename; a
## kill inside that gap leaves no current.json and the next open restores the old state from
## previous.json. Power-loss durability is NOT claimed: GDScript cannot fsync a file's directory.
##
## What `open` verifies: the pointer, the index (hash and schema) and, by hash, every object the
## last transaction added, because those are the ones an unfinished commit can leave incomplete.
## If that fails, previous.json is used only when it passes the same checks. Older objects are
## verified by length and SHA-256 when they are read; damage there is confined to its own entry.
##
## Opaque members (`snapshot`, `placement`, `bindings`, `appearance`, `definition`) are JSON data
## the store does not interpret. Every number in them is stored as a float: a whole number comes
## back as a float, so loading and saving the same content is a no-op.
##
## Not thread-safe: use one instance from one thread at a time.

const R := preload("res://workshop/creator/result.gd")
const CreatorBytes := preload("res://workshop/creator/bytes.gd")
const Limits := preload("res://workshop/creator/limits.gd")
const RecordLoader := preload("res://workshop/creator/record_loader.gd")
const ProcessLock := preload("res://workshop/creator/process_lock.gd")

const DEFAULT_ROOT := "user://aircraft_creator"

const POINTER_FORMAT := "openrc-creator-pointer v1"
const INDEX_FORMAT := "openrc-creator-index v1"
const DRAFT_FORMAT := "openrc-creator-draft v1"
const AIRCRAFT_FORMAT := "openrc-creator-aircraft v1"
const AIRCRAFT_ID_PREFIX := "user-aircraft-"

const MEDIA_INDEX := "application/vnd.openrc.creator-index+json"
const MEDIA_DRAFT := "application/vnd.openrc.creator-draft+json"
const MEDIA_REVISION := "application/vnd.openrc.creator-aircraft+json"
const MEDIA_DEFINITION := "application/vnd.openrc.creator-definition+json"
const MEDIA_AIRCRAFT := "application/vnd.openrc.aircraft+json"
const MEDIA_SOURCE := "application/octet-stream"

const CURRENT_FILE := "current.json"
const PREVIOUS_FILE := "previous.json"
const OBJECTS_DIRECTORY := "objects"
const STAGING_DIRECTORY := "staging"
const DAMAGED_DIRECTORY := "damaged"

const LOCK_ACQUIRED := "acquired"
const LOCK_BUSY := "busy"
const LOCK_UNSUPPORTED := "unsupported"
const LOCK_READ_ONLY := "read_only"

## The first index of every root: fixed bytes, so an interrupted first start is recognizable.
const GENESIS_TRANSACTION := "00000000-0000-4000-8000-000000000000"

## Fault-injection stages (`options.fault_stage` or `set_fault_stage`). The next mutation that
## reaches the stage stops there as a killed process would: no cleanup, a failure result, and the
## instance refuses further writes. Object stages fire on the first new record or payload object.
const FAULT_BEFORE_OBJECT_WRITE := "before_object_write"
const FAULT_MID_OBJECT_WRITE := "mid_object_write"            # half of the object is in staging
const FAULT_AFTER_OBJECT_READBACK := "after_object_readback"  # verified in staging, not installed
const FAULT_BEFORE_INDEX_WRITE := "before_index_write"        # every object installed, no index
const FAULT_AFTER_INDEX_WRITE := "after_index_write"          # index installed, pointers untouched
const FAULT_MID_PREVIOUS_REPLACE := "mid_previous_replace"    # previous.json removed, not rewritten
const FAULT_AFTER_PREVIOUS_POINTER := "after_previous_pointer"  # previous.json holds the old pointer
const FAULT_BEFORE_CURRENT_REPLACE := "before_current_replace"
const FAULT_MID_CURRENT_REPLACE := "mid_current_replace"      # current.json removed, not rewritten
const FAULT_AFTER_CURRENT_REPLACE := "after_current_replace"  # committed, not read back
const FAULT_AFTER_COMMIT := "after_commit_before_ack"         # committed and verified, not reported
## Committed, but the pointer does not read back: the caller gets the "uncertain" outcome.
const FAULT_READBACK_LOST := "readback_lost"
const FAULT_STAGES: PackedStringArray = [
	FAULT_BEFORE_OBJECT_WRITE, FAULT_MID_OBJECT_WRITE, FAULT_AFTER_OBJECT_READBACK,
	FAULT_BEFORE_INDEX_WRITE, FAULT_AFTER_INDEX_WRITE, FAULT_MID_PREVIOUS_REPLACE,
	FAULT_AFTER_PREVIOUS_POINTER, FAULT_BEFORE_CURRENT_REPLACE, FAULT_MID_CURRENT_REPLACE,
	FAULT_AFTER_CURRENT_REPLACE, FAULT_AFTER_COMMIT, FAULT_READBACK_LOST,
]
## Stages at or after the commit point: a reopen shows the new state.
const FAULT_STAGES_COMMITTED: PackedStringArray = [FAULT_AFTER_CURRENT_REPLACE, FAULT_AFTER_COMMIT, FAULT_READBACK_LOST]

const POINTER_KEYS := ["format", "generation", "index", "transaction_id"]
const INDEX_KEYS := ["format", "generation", "transaction_id", "predecessor", "stored_bytes", "aircraft", "drafts", "recovery"]
const BLOB_KEYS := ["sha256", "byte_length", "media_type"]
const INDEX_AIRCRAFT_KEYS := ["name", "archived", "current_revision", "revisions"]
const INDEX_REVISION_KEYS := ["revision", "record", "created_unix"]
const INDEX_DRAFT_KEYS := ["name", "aircraft_uuid", "record", "updated_unix", "archived"]
const INDEX_RECOVERY_KEYS := ["record", "updated_unix"]
const DRAFT_KEYS := ["format", "draft_id", "name", "aircraft_uuid", "snapshot", "source", "source_file_name"]
const AIRCRAFT_KEYS := ["format", "aircraft_uuid", "revision", "name", "definition", "aircraft", "source",
	"source_file_name", "placement", "bindings", "appearance", "snapshot", "created_unix"]

const POINTER_INTEGERS: PackedStringArray = ["generation", "index/byte_length"]
const INDEX_INTEGERS: PackedStringArray = ["generation", "stored_bytes", "predecessor/byte_length",
	"aircraft/*/current_revision", "aircraft/*/revisions/*/revision", "aircraft/*/revisions/*/created_unix",
	"aircraft/*/revisions/*/record/byte_length", "drafts/*/updated_unix", "drafts/*/record/byte_length",
	"recovery/*/updated_unix", "recovery/*/record/byte_length"]
const DRAFT_INTEGERS: PackedStringArray = ["source/byte_length"]
const AIRCRAFT_INTEGERS: PackedStringArray = ["revision", "created_unix", "definition/byte_length",
	"aircraft/byte_length", "source/byte_length"]

# Player messages: what happened and what to do. `%s` is filled from the diagnostic's arguments.
const M_ROOT := "The aircraft library folder cannot be used because it is not a plain folder inside the simulator's data folder. Move it back there, then open the Creator again."
const M_DAMAGED := "Your aircraft library could not be read because its entry files are damaged (%s). Nothing was changed or deleted. Restore the folder %s from a backup, or move it somewhere safe to start an empty library."
const M_LOCK_BUSY := "Another OpenRC window is using your aircraft library, so this window can show it but cannot change it. Close the other window, then open the Creator again to edit here."
const M_LOCK_UNSUPPORTED := "OpenRC could not reserve your aircraft library for editing on this computer, so it is view-only. Your saved aircraft are safe. Restart the simulator and open the Creator again."
const M_RECOVERED := "The last change to your aircraft library did not finish, so the library was put back to the state before it. Check your most recent draft or aircraft and save it again if the change is missing."
const M_REPAIR_FAILED := "Your aircraft library was put back to the state before an unfinished change, but that could not be written to disk (%s), so it is view-only. Check that the disk is not full or write-protected, then open the Creator again."
const M_VIEW_ONLY := "The aircraft library is open for viewing only, so nothing can be saved here. Open the Creator again to edit."
const M_REOPEN := "The aircraft library must be opened again before anything else is saved. Leave the Creator, open it again and check that your last save is there."
const M_UNCERTAIN := "The simulator could not confirm whether your last save finished. Do not save again yet: leave the Creator, open it again and check whether the change is there."
const M_CHANGED_OUTSIDE := "The aircraft library changed on disk while it was open, so nothing was saved. Leave the Creator, open it again and repeat your change."
const M_WRITE := "The aircraft library could not be written (%s), so nothing was saved. Check that the disk is not full or write-protected, then save again."
const M_QUOTA := "The aircraft library is full: this change needs %s MB and %s MB of its %s MB limit is free. Nothing was saved. Use a smaller model file; archiving does not free space."
const M_DISK := "The disk is too full to save this change: it needs %s MB and %s MB is free. Nothing was saved. Free some disk space, then save again."
const M_DRAFTS_FULL := "The aircraft library already holds %s drafts, its maximum. Nothing was saved. Continue an existing draft instead."
const M_AIRCRAFT_FULL := "The aircraft library already holds %s aircraft, its maximum. Nothing was saved. Save a new version of an existing aircraft instead."
const M_REVISIONS_FULL := "This aircraft already has %s saved versions, its maximum. Nothing was saved. Save it as a new aircraft instead."
const M_INDEX_FULL := "The aircraft library cannot list any more entries. Nothing was saved. Continue an existing draft or save a new version of an existing aircraft instead."
const M_DRAFT_EXISTS := "A draft with this identity is already saved, so it was not overwritten. Reload the list of drafts and open that draft."
const M_DRAFT_CONFLICT := "This draft was saved again after you opened it, so the newer version was not overwritten. Reload the draft and repeat your change."
const M_RECOVERY_CONFLICT := "A newer automatic backup of this draft exists, so it was kept. Reload the draft to see it."
const M_AIRCRAFT_CONFLICT := "This aircraft was saved again after you opened it, so the newer version was not overwritten. Reload the aircraft and repeat your change."
const M_INPUT := "The data to save is incomplete or malformed (%s), so nothing was saved. This is a fault in the simulator; please report it."
const M_NAME := "Give it a name of 1 to %s characters without line breaks, then save again."
const M_TEXT := "The %s holds a value that cannot be saved (%s). Remove unusual characters or values from it, then save again."
const M_RECORD_SIZE := "The data to save is larger than the %s MB limit, so nothing was saved. Remove some notes or parts, then save again."
const M_SOURCE_SIZE := "The model file is larger than the %s MB limit, so it was not saved. Export a smaller model and import it again."
const M_NO_SOURCE := "This aircraft has no model file yet, so it cannot be saved as an aircraft. Import a model first."
const M_NOT_AIRCRAFT := "The checked flight data does not belong to this aircraft (%s), so it was not saved. Run the check again, then save."
const M_NO_DRAFT := "That draft is not in the aircraft library. Reload the list of drafts."
const M_NO_RECOVERY := "There is no automatic backup for this draft."
const M_NO_AIRCRAFT := "That aircraft is not in the aircraft library. Reload the list of aircraft."
const M_NO_REVISION := "Version %s of this aircraft does not exist. Reload the aircraft."
const M_ENTRY_DAMAGED := "Part of this saved item is damaged or missing, so it cannot be opened (%s). Your other drafts and aircraft are not affected. Restore the aircraft library folder from a backup to get it back."

var _root := ""
var _lock: RefCounted
var _lock_status := LOCK_READ_ONLY
var _quota := Limits.STORE_QUOTA_BYTES
var _pointer: Dictionary = {}
var _pointer_bytes := PackedByteArray()
var _index: Dictionary = {}
var _recovered := false
## Bytes on disk under the root's objects, staging and damaged folders (writer only).
var _disk_bytes := 0
## Objects this instance wrote or hash-verified in this session: sha256 -> byte length.
var _verified := {}
var _fault_stage := ""
## "" while writes are allowed; otherwise why this instance must be reopened first.
var _halted := ""
var _transaction := ""
var _serial := 0


# --- Opening ----------------------------------------------------------------------------------

## Opens the store. Result value = store instance; diagnostics carry warnings (view-only, restored
## from the previous pointer). `options`: `quota_bytes` (int, default 4 GiB), `read_only` (bool),
## `fault_stage` (test only). An empty root is initialized when this instance is the writer.
## A root whose pointers both fail is refused: nothing is written and no object is promoted.
static func open(root: String = DEFAULT_ROOT, options: Dictionary = {}) -> Dictionary:
	var resolved := _resolve_root(root)
	if resolved.is_empty():
		return R.fail(R.WRITE_FAILED, M_ROOT)
	var quota: Variant = options.get("quota_bytes", Limits.STORE_QUOTA_BYTES)
	var fault := str(options.get("fault_stage", ""))
	if typeof(quota) != TYPE_INT or quota <= 0 or (not fault.is_empty() and not FAULT_STAGES.has(fault)):
		return R.fail(R.RECORD_INVALID, M_INPUT, "options", "", ["options"])
	var own_script: Script = load("res://workshop/creator/store.gd")
	var store: RefCounted = own_script.new()
	return store._open(resolved, quota, bool(options.get("read_only", false)), fault)


func _open(resolved: String, quota: int, read_only: bool, fault: String) -> Dictionary:
	_root = resolved
	_quota = quota
	var notes: Array = []
	if not read_only:
		var acquired: Dictionary = ProcessLock.acquire(_root)
		match str(acquired.status):
			ProcessLock.STATUS_ACQUIRED:
				_lock = acquired.lock
				_lock_status = LOCK_ACQUIRED
			ProcessLock.STATUS_BUSY:
				_lock_status = LOCK_BUSY
				notes.append(R.diagnostic(R.ROOT_LOCK_BUSY, M_LOCK_BUSY, "", "", [], R.SEVERITY_WARNING))
			_:
				_lock_status = LOCK_UNSUPPORTED
				notes.append(R.diagnostic(R.ROOT_LOCK_BUSY, M_LOCK_UNSUPPORTED, "", "", [], R.SEVERITY_WARNING))
	var loaded := _load_accepted(notes)
	if not loaded.ok:
		close()
		return loaded
	_fault_stage = fault
	return R.ok(self, notes)


## Releases the process lock. The instance stays readable and refuses every mutation.
func close() -> void:
	if _lock != null:
		_lock.release()
		_lock = null
	_lock_status = LOCK_READ_ONLY


func is_writer() -> bool:
	return _lock != null and bool(_lock.is_held())


## "acquired" | "busy" | "unsupported" | "read_only".
func lock_status() -> String:
	return _lock_status


func generation() -> int:
	return int(_index.get("generation", 0))


## Writer: bytes on disk under this root that count against the quota (accepted objects, objects
## of unfinished transactions, staging and damaged files). Reader: the total the index recorded.
func stored_bytes() -> int:
	if is_writer():
		return _disk_bytes
	var index_bytes := 0 if _pointer.is_empty() else int(_pointer.index.byte_length)
	return int(_index.get("stored_bytes", 0)) + index_bytes


func quota_bytes() -> int:
	return _quota


func root_path() -> String:
	return _root


## True when `open` used previous.json because current.json was missing or failed validation.
func recovered_from_previous() -> bool:
	return _recovered


## True after an uncertain or injected interruption: reopen before writing again.
func needs_reopen() -> bool:
	return not _halted.is_empty()


## Test hook: arms one fault stage for the next mutation. "" disarms.
func set_fault_stage(stage: String) -> bool:
	if not stage.is_empty() and not FAULT_STAGES.has(stage):
		return false
	_fault_stage = stage
	return true


# --- Listing ----------------------------------------------------------------------------------

## `[{draft_id, name, aircraft_uuid, updated_unix, record_sha256, archived}]`, newest first.
func list_drafts(include_archived: bool = false) -> Array:
	var rows: Array = []
	var drafts: Dictionary = _index.get("drafts", {})
	for draft_id: String in drafts:
		var entry: Dictionary = drafts[draft_id]
		if entry.archived and not include_archived:
			continue
		rows.append({draft_id = draft_id, name = entry.name, aircraft_uuid = entry.aircraft_uuid,
			updated_unix = entry.updated_unix, record_sha256 = entry.record.sha256, archived = entry.archived})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.draft_id < b.draft_id if a.updated_unix == b.updated_unix else a.updated_unix > b.updated_unix)
	return rows


## `[{aircraft_uuid, name, revision, revisions, created_unix, record_sha256, archived}]`, newest
## first. `revision` is the current one, `revisions` their count; hash and time are the current one's.
func list_aircraft(include_archived: bool = false) -> Array:
	var rows: Array = []
	var aircraft: Dictionary = _index.get("aircraft", {})
	for aircraft_uuid: String in aircraft:
		var entry: Dictionary = aircraft[aircraft_uuid]
		if entry.archived and not include_archived:
			continue
		var latest: Dictionary = entry.revisions[int(entry.current_revision) - 1]
		rows.append({aircraft_uuid = aircraft_uuid, name = entry.name, revision = entry.current_revision,
			revisions = (entry.revisions as Array).size(), created_unix = latest.created_unix,
			record_sha256 = latest.record.sha256, archived = entry.archived})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.aircraft_uuid < b.aircraft_uuid if a.created_unix == b.created_unix else a.created_unix > b.created_unix)
	return rows


## Automatic backups, `[{draft_id, updated_unix, record_sha256}]`, newest first. Read from the
## index only, so it also names the backup of a draft that was never saved by name.
func list_recovery() -> Array:
	var rows: Array = []
	var recovery: Dictionary = _index.get("recovery", {})
	for draft_id: String in recovery:
		var entry: Dictionary = recovery[draft_id]
		rows.append({draft_id = draft_id, updated_unix = entry.updated_unix, record_sha256 = entry.record.sha256})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.draft_id < b.draft_id if a.updated_unix == b.updated_unix else a.updated_unix > b.updated_unix)
	return rows


# --- Drafts and recovery ----------------------------------------------------------------------

## Saves a named draft. `draft` = `{draft_id, name, aircraft_uuid ("" or UUID), snapshot,
## source_bytes, source_file_name}`; other keys are ignored. `source_file_name` is a bare file
## name, never a path. `expected_record_sha256` "" means the draft must not exist yet; otherwise it
## must be the draft's current record hash. Value = `{draft_id, record_sha256, generation}`.
## Saving identical content writes nothing and returns the same hash.
func save_draft(draft: Dictionary, expected_record_sha256: String) -> Dictionary:
	return _save_draft_slot("drafts", draft, expected_record_sha256)


## Value = `{draft_id, name, aircraft_uuid, snapshot, source_bytes, source_file_name, record_sha256}`.
func load_draft(draft_id: String) -> Dictionary:
	var entry: Variant = (_index.get("drafts", {}) as Dictionary).get(draft_id)
	if entry == null:
		return R.fail(R.DEPENDENCY_MISSING, M_NO_DRAFT, "draft_id")
	return _load_draft_record(entry.record, draft_id, entry)


## Saves the automatic backup of a draft: one slot per draft ID, independent of the named draft
## and never listed as one. Same arguments and value as `save_draft`; the name may be empty.
func save_recovery(draft: Dictionary, expected_record_sha256: String) -> Dictionary:
	return _save_draft_slot("recovery", draft, expected_record_sha256)


func load_recovery(draft_id: String) -> Dictionary:
	var entry: Variant = (_index.get("recovery", {}) as Dictionary).get(draft_id)
	if entry == null:
		return R.fail(R.DEPENDENCY_MISSING, M_NO_RECOVERY, "draft_id")
	return _load_draft_record(entry.record, draft_id, {})


## Removes the backup slot when it still holds `expected_record_sha256`; a newer backup is kept
## (SAVE_CONFLICT). A slot that is already empty is success. Value = `{draft_id, generation}`.
func clear_recovery(draft_id: String, expected_record_sha256: String) -> Dictionary:
	var begun := _begin()
	if not begun.ok:
		return begun
	var entry: Variant = (_index.recovery as Dictionary).get(draft_id)
	if entry == null:
		return R.ok({draft_id = draft_id, generation = generation()})
	if str(entry.record.sha256) != expected_record_sha256:
		return R.fail(R.SAVE_CONFLICT, M_RECOVERY_CONFLICT, "draft_id")
	var next: Dictionary = _index.duplicate(true)
	(next.recovery as Dictionary).erase(draft_id)
	var committed := _commit(next, [])
	if not committed.ok:
		return committed
	return R.ok({draft_id = draft_id, generation = generation()})


# --- Published aircraft -----------------------------------------------------------------------

## Publishes a new immutable revision. `publication` = `{aircraft_uuid, name, definition,
## raw_bytes, source_bytes, source_file_name, placement, bindings, appearance, snapshot}`; other
## keys are ignored. `raw_bytes` must load as an aircraft whose model ID is
## "user-aircraft-<aircraft_uuid>"; the store neither compiles nor judges the physics.
## `expected_revision` 0 = first publication, otherwise the current revision (else SAVE_CONFLICT).
## Value = `{aircraft_uuid, revision, record_sha256, generation}`. A repeated call after success is
## a conflict, never a second revision.
func publish_aircraft(publication: Dictionary, expected_revision: int) -> Dictionary:
	var prepared := _prepare_publication(publication)
	if not prepared.ok:
		return prepared
	var begun := _begin()
	if not begun.ok:
		return begun
	var parts: Dictionary = prepared.value
	var aircraft_uuid: String = parts.aircraft_uuid
	var aircraft: Dictionary = _index.aircraft
	var entry: Variant = aircraft.get(aircraft_uuid)
	var current := 0 if entry == null else int(entry.current_revision)
	if expected_revision != current:
		return R.fail(R.SAVE_CONFLICT, M_AIRCRAFT_CONFLICT, "aircraft_uuid")
	if entry == null and aircraft.size() >= Limits.STORE_AIRCRAFT:
		return R.fail(R.STORAGE_QUOTA, M_AIRCRAFT_FULL, "", "", [str(Limits.STORE_AIRCRAFT)])
	if current >= Limits.STORE_REVISIONS_PER_AIRCRAFT:
		return R.fail(R.STORAGE_QUOTA, M_REVISIONS_FULL, "", "", [str(Limits.STORE_REVISIONS_PER_AIRCRAFT)])
	var created := _now()
	var record: Dictionary = parts.record
	record["revision"] = current + 1
	record["created_unix"] = created
	var written := _encode_record(record, AIRCRAFT_INTEGERS, "aircraft")
	if not written.ok:
		return written
	var objects: Array = parts.objects
	objects.append(written.value)
	var next: Dictionary = _index.duplicate(true)
	var revisions: Array = [] if entry == null else (next.aircraft[aircraft_uuid].revisions as Array)
	revisions.append({revision = current + 1, created_unix = created,
		record = _blob(written.value.sha256, (written.value.bytes as PackedByteArray).size(), MEDIA_REVISION)})
	next.aircraft[aircraft_uuid] = {name = parts.name, archived = false if entry == null else bool(entry.archived),
		current_revision = current + 1, revisions = revisions}
	var committed := _commit(next, objects)
	if not committed.ok:
		return committed
	return R.ok({aircraft_uuid = aircraft_uuid, revision = current + 1,
		record_sha256 = written.value.sha256, generation = generation()})


## `revision` 0 = current. Value = `{aircraft_uuid, revision, name, definition (Dictionary),
## definition_bytes, definition_sha256, raw_bytes, raw_sha256, source_bytes, source_sha256,
## source_file_name, placement, bindings, appearance, snapshot, created_unix, record_sha256}`.
## Every blob is checked by length and SHA-256. A consumer that flies `raw_bytes` still loads them
## through its own record boundary.
func load_aircraft(aircraft_uuid: String, revision: int = 0) -> Dictionary:
	var entry: Variant = (_index.get("aircraft", {}) as Dictionary).get(aircraft_uuid)
	if entry == null:
		return R.fail(R.DEPENDENCY_MISSING, M_NO_AIRCRAFT, "aircraft_uuid")
	var wanted := int(entry.current_revision) if revision == 0 else revision
	if wanted < 1 or wanted > (entry.revisions as Array).size():
		return R.fail(R.DEPENDENCY_MISSING, M_NO_REVISION, "revision", "", [str(revision)])
	return _load_revision_record(entry.revisions[wanted - 1], aircraft_uuid)


## Hides or shows a draft or an aircraft in the default listings. `kind` is "draft" or "aircraft".
## Nothing is deleted and no space is freed. Value = `{kind, id, archived, generation}`.
func set_archived(kind: String, id: String, archived: bool) -> Dictionary:
	if kind != "draft" and kind != "aircraft":
		return R.fail(R.RECORD_INVALID, M_INPUT, "kind", "", ["kind"])
	var begun := _begin()
	if not begun.ok:
		return begun
	var group := "drafts" if kind == "draft" else "aircraft"
	var entry: Variant = (_index[group] as Dictionary).get(id)
	if entry == null:
		return R.fail(R.DEPENDENCY_MISSING, M_NO_DRAFT if kind == "draft" else M_NO_AIRCRAFT, "id")
	if bool(entry.archived) != archived:
		var next: Dictionary = _index.duplicate(true)
		next[group][id].archived = archived
		var committed := _commit(next, [])
		if not committed.ok:
			return committed
	return R.ok({kind = kind, id = id, archived = archived, generation = generation()})


# --- Draft records ----------------------------------------------------------------------------

func _save_draft_slot(group: String, draft: Dictionary, expected: String) -> Dictionary:
	var named := group == "drafts"
	var prepared := _prepare_draft(draft, named)
	if not prepared.ok:
		return prepared
	var begun := _begin()
	if not begun.ok:
		return begun
	var parts: Dictionary = prepared.value
	var draft_id: String = parts.draft_id
	var slots: Dictionary = _index[group]
	var entry: Variant = slots.get(draft_id)
	var current := "" if entry == null else str(entry.record.sha256)
	if expected != current:
		if not named:
			return R.fail(R.SAVE_CONFLICT, M_RECOVERY_CONFLICT, "draft_id")
		return R.fail(R.SAVE_CONFLICT, M_DRAFT_EXISTS if expected.is_empty() else M_DRAFT_CONFLICT, "draft_id")
	var record_sha: String = parts.record.sha256
	if record_sha == current:
		return R.ok({draft_id = draft_id, record_sha256 = record_sha, generation = generation()})
	if named and entry == null and slots.size() >= Limits.STORE_DRAFTS:
		return R.fail(R.STORAGE_QUOTA, M_DRAFTS_FULL, "", "", [str(Limits.STORE_DRAFTS)])
	var next: Dictionary = _index.duplicate(true)
	var reference := _blob(record_sha, (parts.record.bytes as PackedByteArray).size(), MEDIA_DRAFT)
	if named:
		next.drafts[draft_id] = {name = parts.name, aircraft_uuid = parts.aircraft_uuid, record = reference,
			updated_unix = _now(), archived = false if entry == null else bool(entry.archived)}
	else:
		next.recovery[draft_id] = {record = reference, updated_unix = _now()}
	var committed := _commit(next, parts.objects)
	if not committed.ok:
		return committed
	return R.ok({draft_id = draft_id, record_sha256 = record_sha, generation = generation()})


## Validates a draft and encodes its record once. Value = `{draft_id, name, aircraft_uuid,
## record = {bytes, sha256}, objects}`.
func _prepare_draft(draft: Dictionary, named: bool) -> Dictionary:
	for key: String in ["draft_id", "name", "aircraft_uuid", "snapshot", "source_bytes", "source_file_name"]:
		if not draft.has(key):
			return _input(key)
	if not _is_uuid(draft.draft_id):
		return _input("draft_id")
	if typeof(draft.aircraft_uuid) != TYPE_STRING or not (draft.aircraft_uuid == "" or _is_uuid(draft.aircraft_uuid)):
		return _input("aircraft_uuid")
	if not _is_name(draft.name, not named):
		return R.fail(R.RECORD_INVALID, M_NAME, "name", "", [str(Limits.NAME_CHARACTERS)])
	if not _is_file_name(draft.source_file_name):
		return _input("source_file_name")
	if typeof(draft.source_bytes) != TYPE_PACKED_BYTE_ARRAY or typeof(draft.snapshot) != TYPE_DICTIONARY:
		return _input("source_bytes" if typeof(draft.snapshot) == TYPE_DICTIONARY else "snapshot")
	var source: PackedByteArray = draft.source_bytes
	if source.size() > Limits.MODEL_SOURCE_BYTES:
		return R.fail(R.SOURCE_LIMIT, M_SOURCE_SIZE, "source_bytes", "", [_megabytes(Limits.MODEL_SOURCE_BYTES)])
	var snapshot := _plain_member(draft.snapshot, "draft")
	if not snapshot.ok:
		return snapshot
	var objects: Array = []
	var source_reference: Variant = null
	if not source.is_empty():
		var source_sha := CreatorBytes.sha256(source)
		source_reference = _blob(source_sha, source.size(), MEDIA_SOURCE)
		objects.append({bytes = source, sha256 = source_sha})
	var record := {format = DRAFT_FORMAT, draft_id = draft.draft_id, name = draft.name,
		aircraft_uuid = draft.aircraft_uuid, snapshot = snapshot.value, source = source_reference,
		source_file_name = draft.source_file_name}
	var written := _encode_record(record, DRAFT_INTEGERS, "draft")
	if not written.ok:
		return written
	objects.append(written.value)
	return R.ok({draft_id = draft.draft_id, name = draft.name, aircraft_uuid = draft.aircraft_uuid,
		record = written.value, objects = objects})


## Reads one draft record and its source. `entry` is the named draft's index entry, or `{}`.
func _load_draft_record(reference: Dictionary, draft_id: String, entry: Dictionary) -> Dictionary:
	var blob := _read_object(reference, Limits.DRAFT_BYTES)
	if not blob.ok:
		return _entry_damaged(blob.problem)
	var decoded: Dictionary = CreatorBytes.decode(blob.bytes, DRAFT_INTEGERS, Limits.DRAFT_BYTES)
	if not decoded.ok:
		return _entry_damaged("the draft record is not readable")
	var record: Dictionary = decoded.value.data
	var problem := _draft_problem(record)
	if problem.is_empty() and record.draft_id != draft_id:
		problem = "the draft record belongs to another draft"
	if problem.is_empty() and not entry.is_empty() \
			and (record.name != entry.name or record.aircraft_uuid != entry.aircraft_uuid):
		problem = "the draft record does not match the library list"
	if not problem.is_empty():
		return _entry_damaged(problem)
	var source := PackedByteArray()
	if record.source != null:
		var payload := _read_object(record.source, Limits.MODEL_SOURCE_BYTES)
		if not payload.ok:
			return _entry_damaged(payload.problem)
		source = payload.bytes
	return R.ok({draft_id = draft_id, name = record.name, aircraft_uuid = record.aircraft_uuid,
		snapshot = record.snapshot, source_bytes = source, source_file_name = record.source_file_name,
		record_sha256 = str(reference.sha256)})


static func _draft_problem(record: Dictionary) -> String:
	if not _closed(record, DRAFT_KEYS) or record.format != DRAFT_FORMAT:
		return "the draft record has an unknown shape"
	if not _is_uuid(record.draft_id) or not _is_name(record.name, true) \
			or typeof(record.aircraft_uuid) != TYPE_STRING \
			or not (record.aircraft_uuid == "" or _is_uuid(record.aircraft_uuid)) \
			or typeof(record.snapshot) != TYPE_DICTIONARY or not _is_file_name(record.source_file_name):
		return "the draft record has an invalid field"
	if record.source != null and not _blob_problem(record.source, MEDIA_SOURCE, Limits.MODEL_SOURCE_BYTES).is_empty():
		return "the draft record names its model file wrongly"
	return ""


# --- Aircraft records -------------------------------------------------------------------------

## Validates a publication and encodes its payloads. Value = `{aircraft_uuid, name, record (without
## revision and time), objects}`.
func _prepare_publication(publication: Dictionary) -> Dictionary:
	for key: String in ["aircraft_uuid", "name", "definition", "raw_bytes", "source_bytes", "source_file_name",
			"placement", "bindings", "appearance", "snapshot"]:
		if not publication.has(key):
			return _input(key)
	if not _is_uuid(publication.aircraft_uuid):
		return _input("aircraft_uuid")
	var aircraft_uuid: String = publication.aircraft_uuid
	if not _is_name(publication.name, false):
		return R.fail(R.RECORD_INVALID, M_NAME, "name", "", [str(Limits.NAME_CHARACTERS)])
	if not _is_file_name(publication.source_file_name):
		return _input("source_file_name")
	if typeof(publication.raw_bytes) != TYPE_PACKED_BYTE_ARRAY:
		return _input("raw_bytes")
	if typeof(publication.source_bytes) != TYPE_PACKED_BYTE_ARRAY:
		return _input("source_bytes")
	var source: PackedByteArray = publication.source_bytes
	if source.is_empty():
		return R.fail(R.RECORD_INVALID, M_NO_SOURCE, "source_bytes")
	if source.size() > Limits.MODEL_SOURCE_BYTES:
		return R.fail(R.SOURCE_LIMIT, M_SOURCE_SIZE, "source_bytes", "", [_megabytes(Limits.MODEL_SOURCE_BYTES)])
	var members := {}
	for key: String in ["definition", "placement", "bindings", "appearance", "snapshot"]:
		if typeof(publication[key]) != TYPE_DICTIONARY:
			return _input(key)
		var plain := _plain_member(publication[key], key)
		if not plain.ok:
			return plain
		members[key] = plain.value
	var definition: Dictionary = members.definition
	if definition.has("aircraft_uuid") and definition.aircraft_uuid != aircraft_uuid:
		return R.fail(R.RECORD_INVALID, M_NOT_AIRCRAFT, "definition", "", ["the definition names another aircraft"])
	var raw: PackedByteArray = publication.raw_bytes
	var raw_problem := _aircraft_bytes_problem(raw, aircraft_uuid)
	if not raw_problem.is_empty():
		return R.fail(R.RECORD_INVALID, M_NOT_AIRCRAFT, "raw_bytes", "", [raw_problem])
	var definition_written := _encode_record(definition, PackedStringArray(), "definition", Limits.RECORD_BYTES)
	if not definition_written.ok:
		return definition_written
	var definition_bytes: PackedByteArray = definition_written.value.bytes
	var raw_sha := CreatorBytes.sha256(raw)
	var source_sha := CreatorBytes.sha256(source)
	var record := {format = AIRCRAFT_FORMAT, aircraft_uuid = aircraft_uuid, name = publication.name,
		definition = _blob(definition_written.value.sha256, definition_bytes.size(), MEDIA_DEFINITION),
		aircraft = _blob(raw_sha, raw.size(), MEDIA_AIRCRAFT),
		source = _blob(source_sha, source.size(), MEDIA_SOURCE),
		source_file_name = publication.source_file_name, placement = members.placement,
		bindings = members.bindings, appearance = members.appearance, snapshot = members.snapshot}
	var objects: Array = [definition_written.value, {bytes = raw, sha256 = raw_sha}, {bytes = source, sha256 = source_sha}]
	return R.ok({aircraft_uuid = aircraft_uuid, name = publication.name, record = record, objects = objects})


## "" when `raw` is a loadable aircraft record whose model ID belongs to `aircraft_uuid`.
static func _aircraft_bytes_problem(raw: PackedByteArray, aircraft_uuid: String) -> String:
	if raw.is_empty() or raw.size() > Limits.RECORD_BYTES:
		return "the flight data is empty or too large"
	# The strict reader first: the loader's own text and JSON decoders would log on hostile bytes.
	if not CreatorBytes.decode(raw).ok:
		return "the flight data is not a valid record"
	var expected := AIRCRAFT_ID_PREFIX + aircraft_uuid
	var loaded: Dictionary = RecordLoader.load_bytes(raw, expected)
	if not loaded.get("ok", false):
		return "the flight data does not load as an aircraft"
	if typeof(loaded.get("model")) != TYPE_DICTIONARY or loaded.model.get("id") != expected:
		return "the flight data names another aircraft"
	return ""


func _load_revision_record(listed: Dictionary, aircraft_uuid: String) -> Dictionary:
	var blob := _read_object(listed.record, Limits.DRAFT_BYTES)
	if not blob.ok:
		return _entry_damaged(blob.problem)
	var decoded: Dictionary = CreatorBytes.decode(blob.bytes, AIRCRAFT_INTEGERS, Limits.DRAFT_BYTES)
	if not decoded.ok:
		return _entry_damaged("the aircraft record is not readable")
	var record: Dictionary = decoded.value.data
	var problem := _revision_problem(record)
	if problem.is_empty() and (record.aircraft_uuid != aircraft_uuid or record.revision != listed.revision
			or record.created_unix != listed.created_unix):
		problem = "the aircraft record does not match the library list"
	if not problem.is_empty():
		return _entry_damaged(problem)
	var definition := _read_object(record.definition, Limits.RECORD_BYTES)
	var raw := _read_object(record.aircraft, Limits.RECORD_BYTES)
	var source := _read_object(record.source, Limits.MODEL_SOURCE_BYTES)
	for payload: Dictionary in [definition, raw, source]:
		if not payload.ok:
			return _entry_damaged(payload.problem)
	var definition_data: Dictionary = CreatorBytes.decode(definition.bytes)
	if not definition_data.ok:
		return _entry_damaged("the aircraft definition is not readable")
	return R.ok({aircraft_uuid = aircraft_uuid, revision = record.revision, name = record.name,
		definition = definition_data.value.data, definition_bytes = definition.bytes,
		definition_sha256 = str(record.definition.sha256), raw_bytes = raw.bytes,
		raw_sha256 = str(record.aircraft.sha256), source_bytes = source.bytes,
		source_sha256 = str(record.source.sha256), source_file_name = record.source_file_name,
		placement = record.placement, bindings = record.bindings, appearance = record.appearance,
		snapshot = record.snapshot, created_unix = record.created_unix,
		record_sha256 = str(listed.record.sha256)})


static func _revision_problem(record: Dictionary) -> String:
	if not _closed(record, AIRCRAFT_KEYS) or record.format != AIRCRAFT_FORMAT:
		return "the aircraft record has an unknown shape"
	if not _is_uuid(record.aircraft_uuid) or not _is_count(record.revision) or record.revision < 1 \
			or not _is_name(record.name, false) or not _is_file_name(record.source_file_name) \
			or not _is_count(record.created_unix):
		return "the aircraft record has an invalid field"
	for key: String in ["placement", "bindings", "appearance", "snapshot"]:
		if typeof(record[key]) != TYPE_DICTIONARY:
			return "the aircraft record has an invalid field"
	if not _blob_problem(record.definition, MEDIA_DEFINITION, Limits.RECORD_BYTES).is_empty() \
			or not _blob_problem(record.aircraft, MEDIA_AIRCRAFT, Limits.RECORD_BYTES).is_empty() \
			or not _blob_problem(record.source, MEDIA_SOURCE, Limits.MODEL_SOURCE_BYTES).is_empty():
		return "the aircraft record names a file wrongly"
	return ""


# --- Transaction ------------------------------------------------------------------------------

## Gate of every mutation: writer, not halted, and the accepted pointer and index on disk are
## still the bytes this instance last accepted.
func _begin() -> Dictionary:
	if not is_writer():
		return R.fail(R.ROOT_LOCK_BUSY, M_LOCK_BUSY if _lock_status == LOCK_BUSY else M_VIEW_ONLY)
	if not _halted.is_empty():
		return R.fail(R.WRITE_FAILED, M_REOPEN)
	var seen := _read_file(_root.path_join(CURRENT_FILE), Limits.STORE_POINTER_BYTES)
	if seen.state != "ok" or seen.bytes != _pointer_bytes:
		return R.fail(R.SAVE_CONFLICT, M_CHANGED_OUTSIDE)
	if not _read_object(_pointer.index, Limits.STORE_INDEX_BYTES).ok:
		return R.fail(R.SAVE_CONFLICT, M_CHANGED_OUTSIDE)
	return R.ok()


## Writes `objects` (`[{bytes, sha256}]`) and the index `next`, then moves the pointer. On success
## this instance holds the new accepted state. See the file header for the order and its reasons.
func _commit(next: Dictionary, objects: Array) -> Dictionary:
	_transaction = _new_uuid()
	_serial = 0
	var pending: Array = []
	var new_bytes := 0
	var planned := {}
	for object: Dictionary in objects:
		var sha: String = object.sha256
		var bytes: PackedByteArray = object.bytes
		if planned.has(sha) or _object_present(sha, bytes.size()):
			continue
		planned[sha] = true
		pending.append(object)
		new_bytes += bytes.size()
	next["generation"] = generation() + 1
	next["transaction_id"] = _transaction
	next["predecessor"] = (_pointer.index as Dictionary).duplicate()
	next["stored_bytes"] = _disk_bytes + new_bytes
	var index_written: Dictionary = CreatorBytes.encode(next, Limits.STORE_INDEX_BYTES)
	if not index_written.ok:
		return R.fail(R.STORAGE_QUOTA, M_INDEX_FULL)
	var index_bytes: PackedByteArray = index_written.value.bytes
	var index_checked := _decode_index(index_bytes)
	if not index_checked.ok:
		return _input("index: " + str(index_checked.problem))
	var index_reference := _blob(index_written.value.sha256, index_bytes.size(), MEDIA_INDEX)
	var pointer := {format = POINTER_FORMAT, generation = next.generation, index = index_reference,
		transaction_id = _transaction}
	var pointer_written: Dictionary = CreatorBytes.encode(pointer, Limits.STORE_POINTER_BYTES)
	if not pointer_written.ok:
		return _input("pointer")
	var pointer_bytes: PackedByteArray = pointer_written.value.bytes

	# Refuse before anything is written: exact new bytes plus index and both pointer files.
	var needed := new_bytes + index_bytes.size() + pointer_bytes.size() + _pointer_bytes.size()
	if _disk_bytes + needed > _quota:
		return R.fail(R.STORAGE_QUOTA, M_QUOTA, "", "",
			[_megabytes(needed, true), _megabytes(maxi(_quota - _disk_bytes, 0)), _megabytes(_quota)])
	var directory := DirAccess.open(_root)
	var disk_free := 0 if directory == null else directory.get_space_left()
	if disk_free > 0 and needed > disk_free:
		return R.fail(R.STORAGE_QUOTA, M_DISK, "", "", [_megabytes(needed, true), _megabytes(disk_free)])

	var first := true
	for object: Dictionary in pending:
		var installed := _install(object.sha256, object.bytes, first)
		if not installed.ok:
			return installed
		first = false
	if _fault(FAULT_BEFORE_INDEX_WRITE):
		return _interrupted()
	var index_installed := _install(index_written.value.sha256, index_bytes, false)
	if not index_installed.ok:
		return index_installed
	if _fault(FAULT_AFTER_INDEX_WRITE):
		return _interrupted()

	var staging := _root.path_join(STAGING_DIRECTORY)
	var current_path := _root.path_join(CURRENT_FILE)
	var previous_path := _root.path_join(PREVIOUS_FILE)
	var pointer_temp := staging.path_join(_transaction + "-current.tmp")
	var previous_temp := staging.path_join(_transaction + "-previous.tmp")
	var staged := _write_checked(pointer_temp, pointer_bytes)
	if staged.is_empty():
		staged = _write_checked(previous_temp, _pointer_bytes)
	if not staged.is_empty():
		_discard([pointer_temp, previous_temp])
		return R.fail(R.WRITE_FAILED, M_WRITE, "", "", [staged])
	if _fault(FAULT_MID_PREVIOUS_REPLACE):
		DirAccess.remove_absolute(previous_path)
		return _interrupted()
	# The accepted pointer becomes previous.json first; current.json still names the old state.
	if DirAccess.rename_absolute(previous_temp, previous_path) != OK \
			or _read_file(previous_path, Limits.STORE_POINTER_BYTES).get("bytes") != _pointer_bytes:
		_discard([pointer_temp, previous_temp])
		return R.fail(R.WRITE_FAILED, M_WRITE, "", "", ["the previous pointer could not be kept"])
	if _fault(FAULT_AFTER_PREVIOUS_POINTER) or _fault(FAULT_BEFORE_CURRENT_REPLACE):
		return _interrupted()
	if _fault(FAULT_MID_CURRENT_REPLACE):
		DirAccess.remove_absolute(current_path)
		return _interrupted()

	# Commit point.
	var replaced := DirAccess.rename_absolute(pointer_temp, current_path)
	if _fault(FAULT_AFTER_CURRENT_REPLACE):
		return _interrupted()
	var landed := _read_file(current_path, Limits.STORE_POINTER_BYTES)
	if _fault(FAULT_READBACK_LOST):
		landed = {state = "error", bytes = PackedByteArray()}
	if landed.state == "ok" and landed.bytes == _pointer_bytes:
		# The replace did not happen and the old pointer is intact: an ordinary failure.
		_discard([pointer_temp])
		return R.fail(R.WRITE_FAILED, M_WRITE, "", "", ["the pointer could not be replaced (%s)" % error_string(replaced)])
	if landed.state != "ok" or landed.bytes != pointer_bytes \
			or not _read_object(index_reference, Limits.STORE_INDEX_BYTES).ok:
		return _uncertain()
	_pointer = pointer
	_pointer_bytes = pointer_bytes
	_index = index_checked.data
	_recovered = false
	if _fault(FAULT_AFTER_COMMIT):
		return _interrupted()
	return R.ok({generation = generation()})


## Writes one object to staging, reads it back and moves it to its content address. A file that
## already sits there with other bytes is moved to `damaged/`, never overwritten or deleted.
func _install(sha: String, bytes: PackedByteArray, faults: bool) -> Dictionary:
	if faults and _fault(FAULT_BEFORE_OBJECT_WRITE):
		return _interrupted()
	var created := _make_directories()
	if not created.is_empty():
		return R.fail(R.WRITE_FAILED, M_WRITE, "", "", [created])
	_serial += 1
	var temp := _root.path_join(STAGING_DIRECTORY).path_join("%s-%d.tmp" % [_transaction, _serial])
	if faults and _fault(FAULT_MID_OBJECT_WRITE):
		_write_raw(temp, bytes.slice(0, bytes.size() / 2))
		return _interrupted()
	var problem := _write_checked(temp, bytes)
	if not problem.is_empty():
		_discard([temp])
		return R.fail(R.WRITE_FAILED, M_WRITE, "", "", [problem])
	_disk_bytes += bytes.size()
	if faults and _fault(FAULT_AFTER_OBJECT_READBACK):
		return _interrupted()
	var folder := _root.path_join(OBJECTS_DIRECTORY).path_join(sha.substr(0, 2))
	var target := folder.path_join(sha)
	if DirAccess.make_dir_recursive_absolute(folder) != OK or _is_link(folder):
		_discard([temp])
		_disk_bytes -= bytes.size()
		return R.fail(R.WRITE_FAILED, M_WRITE, "", "", ["an object folder could not be created"])
	if FileAccess.file_exists(target) or DirAccess.dir_exists_absolute(target):
		if _read_object(_blob(sha, bytes.size(), MEDIA_SOURCE), bytes.size()).ok:
			_discard([temp])
			_disk_bytes -= bytes.size()
			_verified[sha] = bytes.size()
			return R.ok()
		var aside := _root.path_join(DAMAGED_DIRECTORY).path_join("object-%s-%s" % [sha, _transaction])
		if DirAccess.make_dir_recursive_absolute(aside.get_base_dir()) != OK \
				or DirAccess.rename_absolute(target, aside) != OK:
			_discard([temp])
			_disk_bytes -= bytes.size()
			return R.fail(R.WRITE_FAILED, M_WRITE, "", "", ["a damaged object could not be moved aside"])
	if DirAccess.rename_absolute(temp, target) != OK:
		_discard([temp])
		_disk_bytes -= bytes.size()
		return R.fail(R.WRITE_FAILED, M_WRITE, "", "", ["an object could not be moved into place"])
	_verified[sha] = bytes.size()
	return R.ok()


## True when the object is on disk with exactly these bytes. Verified once per session by hash.
func _object_present(sha: String, size: int) -> bool:
	var path := _object_path(sha)
	if not FileAccess.file_exists(path):
		return false
	if int(_verified.get(sha, -1)) == size:
		return true
	if not _read_object(_blob(sha, size, MEDIA_SOURCE), size).ok:
		return false
	_verified[sha] = size
	return true


func _fault(stage: String) -> bool:
	if _fault_stage != stage:
		return false
	_fault_stage = ""
	_halted = "interrupted"
	return true


func _interrupted() -> Dictionary:
	return R.fail(R.WRITE_FAILED, M_REOPEN, "store/interrupted")


## The pointer could not be read back after the commit point: neither success nor rollback.
func _uncertain() -> Dictionary:
	_halted = "uncertain"
	var failure: Dictionary = R.fail(R.WRITE_FAILED, M_UNCERTAIN, "store/uncertain")
	failure["uncertain"] = true
	return failure


# --- Accepted state ---------------------------------------------------------------------------

func _load_accepted(notes: Array) -> Dictionary:
	var unsafe := _tree_problem()
	if not unsafe.is_empty():
		return R.fail(R.WRITE_FAILED, M_ROOT)
	var current := _read_accepted(CURRENT_FILE)
	# A reader may look while the writer replaces current.json: ask again before giving up on it.
	var attempts := 0
	var worth_asking: bool = current.state == "invalid" or FileAccess.file_exists(_root.path_join(PREVIOUS_FILE))
	while not is_writer() and worth_asking and current.state != "ok" and attempts < 2:
		OS.delay_msec(25)
		attempts += 1
		current = _read_accepted(CURRENT_FILE)
	if current.state == "ok":
		_adopt(current)
	else:
		var previous := _read_accepted(PREVIOUS_FILE)
		if previous.state == "ok":
			_adopt(previous)
			_recovered = true
			notes.append(R.diagnostic(R.WRITE_FAILED, M_RECOVERED, "", "", [], R.SEVERITY_WARNING))
			if is_writer():
				var repaired := _restore_current()
				if not repaired.is_empty():
					close()
					notes.append(R.diagnostic(R.WRITE_FAILED, M_REPAIR_FAILED, "", "", [repaired], R.SEVERITY_WARNING))
		elif current.state == "missing" and previous.state == "missing" and _only_genesis_objects():
			var genesis := _genesis()
			if is_writer():
				var started := _initialize(genesis)
				if not started.is_empty():
					return R.fail(R.WRITE_FAILED, M_WRITE, "", "", [started])
			else:
				_pointer = genesis.pointer
				_pointer_bytes = genesis.pointer_bytes
				_index = genesis.index
		else:
			var reason := str(current.problem) if current.state == "invalid" else str(previous.get("problem", ""))
			if reason.is_empty():
				reason = "the pointer files are missing"
			return R.fail(R.RECORD_INVALID, M_DAMAGED, "", "", [reason, _root])
	if is_writer():
		_clear_staging()
		_disk_bytes = _measure(_root.path_join(OBJECTS_DIRECTORY), 2) \
			+ _measure(_root.path_join(STAGING_DIRECTORY), 1) + _measure(_root.path_join(DAMAGED_DIRECTORY), 1)
	return R.ok()


func _adopt(accepted: Dictionary) -> void:
	_pointer = accepted.pointer
	_pointer_bytes = accepted.bytes
	_index = accepted.index


## Reads one pointer file and everything `open` verifies behind it.
## Returns `{state = "ok" | "missing" | "invalid", problem, bytes, pointer, index}`.
func _read_accepted(file_name: String) -> Dictionary:
	var raw := _read_file(_root.path_join(file_name), Limits.STORE_POINTER_BYTES)
	if raw.state == "missing":
		return {state = "missing", problem = ""}
	if raw.state != "ok":
		return {state = "invalid", problem = "%s cannot be read" % file_name}
	var decoded: Dictionary = CreatorBytes.decode(raw.bytes, POINTER_INTEGERS, Limits.STORE_POINTER_BYTES)
	if not decoded.ok:
		return {state = "invalid", problem = "%s is not a valid pointer" % file_name}
	var pointer: Dictionary = decoded.value.data
	if not _closed(pointer, POINTER_KEYS) or pointer.format != POINTER_FORMAT or not _is_count(pointer.generation) \
			or not _is_uuid(pointer.transaction_id) \
			or not _blob_problem(pointer.index, MEDIA_INDEX, Limits.STORE_INDEX_BYTES).is_empty():
		return {state = "invalid", problem = "%s is not a valid pointer" % file_name}
	var blob := _read_object(pointer.index, Limits.STORE_INDEX_BYTES)
	if not blob.ok:
		return {state = "invalid", problem = "%s names an index where %s" % [file_name, blob.problem]}
	var index := _decode_index(blob.bytes)
	if not index.ok:
		return {state = "invalid", problem = "%s names an index where %s" % [file_name, index.problem]}
	if index.data.generation != pointer.generation or index.data.transaction_id != pointer.transaction_id:
		return {state = "invalid", problem = "%s and its index disagree" % file_name}
	var latest := _latest_problem(index.data)
	if not latest.is_empty():
		return {state = "invalid", problem = "%s names a change where %s" % [file_name, latest]}
	return {state = "ok", problem = "", bytes = raw.bytes, pointer = pointer, index = index.data}


## Deep check of the objects the last transaction added: the records `index` names that its
## predecessor did not, with their payloads. "" when they are intact, or when the predecessor
## cannot be read and so nothing can be told apart.
func _latest_problem(index: Dictionary) -> String:
	if index.predecessor == null:
		return ""
	var before := _read_object(index.predecessor, Limits.STORE_INDEX_BYTES)
	if not before.ok:
		return ""
	var earlier := _decode_index(before.bytes)
	if not earlier.ok:
		return ""
	var known := {}
	for group: String in ["drafts", "recovery"]:
		for id: String in earlier.data[group]:
			known[earlier.data[group][id].record.sha256] = true
	for id: String in earlier.data.aircraft:
		for listed: Dictionary in earlier.data.aircraft[id].revisions:
			known[listed.record.sha256] = true
	for id: String in index.drafts:
		var entry: Dictionary = index.drafts[id]
		if not known.has(entry.record.sha256) and not _load_draft_record(entry.record, id, entry).ok:
			return "a saved draft is incomplete"
	for id: String in index.recovery:
		var slot: Dictionary = index.recovery[id]
		if not known.has(slot.record.sha256) and not _load_draft_record(slot.record, id, {}).ok:
			return "an automatic backup is incomplete"
	for id: String in index.aircraft:
		for listed: Dictionary in index.aircraft[id].revisions:
			if not known.has(listed.record.sha256) and not _load_revision_record(listed, id).ok:
				return "a saved aircraft is incomplete"
	return ""


## Decodes and validates index bytes. Returns `{ok, data}` or `{ok = false, problem}`.
static func _decode_index(bytes: PackedByteArray) -> Dictionary:
	var decoded: Dictionary = CreatorBytes.decode(bytes, INDEX_INTEGERS, Limits.STORE_INDEX_BYTES)
	if not decoded.ok:
		return {ok = false, problem = "the index is not readable"}
	var index: Dictionary = decoded.value.data
	var problem := _index_problem(index)
	if not problem.is_empty():
		return {ok = false, problem = problem}
	return {ok = true, data = index}


static func _index_problem(index: Dictionary) -> String:
	if not _closed(index, INDEX_KEYS) or index.format != INDEX_FORMAT:
		return "the index has an unknown shape"
	if not _is_count(index.generation) or not _is_count(index.stored_bytes) or not _is_uuid(index.transaction_id) \
			or typeof(index.aircraft) != TYPE_DICTIONARY or typeof(index.drafts) != TYPE_DICTIONARY \
			or typeof(index.recovery) != TYPE_DICTIONARY:
		return "the index has an invalid field"
	if index.predecessor != null and not _blob_problem(index.predecessor, MEDIA_INDEX, Limits.STORE_INDEX_BYTES).is_empty():
		return "the index names its predecessor wrongly"
	if (index.predecessor == null) != (index.generation == 0):
		return "the index has an invalid field"
	var aircraft: Dictionary = index.aircraft
	var drafts: Dictionary = index.drafts
	var recovery: Dictionary = index.recovery
	if aircraft.size() > Limits.STORE_AIRCRAFT or drafts.size() > Limits.STORE_DRAFTS:
		return "the index lists too many entries"
	for id: Variant in aircraft:
		var entry: Variant = aircraft[id]
		if not _is_uuid(id) or not _closed(entry, INDEX_AIRCRAFT_KEYS) or not _is_name(entry.name, false) \
				or typeof(entry.archived) != TYPE_BOOL or typeof(entry.revisions) != TYPE_ARRAY:
			return "the index lists an aircraft wrongly"
		var revisions: Array = entry.revisions
		if revisions.is_empty() or revisions.size() > Limits.STORE_REVISIONS_PER_AIRCRAFT \
				or not _is_count(entry.current_revision) or entry.current_revision != revisions.size():
			return "the index lists an aircraft wrongly"
		for position: int in revisions.size():
			var listed: Variant = revisions[position]
			if not _closed(listed, INDEX_REVISION_KEYS) or not _is_count(listed.revision) \
					or listed.revision != position + 1 or not _is_count(listed.created_unix) \
					or not _blob_problem(listed.record, MEDIA_REVISION, Limits.DRAFT_BYTES).is_empty():
				return "the index lists an aircraft version wrongly"
	for id: Variant in drafts:
		var entry: Variant = drafts[id]
		if not _is_uuid(id) or not _closed(entry, INDEX_DRAFT_KEYS) or not _is_name(entry.name, false) \
				or typeof(entry.aircraft_uuid) != TYPE_STRING \
				or not (entry.aircraft_uuid == "" or _is_uuid(entry.aircraft_uuid)) \
				or typeof(entry.archived) != TYPE_BOOL or not _is_count(entry.updated_unix) \
				or not _blob_problem(entry.record, MEDIA_DRAFT, Limits.DRAFT_BYTES).is_empty():
			return "the index lists a draft wrongly"
	for id: Variant in recovery:
		var entry: Variant = recovery[id]
		if not _is_uuid(id) or not _closed(entry, INDEX_RECOVERY_KEYS) or not _is_count(entry.updated_unix) \
				or not _blob_problem(entry.record, MEDIA_DRAFT, Limits.DRAFT_BYTES).is_empty():
			return "the index lists an automatic backup wrongly"
	return ""


## The fixed first state: `{index, index_bytes, pointer, pointer_bytes}`.
static func _genesis() -> Dictionary:
	var index := {format = INDEX_FORMAT, generation = 0, transaction_id = GENESIS_TRANSACTION, predecessor = null,
		stored_bytes = 0, aircraft = {}, drafts = {}, recovery = {}}
	var index_written: Dictionary = CreatorBytes.encode(index)
	var index_bytes: PackedByteArray = index_written.value.bytes
	var pointer := {format = POINTER_FORMAT, generation = 0, transaction_id = GENESIS_TRANSACTION,
		index = _blob(index_written.value.sha256, index_bytes.size(), MEDIA_INDEX)}
	var pointer_written: Dictionary = CreatorBytes.encode(pointer)
	return {index = _decode_index(index_bytes).data, index_bytes = index_bytes, index_sha256 = index_written.value.sha256,
		pointer = pointer, pointer_bytes = pointer_written.value.bytes}


## Writes the first index and pointer of an empty root. Returns "" or the reason it failed.
func _initialize(genesis: Dictionary) -> String:
	_transaction = _new_uuid()
	_serial = 0
	var installed := _install(genesis.index_sha256, genesis.index_bytes, false)
	if not installed.ok:
		return str(installed.diagnostics[0].arguments[0])
	var temp := _root.path_join(STAGING_DIRECTORY).path_join(_transaction + "-current.tmp")
	var problem := _write_checked(temp, genesis.pointer_bytes)
	if problem.is_empty() and DirAccess.rename_absolute(temp, _root.path_join(CURRENT_FILE)) != OK:
		problem = "the first pointer could not be put in place"
	if not problem.is_empty():
		_discard([temp])
		return problem
	_pointer = genesis.pointer
	_pointer_bytes = genesis.pointer_bytes
	_index = genesis.index
	return ""


## After a fallback: current.json again names the accepted (previous) pointer. A damaged
## current.json is moved to `damaged/` first. Returns "" or the reason it failed.
func _restore_current() -> String:
	var created := _make_directories()
	if not created.is_empty():
		return created
	var current_path := _root.path_join(CURRENT_FILE)
	var token := _new_uuid()
	if FileAccess.file_exists(current_path):
		var aside := _root.path_join(DAMAGED_DIRECTORY).path_join("pointer-%s.json" % token)
		if DirAccess.make_dir_recursive_absolute(aside.get_base_dir()) != OK \
				or DirAccess.rename_absolute(current_path, aside) != OK:
			return "the damaged pointer could not be moved aside"
	var temp := _root.path_join(STAGING_DIRECTORY).path_join(token + "-current.tmp")
	var problem := _write_checked(temp, _pointer_bytes)
	if problem.is_empty() and DirAccess.rename_absolute(temp, current_path) != OK:
		problem = "the pointer could not be put back in place"
	if not problem.is_empty():
		_discard([temp])
	return problem


## True when the root holds no object, or only the fixed first index (an interrupted first start).
func _only_genesis_objects() -> bool:
	var files := _files(_root.path_join(OBJECTS_DIRECTORY), 2)
	if files.is_empty():
		return true
	var genesis := _genesis()
	return files.size() == 1 and files[0] == _object_path(genesis.index_sha256) \
		and _read_object(genesis.pointer.index, Limits.STORE_INDEX_BYTES).ok


# --- Files ------------------------------------------------------------------------------------

func _object_path(sha: String) -> String:
	return _root.path_join(OBJECTS_DIRECTORY).path_join(sha.substr(0, 2)).path_join(sha)


## Reads the object a validated BlobRef names and checks length and SHA-256.
## Returns `{ok, bytes}` or `{ok = false, problem}`.
func _read_object(reference: Dictionary, max_bytes: int) -> Dictionary:
	var sha := str(reference.sha256)
	var size := int(reference.byte_length)
	if not CreatorBytes.is_sha256(sha) or size < 1 or size > max_bytes:
		return {ok = false, problem = "a stored file is named wrongly"}
	var raw := _read_file(_object_path(sha), size)
	if raw.state == "missing":
		return {ok = false, problem = "a stored file is missing"}
	if raw.state != "ok" or (raw.bytes as PackedByteArray).size() != size or CreatorBytes.sha256(raw.bytes) != sha:
		return {ok = false, problem = "a stored file is damaged"}
	return {ok = true, bytes = raw.bytes}


## Bounded whole-file read without engine log output.
## Returns `{state = "ok" | "missing" | "error", bytes}`; empty and oversized files are "error".
static func _read_file(path: String, max_bytes: int) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {state = "missing", bytes = PackedByteArray()}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {state = "error", bytes = PackedByteArray()}
	var length := file.get_length()
	if length < 1 or length > max_bytes:
		file.close()
		return {state = "error", bytes = PackedByteArray()}
	var bytes := file.get_buffer(length)
	var failed := file.get_error() != OK
	file.close()
	if failed or bytes.size() != length:
		return {state = "error", bytes = PackedByteArray()}
	return {state = "ok", bytes = bytes}


## Writes, flushes and closes. Returns "" or the reason.
static func _write_raw(path: String, bytes: PackedByteArray) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "a temporary file could not be created (%s)" % error_string(FileAccess.get_open_error())
	if not bytes.is_empty():
		file.store_buffer(bytes)
	file.flush()
	var failed := file.get_error() != OK
	file.close()
	return "a temporary file could not be written" if failed else ""


## Writes a file and reads it back: same length, same bytes. Returns "" or the reason.
static func _write_checked(path: String, bytes: PackedByteArray) -> String:
	var problem := _write_raw(path, bytes)
	if not problem.is_empty():
		return problem
	var back := _read_file(path, bytes.size())
	if back.state != "ok" or back.bytes != bytes:
		return "a temporary file did not read back as written"
	return ""


static func _discard(paths: Array) -> void:
	for path: String in paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## Creates the root, objects and staging folders. Returns "" or the reason.
func _make_directories() -> String:
	for path: String in [_root, _root.path_join(OBJECTS_DIRECTORY), _root.path_join(STAGING_DIRECTORY)]:
		if not DirAccess.dir_exists_absolute(path) and DirAccess.make_dir_recursive_absolute(path) != OK:
			return "a library folder could not be created"
	return _tree_problem()


## "" when the root, every folder above it up to the user data folder, and the store's own
## folders are plain folders: a link would move writes somewhere this store did not choose.
func _tree_problem() -> String:
	var user := ProjectSettings.globalize_path("user://").replace("\\", "/").trim_suffix("/")
	var paths: Array[String] = [_root.path_join(OBJECTS_DIRECTORY), _root.path_join(STAGING_DIRECTORY),
		_root.path_join(DAMAGED_DIRECTORY)]
	var ancestor := _root
	while ancestor.length() > user.length():
		paths.append(ancestor)
		ancestor = ancestor.get_base_dir()
	for path: String in paths:
		if FileAccess.file_exists(path) or _is_link(path):
			return "a library folder is a link or a file"
	return ""


static func _is_link(path: String) -> bool:
	var parent := DirAccess.open(path.get_base_dir())
	return parent != null and parent.is_link(path)


## Paths of the plain files below `path`, `depth` folder levels deep. Links are not followed.
static func _files(path: String, depth: int) -> PackedStringArray:
	var found := PackedStringArray()
	var directory := DirAccess.open(path)
	if directory == null:
		return found
	directory.include_hidden = true
	directory.list_dir_begin()
	while true:
		var entry := directory.get_next()
		if entry.is_empty():
			break
		var child := path.path_join(entry)
		if directory.is_link(child):
			continue
		if not directory.current_is_dir():
			found.append(child)
		elif depth > 1:
			found.append_array(_files(child, depth - 1))
	directory.list_dir_end()
	return found


static func _measure(path: String, depth: int) -> int:
	var total := 0
	for file_path: String in _files(path, depth):
		var file := FileAccess.open(file_path, FileAccess.READ)
		if file != null:
			total += file.get_length()
			file.close()
	return total


## Staging holds only unfinished temporary files of earlier transactions; none is ever accepted.
func _clear_staging() -> void:
	for file_path: String in _files(_root.path_join(STAGING_DIRECTORY), 1):
		if file_path.ends_with(".tmp"):
			DirAccess.remove_absolute(file_path)


## The absolute root, or "" when it is not a safe plain path under the user data folder.
static func _resolve_root(root: String) -> String:
	if not root.begins_with("user://") or root.contains("\\"):
		return ""
	var relative := root.substr("user://".length())
	while relative.ends_with("/"):
		relative = relative.substr(0, relative.length() - 1)
	if relative.is_empty():
		return ""
	for segment: String in relative.split("/", true):
		if segment.is_empty() or segment == "." or segment == ".." or segment.length() > 120:
			return ""
		for index: int in segment.length():
			var code := segment.unicode_at(index)
			if not ((code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122)
					or code == 45 or code == 95 or code == 46):
				return ""
	var user := ProjectSettings.globalize_path("user://").replace("\\", "/").trim_suffix("/")
	var absolute := ProjectSettings.globalize_path("user://" + relative).replace("\\", "/")
	if absolute != absolute.simplify_path() or not absolute.to_lower().begins_with(user.to_lower() + "/"):
		return ""
	return absolute


# --- Records and values -----------------------------------------------------------------------

## Encodes a record once and proves the reader accepts those bytes, so nothing is stored that
## could not be loaded. Value = `{bytes, sha256}`. `what` names the record in messages.
static func _encode_record(record: Dictionary, integers: PackedStringArray, what: String,
		max_bytes: int = Limits.DRAFT_BYTES) -> Dictionary:
	var written: Dictionary = CreatorBytes.encode(record, max_bytes)
	if not written.ok:
		if str(written.diagnostics[0].code) == R.SOURCE_LIMIT:
			return R.fail(R.SOURCE_LIMIT, M_RECORD_SIZE, what, "", [_megabytes(max_bytes)])
		return R.fail(R.RECORD_INVALID, M_TEXT, what, "", [what, R.texts(written)[0]])
	var read: Dictionary = CreatorBytes.decode(written.value.bytes, integers, max_bytes)
	if not read.ok:
		return R.fail(R.RECORD_INVALID, M_TEXT, what, "", [what, R.texts(read)[0]])
	return R.ok({bytes = written.value.bytes, sha256 = written.value.sha256})


## Deep copy of an opaque JSON member with String keys and every number a finite float.
static func _plain_member(member: Dictionary, what: String) -> Dictionary:
	var problems := PackedStringArray()
	var plain: Variant = _plain(member, 0, problems)
	if not problems.is_empty():
		return R.fail(R.RECORD_INVALID, M_TEXT, what, "", [what, problems[0]])
	return R.ok(plain)


static func _plain(node: Variant, depth: int, problems: PackedStringArray) -> Variant:
	if depth > Limits.JSON_DEPTH:
		problems.append("it is nested too deeply")
		return null
	match typeof(node):
		TYPE_NIL, TYPE_BOOL:
			return node
		TYPE_STRING, TYPE_STRING_NAME:
			# Text the reader would refuse is caught when the encoded record is read back.
			return str(node)
		TYPE_INT:
			if absi(node) > Limits.MAX_SAFE_INTEGER:
				problems.append("a whole number is too large")
			return float(node)
		TYPE_FLOAT:
			if not is_finite(node):
				problems.append("a number is not finite")
				return 0.0
			return 0.0 if node == 0.0 else node
		TYPE_ARRAY:
			var items: Array = []
			for item: Variant in node:
				items.append(_plain(item, depth + 1, problems))
			return items
		TYPE_DICTIONARY:
			var fields := {}
			for key: Variant in node:
				if typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME:
					problems.append("a key is not text")
					continue
				fields[str(key)] = _plain(node[key], depth + 1, problems)
			return fields
	problems.append("a value is not text, a number, a list or a table")
	return null


## True for a control character, DEL or a lone surrogate (which UTF-8 cannot carry).
static func _has_control(text: String) -> bool:
	for index: int in text.length():
		var code := text.unicode_at(index)
		if code < 32 or code == 127 or (code >= 0xD800 and code <= 0xDFFF):
			return true
	return false


static func _blob(sha: String, size: int, media: String) -> Dictionary:
	return {sha256 = sha, byte_length = size, media_type = media}


## "" for a well-formed BlobRef of the expected media type within `max_bytes`.
static func _blob_problem(reference: Variant, media: String, max_bytes: int) -> String:
	if not _closed(reference, BLOB_KEYS) or not CreatorBytes.is_sha256(reference.sha256) \
			or not _is_count(reference.byte_length) or reference.byte_length < 1 \
			or reference.byte_length > max_bytes or typeof(reference.media_type) != TYPE_STRING \
			or reference.media_type != media:
		return "a file reference is malformed"
	return ""


## True for a Dictionary with exactly these keys.
static func _closed(value: Variant, keys: Array) -> bool:
	if typeof(value) != TYPE_DICTIONARY or (value as Dictionary).size() != keys.size():
		return false
	for key: String in keys:
		if not (value as Dictionary).has(key):
			return false
	return true


static func _is_count(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value >= 0 and value <= Limits.MAX_SAFE_INTEGER


## Lowercase UUID version 4.
static func _is_uuid(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or (value as String).length() != 36:
		return false
	var text: String = value
	for index: int in 36:
		var character := text[index]
		if index == 8 or index == 13 or index == 18 or index == 23:
			if character != "-":
				return false
		elif character not in "0123456789abcdef":
			return false
	return text[14] == "4" and text[19] in "89ab"


## A display name: text of at most `Limits.NAME_CHARACTERS` without control characters.
static func _is_name(value: Variant, empty_allowed: bool) -> bool:
	if typeof(value) != TYPE_STRING or (value as String).length() > Limits.NAME_CHARACTERS:
		return false
	var text: String = value
	if text.strip_edges().is_empty():
		return empty_allowed and text.is_empty()
	return not _has_control(text)


## A bare file name for display, or "": never a path, a drive or a URL.
static func _is_file_name(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or (value as String).length() > Limits.SOURCE_FILE_NAME_CHARACTERS:
		return false
	var text: String = value
	if text == "." or text == ".." or _has_control(text):
		return false
	for character: String in ["/", "\\", ":"]:
		if text.contains(character):
			return false
	return true


static func _input(what: String) -> Dictionary:
	return R.fail(R.RECORD_INVALID, M_INPUT, what, "", [what])


static func _entry_damaged(problem: String) -> Dictionary:
	var missing := problem.ends_with("is missing")
	return R.fail(R.DEPENDENCY_MISSING if missing else R.RECORD_INVALID, M_ENTRY_DAMAGED, "", "", [problem])


## Megabytes with one decimal, rounded down, or up for an amount that is needed.
static func _megabytes(bytes: int, up: bool = false) -> String:
	var tenths := float(bytes) * 10.0 / float(Limits.MIB)
	return String.num((ceilf(tenths) if up else floorf(tenths)) / 10.0, 1)


static func _now() -> int:
	return int(Time.get_unix_time_from_system())


static func _new_uuid() -> String:
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0F) | 0x40
	bytes[8] = (bytes[8] & 0x3F) | 0x80
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]

## Bounded, asynchronous storage for complete Float64 trace chunks.
## Main-thread API; the worker owns no scene objects and never references this store.
## A flushed file is not a guarantee of power-loss durability. Unpublished tails
## remain with the caller; recovered CSVs are explicitly incomplete.
extends RefCounted

const DEFAULT_DIRECTORY := "user://trace_spools"
const MAX_CHUNK_BYTES := 1024 * 1024
const MAX_META_BYTES := 64 * 1024
const MAX_ROWS := 4096
const MAX_QUEUE := 2
const MAGIC := "ORCTRC1\n"
const FIXED_BYTES := 24
const DIGEST_BYTES := 32


class Worker extends RefCounted:
	var mutex := Mutex.new()
	var wake := Semaphore.new()
	var queue: Array = [] # Includes an in-flight first entry.
	var failure: Error = OK
	var stopping := false
	var abort := false
	var published := 0
	var directory := ""
	var base_directory := ""
	var identity := ""
	var stage_owned := false
	var stage_index := -1
	var hook: RefCounted # Test-only injectable phase hook; never derived from app arguments.

	func run() -> void:
		while true:
			wake.wait()
			mutex.lock()
			if abort or failure != OK or (stopping and queue.is_empty()):
				mutex.unlock()
				return
			if queue.is_empty():
				mutex.unlock()
				continue
			var item: Dictionary = queue[0]
			mutex.unlock()
			var err := _write_chunk(item)
			mutex.lock()
			if err == OK:
				queue.pop_front()
				published += 1
			else:
				failure = err
			var done := err != OK or abort or (stopping and queue.is_empty())
			mutex.unlock()
			if done:
				return

	func _ensure_directory() -> Error:
		if directory.is_empty():
			var err := DirAccess.make_dir_recursive_absolute(base_directory)
			if err != OK and not (err == ERR_ALREADY_EXISTS and DirAccess.dir_exists_absolute(base_directory)):
				return err
			var candidate := base_directory.path_join("trace-" + identity)
			err = DirAccess.make_dir_absolute(candidate)
			if err != OK:
				return err
			mutex.lock()
			directory = candidate
			mutex.unlock()
		if not stage_owned:
			var err := DirAccess.make_dir_absolute(directory.path_join("stage"))
			if err != OK:
				return err
			mutex.lock()
			stage_owned = true
			mutex.unlock()
		return OK

	func _phase(phase: String, index: int) -> Error:
		if hook == null:
			return OK
		return hook.phase(phase, index)

	func _write_chunk(item: Dictionary) -> Error:
		var index: int = item.index
		var err := _phase("before_write", index)
		if err != OK:
			return err
		err = _ensure_directory()
		if err != OK:
			return err
		err = _phase("after_directory", index)
		if err != OK:
			return err
		var basename := "chunk-%016d.bin" % index
		var staged := directory.path_join("stage").path_join(basename + ".partial")
		var destination := directory.path_join(basename)
		if FileAccess.file_exists(destination) or DirAccess.dir_exists_absolute(destination):
			return ERR_ALREADY_EXISTS
		if (FileAccess.file_exists(staged) or DirAccess.dir_exists_absolute(staged)) and stage_index != index:
			return ERR_ALREADY_EXISTS
		var meta: PackedByteArray = item.meta
		var values: PackedFloat64Array = item.values
		var raw := values.to_byte_array()
		var prefix := PackedByteArray()
		prefix.resize(FIXED_BYTES)
		var magic := MAGIC.to_utf8_buffer()
		for i in magic.size():
			prefix[i] = magic[i]
		prefix.encode_u64(8, index)
		prefix.encode_u32(16, meta.size())
		prefix.encode_u32(20, raw.size())
		var hash := HashingContext.new()
		err = hash.start(HashingContext.HASH_SHA256)
		if err != OK:
			return err
		hash.update(prefix)
		hash.update(meta)
		hash.update(raw)
		var digest := hash.finish()
		var file := FileAccess.open(staged, FileAccess.WRITE)
		if file == null:
			return FileAccess.get_open_error()
		mutex.lock()
		stage_index = index
		mutex.unlock()
		var written := file.store_buffer(prefix) and file.store_buffer(meta) \
			and file.store_buffer(raw) and file.store_buffer(digest)
		file.flush()
		err = file.get_error()
		file.close()
		if not written or err != OK:
			return err if err != OK else ERR_FILE_CANT_WRITE
		err = _phase("after_flush", index)
		if err != OK:
			return err
		# This is the only writer in an exclusively reserved directory.
		if FileAccess.file_exists(destination) or DirAccess.dir_exists_absolute(destination):
			return ERR_ALREADY_EXISTS
		err = DirAccess.rename_absolute(staged, destination)
		if err == OK:
			mutex.lock()
			stage_index = -1
			mutex.unlock()
		return err

	## Called by the dying outer owner after joining. This state object remains
	## alive independently and validates each published packet before deletion.
	func cleanup_saved(columns: Array, rows: int) -> void:
		if directory.is_empty():
			return
		var dir := DirAccess.open(directory)
		if dir == null or dir.is_link(directory):
			return
		var script: Script = load("res://sim/trace_chunk_store.gd")
		for index in published:
			var basename := "chunk-%016d.bin" % index
			var path := directory.path_join(basename)
			if FileAccess.file_exists(path) and not dir.is_link(basename):
				var packet: Dictionary = script._read_packet(path, index, columns, rows, identity)
				if packet.error == OK:
					DirAccess.remove_absolute(path)
		if stage_owned and not dir.is_link("stage"):
			var stage_path := directory.path_join("stage")
			var stage := DirAccess.open(stage_path)
			if stage != null and stage_index >= 0:
				var partial := ("chunk-%016d.bin" % stage_index) + ".partial"
				if FileAccess.file_exists(stage_path.path_join(partial)) and not stage.is_link(partial):
					DirAccess.remove_absolute(stage_path.path_join(partial))
			if stage != null:
				DirAccess.remove_absolute(stage_path)
		DirAccess.remove_absolute(directory)


var _columns: Array = []
var _chunk_rows := 0
var _config_error: Error = OK
var _identity := ""
var _state := Worker.new()
var _thread: Thread
var _accepted := 0
var _last_header := ""
var _read_error: Error = OK
var _cached_index := -1
var _cached_values := PackedFloat64Array()
var _saved := false
var _discarded := false
var _cleanup_error: Error = OK
var _cleanup_path := ""


func _init(columns: Array, chunk_rows: int, directory: String = DEFAULT_DIRECTORY,
		test_hook: RefCounted = null) -> void:
	_columns = columns.duplicate()
	_chunk_rows = chunk_rows
	_config_error = _validate_schema(_columns, _chunk_rows)
	if not _is_little_endian():
		_config_error = ERR_UNAVAILABLE
	var id_bytes := Crypto.new().generate_random_bytes(16)
	if id_bytes.size() != 16:
		_config_error = ERR_CANT_CREATE
	_identity = id_bytes.hex_encode()
	if directory.is_empty():
		_config_error = ERR_INVALID_PARAMETER
	_state.base_directory = ProjectSettings.globalize_path(directory)
	_state.identity = _identity
	_state.hook = test_hook


## OK means a full chunk was accepted. Packed arrays are reference-shared, so a
## bounded duplicate protects queued bytes if the caller mutates its array.
func append_chunk(values: PackedFloat64Array, header: String) -> Error:
	if _discarded:
		return ERR_UNCONFIGURED
	if _config_error != OK:
		return _config_error
	if values.size() != _columns.size() * _chunk_rows or header.is_empty():
		return ERR_INVALID_PARAMETER
	if not _valid_header(header, _columns):
		return ERR_INVALID_PARAMETER
	var meta := JSON.stringify({"id": _identity, "encoding": "float64-le", "columns": _columns,
		"rows": _chunk_rows, "header": header}).to_utf8_buffer()
	if meta.size() > MAX_META_BYTES:
		return ERR_INVALID_PARAMETER
	_state.mutex.lock()
	var failure := _state.failure
	var full := _state.queue.size() >= MAX_QUEUE
	_state.mutex.unlock()
	if failure != OK:
		return failure
	if full:
		return ERR_BUSY
	if _accepted >= 0x7fffffffffffffff / _chunk_rows:
		return ERR_OUT_OF_MEMORY
	if _thread == null:
		var err := _start_worker(false)
		if err != OK:
			return err
	_state.mutex.lock()
	# The worker can fail while the metadata is prepared or the thread starts.
	if _state.failure != OK:
		failure = _state.failure
		_state.mutex.unlock()
		return failure
	if _state.queue.size() >= MAX_QUEUE:
		_state.mutex.unlock()
		return ERR_BUSY
	_state.queue.append({"index": _accepted, "values": values.duplicate(), "meta": meta})
	_accepted += 1
	_last_header = header
	_saved = false
	_state.mutex.unlock()
	_state.wake.post()
	return OK


func row_count() -> int:
	return _accepted * _chunk_rows


## Diagnostic snapshot: queued/in-flight and one decoded cache, in raw bytes.
## Excludes the caller's tail and temporary conversion, hashing and I/O buffers.
func buffered_bytes() -> int:
	var bytes := _cached_values.size() * 8
	_state.mutex.lock()
	for item: Dictionary in _state.queue:
		var values: PackedFloat64Array = item.values
		bytes += values.size() * 8
	_state.mutex.unlock()
	return bytes


func write_error() -> Error:
	_state.mutex.lock()
	var result := _state.failure
	_state.mutex.unlock()
	return result


func read_error() -> Error:
	return _read_error


func last_header() -> String:
	return _last_header


func directory_path() -> String:
	_state.mutex.lock()
	var result := _state.directory
	_state.mutex.unlock()
	return result


## A bad index, missing file or invalid packet returns an empty array and sets
## read_error(); no failed read is represented as a valid zero-filled row.
func row(index: int) -> PackedFloat64Array:
	_read_error = OK
	if _discarded or index < 0 or index >= row_count():
		_read_error = ERR_INVALID_PARAMETER
		return PackedFloat64Array()
	var chunk_index := int(index / _chunk_rows)
	var offset := (index % _chunk_rows) * _columns.size()
	_state.mutex.lock()
	var published := _state.published
	if chunk_index >= published:
		var queue_index := chunk_index - published
		if queue_index < 0 or queue_index >= _state.queue.size():
			_state.mutex.unlock()
			_read_error = ERR_FILE_CORRUPT
			return PackedFloat64Array()
		var values: PackedFloat64Array = _state.queue[queue_index].values
		var result := values.slice(offset, offset + _columns.size())
		_state.mutex.unlock()
		return result
	var directory := _state.directory
	_state.mutex.unlock()
	if _cached_index != chunk_index:
		var packet := _read_packet(directory.path_join(_chunk_name(chunk_index)), chunk_index, _columns, _chunk_rows, _identity)
		_read_error = packet.error
		if _read_error != OK:
			_cached_index = -1
			_cached_values.clear()
			return PackedFloat64Array()
		_cached_values = packet.values
		_cached_index = chunk_index
	return _cached_values.slice(offset, offset + _columns.size())


func _start_worker(stopping: bool) -> Error:
	_state.mutex.lock()
	_state.stopping = stopping
	_state.abort = false
	_state.failure = OK
	_state.mutex.unlock()
	_thread = Thread.new()
	var err := _thread.start(Callable(_state, "run"))
	if err != OK:
		_thread = null
		_state.mutex.lock()
		_state.failure = err
		_state.mutex.unlock()
	return err


## Join the worker and flush all accepted chunks. A failure that was already
## reported before this call is retried once; a new failure is returned and
## remains queued for a later explicit drain.
func drain() -> Error:
	if _discarded:
		return ERR_UNCONFIGURED
	if _config_error != OK:
		return _config_error
	var previous := write_error()
	var had_thread := _thread != null
	if _thread != null:
		_join(false)
	if previous != OK or not had_thread:
		_state.mutex.lock()
		var pending := not _state.queue.is_empty()
		_state.mutex.unlock()
		if pending:
			var start_error := _start_worker(true)
			if start_error != OK:
				return start_error
			_state.wake.post()
			_thread.wait_to_finish()
			_thread = null
	return write_error()


func _join(abort: bool) -> void:
	if _thread == null:
		return
	_state.mutex.lock()
	_state.stopping = true
	_state.abort = abort
	_state.mutex.unlock()
	_state.wake.post()
	_thread.wait_to_finish()
	_thread = null


## Call only after the caller has published the complete final CSV.
func mark_saved() -> void:
	_saved = true


## On a preflight or rename failure every accepted row stays owned and readable.
## Once the spool has been atomically moved to a reserved sibling, discard has
## committed. Cleanup failures then leave that isolated path for inspection.
func discard() -> Error:
	if _discarded:
		return OK
	_join(true)
	var directory := directory_path()
	var container := ""
	if not directory.is_empty():
		var err := _preflight_owned(directory)
		if err != OK:
			return err
		for attempt in 10000:
			container = directory.get_base_dir().path_join(".discard-%s-%d" % [_identity, attempt])
			err = DirAccess.make_dir_absolute(container)
			if err == ERR_ALREADY_EXISTS:
				continue
			if err != OK:
				return err
			break
		if err != OK:
			return err
		if _state.hook != null:
			err = _state.hook.phase("discard_before_rename", 0)
		if err == OK:
			err = DirAccess.rename_absolute(directory, container.path_join("spool"))
		if err != OK:
			DirAccess.remove_absolute(container)
			return err
		_state.mutex.lock()
		_state.directory = container.path_join("spool")
		_state.mutex.unlock()
	_state.mutex.lock()
	_state.queue.clear()
	_state.mutex.unlock()
	_cached_values.clear()
	_discarded = true
	_cleanup_error = OK
	_cleanup_path = container
	if not container.is_empty():
		if _state.hook != null:
			_cleanup_error = _state.hook.phase("discard_before_cleanup", 0)
		if _cleanup_error == OK:
			_cleanup_error = _remove_owned()
		if _cleanup_error == OK:
			_cleanup_error = DirAccess.remove_absolute(container)
		if _cleanup_error == OK:
			_cleanup_path = ""
	return OK


func cleanup_error() -> Error:
	return _cleanup_error


func cleanup_path() -> String:
	return _cleanup_path


func _preflight_owned(directory: String) -> Error:
	var dir := DirAccess.open(directory)
	if dir == null:
		return DirAccess.get_open_error()
	if dir.is_link(directory):
		return ERR_BUSY
	dir.include_hidden = true
	var err := dir.list_dir_begin()
	if err != OK:
		return err
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if name == "stage" and _state.stage_owned and dir.current_is_dir() and not dir.is_link(name):
			var stage := DirAccess.open(directory.path_join(name))
			if stage == null:
				dir.list_dir_end()
				return DirAccess.get_open_error()
			stage.include_hidden = true
			err = stage.list_dir_begin()
			if err != OK:
				dir.list_dir_end()
				return err
			while true:
				var entry := stage.get_next()
				if entry.is_empty():
					break
				if _state.stage_index < 0 or entry != _chunk_name(_state.stage_index) + ".partial" \
						or stage.current_is_dir() or stage.is_link(entry):
					stage.list_dir_end()
					dir.list_dir_end()
					return ERR_BUSY
			stage.list_dir_end()
			continue
		var basename := name.trim_suffix(".partial")
		var digits := basename.trim_prefix("chunk-").trim_suffix(".bin")
		if dir.current_is_dir() or dir.is_link(name) or not name.begins_with("chunk-") \
				or basename != name or not basename.ends_with(".bin") \
				or digits.length() != 16 or not digits.is_valid_int():
			dir.list_dir_end()
			return ERR_BUSY
		var index := digits.to_int()
		if index < 0 or index >= _state.published or basename != _chunk_name(index):
			dir.list_dir_end()
			return ERR_BUSY
	dir.list_dir_end()
	return OK


func _remove_owned() -> Error:
	var directory := directory_path()
	if directory.is_empty():
		return OK
	var dir := DirAccess.open(directory)
	if dir == null:
		return DirAccess.get_open_error()
	if dir.is_link(directory):
		return ERR_BUSY
	var result: Error = OK
	for index in _state.published:
		var name := _chunk_name(index)
		var path := directory.path_join(name)
		if FileAccess.file_exists(path):
			if dir.is_link(name):
				result = ERR_BUSY
				continue
			var packet := _read_packet(path, index, _columns, _chunk_rows, _identity)
			if packet.error != OK:
				result = packet.error
				continue
			var err := DirAccess.remove_absolute(path)
			if err != OK:
				result = err
	if _state.stage_owned:
		var stage := directory.path_join("stage")
		if dir.is_link("stage"):
			return ERR_BUSY
		var stage_dir := DirAccess.open(stage)
		if _state.stage_index >= 0:
			var name := _chunk_name(_state.stage_index) + ".partial"
			var partial := stage.path_join(name)
			if FileAccess.file_exists(partial):
				if stage_dir == null or stage_dir.is_link(name):
					return ERR_BUSY
				var err := DirAccess.remove_absolute(partial)
				if err != OK:
					result = err
		if DirAccess.dir_exists_absolute(stage):
			var err := DirAccess.remove_absolute(stage)
			if err != OK:
				result = err
	if result != OK:
		return result
	if DirAccess.dir_exists_absolute(directory):
		return DirAccess.remove_absolute(directory)
	return OK


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# RefCounted can no longer dispatch instance methods during PREDELETE.
		if _thread != null:
			_state.mutex.lock()
			_state.stopping = true
			_state.abort = false
			_state.mutex.unlock()
			_state.wake.post()
			_thread.wait_to_finish()
			_thread = null
		if _saved:
			_state.cleanup_saved(_columns, _chunk_rows)


static func _chunk_name(index: int) -> String:
	return "chunk-%016d.bin" % index


static func _is_little_endian() -> bool:
	return PackedFloat64Array([1.0]).to_byte_array() == PackedByteArray([0, 0, 0, 0, 0, 0, 240, 63])


static func _validate_schema(columns: Array, rows: int) -> Error:
	if rows < 1 or rows > MAX_ROWS or columns.is_empty() or columns.size() > MAX_CHUNK_BYTES / (rows * 8):
		return ERR_INVALID_PARAMETER
	for column: Variant in columns:
		if typeof(column) != TYPE_STRING or column.is_empty() or column.contains(",") \
				or column.contains("\n") or column.contains("\r"):
			return ERR_INVALID_PARAMETER
	return OK


static func _valid_header(header: String, columns: Array) -> bool:
	var lines := header.trim_suffix("\n").split("\n")
	return not lines.is_empty() and lines[lines.size() - 1] == ",".join(columns)


## Bounded, object-free packet decoder. Validates exact length, SHA-256, chunk
## index and schema before interpreting raw native-endian float64 bytes.
static func _read_packet(path: String, expected_index: int, expected_columns: Array = [], expected_rows: int = 0,
		expected_id: String = "") -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": FileAccess.get_open_error()}
	var length := file.get_length()
	if length < FIXED_BYTES + DIGEST_BYTES or length > FIXED_BYTES + MAX_META_BYTES + MAX_CHUNK_BYTES + DIGEST_BYTES:
		return {"error": ERR_FILE_CORRUPT}
	var prefix := file.get_buffer(FIXED_BYTES)
	if prefix.size() != FIXED_BYTES or prefix.slice(0, 8) != MAGIC.to_utf8_buffer() \
			or prefix.decode_u64(8) != expected_index:
		return {"error": ERR_FILE_CORRUPT}
	var meta_size := prefix.decode_u32(16)
	var raw_size := prefix.decode_u32(20)
	if meta_size == 0 or meta_size > MAX_META_BYTES or raw_size == 0 or raw_size > MAX_CHUNK_BYTES \
			or raw_size % 8 != 0 or length != FIXED_BYTES + meta_size + raw_size + DIGEST_BYTES:
		return {"error": ERR_FILE_CORRUPT}
	var meta := file.get_buffer(meta_size)
	var raw := file.get_buffer(raw_size)
	var digest := file.get_buffer(DIGEST_BYTES)
	if meta.size() != meta_size or raw.size() != raw_size or digest.size() != DIGEST_BYTES:
		return {"error": ERR_FILE_CORRUPT}
	var hash := HashingContext.new()
	if hash.start(HashingContext.HASH_SHA256) != OK:
		return {"error": ERR_CANT_CREATE}
	hash.update(prefix)
	hash.update(meta)
	hash.update(raw)
	if hash.finish() != digest:
		return {"error": ERR_FILE_CORRUPT}
	var parsed: Variant = JSON.parse_string(meta.get_string_from_utf8())
	if not _is_little_endian() or typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("columns")) != TYPE_ARRAY \
			or typeof(parsed.get("rows")) not in [TYPE_FLOAT, TYPE_INT] or typeof(parsed.get("header")) != TYPE_STRING \
			or typeof(parsed.get("id")) != TYPE_STRING or parsed.get("encoding") != "float64-le":
		return {"error": ERR_FILE_CORRUPT}
	var identity: String = parsed.id
	if identity.length() != 32 or not identity.is_valid_hex_number() or identity != identity.to_lower() \
			or (not expected_id.is_empty() and identity != expected_id):
		return {"error": ERR_FILE_CORRUPT}
	var columns: Array = parsed.columns
	var numeric_rows := float(parsed.rows)
	if not is_finite(numeric_rows) or numeric_rows < 1.0 or numeric_rows > MAX_ROWS \
			or floor(numeric_rows) != numeric_rows:
		return {"error": ERR_FILE_CORRUPT}
	var rows := int(numeric_rows)
	if _validate_schema(columns, rows) != OK \
			or parsed.header.is_empty() or not _valid_header(parsed.header, columns) \
			or raw_size != columns.size() * rows * 8:
		return {"error": ERR_FILE_CORRUPT}
	if (not expected_columns.is_empty() and columns != expected_columns) or (expected_rows > 0 and rows != expected_rows):
		return {"error": ERR_FILE_CORRUPT}
	return {"error": OK, "values": raw.to_float64_array(), "columns": columns, "rows": rows,
		"header": parsed.header, "id": identity, "digest": digest}


## Recover only the contiguous, validated published prefix. `destination` is a
## newly reserved directory; recovered.csv inside it never replaces another file.
## A partial chunk, a gap, corruption, or a mixed session is returned as an error
## while retaining any earlier prefix. The missing tail is always explicit.
static func recover_csv(directory: String, destination: String, test_hook: RefCounted = null) -> Dictionary:
	var result := {"complete": false, "error": OK, "rows": 0, "path": "", "last_header": ""}
	var source := ProjectSettings.globalize_path(directory)
	var output := ProjectSettings.globalize_path(destination)
	if directory.is_empty() or destination.is_empty() or source == output:
		result.error = ERR_INVALID_PARAMETER
		return result
	var dir := DirAccess.open(source)
	if dir == null:
		result.error = DirAccess.get_open_error()
		return result
	var maximum := -1
	var bad_name := false
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if dir.current_is_dir() or not name.begins_with("chunk-"):
			continue
		var basename := name.trim_suffix(".partial")
		if not basename.ends_with(".bin"):
			bad_name = true
			continue
		var digits := basename.trim_prefix("chunk-").trim_suffix(".bin")
		if digits.length() != 16 or not digits.is_valid_int():
			bad_name = true
			continue
		var index := digits.to_int()
		if index < 0 or basename != _chunk_name(index):
			bad_name = true
			continue
		maximum = maxi(maximum, index)
	dir.list_dir_end()
	if maximum < 0:
		result.error = ERR_FILE_CORRUPT if bad_name else ERR_FILE_NOT_FOUND
		return result
	var columns: Array = []
	var rows_per_chunk := 0
	var identity := ""
	var valid_chunks := 0
	var source_hash := HashingContext.new()
	source_hash.start(HashingContext.HASH_SHA256)
	var index := 0
	while index <= maximum:
		var packet := _read_packet(source.path_join(_chunk_name(index)), index, columns, rows_per_chunk, identity)
		if packet.error != OK:
			result.error = packet.error
			break
		if index == 0:
			columns = packet.columns
			rows_per_chunk = packet.rows
			identity = packet.id
		source_hash.update(packet.digest)
		result.last_header = packet.header
		valid_chunks += 1
		index += 1
	if bad_name and result.error == OK:
		result.error = ERR_FILE_CORRUPT
	if valid_chunks == 0:
		return result
	var header: String = result.last_header
	var header_lines := header.trim_suffix("\n").split("\n")
	if header_lines.is_empty() or not header_lines[0].begins_with("# format: "):
		result.error = ERR_FILE_CORRUPT
		return result
	var recovered_header := PackedStringArray([header_lines[0], "# recovery_complete: false", "# trace_capture_complete: false"])
	for line_index in range(1, header_lines.size()):
		var line := header_lines[line_index]
		if not line.strip_edges().begins_with("# recovery_complete:") \
				and not line.strip_edges().begins_with("# trace_capture_complete:"):
			recovered_header.append(line)
	var err := DirAccess.make_dir_absolute(output)
	if err != OK:
		result.error = err
		return result
	var output_path := output.path_join("recovered.csv")
	var staged := output.path_join("recovered.partial")
	var file := FileAccess.open(staged, FileAccess.WRITE)
	if file == null:
		result.error = FileAccess.get_open_error()
		return result
	var written := file.store_string("\n".join(recovered_header) + "\n")
	var helicopter := header.contains("# format: openrc-helicopter-trace")
	var copied_hash := HashingContext.new()
	copied_hash.start(HashingContext.HASH_SHA256)
	var copied_rows := 0
	var copy_error: Error = OK
	if test_hook != null:
		copy_error = test_hook.phase("recovery_before_copy", 0)
	for chunk_index in valid_chunks:
		if not written or copy_error != OK:
			break
		var packet := _read_packet(source.path_join(_chunk_name(chunk_index)), chunk_index, columns, rows_per_chunk, identity)
		if packet.error != OK:
			copy_error = packet.error
			break
		copied_hash.update(packet.digest)
		var values: PackedFloat64Array = packet.values
		var batch := PackedStringArray()
		var characters := 0
		for r in rows_per_chunk:
			var fields := PackedStringArray()
			for c in columns.size():
				var value := values[r * columns.size() + c]
				fields.append(JSON.stringify(value, "", true, true) if helicopter else \
					(str(int(value)) if c == 0 else "%.9f" % value))
			var line := ",".join(fields)
			if characters > 0 and characters + line.length() + 1 > 65536:
				written = file.store_string("\n".join(batch) + "\n")
				batch.clear()
				characters = 0
				if not written:
					break
			batch.append(line)
			characters += line.length() + 1
			copied_rows += 1
		if written and not batch.is_empty():
			written = file.store_string("\n".join(batch) + "\n")
	file.flush()
	err = file.get_error()
	file.close()
	if err == OK and written and test_hook != null:
		err = test_hook.phase("recovery_after_flush", 0)
	if not written or err != OK or copy_error != OK:
		result.error = err if err != OK else (copy_error if copy_error != OK else ERR_FILE_CANT_WRITE)
		if FileAccess.file_exists(staged):
			DirAccess.remove_absolute(staged)
		return result
	if copied_rows != valid_chunks * rows_per_chunk or source_hash.finish() != copied_hash.finish():
		result.error = ERR_FILE_CORRUPT
		if FileAccess.file_exists(staged):
			DirAccess.remove_absolute(staged)
		return result
	if FileAccess.file_exists(output_path) or DirAccess.dir_exists_absolute(output_path):
		result.error = ERR_ALREADY_EXISTS
		return result
	err = DirAccess.rename_absolute(staged, output_path)
	if err != OK:
		result.error = err
		if FileAccess.file_exists(staged):
			DirAccess.remove_absolute(staged)
		return result
	result.path = output_path
	result.rows = copied_rows
	return result

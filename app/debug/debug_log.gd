# PT1h-R7: every engine/script message (print, printerr, push_warning, push_error, engine errors) as numbered
# records in a bounded ring, for the debug bridge. Godot may call a Logger from any thread: all access is locked.
# Never formats, writes files or prints from the callbacks (printing from a logger would recurse).
extends Logger

const CAPACITY := 4000
const MAX_TEXT := 4000

var _mutex := Mutex.new()
## A fixed ring indexed by sequence number: appending and reading after a cursor never shift or scan the whole log.
var _ring: Array = []
var _count := 0
var _next_seq := 1
var dropped := 0
## Totals since the logger was added, per level (the ring forgets; these do not).
var _counts := {}
## The local debugger's script profile (launch --script-profile) prints dozens of lines a second; they live in their
## own ring so they never evict errors and warnings from the main one.
const PROFILE_CAPACITY := 20000
var _profile: Array = []
var _profile_count := 0
var _profile_next := 0
var _profile_head := RegEx.create_from_string("^(FRAME: total:|BEGIN PROFILING|ACCUMULATED:|\\d+:res://|\\s+total: )")


func _init() -> void:
	_ring.resize(CAPACITY)
	_profile.resize(PROFILE_CAPACITY)


func _log_message(message: String, error: bool) -> void:
	if not error and _profile_head.search(message) != null:
		_mutex.lock()
		_profile[_profile_next % PROFILE_CAPACITY] = {time_ms = Time.get_ticks_msec(), text = message.trim_suffix("\n")}
		_profile_next += 1
		_profile_count = mini(_profile_count + 1, PROFILE_CAPACITY)
		_mutex.unlock()
		return
	_append({level = "stderr" if error else "info", text = message.trim_suffix("\n").left(MAX_TEXT)})


func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
		error_type: int, script_backtrace: Array[ScriptBacktrace]) -> void:
	var record := {level = ["error", "warning", "script_error", "shader_error"][clampi(error_type, 0, 3)],
		text = (rationale if not rationale.is_empty() else code).left(MAX_TEXT), code = code.left(MAX_TEXT),
		function = function, file = file, line = line}
	# The engine location of push_error/push_warning is the C++ helper; the script frame is the useful one.
	for backtrace: ScriptBacktrace in script_backtrace:
		if backtrace != null and backtrace.get_frame_count() > 0:
			record.script = "%s:%d in %s" % [backtrace.get_frame_file(0), backtrace.get_frame_line(0),
				backtrace.get_frame_function(0)]
			break
	_append(record)


func _append(record: Dictionary) -> void:
	_mutex.lock()
	record.seq = _next_seq
	record.time_ms = Time.get_ticks_msec()
	record.frame = Engine.get_process_frames()
	_ring[(_next_seq - 1) % CAPACITY] = record
	_next_seq += 1
	_counts[record.level] = int(_counts.get(record.level, 0)) + 1
	if _count < CAPACITY:
		_count += 1
	else:
		dropped += 1
	_mutex.unlock()


## Records with seq > `after`, oldest first, at most `limit`. `levels` empty means all levels.
func since(after: int, limit: int, levels: PackedStringArray = PackedStringArray()) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_mutex.lock()
	var seq := maxi(after + 1, _next_seq - _count)
	while seq < _next_seq and out.size() < limit:
		var record: Dictionary = _ring[(seq - 1) % CAPACITY]
		if levels.is_empty() or levels.has(str(record.level)):
			out.append(record.duplicate())
		seq += 1
	_mutex.unlock()
	return out


## A bridge-observed state change (route, screen, pause, crash, fault), interleaved with the engine messages.
func event(text: String, detail: Dictionary = {}) -> void:
	var record := {level = "event", text = text}
	if not detail.is_empty():
		record.detail = detail
	_append(record)


## Script-profile lines printed at or after `from_ms` (Time.get_ticks_msec), oldest first.
func profile_since(from_ms: int) -> PackedStringArray:
	var out := PackedStringArray()
	_mutex.lock()
	for index in range(_profile_next - _profile_count, _profile_next):
		var entry: Dictionary = _profile[index % PROFILE_CAPACITY]
		if int(entry.time_ms) >= from_ms:
			out.append(entry.text)
	_mutex.unlock()
	return out


## The time a main-log record was written, or -1 when the ring has already forgotten it.
func time_of(seq: int) -> int:
	_mutex.lock()
	var value := -1
	if seq > _next_seq - 1 - _count and seq < _next_seq:
		value = int(_ring[(seq - 1) % CAPACITY].time_ms)
	_mutex.unlock()
	return value


func counts() -> Dictionary:
	_mutex.lock()
	var value := _counts.duplicate()
	_mutex.unlock()
	return value


func last_seq() -> int:
	_mutex.lock()
	var value := _next_seq - 1
	_mutex.unlock()
	return value

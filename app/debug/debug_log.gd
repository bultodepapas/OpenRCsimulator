# PT1h-R7: every engine/script message (print, printerr, push_warning, push_error, engine errors) as numbered
# records in a bounded ring, for the debug bridge. Godot may call a Logger from any thread: all access is locked.
# Never formats, writes files or prints from the callbacks (printing from a logger would recurse).
extends Logger

const CAPACITY := 4000
const MAX_TEXT := 4000

var _mutex := Mutex.new()
var _records: Array[Dictionary] = []
var _next_seq := 1
var dropped := 0
## Totals since the logger was added, per level (the ring forgets; these do not).
var _counts := {}


func _log_message(message: String, error: bool) -> void:
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
	_next_seq += 1
	_counts[record.level] = int(_counts.get(record.level, 0)) + 1
	_records.append(record)
	if _records.size() > CAPACITY:
		_records.pop_front()
		dropped += 1
	_mutex.unlock()


## Records with seq > `after`, oldest first, at most `limit`. `levels` empty means all levels.
func since(after: int, limit: int, levels: PackedStringArray = PackedStringArray()) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_mutex.lock()
	for record: Dictionary in _records:
		if int(record.seq) <= after or (not levels.is_empty() and not levels.has(str(record.level))):
			continue
		out.append(record.duplicate())
		if out.size() >= limit:
			break
	_mutex.unlock()
	return out


## A bridge-observed state change (route, screen, pause, crash, fault), interleaved with the engine messages.
func event(text: String, detail: Dictionary = {}) -> void:
	var record := {level = "event", text = text}
	if not detail.is_empty():
		record.detail = detail
	_append(record)


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

## Keeps failed manual trace saves separate from Recorder.recording.
## Recorder.stop() stops collection before saving, but its Trace remains available for a retry.
extends RefCounted

var _pending: Array[Dictionary] = []
var _discarded: Array[RefCounted] = []


## Stop an active recorder once. A stopped recorder whose last save failed is still pending.
func save_if_recording(recorder: RefCounted) -> Dictionary:
	if recorder == null:
		return {ok = true, pending = false, error = OK}
	if bool(recorder.get("recording")):
		_discarded.erase(recorder) # a new recording on this Recorder is a new recovery decision
	var existing := _find(recorder)
	if existing >= 0:
		return {ok = false, pending = true, error = int(_pending[existing].error)}
	if _discarded.has(recorder):
		return {ok = true, pending = false, error = OK}
	if not bool(recorder.get("recording")):
		var note := _property_text(recorder, "note")
		if note.begins_with("trace save failed:"):
			var error_code := _error_from_note(note)
			_remember(recorder, error_code)
			return {ok = false, pending = true, error = error_code}
		return {ok = true, pending = false, error = OK}
	var error_code: Error = recorder.call("stop")
	if error_code == OK:
		return {ok = true, pending = false, error = OK}
	_remember(recorder, error_code)
	return {ok = false, pending = true, error = error_code}


## Retry stop() even though recording is false; the stopped Recorder retains its manual Trace.
func retry(recorder: RefCounted) -> Dictionary:
	var index := _find(recorder)
	if index < 0:
		return {ok = false, pending = false, error = ERR_DOES_NOT_EXIST}
	var error_code: Error = recorder.call("stop")
	if error_code == OK:
		_pending.remove_at(index)
		_discarded.erase(recorder)
		return {ok = true, pending = false, error = OK}
	_pending[index].error = error_code
	return {ok = false, pending = true, error = error_code}


## Discard only the trace the player explicitly chose to discard.
func discard(recorder: RefCounted) -> bool:
	var index := _find(recorder)
	if index < 0:
		return false
	_pending.remove_at(index)
	if not _discarded.has(recorder):
		_discarded.append(recorder)
	return true


func has_pending(recorder: RefCounted) -> bool:
	return _find(recorder) >= 0


func pending_count() -> int:
	return _pending.size()


func _remember(recorder: RefCounted, error_code: Error) -> void:
	_pending.append({recorder = recorder, error = error_code})


func _find(recorder: RefCounted) -> int:
	for index in _pending.size():
		if _pending[index].recorder == recorder:
			return index
	return -1


func _property_text(object: Object, property_name: String) -> String:
	for property: Dictionary in object.get_property_list():
		if str(property.get("name", "")) == property_name:
			return str(object.get(property_name))
	return ""


func _error_from_note(note: String) -> Error:
	var marker := note.rfind("error ")
	if marker < 0:
		return ERR_CANT_CREATE
	var raw_code := note.substr(marker + 6).strip_edges()
	return int(raw_code) if raw_code.is_valid_int() else ERR_CANT_CREATE

## Keeps failed manual trace saves separate from Recorder.recording.
## Recorder.stop() stops collection before saving, but its Trace remains available for a retry.
extends RefCounted

var _pending: Array[Dictionary] = []
var _discarded: Array[WeakRef] = []


## Stop an active recorder once. A stopped recorder whose last save failed is still pending.
func save_if_recording(recorder: RefCounted) -> Dictionary:
	if recorder == null:
		return {ok = true, pending = false, error = OK}
	if bool(recorder.get("recording")):
		_forget_discarded(recorder) # a new recording on this Recorder is a new recovery decision
	var existing := _find(recorder)
	if existing >= 0:
		return {ok = false, pending = true, error = int(_pending[existing].error)}
	if _was_discarded(recorder):
		return {ok = true, pending = false, error = OK}
	if not bool(recorder.get("recording")):
		var note := _property_text(recorder, "note")
		if note.begins_with("trace save failed:") or note.begins_with("helicopter trace save failed:"):
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
		_forget_discarded(recorder)
		return {ok = true, pending = false, error = OK}
	_pending[index].error = error_code
	return {ok = false, pending = true, error = error_code}


## Discard only the trace the player explicitly chose to discard.
func discard(recorder: RefCounted) -> bool:
	var index := _find(recorder)
	if index < 0:
		return false
	_pending.remove_at(index)
	if not _was_discarded(recorder):
		_discarded.append(weakref(recorder))
	return true


## Remove a resolved marker when its completed route releases the recorder.
func forget_completed(recorder: RefCounted) -> void:
	_forget_discarded(recorder)


func discarded_count() -> int:
	_prune_discarded()
	return _discarded.size()


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


func _was_discarded(recorder: RefCounted) -> bool:
	var found := false
	for index in range(_discarded.size() - 1, -1, -1):
		var retained: Object = _discarded[index].get_ref()
		if retained == null:
			_discarded.remove_at(index)
		elif retained == recorder:
			found = true
	return found


func _forget_discarded(recorder: RefCounted) -> void:
	for index in range(_discarded.size() - 1, -1, -1):
		var retained: Object = _discarded[index].get_ref()
		if retained == null or retained == recorder:
			_discarded.remove_at(index)


func _prune_discarded() -> void:
	for index in range(_discarded.size() - 1, -1, -1):
		if _discarded[index].get_ref() == null:
			_discarded.remove_at(index)


func _property_text(object: Object, property_name: String) -> String:
	for property: Dictionary in object.get_property_list():
		if str(property.get("name", "")) == property_name:
			return str(object.get(property_name))
	return ""


func _error_from_note(note: String) -> Error:
	# "trace save failed: error 7" (airplane) or "helicopter trace save failed: 7" (rotorcraft recorder).
	var marker := note.rfind("error ")
	var raw_code := note.substr(marker + 6).strip_edges() if marker >= 0 else note.get_slice(":", note.get_slice_count(":") - 1).strip_edges()
	return int(raw_code) if raw_code.is_valid_int() else ERR_CANT_CREATE

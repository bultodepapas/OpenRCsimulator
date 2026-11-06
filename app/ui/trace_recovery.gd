## Keeps failed manual trace saves separate from Recorder.recording.
## Decisions belong to a recording generation, not to the reusable recorder object.
extends RefCounted

const LEGACY_GENERATION := -1
const ANY_GENERATION := -2

var _pending: Array[Dictionary] = []
var _discarded: Array[Dictionary] = [] # weak recorder reference and recording generation


## Legacy recorder doubles without a generation retain the previous object-scoped behavior.
func generation_of(recorder: RefCounted) -> int:
	if recorder == null:
		return LEGACY_GENERATION
	for property: Dictionary in recorder.get_property_list():
		if str(property.get("name", "")) == "recording_generation":
			var value: Variant = recorder.get("recording_generation")
			return int(value) if typeof(value) == TYPE_INT and int(value) >= 0 else LEGACY_GENERATION
	return LEGACY_GENERATION


## Stop active or unexported work once. A failed save stays pending until a decision.
func save_if_recording(recorder: RefCounted) -> Dictionary:
	if recorder == null:
		return {ok = true, pending = false, error = OK, generation = LEGACY_GENERATION}
	_prune_pending()
	var generation := generation_of(recorder)
	var active := bool(recorder.get("recording"))
	if active:
		_forget_discarded(recorder)
	var existing := _find(recorder, generation)
	if existing >= 0:
		if _saved_externally(recorder, str(_pending[existing].failure_note)):
			_pending.remove_at(existing)
			return {ok = true, pending = false, error = OK, generation = generation}
		return {ok = false, pending = true, error = int(_pending[existing].error), generation = generation}
	if _was_discarded(recorder, generation):
		return {ok = true, pending = false, error = OK, generation = generation}
	if not active and recorder.has_method("has_unsaved_recording"):
		if not _has_unsaved_recording(recorder):
			return {ok = true, pending = false, error = OK, generation = generation}
	elif not active:
		var note := _property_text(recorder, "note")
		if note.begins_with("trace save failed:") or note.begins_with("helicopter trace save failed:"):
			var error_code := _error_from_note(note)
			_remember(recorder, generation, error_code)
			return {ok = false, pending = true, error = error_code, generation = generation}
		return {ok = true, pending = false, error = OK, generation = generation}
	var error_code: Error = recorder.call("stop")
	if error_code == OK:
		return {ok = true, pending = false, error = OK, generation = generation}
	_remember(recorder, generation, error_code)
	return {ok = false, pending = true, error = error_code, generation = generation}


## A stale dialog cannot retry a replacement recording when its generation is supplied.
func retry(recorder: RefCounted, expected_generation: int = ANY_GENERATION) -> Dictionary:
	_prune_pending()
	var generation := generation_of(recorder)
	if expected_generation != ANY_GENERATION and expected_generation != generation:
		return {ok = false, pending = false, error = ERR_DOES_NOT_EXIST, generation = generation}
	var index := _find(recorder, generation)
	if index < 0:
		return {ok = false, pending = false, error = ERR_DOES_NOT_EXIST, generation = generation}
	if _saved_externally(recorder, str(_pending[index].failure_note)):
		_pending.remove_at(index)
		return {ok = true, pending = false, error = OK, generation = generation}
	var error_code: Error = recorder.call("stop")
	if error_code == OK:
		_pending.remove_at(index)
		_forget_discarded(recorder)
		return {ok = true, pending = false, error = OK, generation = generation}
	_pending[index].error = error_code
	_pending[index].failure_note = _property_text(recorder, "note")
	return {ok = false, pending = true, error = error_code, generation = generation}


## Refusal by a recorder adapter leaves its pending data and recovery decision intact.
func discard(recorder: RefCounted, expected_generation: int = ANY_GENERATION) -> bool:
	_prune_pending()
	var generation := generation_of(recorder)
	if expected_generation != ANY_GENERATION and expected_generation != generation:
		return false
	var index := _find(recorder, generation)
	if index < 0:
		return false
	if recorder.has_method("discard_unsaved"):
		var discarded: Variant = recorder.call("discard_unsaved", generation)
		if typeof(discarded) != TYPE_BOOL or not bool(discarded):
			return false
	_pending.remove_at(index)
	if not _was_discarded(recorder, generation):
		_discarded.append({recorder = weakref(recorder), generation = generation})
	return true


## Remove a resolved marker when its completed route releases the recorder.
func forget_completed(recorder: RefCounted) -> void:
	_forget_discarded(recorder)


func discarded_count() -> int:
	_prune_discarded()
	return _discarded.size()


func has_pending(recorder: RefCounted) -> bool:
	_prune_pending()
	return _find(recorder, generation_of(recorder)) >= 0


func pending_count() -> int:
	_prune_pending()
	return _pending.size()


func _remember(recorder: RefCounted, generation: int, error_code: Error) -> void:
	_pending.append({recorder = recorder, generation = generation, error = error_code,
		failure_note = _property_text(recorder, "note")})


func _find(recorder: RefCounted, generation: int) -> int:
	for index in _pending.size():
		if _pending[index].recorder == recorder and int(_pending[index].generation) == generation:
			return index
	return -1


func _prune_pending() -> void:
	for index in range(_pending.size() - 1, -1, -1):
		var entry: Dictionary = _pending[index]
		var recorder: RefCounted = entry.recorder
		if not is_instance_valid(recorder) or generation_of(recorder) != int(entry.generation):
			_pending.remove_at(index)


func _saved_externally(recorder: RefCounted, failure_note: String) -> bool:
	if bool(recorder.get("recording")):
		return false
	if recorder.has_method("has_unsaved_recording"):
		return not _has_unsaved_recording(recorder)
	var note := _property_text(recorder, "note")
	return note != failure_note and (note.begins_with("trace saved:") or note.begins_with("helicopter trace saved:"))


func _has_unsaved_recording(recorder: RefCounted) -> bool:
	var value: Variant = recorder.call("has_unsaved_recording")
	return bool(value) if typeof(value) == TYPE_BOOL else true # fail closed on an invalid adapter result


func _was_discarded(recorder: RefCounted, generation: int) -> bool:
	_prune_discarded()
	for entry: Dictionary in _discarded:
		var reference: WeakRef = entry.recorder
		if reference.get_ref() == recorder and int(entry.generation) == generation:
			return true
	return false


func _forget_discarded(recorder: RefCounted) -> void:
	for index in range(_discarded.size() - 1, -1, -1):
		var reference: WeakRef = _discarded[index].recorder
		var retained: Object = reference.get_ref()
		if retained == null or retained == recorder:
			_discarded.remove_at(index)


func _prune_discarded() -> void:
	for index in range(_discarded.size() - 1, -1, -1):
		var entry: Dictionary = _discarded[index]
		var reference: WeakRef = entry.recorder
		var retained: Object = reference.get_ref()
		if retained == null or generation_of(retained as RefCounted) != int(entry.generation):
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

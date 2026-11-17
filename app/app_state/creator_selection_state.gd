extends RefCounted
## Home's current choice, last acknowledged saved choice and asynchronous source generation.
## A ready source is preview data; this owner never grants flight admission.
const Selection := preload("res://app_state/creator_selection.gd")
const Resolver := preload("res://workshop/creator/source_resolver.gd")
var _selection := {}
var _persisted := {}
var _unknown := false
var _generation := 0
var _source_state := "stock"
var _reason := ""
var _owner: RefCounted


func _init(initial: Variant = {}, unknown: bool = false) -> void:
	var checked: Dictionary = Selection.validate(initial)
	_unknown = unknown or not checked.ok
	if checked.ok:
		_selection = checked.value
		_persisted = checked.value.duplicate(true)
	if _unknown:
		_source_state = "unknown"
		_reason = "The saved aircraft selection is unavailable. Choose an aircraft again."
	elif not _selection.is_empty():
		_restart_resolution()


func selection() -> Dictionary:
	return _selection.duplicate(true)


func persisted_selection() -> Dictionary:
	return _persisted.duplicate(true)


func is_unknown() -> bool:
	return _unknown


func is_stock() -> bool:
	return not _unknown and _selection.is_empty()


func has_creator() -> bool:
	return not _unknown and not _selection.is_empty()


func source_status() -> String:
	return _source_state


func reason() -> String:
	return _reason


func source_owner() -> RefCounted:
	return _owner if _source_state == "ready" else null


## Every explicit saved-model selection rechecks the library, including selecting the same ref again.
func select_creator(value: Variant) -> bool:
	var checked: Dictionary = Selection.validate(value)
	if not checked.ok or checked.value.is_empty():
		return false
	_selection = checked.value
	_unknown = false
	_restart_resolution()
	return true


## Validate a stock/activity ID at the UI boundary before calling this explicit replacement.
func select_stock() -> void:
	_generation += 1
	_selection = {}
	_unknown = false
	_owner = null
	_source_state = "stock"
	_reason = ""


## Start choice does not change the source bytes or invalidate an independent source resolution.
## Any start/context qualification must have its own complete selection/context generation.
func select_start(choice: Variant) -> bool:
	if not has_creator():
		return false
	var checked: Dictionary = Selection.make(_selection.source_ref, choice)
	if not checked.ok:
		return false
	_selection = checked.value
	return true


func retry_source() -> bool:
	if not has_creator():
		return false
	_restart_resolution()
	return true


func _restart_resolution() -> void:
	_generation += 1
	_owner = null
	_source_state = "loading"
	_reason = "Loading saved aircraft…"


func source_ticket() -> Dictionary:
	# Keep the exact in-process owner: a rebuilt state can have the same ref and
	# generation, but must never consume a callback issued by its predecessor.
	return {"owner": self, "generation": _generation, "source_ref": _selection.source_ref.duplicate(true)} if has_creator() else {}


## True means a matching callback was consumed, including an unavailable result. Stale results do nothing.
func finish_resolution(ticket: Variant, result: Variant) -> bool:
	if not has_creator() or _source_state != "loading" or not ticket is Dictionary or ticket.size() != 3 \
			or ticket.get("owner") != self \
			or typeof(ticket.get("generation")) != TYPE_INT or ticket.generation != _generation \
			or not Selection.SourceRef.validate(ticket.get("source_ref")).ok or ticket.source_ref != _selection.source_ref:
		return false
	for key: Variant in ticket:
		if typeof(key) != TYPE_STRING or key not in ["owner", "generation", "source_ref"]:
			return false
	_owner = null
	_source_state = "unavailable"
	_reason = "The saved aircraft is unavailable. Open its library entry to review it."
	if not result is Dictionary or typeof(result.get("ok")) != TYPE_BOOL or not result.ok:
		return true
	var owner: Variant = result.get("value")
	if not Resolver.is_resolved(owner) or not Selection.SourceRef.validate(owner.source_ref()).ok or owner.source_ref() != _selection.source_ref:
		return true
	_owner = owner
	_source_state = "ready"
	_reason = ""
	return true


## Keep last acknowledged disk state after a failed save, so a later explicit choice can retry correctly.
func change_intent() -> Dictionary:
	return Selection.change(_persisted, _selection)


## After a conflict, a fresh locked settings read may update the disk expectation.
## It cannot replace the current UI choice or its source/preview generation.
func reconcile_persisted(value: Variant) -> bool:
	var checked: Dictionary = Selection.validate(value)
	if not checked.ok:
		return false
	_persisted = checked.value
	return true


## Call only after a successful locked preference save. A reentrant UI choice does not undo the disk receipt.
func acknowledge_saved(intent: Variant) -> bool:
	if not intent is Dictionary or intent.size() != 3 or typeof(intent.get("format")) != TYPE_STRING \
			or intent.format != Selection.CHANGE_FORMAT:
		return false
	for key: Variant in intent:
		if typeof(key) != TYPE_STRING or key not in ["format", "before", "after"]:
			return false
	var checked: Dictionary = Selection.change(intent.get("before"), intent.get("after"))
	if not checked.ok or checked.value.before != _persisted:
		return false
	_persisted = checked.value.after.duplicate(true)
	return true

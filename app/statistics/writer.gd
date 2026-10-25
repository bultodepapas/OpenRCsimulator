extends RefCounted
class_name FlightStatisticsWriter

## Runs one detached snapshot commit at a time. The caller owns the store and
## must not read or mutate store.data until poll() or finish() joins the worker.
## candidate must be detached and remain unchanged for the duration of the commit.

var _thread: Thread
var _pending: bool = false


func start(store: Variant, candidate: Dictionary) -> bool:
	if _pending or store == null or typeof(store) != TYPE_OBJECT:
		return false
	if not store is RefCounted or store is Node or not store.has_method("commit"):
		return false
	var worker := Thread.new()
	var start_error: Error = worker.start(Callable(self, "_commit_worker").bind(store, candidate), Thread.PRIORITY_LOW)
	if start_error != OK:
		return false
	_thread = worker
	_pending = true
	return true


func pending() -> bool:
	return _pending


func poll() -> Dictionary:
	if not _pending or _thread.is_alive():
		return {}
	return _join_result()


func finish() -> Dictionary:
	if not _pending:
		return {}
	return _join_result()


func _commit_worker(store: Variant, candidate: Dictionary) -> Dictionary:
	var ok: bool = bool(store.call("commit", candidate))
	var stored_data: Variant = store.get("data")
	var generation: int = int(stored_data.get("generation", -1)) if typeof(stored_data) == TYPE_DICTIONARY else -1
	var durable_sequence: int = int(stored_data.get("sequence", -1)) if typeof(stored_data) == TYPE_DICTIONARY else -1
	return {
		"ok": ok,
		"note": str(store.get("note")),
		"generation": generation,
		"durable_sequence": durable_sequence,
	}


func _join_result() -> Dictionary:
	var value: Variant = _thread.wait_to_finish()
	_pending = false
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {
		"ok": false,
		"note": "Statistics writer thread returned no result.",
		"generation": -1,
		"durable_sequence": -1,
	}

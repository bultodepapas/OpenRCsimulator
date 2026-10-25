## Two-entry exact LRU for raw cruise-trim results; no live session or resources are retained.
## The caller must still rebuild its model and atmosphere inputs before calling this wrapper.
extends RefCounted

const ManagedJob := preload("res://sim/launch_trim_job.gd")
const CruiseTrim := preload("res://physics/cruise_trim.gd")
const Air := preload("res://physics/air_data.gd")
const DEFAULT_MAX_ALPHA_RAD: float = CruiseTrim.DEFAULT_MAX_ALPHA_RAD
const MAX_VALUE_DEPTH := 64
const MAX_CACHE_ENTRIES := 2
const MAX_RETAINED_KEY_BYTES := 1024 * 1024
const SAFE_LEAF_TYPES := [
	TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING,
	TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_RECT2, TYPE_RECT2I, TYPE_VECTOR3, TYPE_VECTOR3I,
	TYPE_TRANSFORM2D, TYPE_VECTOR4, TYPE_VECTOR4I, TYPE_PLANE, TYPE_QUATERNION,
	TYPE_AABB, TYPE_BASIS, TYPE_TRANSFORM3D, TYPE_PROJECTION, TYPE_COLOR,
	TYPE_STRING_NAME, TYPE_NODE_PATH,
	TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY,
	TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY,
	TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY,
	TYPE_PACKED_VECTOR4_ARRAY,
]

var _entries: Array[Dictionary] = [] # Most recently used first.
var _hits := 0
var _misses := 0
var _bypasses := 0
var _staged_workers_started := 0
var _staged_active_token := 0
var _staged_next_token := 1
var _cache_generation := 0
var _managed_job: RefCounted = null
var _managed_ticket: Dictionary = {}
var _managed_consumer: WeakRef = null
var _drain_tree: WeakRef = null
var _menu_starts := 0
var _menu_adoptions := 0
var _menu_discarded := 0
var _menu_completed := 0
var _menu_skipped := 0


## Mirrors every CruiseTrim.solve_level_at_throttle input, including its default max-alpha argument.
func solve_level_at_throttle(reference_speed_mps: float, target_throttle: float,
		max_speed_mps: float, model: Dictionary, g: float, throws: Dictionary,
		rho: float = Air.RHO_SEA_LEVEL, engine_charge_ratio: float = 1.0,
		max_alpha_rad: float = DEFAULT_MAX_ALPHA_RAD) -> Dictionary:
	var arguments: Array = [reference_speed_mps, target_throttle, max_speed_mps, model, g,
		throws, rho, engine_charge_ratio, max_alpha_rad]
	var encoded: Dictionary = _encode_arguments(arguments)
	if not encoded.ok:
		_bypasses += 1
		return _solve(arguments)
	var key: PackedByteArray = encoded.key
	if key.size() > MAX_RETAINED_KEY_BYTES:
		_bypasses += 1
		return _solve(arguments)
	var entry_index: int = _find_entry_index(key)
	if entry_index >= 0:
		_hits += 1
		var entry: Dictionary = _entries[entry_index]
		_entries.remove_at(entry_index)
		_entries.push_front(entry)
		var cached_result: Dictionary = entry.result
		return cached_result.duplicate(true)

	_misses += 1
	var result: Dictionary = _solve(arguments)
	if not result.get("ok", false):
		return result # Failures are deliberately never retained.
	_store_success(key, result)
	return result


## Main-thread-only cache lookup and worker reservation. The worker receives only a safe round-trip copy.
func begin_staged_solve(arguments: Array) -> Dictionary:
	var encoded: Dictionary = _encode_arguments(arguments)
	if not encoded.get("ok", false):
		_bypasses += 1
		return {kind = "sync", result = _solve(arguments)}
	var key: PackedByteArray = encoded.key
	if key.size() > MAX_RETAINED_KEY_BYTES:
		_bypasses += 1
		return {kind = "sync", result = _solve(arguments)}
	var entry_index: int = _find_entry_index(key)
	if entry_index >= 0:
		_hits += 1
		var entry: Dictionary = _entries[entry_index]
		_entries.remove_at(entry_index)
		_entries.push_front(entry)
		var cached_result: Dictionary = entry.result
		return {kind = "result", result = cached_result.duplicate(true)}

	_misses += 1
	# There is one reservation per shared cache. A second session preserves the old sync API semantics.
	if _staged_active_token != 0:
		var synchronous_result: Dictionary = _solve(arguments)
		if synchronous_result.get("ok", false):
			_store_success(key, synchronous_result)
		return {kind = "result", result = synchronous_result}

	var worker_arguments: Variant = bytes_to_var(key)
	var worker_ancestors: Array = []
	if typeof(worker_arguments) != TYPE_ARRAY \
			or not _is_cache_safe(worker_arguments, worker_ancestors, 0) \
			or var_to_bytes(worker_arguments) != key:
		# Defensive round-trip guard. Do not send an unchecked Variant into a worker.
		_bypasses += 1
		var fallback_result: Dictionary = _solve(arguments)
		if fallback_result.get("ok", false):
			_store_success(key, fallback_result)
		return {kind = "result", result = fallback_result}

	var token: int = _staged_next_token
	_staged_next_token += 1
	_staged_active_token = token
	return {
		kind = "worker", token = token, generation = _cache_generation,
		key = key.duplicate(), arguments = worker_arguments,
	}


## The caller invokes this after Thread.start succeeds; the cache itself remains main-thread-only.
func staged_worker_started(job: Dictionary) -> bool:
	if int(job.get("token", 0)) != _staged_active_token:
		return false
	_staged_workers_started += 1
	return true


## Thread.start failure fallback. The reservation stays held until the same final validation decision as a worker result.
func solve_staged_synchronously(job: Dictionary) -> Dictionary:
	if int(job.get("token", 0)) != _staged_active_token:
		return {ok = false, message = "launch trim reservation is no longer active"}
	var arguments: Variant = job.get("arguments")
	if typeof(arguments) != TYPE_ARRAY:
		return {ok = false, message = "launch trim worker arguments are invalid"}
	return _solve(arguments)


## Called on main after final candidate validation. Cancellation or any failed validation releases without insertion.
func finish_staged_solve(job: Dictionary, result: Dictionary, retain_success: bool) -> bool:
	if int(job.get("token", 0)) != _staged_active_token:
		return false
	var keep: bool = retain_success and int(job.get("generation", -1)) == _cache_generation \
			and result.get("ok", false)
	_staged_active_token = 0
	if keep:
		var key_value: Variant = job.get("key", PackedByteArray())
		if typeof(key_value) != TYPE_PACKED_BYTE_ARRAY:
			return false
		var key: PackedByteArray = key_value
		if key.size() > MAX_RETAINED_KEY_BYTES:
			return false
		_store_success(key, result)
	return true


## Managed startup never runs a second synchronous solve behind an active worker.
## A speculative result stays private until the adopting flight validates its full candidate.
func acquire_managed(arguments: Array, speculative := false, consumer: Object = null) -> Dictionary:
	var encoded: Dictionary = _encode_arguments(arguments)
	if not encoded.get("ok", false) or encoded.get("key", PackedByteArray()).size() > MAX_RETAINED_KEY_BYTES:
		_bypasses += 1
		return _managed_bypass(arguments, speculative, "launch trim arguments cannot enter the detached worker")
	var key: PackedByteArray = encoded.key
	_recover_orphaned_consumer()
	if _managed_job != null:
		if _managed_job.owner == "abandoned":
			poll_menu()
		if _managed_job != null:
			var same_key: bool = _managed_ticket.key == key and int(_managed_ticket.generation) == _cache_generation
			if same_key and _managed_job.owner == "menu":
				if not speculative:
					_managed_job.owner = "flight"
					_managed_consumer = weakref(consumer) if consumer != null else null
					_menu_adoptions += 1
				return _managed_resolution()
			if not speculative and _managed_job.owner == "menu":
				abandon_menu()
				poll_menu()
			if _managed_job != null:
				if speculative:
					_menu_skipped += 1
				return {kind = "skipped" if speculative else "wait", reason = "another launch trim worker is draining"}
	if _staged_active_token != 0:
		if speculative:
			_menu_skipped += 1
		return {kind = "skipped" if speculative else "wait", reason = "launch trim reservation is busy"}
	var entry_index: int = _find_entry_index(key)
	if entry_index >= 0:
		_hits += 1
		var entry: Dictionary = _entries[entry_index]
		_entries.remove_at(entry_index)
		_entries.push_front(entry)
		return {kind = "result", result = entry.result.duplicate(true)}
	var worker_arguments: Variant = bytes_to_var(key)
	var ancestors: Array = []
	if typeof(worker_arguments) != TYPE_ARRAY or not _is_cache_safe(worker_arguments, ancestors, 0) \
			or var_to_bytes(worker_arguments) != key:
		return _managed_bypass(arguments, speculative, "launch trim arguments failed the safe round trip")
	_misses += 1
	_staged_active_token = _staged_next_token
	_staged_next_token += 1
	_managed_ticket = {token = _staged_active_token, generation = _cache_generation, key = key.duplicate()}
	_managed_job = ManagedJob.new()
	_managed_job.owner = "menu" if speculative else "flight"
	_managed_consumer = weakref(consumer) if not speculative and consumer != null else null
	var error: Error = _managed_job.start(worker_arguments, speculative)
	if error == OK:
		_staged_workers_started += 1
		if speculative:
			_menu_starts += 1
	elif speculative:
		_release_managed(false)
		return {kind = "skipped", reason = "launch trim worker could not start"}
	else:
		# Thread startup failure keeps foreground synchronous compatibility.
		_managed_job.result = _solve(arguments)
	return _managed_resolution()


func _managed_bypass(arguments: Array, speculative: bool, reason: String) -> Dictionary:
	if speculative:
		_menu_skipped += 1
		return {kind = "skipped", reason = reason}
	# Unsafe keys cannot be compared to a pending job; drain before a synchronous fallback.
	abandon_menu()
	poll_menu()
	if _staged_active_token != 0:
		return {kind = "wait", reason = "launch trim worker must drain before synchronous fallback"}
	return {kind = "result", result = _solve(arguments)}


func _managed_resolution() -> Dictionary:
	return {kind = "pending", job = _managed_job, ticket = _managed_ticket.duplicate(true)}


## Adopted jobs are polled exclusively by their flight. Home can observe but never clear them.
func poll_menu() -> Dictionary:
	_recover_orphaned_consumer()
	if _managed_job == null:
		return {active = false, complete = false, adopted = false}
	var adopted: bool = _managed_job.owner == "flight"
	if not adopted:
		var was_complete: bool = _managed_job.complete
		_managed_job.poll()
		if not was_complete and _managed_job.complete:
			_menu_completed += 1
	var status: Dictionary = {active = true, complete = _managed_job.complete, adopted = adopted,
		abandoned = _managed_job.owner == "abandoned", token = int(_managed_ticket.token)}
	if not adopted and _managed_job.owner == "abandoned" and _managed_job.complete:
		_release_managed(false)
		status.active = false
	return status


func abandon_menu() -> void:
	if _managed_job != null and _managed_job.owner == "menu":
		_managed_job.owner = "abandoned"
		_ensure_abandoned_drain()


func menu_busy() -> bool:
	return _managed_job != null


func poll_managed(resolution: Dictionary) -> Dictionary:
	if not _owns_managed(resolution) or _managed_job.owner != "flight":
		return {complete = true, result = {ok = false, message = "launch trim ownership was lost"}}
	if not _managed_job.poll():
		return {complete = false}
	return {complete = true, result = _managed_job.result_copy()}


func finish_managed(resolution: Dictionary, retain_success: bool) -> bool:
	if not _owns_managed(resolution) or _managed_job.owner != "flight":
		return false
	if not _managed_job.poll():
		_managed_job.owner = "abandoned"
		_managed_consumer = null
		_ensure_abandoned_drain()
		return true
	_release_managed(retain_success)
	return true


func _owns_managed(resolution: Dictionary) -> bool:
	return _managed_job != null and is_same(resolution.get("job"), _managed_job) \
		and int(resolution.get("ticket", {}).get("token", 0)) == _staged_active_token


func _release_managed(retain_success: bool) -> void:
	var result: Dictionary = _managed_job.result_copy()
	var retained: bool = retain_success and int(_managed_ticket.generation) == _cache_generation and result.get("ok", false)
	finish_staged_solve(_managed_ticket, result, retained)
	if not retained:
		_menu_discarded += 1
	_managed_job = null
	_managed_ticket = {}
	_managed_consumer = null
	_disconnect_abandoned_drain()


## An explicit consumer release normally owns this transition. A weak guard also prevents stale flight ownership.
func _recover_orphaned_consumer() -> void:
	if _managed_job != null and _managed_job.owner == "flight" \
			and _managed_consumer != null and _managed_consumer.get_ref() == null:
		_managed_job.owner = "abandoned"
		_managed_consumer = null
		_ensure_abandoned_drain()


## Cancellation during normal setup drains in its coroutine. Destruction can remove that coroutine,
## so only an abandoned job installs this bounded, cache-owned callback, independent of AppRoot.
func _ensure_abandoned_drain() -> void:
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop is SceneTree:
		var tree: SceneTree = main_loop
		_drain_tree = weakref(tree)
		if not tree.process_frame.is_connected(_drain_abandoned_frame):
			tree.process_frame.connect(_drain_abandoned_frame)


func _drain_abandoned_frame() -> void:
	poll_menu()
	if _managed_job == null:
		_disconnect_abandoned_drain()


func _disconnect_abandoned_drain() -> void:
	if _drain_tree == null:
		return
	var tree: SceneTree = _drain_tree.get_ref() as SceneTree
	if tree != null and tree.process_frame.is_connected(_drain_abandoned_frame):
		tree.process_frame.disconnect(_drain_abandoned_frame)
	_drain_tree = null


func stats() -> Dictionary:
	var retained_key_bytes: int = _retained_key_bytes()
	return {
		hits = _hits,
		misses = _misses,
		bypasses = _bypasses,
		has_entry = not _entries.is_empty(),
		entries = _entries.size(),
		entry_limit = MAX_CACHE_ENTRIES,
		retained_key_bytes = retained_key_bytes,
		retained_key_limit_bytes = MAX_RETAINED_KEY_BYTES,
		staged_worker_active = _staged_active_token != 0,
		staged_workers_started = _staged_workers_started,
		menu_starts = _menu_starts,
		menu_adoptions = _menu_adoptions,
		menu_discarded = _menu_discarded,
		menu_completed = _menu_completed,
		menu_skipped = _menu_skipped,
		managed_owner = _managed_job.owner if _managed_job != null else "",
		managed_token = int(_managed_ticket.get("token", 0)),
	}


## Test utility. Production can retain one instance across FlightSession replacement.
func clear() -> void:
	_entries.clear()
	_hits = 0
	_misses = 0
	_bypasses = 0
	_staged_workers_started = 0
	_cache_generation += 1
	abandon_menu()


func _find_entry_index(key: PackedByteArray) -> int:
	for index: int in range(_entries.size()):
		var entry_key: PackedByteArray = _entries[index].key
		if key == entry_key:
			return index
	return -1


func _retained_key_bytes() -> int:
	var total_bytes: int = 0
	for entry: Dictionary in _entries:
		var entry_key: PackedByteArray = entry.key
		total_bytes += entry_key.size()
	return total_bytes


func _store_success(key: PackedByteArray, result: Dictionary) -> void:
	var existing_index: int = _find_entry_index(key)
	if existing_index >= 0:
		_entries.remove_at(existing_index)
	_entries.push_front({"key": key.duplicate(), "result": result.duplicate(true)})
	while _entries.size() > MAX_CACHE_ENTRIES or _retained_key_bytes() > MAX_RETAINED_KEY_BYTES:
		_entries.pop_back()


func _solve(arguments: Array) -> Dictionary:
	return CruiseTrim.solve_level_at_throttle(
		float(arguments[0]), float(arguments[1]), float(arguments[2]), arguments[3],
		float(arguments[4]), arguments[5], float(arguments[6]), float(arguments[7]), float(arguments[8]))


func _encode_arguments(arguments: Array) -> Dictionary:
	var ancestors: Array = []
	if not _is_cache_safe(arguments, ancestors, 0):
		return {ok = false, reason = "unsupported, cyclic, or too-deep solver input"}
	return {ok = true, key = var_to_bytes(arguments)}


func _is_cache_safe(value: Variant, ancestors: Array, depth: int) -> bool:
	if depth > MAX_VALUE_DEPTH:
		return false
	var value_type: int = typeof(value)
	match value_type:
		TYPE_ARRAY, TYPE_DICTIONARY:
			for ancestor: Variant in ancestors:
				if is_same(value, ancestor):
					return false
			ancestors.push_back(value)
			var safe := true
			if value_type == TYPE_ARRAY:
				var array_value: Array = value
				for item: Variant in array_value:
					if not _is_cache_safe(item, ancestors, depth + 1):
						safe = false
						break
			else:
				var dictionary_value: Dictionary = value
				for key: Variant in dictionary_value:
					if not _is_cache_safe(key, ancestors, depth + 1) \
							or not _is_cache_safe(dictionary_value[key], ancestors, depth + 1):
						safe = false
						break
			ancestors.pop_back()
			return safe
		_:
			# In particular, OBJECT, CALLABLE, SIGNAL, and RID values never enter a cache key.
			return value_type in SAFE_LEAF_TYPES

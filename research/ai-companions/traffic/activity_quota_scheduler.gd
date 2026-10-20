extends RefCounted

## Deterministic AFC-13/17 groundwork for activity choice and shared slot quotas.
## This scheduler only grants intent leases. It does not move or control aircraft.

const STATE_VERSION: String = "openrc-activity-quota-state v1"
const DEFAULT_MAX_PENDING: int = 64
const DEFAULT_MAX_ACTIVE: int = 32
const DEFAULT_MAX_EVENTS: int = 128
const HARD_MAX_PENDING: int = 256
const HARD_MAX_ACTIVE: int = 32
const HARD_MAX_EVENTS: int = 512
const HARD_MAX_COOLDOWNS: int = 512

var _choice_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _choice_seed: int = 1
var _pending: Array[Dictionary] = []
var _active: Dictionary = {}
var _cooldown_until: Dictionary = {}
var _events: Array[Dictionary] = []
var _request_sequence: int = 0
var _event_sequence: int = 0
var _max_pending: int = DEFAULT_MAX_PENDING
var _max_active: int = DEFAULT_MAX_ACTIVE
var _max_events: int = DEFAULT_MAX_EVENTS


func _init(seed_value: int = 1, max_pending: int = DEFAULT_MAX_PENDING, max_events: int = DEFAULT_MAX_EVENTS, max_active: int = DEFAULT_MAX_ACTIVE) -> void:
	_choice_seed = _normalize_seed(seed_value)
	_choice_rng.seed = _choice_seed
	_max_pending = clampi(max_pending, 1, HARD_MAX_PENDING)
	_max_events = clampi(max_events, 1, HARD_MAX_EVENTS)
	_max_active = clampi(max_active, 1, HARD_MAX_ACTIVE)


## Choices are sorted by activity_id before drawing so dictionary/array assembly
## order cannot change the seeded result. Ineligible, unsupported, zero-weight,
## and cooling-down choices consume no RNG state.
func choose_weighted_activity(tick: int, pilot_id: String, options: Array[Dictionary]) -> Dictionary:
	if tick < 0 or pilot_id.is_empty():
		return _reject("invalid_choice_context")
	var eligible: Array[Dictionary] = []
	for option: Dictionary in options:
		var activity_id: String = String(option.get("activity_id", ""))
		var weight: float = float(option.get("weight", 0.0))
		if activity_id.is_empty() or not is_finite(weight) or weight <= 0.0 or not bool(option.get("eligible", false)):
			continue
		var key: String = _cooldown_key(pilot_id, activity_id)
		if int(_cooldown_until.get(key, -1)) > tick:
			continue
		var copy: Dictionary = option.duplicate(true)
		copy["activity_id"] = activity_id
		copy["weight"] = weight
		eligible.append(copy)
	if eligible.is_empty():
		return {"ok": true, "selected": false, "reason": "no_eligible_weighted_activity"}
	eligible.sort_custom(_activity_id_less)
	var total_weight: float = 0.0
	for option: Dictionary in eligible:
		total_weight += float(option["weight"])
	if not is_finite(total_weight) or total_weight <= 0.0:
		return _reject("invalid_total_weight")
	var draw: float = _choice_rng.randf() * total_weight
	for option: Dictionary in eligible:
		draw -= float(option["weight"])
		if draw < 0.0:
			return {"ok": true, "selected": true, "activity": option.duplicate(true)}
	return {"ok": true, "selected": true, "activity": eligible.back().duplicate(true)}


## quota_key is an authored shared resource such as runway, a maneuver box, or a
## pass corridor. A caller submits one selected activity per pilot, then resolves
## once after same-tick requests are collected. Eligibility is rechecked at grant.
func request_activity(tick: int, request_id: String, pilot_id: String, owner_id: int, generation: int, activity_id: String, quota_key: String, weight: float, quota: int, minimum_duration_ticks: int, repeat_cooldown_ticks: int, priority: int = 0, eligible: bool = true, eligibility_reason: String = "") -> Dictionary:
	if tick < 0 or request_id.is_empty() or pilot_id.is_empty() or owner_id < 0 or generation < 0 or activity_id.is_empty() or quota_key.is_empty():
		return _reject("invalid_activity_request")
	if not is_finite(weight) or weight <= 0.0 or quota <= 0 or minimum_duration_ticks < 0 or repeat_cooldown_ticks < 0:
		return _reject("invalid_activity_limits")
	if not eligible:
		_record_event(tick, "activity_refused", {"request_id": request_id, "owner_id": owner_id, "generation": generation, "activity_id": activity_id, "reason": eligibility_reason if not eligibility_reason.is_empty() else "ineligible"})
		return {"ok": false, "reason": eligibility_reason if not eligibility_reason.is_empty() else "ineligible"}
	if int(_cooldown_until.get(_cooldown_key(pilot_id, activity_id), -1)) > tick:
		return _reject("activity_cooldown")
	if not _cooldown_until.has(_cooldown_key(pilot_id, activity_id)) and _cooldown_until.size() >= HARD_MAX_COOLDOWNS:
		return _reject("cooldown_state_full")
	if _pending.size() >= _max_pending:
		return _reject("activity_queue_full")
	if _request_id_exists(request_id) or _has_pending_owner(owner_id, generation) or _active.has(_owner_key(owner_id, generation)):
		return _reject("activity_already_pending_or_active")
	if _quota_definition_conflicts(quota_key, quota):
		return _reject("quota_definition_conflict")
	_request_sequence += 1
	_pending.append({
		"request_id": request_id,
		"pilot_id": pilot_id,
		"owner_id": owner_id,
		"generation": generation,
		"activity_id": activity_id,
		"quota_key": quota_key,
		"weight": weight,
		"quota": quota,
		"minimum_duration_ticks": minimum_duration_ticks,
		"repeat_cooldown_ticks": repeat_cooldown_ticks,
		"priority": priority,
		"request_tick": tick,
		"request_sequence": _request_sequence
	})
	_record_event(tick, "activity_queued", {"request_id": request_id, "owner_id": owner_id, "generation": generation, "activity_id": activity_id, "quota_key": quota_key})
	return {"ok": true, "request_id": request_id}


## eligibility_updates maps request_id to {eligible: bool, reason: String}.
## The queue is bounded, sorted by safety priority then age and stable identity,
## and grants as many independent quota keys as their capacities permit.
func resolve(tick: int, eligibility_updates: Dictionary = {}) -> Dictionary:
	if tick < 0:
		return _reject("invalid_tick")
	var newly_cancelled: Array[Dictionary] = []
	for index: int in range(_pending.size() - 1, -1, -1):
		var request: Dictionary = _pending[index]
		var request_id: String = String(request.get("request_id", ""))
		var update: Variant = eligibility_updates.get(request_id, null)
		if update is Dictionary and not bool(update.get("eligible", false)):
			var reason: String = String(update.get("reason", "ineligible_at_grant"))
			newly_cancelled.append(_cancel_pending_at(index, tick, reason))
		elif int(_cooldown_until.get(_cooldown_key(String(request.get("pilot_id", "")), String(request.get("activity_id", ""))), -1)) > tick:
			newly_cancelled.append(_cancel_pending_at(index, tick, "activity_cooldown"))
	var ranked: Array[Dictionary] = []
	for request: Dictionary in _pending:
		ranked.append(request)
	ranked.sort_custom(_request_less)
	var granted: Array[Dictionary] = []
	var used_by_quota: Dictionary = _active_quota_counts()
	var used_owners: Dictionary = {}
	for request: Dictionary in ranked:
		if _active.size() >= _max_active:
			break
		var key: String = _owner_key(int(request["owner_id"]), int(request["generation"]))
		if used_owners.has(key) or _active.has(key):
			continue
		var quota_key: String = String(request["quota_key"])
		var used: int = int(used_by_quota.get(quota_key, 0))
		if used >= int(request["quota"]):
			continue
		var lease: Dictionary = {
			"request_id": request["request_id"],
			"pilot_id": request["pilot_id"],
			"owner_id": request["owner_id"],
			"generation": request["generation"],
			"activity_id": request["activity_id"],
			"quota_key": quota_key,
			"quota": request["quota"],
			"weight": request["weight"],
			"granted_tick": tick,
			"minimum_until_tick": tick + int(request["minimum_duration_ticks"]),
			"repeat_cooldown_ticks": request["repeat_cooldown_ticks"]
		}
		_active[key] = lease
		used_by_quota[quota_key] = used + 1
		used_owners[key] = true
		granted.append(lease.duplicate(true))
		_remove_request_id(String(request["request_id"]))
		_record_event(tick, "activity_granted", {"request_id": request["request_id"], "owner_id": request["owner_id"], "generation": request["generation"], "activity_id": request["activity_id"], "quota_key": quota_key, "minimum_until_tick": lease["minimum_until_tick"]})
	return {"ok": true, "granted": granted, "cancelled": newly_cancelled}


func complete_activity(tick: int, owner_id: int, generation: int, activity_id: String, outcome: String = "completed", safety_preemption: bool = false) -> Dictionary:
	var key: String = _owner_key(owner_id, generation)
	if not _active.has(key):
		return _reject("stale_activity_lease")
	var lease: Dictionary = _active[key]
	if String(lease.get("activity_id", "")) != activity_id:
		return _reject("activity_identity_mismatch")
	if tick < int(lease.get("minimum_until_tick", tick)) and not safety_preemption:
		return _reject("minimum_activity_duration")
	_active.erase(key)
	var cooldown_tick: int = tick + int(lease.get("repeat_cooldown_ticks", 0))
	var cooldown_key: String = _cooldown_key(String(lease.get("pilot_id", "")), activity_id)
	_cooldown_until[cooldown_key] = maxi(cooldown_tick, int(_cooldown_until.get(cooldown_key, -1)))
	_record_event(tick, "activity_completed", {"owner_id": owner_id, "generation": generation, "activity_id": activity_id, "outcome": outcome, "safety_preemption": safety_preemption, "cooldown_until_tick": cooldown_tick})
	return {"ok": true, "cooldown_until_tick": cooldown_tick}


func retire_agent(tick: int, owner_id: int, generation: int, reason: String = "retired") -> Dictionary:
	var removed: int = 0
	var key: String = _owner_key(owner_id, generation)
	if _active.has(key):
		var lease: Dictionary = _active[key]
		_active.erase(key)
		_set_cooldown(tick, lease)
		_record_event(tick, "activity_aborted", {"owner_id": owner_id, "generation": generation, "activity_id": lease.get("activity_id", ""), "reason": reason})
		removed += 1
	for index: int in range(_pending.size() - 1, -1, -1):
		var request: Dictionary = _pending[index]
		if int(request.get("owner_id", -1)) == owner_id and int(request.get("generation", -1)) == generation:
			_cancel_pending_at(index, tick, reason)
			removed += 1
	return {"ok": true, "removed": removed}


func cancel_request(tick: int, request_id: String, owner_id: int, generation: int, reason: String = "cancelled") -> Dictionary:
	for index: int in range(_pending.size() - 1, -1, -1):
		var request: Dictionary = _pending[index]
		if String(request.get("request_id", "")) == request_id and int(request.get("owner_id", -1)) == owner_id and int(request.get("generation", -1)) == generation:
			_cancel_pending_at(index, tick, reason)
			return {"ok": true}
	return _reject("stale_activity_request")


func drain_events() -> Array[Dictionary]:
	var result: Array[Dictionary] = _duplicate_dictionary_array(_events)
	_events.clear()
	return result


func snapshot_state() -> Dictionary:
	return {
		"version": STATE_VERSION,
		"choice_seed": _choice_seed,
		"choice_rng_state": _choice_rng.state,
		"pending": _duplicate_dictionary_array(_pending),
		"active": _duplicate_dictionary_map(_active),
		"cooldown_until": _cooldown_until.duplicate(true),
		"events": _duplicate_dictionary_array(_events),
		"request_sequence": _request_sequence,
		"event_sequence": _event_sequence,
		"max_pending": _max_pending,
		"max_active": _max_active,
		"max_events": _max_events
	}


func restore_state(candidate: Dictionary) -> Dictionary:
	if String(candidate.get("version", "")) != STATE_VERSION:
		return _reject("state_version_mismatch")
	var raw_pending: Variant = candidate.get("pending", null)
	var raw_active: Variant = candidate.get("active", null)
	var raw_cooldowns: Variant = candidate.get("cooldown_until", null)
	var raw_events: Variant = candidate.get("events", null)
	if not raw_pending is Array or not raw_active is Dictionary or not raw_cooldowns is Dictionary or not raw_events is Array:
		return _reject("invalid_state_shape")
	var max_pending: int = int(candidate.get("max_pending", 0))
	var max_active: int = int(candidate.get("max_active", 0))
	var max_events: int = int(candidate.get("max_events", 0))
	if max_pending <= 0 or max_active <= 0 or max_events <= 0 or raw_pending.size() > max_pending or raw_active.size() > max_active or raw_events.size() > max_events or raw_cooldowns.size() > HARD_MAX_COOLDOWNS:
		return _reject("state_bound_exceeded")
	if max_pending > HARD_MAX_PENDING or max_active > HARD_MAX_ACTIVE or max_events > HARD_MAX_EVENTS:
		return _reject("state_hard_bound_exceeded")
	var restored_pending: Array[Dictionary] = []
	for request: Variant in raw_pending:
		if not request is Dictionary or not request.has("request_id") or not request.has("owner_id") or not request.has("generation"):
			return _reject("malformed_pending_request")
		restored_pending.append(request.duplicate(true))
	var restored_events: Array[Dictionary] = []
	for event: Variant in raw_events:
		if not event is Dictionary:
			return _reject("malformed_event")
		restored_events.append(event.duplicate(true))
	_choice_seed = _normalize_seed(int(candidate.get("choice_seed", 1)))
	_choice_rng.seed = _choice_seed
	_choice_rng.state = int(candidate.get("choice_rng_state", _choice_rng.state))
	_pending = restored_pending
	_active = raw_active.duplicate(true)
	_cooldown_until = raw_cooldowns.duplicate(true)
	_events = restored_events
	_request_sequence = int(candidate.get("request_sequence", 0))
	_event_sequence = int(candidate.get("event_sequence", 0))
	_max_pending = max_pending
	_max_active = max_active
	_max_events = max_events
	return {"ok": true}


func _request_less(left: Dictionary, right: Dictionary) -> bool:
	var left_priority: int = int(left.get("priority", 0))
	var right_priority: int = int(right.get("priority", 0))
	if left_priority != right_priority:
		return left_priority < right_priority
	var left_tick: int = int(left.get("request_tick", 0))
	var right_tick: int = int(right.get("request_tick", 0))
	if left_tick != right_tick:
		return left_tick < right_tick
	var left_owner: int = int(left.get("owner_id", 0))
	var right_owner: int = int(right.get("owner_id", 0))
	if left_owner != right_owner:
		return left_owner < right_owner
	var left_generation: int = int(left.get("generation", 0))
	var right_generation: int = int(right.get("generation", 0))
	if left_generation != right_generation:
		return left_generation < right_generation
	return String(left.get("request_id", "")) < String(right.get("request_id", ""))


func _activity_id_less(left: Dictionary, right: Dictionary) -> bool:
	return String(left.get("activity_id", "")) < String(right.get("activity_id", ""))


func _active_quota_counts() -> Dictionary:
	var counts: Dictionary = {}
	for lease: Dictionary in _active.values():
		var quota_key: String = String(lease.get("quota_key", ""))
		counts[quota_key] = int(counts.get(quota_key, 0)) + 1
	return counts


func _quota_definition_conflicts(quota_key: String, quota: int) -> bool:
	for lease: Dictionary in _active.values():
		if String(lease.get("quota_key", "")) == quota_key and int(lease.get("quota", -1)) != quota:
			return true
	for request: Dictionary in _pending:
		if String(request.get("quota_key", "")) == quota_key and int(request.get("quota", -1)) != quota:
			return true
	return false


func _has_pending_owner(owner_id: int, generation: int) -> bool:
	for request: Dictionary in _pending:
		if int(request.get("owner_id", -1)) == owner_id and int(request.get("generation", -1)) == generation:
			return true
	return false


func _request_id_exists(request_id: String) -> bool:
	for request: Dictionary in _pending:
		if String(request.get("request_id", "")) == request_id:
			return true
	for lease: Dictionary in _active.values():
		if String(lease.get("request_id", "")) == request_id:
			return true
	return false


func _remove_request_id(request_id: String) -> void:
	for index: int in range(_pending.size() - 1, -1, -1):
		if String(_pending[index].get("request_id", "")) == request_id:
			_pending.remove_at(index)
			return


func _cancel_pending_at(index: int, tick: int, reason: String) -> Dictionary:
	var request: Dictionary = _pending[index]
	_pending.remove_at(index)
	_record_event(tick, "activity_request_cancelled", {"request_id": request.get("request_id", ""), "owner_id": request.get("owner_id", -1), "generation": request.get("generation", -1), "activity_id": request.get("activity_id", ""), "reason": reason})
	return {"request_id": request.get("request_id", ""), "reason": reason}


func _set_cooldown(tick: int, lease: Dictionary) -> void:
	var key: String = _cooldown_key(String(lease.get("pilot_id", "")), String(lease.get("activity_id", "")))
	var deadline: int = tick + int(lease.get("repeat_cooldown_ticks", 0))
	_cooldown_until[key] = maxi(deadline, int(_cooldown_until.get(key, -1)))


func _owner_key(owner_id: int, generation: int) -> String:
	return str(owner_id) + ":" + str(generation)


func _cooldown_key(pilot_id: String, activity_id: String) -> String:
	return str(pilot_id.length()) + ":" + pilot_id + ":" + activity_id


func _normalize_seed(value: int) -> int:
	if value >= 1 and value <= 2147483646:
		return value
	var wrapped: int = value % 2147483646
	if wrapped < 0:
		wrapped = -wrapped
	return wrapped + 1


func _duplicate_dictionary_array(source: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Dictionary in source:
		result.append(value.duplicate(true))
	return result


func _duplicate_dictionary_map(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in source.keys():
		var value: Variant = source[key]
		result[key] = value.duplicate(true) if value is Dictionary else value
	return result


func _record_event(tick: int, event_type: String, payload: Dictionary) -> void:
	_event_sequence += 1
	_events.append({"sequence": _event_sequence, "tick": tick, "type": event_type, "payload": payload.duplicate(true)})
	while _events.size() > _max_events:
		_events.pop_front()


func _reject(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

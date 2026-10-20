extends RefCounted

## AFC runway coordination groundwork. This class is deliberately independent of
## scenes, aircraft laws, and render nodes. Every value in its public state is a
## scalar, String, Array, or Dictionary so a fleet journal can serialize it.

const STATE_VERSION: String = "openrc-runway-coordinator-state v1"
const TICK_RATE_HZ: int = 240
const CALM_HEADWIND_THRESHOLD_MPS: float = 1.0
const DIRECTION_REVERSAL_TICKS: int = 10 * TICK_RATE_HZ
const DEFAULT_RESERVATION_TTL_TICKS: int = 15 * TICK_RATE_HZ
const DEFAULT_FAIRNESS_PROMOTION_TICKS: int = 20 * TICK_RATE_HZ
const DEFAULT_MAX_QUEUE: int = 64
const DEFAULT_MAX_EVENTS: int = 128
const HARD_MAX_QUEUE: int = 256
const HARD_MAX_EVENTS: int = 512
const HARD_MAX_WRECKS: int = 64

const MODE_FREE: String = "free"
const MODE_RESERVED: String = "reserved"
const MODE_OCCUPIED: String = "occupied"
const MODE_CLEARING: String = "clearing"
const MODE_BLOCKED: String = "blocked"

const OP_LANDING: String = "landing"
const OP_TAKEOFF: String = "takeoff"
const OP_TOUCH_AND_GO: String = "touch_and_go"
const OP_LOW_PASS: String = "low_pass"
const OP_PASS: String = "pass"
const VALID_OPERATIONS: Array[String] = [OP_LANDING, OP_TAKEOFF, OP_TOUCH_AND_GO, OP_LOW_PASS, OP_PASS]

var _mode: String = MODE_FREE
var _direction: int = 1
var _wind_candidate_direction: int = 0
var _wind_candidate_since_tick: int = -1
var _last_wind_sample_tick: int = -1
var _headwind_component_mps: float = 0.0
var _crosswind_mps: float = 0.0
var _gust_mps: float = 0.0
var _player_in_runway: bool = false
var _player_approach_intent: bool = false
var _grant: Dictionary = {}
var _occupant: Dictionary = {}
var _blocked_wrecks: Dictionary = {}
var _requests: Array[Dictionary] = []
var _events: Array[Dictionary] = []
var _request_sequence: int = 0
var _grant_sequence: int = 0
var _event_sequence: int = 0
var _fairness_promotion_ticks: int = DEFAULT_FAIRNESS_PROMOTION_TICKS
var _reservation_ttl_ticks: int = DEFAULT_RESERVATION_TTL_TICKS
var _max_queue: int = DEFAULT_MAX_QUEUE
var _max_events: int = DEFAULT_MAX_EVENTS


func _init(initial_direction: int = 1, fairness_promotion_ticks: int = DEFAULT_FAIRNESS_PROMOTION_TICKS, reservation_ttl_ticks: int = DEFAULT_RESERVATION_TTL_TICKS, max_queue: int = DEFAULT_MAX_QUEUE, max_events: int = DEFAULT_MAX_EVENTS) -> void:
	if initial_direction == -1 or initial_direction == 1:
		_direction = initial_direction
	if fairness_promotion_ticks > 0:
		_fairness_promotion_ticks = fairness_promotion_ticks
	if reservation_ttl_ticks > 0:
		_reservation_ttl_ticks = reservation_ttl_ticks
	if max_queue > 0:
		_max_queue = mini(HARD_MAX_QUEUE, max_queue)
	if max_events > 0:
		_max_events = mini(HARD_MAX_EVENTS, max_events)


## Submit every same-tick request before calling resolve(). direction=0 follows
## the currently accepted runway direction. max wind limits below zero mean that
## this request has no authored limit and must be checked by a later profile gate.
func submit_request(tick: int, request_id: String, owner_id: int, generation: int, pilot_id: String, operation: String, direction: int = 0, player_request: bool = false, emergency: bool = false, committed_arrival: bool = false, protected_volume_id: String = "", earliest_entry_tick: int = -1, latest_entry_tick: int = -1, max_crosswind_mps: float = -1.0, max_gust_mps: float = -1.0, protected_volume_ids: Array = []) -> Dictionary:
	if tick < 0 or request_id.is_empty() or owner_id < 0 or generation < 0:
		return _reject("invalid_identity_or_tick")
	if not VALID_OPERATIONS.has(operation):
		return _reject("unsupported_operation")
	if direction != -1 and direction != 0 and direction != 1:
		return _reject("invalid_direction")
	if earliest_entry_tick < -1 or latest_entry_tick < -1:
		return _reject("invalid_entry_window")
	if latest_entry_tick >= 0 and earliest_entry_tick >= 0 and latest_entry_tick < earliest_entry_tick:
		return _reject("invalid_entry_window")
	if not _optional_limit_is_valid(max_crosswind_mps) or not _optional_limit_is_valid(max_gust_mps):
		return _reject("invalid_wind_limit")
	var protected_volumes: Array[String] = []
	for volume: Variant in protected_volume_ids:
		if not volume is String or String(volume).is_empty():
			return _reject("invalid_protected_volume")
		if not protected_volumes.has(String(volume)):
			protected_volumes.append(String(volume))
	if not protected_volume_id.is_empty() and not protected_volumes.has(protected_volume_id):
		protected_volumes.append(protected_volume_id)
	if _requests.size() >= _max_queue:
		return _reject("request_queue_full")
	if _request_id_exists(request_id):
		return _reject("duplicate_request_id")
	_request_sequence += 1
	_requests.append({
		"request_id": request_id,
		"owner_id": owner_id,
		"generation": generation,
		"pilot_id": pilot_id,
		"operation": operation,
		"direction": direction,
		"player_request": player_request,
		"emergency": emergency,
		"committed_arrival": committed_arrival,
		"protected_volume_id": protected_volume_id,
		"protected_volumes": protected_volumes,
		"request_tick": tick,
		"request_sequence": _request_sequence,
		"earliest_entry_tick": earliest_entry_tick,
		"latest_entry_tick": latest_entry_tick,
		"max_crosswind_mps": max_crosswind_mps,
		"max_gust_mps": max_gust_mps
	})
	_record_event(tick, "request_queued", {"request_id": request_id, "owner_id": owner_id, "generation": generation, "operation": operation})
	return {"ok": true, "request_id": request_id}


## Wind inputs are signed along the runway axis: a positive headwind component
## favors direction +1, a negative value favors -1. Crosswind and gust are
## magnitudes. Calm wind retains the accepted direction. A reversal waits ten
## simulation seconds and remains locked while a runway is occupied or an arrival
## is committed. A reservation whose wind envelope becomes invalid is revoked.
func update_wind(tick: int, headwind_component_mps: float, crosswind_mps: float, gust_mps: float) -> Dictionary:
	if tick < 0 or tick < _last_wind_sample_tick:
		return _reject("wind_tick_reversed")
	if not _finite_number(headwind_component_mps) or not _finite_number(crosswind_mps) or not _finite_number(gust_mps):
		return _reject("non_finite_wind")
	if crosswind_mps < 0.0 or gust_mps < 0.0:
		return _reject("negative_wind_magnitude")
	_last_wind_sample_tick = tick
	_headwind_component_mps = headwind_component_mps
	_crosswind_mps = crosswind_mps
	_gust_mps = gust_mps
	_check_grant_wind(tick)
	var preferred_direction: int = 0
	if absf(headwind_component_mps) >= CALM_HEADWIND_THRESHOLD_MPS:
		preferred_direction = 1 if headwind_component_mps > 0.0 else -1
	if preferred_direction == 0 or preferred_direction == _direction:
		_wind_candidate_direction = 0
		_wind_candidate_since_tick = -1
	elif preferred_direction != _wind_candidate_direction:
		_wind_candidate_direction = preferred_direction
		_wind_candidate_since_tick = tick
	_record_event(tick, "wind_sampled", {"headwind_component_mps": headwind_component_mps, "crosswind_mps": crosswind_mps, "gust_mps": gust_mps})
	return _consider_wind_reversal(tick)


## Player observations are advisory to the AI. The player is never constrained.
## A player approach or runway incursion immediately revokes a reserved AI grant;
## only a complete footprint and protected-path clearance releases occupancy.
func observe_player(tick: int, player_id: int, generation: int, in_runway: bool, approach_intent: bool) -> Dictionary:
	if tick < 0 or player_id < 0 or generation < 0:
		return _reject("invalid_player_identity_or_tick")
	var was_in_runway: bool = _player_in_runway
	var was_approaching: bool = _player_approach_intent
	_player_in_runway = in_runway
	_player_approach_intent = approach_intent
	var reserved_emergency: bool = bool(_grant.get("emergency", false))
	if (in_runway or (approach_intent and not reserved_emergency)) and _mode == MODE_RESERVED and not bool(_grant.get("player_request", false)):
		_revoke_reservation(tick, "player_incursion" if in_runway else "player_approach", true)
	if in_runway:
		if _mode != MODE_BLOCKED and not _occupant_matches(player_id, generation):
			if _mode == MODE_RESERVED:
				_revoke_reservation(tick, "player_incursion", true)
			_mode = MODE_OCCUPIED
			_occupant = {"owner_id": player_id, "generation": generation, "pilot_id": "player", "is_player": true, "is_wreck": false, "protected_volume_id": "player_runway"}
			_record_event(tick, "player_runway_occupancy", {"owner_id": player_id, "generation": generation})
	elif was_in_runway and _occupant_matches(player_id, generation):
		_mode = MODE_CLEARING
		_record_event(tick, "player_clearance_required", {"owner_id": player_id, "generation": generation})
	if was_approaching != approach_intent:
		_record_event(tick, "player_approach_changed", {"active": approach_intent})
	return {"ok": true, "mode": _mode, "player_priority_active": _player_in_runway or _player_approach_intent}


## Resolve after all requests for this planning boundary have been submitted.
## It expires unentered reservations, applies any matured wind reversal, then
## grants exactly one request using stable priority, age promotion, request time,
## ID, generation, and submission sequence ordering.
func resolve(tick: int) -> Dictionary:
	if tick < 0:
		return _reject("invalid_tick")
	_expire_requests(tick)
	if _mode == MODE_RESERVED and tick > int(_grant.get("deadline_tick", -1)):
		_revoke_reservation(tick, "reservation_expired", false)
	_consider_wind_reversal(tick)
	if _mode != MODE_FREE:
		return {"ok": true, "granted": false, "mode": _mode, "reason": "runway_not_free"}
	if _player_in_runway:
		return {"ok": true, "granted": false, "mode": _mode, "reason": "player_priority"}
	if _requests.is_empty():
		return {"ok": true, "granted": false, "mode": _mode, "reason": "queue_empty"}
	var ranked: Array[Dictionary] = []
	for request: Dictionary in _requests:
		if _player_approach_intent and not bool(request.get("emergency", false)) and not bool(request.get("player_request", false)):
			continue
		if not _request_direction_matches(request):
			continue
		var earliest: int = int(request.get("earliest_entry_tick", -1))
		if earliest >= 0 and earliest > tick:
			continue
		if not _request_wind_is_valid(request):
			continue
		ranked.append({"request": request, "priority": _effective_priority(request, tick)})
	if ranked.is_empty():
	return {"ok": true, "granted": false, "mode": _mode, "reason": "player_priority" if _player_approach_intent else "no_eligible_direction_or_wind"}
	ranked.sort_custom(_ranked_request_less)
	var winner: Dictionary = ranked[0]["request"]
	_remove_request_id(String(winner["request_id"]))
	_grant_sequence += 1
	var entry_tick: int = maxi(tick, int(winner.get("earliest_entry_tick", -1)))
	var deadline_tick: int = tick + _reservation_ttl_ticks
	var requested_deadline: int = int(winner.get("latest_entry_tick", -1))
	if requested_deadline >= 0:
		deadline_tick = mini(deadline_tick, requested_deadline)
	if deadline_tick < entry_tick:
		_record_event(tick, "request_cancelled", {"request_id": winner["request_id"], "reason": "entry_window_closed"})
		return resolve(tick)
	var grant: Dictionary = winner.duplicate(true)
	grant["ticket"] = _grant_sequence
	grant["requested_direction"] = int(winner["direction"])
	grant["direction"] = _direction if int(winner["direction"]) == 0 else int(winner["direction"])
	grant["entry_tick"] = entry_tick
	grant["deadline_tick"] = deadline_tick
	grant["granted_tick"] = tick
	_grant = grant
	_mode = MODE_RESERVED
	_record_event(tick, "reservation_granted", {"ticket": _grant_sequence, "request_id": winner["request_id"], "owner_id": winner["owner_id"], "generation": winner["generation"], "operation": winner["operation"], "direction": grant["direction"], "entry_tick": entry_tick, "deadline_tick": deadline_tick})
	return {"ok": true, "granted": true, "grant": _grant.duplicate(true)}


## A grant ticket is accepted once and only for the owner generation it names.
## Physical occupancy supersedes reservation timers and cannot expire.
func enter_runway(tick: int, ticket: int, owner_id: int, generation: int) -> Dictionary:
	if _mode != MODE_RESERVED or ticket != int(_grant.get("ticket", -1)) or owner_id != int(_grant.get("owner_id", -1)) or generation != int(_grant.get("generation", -1)):
		return _reject("stale_grant")
	if tick < int(_grant.get("entry_tick", -1)) or tick > int(_grant.get("deadline_tick", -1)):
		return _reject("entry_outside_grant_window")
	if _player_in_runway or (_player_approach_intent and not bool(_grant.get("emergency", false)) and not bool(_grant.get("player_request", false))):
		_revoke_reservation(tick, "player_incursion", true)
		return _reject("player_priority")
	if int(_grant.get("direction", 0)) != _direction:
		_revoke_reservation(tick, "runway_direction_changed", true)
		return _reject("runway_direction_changed")
	if not _request_wind_is_valid(_grant):
		_revoke_reservation(tick, "wind_envelope_exceeded", true)
		return _reject("wind_envelope_exceeded")
	_occupant = {"owner_id": owner_id, "generation": generation, "pilot_id": String(_grant.get("pilot_id", "")), "is_player": bool(_grant.get("player_request", false)), "is_wreck": false, "operation": String(_grant.get("operation", "")), "direction": _direction, "protected_volume_id": String(_grant.get("protected_volume_id", "")), "protected_volumes": _grant.get("protected_volumes", []).duplicate(true), "ticket": ticket}
	_mode = MODE_OCCUPIED
	_record_event(tick, "runway_occupied", {"ticket": ticket, "owner_id": owner_id, "generation": generation, "operation": _occupant["operation"]})
	_grant.clear()
	return {"ok": true, "mode": _mode}


## Reports geometric clearance from the caller's swept footprint query. It is
## intentionally impossible to release on a CG-only or timer-only observation.
func report_clearance(tick: int, owner_id: int, generation: int, footprint_clear: bool, protected_path_clear: bool) -> Dictionary:
	if tick < 0:
		return _reject("invalid_tick")
	if _mode != MODE_OCCUPIED and _mode != MODE_CLEARING:
		return _reject("no_movable_occupant")
	if bool(_occupant.get("is_wreck", false)) or owner_id != int(_occupant.get("owner_id", -1)) or generation != int(_occupant.get("generation", -1)):
		return _reject("occupant_identity_mismatch")
	if footprint_clear and protected_path_clear:
		var old_id: int = owner_id
		var old_generation: int = generation
		_occupant.clear()
		_mode = MODE_FREE
		_record_event(tick, "runway_cleared", {"owner_id": old_id, "generation": old_generation})
		return {"ok": true, "cleared": true, "mode": _mode}
	_mode = MODE_CLEARING if footprint_clear else MODE_OCCUPIED
	_record_event(tick, "clearance_observed", {"owner_id": owner_id, "generation": generation, "footprint_clear": footprint_clear, "protected_path_clear": protected_path_clear})
	return {"ok": true, "cleared": false, "mode": _mode}


## A physical runway wreck is a persistent blocker. It consumes occupancy until
## the owning world has removed that exact wreck and this atomic commit call clears
## the occupancy record. Reservation timers and normal clear-runway requests do
## not remove it.
func report_runway_wreck(tick: int, owner_id: int, generation: int, pilot_id: String, wreck_id: String, protected_volume_id: String = "runway") -> Dictionary:
	if tick < 0 or owner_id < 0 or generation < 0 or wreck_id.is_empty():
		return _reject("invalid_wreck_identity")
	if not _blocked_wrecks.has(wreck_id) and _blocked_wrecks.size() >= HARD_MAX_WRECKS:
		return _reject("wreck_blocker_capacity_exceeded")
	if _mode == MODE_RESERVED:
		_revoke_reservation(tick, "runway_wreck", false)
	_requests = _requests.filter(func(request: Dictionary) -> bool: return int(request.get("owner_id", -1)) != owner_id or int(request.get("generation", -1)) != generation)
	var wreck: Dictionary = {"owner_id": owner_id, "generation": generation, "pilot_id": pilot_id, "is_player": false, "is_wreck": true, "wreck_id": wreck_id, "protected_volume_id": protected_volume_id}
	if _mode != MODE_BLOCKED:
		_occupant = wreck.duplicate(true)
	_blocked_wrecks[wreck_id] = wreck
	_mode = MODE_BLOCKED
	_record_event(tick, "runway_blocked_by_wreck", {"owner_id": owner_id, "generation": generation, "wreck_id": wreck_id})
	return {"ok": true, "mode": _mode, "wreck_id": wreck_id}


func clear_wreck_and_occupancy(tick: int, wreck_id: String, wreck_removal_committed: bool) -> Dictionary:
	if tick < 0 or _mode != MODE_BLOCKED or wreck_id.is_empty() or not _blocked_wrecks.has(wreck_id):
		return _reject("wreck_identity_mismatch")
	if not wreck_removal_committed:
		return _reject("wreck_removal_not_committed")
	var removed_wreck: Dictionary = _blocked_wrecks[wreck_id]
	_blocked_wrecks.erase(wreck_id)
	if _blocked_wrecks.is_empty():
		_occupant.clear()
		_mode = MODE_FREE
	else:
		var remaining_ids: Array = _blocked_wrecks.keys()
		remaining_ids.sort()
		_occupant = _blocked_wrecks[String(remaining_ids[0])].duplicate(true)
	_record_event(tick, "runway_wreck_removed", {"wreck_id": wreck_id, "owner_id": removed_wreck.get("owner_id", -1), "generation": removed_wreck.get("generation", -1), "remaining_wrecks": _blocked_wrecks.size()})
	return {"ok": true, "mode": _mode, "remaining_wrecks": _blocked_wrecks.size()}


func cancel_request(tick: int, request_id: String, owner_id: int, generation: int, reason: String = "cancelled") -> Dictionary:
	if tick < 0:
		return _reject("invalid_tick")
	for index: int in range(_requests.size()):
		var request: Dictionary = _requests[index]
		if String(request.get("request_id", "")) == request_id and int(request.get("owner_id", -1)) == owner_id and int(request.get("generation", -1)) == generation:
			_requests.remove_at(index)
			_record_event(tick, "request_cancelled", {"request_id": request_id, "owner_id": owner_id, "generation": generation, "reason": reason})
			return {"ok": true}
	return _reject("stale_request")


func cancel_reservation(tick: int, ticket: int, owner_id: int, generation: int, reason: String = "cancelled") -> Dictionary:
	if tick < 0:
		return _reject("invalid_tick")
	if _mode != MODE_RESERVED or ticket != int(_grant.get("ticket", -1)) or owner_id != int(_grant.get("owner_id", -1)) or generation != int(_grant.get("generation", -1)):
		return _reject("stale_grant")
	_revoke_reservation(tick, reason, false)
	return {"ok": true}


func drain_events() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in _events:
		result.append(event.duplicate(true))
	_events.clear()
	return result


func snapshot_state() -> Dictionary:
	return {
		"version": STATE_VERSION,
		"mode": _mode,
		"direction": _direction,
		"wind_candidate_direction": _wind_candidate_direction,
		"wind_candidate_since_tick": _wind_candidate_since_tick,
		"last_wind_sample_tick": _last_wind_sample_tick,
		"headwind_component_mps": _headwind_component_mps,
		"crosswind_mps": _crosswind_mps,
		"gust_mps": _gust_mps,
		"player_in_runway": _player_in_runway,
		"player_approach_intent": _player_approach_intent,
		"grant": _grant.duplicate(true),
		"occupant": _occupant.duplicate(true),
		"blocked_wrecks": _blocked_wrecks.duplicate(true),
		"requests": _duplicate_dictionary_array(_requests),
		"events": _duplicate_dictionary_array(_events),
		"request_sequence": _request_sequence,
		"grant_sequence": _grant_sequence,
		"event_sequence": _event_sequence,
		"fairness_promotion_ticks": _fairness_promotion_ticks,
		"reservation_ttl_ticks": _reservation_ttl_ticks,
		"max_queue": _max_queue,
		"max_events": _max_events
	}


func restore_state(candidate: Dictionary) -> Dictionary:
	if String(candidate.get("version", "")) != STATE_VERSION:
		return _reject("state_version_mismatch")
	var mode: String = String(candidate.get("mode", ""))
	var direction: int = int(candidate.get("direction", 0))
	if not [MODE_FREE, MODE_RESERVED, MODE_OCCUPIED, MODE_CLEARING, MODE_BLOCKED].has(mode) or (direction != -1 and direction != 1):
		return _reject("invalid_state_header")
	var raw_requests: Variant = candidate.get("requests", null)
	var raw_events: Variant = candidate.get("events", null)
	var raw_grant: Variant = candidate.get("grant", null)
	var raw_occupant: Variant = candidate.get("occupant", null)
	var raw_wrecks: Variant = candidate.get("blocked_wrecks", null)
	if not raw_requests is Array or not raw_events is Array or not raw_grant is Dictionary or not raw_occupant is Dictionary or not raw_wrecks is Dictionary:
		return _reject("invalid_state_shape")
	if raw_requests.size() > int(candidate.get("max_queue", 0)) or raw_events.size() > int(candidate.get("max_events", 0)):
		return _reject("state_bound_exceeded")
	if int(candidate.get("max_queue", 0)) > HARD_MAX_QUEUE or int(candidate.get("max_events", 0)) > HARD_MAX_EVENTS or raw_wrecks.size() > HARD_MAX_WRECKS:
		return _reject("state_hard_bound_exceeded")
	if mode == MODE_RESERVED and raw_grant.is_empty():
		return _reject("reserved_state_missing_grant")
	if mode != MODE_RESERVED and not raw_grant.is_empty():
		return _reject("grant_outside_reserved_state")
	if (mode == MODE_OCCUPIED or mode == MODE_CLEARING or mode == MODE_BLOCKED) and raw_occupant.is_empty():
		return _reject("occupied_state_missing_occupant")
	if mode == MODE_BLOCKED and raw_wrecks.is_empty():
		return _reject("blocked_state_missing_wreck")
	if mode != MODE_BLOCKED and not raw_wrecks.is_empty():
		return _reject("wreck_state_outside_blocked_mode")
	var restored_requests: Array[Dictionary] = []
	for value: Variant in raw_requests:
		if not value is Dictionary or not value.has("request_id") or not value.has("owner_id") or not value.has("generation"):
			return _reject("malformed_request_state")
		restored_requests.append(value.duplicate(true))
	var restored_events: Array[Dictionary] = []
	for event: Variant in raw_events:
		if not event is Dictionary:
			return _reject("malformed_event_state")
		restored_events.append(event.duplicate(true))
	_mode = mode
	_direction = direction
	_wind_candidate_direction = int(candidate.get("wind_candidate_direction", 0))
	_wind_candidate_since_tick = int(candidate.get("wind_candidate_since_tick", -1))
	_last_wind_sample_tick = int(candidate.get("last_wind_sample_tick", -1))
	_headwind_component_mps = float(candidate.get("headwind_component_mps", 0.0))
	_crosswind_mps = float(candidate.get("crosswind_mps", 0.0))
	_gust_mps = float(candidate.get("gust_mps", 0.0))
	_player_in_runway = bool(candidate.get("player_in_runway", false))
	_player_approach_intent = bool(candidate.get("player_approach_intent", false))
	_grant = raw_grant.duplicate(true)
	_occupant = raw_occupant.duplicate(true)
	_blocked_wrecks = raw_wrecks.duplicate(true)
	_requests = restored_requests
	_events = restored_events
	_request_sequence = int(candidate.get("request_sequence", 0))
	_grant_sequence = int(candidate.get("grant_sequence", 0))
	_event_sequence = int(candidate.get("event_sequence", 0))
	_fairness_promotion_ticks = maxi(1, int(candidate.get("fairness_promotion_ticks", DEFAULT_FAIRNESS_PROMOTION_TICKS)))
	_reservation_ttl_ticks = maxi(1, int(candidate.get("reservation_ttl_ticks", DEFAULT_RESERVATION_TTL_TICKS)))
	_max_queue = clampi(int(candidate.get("max_queue", DEFAULT_MAX_QUEUE)), 1, HARD_MAX_QUEUE)
	_max_events = clampi(int(candidate.get("max_events", DEFAULT_MAX_EVENTS)), 1, HARD_MAX_EVENTS)
	return {"ok": true}


func _consider_wind_reversal(tick: int) -> Dictionary:
	if _wind_candidate_direction == 0 or _wind_candidate_since_tick < 0:
		return {"ok": true, "changed": false}
	if tick - _wind_candidate_since_tick < DIRECTION_REVERSAL_TICKS:
		return {"ok": true, "changed": false}
	if _mode == MODE_OCCUPIED or _mode == MODE_CLEARING or _mode == MODE_BLOCKED or _has_committed_arrival():
		return {"ok": true, "changed": false, "locked": true}
	var previous_direction: int = _direction
	_direction = _wind_candidate_direction
	_wind_candidate_direction = 0
	_wind_candidate_since_tick = -1
	if _mode == MODE_RESERVED:
		_revoke_reservation(tick, "wind_direction_reversed", true)
	_record_event(tick, "runway_direction_changed", {"previous_direction": previous_direction, "direction": _direction})
	return {"ok": true, "changed": true, "direction": _direction}


func _check_grant_wind(tick: int) -> void:
	if _mode != MODE_RESERVED or _grant.is_empty():
		return
	if not _request_wind_is_valid(_grant):
		_revoke_reservation(tick, "wind_envelope_exceeded", true)


func _request_wind_is_valid(request: Dictionary) -> bool:
	var cross_limit: float = float(request.get("max_crosswind_mps", -1.0))
	var gust_limit: float = float(request.get("max_gust_mps", -1.0))
	if cross_limit >= 0.0 and _crosswind_mps > cross_limit:
		return false
	if gust_limit >= 0.0 and _gust_mps > gust_limit:
		return false
	return true


func _effective_priority(request: Dictionary, tick: int) -> int:
	var base: int = _base_priority(request)
	if base <= 1:
		return base
	var age_ticks: int = maxi(0, tick - int(request.get("request_tick", tick)))
	var promotions: int = mini(3, floori(float(age_ticks) / float(_fairness_promotion_ticks)))
	return maxi(2, base - promotions)


func _base_priority(request: Dictionary) -> int:
	if bool(request.get("emergency", false)):
		return 0
	if bool(request.get("player_request", false)):
		return 1
	if String(request.get("operation", "")) == OP_LANDING and bool(request.get("committed_arrival", false)):
		return 2
	if String(request.get("operation", "")) == OP_LANDING:
		return 3
	if String(request.get("operation", "")) == OP_TAKEOFF or String(request.get("operation", "")) == OP_TOUCH_AND_GO:
		return 4
	return 5


func _ranked_request_less(left: Dictionary, right: Dictionary) -> bool:
	var left_request: Dictionary = left["request"]
	var right_request: Dictionary = right["request"]
	var left_priority: int = int(left["priority"])
	var right_priority: int = int(right["priority"])
	if left_priority != right_priority:
		return left_priority < right_priority
	var left_tick: int = int(left_request.get("request_tick", 0))
	var right_tick: int = int(right_request.get("request_tick", 0))
	if left_tick != right_tick:
		return left_tick < right_tick
	var left_owner: int = int(left_request.get("owner_id", 0))
	var right_owner: int = int(right_request.get("owner_id", 0))
	if left_owner != right_owner:
		return left_owner < right_owner
	var left_generation: int = int(left_request.get("generation", 0))
	var right_generation: int = int(right_request.get("generation", 0))
	if left_generation != right_generation:
		return left_generation < right_generation
	var left_request_id: String = String(left_request.get("request_id", ""))
	var right_request_id: String = String(right_request.get("request_id", ""))
	if left_request_id != right_request_id:
		return left_request_id < right_request_id
	return int(left_request.get("request_sequence", 0)) < int(right_request.get("request_sequence", 0))


func _request_direction_matches(request: Dictionary) -> bool:
	var requested_direction: int = int(request.get("direction", 0))
	return requested_direction == 0 or requested_direction == _direction


func _has_committed_arrival() -> bool:
	if _mode == MODE_RESERVED and String(_grant.get("operation", "")) == OP_LANDING and bool(_grant.get("committed_arrival", false)):
		return true
	for request: Dictionary in _requests:
		if String(request.get("operation", "")) == OP_LANDING and bool(request.get("committed_arrival", false)):
			return true
	return false


func _expire_requests(tick: int) -> void:
	for index: int in range(_requests.size() - 1, -1, -1):
		var request: Dictionary = _requests[index]
		var latest: int = int(request.get("latest_entry_tick", -1))
		if latest >= 0 and tick > latest:
			_record_event(tick, "request_cancelled", {"request_id": request.get("request_id", ""), "owner_id": request.get("owner_id", -1), "generation": request.get("generation", -1), "reason": "request_expired"})
			_requests.remove_at(index)


func _revoke_reservation(tick: int, reason: String, requeue: bool) -> void:
	if _mode != MODE_RESERVED or _grant.is_empty():
		return
	var old_grant: Dictionary = _grant.duplicate(true)
	_grant.clear()
	_mode = MODE_FREE
	_record_event(tick, "reservation_revoked", {"ticket": old_grant.get("ticket", -1), "request_id": old_grant.get("request_id", ""), "owner_id": old_grant.get("owner_id", -1), "generation": old_grant.get("generation", -1), "reason": reason})
	if requeue and _requests.size() < _max_queue:
		old_grant.erase("ticket")
		old_grant.erase("entry_tick")
		old_grant.erase("deadline_tick")
		old_grant.erase("granted_tick")
		old_grant["direction"] = int(old_grant.get("requested_direction", old_grant.get("direction", 0)))
		old_grant.erase("requested_direction")
		_requests.append(old_grant)


func _request_id_exists(request_id: String) -> bool:
	if _mode == MODE_RESERVED and String(_grant.get("request_id", "")) == request_id:
		return true
	for request: Dictionary in _requests:
		if String(request.get("request_id", "")) == request_id:
			return true
	return false


func _remove_request_id(request_id: String) -> void:
	for index: int in range(_requests.size() - 1, -1, -1):
		if String(_requests[index].get("request_id", "")) == request_id:
			_requests.remove_at(index)
			return


func _occupant_matches(owner_id: int, generation: int) -> bool:
	return not _occupant.is_empty() and int(_occupant.get("owner_id", -1)) == owner_id and int(_occupant.get("generation", -1)) == generation


func _optional_limit_is_valid(value: float) -> bool:
	return _finite_number(value) and value >= -1.0


func _finite_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))


func _duplicate_dictionary_array(source: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Dictionary in source:
		result.append(value.duplicate(true))
	return result


func _record_event(tick: int, event_type: String, payload: Dictionary) -> void:
	_event_sequence += 1
	_events.append({"sequence": _event_sequence, "tick": tick, "type": event_type, "payload": payload.duplicate(true)})
	while _events.size() > _max_events:
		_events.pop_front()


func _reject(reason: String) -> Dic
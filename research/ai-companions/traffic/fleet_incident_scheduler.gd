extends RefCounted

## Deterministic AFC-19 opportunity scheduler. It emits bounded intent episodes;
## it never alters an aircraft state or asserts a crash. All deadlines use fleet
## simulation ticks, independent of render callbacks and aircraft count.

const STATE_VERSION: String = "openrc-fleet-incident-scheduler-state v1"
const RATE_OFF: String = "off"
const RATE_RARE: String = "rare"
const RATE_OCCASIONAL: String = "occasional"
const RATE_LIVELY: String = "lively"
const VALID_RATES: Array[String] = [RATE_OFF, RATE_RARE, RATE_OCCASIONAL, RATE_LIVELY]

const TICK_RATE_HZ: int = 240
const FIRST_INCIDENT_GRACE_TICKS: int = 60 * TICK_RATE_HZ
const MIN_FLEET_INTERVAL_TICKS: int = 120 * TICK_RATE_HZ
const MIN_PILOT_INTERVAL_TICKS: int = 180 * TICK_RATE_HZ
const DEFAULT_MAX_EVENTS: int = 256
const HARD_MAX_EVENTS: int = 1024
const HARD_MAX_TRACKED_PILOTS: int = 128
const MAX_CRASH_PRONE_FRACTION: float = 0.25
const RNG_ALGORITHM_ID: String = "Godot.RandomNumberGenerator 4.7.2-stable"

var _seed: int = 1
var _time_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _pilot_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _severity_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _rate_name: String = RATE_OFF
var _rate_per_minute: float = 0.0
var _start_tick: int = 0
var _grace_until_tick: int = FIRST_INCIDENT_GRACE_TICKS
var _last_advanced_tick: int = -1
var _next_deadline_tick: int = -1
var _last_fleet_start_tick: int = -1
var _last_pilot_start_tick: Dictionary = {}
var _active: Dictionary = {}
var _allow_crash_prone: bool = false
var _opportunity_count: int = 0
var _eligible_start_count: int = 0
var _crash_prone_start_count: int = 0
var _event_sequence: int = 0
var _events: Array[Dictionary] = []
var _max_events: int = DEFAULT_MAX_EVENTS


func _init(seed_value: int = 1, rate_name: String = RATE_OFF, start_tick: int = 0, allow_crash_prone: bool = false, max_events: int = DEFAULT_MAX_EVENTS) -> void:
	_seed = _normalize_seed(seed_value)
	_time_rng.seed = _derive_stream_seed(_seed, 17)
	_pilot_rng.seed = _derive_stream_seed(_seed, 31)
	_severity_rng.seed = _derive_stream_seed(_seed, 47)
	_start_tick = maxi(0, start_tick)
	_grace_until_tick = _start_tick + FIRST_INCIDENT_GRACE_TICKS
	_allow_crash_prone = allow_crash_prone
	_max_events = clampi(max_events, 1, HARD_MAX_EVENTS)
	set_rate(rate_name, _start_tick)


## Rate names correspond to fleet-wide opportunity rates: Off=0, Rare=1/20,
## Occasional=1/8, Lively=1/3 per simulated minute. Changing rate is an explicit
## settings event: it resamples the next interval from the fixed time stream.
func set_rate(rate_name: String, tick: int) -> Dictionary:
	if tick < 0 or tick < _last_advanced_tick or not VALID_RATES.has(rate_name):
		return _reject("invalid_rate_or_tick")
	if rate_name == _rate_name:
		return {"ok": true, "changed": false, "next_deadline_tick": _next_deadline_tick}
	_rate_name = rate_name
	_rate_per_minute = _rate_for_name(rate_name)
	if _rate_name == RATE_OFF:
		_next_deadline_tick = -1
		if not _active.is_empty():
			var old: Dictionary = _active.duplicate(true)
			_active.clear()
			_record_event(tick, "incident_cancelled", {"opportunity_id": old.get("opportunity_id", -1), "pilot_id": old.get("pilot_id", ""), "reason": "incidents_disabled"})
	else:
		var schedule_origin: int = maxi(tick, _grace_until_tick)
		_schedule_after(schedule_origin)
	_record_event(tick, "incident_rate_changed", {"rate": _rate_name, "opportunities_per_minute": _rate_per_minute, "next_deadline_tick": _next_deadline_tick})
	return {"ok": true, "changed": true, "next_deadline_tick": _next_deadline_tick}


func set_crash_prone_allowed(tick: int, allowed: bool) -> Dictionary:
	if tick < 0 or tick < _last_advanced_tick:
		return _reject("invalid_policy_tick")
	if _allow_crash_prone == allowed:
		return {"ok": true, "changed": false}
	_allow_crash_prone = allowed
	_record_event(tick, "crash_prone_policy_changed", {"allowed": allowed})
	return {"ok": true, "changed": true}


## `eligible_pilots` is the planning snapshot at each due opportunity. Rows use
## stable pilot_id, owner_id and generation, an eligible flag/reason, optional
## episode_options, and crash_prone_eligible. Safety and recovery-space gates are
## fleet-wide facts. If a caller catches up over several deadlines, every missed
## event is recorded at its scheduled tick and rechecked; no opportunity is saved
## for later, so skipped/ineligible events cannot create a postponed burst.
func advance_to(tick: int, eligible_pilots: Array, player_protective_volume_clear: bool = true, recovery_space_clear: bool = true) -> Array[Dictionary]:
	var emitted: Array[Dictionary] = []
	if tick < 0 or tick < _last_advanced_tick:
		return emitted
	_last_advanced_tick = tick
	if _rate_name == RATE_OFF:
		return emitted
	while _next_deadline_tick >= 0 and _next_deadline_tick <= tick:
		var deadline: int = _next_deadline_tick
		_process_opportunity(deadline, eligible_pilots, player_protective_volume_clear, recovery_space_clear, emitted)
		_schedule_after(deadline)
	return emitted


func complete_incident(tick: int, opportunity_id: int, outcome: String = "episode_ended") -> Dictionary:
	if tick < int(_active.get("tick", 0)) or _active.is_empty() or opportunity_id != int(_active.get("opportunity_id", -1)):
		return _reject("stale_incident")
	var old: Dictionary = _active.duplicate(true)
	_active.clear()
	var event: Dictionary = _record_event(tick, "incident_completed", {"opportunity_id": opportunity_id, "pilot_id": old.get("pilot_id", ""), "outcome": outcome, "crash_prone_episode": old.get("crash_prone_episode", false)})
	return {"ok": true, "event": event}


func cancel_active(tick: int, opportunity_id: int, reason: String) -> Dictionary:
	if tick < int(_active.get("tick", 0)) or _active.is_empty() or opportunity_id != int(_active.get("opportunity_id", -1)):
		return _reject("stale_incident")
	var old: Dictionary = _active.duplicate(true)
	_active.clear()
	var event: Dictionary = _record_event(tick, "incident_cancelled", {"opportunity_id": opportunity_id, "pilot_id": old.get("pilot_id", ""), "reason": reason})
	return {"ok": true, "event": event}


func next_deadline_tick() -> int:
	return _next_deadline_tick


func opportunity_count() -> int:
	return _opportunity_count


func active_incident() -> Dictionary:
	return _active.duplicate(true)


func drain_events() -> Array[Dictionary]:
	var result: Array[Dictionary] = _duplicate_dictionary_array(_events)
	_events.clear()
	return result


func snapshot_state() -> Dictionary:
	return {
		"version": STATE_VERSION,
		"rng_algorithm": RNG_ALGORITHM_ID,
		"seed": _seed,
		"time_rng_state": _time_rng.state,
		"pilot_rng_state": _pilot_rng.state,
		"severity_rng_state": _severity_rng.state,
		"rate": _rate_name,
		"rate_per_minute": _rate_per_minute,
		"start_tick": _start_tick,
		"grace_until_tick": _grace_until_tick,
		"last_advanced_tick": _last_advanced_tick,
		"next_deadline_tick": _next_deadline_tick,
		"last_fleet_start_tick": _last_fleet_start_tick,
		"last_pilot_start_tick": _last_pilot_start_tick.duplicate(true),
		"active": _active.duplicate(true),
		"allow_crash_prone": _allow_crash_prone,
		"opportunity_count": _opportunity_count,
		"eligible_start_count": _eligible_start_count,
		"crash_prone_start_count": _crash_prone_start_count,
		"event_sequence": _event_sequence,
		"events": _duplicate_dictionary_array(_events),
		"max_events": _max_events
	}


func restore_state(candidate: Dictionary) -> Dictionary:
	if String(candidate.get("version", "")) != STATE_VERSION or String(candidate.get("rng_algorithm", "")) != RNG_ALGORITHM_ID:
		return _reject("state_or_rng_version_mismatch")
	var rate_name: String = String(candidate.get("rate", ""))
	var raw_active: Variant = candidate.get("active", null)
	var raw_cooldowns: Variant = candidate.get("last_pilot_start_tick", null)
	var raw_events: Variant = candidate.get("events", null)
	if not VALID_RATES.has(rate_name) or not raw_active is Dictionary or not raw_cooldowns is Dictionary or not raw_events is Array:
		return _reject("invalid_state_shape")
	var max_events: int = int(candidate.get("max_events", 0))
	if max_events <= 0 or raw_events.size() > max_events:
		return _reject("state_bound_exceeded")
	if max_events > HARD_MAX_EVENTS or raw_cooldowns.size() > HARD_MAX_TRACKED_PILOTS:
		return _reject("state_hard_bound_exceeded")
	if rate_name == RATE_OFF and int(candidate.get("next_deadline_tick", -1)) != -1:
		return _reject("off_state_has_deadline")
	if rate_name != RATE_OFF and int(candidate.get("next_deadline_tick", -1)) < 0:
		return _reject("enabled_state_missing_deadline")
	if rate_name != RATE_OFF and int(candidate.get("next_deadline_tick", -1)) <= int(candidate.get("last_advanced_tick", -1)):
		return _reject("enabled_state_deadline_not_in_future")
	if not raw_active.is_empty() and (not raw_active.has("opportunity_id") or not raw_active.has("pilot_id") or not raw_active.has("generation")):
		return _reject("malformed_active_incident")
	var restored_events: Array[Dictionary] = []
	for event: Variant in raw_events:
		if not event is Dictionary:
			return _reject("malformed_event")
		restored_events.append(event.duplicate(true))
	_seed = _normalize_seed(int(candidate.get("seed", 1)))
	_time_rng.seed = _derive_stream_seed(_seed, 17)
	_pilot_rng.seed = _derive_stream_seed(_seed, 31)
	_severity_rng.seed = _derive_stream_seed(_seed, 47)
	_time_rng.state = int(candidate.get("time_rng_state", _time_rng.state))
	_pilot_rng.state = int(candidate.get("pilot_rng_state", _pilot_rng.state))
	_severity_rng.state = int(candidate.get("severity_rng_state", _severity_rng.state))
	_rate_name = rate_name
	_rate_per_minute = _rate_for_name(rate_name)
	_start_tick = int(candidate.get("start_tick", 0))
	_grace_until_tick = int(candidate.get("grace_until_tick", _start_tick + FIRST_INCIDENT_GRACE_TICKS))
	_last_advanced_tick = int(candidate.get("last_advanced_tick", -1))
	_next_deadline_tick = int(candidate.get("next_deadline_tick", -1))
	_last_fleet_start_tick = int(candidate.get("last_fleet_start_tick", -1))
	_last_pilot_start_tick = raw_cooldowns.duplicate(true)
	_active = raw_active.duplicate(true)
	_allow_crash_prone = bool(candidate.get("allow_crash_prone", false))
	_opportunity_count = int(candidate.get("opportunity_count", 0))
	_eligible_start_count = int(candidate.get("eligible_start_count", 0))
	_crash_prone_start_count = int(candidate.get("crash_prone_start_count", 0))
	_event_sequence = int(candidate.get("event_sequence", 0))
	_events = restored_events
	_max_events = max_events
	return {"ok": true}


func _process_opportunity(tick: int, eligible_pilots: Array, player_clear: bool, recovery_clear: bool, emitted: Array[Dictionary]) -> void:
	_opportunity_count += 1
	var opportunity_id: int = _opportunity_count
	var opportunity_event: Dictionary = _record_event(tick, "incident_opportunity", {"opportunity_id": opportunity_id, "rate": _rate_name})
	emitted.append(opportunity_event)
	var cancel_reason: String = ""
	if not player_clear:
		cancel_reason = "player_protective_volume"
	elif not recovery_clear:
		cancel_reason = "recovery_space_occupied"
	elif not _active.is_empty():
		cancel_reason = "incident_already_active"
	elif _last_fleet_start_tick >= 0 and tick - _last_fleet_start_tick < MIN_FLEET_INTERVAL_TICKS:
		cancel_reason = "fleet_cooldown"
	if not cancel_reason.is_empty():
		emitted.append(_record_event(tick, "incident_cancelled", {"opportunity_id": opportunity_id, "reason": cancel_reason}))
		return
	var candidates: Array[Dictionary] = []
	var saw_eligible: bool = false
	var saw_pilot_cooldown: bool = false
	for raw_candidate: Variant in eligible_pilots:
		if not raw_candidate is Dictionary:
			continue
		var candidate: Dictionary = raw_candidate
		if not bool(candidate.get("eligible", false)):
			continue
		saw_eligible = true
		var pilot_id: String = String(candidate.get("pilot_id", ""))
		if pilot_id.is_empty() or int(candidate.get("owner_id", -1)) < 0 or int(candidate.get("generation", -1)) < 0:
			continue
		var prior_tick: int = int(_last_pilot_start_tick.get(pilot_id, -1))
		if prior_tick >= 0 and tick - prior_tick < MIN_PILOT_INTERVAL_TICKS:
			saw_pilot_cooldown = true
			continue
		candidates.append(candidate.duplicate(true))
	if candidates.is_empty():
		cancel_reason = "pilot_cooldown" if saw_eligible and saw_pilot_cooldown else "no_eligible_pilot"
		emitted.append(_record_event(tick, "incident_cancelled", {"opportunity_id": opportunity_id, "reason": cancel_reason}))
		return
	candidates.sort_custom(_pilot_candidate_less)
	var pilot_index: int = _pilot_rng.randi_range(0, candidates.size() - 1)
	var selected: Dictionary = candidates[pilot_index]
	var selected_pilot_id: String = String(selected["pilot_id"])
	if not _last_pilot_start_tick.has(selected_pilot_id) and _last_pilot_start_tick.size() >= HARD_MAX_TRACKED_PILOTS:
		emitted.append(_record_event(tick, "incident_cancelled", {"opportunity_id": opportunity_id, "reason": "pilot_history_capacity"}))
		return
	var options: Array = selected.get("episode_options", [])
	var episode_family: String = "bounded_mistake"
	if not options.is_empty():
		var valid_options: Array[String] = []
		for option: Variant in options:
			if option is String and not String(option).is_empty():
				valid_options.append(String(option))
		valid_options.sort()
		if not valid_options.is_empty():
			episode_family = valid_options[_pilot_rng.randi_range(0, valid_options.size() - 1)]
	_eligible_start_count += 1
	var crash_prone_episode: bool = false
	var current_quota: int = floori(float(_eligible_start_count) * MAX_CRASH_PRONE_FRACTION)
	if _allow_crash_prone and bool(selected.get("crash_prone_eligible", false)) and _crash_prone_start_count < current_quota:
		crash_prone_episode = _severity_rng.randf() < MAX_CRASH_PRONE_FRACTION
	if crash_prone_episode:
		_crash_prone_start_count += 1
	var active: Dictionary = {
		"opportunity_id": opportunity_id,
		"tick": tick,
		"pilot_id": String(selected["pilot_id"]),
		"owner_id": int(selected["owner_id"]),
		"generation": int(selected["generation"]),
		"episode_family": episode_family,
		"crash_prone_episode": crash_prone_episode,
		"seed": _seed
	}
	_active = active
	_last_fleet_start_tick = tick
	_last_pilot_start_tick[String(selected["pilot_id"])] = tick
	emitted.append(_record_event(tick, "incident_started", {"opportunity_id": opportunity_id, "pilot_id": active["pilot_id"], "owner_id": active["owner_id"], "generation": active["generation"], "episode_family": episode_family, "crash_prone_episode": crash_prone_episode}))


func _schedule_after(origin_tick: int) -> void:
	if _rate_per_minute <= 0.0:
		_next_deadline_tick = -1
		return
	var uniform_complement: float = maxf(0.000000000001, 1.0 - _time_rng.randf())
	var waiting_minutes: float = -log(uniform_complement) / _rate_per_minute
	var wait_ticks: int = maxi(1, ceili(waiting_minutes * 60.0 * float(TICK_RATE_HZ)))
	_next_deadline_tick = origin_tick + wait_ticks


func _rate_for_name(rate_name: String) -> float:
	match rate_name:
		RATE_RARE:
			return 1.0 / 20.0
		RATE_OCCASIONAL:
			return 1.0 / 8.0
		RATE_LIVELY:
			return 1.0 / 3.0
		_:
			return 0.0


func _pilot_candidate_less(left: Dictionary, right: Dictionary) -> bool:
	var left_pilot: String = String(left.get("pilot_id", ""))
	var right_pilot: String = String(right.get("pilot_id", ""))
	if left_pilot != right_pilot:
		return left_pilot < right_pilot
	var left_owner: int = int(left.get("owner_id", -1))
	var right_owner: int = int(right.get("owner_id", -1))
	if left_owner != right_owner:
		return left_owner < right_owner
	return int(left.get("generation", -1)) < int(right.get("generation", -1))


func _normalize_seed(value: int) -> int:
	if value >= 1 and value <= 2147483646:
		return value
	var wrapped: int = value % 2147483646
	if wrapped < 0:
		wrapped = -wrapped
	return wrapped + 1


func _derive_stream_seed(base_seed: int, salt: int) -> int:
	return int(((base_seed * 48271 + salt) % 2147483646) + 1)


func _duplicate_dictionary_array(source: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Dictionary in source:
		result.append(value.duplicate(true))
	return result


func _record_event(tick: int, event_type: String, payload: Dictionary) -> Dictionary:
	_event_sequence += 1
	var event: Dictionary = {"sequence": _event_sequence, "tick": tick, "type": event_type, "payload": payload.duplicate(true)}
	_events.append(event)
	while _events.size() > _max_events:
		_events.pop_front()
	return event.duplicate(true)


func _reject(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

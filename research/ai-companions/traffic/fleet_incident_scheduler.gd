extends RefCounted

## Deterministic AFC-19 opportunity scheduler. It emits bounded intent episodes;
## it never alters an aircraft state or asserts a crash. All deadlines use fleet
## simulation ticks, independent of render callbacks and aircraft count.

const STATE_VERSION: String = "openrc-fleet-incident-scheduler-state v2"
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
const HARD_MAX_FAMILIES_PER_PILOT: int = 64
const DEFAULT_MAX_EPISODE_DURATION_TICKS: int = 30 * TICK_RATE_HZ
const HARD_MAX_EPISODE_DURATION_TICKS: int = 5 * 60 * TICK_RATE_HZ
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
var _max_episode_duration_ticks: int = DEFAULT_MAX_EPISODE_DURATION_TICKS


func _init(seed_value: int = 1, rate_name: String = RATE_OFF, start_tick: int = 0, allow_crash_prone: bool = false, max_events: int = DEFAULT_MAX_EVENTS, max_episode_duration_ticks: int = DEFAULT_MAX_EPISODE_DURATION_TICKS) -> void:
	_seed = _normalize_seed(seed_value)
	_time_rng.seed = _derive_stream_seed(_seed, 17)
	_pilot_rng.seed = _derive_stream_seed(_seed, 31)
	_severity_rng.seed = _derive_stream_seed(_seed, 47)
	_start_tick = maxi(0, start_tick)
	_grace_until_tick = _start_tick + FIRST_INCIDENT_GRACE_TICKS
	_allow_crash_prone = allow_crash_prone
	_max_events = clampi(max_events, 1, HARD_MAX_EVENTS)
	_max_episode_duration_ticks = clampi(max_episode_duration_ticks, 1, HARD_MAX_EPISODE_DURATION_TICKS)
	set_rate(rate_name, _start_tick)


## Rate names correspond to fleet-wide opportunity rates: Off=0, Rare=1/20,
## Occasional=1/8, Lively=1/3 per simulated minute. Changing rate is an explicit
## settings event: it resamples the next interval from the fixed time stream.
func set_rate(rate_name: String, tick: int) -> Dictionary:
	if tick < 0 or tick < _last_advanced_tick or not VALID_RATES.has(rate_name):
		return _reject("invalid_rate_or_tick")
	if _rate_name != RATE_OFF and _next_deadline_tick >= 0 and _next_deadline_tick <= tick:
		return _reject("opportunity_deadline_missed")
	_expire_active_episode(tick)
	_last_advanced_tick = tick
	if rate_name == _rate_name:
		return {"ok": true, "changed": false, "next_deadline_tick": _next_deadline_tick}
	_rate_name = rate_name
	_rate_per_minute = _rate_for_name(rate_name)
	if _rate_name == RATE_OFF:
		_next_deadline_tick = -1
		if not _active.is_empty():
			var old: Dictionary = _active.duplicate(true)
			_active.clear()
			_record_event(tick, "incident_cancelled", {"opportunity_id": old.get("opportunity_id", -1), "pilot_id": old.get("pilot_id", ""), "episode_family": old.get("episode_family", ""), "crash_prone": old.get("crash_prone", false), "reason": "incidents_disabled"})
	else:
		var schedule_origin: int = maxi(tick, _grace_until_tick)
		_schedule_after(schedule_origin)
	_record_event(tick, "incident_rate_changed", {"rate": _rate_name, "opportunities_per_minute": _rate_per_minute, "next_deadline_tick": _next_deadline_tick})
	return {"ok": true, "changed": true, "next_deadline_tick": _next_deadline_tick}


func set_crash_prone_allowed(tick: int, allowed: bool) -> Dictionary:
	if tick < 0 or tick < _last_advanced_tick:
		return _reject("invalid_policy_tick")
	if _rate_name != RATE_OFF and _next_deadline_tick >= 0 and _next_deadline_tick <= tick:
		return _reject("opportunity_deadline_missed")
	_expire_active_episode(tick)
	_last_advanced_tick = tick
	if _allow_crash_prone == allowed:
		return {"ok": true, "changed": false}
	_allow_crash_prone = allowed
	_record_event(tick, "crash_prone_policy_changed", {"allowed": allowed})
	return {"ok": true, "changed": true}


## `eligible_pilots` and safety gates are a planning snapshot valid at `tick`.
## Rows use stable pilot identity and classified `episode_families`. Opportunity
## snapshots must be supplied at their exact deadline; a late call is rejected
## atomically rather than applying current eligibility to historical events. The
## fleet clock calls this once per fixed tick, so render-frame cadence is absent
## from the scheduler contract and every call has bounded work.
func advance_to(tick: int, eligible_pilots: Array, player_protective_volume_clear: bool = true, recovery_space_clear: bool = true) -> Dictionary:
	if tick < 0 or tick < _last_advanced_tick:
		return {"ok": false, "reason": "invalid_or_reversed_tick", "events": []}
	if _rate_name != RATE_OFF and _next_deadline_tick >= 0 and _next_deadline_tick < tick:
		return {"ok": false, "reason": "opportunity_snapshot_not_at_deadline", "next_deadline_tick": _next_deadline_tick, "events": []}
	if _rate_name != RATE_OFF and _next_deadline_tick == tick and not _valid_roster_snapshot(eligible_pilots):
		return {"ok": false, "reason": "invalid_opportunity_roster", "events": []}
	_last_advanced_tick = tick
	var emitted: Array[Dictionary] = []
	var timeout_event: Dictionary = _expire_active_episode(tick)
	if not timeout_event.is_empty():
		emitted.append(timeout_event)
	if _rate_name != RATE_OFF and _next_deadline_tick == tick:
		_process_opportunity(tick, eligible_pilots, player_protective_volume_clear, recovery_space_clear, emitted)
		_schedule_after(tick)
	return {"ok": true, "events": emitted}


func complete_incident(tick: int, opportunity_id: int, outcome: String = "episode_ended") -> Dictionary:
	if tick < 0 or tick < _last_advanced_tick:
		return _reject("invalid_or_reversed_tick")
	if outcome.is_empty():
		return _reject("invalid_completion_outcome")
	if _rate_name != RATE_OFF and _next_deadline_tick >= 0 and _next_deadline_tick <= tick:
		return _reject("opportunity_deadline_missed")
	_last_advanced_tick = tick
	_expire_active_episode(tick)
	if tick < int(_active.get("tick", 0)) or _active.is_empty() or opportunity_id != int(_active.get("opportunity_id", -1)):
		return _reject("stale_incident")
	var old: Dictionary = _active.duplicate(true)
	_active.clear()
	var event: Dictionary = _record_event(tick, "incident_completed", {"opportunity_id": opportunity_id, "pilot_id": old.get("pilot_id", ""), "outcome": outcome, "episode_family": old.get("episode_family", ""), "crash_prone": old.get("crash_prone", false)})
	return {"ok": true, "event": event}


func cancel_active(tick: int, opportunity_id: int, reason: String) -> Dictionary:
	if tick < 0 or tick < _last_advanced_tick:
		return _reject("invalid_or_reversed_tick")
	if reason.is_empty():
		return _reject("invalid_cancellation_reason")
	if _rate_name != RATE_OFF and _next_deadline_tick >= 0 and _next_deadline_tick <= tick:
		return _reject("opportunity_deadline_missed")
	_last_advanced_tick = tick
	_expire_active_episode(tick)
	if tick < int(_active.get("tick", 0)) or _active.is_empty() or opportunity_id != int(_active.get("opportunity_id", -1)):
		return _reject("stale_incident")
	var old: Dictionary = _active.duplicate(true)
	_active.clear()
	var event: Dictionary = _record_event(tick, "incident_cancelled", {"opportunity_id": opportunity_id, "pilot_id": old.get("pilot_id", ""), "episode_family": old.get("episode_family", ""), "crash_prone": old.get("crash_prone", false), "reason": reason})
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
		"max_events": _max_events,
		"max_episode_duration_ticks": _max_episode_duration_ticks
	}


func restore_state(candidate: Dictionary) -> Dictionary:
	if candidate.size() != snapshot_state().size():
		return _reject("invalid_state_fields")
	for key: String in snapshot_state():
		if not candidate.has(key):
			return _reject("invalid_state_fields")
	if String(candidate.get("version", "")) != STATE_VERSION or String(candidate.get("rng_algorithm", "")) != RNG_ALGORITHM_ID:
		return _reject("state_or_rng_version_mismatch")
	var integer_fields: Array[String] = ["seed", "time_rng_state", "pilot_rng_state", "severity_rng_state", "start_tick", "grace_until_tick", "last_advanced_tick", "next_deadline_tick", "last_fleet_start_tick", "opportunity_count", "eligible_start_count", "crash_prone_start_count", "event_sequence", "max_events", "max_episode_duration_ticks"]
	for field: String in integer_fields:
		if not candidate.has(field) or typeof(candidate[field]) != TYPE_INT:
			return _reject("invalid_integer_state_field")
	var seed: int = candidate["seed"]
	var start_tick: int = candidate["start_tick"]
	var grace_until_tick: int = candidate["grace_until_tick"]
	var last_advanced_tick: int = candidate["last_advanced_tick"]
	var next_deadline_tick: int = candidate["next_deadline_tick"]
	var last_fleet_start_tick: int = candidate["last_fleet_start_tick"]
	var opportunity_count: int = candidate["opportunity_count"]
	var eligible_start_count: int = candidate["eligible_start_count"]
	var crash_prone_start_count: int = candidate["crash_prone_start_count"]
	var event_sequence: int = candidate["event_sequence"]
	var max_events: int = candidate["max_events"]
	var max_episode_duration_ticks: int = candidate["max_episode_duration_ticks"]
	if seed < 1 or seed > 2147483646 or start_tick < 0 or grace_until_tick != start_tick + FIRST_INCIDENT_GRACE_TICKS:
		return _reject("invalid_seed_or_start_clock")
	if last_advanced_tick < -1 or last_fleet_start_tick < -1 or opportunity_count < 0 or eligible_start_count < 0 or crash_prone_start_count < 0 or event_sequence < 0:
		return _reject("negative_scheduler_counter")
	if eligible_start_count > opportunity_count or crash_prone_start_count > floori(float(eligible_start_count) * MAX_CRASH_PRONE_FRACTION):
		return _reject("incident_counter_invariant_broken")
	if max_events <= 0 or max_events > HARD_MAX_EVENTS or max_episode_duration_ticks <= 0 or max_episode_duration_ticks > HARD_MAX_EPISODE_DURATION_TICKS:
		return _reject("state_bound_exceeded")
	var rate_name: String = String(candidate.get("rate", ""))
	var raw_active: Variant = candidate.get("active", null)
	var raw_cooldowns: Variant = candidate.get("last_pilot_start_tick", null)
	var raw_events: Variant = candidate.get("events", null)
	if not VALID_RATES.has(rate_name) or not raw_active is Dictionary or not raw_cooldowns is Dictionary or not raw_events is Array or typeof(candidate.get("allow_crash_prone", null)) != TYPE_BOOL:
		return _reject("invalid_state_shape")
	if max_events <= 0 or raw_events.size() > max_events:
		return _reject("state_bound_exceeded")
	if raw_cooldowns.size() > HARD_MAX_TRACKED_PILOTS:
		return _reject("state_hard_bound_exceeded")
	if rate_name == RATE_OFF and next_deadline_tick != -1:
		return _reject("off_state_has_deadline")
	if rate_name != RATE_OFF and next_deadline_tick < 0:
		return _reject("enabled_state_missing_deadline")
	if rate_name != RATE_OFF and (next_deadline_tick <= last_advanced_tick or next_deadline_tick < grace_until_tick):
		return _reject("enabled_state_deadline_not_in_future")
	var rate_per_minute: Variant = candidate.get("rate_per_minute", null)
	if not _finite_number(rate_per_minute) or not is_equal_approx(float(rate_per_minute), _rate_for_name(rate_name)):
		return _reject("rate_value_mismatch")
	if (eligible_start_count == 0) != (last_fleet_start_tick == -1) or last_fleet_start_tick > last_advanced_tick:
		return _reject("fleet_start_clock_mismatch")
	if not _valid_active_snapshot(raw_active, seed, start_tick, last_advanced_tick, opportunity_count, eligible_start_count, crash_prone_start_count, max_episode_duration_ticks):
		return _reject("malformed_active_incident")
	for pilot_id: Variant in raw_cooldowns.keys():
		var pilot_tick: Variant = raw_cooldowns[pilot_id]
		if not pilot_id is String or String(pilot_id).is_empty() or typeof(pilot_tick) != TYPE_INT or int(pilot_tick) < 0 or int(pilot_tick) > last_fleet_start_tick:
			return _reject("malformed_pilot_cooldown")
	var restored_events: Array[Dictionary] = []
	var prior_sequence: int = -1
	for event: Variant in raw_events:
		if not _valid_event_snapshot(event, event_sequence, prior_sequence, opportunity_count, max_episode_duration_ticks):
			return _reject("malformed_event")
		restored_events.append(event.duplicate(true))
		prior_sequence = int(event["sequence"])
	_seed = seed
	_time_rng.seed = _derive_stream_seed(_seed, 17)
	_pilot_rng.seed = _derive_stream_seed(_seed, 31)
	_severity_rng.seed = _derive_stream_seed(_seed, 47)
	# Godot's RandomNumberGenerator exposes its unsigned internal state as a
	# signed 64-bit int, so negative TYPE_INT values are valid and preserved.
	_time_rng.state = candidate["time_rng_state"]
	_pilot_rng.state = candidate["pilot_rng_state"]
	_severity_rng.state = candidate["severity_rng_state"]
	_rate_name = rate_name
	_rate_per_minute = _rate_for_name(rate_name)
	_start_tick = start_tick
	_grace_until_tick = grace_until_tick
	_last_advanced_tick = last_advanced_tick
	_next_deadline_tick = next_deadline_tick
	_last_fleet_start_tick = last_fleet_start_tick
	_last_pilot_start_tick = raw_cooldowns.duplicate(true)
	_active = raw_active.duplicate(true)
	_allow_crash_prone = candidate["allow_crash_prone"]
	_opportunity_count = opportunity_count
	_eligible_start_count = eligible_start_count
	_crash_prone_start_count = crash_prone_start_count
	_event_sequence = event_sequence
	_events = restored_events
	_max_events = max_events
	_max_episode_duration_ticks = max_episode_duration_ticks
	return {"ok": true}


func _valid_roster_snapshot(roster: Array) -> bool:
	if roster.size() > HARD_MAX_TRACKED_PILOTS:
		return false
	var pilot_ids := {}
	var owner_generations := {}
	for row: Variant in roster:
		if not row is Dictionary or typeof(row.get("pilot_id")) != TYPE_STRING or String(row.pilot_id).is_empty() \
				or typeof(row.get("owner_id")) != TYPE_INT or row.owner_id < 0 \
				or typeof(row.get("generation")) != TYPE_INT or row.generation < 0 \
				or typeof(row.get("eligible")) != TYPE_BOOL \
				or typeof(row.get("crash_prone_eligible", false)) != TYPE_BOOL:
			return false
		var owner_key := "%d:%d" % [row.owner_id, row.generation]
		if pilot_ids.has(row.pilot_id) or owner_generations.has(owner_key):
			return false
		pilot_ids[row.pilot_id] = true
		owner_generations[owner_key] = true
		var families: Variant = row.get("episode_families", [])
		if not families is Array or families.size() > HARD_MAX_FAMILIES_PER_PILOT:
			return false
	return true


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
	var saw_family_ineligible: bool = false
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
		var families: Array[Dictionary] = _normalized_episode_families(candidate)
		if families.is_empty():
			saw_family_ineligible = true
			continue
		var normal_families: Array[Dictionary] = _families_with_crash_class(families, false)
		if normal_families.is_empty():
			saw_family_ineligible = true
			continue
		var prior_tick: int = int(_last_pilot_start_tick.get(pilot_id, -1))
		if prior_tick >= 0 and tick - prior_tick < MIN_PILOT_INTERVAL_TICKS:
			saw_pilot_cooldown = true
			continue
		candidates.append(candidate.duplicate(true))
	if candidates.is_empty():
		if saw_eligible and saw_pilot_cooldown:
			cancel_reason = "pilot_cooldown"
		elif saw_eligible and saw_family_ineligible:
			cancel_reason = "no_eligible_episode_family"
		else:
			cancel_reason = "no_eligible_pilot"
		emitted.append(_record_event(tick, "incident_cancelled", {"opportunity_id": opportunity_id, "reason": cancel_reason}))
		return
	candidates.sort_custom(_pilot_candidate_less)
	var pilot_index: int = _pilot_rng.randi_range(0, candidates.size() - 1)
	var selected: Dictionary = candidates[pilot_index]
	var selected_pilot_id: String = String(selected["pilot_id"])
	if not _last_pilot_start_tick.has(selected_pilot_id) and _last_pilot_start_tick.size() >= HARD_MAX_TRACKED_PILOTS:
		emitted.append(_record_event(tick, "incident_cancelled", {"opportunity_id": opportunity_id, "reason": "pilot_history_capacity"}))
		return
	_eligible_start_count += 1
	var crash_prone_episode: bool = false
	var current_quota: int = floori(float(_eligible_start_count) * MAX_CRASH_PRONE_FRACTION)
	var families: Array[Dictionary] = _normalized_episode_families(selected)
	var normal_families: Array[Dictionary] = _families_with_crash_class(families, false)
	var crash_families: Array[Dictionary] = _families_with_crash_class(families, true)
	if _allow_crash_prone and typeof(selected.get("crash_prone_eligible", false)) == TYPE_BOOL and bool(selected.get("crash_prone_eligible", false)) and not crash_families.is_empty() and _crash_prone_start_count < current_quota:
		crash_prone_episode = _severity_rng.randf() < MAX_CRASH_PRONE_FRACTION
	var selected_families: Array[Dictionary] = crash_families if crash_prone_episode else normal_families
	var family_index: int = 0
	if selected_families.size() > 1:
		family_index = _pilot_rng.randi_range(0, selected_families.size() - 1)
	var episode_family: String = String(selected_families[family_index]["family_id"])
	if crash_prone_episode:
		_crash_prone_start_count += 1
	var active: Dictionary = {
		"opportunity_id": opportunity_id,
		"tick": tick,
		"pilot_id": String(selected["pilot_id"]),
		"owner_id": int(selected["owner_id"]),
		"generation": int(selected["generation"]),
		"episode_family": episode_family,
		"crash_prone": crash_prone_episode,
		"deadline_tick": tick + _max_episode_duration_ticks,
		"seed": _seed
	}
	_active = active
	_last_fleet_start_tick = tick
	_last_pilot_start_tick[String(selected["pilot_id"])] = tick
	emitted.append(_record_event(tick, "incident_started", {"opportunity_id": opportunity_id, "pilot_id": active["pilot_id"], "owner_id": active["owner_id"], "generation": active["generation"], "episode_family": episode_family, "crash_prone": crash_prone_episode, "deadline_tick": active["deadline_tick"]}))


func _schedule_after(origin_tick: int) -> void:
	if _rate_per_minute <= 0.0:
		_next_deadline_tick = -1
		return
	var uniform_complement: float = maxf(0.000000000001, 1.0 - _time_rng.randf())
	var waiting_minutes: float = -log(uniform_complement) / _rate_per_minute
	var wait_ticks: int = maxi(1, ceili(waiting_minutes * 60.0 * float(TICK_RATE_HZ)))
	_next_deadline_tick = origin_tick + wait_ticks


func _expire_active_episode(tick: int) -> Dictionary:
	if _active.is_empty() or tick < int(_active.get("deadline_tick", tick)):
		return {}
	var expired: Dictionary = _active.duplicate(true)
	_active.clear()
	return _record_event(int(expired["deadline_tick"]), "incident_cancelled", {
		"opportunity_id": expired.get("opportunity_id", -1),
		"pilot_id": expired.get("pilot_id", ""),
		"episode_family": expired.get("episode_family", ""),
		"crash_prone": expired.get("crash_prone", false),
		"reason": "episode_timeout",
		"recovery_required": true,
		"deadline_tick": expired.get("deadline_tick", -1)
	})


func _normalized_episode_families(candidate: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw_families: Variant = candidate.get("episode_families", null)
	if not raw_families is Array:
		return result
	var by_family_id: Dictionary = {}
	for raw_family: Variant in raw_families:
		if not raw_family is Dictionary or not raw_family.has("family_id") or not raw_family.has("crash_prone"):
			return []
		var family_id: Variant = raw_family["family_id"]
		var crash_prone: Variant = raw_family["crash_prone"]
		if typeof(family_id) != TYPE_STRING or String(family_id).is_empty() or typeof(crash_prone) != TYPE_BOOL:
			return []
		if by_family_id.has(String(family_id)) and bool(by_family_id[String(family_id)]) != bool(crash_prone):
			return []
		by_family_id[String(family_id)] = bool(crash_prone)
	var family_ids: Array = by_family_id.keys()
	family_ids.sort()
	for family_id: Variant in family_ids:
		result.append({"family_id": String(family_id), "crash_prone": bool(by_family_id[family_id])})
	return result


func _families_with_crash_class(families: Array[Dictionary], crash_prone: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for family: Dictionary in families:
		if bool(family.get("crash_prone", false)) == crash_prone:
			result.append(family)
	return result


func _valid_active_snapshot(raw_active: Dictionary, seed: int, start_tick: int, last_advanced_tick: int, opportunity_count: int, eligible_start_count: int, crash_prone_start_count: int, max_episode_duration_ticks: int) -> bool:
	if raw_active.is_empty():
		return true
	var integer_fields: Array[String] = ["opportunity_id", "tick", "owner_id", "generation", "deadline_tick", "seed"]
	for field: String in integer_fields:
		if not raw_active.has(field) or typeof(raw_active[field]) != TYPE_INT:
			return false
	if typeof(raw_active.get("pilot_id", null)) != TYPE_STRING or String(raw_active["pilot_id"]).is_empty():
		return false
	if typeof(raw_active.get("episode_family", null)) != TYPE_STRING or String(raw_active["episode_family"]).is_empty() or typeof(raw_active.get("crash_prone", null)) != TYPE_BOOL:
		return false
	var opportunity_id: int = raw_active["opportunity_id"]
	var tick: int = raw_active["tick"]
	var deadline_tick: int = raw_active["deadline_tick"]
	var crash_prone: bool = raw_active["crash_prone"]
	return opportunity_id > 0 and opportunity_id <= opportunity_count and tick >= start_tick and tick <= last_advanced_tick and raw_active["owner_id"] >= 0 and raw_active["generation"] >= 0 and raw_active["seed"] == seed and deadline_tick > tick and deadline_tick - tick == max_episode_duration_ticks and deadline_tick > last_advanced_tick and eligible_start_count > 0 and (not crash_prone or crash_prone_start_count > 0)


func _valid_event_snapshot(event: Variant, maximum_sequence: int, prior_sequence: int, maximum_opportunity_id: int, max_episode_duration_ticks: int) -> bool:
	if not event is Dictionary or not event.has("sequence") or not event.has("tick") or not event.has("type") or not event.has("payload"):
		return false
	if typeof(event["sequence"]) != TYPE_INT or typeof(event["tick"]) != TYPE_INT or typeof(event["type"]) != TYPE_STRING or not event["payload"] is Dictionary:
		return false
	if int(event["sequence"]) <= prior_sequence or int(event["sequence"]) > maximum_sequence or int(event["tick"]) < 0:
		return false
	var payload: Dictionary = event["payload"]
	match String(event["type"]):
		"incident_rate_changed":
			if typeof(payload.get("rate", null)) != TYPE_STRING or not VALID_RATES.has(String(payload["rate"])):
				return false
			if not _finite_number(payload.get("opportunities_per_minute", null)) or not is_equal_approx(float(payload["opportunities_per_minute"]), _rate_for_name(String(payload["rate"]))):
				return false
			if typeof(payload.get("next_deadline_tick", null)) != TYPE_INT:
				return false
			var deadline: int = payload["next_deadline_tick"]
			if (String(payload["rate"]) == RATE_OFF) != (deadline == -1) or deadline < -1:
				return false
			if deadline >= 0 and deadline <= int(event["tick"]):
				return false
		"crash_prone_policy_changed":
			if typeof(payload.get("allowed", null)) != TYPE_BOOL:
				return false
		"incident_opportunity":
			if not _valid_opportunity_event_payload(payload, maximum_opportunity_id):
				return false
			if typeof(payload.get("rate", null)) != TYPE_STRING or not VALID_RATES.has(String(payload["rate"])) or String(payload["rate"]) == RATE_OFF:
				return false
		"incident_started":
			if not _valid_opportunity_event_payload(payload, maximum_opportunity_id):
				return false
			if typeof(payload.get("pilot_id", null)) != TYPE_STRING or String(payload["pilot_id"]).is_empty():
				return false
			if not _nonnegative_int(payload.get("owner_id", null)) or not _nonnegative_int(payload.get("generation", null)):
				return false
			if not _valid_family_event_fields(payload) or typeof(payload.get("deadline_tick", null)) != TYPE_INT:
				return false
			if int(payload["deadline_tick"]) <= int(event["tick"]) or int(payload["deadline_tick"]) - int(event["tick"]) != max_episode_duration_ticks:
				return false
		"incident_completed":
			if not _valid_opportunity_event_payload(payload, maximum_opportunity_id):
				return false
			if typeof(payload.get("pilot_id", null)) != TYPE_STRING or String(payload["pilot_id"]).is_empty() or typeof(payload.get("outcome", null)) != TYPE_STRING or String(payload["outcome"]).is_empty():
				return false
			if not _valid_family_event_fields(payload):
				return false
		"incident_cancelled":
			if not _valid_opportunity_event_payload(payload, maximum_opportunity_id) or typeof(payload.get("reason", null)) != TYPE_STRING or String(payload["reason"]).is_empty():
				return false
			var has_classification: bool = payload.has("pilot_id") or payload.has("episode_family") or payload.has("crash_prone")
			if has_classification:
				if typeof(payload.get("pilot_id", null)) != TYPE_STRING or String(payload["pilot_id"]).is_empty() or not _valid_family_event_fields(payload):
					return false
			if payload.has("recovery_required"):
				if String(payload["reason"]) != "episode_timeout" or typeof(payload["recovery_required"]) != TYPE_BOOL or not bool(payload["recovery_required"]) or typeof(payload.get("deadline_tick", null)) != TYPE_INT or int(payload["deadline_tick"]) != int(event["tick"]):
					return false
		_:
			return false
	return true


func _valid_opportunity_event_payload(payload: Dictionary, maximum_opportunity_id: int) -> bool:
	return _nonnegative_int(payload.get("opportunity_id", null)) and int(payload["opportunity_id"]) > 0 and int(payload["opportunity_id"]) <= maximum_opportunity_id


func _valid_family_event_fields(payload: Dictionary) -> bool:
	return typeof(payload.get("episode_family", null)) == TYPE_STRING and not String(payload["episode_family"]).is_empty() and typeof(payload.get("crash_prone", null)) == TYPE_BOOL


func _nonnegative_int(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= 0


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


func _finite_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))


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

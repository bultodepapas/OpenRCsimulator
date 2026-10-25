## Pure accepted-tick flight/event classifier. It owns no nodes, files or wall-clock state.
extends RefCounted

const Rules := preload("res://statistics/rules.gd")
const SNAPSHOT_VERSION := 1
const PHASES := ["ground_ready", "takeoff_pending", "airborne", "contact_pending", "terminal"]

var flight: Dictionary = {}

var _profile: Dictionary = {}
var _thresholds: Dictionary = {}
var _air_start_requested := false
var _phase := "ground_ready"
var _last_tick := 0
var _clock_s := 0.0
var _candidate_air_s := 0.0
var _candidate_clearance_s := 0.0
var _episode_open := false
var _episode_tick := -1
var _stable_support_s := 0.0
var _qualified_support_seen := false
var _stop_s := 0.0
var _stop_evidence_s := 0.0
var _stop_rejected_s := 0.0
var _rearm_clearance_s := 0.0
var _incident_latched := false
var _crash_emitted := false
var _continuity_lost := false
var _speed_window: Array[Dictionary] = []
var _speed_head := 0
var _speed_window_s := 0.0
var _pending_speed: Array[Dictionary] = []
var _pending_speed_head := 0
var _previous_speed: Dictionary = {}
var _speed_reject_counts: Dictionary = {}


func configure(profile: Dictionary, air_start: bool = false) -> void:
	_profile = profile.duplicate(true)
	_thresholds = Rules.resolve(_profile)
	_air_start_requested = air_start
	_phase = "takeoff_pending" if air_start else "ground_ready"
	_last_tick = int(_profile.get("initial_tick", 0))
	if _last_tick < 0:
		_last_tick = 0
	_clock_s = 0.0
	_candidate_air_s = 0.0
	_candidate_clearance_s = 0.0
	_episode_open = false
	_episode_tick = -1
	_stable_support_s = 0.0
	_qualified_support_seen = false
	_stop_s = 0.0
	_stop_evidence_s = 0.0
	_stop_rejected_s = 0.0
	_rearm_clearance_s = 0.0
	_incident_latched = bool(_profile.get("incident_latched", false))
	_crash_emitted = false
	_continuity_lost = false
	_clear_speed_state()
	_speed_reject_counts.clear()
	flight = {}


func observe(sample: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var tick_value: Variant = sample.get("tick", -1)
	var tick := int(tick_value) if typeof(tick_value) in [TYPE_INT, TYPE_FLOAT] else -1
	if bool(sample.get("incident", false)):
		_incident_latched = true
	var terminal := bool(sample.get("terminal", false))

	if tick == _last_tick:
		if terminal:
			_handle_terminal(sample, tick, events)
		return events
	if tick < 0 or tick < _last_tick or tick > _last_tick + 1:
		_mark_discontinuity()
		if tick > _last_tick:
			_last_tick = tick
		if terminal:
			_handle_terminal(sample, tick, events)
		return events
	_last_tick = tick

	var dt_value: Variant = sample.get("dt", -1.0)
	var dt := float(dt_value) if typeof(dt_value) in [TYPE_INT, TYPE_FLOAT] else -1.0
	var sample_valid := bool(sample.get("valid", false)) and is_finite(dt) \
		and dt > 0.0 and dt <= float(_thresholds.max_sample_dt_s)
	if not sample_valid:
		_mark_discontinuity()
		if terminal:
			_handle_terminal(sample, tick, events)
		return events
	if _continuity_lost:
		if terminal:
			_handle_terminal(sample, tick, events)
		return events

	_clock_s += dt
	if not flight.is_empty() and _is_active_flight() and not _is_physically_supported(sample):
		flight.airborne_seconds = float(flight.airborne_seconds) + dt
	if terminal:
		_handle_terminal(sample, tick, events)
		return events

	if _phase == "ground_ready" or _phase == "takeoff_pending":
		_process_takeoff(sample, dt, tick, events)
	elif _phase == "airborne":
		_process_airborne(sample, tick)
	elif _phase == "contact_pending":
		_process_contact(sample, dt, tick, events)
	if _phase == "airborne" and _is_active_flight():
		_collect_speed(sample, dt, tick)
	else:
		_clear_speed_state()
	return events


func end(reason: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not flight.is_empty() and _is_active_flight():
		if _episode_open:
			_resolve_episode("unknown", "ended_before_resolution", _last_tick,
				"ended_before_resolution", events)
		var outcome := reason if reason in ["restarted", "abandoned", "interrupted"] else "interrupted"
		_close_flight(outcome, _last_tick, events)
	_candidate_air_s = 0.0
	_candidate_clearance_s = 0.0
	_clear_episode()
	_clear_speed_state()
	_phase = "terminal"
	return events


func snapshot() -> Dictionary:
	return {
		"version": SNAPSHOT_VERSION,
		"profile": _json_safe(_profile),
		"air_start_requested": _air_start_requested,
		"phase": _phase,
		"last_tick": _last_tick,
		"clock_s": _clock_s,
		"candidate_air_s": _candidate_air_s,
		"candidate_clearance_s": _candidate_clearance_s,
		"episode_open": _episode_open,
		"episode_tick": _episode_tick,
		"stable_support_s": _stable_support_s,
		"qualified_support_seen": _qualified_support_seen,
		"stop_s": _stop_s,
		"stop_evidence_s": _stop_evidence_s,
		"stop_rejected_s": _stop_rejected_s,
		"rearm_clearance_s": _rearm_clearance_s,
		"incident_latched": _incident_latched,
		"crash_emitted": _crash_emitted,
		"continuity_lost": _continuity_lost,
		"flight": _json_safe(flight),
		"speed_window": _json_safe(_effective_speed_window()),
		"speed_window_s": _speed_window_s,
		"pending_speed": _json_safe(_effective_pending_speed()),
		"previous_speed": _json_safe(_previous_speed),
		"speed_reject_counts": _json_safe(_speed_reject_counts),
	}


func restore(value: Dictionary) -> bool:
	if not _valid_snapshot(value):
		return false
	var copy: Dictionary = value.duplicate(true)
	_profile = copy.profile
	_thresholds = Rules.resolve(_profile)
	_air_start_requested = bool(copy.air_start_requested)
	_phase = str(copy.phase)
	_last_tick = int(copy.last_tick)
	_clock_s = float(copy.clock_s)
	_candidate_air_s = float(copy.candidate_air_s)
	_candidate_clearance_s = float(copy.candidate_clearance_s)
	_episode_open = bool(copy.episode_open)
	_episode_tick = int(copy.episode_tick)
	_stable_support_s = float(copy.stable_support_s)
	_qualified_support_seen = bool(copy.qualified_support_seen)
	_stop_s = float(copy.stop_s)
	_stop_evidence_s = float(copy.stop_evidence_s)
	_stop_rejected_s = float(copy.stop_rejected_s)
	_rearm_clearance_s = float(copy.rearm_clearance_s)
	_incident_latched = bool(copy.incident_latched)
	_crash_emitted = bool(copy.crash_emitted)
	_continuity_lost = bool(copy.continuity_lost)
	flight = copy.flight
	_speed_window = []
	_speed_window_s = 0.0
	for entry_value: Variant in copy.speed_window:
		var entry: Dictionary = entry_value.duplicate(true)
		entry.tick = int(entry.tick)
		_speed_window.append(entry)
		_speed_window_s += float(entry.dt)
	_speed_head = 0
	_pending_speed = []
	for entry_value: Variant in copy.pending_speed:
		var entry: Dictionary = entry_value.duplicate(true)
		entry.tick = int(entry.tick)
		_pending_speed.append(entry)
	_pending_speed_head = 0
	_previous_speed = copy.previous_speed
	_speed_reject_counts = copy.speed_reject_counts
	for key: String in ["full_stops", "touch_and_go", "failed_landings", "unknown_landings"]:
		if not flight.is_empty():
			flight[key] = int(flight[key])
	for key: String in _speed_reject_counts:
		_speed_reject_counts[key] = int(_speed_reject_counts[key])
	if not _previous_speed.is_empty():
		_previous_speed.tick = int(_previous_speed.tick)
	return true


func _process_takeoff(sample: Dictionary, dt: float, tick: int, events: Array[Dictionary]) -> void:
	if _is_physically_supported(sample):
		_candidate_air_s = 0.0
		_candidate_clearance_s = 0.0
		_phase = "takeoff_pending" if _air_start_requested else "ground_ready"
		return
	_candidate_air_s += dt
	if bool(sample.get("clearance_ok", false)):
		_candidate_clearance_s += dt
	else:
		_candidate_clearance_s = 0.0
	if _candidate_clearance_s + 1e-12 < float(_thresholds.liftoff_clearance_s):
		_phase = "takeoff_pending"
		return
	var start_kind := "air_start" if _air_start_requested else "takeoff"
	_start_flight(start_kind, _candidate_air_s, tick, events)
	_candidate_air_s = 0.0
	_candidate_clearance_s = 0.0
	_air_start_requested = false
	_phase = "airborne"


func _process_airborne(sample: Dictionary, tick: int) -> void:
	if _is_physically_supported(sample) or bool(sample.get("intended_support", false)):
		_open_episode(tick)
		_phase = "contact_pending"


func _process_contact(sample: Dictionary, dt: float, tick: int, events: Array[Dictionary]) -> void:
	var supported := _is_physically_supported(sample)
	var intended := bool(sample.get("intended_support", false)) \
		and bool(_profile.get("landing_available", false))
	var controlled := bool(sample.get("controlled", false))
	var stable_before := _stable_support_s + 1e-12 >= float(_thresholds.stable_support_s)
	if supported and intended and controlled:
		_stable_support_s += dt
		if _stable_support_s + 1e-12 >= float(_thresholds.stable_support_s) \
			and not _incident_latched:
			_qualified_support_seen = true
	else:
		_stable_support_s = 0.0
		_stop_s = 0.0

	var stop_geometry := supported and bool(sample.get("stop_support", false))
	var slow := _finite_nonnegative(sample.get("ground_speed_3d", -1.0)) \
		and float(sample.get("ground_speed_3d", -1.0)) <= float(_thresholds.full_stop_speed_mps)
	var quiet := _finite_nonnegative(sample.get("angular_speed", -1.0)) \
		and float(sample.get("angular_speed", -1.0)) <= float(_thresholds.full_stop_angular_speed_rad_s)
	if stop_geometry and slow and quiet:
		_stop_evidence_s += dt
		if not controlled:
			_stop_rejected_s += dt
		else:
			_stop_rejected_s = 0.0
	else:
		_stop_evidence_s = 0.0
		_stop_rejected_s = 0.0

	if stable_before and supported and intended and controlled and stop_geometry and slow and quiet:
		_stop_s += dt
	else:
		_stop_s = 0.0

	if _stop_s + 1e-12 >= float(_thresholds.full_stop_s):
		_finish_full_stop(tick, events)
		return
	if _stop_rejected_s + 1e-12 >= float(_thresholds.full_stop_s):
		_resolve_full_stop_failure(tick, "control_envelope", events)
		return

	if not supported and bool(sample.get("clearance_ok", false)):
		_rearm_clearance_s += dt
	else:
		_rearm_clearance_s = 0.0
	if _rearm_clearance_s + 1e-12 >= float(_thresholds.rearm_clearance_s):
		var clean_episode := _qualified_support_seen and not _incident_latched \
			and bool(_profile.get("landing_available", false))
		if clean_episode:
			_resolve_episode("success", "touch_and_go", tick, "", events)
			_phase = "airborne"
		else:
			var landing_outcome := "failed"
			var reason := "touchdown_not_confirmed"
			if not bool(_profile.get("landing_available", false)) or _continuity_lost:
				landing_outcome = "unknown"
				reason = "classification_unavailable"
			elif _incident_latched:
				reason = "disqualifying_incident"
			_resolve_episode(landing_outcome, "bounce_departure", tick, reason, events)
			_phase = "airborne"
		_stable_support_s = 0.0
		_stop_s = 0.0
		_stop_evidence_s = 0.0
		_stop_rejected_s = 0.0
		_rearm_clearance_s = 0.0


func _finish_full_stop(tick: int, events: Array[Dictionary]) -> void:
	if not bool(_profile.get("landing_available", false)) or _continuity_lost:
		_resolve_episode("unknown", "full_stop", tick, "classification_unavailable", events)
		_close_flight("interrupted", tick, events)
	elif _incident_latched or not _qualified_support_seen:
		var reason := "disqualifying_incident" if _incident_latched else "support_not_controlled"
		_resolve_episode("failed", "full_stop", tick, reason, events)
		_close_flight("damaged_stop" if _incident_latched else "failed_stop", tick, events)
	else:
		_resolve_episode("success", "full_stop", tick, "", events)
		_close_flight("completed", tick, events)
	_phase = "ground_ready"
	_clear_episode()
	_clear_speed_state()


func _resolve_full_stop_failure(tick: int, reason: String, events: Array[Dictionary]) -> void:
	if not bool(_profile.get("landing_available", false)) or _continuity_lost:
		_resolve_episode("unknown", "full_stop", tick, "classification_unavailable", events)
		_close_flight("interrupted", tick, events)
	else:
		var outcome := "failed"
		var close_reason := "failed_stop"
		if _incident_latched:
			reason = "disqualifying_incident"
			close_reason = "damaged_stop"
		_resolve_episode(outcome, "full_stop", tick, reason, events)
		_close_flight(close_reason, tick, events)
	_phase = "ground_ready"
	_clear_episode()
	_clear_speed_state()


func _handle_terminal(sample: Dictionary, tick: int, events: Array[Dictionary]) -> void:
	if _crash_emitted:
		return
	_crash_emitted = true
	_incident_latched = true
	var ground := bool(sample.get("ground_contact", false)) \
		or bool(sample.get("supported", false))
	events.append({"type": "crash", "ground": ground, "tick": tick})
	if _is_active_flight():
		if not _episode_open and _phase == "airborne" and ground:
			_open_episode(tick)
		if _episode_open:
			_resolve_episode("failed", "terminal_contact", tick, "terminal_crash", events)
		_close_flight("crashed", tick, events)
	_candidate_air_s = 0.0
	_candidate_clearance_s = 0.0
	_clear_episode()
	_clear_speed_state()
	_phase = "terminal"


func _start_flight(start_kind: String, backfill_s: float, tick: int, events: Array[Dictionary]) -> void:
	flight = {
		"airborne_seconds": maxf(0.0, backfill_s),
		"outcome": "active",
		"start_kind": start_kind,
		"full_stops": 0,
		"touch_and_go": 0,
		"failed_landings": 0,
		"unknown_landings": 0,
		"max_tas_mps": -1.0,
		"max_groundspeed_mps": -1.0,
		"complete_observation": not _continuity_lost,
	}
	_speed_reject_counts.clear()
	events.append({"type": "started", "start_kind": start_kind,
		"tick": tick, "flight": flight.duplicate(true)})


func _open_episode(tick: int) -> void:
	if _episode_open:
		return
	_episode_open = true
	_episode_tick = tick
	_stable_support_s = 0.0
	_qualified_support_seen = false
	_stop_s = 0.0
	_stop_evidence_s = 0.0
	_stop_rejected_s = 0.0
	_rearm_clearance_s = 0.0
	_clear_speed_state()


func _resolve_episode(outcome: String, kind: String, tick: int, reason: String,
		events: Array[Dictionary]) -> void:
	if not _episode_open:
		return
	if not flight.is_empty():
		match outcome:
			"success":
				if kind == "full_stop":
					flight.full_stops = int(flight.full_stops) + 1
				else:
					flight.touch_and_go = int(flight.touch_and_go) + 1
			"failed":
				flight.failed_landings = int(flight.failed_landings) + 1
			_:
				flight.unknown_landings = int(flight.unknown_landings) + 1
		events.append({
			"type": "landing",
			"kind": kind,
			"outcome": outcome,
			"reason": reason,
			"tick": tick,
			"first_contact_tick": _episode_tick,
			"flight": flight.duplicate(true),
		})
	_clear_episode()


func _close_flight(outcome: String, tick: int, events: Array[Dictionary]) -> void:
	if flight.is_empty():
		return
	flight.outcome = outcome
	var closed_flight: Dictionary = flight.duplicate(true)
	events.append({"type": "closed", "outcome": outcome,
		"tick": tick, "flight": closed_flight})
	flight = {}


func _clear_episode() -> void:
	_episode_open = false
	_episode_tick = -1
	_stable_support_s = 0.0
	_qualified_support_seen = false
	_stop_s = 0.0
	_stop_evidence_s = 0.0
	_stop_rejected_s = 0.0
	_rearm_clearance_s = 0.0


func _mark_discontinuity() -> void:
	_continuity_lost = true
	if not flight.is_empty():
		flight.complete_observation = false
	_candidate_air_s = 0.0
	_candidate_clearance_s = 0.0
	_stable_support_s = 0.0
	_stop_s = 0.0
	_stop_evidence_s = 0.0
	_stop_rejected_s = 0.0
	_rearm_clearance_s = 0.0
	_clear_speed_state()


func _collect_speed(sample: Dictionary, dt: float, tick: int) -> void:
	if _clock_s <= float(_thresholds.speed_exclusion_after_activation_s) + 1e-12:
		_clear_speed_state()
		return
	if bool(sample.get("incident", false)) or bool(sample.get("ground_contact", false)):
		_clear_speed_state()
		return
	var tas := _finite_nonnegative_value(sample.get("tas", -1.0))
	var ground_speed := _finite_nonnegative_value(sample.get("groundspeed", -1.0))
	var position := _vector3(sample.get("position", []))
	var velocity := _vector3(sample.get("velocity_ned", []))
	if tas < 0.0 or ground_speed < 0.0 or position.is_empty() or velocity.is_empty():
		_record_speed_rejection("invalid_sample")
		_clear_speed_state()
		return
	var cap := float(_profile.get("speed_cap_mps", _thresholds.default_speed_cap_mps))
	if not is_finite(cap) or cap <= 0.0:
		cap = float(_thresholds.default_speed_cap_mps)
	if tas > cap or ground_speed > cap:
		_record_speed_rejection("speed_cap")
		_clear_speed_state()
		return
	if not _previous_speed.is_empty():
		var max_delta := float(_thresholds.speed_acceleration_limit_mps2) * dt + 1e-9
		if absf(tas - float(_previous_speed.tas)) > max_delta \
			or absf(ground_speed - float(_previous_speed.groundspeed)) > max_delta:
			_record_speed_rejection("acceleration")
			_clear_speed_state()
			return
		if _position_discontinuous(position, velocity, dt, ground_speed):
			_record_speed_rejection("position_discontinuity")
			_clear_speed_state()
			return
	_previous_speed = {"tick": tick, "tas": tas, "groundspeed": ground_speed,
		"position": position, "velocity": velocity}
	_speed_window.append({"tick": tick, "dt": dt, "tas": tas, "groundspeed": ground_speed})
	_speed_window_s += dt
	_trim_speed_window()
	if _speed_window_s + 1e-12 >= float(_thresholds.speed_window_s):
		_add_speed_candidate(tick)
	_commit_mature_speed_candidates()


func _position_discontinuous(position: Array, velocity: Array, dt: float, speed: float) -> bool:
	var old_position: Array = _previous_speed.position
	var old_velocity: Array = _previous_speed.velocity
	var error_sq := 0.0
	for i in 3:
		var predicted := 0.5 * (float(old_velocity[i]) + float(velocity[i])) * dt
		var actual := float(position[i]) - float(old_position[i])
		var difference := actual - predicted
		error_sq += difference * difference
	var tolerance := maxf(0.05, 0.1 * maxf(speed, float(_previous_speed.groundspeed)) * dt)
	return sqrt(error_sq) > tolerance


func _trim_speed_window() -> void:
	var window_s := float(_thresholds.speed_window_s)
	while _speed_window.size() - _speed_head > 1:
		var oldest: Dictionary = _speed_window[_speed_head]
		if _speed_window_s - float(oldest.dt) + 1e-12 < window_s:
			break
		_speed_window_s -= float(oldest.dt)
		_speed_head += 1
	var max_samples := int(_thresholds.max_speed_samples)
	while _speed_window.size() - _speed_head > max_samples:
		var oldest: Dictionary = _speed_window[_speed_head]
		_speed_window_s -= float(oldest.dt)
		_speed_head += 1
	if _speed_head > 32 and _speed_head * 2 > _speed_window.size():
		_speed_window = _speed_window.slice(_speed_head)
		_speed_head = 0


func _add_speed_candidate(tick: int) -> void:
	var tas_values: Array[float] = []
	var ground_values: Array[float] = []
	for i in range(_speed_head, _speed_window.size()):
		var entry: Dictionary = _speed_window[i]
		tas_values.append(float(entry.tas))
		ground_values.append(float(entry.groundspeed))
	var median_tas := _median(tas_values)
	var median_ground := _median(ground_values)
	var tas_stable := _all_near_median(tas_values, median_tas)
	var ground_stable := _all_near_median(ground_values, median_ground)
	if not tas_stable or not ground_stable:
		_record_speed_rejection("unsteady_window")
	_pending_speed.append({
		"tick": tick,
		"time_s": _clock_s,
		"tas": median_tas if tas_stable else -1.0,
		"groundspeed": median_ground if ground_stable else -1.0,
	})
	while _pending_speed.size() - _pending_speed_head > int(_thresholds.max_speed_samples):
		_pending_speed_head += 1
	_commit_mature_speed_candidates()


func _commit_mature_speed_candidates() -> void:
	var delay := float(_thresholds.speed_window_s)
	while _pending_speed_head < _pending_speed.size():
		var candidate: Dictionary = _pending_speed[_pending_speed_head]
		if _clock_s - float(candidate.time_s) + 1e-12 < delay:
			break
		if not flight.is_empty():
			var candidate_tas := float(candidate.tas)
			var candidate_ground := float(candidate.groundspeed)
			if candidate_tas >= 0.0:
				flight.max_tas_mps = maxf(float(flight.max_tas_mps), candidate_tas)
			if candidate_ground >= 0.0:
				flight.max_groundspeed_mps = maxf(float(flight.max_groundspeed_mps), candidate_ground)
		_pending_speed_head += 1
	if _pending_speed_head > 32 and _pending_speed_head * 2 > _pending_speed.size():
		_pending_speed = _pending_speed.slice(_pending_speed_head)
		_pending_speed_head = 0


func _all_near_median(values: Array[float], median: float) -> bool:
	var tolerance := maxf(float(_thresholds.speed_stability_absolute_mps),
		float(_thresholds.speed_stability_fraction) * median)
	for value: float in values:
		if absf(value - median) > tolerance:
			return false
	return not values.is_empty()


func _median(values: Array[float]) -> float:
	if values.is_empty():
		return -1.0
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	var middle := sorted.size() / 2
	if sorted.size() % 2 == 1:
		return sorted[middle]
	return 0.5 * (sorted[middle - 1] + sorted[middle])


func _record_speed_rejection(reason: String) -> void:
	_speed_reject_counts[reason] = int(_speed_reject_counts.get(reason, 0)) + 1


func _clear_speed_state() -> void:
	_speed_window.clear()
	_speed_head = 0
	_speed_window_s = 0.0
	_pending_speed.clear()
	_pending_speed_head = 0
	_previous_speed.clear()


func _effective_speed_window() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(_speed_head, _speed_window.size()):
		out.append(_speed_window[i].duplicate(true))
	return out


func _effective_pending_speed() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(_pending_speed_head, _pending_speed.size()):
		out.append(_pending_speed[i].duplicate(true))
	return out


func _is_active_flight() -> bool:
	return not flight.is_empty() and str(flight.get("outcome", "")) == "active"


func _is_physically_supported(sample: Dictionary) -> bool:
	return bool(sample.get("supported", false)) or bool(sample.get("ground_contact", false))


func _finite_nonnegative(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0.0


func _finite_nonnegative_value(value: Variant) -> float:
	return float(value) if _finite_nonnegative(value) else -1.0


func _vector3(value: Variant) -> Array:
	if typeof(value) not in [TYPE_ARRAY, TYPE_PACKED_FLOAT64_ARRAY] or value.size() != 3:
		return []
	var out: Array = []
	for item: Variant in value:
		if typeof(item) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(item)):
			return []
		out.append(float(item))
	return out


func _json_safe(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var out: Dictionary = {}
			for key: Variant in value:
				out[str(key)] = _json_safe(value[key])
			return out
		TYPE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			var out: Array = []
			for item: Variant in value:
				out.append(_json_safe(item))
			return out
		TYPE_FLOAT:
			return float(value) if is_finite(float(value)) else null
		_:
			return value


func _valid_snapshot(value: Dictionary) -> bool:
	if int(value.get("version", -1)) != SNAPSHOT_VERSION or not _json_only(value, 0):
		return false
	for key: String in ["profile", "flight", "speed_window", "pending_speed", "previous_speed", "speed_reject_counts"]:
		if not value.has(key):
			return false
	if typeof(value.profile) != TYPE_DICTIONARY or typeof(value.flight) != TYPE_DICTIONARY \
		or typeof(value.speed_window) != TYPE_ARRAY or typeof(value.pending_speed) != TYPE_ARRAY \
		or typeof(value.previous_speed) != TYPE_DICTIONARY or typeof(value.speed_reject_counts) != TYPE_DICTIONARY:
		return false
	if typeof(value.phase) != TYPE_STRING or str(value.phase) not in PHASES:
		return false
	for key: String in ["air_start_requested", "episode_open", "qualified_support_seen", "incident_latched", "crash_emitted", "continuity_lost"]:
		if typeof(value.get(key)) != TYPE_BOOL:
			return false
	for key: String in ["last_tick", "episode_tick"]:
		if not _finite_integer(value.get(key)):
			return false
	for key: String in ["clock_s", "candidate_air_s", "candidate_clearance_s", "stable_support_s", "stop_s", "stop_evidence_s", "stop_rejected_s", "rearm_clearance_s", "speed_window_s"]:
		var number: Variant = value.get(key)
		if typeof(number) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(number)) or float(number) < 0.0:
			return false
	if value.speed_window.size() > int(Rules.DEFAULTS.max_speed_samples) \
		or value.pending_speed.size() > int(Rules.DEFAULTS.max_speed_samples):
		return false
	if not value.flight.is_empty() and not _valid_flight(value.flight):
		return false
	for entry: Variant in value.speed_window:
		if not _valid_speed_window_entry(entry):
			return false
	for entry: Variant in value.pending_speed:
		if not _valid_pending_entry(entry):
			return false
	if not value.previous_speed.is_empty() and not _valid_previous_speed(value.previous_speed):
		return false
	for key: Variant in value.speed_reject_counts:
		if typeof(key) != TYPE_STRING or not _finite_integer(value.speed_reject_counts[key]) \
			or int(value.speed_reject_counts[key]) < 0:
			return false
	return true


func _valid_flight(value: Dictionary) -> bool:
	for key: String in ["airborne_seconds", "outcome", "start_kind", "full_stops", "touch_and_go", "failed_landings", "unknown_landings", "max_tas_mps", "max_groundspeed_mps", "complete_observation"]:
		if not value.has(key):
			return false
	if typeof(value.airborne_seconds) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(value.airborne_seconds)) \
		or float(value.airborne_seconds) < 0.0:
		return false
	for key: String in ["full_stops", "touch_and_go", "failed_landings", "unknown_landings"]:
		if not _finite_integer(value[key]) or int(value[key]) < 0:
			return false
	for key: String in ["max_tas_mps", "max_groundspeed_mps"]:
		if typeof(value[key]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value[key])) or float(value[key]) < -1.0:
			return false
	return typeof(value.outcome) == TYPE_STRING and typeof(value.start_kind) == TYPE_STRING \
		and typeof(value.complete_observation) == TYPE_BOOL


func _valid_speed_window_entry(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	return _finite_integer(value.get("tick")) and _finite_positive(value.get("dt")) \
		and _finite_nonnegative(value.get("tas")) and _finite_nonnegative(value.get("groundspeed"))


func _valid_pending_entry(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	if not _finite_integer(value.get("tick")) or not _finite_nonnegative(value.get("time_s")):
		return false
	for key: String in ["tas", "groundspeed"]:
		var number: Variant = value.get(key)
		if typeof(number) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(number)) or float(number) < -1.0:
			return false
	return true


func _valid_previous_speed(value: Dictionary) -> bool:
	return _finite_integer(value.get("tick")) and _finite_nonnegative(value.get("tas")) \
		and _finite_nonnegative(value.get("groundspeed")) and _vector3(value.get("position", [])).size() == 3 \
		and _vector3(value.get("velocity", [])).size() == 3


func _finite_positive(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) > 0.0


func _finite_integer(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) \
		and absf(float(value)) <= 9007199254740991.0 and floor(float(value)) == float(value)


func _json_only(value: Variant, depth: int) -> bool:
	if depth > 24:
		return false
	match typeof(value):
		TYPE_DICTIONARY:
			for key: Variant in value:
				if typeof(key) not in [TYPE_STRING, TYPE_INT]:
					return false
				if not _json_only(value[key], depth + 1):
					return false
			return true
		TYPE_ARRAY:
			if value.size() > 1024:
				return false
			for item: Variant in value:
				if not _json_only(item, depth + 1):
					return false
			return true
		TYPE_FLOAT:
			return is_finite(float(value))
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return true
		_:
			return false

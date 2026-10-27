## Pure accepted-tick flight/event classifier. It owns no nodes, files or wall-clock state.
extends RefCounted

const Rules := preload("res://statistics/rules.gd")
const FlightEvent := preload("res://statistics/flight_event.gd")
const SNAPSHOT_VERSION := 3
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
var _accident_serial := 0
var _accident_id := ""
var _accident_terminal := false
var _continuity_lost := false
var _semantic_sequence := 0
var _semantic_flight_id := ""
var _support_observed := false
var _first_unsupported_tick := -1
var _sample_interval_s := 0.0
var _episode_contact_seen := false
var _episode_supported := false
var _episode_support_known := false
var _hop_first_tick := -1
var _hop_seconds := 0.0
## Derived per-call coverage; never resumed as durable observation history.
var _accepted_component_events: Array[Dictionary] = [] # Derived per-call facts, never historical state.
var _accepted_observation_edge := false
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
	_accident_serial = 0
	_accident_id = ""
	_accident_terminal = false
	_continuity_lost = false
	_clear_speed_state()
	_speed_reject_counts.clear()
	flight = {}
	_semantic_sequence = 0
	_semantic_flight_id = ""
	_support_observed = false
	_first_unsupported_tick = -1
	_sample_interval_s = 0.0
	_clear_hop()


func observe(sample: Dictionary) -> Array[Dictionary]:
	_accepted_observation_edge = false
	_accepted_component_events.clear()
	var staged_component_events: Array[Dictionary] = []
	var events: Array[Dictionary] = []
	if _phase == "terminal":
		return events
	var tick_value: Variant = sample.get("tick", -1)
	if sample.has("component_failure_observation") and not FlightEvent._integer(tick_value): return events
	var tick := int(tick_value) if typeof(tick_value) in [TYPE_INT, TYPE_FLOAT] else -1
	var terminal := bool(sample.get("terminal", false))
	if tick == _last_tick + 1 and sample.has("component_failure_observation"):
		var step_value: Variant = sample.get("dt")
		if typeof(step_value) not in [TYPE_FLOAT, TYPE_INT]: return events
		var packet: Variant = sample.component_failure_observation
		if not FlightEvent.valid_damage_observation(packet, tick, _profile.get("damage_source_generation"),
			_profile.get("damage_response_identity"), float(step_value)): return events
		if not packet.events.is_empty():
			# Reserve room for its complete pair batch plus existing accident/support annotations.
			if _semantic_sequence > 9007199254740991 - 2 * packet.events.size() - 4: return events
			for record: Dictionary in packet.events:
				if FlightEvent.make_damage(_profile, "GEAR_FAILURE", record, _semantic_sequence,
					_semantic_flight_id, "", "preflight").is_empty(): return events
		for record: Dictionary in packet.events: staged_component_events.append(record.duplicate(true))

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

	_sample_interval_s = dt
	_accepted_component_events = staged_component_events
	_accepted_observation_edge = true
	if _is_physically_supported(sample): _support_observed = true
	if bool(sample.get("incident", false)) or not _accepted_component_events.is_empty():
		_incident_latched = true
	if (bool(sample.get("gear_up_contact", false)) or not _accepted_component_events.is_empty()) and not terminal:
		_record_accident(sample, tick, false, events)
	_clock_s += dt
	if not flight.is_empty() and _is_active_flight() and not _is_physically_supported(sample):
		flight.airborne_seconds = float(flight.airborne_seconds) + dt
	if terminal:
		# A newly accepted terminal endpoint can also complete a physical hop.
		# Same-tick guard escalation and discontinuous samples return above and
		# must not advance this edge history a second time.
		if _episode_open: _observe_hop(sample, dt, tick, events)
		_handle_terminal(sample, tick, events, true)
		return events

	if _phase == "ground_ready" or _phase == "takeoff_pending":
		_process_takeoff(sample, dt, tick, events)
	elif _phase == "airborne":
		_process_airborne(sample, tick, events)
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
		"semantic_sequence": _semantic_sequence,
		"semantic_flight_id": _semantic_flight_id,
		"support_observed": _support_observed,
		"first_unsupported_tick": _first_unsupported_tick,
		"sample_interval_s": _sample_interval_s,
		"episode_contact_seen": _episode_contact_seen,
		"episode_supported": _episode_supported,
		"episode_support_known": _episode_support_known,
		"hop_first_tick": _hop_first_tick,
		"hop_seconds": _hop_seconds,
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
		"accident_serial": _accident_serial,
		"accident_id": _accident_id,
		"accident_terminal": _accident_terminal,
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
	_accepted_component_events.clear()
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
	# Historical v1 checkpoints did not observe survivable accident groups.
	# Never infer or accept new group fields disguised as legacy coverage.
	var has_accidents := int(copy.version) >= 2
	_accident_serial = int(copy.accident_serial) if has_accidents else 0
	_accident_id = str(copy.accident_id) if has_accidents else ""
	_accident_terminal = bool(copy.accident_terminal) if has_accidents else false
	# V1/v2 had no semantic support-edge history. Do not invent a past hop or takeoff.
	var has_semantics := int(copy.version) >= 3
	_semantic_sequence = int(copy.semantic_sequence) if has_semantics else 0
	_semantic_flight_id = str(copy.semantic_flight_id) if has_semantics else ""
	_support_observed = bool(copy.support_observed) if has_semantics else false
	_first_unsupported_tick = int(copy.first_unsupported_tick) if has_semantics else -1
	_sample_interval_s = float(copy.sample_interval_s) if has_semantics else 0.0
	_episode_contact_seen = bool(copy.episode_contact_seen) if has_semantics else _episode_open
	_episode_supported = bool(copy.episode_supported) if has_semantics else false
	_episode_support_known = bool(copy.episode_support_known) if has_semantics else false
	_hop_first_tick = int(copy.hop_first_tick) if has_semantics else -1
	_hop_seconds = float(copy.hop_seconds) if has_semantics else 0.0
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
		_first_unsupported_tick = -1
		_phase = "takeoff_pending" if _air_start_requested else "ground_ready"
		return
	if _first_unsupported_tick < 0: _first_unsupported_tick = tick
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
	_clear_accident_group()


func _process_airborne(sample: Dictionary, tick: int, events: Array[Dictionary]) -> void:
	if _is_physically_supported(sample) or bool(sample.get("intended_support", false)):
		_open_episode(tick, sample, events)
		_phase = "contact_pending"


func _process_contact(sample: Dictionary, dt: float, tick: int, events: Array[Dictionary]) -> void:
	_observe_hop(sample, dt, tick, events)
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
	# An accident can come to physical rest on the hull without a wheel stop set.
	if supported and (_incident_latched or stop_geometry) and slow and quiet:
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

	if _incident_latched and _stop_evidence_s + 1e-12 >= float(_thresholds.full_stop_s):
		_finish_full_stop(tick, events)
		return
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
			if _incident_latched:
				reason = "disqualifying_incident"
			elif not bool(_profile.get("landing_available", false)) or _continuity_lost:
				landing_outcome = "unknown"
				reason = "classification_unavailable"
			_resolve_episode(landing_outcome, "bounce_departure", tick, reason, events)
			_phase = "airborne"
		_stable_support_s = 0.0
		_stop_s = 0.0
		_stop_evidence_s = 0.0
		_stop_rejected_s = 0.0
		_rearm_clearance_s = 0.0
		_clear_accident_group()


func _finish_full_stop(tick: int, events: Array[Dictionary]) -> void:
	_semantic("GROUND_STOP", tick, events)
	if _incident_latched:
		_resolve_episode("failed", "full_stop", tick, "disqualifying_incident", events)
		_close_flight("damaged_stop", tick, events)
	elif not bool(_profile.get("landing_available", false)) or _continuity_lost:
		_resolve_episode("unknown", "full_stop", tick, "classification_unavailable", events)
		_close_flight("interrupted", tick, events)
	elif not _qualified_support_seen:
		_resolve_episode("failed", "full_stop", tick, "support_not_controlled", events)
		_close_flight("failed_stop", tick, events)
	else:
		_resolve_episode("success", "full_stop", tick, "", events)
		_close_flight("completed", tick, events)
	_phase = "ground_ready"
	_clear_episode()
	_clear_speed_state()
	# Keep the last accepted contact group while supported at rest. Persistent
	# gear-up support must not manufacture a new incident on the following tick.


func _resolve_full_stop_failure(tick: int, reason: String, events: Array[Dictionary]) -> void:
	_semantic("GROUND_STOP", tick, events)
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


func _record_accident(sample: Dictionary, tick: int, terminal: bool, events: Array[Dictionary], observe_edge := true) -> void:
	_incident_latched = true
	var ground := _is_physically_supported(sample)
	var first := _accident_id.is_empty()
	if first:
		_accident_serial += 1
		_accident_id = "g%s:a%d:t%d" % [str(_profile.get("generation_id", "0")), _accident_serial, tick]
		_accident_terminal = false
	var escalated := terminal and not _accident_terminal
	_accident_terminal = _accident_terminal or terminal
	if ground and _is_active_flight() and not _episode_open:
		_open_episode(tick, sample, events, observe_edge)
		_phase = "contact_pending"
	var cause := "gear_up_contact" if bool(sample.get("gear_up_contact", false)) else ("gear_failure" if not _accepted_component_events.is_empty() else "terminal_crash")
	if first or escalated:
		events.append({"type": "accident" if first else "accident_updated", "kind": cause,
			"accident_id": _accident_id, "event_id": _accident_id + (":crash" if first else ":terminal"),
			"terminal": terminal, "ground": ground, "tick": tick, "rules_version": Rules.VERSION})
	if first:
		if bool(sample.get("gear_up_contact", false)): _semantic("GEAR_UP_CONTACT", tick, events, {}, terminal)
		_semantic("CRASH", tick, events, {}, terminal)
	elif escalated:
		_semantic("CRASH", tick, events, {}, true, 1)
	# M7 is a generation latch, independent of semantic accident grouping and terminal control.
	if not _crash_emitted:
		_crash_emitted = true
		var crash_record := {"type": "crash", "kind": cause, "ground": ground, "tick": tick, "terminal": terminal,
			"accident_id": _accident_id, "event_id": _accident_id + ":m7", "rules_version": Rules.VERSION}
		if not _accepted_component_events.is_empty(): crash_record.damage_summary = _accepted_component_events.duplicate(true)
		events.append(crash_record)
	if observe_edge and _accepted_observation_edge:
		_semantic_component_failures(tick, events)
	_clear_speed_state()


func _clear_accident_group() -> void:
	_accident_id = ""
	_accident_terminal = false


func _handle_terminal(sample: Dictionary, tick: int, events: Array[Dictionary], accepted_edge := false) -> void:
	if _phase == "terminal":
		return
	_record_accident(sample, tick, true, events, accepted_edge)
	if _is_active_flight():
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
	_semantic_flight_id = "g%s:f%d" % [str(_profile.get("generation_id", "0")), tick]
	events.append({"type": "started", "start_kind": start_kind,
		"tick": tick, "flight": flight.duplicate(true)})
	if start_kind == "takeoff" and _support_observed and _first_unsupported_tick >= 0:
		_semantic("TAKEOFF", tick, events, {first_loss_support_tick = _first_unsupported_tick, confirmation_tick = tick})


func _open_episode(tick: int, sample: Dictionary, events: Array[Dictionary], observe_edge := true) -> void:
	if _episode_open:
		return
	_episode_open = true
	_episode_tick = tick
	_clear_hop()
	if observe_edge: _observe_hop(sample, 0.0, tick, events)
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
	if outcome == "success":
		_semantic("LANDING_SUCCESS", tick, events, {first_contact_tick = _episode_tick})
		if kind == "touch_and_go": _semantic("TOUCH_AND_GO", tick, events, {first_contact_tick = _episode_tick})
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
	_semantic_flight_id = ""


func _clear_episode() -> void:
	_clear_hop()
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
	# Runs every accepted tick (UI-FS-08-R1): packed copies sort natively, and the sorted
	# extremes decide stability exactly (|v − median| is monotonic on each side of the median).
	var count: int = _speed_window.size() - _speed_head
	var tas_values := PackedFloat64Array()
	var ground_values := PackedFloat64Array()
	tas_values.resize(count)
	ground_values.resize(count)
	for i in count:
		var entry: Dictionary = _speed_window[_speed_head + i]
		tas_values[i] = float(entry.tas)
		ground_values[i] = float(entry.groundspeed)
	tas_values.sort()
	ground_values.sort()
	var median_tas := _sorted_median(tas_values)
	var median_ground := _sorted_median(ground_values)
	var tas_stable := _sorted_near_median(tas_values, median_tas)
	var ground_stable := _sorted_near_median(ground_values, median_ground)
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


## Every value within tolerance of the median; `sorted` is ascending and finite.
func _sorted_near_median(sorted: PackedFloat64Array, median: float) -> bool:
	if sorted.is_empty():
		return false
	var tolerance := maxf(float(_thresholds.speed_stability_absolute_mps),
		float(_thresholds.speed_stability_fraction) * median)
	return absf(sorted[0] - median) <= tolerance and absf(sorted[sorted.size() - 1] - median) <= tolerance


func _sorted_median(sorted: PackedFloat64Array) -> float:
	if sorted.is_empty():
		return -1.0
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
	if not _json_only(value, 0) or not _finite_integer(value.get("version")) \
		or int(value.version) not in [1, 2, SNAPSHOT_VERSION]:
		return false
	if int(value.version) >= 2:
		if not _finite_integer(value.get("accident_serial")) or int(value.accident_serial) < 0 \
			or typeof(value.get("accident_id")) != TYPE_STRING or str(value.accident_id).length() > 192 \
			or typeof(value.get("accident_terminal")) != TYPE_BOOL:
			return false
		# Restored group state must preserve the same idempotency relationships as
		# accepted observations; otherwise a damaged checkpoint can recount M7 or
		# suppress the terminal escalation that updates a durable crash record.
		if (int(value.accident_serial) > 0 or not str(value.accident_id).is_empty()) \
			and (value.get("incident_latched") != true or value.get("crash_emitted") != true):
			return false
		if not str(value.accident_id).is_empty() and int(value.accident_serial) == 0:
			return false
		if value.accident_terminal and (str(value.accident_id).is_empty() or value.get("phase") != "terminal"):
			return false
	for key: String in ["profile", "flight", "speed_window", "pending_speed", "previous_speed", "speed_reject_counts"]:
		if not value.has(key):
			return false
	if typeof(value.profile) != TYPE_DICTIONARY or typeof(value.flight) != TYPE_DICTIONARY \
		or typeof(value.speed_window) != TYPE_ARRAY or typeof(value.pending_speed) != TYPE_ARRAY \
		or typeof(value.previous_speed) != TYPE_DICTIONARY or typeof(value.speed_reject_counts) != TYPE_DICTIONARY:
		return false
	if value.profile.has("damage_response_identity") or value.profile.has("damage_source_generation"):
		if not FlightEvent._hash(value.profile.get("damage_response_identity")) \
			or not FlightEvent._id(value.profile.get("damage_source_generation"), 128): return false
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
	if int(value.version) >= 3 and not _valid_semantic_snapshot(value): return false
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


func _semantic(kind: String, tick: int, events: Array[Dictionary], measurements: Dictionary = {},
		terminal := false, revision := 0) -> void:
	var values := measurements.duplicate(true)
	values.sample_interval_s = _sample_interval_s
	var episode_id := "g%s:e%d" % [str(_profile.get("generation_id", "0")), _episode_tick] if _episode_open else ""
	var event := FlightEvent.make(_profile, kind, tick, _semantic_sequence, _semantic_flight_id,
		episode_id, _accident_id, values, terminal, revision)
	if event.is_empty(): return
	if not _accepted_observation_edge:
		event.evidence_coverage.erase("accepted_endpoint_support")
		event.evidence_coverage.append("outcome_without_new_valid_interval")
	if kind == "CRASH" and _accepted_observation_edge and not _accepted_component_events.is_empty():
		event.evidence_coverage.erase("damage_unobserved")
		event.evidence_coverage.append("component_failure_observed")
		for record: Dictionary in _accepted_component_events:
			event.cause.evidence_ids.append(record.physical_evidence.source_event_id)
	if terminal: event.evidence_coverage.append("terminal_guard_outcome")
	if _continuity_lost: event.evidence_coverage.append("discontinuous_observation")
	_semantic_sequence += 1
	events.append({type = "semantic", event = event})


func _clear_hop() -> void:
	_episode_contact_seen = false
	_episode_supported = false
	_episode_support_known = false
	_hop_first_tick = -1
	_hop_seconds = 0.0


func _observe_hop(sample: Dictionary, dt: float, tick: int, events: Array[Dictionary]) -> void:
	var supported := _is_physically_supported(sample)
	if supported and not _episode_contact_seen:
		_episode_contact_seen = true
		_semantic("TOUCHDOWN", tick, events, {first_contact_tick = tick}, bool(sample.get("terminal", false)))
	elif supported and _episode_support_known and not _episode_supported and _hop_first_tick >= 0:
		_semantic("BOUNCE", tick, events, {first_loss_support_tick = _hop_first_tick,
			unsupported_seconds = _hop_seconds, first_contact_tick = _episode_tick}, bool(sample.get("terminal", false)))
	if not supported and _episode_contact_seen and _episode_support_known:
		if _episode_supported: _hop_first_tick = tick
		if _hop_first_tick >= 0: _hop_seconds += dt
	else:
		_hop_first_tick = -1
		_hop_seconds = 0.0
	_episode_supported = supported
	_episode_support_known = true


func _valid_semantic_snapshot(value: Dictionary) -> bool:
	for key: String in ["semantic_sequence", "first_unsupported_tick", "hop_first_tick"]:
		if not _finite_integer(value.get(key)): return false
	if value.semantic_sequence < 0 or value.first_unsupported_tick < -1 or value.hop_first_tick < -1 \
		or value.first_unsupported_tick > value.get("last_tick", -1) or value.hop_first_tick > value.get("last_tick", -1): return false
	if typeof(value.get("semantic_flight_id")) != TYPE_STRING or value.semantic_flight_id.length() > 192: return false
	for key: String in ["support_observed", "episode_contact_seen", "episode_supported", "episode_support_known"]:
		if typeof(value.get(key)) != TYPE_BOOL: return false
	for key: String in ["sample_interval_s", "hop_seconds"]:
		if not _finite_nonnegative(value.get(key)): return false
	if value.hop_first_tick >= 0 and (not value.get("episode_open", false) or not value.episode_contact_seen \
		or not value.episode_support_known or value.episode_supported or value.hop_seconds <= 0.0): return false
	if value.hop_first_tick >= 0 and value.hop_first_tick < value.episode_tick: return false
	if value.hop_seconds > value.clock_s + 64.0 * 2.220446049250313e-16 * maxf(1.0, value.clock_s): return false
	if value.episode_supported and (not value.episode_support_known or not value.episode_contact_seen): return false
	if value.hop_first_tick < 0 and value.hop_seconds != 0.0: return false
	if not value.get("episode_open", false) and (value.episode_contact_seen or value.episode_supported \
		or value.episode_support_known): return false
	return true

## Only the qualified accepted failure path calls this, through _record_accident.
## These are factual annotations of its accident, never a second crash counter.
func _semantic_component_failures(tick: int, events: Array[Dictionary]) -> void:
	var episode_id := "g%s:e%d" % [str(_profile.get("generation_id", "0")), _episode_tick] if _episode_open else ""
	var staged: Array[Dictionary] = []
	var sequence := _semantic_sequence
	for record: Dictionary in _accepted_component_events:
		for kind: String in ["COMPONENT_DAMAGE", "GEAR_FAILURE"]:
			var event := FlightEvent.make_damage(_profile, kind, record, sequence,
				_semantic_flight_id, episode_id, _accident_id)
			if event.is_empty(): return # No partial pair/batch can be published.
			sequence += 1
			staged.append({type = "semantic", event = event})
	_semantic_sequence = sequence
	events.append_array(staged)

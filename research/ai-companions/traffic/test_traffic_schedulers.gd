extends SceneTree

const Runway = preload("res://runway_coordinator.gd")
const ActivityScheduler = preload("res://activity_quota_scheduler.gd")
const IncidentScheduler = preload("res://fleet_incident_scheduler.gd")

var _failures: int = 0


func _initialize() -> void:
	_test_runway_priority_matches_independent_oracle()
	_test_runway_aging_prevents_feasible_starvation()
	_test_runway_stale_generation_and_occupancy()
	_test_runway_player_priority_and_implicit_occupancy()
	_test_runway_wind_reversal_and_envelope_revocation()
	_test_runway_wreck_occupancy_and_serialization()
	_test_activity_quota_fairness_cooldown_and_eligibility()
	_test_activity_weighted_choice_and_replay_state()
	_test_incidents_off_and_grace()
	_test_incident_deadlines_ignore_frame_and_fleet_size()
	_test_incident_poisson_rate_against_analytic_interval()
	_test_incident_cooldowns_and_non_crash_guarantee()
	if _failures == 0:
		print("PASS traffic scheduler draft checks")
		quit(0)
	else:
		printerr("FAIL traffic scheduler draft checks: ", _failures)
		quit(1)


func _test_runway_priority_matches_independent_oracle() -> void:
	var coordinator = Runway.new(1, 100000, 10000, 32, 64)
	var requests: Array[Dictionary] = [
		{"request_id": "pass", "owner_id": 90, "generation": 1, "operation": "pass", "request_tick": 4, "direction": 0},
		{"request_id": "takeoff", "owner_id": 80, "generation": 1, "operation": "takeoff", "request_tick": 3, "direction": 0},
		{"request_id": "landing-late", "owner_id": 70, "generation": 1, "operation": "landing", "request_tick": 8, "direction": 0},
		{"request_id": "landing-early", "owner_id": 60, "generation": 2, "operation": "landing", "request_tick": 2, "direction": 0},
		{"request_id": "committed", "owner_id": 50, "generation": 1, "operation": "landing", "request_tick": 9, "committed_arrival": true, "direction": 0},
		{"request_id": "player", "owner_id": 0, "generation": 1, "operation": "takeoff", "request_tick": 6, "player_request": true, "direction": 0},
		{"request_id": "emergency", "owner_id": 40, "generation": 1, "operation": "landing", "request_tick": 7, "emergency": true, "direction": 0}
	]
	var expected: Array[int] = _reference_runway_order(requests, 100, 100000)
	for request: Dictionary in requests:
		var accepted: Dictionary = coordinator.submit_request(int(request["request_tick"]), String(request["request_id"]), int(request["owner_id"]), int(request["generation"]), "pilot-" + str(request["owner_id"]), String(request["operation"]), int(request["direction"]), bool(request.get("player_request", false)), bool(request.get("emergency", false)), bool(request.get("committed_arrival", false)))
		_check(bool(accepted.get("ok", false)), "simultaneous queue request should be accepted")
	var actual_owners: Array[int] = []
	for expected_owner: int in expected:
		var result: Dictionary = coordinator.resolve(100)
		_check(bool(result.get("granted", false)), "reference-ordered request should receive a runway slot")
		var grant: Dictionary = result.get("grant", {})
		actual_owners.append(int(grant.get("owner_id", -1)))
		var released: Dictionary = coordinator.cancel_reservation(100, int(grant.get("ticket", -1)), int(grant.get("owner_id", -1)), int(grant.get("generation", -1)), "oracle_slot_release")
		_check(bool(released.get("ok", false)), "oracle slot should be released with its matching ticket")
	_check(actual_owners == expected, "runway grant order should match the independent priority oracle")
	_check(not bool(coordinator.resolve(100).get("granted", false)), "all oracle requests should be consumed")
	var volume_contract = Runway.new()
	volume_contract.submit_request(0, "landing-volumes", 2, 1, "pilot-2", "landing", 0, false, false, false, "arrival-gate", -1, -1, -1.0, -1.0, ["approach-tube", "runway-strip"])
	var volume_grant: Dictionary = volume_contract.resolve(0).get("grant", {})
	_check(volume_grant.get("protected_volumes", []).has("approach-tube") and volume_grant.get("protected_volumes", []).has("runway-strip") and volume_grant.get("protected_volumes", []).has("arrival-gate"), "reservation serializes every protected approach/runway volume ID")
	var bounded = Runway.new(1, 10, 20, 1, 1)
	_check(bool(bounded.submit_request(0, "first", 1, 1, "pilot-1", "takeoff").get("ok", false)), "bounded runway queue accepts up to its configured capacity")
	_check(not bool(bounded.submit_request(0, "second", 2, 1, "pilot-2", "takeoff").get("ok", false)), "bounded runway queue refuses overflow without dropping an existing request")
	bounded.resolve(0)
	_check(bounded.snapshot_state()["events"].size() <= 1, "runway diagnostic event storage remains bounded")


func _test_runway_aging_prevents_feasible_starvation() -> void:
	var coordinator = Runway.new(1, 10, 10000, 32, 64)
	coordinator.submit_request(0, "old-takeoff", 90, 1, "pilot-90", "takeoff")
	coordinator.submit_request(0, "first-landing", 1, 1, "pilot-1", "landing", 1, false, false, true)
	var first: Dictionary = coordinator.resolve(0).get("grant", {})
	_check(int(first.get("owner_id", -1)) == 1, "committed arrival should precede a new takeoff")
	coordinator.cancel_reservation(0, int(first.get("ticket", -1)), 1, 1, "fixture_release")
	coordinator.submit_request(10, "second-landing", 2, 1, "pilot-2", "landing", 1, false, false, true)
	var second: Dictionary = coordinator.resolve(10).get("grant", {})
	_check(int(second.get("owner_id", -1)) == 2, "newer committed arrival still outranks a not-yet-aged takeoff")
	coordinator.cancel_reservation(10, int(second.get("ticket", -1)), 2, 1, "fixture_release")
	coordinator.submit_request(20, "third-landing", 3, 1, "pilot-3", "landing", 1, false, false, true)
	var third: Dictionary = coordinator.resolve(20).get("grant", {})
	_check(int(third.get("owner_id", -1)) == 90, "aged takeoff should rise to the committed-arrival band and win by older request time")
	_check(coordinator.snapshot_state()["requests"].size() == 1, "later landing remains queued after the aged request gets a turn")


func _test_runway_stale_generation_and_occupancy() -> void:
	var coordinator = Runway.new()
	coordinator.submit_request(0, "sortie-7-g2", 7, 2, "pilot-7", "takeoff")
	var grant: Dictionary = coordinator.resolve(0).get("grant", {})
	_check(not bool(coordinator.enter_runway(1, int(grant["ticket"]), 7, 1).get("ok", false)), "reused slot generation must not enter with an old grant")
	_check(bool(coordinator.enter_runway(1, int(grant["ticket"]), 7, 2).get("ok", false)), "current generation enters with its exact ticket")
	coordinator.resolve(1000000)
	_check(String(coordinator.snapshot_state()["mode"]) == "occupied", "actual occupancy never expires when a reservation timer passes")
	_check(not bool(coordinator.report_clearance(1000000, 8, 2, true, true).get("ok", false)), "another aircraft cannot release an occupied runway")
	_check(not bool(coordinator.report_clearance(1000000, 7, 2, true, false).get("cleared", false)), "swept footprint alone does not clear the protected path")
	_check(String(coordinator.snapshot_state()["mode"]) == "clearing", "runway enters clearing while the path remains protected")
	_check(bool(coordinator.report_clearance(1000001, 7, 2, true, true).get("cleared", false)), "full footprint and protected-path clearance release occupancy")
	_check(String(coordinator.snapshot_state()["mode"]) == "free", "fully cleared runway returns to free")


func _test_runway_player_priority_and_implicit_occupancy() -> void:
	var coordinator = Runway.new()
	coordinator.submit_request(0, "ai-takeoff", 4, 1, "pilot-4", "takeoff")
	var ai_grant: Dictionary = coordinator.resolve(0).get("grant", {})
	var approached: Dictionary = coordinator.observe_player(1, 0, 8, false, true)
	_check(bool(approached.get("ok", false)), "player approach observation should be accepted")
	_check(not bool(coordinator.enter_runway(2, int(ai_grant["ticket"]), 4, 1).get("ok", false)), "player approach invalidates an AI grant before entry")
	_check(String(coordinator.snapshot_state()["mode"]) == "free", "revoked approach grant does not fabricate runway occupancy")
	_check(String(coordinator.resolve(3).get("reason", "")) == "player_priority", "AI holds while player approach intent is present")
	coordinator.submit_request(3, "emergency-landing", 5, 1, "pilot-5", "landing", 0, false, true, true)
	var emergency_grant: Dictionary = coordinator.resolve(3).get("grant", {})
	_check(bool(emergency_grant.get("emergency", false)), "immediate AI emergency retains priority over an advisory player approach")
	coordinator.cancel_reservation(3, int(emergency_grant.get("ticket", -1)), 5, 1, "fixture_release")
	_check(String(coordinator.resolve(3).get("reason", "")) == "player_priority", "ordinary AI traffic remains held after emergency reservation ends")
	coordinator.observe_player(4, 0, 8, false, false)
	var restored_grant: Dictionary = coordinator.resolve(4).get("grant", {})
	_check(not restored_grant.is_empty(), "valid AI request is requeued after the player clears approach intent")
	coordinator.cancel_reservation(4, int(restored_grant["ticket"]), 4, 1, "fixture_release")
	var implicit: Dictionary = coordinator.observe_player(5, 0, 8, true, false)
	_check(bool(implicit.get("ok", false)) and String(implicit.get("mode", "")) == "occupied", "player runway presence occupies the strip without a request")
	_check(not bool(coordinator.resolve(6).get("granted", false)), "implicit player occupancy blocks new AI reservations")
	coordinator.observe_player(7, 0, 8, false, false)
	_check(String(coordinator.snapshot_state()["mode"]) == "clearing", "player exit retains occupancy until geometry reports clearance")
	coordinator.report_clearance(8, 0, 8, true, false)
	_check(String(coordinator.snapshot_state()["mode"]) == "clearing", "protected arrival/departure volume still retains the strip")
	coordinator.report_clearance(9, 0, 8, true, true)
	_check(String(coordinator.snapshot_state()["mode"]) == "free", "player occupancy clears after both geometric checks pass")


func _test_runway_wind_reversal_and_envelope_revocation() -> void:
	var coordinator = Runway.new()
	coordinator.update_wind(0, 5.0, 2.0, 4.0)
	coordinator.submit_request(0, "takeoff-limited", 12, 1, "pilot-12", "takeoff", 0, false, false, false, "departure-east", -1, -1, 3.0, 5.0)
	var grant: Dictionary = coordinator.resolve(0).get("grant", {})
	_check(not grant.is_empty(), "request inside current wind envelope receives a grant")
	coordinator.update_wind(1, -5.0, 2.0, 4.0)
	_check(String(coordinator.snapshot_state()["mode"]) == "reserved", "direction change waits through its ten-second dwell")
	coordinator.update_wind(2401, -5.0, 2.0, 4.0)
	_check(int(coordinator.snapshot_state()["direction"]) == -1, "consistent opposite headwind reverses the runway after 10 seconds")
	_check(String(coordinator.snapshot_state()["mode"]) == "free", "direction reversal revokes a stale reservation")
	var retargeted: Dictionary = coordinator.resolve(2401).get("grant", {})
	_check(int(retargeted.get("direction", 0)) == -1, "requeued direction-neutral request follows the newly accepted runway direction")
	var events: Array[Dictionary] = coordinator.drain_events()
	_check(_events_have(events, "reservation_revoked", "wind_direction_reversed"), "wind reversal reason is journaled")
	var opposite_request = Runway.new(1)
	opposite_request.update_wind(0, -4.0, 0.0, 1.0)
	opposite_request.update_wind(2400, -4.0, 0.0, 1.0)
	opposite_request.submit_request(2400, "westbound", 20, 1, "pilot-20", "landing", -1)
	_check(int(opposite_request.resolve(2400).get("grant", {}).get("direction", 0)) == -1, "opposite direction request grants only after accepted reversal")
	var occupied = Runway.new()
	occupied.update_wind(0, -3.0, 0.0, 0.0)
	occupied.observe_player(0, 0, 1, true, false)
	var locked: Dictionary = occupied.update_wind(2400, -3.0, 0.0, 0.0)
	_check(not bool(locked.get("changed", false)) and int(occupied.snapshot_state()["direction"]) == 1, "occupied runway locks its direction despite persistent wind")
	occupied.report_clearance(2401, 0, 1, true, true)
	var now_clear: Dictionary = occupied.update_wind(2401, -3.0, 0.0, 0.0)
	_check(bool(now_clear.get("changed", false)) and int(occupied.snapshot_state()["direction"]) == -1, "persistent wind reversal is considered when runway occupancy clears")
	var envelope = Runway.new()
	envelope.update_wind(0, 5.0, 2.0, 2.0)
	envelope.submit_request(0, "limited", 3, 1, "pilot-3", "takeoff", 0, false, false, false, "departure", -1, -1, 3.0, 3.0)
	var wind_grant: Dictionary = envelope.resolve(0).get("grant", {})
	envelope.update_wind(1, 5.0, 4.0, 2.0)
	_check(String(envelope.snapshot_state()["mode"]) == "free", "crosswind envelope change revokes an unentered grant")
	_check(not bool(envelope.enter_runway(1, int(wind_grant.get("ticket", -1)), 3, 1).get("ok", false)), "revoked wind-limited ticket cannot enter later")


func _test_runway_wreck_occupancy_and_serialization() -> void:
	var coordinator = Runway.new()
	coordinator.submit_request(0, "queued", 30, 1, "pilot-30", "landing")
	var blocked: Dictionary = coordinator.report_runway_wreck(1, 9, 2, "pilot-9", "wreck-9-g2", "arrival-west")
	_check(bool(blocked.get("ok", false)) and String(blocked.get("mode", "")) == "blocked", "runway wreck moves the coordinator into persistent blocked state")
	coordinator.report_runway_wreck(2, 10, 1, "pilot-10", "wreck-10-g1", "departure-east")
	_check(not bool(coordinator.resolve(200000).get("granted", false)), "wreck blocks new operations beyond any reservation duration")
	_check(not bool(coordinator.clear_wreck_and_occupancy(200001, "wreck-9-g2", false).get("ok", false)), "wreck occupancy cannot clear before world removal commits")
	_check(not bool(coordinator.clear_wreck_and_occupancy(200001, "other-wreck", true).get("ok", false)), "another wreck identity cannot clear the blocker")
	var restored = Runway.new()
	_check(bool(restored.restore_state(coordinator.snapshot_state()).get("ok", false)), "runway snapshot restores through a versioned serializable state")
	_check(restored.snapshot_state() == coordinator.snapshot_state(), "restored runway state preserves blocker, queue, and event sequence")
	var first_clear: Dictionary = coordinator.clear_wreck_and_occupancy(200002, "wreck-9-g2", true)
	_check(bool(first_clear.get("ok", false)) and String(first_clear.get("mode", "")) == "blocked", "removing one wreck leaves the other runway blocker occupied")
	_check(bool(coordinator.clear_wreck_and_occupancy(200003, "wreck-10-g1", true).get("ok", false)), "last exact committed wreck removal atomically clears occupancy")
	_check(bool(coordinator.resolve(200003).get("granted", false)), "queued movement can proceed after all wreck cleanup")
	var corrupt: Dictionary = coordinator.snapshot_state()
	corrupt["mode"] = "blocked"
	corrupt["blocked_wreck_id"] = ""
	_check(not bool(Runway.new().restore_state(corrupt).get("ok", false)), "malformed blocked state is rejected")


func _test_activity_quota_fairness_cooldown_and_eligibility() -> void:
	var scheduler = ActivityScheduler.new(700)
	for agent_id: int in [3, 1, 2]:
		var queued: Dictionary = scheduler.request_activity(0, "box-" + str(agent_id), "pilot-" + str(agent_id), agent_id, 1, "loop", "box-a", 1.0, 1, 20, 60)
		_check(bool(queued.get("ok", false)), "eligible maneuver request enters bounded queue")
	var first_result: Dictionary = scheduler.resolve(0)
	var grants: Array = first_result.get("granted", [])
	_check(grants.size() == 1 and int(grants[0].get("owner_id", -1)) == 1, "quota one grants the oldest stable request only")
	_check(not bool(scheduler.complete_activity(10, 1, 1, "loop").get("ok", false)), "minimum activity duration prevents an early normal completion")
	_check(bool(scheduler.complete_activity(10, 1, 1, "loop", "recovery", true).get("ok", false)), "safety recovery may preempt the activity immediately")
	var second: Array = scheduler.resolve(10).get("granted", [])
	_check(second.size() == 1 and int(second[0].get("owner_id", -1)) == 2, "oldest feasible queued agent receives the next released quota")
	_check(not bool(scheduler.request_activity(10, "loop-again", "pilot-1", 1, 1, "loop", "box-a", 1.0, 1, 20, 60).get("ok", false)), "completed activity cooldown prevents immediate repeat")
	var wrong_generation: Dictionary = scheduler.complete_activity(40, 2, 2, "loop")
	_check(not bool(wrong_generation.get("ok", false)), "stale generation cannot finish a current activity lease")
	_check(bool(scheduler.complete_activity(40, 2, 1, "loop").get("ok", false)), "lease completes after its minimum duration")
	var third: Array = scheduler.resolve(40).get("granted", [])
	_check(third.size() == 1 and int(third[0].get("owner_id", -1)) == 3, "third queued agent receives quota without starvation")
	var refused: Dictionary = scheduler.request_activity(41, "unsupported-roll", "pilot-4", 4, 1, "roll", "box-a", 1.0, 1, 0, 0, 0, false, "profile_not_qualified")
	_check(not bool(refused.get("ok", false)) and String(refused.get("reason", "")) == "profile_not_qualified", "unsupported activity records its eligibility reason")
	var cancelled = ActivityScheduler.new(10)
	cancelled.request_activity(0, "energy-choice", "pilot-5", 5, 1, "loop", "box-a", 1.0, 1, 0, 0)
	var canceled_result: Dictionary = cancelled.resolve(0, {"energy-choice": {"eligible": false, "reason": "energy_below_entry_gate"}})
	_check(canceled_result.get("granted", []).is_empty(), "eligibility is rechecked at the grant boundary")
	_check(not canceled_result.get("cancelled", []).is_empty() and String(canceled_result["cancelled"][0].get("reason", "")) == "energy_below_entry_gate", "grant-time refusal logs the explicit energy reason")
	var independent = ActivityScheduler.new(11)
	independent.request_activity(0, "circuit", "pilot-6", 6, 1, "circuit", "circuit-lane", 1.0, 3, 0, 0)
	independent.request_activity(0, "show-box", "pilot-7", 7, 1, "loop", "box-b", 1.0, 1, 0, 0)
	_check(independent.resolve(0).get("granted", []).size() == 2, "different quota resources can host independent concurrent activities")
	var replaced_generation: Dictionary = independent.request_activity(1, "next-sortie", "pilot-6", 6, 2, "circuit", "circuit-lane", 1.0, 3, 0, 0)
	_check(bool(replaced_generation.get("ok", false)), "new sortie generation is distinct from the previous active lease")
	independent.retire_agent(1, 6, 1, "old_generation_retired")
	_check(independent.resolve(1).get("granted", []).size() == 1, "old-generation retirement releases its slot without touching the new generation")
	var bounded = ActivityScheduler.new(3, 8, 8, 1)
	bounded.request_activity(0, "lane-one", "pilot-20", 20, 1, "circuit", "lane-one", 1.0, 1, 0, 0)
	bounded.request_activity(0, "lane-two", "pilot-21", 21, 1, "pass", "lane-two", 1.0, 1, 0, 0)
	_check(bounded.resolve(0).get("granted", []).size() == 1 and bounded.snapshot_state()["active"].size() == 1, "active activity leases obey the hard fleet bound across independent resources")


func _test_activity_weighted_choice_and_replay_state() -> void:
	var first = ActivityScheduler.new(98765)
	var second = ActivityScheduler.new(98765)
	var left_options: Array[Dictionary] = [
		{"activity_id": "circuit", "weight": 3.0, "eligible": true},
		{"activity_id": "loop", "weight": 1.0, "eligible": true},
		{"activity_id": "unsupported", "weight": 100.0, "eligible": false, "reason": "not_qualified"}
	]
	var right_options: Array[Dictionary] = [left_options[2], left_options[1], left_options[0]]
	var left_choice: Dictionary = first.choose_weighted_activity(0, "pilot-a", left_options)
	var right_choice: Dictionary = second.choose_weighted_activity(0, "pilot-a", right_options)
	_check(String(left_choice.get("activity", {}).get("activity_id", "")) == String(right_choice.get("activity", {}).get("activity_id", "")), "weighted choice ignores input array order for the same seed")
	var snapshot: Dictionary = first.snapshot_state()
	var restored = ActivityScheduler.new(1)
	_check(bool(restored.restore_state(snapshot).get("ok", false)), "activity RNG and leases restore from serialized state")
	var next_left: Dictionary = first.choose_weighted_activity(1, "pilot-a", left_options)
	var next_right: Dictionary = restored.choose_weighted_activity(1, "pilot-a", right_options)
	_check(String(next_left.get("activity", {}).get("activity_id", "")) == String(next_right.get("activity", {}).get("activity_id", "")), "restored activity RNG continues exact deterministic selection")
	var no_draw = ActivityScheduler.new(123)
	var before: int = int(no_draw.snapshot_state()["choice_rng_state"])
	no_draw.choose_weighted_activity(0, "pilot-b", [{"activity_id": "roll", "weight": 5.0, "eligible": false}])
	_check(int(no_draw.snapshot_state()["choice_rng_state"]) == before, "no eligible activity consumes no choice randomness")


func _test_incidents_off_and_grace() -> void:
	var off = IncidentScheduler.new(501, "off", 0, true)
	var before: Dictionary = off.snapshot_state()
	var output: Array[Dictionary] = off.advance_to(100000000, _one_eligible_pilot())
	var after: Dictionary = off.snapshot_state()
	_check(output.is_empty() and off.opportunity_count() == 0, "Off produces no opportunities regardless of elapsed ticks")
	_check(int(before["time_rng_state"]) == int(after["time_rng_state"]) and int(after["next_deadline_tick"]) == -1, "Off does not consume timing RNG or retain a scheduled deadline")
	var grace = IncidentScheduler.new(502, "lively", 0, false)
	_check(grace.next_deadline_tick() > IncidentScheduler.FIRST_INCIDENT_GRACE_TICKS, "first Poisson opportunity follows the 60-second fleet grace period")
	var early: Array[Dictionary] = grace.advance_to(IncidentScheduler.FIRST_INCIDENT_GRACE_TICKS, _one_eligible_pilot())
	_check(early.is_empty() and grace.opportunity_count() == 0, "no scheduled incidents can occur inside the first-minute grace")
	var toggled = IncidentScheduler.new(503, "rare", 0, false)
	var toggle_result: Dictionary = toggled.set_rate("off", 10)
	_check(bool(toggle_result.get("ok", false)) and toggled.next_deadline_tick() == -1, "switching Off removes future deadlines immediately")
	var active_checkpoint = IncidentScheduler.new(504, "lively", 0, false)
	var due: int = active_checkpoint.next_deadline_tick()
	active_checkpoint.advance_to(due, _one_eligible_pilot())
	var checkpoint: Dictionary = active_checkpoint.snapshot_state()
	var restored = IncidentScheduler.new(1)
	_check(bool(restored.restore_state(checkpoint).get("ok", false)), "incident timing, active episode, cooldowns, and RNG restore from serializable state")
	_check(restored.snapshot_state() == checkpoint, "incident restore retains exact point-process state")


func _test_incident_deadlines_ignore_frame_and_fleet_size() -> void:
	var baseline = IncidentScheduler.new(5555, "occasional", 0, false)
	var frame_grouped = IncidentScheduler.new(5555, "occasional", 0, false)
	var one_aircraft = IncidentScheduler.new(5555, "occasional", 0, false)
	var many_aircraft = IncidentScheduler.new(5555, "occasional", 0, false)
	var stop_tick: int = IncidentScheduler.FIRST_INCIDENT_GRACE_TICKS + 240 * 60 * 90
	var frame_tick: int = 0
	var frame_pattern: Array[int] = [2, 6, 1, 8, 4, 3]
	var frame_index: int = 0
	while frame_tick < stop_tick:
		frame_tick = mini(stop_tick, frame_tick + frame_pattern[frame_index % frame_pattern.size()])
		frame_grouped.advance_to(frame_tick, [])
		frame_index += 1
	while baseline.next_deadline_tick() >= 0 and baseline.next_deadline_tick() <= stop_tick:
		baseline.advance_to(baseline.next_deadline_tick(), [])
	var roster_one: Array[Dictionary] = _one_eligible_pilot()
	var roster_many: Array[Dictionary] = _many_eligible_pilots(32)
	while one_aircraft.next_deadline_tick() >= 0 and one_aircraft.next_deadline_tick() <= stop_tick:
		var due_one: int = one_aircraft.next_deadline_tick()
		for event: Dictionary in one_aircraft.advance_to(due_one, roster_one):
			if String(event.get("type", "")) == "incident_started":
				one_aircraft.complete_incident(due_one, int(event.get("payload", {}).get("opportunity_id", -1)), "fixture_complete")
	while many_aircraft.next_deadline_tick() >= 0 and many_aircraft.next_deadline_tick() <= stop_tick:
		var due_many: int = many_aircraft.next_deadline_tick()
		for event: Dictionary in many_aircraft.advance_to(due_many, roster_many):
			if String(event.get("type", "")) == "incident_started":
				many_aircraft.complete_incident(due_many, int(event.get("payload", {}).get("opportunity_id", -1)), "fixture_complete")
	_check(baseline.opportunity_count() == frame_grouped.opportunity_count(), "fixed-tick Poisson opportunities do not depend on render-frame grouping")
	_check(int(baseline.snapshot_state()["next_deadline_tick"]) == int(frame_grouped.snapshot_state()["next_deadline_tick"]), "frame grouping preserves the exact next deadline")
	_check(baseline.opportunity_count() == one_aircraft.opportunity_count() and baseline.opportunity_count() == many_aircraft.opportunity_count(), "fleet opportunity count is independent of one or 32 aircraft")
	_check(int(baseline.snapshot_state()["next_deadline_tick"]) == int(one_aircraft.snapshot_state()["next_deadline_tick"]) and int(one_aircraft.snapshot_state()["next_deadline_tick"]) == int(many_aircraft.snapshot_state()["next_deadline_tick"]), "selection from different fleet sizes does not perturb future timing draws")
	_check(one_aircraft.snapshot_state()["time_rng_state"] == many_aircraft.snapshot_state()["time_rng_state"], "incident timing RNG is isolated from target selection")


func _test_incident_poisson_rate_against_analytic_interval() -> void:
	var minutes: int = 100000
	var rate_cases: Array[Dictionary] = [
		{"rate": "rare", "lambda": 1.0 / 20.0},
		{"rate": "occasional", "lambda": 1.0 / 8.0},
		{"rate": "lively", "lambda": 1.0 / 3.0}
	]
	for case: Dictionary in rate_cases:
		var scheduler = IncidentScheduler.new(8612, String(case["rate"]), 0, false)
		var stop_tick: int = minutes * 60 * IncidentScheduler.TICK_RATE_HZ
		while scheduler.next_deadline_tick() >= 0 and scheduler.next_deadline_tick() <= stop_tick:
			scheduler.advance_to(scheduler.next_deadline_tick(), [])
		var observed: float = float(scheduler.opportunity_count())
		var exposure_minutes: float = float(minutes) - 1.0
		var mean: float = float(case["lambda"]) * exposure_minutes
		var lower_99: float = mean - 2.576 * sqrt(mean)
		var upper_99: float = mean + 2.576 * sqrt(mean)
		_check(observed >= lower_99 and observed <= upper_99, String(case["rate"]) + " opportunities fall inside the predeclared 99% Poisson interval")


func _test_incident_cooldowns_and_non_crash_guarantee() -> void:
	var scheduler = IncidentScheduler.new(34591, "lively", 0, true)
	var roster: Array[Dictionary] = _many_eligible_pilots(20)
	var stop_tick: int = IncidentScheduler.FIRST_INCIDENT_GRACE_TICKS + 240 * 60 * 2400
	var last_fleet_start: int = -1
	var last_pilot_start: Dictionary = {}
	var observed_starts: int = 0
	while scheduler.next_deadline_tick() >= 0 and scheduler.next_deadline_tick() <= stop_tick:
		var due: int = scheduler.next_deadline_tick()
		var events: Array[Dictionary] = scheduler.advance_to(due, roster, true, true)
		for event: Dictionary in events:
			if String(event.get("type", "")) != "incident_started":
				continue
			var payload: Dictionary = event.get("payload", {})
			var pilot_id: String = String(payload.get("pilot_id", ""))
			observed_starts += 1
			if last_fleet_start >= 0:
				_check(due - last_fleet_start >= IncidentScheduler.MIN_FLEET_INTERVAL_TICKS, "fleet incident starts obey the 120-second minimum")
			if last_pilot_start.has(pilot_id):
				_check(due - int(last_pilot_start[pilot_id]) >= IncidentScheduler.MIN_PILOT_INTERVAL_TICKS, "a pilot obeys the 180-second minimum")
			last_fleet_start = due
			last_pilot_start[pilot_id] = due
			scheduler.complete_incident(due, int(payload.get("opportunity_id", -1)), "fixture_complete")
	var final_state: Dictionary = scheduler.snapshot_state()
	var eligible_starts: int = int(final_state["eligible_start_count"])
	var crash_prone: int = int(final_state["crash_prone_start_count"])
	_check(observed_starts > 100, "cooldown fixture exercises many independent incident opportunities")
	_check(crash_prone <= floori(float(eligible_starts) * 0.25), "crash-prone episodes never exceed 25 percent of eligible starts")
	_check(scheduler.active_incident().is_empty(), "completing an episode leaves no stale active incident")
	var ineligible = IncidentScheduler.new(800, "lively", 0, false)
	var due_no_space: int = ineligible.next_deadline_tick()
	var cancelled: Array[Dictionary] = ineligible.advance_to(due_no_space, _one_eligible_pilot(), true, false)
	_check(_output_has(cancelled, "incident_cancelled", "recovery_space_occupied"), "occupied recovery space cancels and logs the opportunity")
	var next_due: int = ineligible.next_deadline_tick()
	_check(next_due > due_no_space and ineligible.active_incident().is_empty(), "cancelled opportunity is not postponed or converted into a later burst")
	_check(ineligible.advance_to(next_due - 1, _one_eligible_pilot()).is_empty(), "an ineligible attempt does not create an early deferred incident")
	var next_opportunity: Array[Dictionary] = ineligible.advance_to(next_due, _one_eligible_pilot())
	_check(not next_opportunity.is_empty() and not ineligible.active_incident().is_empty() and int(ineligible.active_incident().get("tick", -1)) == next_due, "eligible pilot starts only at the next independently scheduled opportunity")
	var protected = IncidentScheduler.new(801, "lively", 0, false)
	var protected_events: Array[Dictionary] = protected.advance_to(protected.next_deadline_tick(), _one_eligible_pilot(), false, true)
	_check(_output_has(protected_events, "incident_cancelled", "player_protective_volume"), "player protective volume cancels and logs an incident opportunity")
	var off_active = IncidentScheduler.new(802, "lively", 0, false)
	var active_tick: int = off_active.next_deadline_tick()
	var active_events: Array[Dictionary] = off_active.advance_to(active_tick, _one_eligible_pilot())
	var active_id: int = -1
	for event: Dictionary in active_events:
		if String(event.get("type", "")) == "incident_started":
			active_id = int(event.get("payload", {}).get("opportunity_id", -1))
	_check(active_id >= 0, "fixture starts an active incident before Off transition")
	off_active.set_rate("off", active_tick)
	_check(off_active.active_incident().is_empty() and off_active.next_deadline_tick() == -1, "switching Off cancels the active scheduled episode and all future deadlines")


func _reference_runway_order(requests: Array[Dictionary], tick: int, fairness_ticks: int) -> Array[int]:
	var remaining: Array[Dictionary] = []
	for request: Dictionary in requests:
		remaining.append(request.duplicate(true))
	var order: Array[int] = []
	while not remaining.is_empty():
		var best_index: int = 0
		for index: int in range(1, remaining.size()):
			if _reference_request_less(remaining[index], remaining[best_index], tick, fairness_ticks):
				best_index = index
		order.append(int(remaining[best_index]["owner_id"]))
		remaining.remove_at(best_index)
	return order


func _reference_request_less(left: Dictionary, right: Dictionary, tick: int, fairness_ticks: int) -> bool:
	var left_priority: int = _reference_priority(left, tick, fairness_ticks)
	var right_priority: int = _reference_priority(right, tick, fairness_ticks)
	if left_priority != right_priority:
		return left_priority < right_priority
	if int(left["request_tick"]) != int(right["request_tick"]):
		return int(left["request_tick"]) < int(right["request_tick"])
	if int(left["owner_id"]) != int(right["owner_id"]):
		return int(left["owner_id"]) < int(right["owner_id"])
	if int(left["generation"]) != int(right["generation"]):
		return int(left["generation"]) < int(right["generation"])
	return String(left["request_id"]) < String(right["request_id"])


func _reference_priority(request: Dictionary, tick: int, fairness_ticks: int) -> int:
	var base: int
	if bool(request.get("emergency", false)):
		base = 0
	elif bool(request.get("player_request", false)):
		base = 1
	elif String(request.get("operation", "")) == "landing" and bool(request.get("committed_arrival", false)):
		base = 2
	elif String(request.get("operation", "")) == "landing":
		base = 3
	elif String(request.get("operation", "")) == "takeoff" or String(request.get("operation", "")) == "touch_and_go":
		base = 4
	else:
		base = 5
	if base <= 1:
		return base
	var promotions: int = mini(3, floori(float(maxi(0, tick - int(request.get("request_tick", tick)))) / float(fairness_ticks)))
	return maxi(2, base - promotions)


func _events_have(events: Array[Dictionary], event_type: String, reason: String) -> bool:
	for event: Dictionary in events:
		if String(event.get("type", "")) == event_type and String(event.get("payload", {}).get("reason", "")) == reason:
			return true
	return false


func _output_has(events: Array[Dictionary], event_type: String, reason: String) -> bool:
	for event: Dictionary in events:
		if String(event.get("type", "")) == event_type and String(event.get("payload", {}).get("reason", "")) == reason:
			return true
	return false


func _one_eligible_pilot() -> Array[Dictionary]:
	return [{"pilot_id": "pilot-0", "owner_id": 0, "generation": 1, "eligible": true, "episode_options": ["late_throttle", "delayed_flare"], "crash_prone_eligible": true}]


func _many_eligible_pilots(count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in range(count):
		result.append({"pilot_id": "pilot-" + str(index), "owner_id": index, "generation": 1, "eligible": true, "episode_options": ["late_throttle", "bounded_bank"], "crash_prone_eligible": true})
	return result


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	printerr("CHECK FAILED: ", message)

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
	_test_runway_player_incursion_preserves_ai_occupancy()
	_test_runway_wind_reversal_and_envelope_revocation()
	_test_runway_wreck_occupancy_and_serialization()
	_test_activity_quota_fairness_cooldown_and_eligibility()
	_test_activity_weighted_choice_and_replay_state()
	_test_activity_restore_is_strict_and_transactional()
	_test_incidents_off_and_grace()
	_test_incident_timeout_and_snapshot_validation()
	_test_incident_deadlines_ignore_frame_and_fleet_size()
	_test_incident_filtered_outcomes_match_independent_reference()
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
	_check(String(coordinator.snapshot_state()["mode"]) == "occupied", "player runway exit stays occupied until footprint geometry is reported clear")
	coordinator.report_clearance(8, 0, 8, true, false)
	_check(String(coordinator.snapshot_state()["mode"]) == "clearing", "protected arrival/departure volume still retains the strip")
	coordinator.report_clearance(9, 0, 8, true, true)
	_check(String(coordinator.snapshot_state()["mode"]) == "free", "player occupancy clears after both geometric checks pass")


func _test_runway_player_incursion_preserves_ai_occupancy() -> void:
	var ai_remains = Runway.new()
	ai_remains.submit_request(0, "ai-remains", 41, 3, "pilot-41", "landing")
	var ai_grant: Dictionary = ai_remains.resolve(0).get("grant", {})
	_check(bool(ai_remains.enter_runway(1, int(ai_grant.get("ticket", -1)), 41, 3).get("ok", false)), "AI occupies runway before player incursion")
	ai_remains.observe_player(2, 0, 9, true, false)
	var overlap: Dictionary = ai_remains.snapshot_state()
	_check(String(overlap["mode"]) == "occupied" and overlap["physical_blockers"].size() == 2 and overlap["physical_blockers"].has("41:3") and overlap["physical_blockers"].has("0:9"), "player incursion records a second physical blocker without replacing the occupying AI")
	_check(bool(overlap["player_in_runway"]) and int(overlap["player_owner_id"]) == 0 and int(overlap["player_generation"]) == 9, "overlap snapshot identifies both physical occupants")
	var restored_overlap = Runway.new()
	_check(bool(restored_overlap.restore_state(overlap).get("ok", false)) and restored_overlap.snapshot_state() == overlap, "overlapping player and AI occupancy survives a deterministic checkpoint")
	ai_remains.observe_player(3, 0, 9, false, false)
	ai_remains.report_clearance(3, 0, 9, true, false)
	_check(String(ai_remains.snapshot_state()["mode"]) == "occupied" and ai_remains.snapshot_state()["physical_blockers"].has("0:9"), "player footprint clearance does not hide the still-present AI runway occupant")
	_check(bool(ai_remains.report_clearance(4, 41, 3, true, true).get("cleared", false)), "AI geometric clearance removes only the AI physical blocker")
	_check(String(ai_remains.snapshot_state()["mode"]) == "clearing" and ai_remains.snapshot_state()["physical_blockers"].has("0:9"), "AI clearance cannot free the strip while the player's protected path remains occupied")
	_check(bool(ai_remains.report_clearance(5, 0, 9, true, true).get("cleared", false)), "player path clearance removes the final overlap blocker")
	_check(String(ai_remains.snapshot_state()["mode"]) == "free" and int(ai_remains.snapshot_state()["player_owner_id"]) == -1, "last blocker clearance returns the runway to a clean free state")

	var player_remains = Runway.new()
	player_remains.submit_request(0, "ai-clears-first", 42, 1, "pilot-42", "takeoff")
	var second_grant: Dictionary = player_remains.resolve(0).get("grant", {})
	player_remains.enter_runway(1, int(second_grant.get("ticket", -1)), 42, 1)
	player_remains.observe_player(2, 0, 10, true, false)
	var ai_clearance: Dictionary = player_remains.report_clearance(3, 42, 1, true, true)
	_check(bool(ai_clearance.get("cleared", false)) and String(ai_clearance.get("mode", "")) == "occupied", "AI clearance removes only its own blocker while the player remains on the strip")
	_check(player_remains.snapshot_state()["physical_blockers"].has("0:10"), "the player's independent physical blocker survives AI clearance")
	player_remains.observe_player(4, 0, 10, false, false)
	player_remains.report_clearance(4, 0, 10, true, false)
	_check(String(player_remains.snapshot_state()["mode"]) == "clearing", "player exit after AI clearance still waits for player geometry")
	_check(bool(player_remains.report_clearance(5, 0, 10, true, true).get("cleared", false)), "player geometry is the final required clearance when the AI left first")
	_check(String(player_remains.snapshot_state()["mode"]) == "free" and int(player_remains.snapshot_state()["player_generation"]) == -1, "player-last clearance removes the player blocker identity")


func _test_runway_wind_reversal_and_envelope_revocation() -> void:
	var coordinator = Runway.new()
	coordinator.update_wind(0, 5.0, 2.0, 4.0)
	# This abstract envelope explicitly permits 5 m/s tailwind to isolate the
	# direction-hysteresis behavior; real aircraft admission owns its profile limit.
	coordinator.submit_request(0, "takeoff-limited", 12, 1, "pilot-12", "takeoff", 0, false, false, false, "departure-east", -1, -1, 3.0, 5.0, [], 5.0)
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
	occupied.observe_player(2401, 0, 1, false, false)
	occupied.report_clearance(2401, 0, 1, true, true)
	var now_clear: Dictionary = occupied.update_wind(2402, -3.0, 0.0, 0.0)
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
	var live_ai = Runway.new()
	live_ai.submit_request(0, "live-ai", 51, 4, "pilot-51", "landing")
	var live_grant: Dictionary = live_ai.resolve(0).get("grant", {})
	live_ai.enter_runway(1, int(live_grant.get("ticket", -1)), 51, 4)
	live_ai.report_runway_wreck(2, 52, 1, "pilot-52", "foreign-wreck", "arrival-west")
	var mixed_blockers: Dictionary = live_ai.snapshot_state()
	_check(String(mixed_blockers["mode"]) == "blocked" and mixed_blockers["physical_blockers"].has("51:4") and mixed_blockers["blocked_wrecks"].has("foreign-wreck"), "a foreign wreck adds a blocker without replacing the live AI occupant")
	var foreign_removed: Dictionary = live_ai.clear_wreck_and_occupancy(3, "foreign-wreck", true)
	_check(bool(foreign_removed.get("ok", false)) and String(foreign_removed.get("mode", "")) == "occupied" and live_ai.snapshot_state()["physical_blockers"].has("51:4"), "removing the foreign wreck leaves the live AI physical blocker intact")
	_check(not bool(live_ai.resolve(4).get("granted", false)), "a surviving AI blocker still denies runway reservations after wreck cleanup")
	_check(bool(live_ai.report_clearance(5, 51, 4, true, true).get("cleared", false)) and String(live_ai.snapshot_state()["mode"]) == "free", "the live AI's own geometric clearance removes the final blocker")


func _test_activity_quota_fairness_cooldown_and_eligibility() -> void:
	var scheduler = ActivityScheduler.new(700)
	for agent_id: int in [3, 1, 2]:
		var queued: Dictionary = scheduler.request_activity(0, "box-" + str(agent_id), "pilot-" + str(agent_id), agent_id, 1, "loop", "box-a", 1.0, 1, 20, 60)
		_check(bool(queued.get("ok", false)), "eligible maneuver request enters bounded queue")
	var first_result: Dictionary = scheduler.resolve(0, _activity_eligibility(["box-1", "box-2", "box-3"]))
	var grants: Array = first_result.get("granted", [])
	_check(grants.size() == 1 and int(grants[0].get("owner_id", -1)) == 1, "quota one grants the oldest stable request only")
	_check(not bool(scheduler.complete_activity(10, 1, 1, "loop").get("ok", false)), "minimum activity duration prevents an early normal completion")
	_check(bool(scheduler.complete_activity(10, 1, 1, "loop", "recovery", true).get("ok", false)), "safety recovery may preempt the activity immediately")
	var second: Array = scheduler.resolve(10, _activity_eligibility(["box-2", "box-3"])).get("granted", [])
	_check(second.size() == 1 and int(second[0].get("owner_id", -1)) == 2, "oldest feasible queued agent receives the next released quota")
	_check(not bool(scheduler.request_activity(10, "loop-again", "pilot-1", 1, 1, "loop", "box-a", 1.0, 1, 20, 60).get("ok", false)), "completed activity cooldown prevents immediate repeat")
	var wrong_generation: Dictionary = scheduler.complete_activity(40, 2, 2, "loop")
	_check(not bool(wrong_generation.get("ok", false)), "stale generation cannot finish a current activity lease")
	_check(bool(scheduler.complete_activity(40, 2, 1, "loop").get("ok", false)), "lease completes after its minimum duration")
	var third: Array = scheduler.resolve(40, _activity_eligibility(["box-3"])).get("granted", [])
	_check(third.size() == 1 and int(third[0].get("owner_id", -1)) == 3, "third queued agent receives quota without starvation")
	var refused: Dictionary = scheduler.request_activity(41, "unsupported-roll", "pilot-4", 4, 1, "roll", "box-a", 1.0, 1, 0, 0, 0, false, "profile_not_qualified")
	_check(not bool(refused.get("ok", false)) and String(refused.get("reason", "")) == "profile_not_qualified", "unsupported activity records its eligibility reason")
	var cancelled = ActivityScheduler.new(10)
	cancelled.request_activity(0, "energy-choice", "pilot-5", 5, 1, "loop", "box-a", 1.0, 1, 0, 0)
	var pending_before_missing: Dictionary = cancelled.snapshot_state()
	var missing_map: Dictionary = cancelled.resolve(0)
	_check(not bool(missing_map.get("ok", true)) and String(missing_map.get("reason", "")) == "grant_eligibility_missing", "omitted grant-time eligibility refuses the entire resolve boundary")
	_check(cancelled.snapshot_state() == pending_before_missing, "missing eligibility leaves queue, lease state, RNG, and events unchanged")
	var partial = ActivityScheduler.new(12)
	partial.request_activity(0, "first", "pilot-first", 15, 1, "loop", "box-a", 1.0, 1, 0, 0)
	partial.request_activity(0, "second", "pilot-second", 16, 1, "loop", "box-a", 1.0, 1, 0, 0)
	var partial_before: Dictionary = partial.snapshot_state()
	var partial_result: Dictionary = partial.resolve(0, {"first": {"eligible": true}})
	_check(not bool(partial_result.get("ok", true)) and String(partial_result.get("request_id", "")) == "second", "partial eligibility map names the pending request that lacks revalidation")
	_check(partial.snapshot_state() == partial_before, "partial eligibility map cannot partially grant or cancel another request")
	var malformed_result: Dictionary = partial.resolve(0, {"first": {"eligible": 1}, "second": {"eligible": true}})
	_check(not bool(malformed_result.get("ok", true)) and String(malformed_result.get("reason", "")) == "grant_eligibility_update_invalid", "grant-time eligibility accepts only an explicit boolean")
	_check(partial.snapshot_state() == partial_before, "malformed eligibility map leaves the full pending boundary unchanged")
	var canceled_result: Dictionary = cancelled.resolve(0, {"energy-choice": {"eligible": false, "reason": "energy_below_entry_gate"}})
	_check(canceled_result.get("granted", []).is_empty(), "eligibility is rechecked at the grant boundary")
	_check(not canceled_result.get("cancelled", []).is_empty() and String(canceled_result["cancelled"][0].get("reason", "")) == "energy_below_entry_gate", "grant-time refusal logs the explicit energy reason")
	var independent = ActivityScheduler.new(11)
	independent.request_activity(0, "circuit", "pilot-6", 6, 1, "circuit", "circuit-lane", 1.0, 3, 0, 0)
	independent.request_activity(0, "show-box", "pilot-7", 7, 1, "loop", "box-b", 1.0, 1, 0, 0)
	_check(independent.resolve(0, _activity_eligibility(["circuit", "show-box"])).get("granted", []).size() == 2, "different quota resources can host independent concurrent activities")
	var replaced_generation: Dictionary = independent.request_activity(1, "next-sortie", "pilot-6", 6, 2, "circuit", "circuit-lane", 1.0, 3, 0, 0)
	_check(bool(replaced_generation.get("ok", false)), "new sortie generation is distinct from the previous active lease")
	independent.retire_agent(1, 6, 1, "old_generation_retired")
	_check(independent.resolve(1, _activity_eligibility(["next-sortie"])).get("granted", []).size() == 1, "old-generation retirement releases its slot without touching the new generation")
	var bounded = ActivityScheduler.new(3, 8, 8, 1)
	bounded.request_activity(0, "lane-one", "pilot-20", 20, 1, "circuit", "lane-one", 1.0, 1, 0, 0)
	bounded.request_activity(0, "lane-two", "pilot-21", 21, 1, "pass", "lane-two", 1.0, 1, 0, 0)
	_check(bounded.resolve(0, _activity_eligibility(["lane-one", "lane-two"])).get("granted", []).size() == 1 and bounded.snapshot_state()["active"].size() == 1, "active activity leases obey the hard fleet bound across independent resources")


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


func _test_activity_restore_is_strict_and_transactional() -> void:
	var source = ActivityScheduler.new(5544, 8, 32, 1)
	source.request_activity(0, "cooldown-source", "pilot-one", 1, 1, "loop", "lane-one", 1.0, 1, 0, 12)
	source.resolve(0, _activity_eligibility(["cooldown-source"]))
	source.complete_activity(0, 1, 1, "loop")
	source.request_activity(1, "active-lease", "pilot-two", 2, 4, "circuit", "lane-two", 1.5, 1, 8, 20)
	source.request_activity(1, "pending-one", "pilot-three", 3, 2, "pass", "lane-three", 2.0, 1, 0, 0)
	source.resolve(1, _activity_eligibility(["active-lease", "pending-one"]))
	source.request_activity(2, "pending-two", "pilot-four", 4, 1, "loop", "lane-four", 1.0, 1, 0, 0)
	var valid_snapshot: Dictionary = source.snapshot_state()
	var roundtrip = ActivityScheduler.new(9)
	_check(bool(roundtrip.restore_state(valid_snapshot).get("ok", false)) and roundtrip.snapshot_state() == valid_snapshot,
		"strict activity snapshot restores active and pending leases, cooldowns, events, and RNG exactly")
	var transported: Variant = bytes_to_var(var_to_bytes(valid_snapshot))
	var binary_roundtrip = ActivityScheduler.new(10)
	_check(transported is Dictionary and bool(binary_roundtrip.restore_state(transported).get("ok", false))
		and binary_roundtrip.snapshot_state() == valid_snapshot, "activity checkpoint survives lossless native Variant binary transport")

	var active_key: String = String(valid_snapshot["active"].keys()[0])
	var malformed: Array[Dictionary] = []
	var bad: Dictionary = valid_snapshot.duplicate(true)
	bad["active"][active_key]["owner_id"] = float(bad["active"][active_key]["owner_id"])
	malformed.append(bad)
	bad = valid_snapshot.duplicate(true)
	bad["active"][active_key]["generation"] = -1
	malformed.append(bad)
	bad = valid_snapshot.duplicate(true)
	bad["active"][active_key]["weight"] = NAN
	malformed.append(bad)
	bad = valid_snapshot.duplicate(true)
	var moved_lease: Dictionary = bad["active"].get(active_key).duplicate(true)
	bad["active"].erase(active_key)
	bad["active"]["999:1"] = moved_lease
	malformed.append(bad)
	bad = valid_snapshot.duplicate(true)
	bad["pending"][0]["priority"] = 1.5
	malformed.append(bad)
	bad = valid_snapshot.duplicate(true)
	bad["pending"][1]["request_sequence"] = bad["pending"][0]["request_sequence"]
	malformed.append(bad)
	bad = valid_snapshot.duplicate(true)
	bad["active"][active_key]["unexpected"] = {"nested": [1, 2, 3]}
	malformed.append(bad)
	bad = valid_snapshot.duplicate(true)
	var last_event: Dictionary = bad["events"].back()
	last_event["payload"]["owner_id"] = 1.25
	bad["events"][bad["events"].size() - 1] = last_event
	malformed.append(bad)
	bad = valid_snapshot.duplicate(true)
	var cooldown_key: String = String(bad["cooldown_until"].keys()[0])
	bad["cooldown_until"][cooldown_key] = float(bad["cooldown_until"][cooldown_key])
	malformed.append(bad)
	var rejected_transactionally := true
	for candidate: Dictionary in malformed:
		var guard = ActivityScheduler.new(777, 8, 32, 1)
		guard.request_activity(0, "guard-pending", "guard-pilot", 70, 1, "loop", "guard-lane", 1.0, 1, 0, 0)
		var before: Dictionary = guard.snapshot_state()
		var result: Dictionary = guard.restore_state(candidate)
		rejected_transactionally = rejected_transactionally and not bool(result.get("ok", true)) and guard.snapshot_state() == before
	_check(rejected_transactionally, "malformed activity snapshots reject without numeric coercion or partial mutation")


func _test_incidents_off_and_grace() -> void:
	var off = IncidentScheduler.new(501, "off", 0, true)
	var before: Dictionary = off.snapshot_state()
	var output: Array = off.advance_to(100000000, _one_eligible_pilot()).get("events", [])
	var after: Dictionary = off.snapshot_state()
	_check(output.is_empty() and off.opportunity_count() == 0, "Off produces no opportunities regardless of elapsed ticks")
	_check(int(before["time_rng_state"]) == int(after["time_rng_state"]) and int(after["next_deadline_tick"]) == -1, "Off does not consume timing RNG or retain a scheduled deadline")
	var signed_rng_restore = IncidentScheduler.new(1)
	_check(int(before["severity_rng_state"]) < 0 and bool(signed_rng_restore.restore_state(before).get("ok", false)), "lossless signed engine RNG state restores without integer coercion")
	var grace = IncidentScheduler.new(502, "lively", 0, false)
	_check(grace.next_deadline_tick() > IncidentScheduler.FIRST_INCIDENT_GRACE_TICKS, "first Poisson opportunity follows the 60-second fleet grace period")
	var early: Array = grace.advance_to(IncidentScheduler.FIRST_INCIDENT_GRACE_TICKS, _one_eligible_pilot()).get("events", [])
	_check(early.is_empty() and grace.opportunity_count() == 0, "no scheduled incidents can occur inside the first-minute grace")
	var toggled = IncidentScheduler.new(503, "rare", 0, false)
	var toggle_result: Dictionary = toggled.set_rate("off", 10)
	_check(bool(toggle_result.get("ok", false)) and toggled.next_deadline_tick() == -1 and int(toggled.snapshot_state()["last_advanced_tick"]) == 10, "settings changes are recorded at their accepted scheduler tick")
	var toggle_restore = IncidentScheduler.new(1)
	_check(bool(toggle_restore.restore_state(toggled.snapshot_state()).get("ok", false)), "settings event snapshots preserve clock and deadline invariants")
	var due_guard = IncidentScheduler.new(508, "rare", 0, false)
	var due_guard_before: Dictionary = due_guard.snapshot_state()
	var deadline_settings_result: Dictionary = due_guard.set_rate("off", due_guard.next_deadline_tick())
	_check(not bool(deadline_settings_result.get("ok", true)) and String(deadline_settings_result.get("reason", "")) == "opportunity_deadline_missed" and due_guard.snapshot_state() == due_guard_before, "rate changes cannot silently discard an opportunity at its exact deadline")
	var active_checkpoint = IncidentScheduler.new(504, "lively", 0, false)
	var due: int = active_checkpoint.next_deadline_tick()
	active_checkpoint.advance_to(due, _one_eligible_pilot())
	var checkpoint: Dictionary = active_checkpoint.snapshot_state()
	var restored = IncidentScheduler.new(1)
	_check(bool(restored.restore_state(checkpoint).get("ok", false)), "incident timing, active episode, cooldowns, and RNG restore from serializable state")
	_check(restored.snapshot_state() == checkpoint, "incident restore retains exact point-process state")
	var checkpoint_transport: PackedByteArray = var_to_bytes(checkpoint)
	var transported: Variant = bytes_to_var(checkpoint_transport)
	_check(transported is Dictionary and bool(restored.restore_state(transported).get("ok", false)), "native Variant binary transport preserves the checkpoint dictionary")
	var next_due: int = active_checkpoint.next_deadline_tick()
	var source_continuation: Dictionary = active_checkpoint.advance_to(next_due, _one_eligible_pilot())
	var restored_continuation: Dictionary = restored.advance_to(next_due, _one_eligible_pilot())
	_check(source_continuation == restored_continuation and active_checkpoint.snapshot_state() == restored.snapshot_state(), "binary-restored checkpoint continues with the same deadline, events and RNG states")


func _test_incident_timeout_and_snapshot_validation() -> void:
	var scheduler = IncidentScheduler.new(909, "lively", 0, false)
	var due: int = scheduler.next_deadline_tick()
	var start_events: Array = scheduler.advance_to(due, _one_eligible_pilot()).get("events", [])
	var started: Dictionary = {}
	for event: Dictionary in start_events:
		if String(event.get("type", "")) == "incident_started":
			started = event
	var start_payload: Dictionary = started.get("payload", {})
	var active: Dictionary = scheduler.active_incident()
	var family_id: String = String(start_payload.get("episode_family", ""))
	var family_classified: bool = false
	for family: Dictionary in _one_eligible_pilot()[0]["episode_families"]:
		if String(family.get("family_id", "")) == family_id:
			family_classified = bool(family.get("crash_prone", true)) == bool(start_payload.get("crash_prone", true))
	_check(not started.is_empty() and family_classified, "started incident carries the classification of its selected family")
	_check(int(active.get("deadline_tick", -1)) == due + IncidentScheduler.DEFAULT_MAX_EPISODE_DURATION_TICKS, "episode checkpoint has a fixed bounded tick deadline")
	var active_state: Dictionary = scheduler.snapshot_state()
	var short_episode = IncidentScheduler.new(911, "rare", 0, false, IncidentScheduler.DEFAULT_MAX_EVENTS, 1)
	var short_due: int = short_episode.next_deadline_tick()
	short_episode.advance_to(short_due, _one_eligible_pilot())
	var short_active: Dictionary = short_episode.active_incident()
	var timeout_result: Dictionary = short_episode.advance_to(int(short_active["deadline_tick"]), [])
	_check(bool(timeout_result.get("ok", false)) and short_episode.active_incident().is_empty(), "episode deadline cancels an uncompleted episode on its bounded tick")
	var late_completion: Dictionary = short_episode.complete_incident(int(short_active["deadline_tick"]), int(short_active["opportunity_id"]), "late_completion")
	_check(not bool(late_completion.get("ok", false)), "a timed-out episode cannot later be reported as completed")
	var timeout_events: Array[Dictionary] = timeout_result.get("events", [])
	var timeout_was_recovery_only: bool = false
	for event: Dictionary in timeout_events:
		var payload: Dictionary = event.get("payload", {})
		if String(event.get("type", "")) == "incident_cancelled" and String(payload.get("reason", "")) == "episode_timeout":
			timeout_was_recovery_only = bool(payload.get("recovery_required", false))
	_check(timeout_was_recovery_only, "timeout is a recovery-required cancellation, never a claim that physical recovery succeeded")
	var timeout_restore = IncidentScheduler.new(1)
	_check(bool(timeout_restore.restore_state(short_episode.snapshot_state()).get("ok", false)), "timeout cancellation and its family classification survive strict checkpoint restore")

	var guard = IncidentScheduler.new(910, "off", 0, false)
	var guard_before: Dictionary = guard.snapshot_state()
	var valid_state: Dictionary = active_state
	var fractional_tick: Dictionary = valid_state.duplicate(true)
	fractional_tick["start_tick"] = 1.5
	_check(not bool(guard.restore_state(fractional_tick).get("ok", false)) and guard.snapshot_state() == guard_before, "fractional snapshot tick is rejected without mutating the target")
	var negative_active_identity: Dictionary = valid_state.duplicate(true)
	negative_active_identity["active"]["owner_id"] = -1
	_check(not bool(guard.restore_state(negative_active_identity).get("ok", false)) and guard.snapshot_state() == guard_before, "negative active identity is rejected without mutation")
	var floating_rng_state: Dictionary = valid_state.duplicate(true)
	floating_rng_state["time_rng_state"] = float(valid_state["time_rng_state"])
	_check(not bool(guard.restore_state(floating_rng_state).get("ok", false)) and guard.snapshot_state() == guard_before, "floating RNG state is rejected without mutation")
	var negative_tick: Dictionary = valid_state.duplicate(true)
	negative_tick["last_advanced_tick"] = -2
	_check(not bool(guard.restore_state(negative_tick).get("ok", false)) and guard.snapshot_state() == guard_before, "negative scheduler tick is rejected without mutation")
	var negative_event_identity: Dictionary = valid_state.duplicate(true)
	var malformed_started_event: Dictionary = negative_event_identity["events"].back()
	malformed_started_event["payload"]["owner_id"] = -1
	negative_event_identity["events"][negative_event_identity["events"].size() - 1] = malformed_started_event
	_check(not bool(guard.restore_state(negative_event_identity).get("ok", false)) and guard.snapshot_state() == guard_before, "negative event identity is rejected without mutation")
	var fractional_event_tick: Dictionary = valid_state.duplicate(true)
	var malformed_event_tick: Dictionary = fractional_event_tick["events"].back()
	malformed_event_tick["tick"] = float(malformed_event_tick["tick"]) + 0.5
	fractional_event_tick["events"][fractional_event_tick["events"].size() - 1] = malformed_event_tick
	_check(not bool(guard.restore_state(fractional_event_tick).get("ok", false)) and guard.snapshot_state() == guard_before, "fractional event tick is rejected without mutation")


func _test_incident_deadlines_ignore_frame_and_fleet_size() -> void:
	var baseline = IncidentScheduler.new(5555, "occasional", 0, false)
	var frame_grouped = IncidentScheduler.new(5555, "occasional", 0, false)
	var one_aircraft = IncidentScheduler.new(5555, "occasional", 0, false)
	var many_aircraft = IncidentScheduler.new(5555, "occasional", 0, false)
	var stop_tick: int = IncidentScheduler.FIRST_INCIDENT_GRACE_TICKS + 240 * 60 * 90
	var late_context_rejected: bool = true
	while baseline.next_deadline_tick() >= 0 and baseline.next_deadline_tick() <= stop_tick:
		var due: int = baseline.next_deadline_tick()
		var expected: Dictionary = baseline.advance_to(due, [])
		var frame_state_before: Dictionary = frame_grouped.snapshot_state()
		var late: Dictionary = frame_grouped.advance_to(due + 1, [])
		late_context_rejected = late_context_rejected and not bool(late.get("ok", true)) and frame_grouped.snapshot_state() == frame_state_before
		var exact: Dictionary = frame_grouped.advance_to(due, [])
		late_context_rejected = late_context_rejected and bool(expected.get("ok", false)) and bool(exact.get("ok", false))
	var roster_one: Array[Dictionary] = _one_eligible_pilot()
	var roster_many: Array[Dictionary] = _many_eligible_pilots(32)
	while one_aircraft.next_deadline_tick() >= 0 and one_aircraft.next_deadline_tick() <= stop_tick:
		var due_one: int = one_aircraft.next_deadline_tick()
		for event: Dictionary in one_aircraft.advance_to(due_one, roster_one).get("events", []):
			if String(event.get("type", "")) == "incident_started":
				_check(not bool(event.get("payload", {}).get("crash_prone", true)), "disabled crash-prone policy excludes every crash-prone family")
				one_aircraft.complete_incident(due_one, int(event.get("payload", {}).get("opportunity_id", -1)), "fixture_complete")
	while many_aircraft.next_deadline_tick() >= 0 and many_aircraft.next_deadline_tick() <= stop_tick:
		var due_many: int = many_aircraft.next_deadline_tick()
		for event: Dictionary in many_aircraft.advance_to(due_many, roster_many).get("events", []):
			if String(event.get("type", "")) == "incident_started":
				many_aircraft.complete_incident(due_many, int(event.get("payload", {}).get("opportunity_id", -1)), "fixture_complete")
	_check(late_context_rejected and baseline.opportunity_count() == frame_grouped.opportunity_count(), "late frame snapshots reject atomically; opportunities require their exact fixed tick")
	_check(int(baseline.snapshot_state()["next_deadline_tick"]) == int(frame_grouped.snapshot_state()["next_deadline_tick"]), "rejected late context preserves the exact next deadline")
	_check(baseline.opportunity_count() == one_aircraft.opportunity_count() and baseline.opportunity_count() == many_aircraft.opportunity_count(), "fleet opportunity count is independent of one or 32 aircraft")
	_check(int(baseline.snapshot_state()["next_deadline_tick"]) == int(one_aircraft.snapshot_state()["next_deadline_tick"]) and int(one_aircraft.snapshot_state()["next_deadline_tick"]) == int(many_aircraft.snapshot_state()["next_deadline_tick"]), "selection from different fleet sizes does not perturb future timing draws")
	_check(one_aircraft.snapshot_state()["time_rng_state"] == many_aircraft.snapshot_state()["time_rng_state"], "incident timing RNG is isolated from target selection")


func _test_incident_filtered_outcomes_match_independent_reference() -> void:
	const TEST_SEED: int = 9137
	const OPPORTUNITY_LIMIT: int = 2000
	var scheduler = IncidentScheduler.new(TEST_SEED, "lively", 0, false)
	var reference_pilot_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	reference_pilot_rng.seed = int(((TEST_SEED * 48271 + 31) % 2147483646) + 1)
	var reference_last_fleet_start: int = -1
	var reference_last_pilot_start: Dictionary = {}
	var reference_active_id: int = -1
	var reference_active_deadline: int = -1
	var expected_opportunity_id: int = 0
	while expected_opportunity_id < OPPORTUNITY_LIMIT:
		var due: int = scheduler.next_deadline_tick()
		expected_opportunity_id += 1
		var timed_out_active_id: int = -1
		if reference_active_id >= 0 and due >= reference_active_deadline:
			timed_out_active_id = reference_active_id
			reference_active_id = -1
			reference_active_deadline = -1
		var player_clear: bool = expected_opportunity_id % 17 != 0
		var recovery_clear: bool = expected_opportunity_id % 23 != 0
		var roster: Array[Dictionary] = _reference_incident_roster(expected_opportunity_id)
		var expected_reason: String = ""
		var expected_pilot_id: String = ""
		if not player_clear:
			expected_reason = "player_protective_volume"
		elif not recovery_clear:
			expected_reason = "recovery_space_occupied"
		elif reference_active_id >= 0:
			expected_reason = "incident_already_active"
		elif reference_last_fleet_start >= 0 and due - reference_last_fleet_start < IncidentScheduler.MIN_FLEET_INTERVAL_TICKS:
			expected_reason = "fleet_cooldown"
		else:
			var eligible_candidates: Array[Dictionary] = []
			var saw_eligible: bool = false
			var saw_cooldown: bool = false
			for pilot: Dictionary in roster:
				if not bool(pilot["eligible"]):
					continue
				saw_eligible = true
				var pilot_id: String = String(pilot["pilot_id"])
				var prior_tick: int = int(reference_last_pilot_start.get(pilot_id, -1))
				if prior_tick >= 0 and due - prior_tick < IncidentScheduler.MIN_PILOT_INTERVAL_TICKS:
					saw_cooldown = true
					continue
				eligible_candidates.append(pilot)
			eligible_candidates.sort_custom(_reference_pilot_less)
			if eligible_candidates.is_empty():
				expected_reason = "pilot_cooldown" if saw_eligible and saw_cooldown else "no_eligible_pilot"
			else:
				var selected: Dictionary = eligible_candidates[reference_pilot_rng.randi_range(0, eligible_candidates.size() - 1)]
				expected_pilot_id = String(selected["pilot_id"])
		var previous_active_id: int = reference_active_id
		var advance_result: Dictionary = scheduler.advance_to(due, roster, player_clear, recovery_clear)
		var events: Array = advance_result.get("events", [])
		_check(bool(advance_result.get("ok", false)), "filtered reference advances only with an exact opportunity snapshot")
		var actual_outcome: Dictionary = {}
		var actual_timeout: Dictionary = {}
		for event: Dictionary in events:
			if String(event.get("type", "")) == "incident_cancelled" and String(event.get("payload", {}).get("reason", "")) == "episode_timeout":
				actual_timeout = event
			if String(event.get("type", "")) == "incident_started" or String(event.get("type", "")) == "incident_cancelled":
				actual_outcome = event
		_check((timed_out_active_id >= 0) == (not actual_timeout.is_empty()), "active episode expiry occurs on its bounded tick deadline")
		if expected_reason.is_empty():
			var actual_payload: Dictionary = actual_outcome.get("payload", {})
			_check(String(actual_outcome.get("type", "")) == "incident_started" and String(actual_payload.get("pilot_id", "")) == expected_pilot_id, "filtered incident reference matches each selected pilot in sorted deterministic order")
			reference_last_fleet_start = due
			reference_last_pilot_start[expected_pilot_id] = due
			reference_active_id = expected_opportunity_id
			reference_active_deadline = due + IncidentScheduler.DEFAULT_MAX_EPISODE_DURATION_TICKS
		else:
			var actual_payload: Dictionary = actual_outcome.get("payload", {})
			_check(String(actual_outcome.get("type", "")) == "incident_cancelled" and String(actual_payload.get("reason", "")) == expected_reason, "filtered incident reference matches each cancellation reason")
		if previous_active_id >= 0 and timed_out_active_id < 0:
			_check(bool(scheduler.complete_incident(due, previous_active_id, "reference_fixture_release").get("ok", false)), "reference fixture releases the prior active episode after this opportunity")
			if reference_active_id == previous_active_id:
				reference_active_id = -1
				reference_active_deadline = -1
	_check(scheduler.opportunity_count() == OPPORTUNITY_LIMIT, "independent filtered comparison covers the declared opportunity count")


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
		var events: Array = scheduler.advance_to(due, roster, true, true).get("events", [])
		for event: Dictionary in events:
			if String(event.get("type", "")) != "incident_started":
				continue
			var payload: Dictionary = event.get("payload", {})
			var pilot_id: String = String(payload.get("pilot_id", ""))
			var family_is_classified: bool = false
			for pilot: Dictionary in roster:
				if String(pilot.get("pilot_id", "")) != pilot_id:
					continue
				for family: Dictionary in pilot.get("episode_families", []):
					if String(family.get("family_id", "")) == String(payload.get("episode_family", "")):
						family_is_classified = bool(family.get("crash_prone", true)) == bool(payload.get("crash_prone", true))
			_check(family_is_classified, "incident family event preserves its authored crash-prone classification")
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
	var cancelled: Array = ineligible.advance_to(due_no_space, _one_eligible_pilot(), true, false).get("events", [])
	_check(_output_has(cancelled, "incident_cancelled", "recovery_space_occupied"), "occupied recovery space cancels and logs the opportunity")
	var next_due: int = ineligible.next_deadline_tick()
	_check(next_due > due_no_space and ineligible.active_incident().is_empty(), "cancelled opportunity is not postponed or converted into a later burst")
	_check(ineligible.advance_to(next_due - 1, _one_eligible_pilot()).get("events", []).is_empty(), "an ineligible attempt does not create an early deferred incident")
	var next_opportunity: Array = ineligible.advance_to(next_due, _one_eligible_pilot()).get("events", [])
	_check(not next_opportunity.is_empty() and not ineligible.active_incident().is_empty() and int(ineligible.active_incident().get("tick", -1)) == next_due, "eligible pilot starts only at the next independently scheduled opportunity")
	var malformed_family_scheduler = IncidentScheduler.new(803, "lively", 0, false)
	var malformed_family_roster: Array[Dictionary] = _one_eligible_pilot()
	malformed_family_roster[0]["episode_families"] = [{"family_id": "unclassified", "crash_prone": 1}]
	var malformed_family_events: Array = malformed_family_scheduler.advance_to(malformed_family_scheduler.next_deadline_tick(), malformed_family_roster).get("events", [])
	_check(_output_has(malformed_family_events, "incident_cancelled", "no_eligible_episode_family"), "malformed incident family classification refuses the opportunity")
	var protected = IncidentScheduler.new(801, "lively", 0, false)
	var protected_events: Array = protected.advance_to(protected.next_deadline_tick(), _one_eligible_pilot(), false, true).get("events", [])
	_check(_output_has(protected_events, "incident_cancelled", "player_protective_volume"), "player protective volume cancels and logs an incident opportunity")
	var off_active = IncidentScheduler.new(802, "lively", 0, false)
	var active_tick: int = off_active.next_deadline_tick()
	var active_events: Array = off_active.advance_to(active_tick, _one_eligible_pilot()).get("events", [])
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


func _reference_pilot_less(left: Dictionary, right: Dictionary) -> bool:
	var left_id: String = String(left.get("pilot_id", ""))
	var right_id: String = String(right.get("pilot_id", ""))
	if left_id != right_id:
		return left_id < right_id
	if int(left.get("owner_id", -1)) != int(right.get("owner_id", -1)):
		return int(left.get("owner_id", -1)) < int(right.get("owner_id", -1))
	return int(left.get("generation", -1)) < int(right.get("generation", -1))


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
	return [{"pilot_id": "pilot-0", "owner_id": 0, "generation": 1, "eligible": true, "episode_families": [{"family_id": "late_throttle", "crash_prone": false}, {"family_id": "delayed_flare", "crash_prone": false}, {"family_id": "one_roll_too_many", "crash_prone": true}], "crash_prone_eligible": true}]


func _many_eligible_pilots(count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in range(count):
		result.append({"pilot_id": "pilot-" + str(index), "owner_id": index, "generation": 1, "eligible": true, "episode_families": [{"family_id": "bounded_bank", "crash_prone": false}, {"family_id": "late_throttle", "crash_prone": false}, {"family_id": "one_roll_too_many", "crash_prone": true}], "crash_prone_eligible": true})
	return result


func _reference_incident_roster(opportunity_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for offset: int in range(4):
		var index: int = offset if opportunity_id % 2 == 0 else 3 - offset
		result.append({"pilot_id": "oracle-" + str(index), "owner_id": index, "generation": 1, "eligible": (opportunity_id + index * 3) % 5 != 0, "episode_families": [{"family_id": "normal", "crash_prone": false}], "crash_prone_eligible": false})
	return result


func _activity_eligibility(request_ids: Array) -> Dictionary:
	var result: Dictionary = {}
	for request_id: Variant in request_ids:
		result[String(request_id)] = {"eligible": true}
	return result


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	printerr("CHECK FAILED: ", message)

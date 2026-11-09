extends SceneTree

const Runway := preload("res://runway_coordinator.gd")
const Activities := preload("res://activity_quota_scheduler.gd")
const Incidents := preload("res://fleet_incident_scheduler.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	var runway := Runway.new()
	runway.submit_request(20, "future", 1, 0, "p1", "takeoff")
	_check("runway cannot grant before request exists", not runway.resolve(19).get("granted", false))
	_check("runway grants at request time", runway.resolve(20).get("granted", false))
	var original: Dictionary = runway.snapshot_state()
	var mutations: Array[Dictionary] = []
	var bad := original.duplicate(true)
	bad.extra = 1
	mutations.append(bad)
	bad = original.duplicate(true)
	bad.events[0].payload.owner_id = 1.5
	mutations.append(bad)
	bad = original.duplicate(true)
	bad.events[0].type = "unknown"
	mutations.append(bad)
	bad = original.duplicate(true)
	bad.events[0].sequence = original.event_sequence + 1
	mutations.append(bad)
	bad = original.duplicate(true)
	bad.grant.direction = -bad.direction
	mutations.append(bad)
	for i: int in mutations.size():
		_check("malformed runway restore %d refuses atomically" % i, not runway.restore_state(mutations[i]).ok
			and runway.snapshot_state() == original)
	var restored := Runway.new()
	_check("valid runway state still roundtrips", restored.restore_state(original).ok and restored.snapshot_state() == original)
	var activity := Activities.new(73)
	activity.request_activity(20, "future", "p1", 1, 0, "circuit", "lane", 1.0, 1, 0, 0)
	var eligibility := {future = {eligible = true}}
	_check("activity cannot grant before request exists", activity.resolve(19, eligibility).get("granted", []).is_empty())
	_check("activity grants at request time", activity.resolve(20, eligibility).get("granted", []).size() == 1)
	var active: Dictionary = activity.snapshot_state()
	_check("preempted completion cannot precede grant", not activity.complete_activity(-1, 1, 0, "circuit", "abort", true).ok
		and activity.snapshot_state() == active)
	_check("retirement cannot precede grant", not activity.retire_agent(-1, 1, 0).ok and activity.snapshot_state() == active)
	var choices: Array[Dictionary] = [{activity_id = "a", weight = 1.0, eligible = true},
		{activity_id = "a", weight = 2.0, eligible = true}]
	_check("duplicate weighted IDs refuse without consuming RNG", not activity.choose_weighted_activity(20, "p1", choices).ok
		and activity.snapshot_state() == active)
	choices = [{activity_id = "a", weight = 1.0, eligible = "false"}]
	_check("eligibility requires an actual boolean", not activity.choose_weighted_activity(20, "p1", choices).ok
		and activity.snapshot_state() == active)
	_test_player_grant_observation()
	_test_runway_queue_reservation_capacity()
	_test_activity_cooldown_capacity()
	var incident := Incidents.new(73, "lively")
	var before: Dictionary = incident.snapshot_state()
	var roster := [{pilot_id = "p1", owner_id = 1, generation = 0, eligible = true,
		episode_families = [{family_id = "bounded", crash_prone = false}]}]
	var bad_roster := roster.duplicate(true)
	bad_roster.append(roster[0].duplicate(true))
	_check("duplicate incident pilots refuse atomically", not incident.advance_to(incident.next_deadline_tick(), bad_roster).ok
		and incident.snapshot_state() == before)
	bad_roster = roster.duplicate(true)
	bad_roster[0].eligible = "false"
	_check("incident eligibility cannot coerce strings", not incident.advance_to(incident.next_deadline_tick(), bad_roster).ok
		and incident.snapshot_state() == before)
	bad_roster = roster.duplicate(true)
	bad_roster[0].owner_id = 1.5
	_check("incident identity cannot round fractions", not incident.advance_to(incident.next_deadline_tick(), bad_roster).ok
		and incident.snapshot_state() == before)
	bad_roster = roster.duplicate(true)
	bad_roster[0].episode_families.resize(65)
	_check("incident family iteration is bounded", not incident.advance_to(incident.next_deadline_tick(), bad_roster).ok
		and incident.snapshot_state() == before)
	bad = before.duplicate(true)
	bad.extra = 1
	_check("incident checkpoint unknown fields refuse", not incident.restore_state(bad).ok and incident.snapshot_state() == before)
	_check("valid incident roster can retry exact deadline", incident.advance_to(incident.next_deadline_tick(), roster).ok)
	print("scheduler boundaries: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func _test_player_grant_observation() -> void:
	var explicit := Runway.new()
	explicit.submit_request(0, "explicit", 1, 2, "player", "landing", 0, true)
	var explicit_grant: Dictionary = explicit.resolve(0).get("grant", {})
	_check("explicit player entry succeeds before observation", explicit.enter_runway(1, int(explicit_grant.ticket), 1, 2).ok)
	explicit.observe_player(1, 1, 2, true, false)
	var explicit_state: Dictionary = explicit.snapshot_state()
	var explicit_copy := Runway.new()
	_check("explicit-then-observed entry roundtrips", explicit_copy.restore_state(explicit_state).ok
		and explicit_copy.snapshot_state() == explicit_state)
	var explicit_events: int = explicit_state.events.size()
	_check("the player's own blocker is not reported as an overlap", not explicit_state.events.back().payload.overlapped)
	explicit.observe_player(2, 1, 2, true, false)
	_check("repeated player observation does not duplicate occupancy events", explicit.snapshot_state().events.size() == explicit_events)

	var observed := Runway.new()
	observed.submit_request(0, "observed", 1, 2, "player", "landing", 0, true)
	var observed_grant: Dictionary = observed.resolve(0).get("grant", {})
	_check("matching observed entry succeeds", observed.observe_player(1, 1, 2, true, false).ok)
	var occupied: Dictionary = observed.snapshot_state()
	_check("matching observed entry consumes the grant and preserves ticket", occupied.mode == "occupied"
		and occupied.grant.is_empty() and int(occupied.physical_blockers["1:2"].get("ticket", -1)) == int(observed_grant.ticket))
	var resumed := Runway.new()
	_check("observed-before-explicit entry roundtrips", resumed.restore_state(occupied).ok and resumed.snapshot_state() == occupied)
	var delayed := Runway.new()
	delayed.restore_state(occupied)
	delayed.resolve(1000000)
	_check("observed occupancy outlasts ticket expiry and permits delayed confirmation", delayed.snapshot_state().mode == "occupied"
		and delayed.enter_runway(1000000, int(observed_grant.ticket), 1, 2).ok)
	var malformed: Dictionary = occupied.duplicate(true)
	malformed.physical_blockers["1:2"].observed_grant_tick = 1.5
	_check("malformed observed-entry tick rejects atomically", not resumed.restore_state(malformed).ok and resumed.snapshot_state() == occupied)
	malformed = occupied.duplicate(true)
	malformed.physical_blockers["1:2"].ticket = int(malformed.grant_sequence) + 1
	_check("an unissued observed-entry ticket rejects atomically", not resumed.restore_state(malformed).ok and resumed.snapshot_state() == occupied)
	observed.observe_player(2, 1, 2, true, false)
	resumed.observe_player(2, 1, 2, true, false)
	var before_wrong: Dictionary = observed.snapshot_state()
	_check("another generation cannot confirm a player entry", not observed.enter_runway(2, int(observed_grant.ticket), 1, 3).ok
		and observed.snapshot_state() == before_wrong)
	_check("another ticket cannot confirm a player entry", not observed.enter_runway(2, int(observed_grant.ticket) + 1, 1, 2).ok
		and observed.snapshot_state() == before_wrong)
	_check("entry confirmation cannot precede observed occupancy", not observed.enter_runway(0, int(observed_grant.ticket), 1, 2).ok
		and observed.snapshot_state() == before_wrong)
	var confirm: Dictionary = observed.enter_runway(2, int(observed_grant.ticket), 1, 2)
	var confirm_copy: Dictionary = resumed.enter_runway(2, int(observed_grant.ticket), 1, 2)
	_check("observed entry confirms once after checkpoint", confirm.ok and confirm_copy == confirm
		and observed.snapshot_state() == resumed.snapshot_state())
	var confirmed: Dictionary = observed.snapshot_state()
	_check("a consumed ticket cannot be confirmed twice", not observed.enter_runway(2, int(observed_grant.ticket), 1, 2).ok
		and observed.snapshot_state() == confirmed)
	var left := Runway.new()
	left.restore_state(occupied)
	left.observe_player(2, 1, 2, false, false)
	var left_state: Dictionary = left.snapshot_state()
	var left_copy := Runway.new()
	_check("leaving before confirmation invalidates it and remains restorable", not left.enter_runway(2, int(observed_grant.ticket), 1, 2).ok
		and left.snapshot_state() == left_state and left_copy.restore_state(left_state).ok)
	left.observe_player(3, 1, 2, true, false)
	_check("re-entry cannot revive an abandoned confirmation", not left.enter_runway(3, int(observed_grant.ticket), 1, 2).ok)
	var wreck := Runway.new()
	wreck.restore_state(occupied)
	wreck.report_runway_wreck(2, 1, 2, "player", "wreck")
	wreck.observe_player(3, 1, 2, true, false)
	var wreck_state: Dictionary = wreck.snapshot_state()
	var wreck_copy := Runway.new()
	_check("player observation retains a wreck and invalidates its confirmation", wreck_state.mode == "blocked"
		and wreck_state.physical_blockers["1:2"].is_wreck and not wreck.enter_runway(3, int(observed_grant.ticket), 1, 2).ok
		and wreck_copy.restore_state(wreck_state).ok)
	wreck.observe_player(4, 1, 2, false, false)
	var removed_after_absence: Dictionary = wreck.clear_wreck_and_occupancy(4, "wreck", true)
	var after_absence: Dictionary = wreck.snapshot_state()
	var after_absence_copy := Runway.new()
	_check("wreck removal after player absence retains the unconfirmed player blocker", removed_after_absence.ok
		and after_absence.mode == "occupied" and after_absence.physical_blockers.has("1:2")
		and not after_absence.physical_blockers["1:2"].is_wreck and after_absence_copy.restore_state(after_absence).ok
		and after_absence_copy.snapshot_state() == after_absence)
	_check("clearance after player absence releases its remaining blocker", wreck.report_clearance(4, 1, 2, true, true).get("cleared", false)
		and wreck.snapshot_state().mode == "free")
	var removal_first := Runway.new()
	removal_first.restore_state(occupied)
	removal_first.report_runway_wreck(2, 1, 2, "player", "wreck-first")
	var removed: Dictionary = removal_first.clear_wreck_and_occupancy(3, "wreck-first", true)
	var after_removal: Dictionary = removal_first.snapshot_state()
	var after_removal_copy := Runway.new()
	_check("wreck removal retains a still-observed player blocker", removed.ok and removed.mode == "occupied"
		and after_removal.blocked_wrecks.is_empty() and after_removal.physical_blockers.has("1:2")
		and not after_removal.physical_blockers["1:2"].is_wreck and after_removal_copy.restore_state(after_removal).ok
		and after_removal_copy.snapshot_state() == after_removal)
	removal_first.observe_player(4, 1, 2, false, false)
	_check("player absence and clearance release the remaining blocker", removal_first.report_clearance(4, 1, 2, true, true).get("cleared", false)
		and removal_first.snapshot_state().mode == "free")

	var incursion := Runway.new()
	incursion.submit_request(0, "reserved-player", 4, 1, "player", "landing", 0, true)
	var reserved: Dictionary = incursion.resolve(0).get("grant", {})
	incursion.observe_player(1, 4, 2, true, false)
	var incursion_state: Dictionary = incursion.snapshot_state()
	var incursion_copy := Runway.new()
	_check("different generation revokes rather than consumes player reservation", incursion_state.grant.is_empty()
		and incursion_state.requests.size() == 1 and int(incursion_state.requests[0].generation) == 1
		and incursion_state.physical_blockers.has("4:2") and not incursion.enter_runway(1, int(reserved.ticket), 4, 1).ok
		and incursion_copy.restore_state(incursion_state).ok)
	incursion.observe_player(2, 4, 2, false, false)
	incursion.report_clearance(2, 4, 2, true, true)
	_check("displaced player request remains eligible after clearance", incursion.resolve(2).get("grant", {}).get("generation", -1) == 1)
	var wrong_owner := Runway.new()
	wrong_owner.submit_request(0, "owner-reserved", 6, 1, "player", "landing", 0, true)
	var owner_grant: Dictionary = wrong_owner.resolve(0).get("grant", {})
	wrong_owner.observe_player(1, 7, 1, true, false)
	var owner_state: Dictionary = wrong_owner.snapshot_state()
	var owner_copy := Runway.new()
	_check("another owner cannot consume the player grant", owner_state.grant.is_empty() and owner_state.requests.size() == 1
		and owner_state.physical_blockers.has("7:1") and not wrong_owner.enter_runway(1, int(owner_grant.ticket), 6, 1).ok
		and owner_copy.restore_state(owner_state).ok)
	var ai_reservation := Runway.new()
	ai_reservation.submit_request(0, "ai-reserved", 8, 1, "ai", "takeoff")
	var ai_grant: Dictionary = ai_reservation.resolve(0).get("grant", {})
	ai_reservation.observe_player(1, 8, 1, true, false)
	var ai_state: Dictionary = ai_reservation.snapshot_state()
	var ai_copy := Runway.new()
	_check("a player observation cannot consume an AI grant even for the same identity", ai_state.grant.is_empty()
		and ai_state.requests.size() == 1 and not ai_reservation.enter_runway(1, int(ai_grant.ticket), 8, 1).ok
		and ai_copy.restore_state(ai_state).ok)

	var late := Runway.new(1, 20, 2)
	late.submit_request(0, "late", 5, 1, "player", "landing", 0, true)
	var expired: Dictionary = late.resolve(0).get("grant", {})
	late.observe_player(3, 5, 1, true, false)
	var late_state: Dictionary = late.snapshot_state()
	var late_copy := Runway.new()
	_check("late observed entry blocks physically without reviving an expired grant", late_state.mode == "occupied"
		and late_state.grant.is_empty() and late_state.requests.is_empty()
		and not late.enter_runway(3, int(expired.ticket), 5, 1).ok and late_copy.restore_state(late_state).ok)


func _test_runway_queue_reservation_capacity() -> void:
	var one := Runway.new(1, 20, 100, 1)
	_check("capacity-one player request is accepted", one.submit_request(0, "original", 4, 1, "player", "landing", 0, true).ok)
	var grant: Dictionary = one.resolve(0).get("grant", {})
	var reserved: Dictionary = one.snapshot_state()
	var rejected: Dictionary = one.submit_request(0, "would-fill", 5, 1, "other", "landing")
	_check("grant reserves its capacity-one requeue slot atomically", not rejected.ok and rejected.reason == "request_queue_full"
		and one.snapshot_state() == reserved)
	one.observe_player(1, 4, 2, true, false)
	var displaced: Dictionary = one.snapshot_state()
	var resumed := Runway.new()
	_check("capacity-one incursion preserves displaced request and physical blocker", displaced.grant.is_empty()
		and displaced.requests.size() == 1 and displaced.requests[0].request_id == "original"
		and displaced.physical_blockers.has("4:2") and resumed.restore_state(displaced).ok
		and resumed.snapshot_state() == displaced)
	one.observe_player(2, 4, 2, false, false)
	one.report_clearance(2, 4, 2, true, true)
	resumed.observe_player(2, 4, 2, false, false)
	resumed.report_clearance(2, 4, 2, true, true)
	var next: Dictionary = one.resolve(2)
	var next_copy: Dictionary = resumed.resolve(2)
	_check("displaced capacity-one request grants identically after restore", next.get("grant", {}).get("request_id", "") == "original"
		and next == next_copy and one.snapshot_state() == resumed.snapshot_state()
		and int(next.grant.ticket) != int(grant.ticket))

	var two := Runway.new(1, 20, 100, 2)
	two.submit_request(0, "player", 10, 1, "player", "landing", 0, true)
	two.submit_request(0, "waiting", 11, 1, "other", "takeoff")
	two.resolve(0)
	var two_reserved: Dictionary = two.snapshot_state()
	var two_copy := Runway.new()
	_check("grant plus one waiting request restores at capacity two", two_copy.restore_state(two_reserved).ok
		and two_copy.snapshot_state() == two_reserved)
	var overcommitted: Dictionary = two_reserved.duplicate(true)
	overcommitted.max_queue = 1
	var guard := Runway.new()
	var guard_before: Dictionary = guard.snapshot_state()
	_check("legacy full queue plus grant rejects atomically", not guard.restore_state(overcommitted).ok
		and guard.snapshot_state() == guard_before)
	_check("capacity-two slot admission refuses without events or sequence changes", not two.submit_request(0, "overflow", 12, 1, "third", "takeoff").ok
		and two.snapshot_state() == two_reserved)
	two.observe_player(1, 10, 2, true, false)
	var two_displaced: Dictionary = two.snapshot_state()
	var events: Array = two_displaced.events
	var restored := Runway.new()
	_check("capacity-two incursion requeues both requests in deterministic order", two_displaced.requests.size() == 2
		and two_displaced.requests[0].request_id == "waiting" and two_displaced.requests[1].request_id == "player"
		and events[-2].type == "reservation_revoked" and events[-1].type == "player_runway_occupancy"
		and int(events[-1].sequence) == int(events[-2].sequence) + 1
		and restored.restore_state(two_displaced).ok and restored.snapshot_state() == two_displaced)

	var consumed := Runway.new(1, 20, 100, 1)
	consumed.submit_request(0, "consumed", 20, 1, "player", "landing", 0, true)
	consumed.resolve(0)
	consumed.observe_player(1, 20, 1, true, false)
	_check("consuming a grant releases its reserved queue slot", consumed.submit_request(1, "new", 21, 1, "other", "takeoff").ok
		and consumed.snapshot_state().requests.size() == 1 and consumed.snapshot_state().mode == "occupied")


func _scheduler_with_history(count: int):
	var scheduler := Activities.new(91)
	var state: Dictionary = scheduler.snapshot_state()
	for index: int in count:
		state.cooldown_until["%d:%s:loop" % [("history-%d" % index).length(), "history-%d" % index]] = 1000
	_check("constructed bounded cooldown checkpoint restores", scheduler.restore_state(state).ok)
	return scheduler


func _test_activity_cooldown_capacity() -> void:
	var limited = _scheduler_with_history(511)
	limited.request_activity(1, "first", "new-a", 1, 1, "loop", "a", 1.0, 1, 0, 20)
	limited.request_activity(1, "second", "new-b", 2, 1, "loop", "b", 1.0, 1, 0, 20)
	var result: Dictionary = limited.resolve(1, {first = {eligible = true}, second = {eligible = true}})
	_check("one remaining cooldown slot grants only one distinct promise", result.ok and result.granted.size() == 1
		and result.granted[0].request_id == "first" and limited.snapshot_state().pending.size() == 1)
	var promised: Dictionary = limited.snapshot_state()
	var promised_copy := Activities.new()
	_check("in-flight cooldown promise restores exactly", promised_copy.restore_state(promised).ok and promised_copy.snapshot_state() == promised)
	_check("normal completion consumes the reserved slot", limited.complete_activity(2, 1, 1, "loop").ok
		and limited.snapshot_state().cooldown_until.size() == 512)
	var full: Dictionary = limited.snapshot_state()
	_check("new cooldown key refuses atomically at capacity", not limited.request_activity(2, "third", "new-c", 3, 1, "loop", "c", 1.0, 1, 0, 20).ok
		and limited.snapshot_state() == full)
	_check("waiting activity does not exceed capacity on a later resolve", limited.resolve(2, {second = {eligible = true}}).granted.is_empty()
		and limited.snapshot_state().cooldown_until.size() == 512)
	_check("a waiting request cannot complete without a lease", not limited.complete_activity(2, 2, 1, "loop").ok
		and limited.snapshot_state().cooldown_until.size() == 512)
	var complete_copy := Activities.new()
	_check("full cooldown checkpoint roundtrips", complete_copy.restore_state(limited.snapshot_state()).ok)

	var pair = _scheduler_with_history(510)
	pair.request_activity(1, "preempt", "a", 10, 1, "loop", "a", 1.0, 1, 30, 20)
	pair.request_activity(1, "retire", "b", 11, 1, "loop", "b", 1.0, 1, 30, 20)
	_check("two available slots reserve two distinct completions", pair.resolve(1, {preempt = {eligible = true}, retire = {eligible = true}}).granted.size() == 2)
	var two_promises: Dictionary = pair.snapshot_state()
	var overcommitted: Dictionary = two_promises.duplicate(true)
	overcommitted.cooldown_until["3:new:loop"] = 1000
	var guard := Activities.new(44)
	var guard_before: Dictionary = guard.snapshot_state()
	_check("legacy overcommitted checkpoint refuses atomically", not guard.restore_state(overcommitted).ok
		and guard.snapshot_state() == guard_before)
	_check("safety preemption reserves its completion history", pair.complete_activity(2, 10, 1, "loop", "recovery", true).ok
		and pair.snapshot_state().cooldown_until.size() == 511)
	_check("retirement reserves its completion history", pair.retire_agent(2, 11, 1).ok
		and pair.snapshot_state().cooldown_until.size() == 512)
	var pair_copy := Activities.new()
	_check("preemption and retirement state roundtrips", pair_copy.restore_state(pair.snapshot_state()).ok)

	var shared = _scheduler_with_history(511)
	shared.request_activity(1, "shared-a", "shared", 20, 1, "loop", "same", 1.0, 2, 0, 20)
	shared.request_activity(1, "shared-b", "shared", 21, 1, "loop", "same", 1.0, 2, 0, 20)
	_check("leases sharing a cooldown key reserve only one slot", shared.resolve(1, {"shared-a": {eligible = true}, "shared-b": {eligible = true}}).granted.size() == 2)
	var shared_active: Dictionary = shared.snapshot_state()
	var shared_active_copy := Activities.new()
	_check("shared-key active leases roundtrip at capacity", shared_active_copy.restore_state(shared_active).ok
		and shared_active_copy.snapshot_state() == shared_active)
	_check("shared-key completion and retirement stay within the bound", shared.complete_activity(2, 20, 1, "loop").ok
		and shared.retire_agent(2, 21, 1).ok and shared.snapshot_state().cooldown_until.size() == 512)
	var shared_copy := Activities.new()
	_check("shared-key checkpoint roundtrips", shared_copy.restore_state(shared.snapshot_state()).ok)

	var reused = _scheduler_with_history(512)
	var reused_state: Dictionary = reused.snapshot_state()
	reused_state.cooldown_until["9:history-0:loop"] = 0
	_check("expired existing history remains valid at capacity", reused.restore_state(reused_state).ok)
	_check("an existing expired key can be granted at capacity", reused.request_activity(1, "reuse", "history-0", 30, 1, "loop", "reuse", 1.0, 1, 0, 20).ok
		and reused.resolve(1, {reuse = {eligible = true}}).granted.size() == 1)
	_check("reused key completion does not grow history", reused.complete_activity(2, 30, 1, "loop").ok
		and reused.snapshot_state().cooldown_until.size() == 512)


func _check(description: String, value: bool) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL ", description)

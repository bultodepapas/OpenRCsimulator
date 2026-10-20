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

func _check(description: String, value: bool) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL ", description)

# Actual detector output fed into the telemetry event consumer, entirely in memory.
# Use run_godot_probes.py to copy exact dependencies into an isolated project.
extends SceneTree

const Detector := preload("res://statistics/detector.gd")
const Event := preload("res://statistics/flight_event.gd")
const Service := preload("res://telemetry/telemetry_service.gd")
const Contract := preload("res://telemetry/telemetry_contract.gd")

func _initialize() -> void:
	var detector := Detector.new()
	detector.configure({"landing_available": true, "generation_id": "probe", "aircraft_id": "f4u-corsair-250",
		"configuration_hash": "fixture", "rules": {"liftoff_clearance_s": 0.2,
		"stable_support_s": 0.2, "full_stop_s": 0.4, "rearm_clearance_s": 0.3}})
	detector.observe(_sample(1, true))
	detector.observe(_sample(2, false))
	detector.observe(_sample(3, false))
	var facts := {"gear_up_contact": true, "intended_support": false, "controlled": false}
	var first := _crashes(detector.observe(_sample(4, true, facts)))
	facts.terminal = true
	var revised := _crashes(detector.observe(_sample(4, true, facts)))
	if first.size() != 1 or revised.size() != 1:
		printerr("INCONCLUSIVE: detector did not produce both crash revisions")
		quit(1)
		return
	var event0: Dictionary = first[0]
	var event1: Dictionary = revised[0]
	var actual_events: bool = Event.valid(event0) and Event.valid(event1) and event0.revision == 0 \
		and event1.revision == 1 and not event0.terminal and event1.terminal \
		and event0.accident_id != "" and event0.accident_id == event1.accident_id
	var s := Service.new()
	s.state = "on"
	s._activity = {"classification": "accepted_fixed_wing", "takeoffs": 0, "landings": 0, "aircraft_crashes": 0}
	s.note_flight_events([event0])
	s.note_flight_events([event1])
	var one_summary_count: int = s._activity.aircraft_crashes
	s.free()

	# Feed the same real revisions across the service's actual 5-minute slice
	# transition to test loss of any accident-level continuity between slices.
	var c := Service.new()
	c.state = "on"
	c.release = {"notice": Contract.NOTICE_VERSION, "release_id": "v0.3.2", "channel": "stable"}
	c.utc_day = func() -> String: return "2026-11-22"
	var ctx := {"mode": "flight", "activity": true, "vehicle": "f4u-corsair-250",
		"fixed_wing_accepted": true, "simulated_seconds": 10.0, "window_size": Vector2i(1920, 1080)}
	c.context_provider = func() -> Dictionary: return ctx
	c.hardware_facts = {"os": "Linux", "architecture": "x86_64", "cpu": "AMD Ryzen", "threads": 8,
		"memory_bytes": 8589934592, "gpu": "NVIDIA GeForce RTX", "renderer": "forward_plus", "driver": "vulkan"}
	c._session_id = "a".repeat(32)
	c._session_day = "2026-11-22"
	c._session_start_usec = 0
	c._activity_from_start = true
	c._track_activity(ctx, "flight", "f4u-corsair-250", 0, true)
	c.note_flight_events([event0])
	c._activity.active_us = 300000000
	c._track_activity(ctx, "flight", "f4u-corsair-250", 300000000, true)
	c.note_flight_events([event1])
	c._end_activity(301000000, "returned_home", true)
	var slice_counts := []
	for item: Dictionary in c._pending:
		if item.name == "activity_summary":
			slice_counts.append(item.aircraft_crashes)
	print("CRASH_REVISION_PROBE ", JSON.stringify({"detector_outputs_valid_same_accident": actual_events,
		"revisions": [event0.revision, event1.revision], "one_summary_count": one_summary_count,
		"slice_counts": slice_counts}))
	var reproduced: bool = actual_events and one_summary_count == 2 and slice_counts == [1, 1]
	c.free()
	if reproduced:
		print("REPRODUCED: one accident and its terminal revision produce two telemetry crash counts")
		quit(0)
	else:
		printerr("INCONCLUSIVE: expected source-state signature was not observed")
		quit(1)

func _sample(tick: int, ground: bool, changes: Dictionary = {}) -> Dictionary:
	var value := {"tick": tick, "dt": 0.1, "valid": true, "supported": ground, "ground_contact": ground,
		"intended_support": ground, "stop_support": ground, "controlled": true, "clearance_ok": not ground,
		"ground_speed_3d": 5.0, "angular_speed": 0.0, "incident": false, "gear_up_contact": false,
		"terminal": false}
	value.merge(changes, true)
	return value

func _crashes(events: Array) -> Array:
	var found := []
	for item: Dictionary in events:
		if item.get("type") == "semantic" and item.event.type == "CRASH":
			found.append(item.event)
	return found

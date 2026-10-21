## AFC-09 focused checks for candidate-only full-footprint exit qualification.
extends SceneTree

var candidate_driver: Script
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	var script_dir: String = get_script().resource_path.get_base_dir()
	var driver_path: String = script_dir.path_join("external_sortie_driver_candidate_taxi.gd")
	for argument: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
		if pair.size() == 2 and pair[0] == "driver":
			driver_path = pair[1]
	candidate_driver = load(driver_path)
	if candidate_driver == null:
		printerr("AFC-09 taxi clearance-state candidate driver is unavailable: " + driver_path)
		quit(2)
		return
	call_deferred("_run")


func _run() -> void:
	_test_hull_clearance_arrives_after_gear()
	_test_reentry_resets_dwell_and_keeps_corridor_live()
	_test_completion_requires_current_full_clear()
	_test_end_corridor_remains_required()
	print("AFC-09 taxi exit clearance (%s): %d checks, %d failed" % [candidate_driver.resource_path, checks, failures.size()])
	for failure: String in failures:
		printerr("FAIL " + failure)
	quit(1 if not failures.is_empty() else 0)


func _test_hull_clearance_arrives_after_gear() -> void:
	var state: Dictionary = candidate_driver.new_clearance_state()
	var late_hull: Dictionary = candidate_driver.advance_clearance_state(state, 0.125, true, false, true, 1.0)
	_assert(not bool(late_hull.runway_vacated), "gear-only clearance cannot start full-exit qualification")
	_assert(not bool(late_hull.full_exit_clear_now) and float(late_hull.clear_dwell_s) == 0.0,
		"late hull clearance leaves the clear dwell at zero")
	var first_full: Dictionary = candidate_driver.advance_clearance_state(state, 0.125, true, true, true, 1.0)
	_assert(not bool(first_full.runway_vacated) and is_equal_approx(float(first_full.clear_dwell_s), 0.125),
		"full-footprint dwell starts only when gear and hull are clear")
	var dwell_complete: Dictionary = candidate_driver.advance_clearance_state(state, 0.125, true, true, true, 1.0)
	_assert(bool(dwell_complete.runway_vacated), "full-footprint exit qualifies after 0.25 seconds")


func _test_reentry_resets_dwell_and_keeps_corridor_live() -> void:
	var state: Dictionary = candidate_driver.new_clearance_state()
	for _tick in 2:
		candidate_driver.advance_clearance_state(state, 0.125, true, true, true, 1.0)
	var first_clear: Dictionary = candidate_driver.advance_clearance_state(state, 0.125, true, true, true, 1.0)
	_assert(bool(first_clear.runway_vacated), "initial full clear is qualified")
	var reentry: Dictionary = candidate_driver.advance_clearance_state(state, 0.125, false, true, true, -0.01)
	_assert(not bool(reentry.runway_vacated) and float(reentry.clear_dwell_s) == 0.0,
		"re-entry revokes the prior clear and resets the dwell")
	_assert(int(reentry.clear_reset_count) == 1, "re-entry is recorded as a clear reset")
	_assert(bool(reentry.corridor_check_required) and bool(reentry.lateral_footprint_violation),
		"corridor validation remains active and detects a footprint violation after initial clear")
	var requalified: Dictionary = candidate_driver.advance_clearance_state(state, 0.125, true, true, true, 1.0)
	_assert(not bool(requalified.runway_vacated), "re-entry requires a fresh full 0.25-second clear dwell")
	requalified = candidate_driver.advance_clearance_state(state, 0.125, true, true, true, 1.0)
	_assert(bool(requalified.runway_vacated), "fresh clear dwell can qualify after re-entry")


func _test_completion_requires_current_full_clear() -> void:
	var state: Dictionary = candidate_driver.new_clearance_state()
	for _tick in 2:
		candidate_driver.advance_clearance_state(state, 0.125, true, true, true, 1.0)
	var clear_status: Dictionary = candidate_driver.advance_clearance_state(state, 0.125, true, true, true, 1.0)
	_assert(candidate_driver.can_complete_clearance(state, 2.0), "completion is allowed after deadline with current full clear")
	_assert(not candidate_driver.can_complete_clearance(state, 1.999), "completion still observes the two-second minimum")
	var airborne: Dictionary = candidate_driver.advance_clearance_state(state, 0.125, true, true, false, 1.0)
	_assert(not candidate_driver.can_complete_clearance(state, 10.0) and not bool(airborne.runway_vacated),
		"airborne geometric clearance cannot complete or keep the vacated dwell")
	var current_wheels_reentered: Dictionary = candidate_driver.advance_clearance_state(state, 0.125, false, true, true, 1.0)
	_assert(not candidate_driver.can_complete_clearance(state, 10.0), "stale qualified clear cannot complete after wheel re-entry")
	_assert(not bool(current_wheels_reentered.full_exit_clear_now), "current footprint state reflects wheel re-entry")
	var current_hull_reentered: Dictionary = candidate_driver.advance_clearance_state(state, 0.125, true, false, true, 1.0)
	_assert(not candidate_driver.can_complete_clearance(state, 10.0), "hull re-entry also blocks completion")
	_assert(not bool(current_hull_reentered.full_exit_clear_now), "current footprint state reflects hull re-entry")
	_assert(bool(clear_status.full_exit_clear_now), "completion test began from current gear-and-hull clearance")


func _test_end_corridor_remains_required() -> void:
	var state: Dictionary = candidate_driver.new_clearance_state()
	var status: Dictionary
	for _tick in 3:
		status = candidate_driver.advance_clearance_state(state, 0.125, true, true, true, -0.01)
	_assert(bool(status.full_exit_clear_now), "end-corridor check runs after full gear-and-hull clearance")
	_assert(bool(status.corridor_check_required) and bool(status.lateral_footprint_violation),
		"side corridor remains live through the fully clear endpoint")
	_assert(not bool(status.runway_vacated) and not candidate_driver.can_complete_clearance(state, 10.0),
		"full clearance outside the corridor cannot qualify or complete")


func _assert(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)

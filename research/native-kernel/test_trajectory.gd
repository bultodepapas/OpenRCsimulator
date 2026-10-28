## Focused NK-3 trajectory evidence policy checks; no native library or simulation run required.
extends SceneTree

const Trajectory := preload("trajectory.gd")

var _checks := 0
var _failures := 0


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + description)


func _end(tick: int, crashed := false, paused := false, fault := "") -> Dictionary:
	return {tick = tick, crashed = crashed, paused = paused, fault = fault, pause_reason = ""}


func _initialize() -> void:
	for case: String in Trajectory.CASES:
		_check(Trajectory._trajectory_completion_ok(case, 960, 960, _end(960)), case + " completes 960 healthy ticks")
		_check(not Trajectory._trajectory_completion_ok(case, 960, 0, _end(0)), case + " rejects empty agreement")
		_check(not Trajectory._trajectory_completion_ok(case, 960, 959, _end(959)), case + " rejects a truncated run")
		_check(not Trajectory._trajectory_completion_ok(case, 960, 960, _end(960, false, true, "fault")), case + " rejects a fault")
		_check(not Trajectory._trajectory_completion_ok(case, 960, 960, _end(960, false, true)), case + " rejects a pause")
	for case: String in ["trim", "runway", "maneuver"]:
		_check(not Trajectory._trajectory_completion_ok(case, 14400, 960, _end(960, true, true)), case + " rejects early crash")
		_check(not Trajectory._trajectory_completion_ok(case, 960, 960, _end(960, true, true)), case + " rejects final crash")
	for case: String in ["takeoff", "lake"]:
		_check(Trajectory._trajectory_completion_ok(case, 14400, 960, _end(960, true, true)), case + " accepts crash after minimum")
		_check(not Trajectory._trajectory_completion_ok(case, 14400, 959, _end(959, true, true)), case + " rejects crash below minimum")
		_check(not Trajectory._trajectory_completion_ok(case, 14400, 960, _end(960)), case + " rejects unexplained early stop")
		_check(not Trajectory._trajectory_completion_ok(case, 14400, 960, _end(960, true, true, "fault")), case + " rejects crash with fault")
	_check(Trajectory._trajectory_completion_ok("trim", 10, 10, _end(10)), "short positive request must complete")
	_check(not Trajectory._trajectory_completion_ok("trim", 0, 0, _end(0)), "zero request fails")
	_check(not Trajectory._trajectory_completion_ok("trim", -1, 0, _end(0)), "negative request fails")
	_check(not Trajectory._trajectory_completion_ok("unknown", 960, 960, _end(960)), "unknown case fails")
	_check(not Trajectory._trajectory_completion_ok("trim", 960, 961, _end(961)), "more ticks than requested fails")
	_check(not Trajectory._trajectory_completion_ok("trim", 960, 960, _end(959)), "end tick must match actual count")
	_check(not Trajectory._trajectory_completion_ok("trim", 960, 960, {}), "missing end fields fail")

	var start := {context_calls = 0, stage_calls = 0}
	var first := {context_calls = 1, stage_calls = 8}
	var second := {context_calls = 2, stage_calls = 8}
	_check(Trajectory._native_tick_covered(start, first), "tick with substeps is covered")
	_check(not Trajectory._native_tick_covered(first, second), "substeps cannot conceal a later uncovered tick")
	_check(not Trajectory._native_tick_covered(start, {context_calls = 0, stage_calls = 4}), "missing context fails")
	_check(not Trajectory._native_tick_covered(start, {context_calls = 1, stage_calls = 3}), "fewer than four stages fail")

	var rejected := _end(1200, false, true, "step rejected")
	_check(Trajectory._fault_outcome_ok(1200, false, rejected), "fault rejected at injection tick")
	_check(not Trajectory._fault_outcome_ok(1199, false, rejected), "fault must reach injection tick")
	_check(not Trajectory._fault_outcome_ok(1200, true, rejected), "equal advancing fault steps fail")
	_check(not Trajectory._fault_outcome_ok(1200, false, _end(1200, false, true)), "fault reason is required")
	_check(not Trajectory._fault_outcome_ok(1200, false, _end(1200, true, true, "fault")), "crash is not fault rejection")

	var pass_ticks: Array = []
	pass_ticks.resize(1200)
	var run := {info = {restored = true, resumed = true, native_after_restore = true}, passes = [pass_ticks, pass_ticks]}
	_check(Trajectory._checkpoint_result_ok(run, false), "reference restores and runs both passes")
	_check(Trajectory._checkpoint_result_ok(run, true), "native restores and runs both passes")
	var broken: Dictionary = run.duplicate(true)
	broken.passes = [[], []]
	_check(not Trajectory._checkpoint_result_ok(broken, false), "equal empty restore passes fail")
	broken = run.duplicate(true)
	broken.passes[1].resize(1199)
	_check(not Trajectory._checkpoint_result_ok(broken, false), "truncated restore pass fails")
	broken = run.duplicate(true)
	broken.info.restored = false
	_check(not Trajectory._checkpoint_result_ok(broken, false), "failed restore fails")
	broken = run.duplicate(true)
	broken.info.resumed = false
	_check(not Trajectory._checkpoint_result_ok(broken, false), "failed resume fails")
	broken = run.duplicate(true)
	broken.info.native_after_restore = false
	_check(not Trajectory._checkpoint_result_ok(broken, true), "native stage must be present after restore")
	broken.info.reinstalled = true
	_check(Trajectory._checkpoint_result_ok(broken, true), "successful native reinstall is accepted")

	var runs := [
		{ticks = 960, stage = "evaluate", fingerprint = "same", install = {ok = false, error = "not attempted"}},
		{ticks = 960, stage = "evaluate", fingerprint = "same", install = {ok = false, error = "unsupported"}},
	]
	_check(Trajectory._fallback_result_ok(runs), "refusal retains reference for 960 ticks")
	var bad_runs: Array = runs.duplicate(true)
	bad_runs[0].ticks = 0
	bad_runs[1].ticks = 0
	_check(not Trajectory._fallback_result_ok(bad_runs), "equal empty fallback runs fail")
	bad_runs = runs.duplicate(true)
	bad_runs[1].install.ok = true
	_check(not Trajectory._fallback_result_ok(bad_runs), "accepted unsupported aircraft fails")
	bad_runs = runs.duplicate(true)
	bad_runs[1].install.error = ""
	_check(not Trajectory._fallback_result_ok(bad_runs), "refusal requires a reason")
	bad_runs = runs.duplicate(true)
	bad_runs[1].stage = "stage"
	_check(not Trajectory._fallback_result_ok(bad_runs), "fallback must retain the reference stage")
	bad_runs = runs.duplicate(true)
	bad_runs[1].fingerprint = "different"
	_check(not Trajectory._fallback_result_ok(bad_runs), "fallback fingerprint must match")

	print("NK3_TRAJECTORY_POLICY checks=%d failures=%d" % [_checks, _failures])
	quit(1 if _failures else 0)

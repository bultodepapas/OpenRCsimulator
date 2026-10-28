## Focused NK-3 trajectory evidence policy checks; no native library or simulation run required.
extends SceneTree

const Trajectory := preload("trajectory.gd")

var _checks := 0
var _failures := 0


class FakeNative:
	extends RefCounted
	var context_calls := 0
	var stage_calls := 0

	func stage(_a: Variant, _b: Variant, _c: Variant) -> void:
		stage_calls += 1

	func reset_stage_stats(_timing: bool) -> void:
		context_calls = 0
		stage_calls = 0

	func stage_stats() -> Dictionary:
		return {context_calls = context_calls, stage_calls = stage_calls, stage_ns = 0.0}


class FakeSimulation:
	extends Node
	var tick := 0
	var paused := false
	var fault_reason := ""
	var model := {stage = Callable(), pre_tick = Callable(), post_tick_joint = Callable(), post_tick = Callable()}
	var native: FakeNative
	var session: Node
	var failure := ""
	var fail_at := -1

	func dt() -> float:
		return 1.0 / 240.0

	func _pre_tick(_a: Variant, _b: Variant, _c: Variant) -> void:
		if native != null:
			native.context_calls += 1

	func _reference_stage(_a: Variant, _b: Variant, _c: Variant) -> void:
		pass

	func _physics_process(_delta: float) -> void:
		if paused or (failure == "stopped" and tick == fail_at):
			return
		var before := tick
		tick += 2 if failure == "double" and before == fail_at else 1
		if failure != "context" or tick != fail_at:
			model.pre_tick.call(1, 2, 3)
		var calls := 3 if failure == "stage" and tick == fail_at else 4
		for _index in calls:
			model.stage.call(1, 2, 3)
		if tick == fail_at:
			match failure:
				"pause": paused = true
				"fault": fault_reason = "rejected"
				"crash": session.crash = {reason = "crashed"}
				"uninstall": model.stage = Callable()


class FakeSession:
	extends Node
	var sim := FakeSimulation.new()
	var crash := {}

	func _init() -> void:
		add_child(sim)
		sim.session = self
		sim.model.pre_tick = Callable(sim, "_pre_tick")
		sim.model.stage = Callable(sim, "_reference_stage")

	func _physics_process(_delta: float) -> void:
		pass


class FailingTimingHarness:
	extends "trajectory.gd"

	func _timed_run(_case: String, _native: bool, _warmup: int, _samples: int) -> Dictionary:
		return {ok = false, error = "sentinel failure"}


class AttributionHarness:
	extends "trajectory.gd"
	var failure := ""
	var fail_at := -1

	func _session_for(_case: String, native: bool) -> Dictionary:
		var session := FakeSession.new()
		session.sim.failure = failure
		session.sim.fail_at = fail_at
		if native:
			session.sim.native = _native as FakeNative
			session.sim.model.stage = Callable(_native, "stage")
		return {session = session}


func _fake_timed_run(failure: String, fail_at: int, native: bool, warmup: int = 2, samples: int = 3) -> Dictionary:
	var session := FakeSession.new()
	var fake_native := FakeNative.new() if native else null
	session.sim.native = fake_native
	session.sim.failure = failure
	session.sim.fail_at = fail_at
	if native and failure != "not_installed":
		session.sim.model.stage = Callable(fake_native, "stage")
	if failure == "initial_pause":
		session.sim.paused = true
	var result := Trajectory._timed_session(session, fake_native, warmup, samples)
	session.free()
	return result


func _check_failed_timing(result: Dictionary, reason: String, description: String) -> void:
	_check(not result.ok and reason in result.error, description)
	_check(not result.has("median") and not result.has("mean"), description + " has no timing summary")


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + description)


func _end(tick: int, crashed := false, paused := false, fault := "") -> Dictionary:
	return {tick = tick, crashed = crashed, paused = paused, fault = fault, pause_reason = ""}


func _initialize() -> void:
	var healthy := _fake_timed_run("", -1, false)
	_check(healthy.ok and healthy.warmup_completed == 2 and healthy.samples_completed == 3,
		"reference timing accepts every completed tick")
	healthy = _fake_timed_run("", -1, true)
	_check(healthy.ok and healthy.warmup_completed == 2 and healthy.samples_completed == 3,
		"native timing accepts every covered tick")
	_check_failed_timing(_fake_timed_run("", -1, false, 0, 3), "positive", "zero warm-up fails")
	_check_failed_timing(_fake_timed_run("", -1, false, 2, 0), "positive", "zero samples fail")
	_check_failed_timing(_fake_timed_run("initial_pause", -1, false), "paused", "initial pause fails")
	_check_failed_timing(_fake_timed_run("stopped", 1, false), "warm-up tick 2", "truncated warm-up fails")
	_check_failed_timing(_fake_timed_run("stopped", 2, false), "sample tick 1", "truncated sample fails")
	_check_failed_timing(_fake_timed_run("double", 2, false), "exactly once", "double advancement fails")
	_check_failed_timing(_fake_timed_run("pause", 3, false), "paused", "pause on an advancing tick fails")
	_check_failed_timing(_fake_timed_run("fault", 3, false), "fault", "fault on an advancing tick fails")
	_check_failed_timing(_fake_timed_run("crash", 3, false), "crashed", "crash on an advancing tick fails")
	_check_failed_timing(_fake_timed_run("not_installed", -1, true), "not installed", "missing native install fails")
	_check_failed_timing(_fake_timed_run("uninstall", 3, true), "replaced", "native replacement fails")
	_check_failed_timing(_fake_timed_run("stage", 3, true), "cover", "uncovered native stage fails")
	_check_failed_timing(_fake_timed_run("context", 1, true), "warm-up tick 1", "uncovered native warm-up fails")

	var harness := FailingTimingHarness.new()
	harness._options = {pairs = "1", warmup = "1", samples = "1", "timing-cases" = "trim"}
	harness._report = {}
	harness._time_sessions()
	_check(harness._failures.size() == 1 and "sentinel failure" in harness._failures[0],
		"pair failure propagates to the oracle")
	_check(not harness._report.session_timing.cases.trim.has("reference_median_us"),
		"failed pair has no timing summary")
	harness._failures.clear()
	harness._options = {pairs = "0", warmup = "1", samples = "1"}
	harness._time_sessions()
	_check(harness._failures.size() == 1 and "positive" in harness._failures[0], "zero pairs fail")
	harness._failures.clear()
	harness._options = {samples = "1", repeats = "0"}
	harness._attribute_native()
	_check(harness._failures.size() == 1 and "positive" in harness._failures[0], "zero attribution repeats fail")
	harness.free()

	var attribution := AttributionHarness.new()
	attribution._native = FakeNative.new()
	var attributed := attribution._attribution_run("trim", true, 2)
	_check(not attributed.is_empty() and attributed.stage_calls_per_tick == 4.0,
		"attribution accepts covered native ticks")
	attribution.failure = "stopped"
	attribution.fail_at = 100
	_check(attribution._attribution_run("trim", true, 2).is_empty() \
		and "warm-up tick 101" in attribution._failures[-1], "attribution rejects truncated warm-up")
	attribution.failure = "stage"
	attribution.fail_at = 601
	_check(attribution._attribution_run("trim", true, 2).is_empty() \
		and "sample tick 1" in attribution._failures[-1], "attribution rejects uncovered native tick")
	attribution.failure = "uninstall"
	_check(attribution._attribution_run("trim", true, 2).is_empty() \
		and "replaced" in attribution._failures[-1], "attribution rejects native stage replacement")
	attribution.free()

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

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
	var state := PackedFloat64Array([0.0])
	var aux := PackedFloat64Array([0.0])
	var continuous := PackedFloat64Array([0.0])
	var inputs := PackedFloat64Array([0.0])
	var last_loads := PackedFloat64Array([0.0])
	var modes := PackedInt64Array([0])
	var model := {stage = Callable(), pre_tick = Callable(), post_tick_joint = Callable(), post_tick = Callable()}
	var native: FakeNative
	var session: Node
	var failure := ""
	var fail_at := -1
	var divergent_field := "state"

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
		state[0] = 0.0
		aux[0] = float(tick)
		continuous[0] = float(tick)
		inputs[0] = float(tick)
		last_loads[0] = float(tick)
		modes[0] = tick
		if failure == "divergence" and tick == fail_at:
			match divergent_field:
				"state": state[0] += 1.0
				"state_zero_sign": state[0] = PackedByteArray([0, 0, 0, 0, 0, 0, 0, 128]).decode_double(0)
				"aux": aux[0] += 1.0
				"continuous": continuous[0] += 1.0
				"inputs": inputs[0] += 1.0
				"last_loads": last_loads[0] += 1.0
				"modes": modes[0] += 1
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


class PartialTimingHarness:
	extends "trajectory.gd"

	func _timed_run(_case: String, native: bool, _warmup: int, _samples: int) -> Dictionary:
		if native:
			return {ok = false, error = "native stopped", warmup_completed = 1, samples_completed = 0}
		return {ok = true, median = 1.0, p95 = 1.0, mean = 1.0, trajectory_sha256 = "a".repeat(64)}


class PairedTimingHarness:
	extends "trajectory.gd"
	var divergent_field := ""
	var divergent_tick := -1

	func _session_for(_case: String, native: bool) -> Dictionary:
		var session := FakeSession.new()
		if native:
			session.sim.native = _native as FakeNative
			session.sim.model.stage = Callable(_native, "stage")
			if not divergent_field.is_empty():
				session.sim.failure = "divergence"
				session.sim.divergent_field = divergent_field
				session.sim.fail_at = divergent_tick
		return {session = session}


class ModeHarness:
	extends "trajectory.gd"
	var called: Array[String] = []

	func _compare_trajectory(_case: String, _ticks: int) -> void:
		called.append("trajectory")

	func _check_fault_paths() -> void:
		called.append("fault")

	func _check_checkpoint_restore() -> void:
		called.append("checkpoint")

	func _check_fallback() -> void:
		called.append("fallback")

	func _time_sessions() -> void:
		called.append("timing")

	func _attribute_native() -> void:
		called.append("attribution")


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
	for invalid: Dictionary in [{only = "timng"}, {only = "timing", "skip-timing" = "true"},
			{only = "attribution", "skip-timing" = "true"}]:
		var mode := ModeHarness.new()
		mode._options = invalid
		mode._report = {components = {literal = {count = 1, identical = 1}}}
		mode._checks()
		_check(not mode._failures.is_empty() and mode.called.is_empty(),
			"invalid mode fails before requested work: " + str(invalid))
		mode.free()
	var mode := ModeHarness.new()
	mode._options = {only = "all", "skip-timing" = "true"}
	mode._report = {components = {literal = {count = 1, identical = 1}}}
	mode._checks()
	_check(mode._failures.is_empty() and mode.called.count("trajectory") == 5 \
		and not "timing" in mode.called and not "attribution" in mode.called,
		"all mode can still skip timing after its trajectory checks")
	mode.free()
	mode = ModeHarness.new()
	mode._options = {only = "timing"}
	mode._report = {components = {literal = {count = 1, identical = 1}}}
	mode._checks()
	_check(mode._failures.is_empty() and mode.called == ["timing", "attribution"],
		"timing mode executes timing and attribution")
	mode.free()
	mode = ModeHarness.new()
	mode._options = {only = "attribution"}
	mode._report = {components = {literal = {count = 1, identical = 1}}}
	mode._checks()
	_check(mode._failures.is_empty() and mode.called == ["attribution"], "attribution mode executes attribution")
	mode.free()

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

	var pair := PairedTimingHarness.new()
	pair._native = FakeNative.new()
	pair._options = {pairs = "1", warmup = "2", samples = "3", "timing-cases" = "trim"}
	pair._report = {}
	pair._time_sessions()
	var success: Dictionary = pair._report.session_timing.cases.trim
	_check(pair._failures.is_empty() and success.has("reference_median_us"), "matching completed timing pair succeeds")
	_check(success.pairs[0].reference.trajectory_sha256 == success.pairs[0].native.trajectory_sha256 \
		and success.pairs[0].reference.trajectory_sha256.length() == 64, "matching pair retains its full tape hashes")
	_check("research stage_adapter.gd" in pair._report.measurement_scope.backend \
		and "outside the stopwatch" in pair._report.measurement_scope.timing_validation,
		"report identifies the research boundary and outside-stopwatch validation")
	pair.free()
	for field: String in ["state", "state_zero_sign", "aux", "continuous", "inputs", "last_loads", "modes"]:
		for changed_tick: int in [1, 3]:
			pair = PairedTimingHarness.new()
			pair._native = FakeNative.new()
			pair._options = {pairs = "1", warmup = "2", samples = "3", "timing-cases" = "trim"}
			pair._report = {}
			pair.divergent_field = field
			pair.divergent_tick = changed_tick
			pair._time_sessions()
			var rejected: Dictionary = pair._report.session_timing.cases.trim
			_check(pair._failures.size() == 1 and "trajectories differ" in pair._failures[0] \
				and not rejected.has("reference_median_us") and not rejected.has("pairs") \
				and rejected.reference_completed == {warmup = 2, samples = 3} \
				and rejected.native_completed == {warmup = 2, samples = 3},
				"reject transient %s difference at tick %d despite a matching final state" % [field, changed_tick])
			pair.free()

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
	_check("research stage_adapter.gd" in harness._report.measurement_scope.backend,
		"attribution report identifies the research boundary")
	harness.free()
	var partial := PartialTimingHarness.new()
	partial._options = {pairs = "1", warmup = "1", samples = "1", "timing-cases" = "trim"}
	partial._report = {}
	partial._time_sessions()
	_check(partial._failures.size() == 1 and not partial._report.session_timing.cases.trim.has("pairs") \
		and not partial._report.session_timing.cases.trim.has("reference_median_us"),
		"failed second backend does not report one-sided timing")
	partial.free()

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
	var passed := _checks > 0 and _failures == 0
	print("NK3_TRAJECTORY_POLICY verdict=%s" % ["pass" if passed else "fail"])
	quit(0 if passed else 1)

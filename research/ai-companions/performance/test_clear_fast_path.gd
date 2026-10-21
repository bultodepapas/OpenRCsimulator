extends SceneTree

## Differential controller proof, not physical-flight or target-hardware evidence.
const FieldLoader := preload("res://data/field_loader.gd")
const Math3D := preload("res://physics/math3d.gd")
const Body := preload("res://physics/rigid_body.gd")
const BaselinePath := "res://../research/ai-companions/performance/reachable_clear_baseline.gd"
const CandidatePath := "res://../research/ai-companions/performance/reachable_clear_candidate.gd"
const ExpectedBaseline := "363942b4b7d67f85333233f0c6000890ca984e5b76a8ccabe7973f70218259ed"
const Trim := {V = 15.0, throttle = 0.45}

class BaselineCounter extends "res://../research/ai-companions/performance/reachable_clear_baseline.gd":
	var scores := 0
	func _score_bank(state: PackedFloat64Array, velocity: PackedFloat64Array, speed: float,
			bank: float, nominal: float, candidate: float, clearance: float,
			threats: Array[Dictionary], trace: bool = false) -> Dictionary:
		scores += 1
		return super._score_bank(state, velocity, speed, bank, nominal, candidate, clearance, threats, trace)

class CandidateCounter extends "reachable_clear_candidate.gd":
	var scores := 0
	func _score_bank(state: PackedFloat64Array, velocity: PackedFloat64Array, speed: float,
			bank: float, nominal: float, candidate: float, clearance: float,
			threats: Array[Dictionary], trace: bool = false) -> Dictionary:
		scores += 1
		return super._score_bank(state, velocity, speed, bank, nominal, candidate, clearance, threats, trace)

var _checks := 0
var _failures := 0
var _comparisons := 0
var _saved_scores := 0
var _held_comparisons := 0
var _clear_comparisons := 0
var _output := ""

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): _output = argument.trim_prefix("--out=")
	if _output.is_empty() or FileAccess.file_exists(_output):
		printerr("Require --out=<new JSON file>")
		quit(2)
		return
	_check("baseline is the frozen production controller", FileAccess.get_sha256(BaselinePath) == ExpectedBaseline)
	var loaded: Dictionary = FieldLoader.load_from()
	_check("Club field loads", loaded.get("ok", false))
	if _failures > 0:
		_finish()
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261020
	var base := BaselineCounter.new()
	var candidate := CandidateCounter.new()
	var pair_failures := 0
	# Independent generated observations exercise branch equivalence. They are not
	# flown paths and do not establish flight stability or prediction accuracy.
	for sequence in 128:
		var configured: bool = base.configure(0, 1, sequence, Trim, loaded.field) \
			and candidate.configure(0, 1, sequence, Trim, loaded.field)
		if not configured:
			pair_failures += 1
			continue
		base.diagnostics_enabled = sequence % 2 == 0
		candidate.diagnostics_enabled = base.diagnostics_enabled
		# Suppress console output only; retain diagnostic calculations for comparison.
		base._plan_diagnostic_count = base.MAX_PLAN_DIAGNOSTICS
		candidate._plan_diagnostic_count = candidate.MAX_PLAN_DIAGNOSTICS
		var pose: Dictionary = base.initial_pose()
		for phase in 10:
			var snapshot := _snapshot(pose, rng, phase)
			var traffic: Array = _traffic(snapshot, rng, phase)
			var tick: int = phase * 244
			base.scores = 0
			candidate.scores = 0
			var was_held: bool = base.snapshot_state().has_held_maneuver
			var expected: Dictionary = base.command(snapshot, tick, traffic)
			var actual: Dictionary = candidate.command(snapshot, tick, traffic)
			_comparisons += 1
			if var_to_bytes(expected) != var_to_bytes(actual) \
					or var_to_bytes(base.snapshot_state()) != var_to_bytes(candidate.snapshot_state()) \
					or var_to_bytes(base._last_decision) != var_to_bytes(candidate._last_decision):
				pair_failures += 1
				printerr("Differential mismatch sequence=%d phase=%d" % [sequence, phase])
			_saved_scores += base.scores - candidate.scores
			if was_held:
				_held_comparisons += 1
				if base.scores != candidate.scores: pair_failures += 1
			elif candidate.scores < base.scores:
				_clear_comparisons += 1
				if candidate.scores != 1 or base.scores != 12: pair_failures += 1
	_check("generated commands, latch and diagnostics are byte-identical", pair_failures == 0)
	_check("clear branch skips exactly eleven scores", _clear_comparisons > 0 and _saved_scores == _clear_comparisons * 11)
	_check("held maneuvers still evaluate every original score", _held_comparisons > 0)
	# Exact zero is deliberately included: the original rule is >= 0, not > 0.
	for clearance: float in [25.0 - 1.0e-9, 25.0, 25.0 + 1.0e-9]:
		base.configure(0, 1, 0, Trim, loaded.field)
		candidate.configure(0, 1, 0, Trim, loaded.field)
		base.diagnostics_enabled = false
		candidate.diagnostics_enabled = false
		var snapshot := _snapshot(base.initial_pose(), rng, 0)
		snapshot.ground_clearance_m = clearance
		base.scores = 0
		candidate.scores = 0
		var traffic: Array = _traffic(snapshot, rng, 0)
		var expected: Dictionary = base.command(snapshot, 0, traffic)
		var actual: Dictionary = candidate.command(snapshot, 0, traffic)
		_check("score boundary %.12f preserves packet and latch" % clearance,
			var_to_bytes(expected) == var_to_bytes(actual) \
			and var_to_bytes(base.snapshot_state()) == var_to_bytes(candidate.snapshot_state()))
		_check("score boundary %.12f preserves branch semantics" % clearance,
			candidate.scores == (1 if clearance >= 25.0 else base.scores))
	_finish()

func _snapshot(pose: Dictionary, rng: RandomNumberGenerator, phase: int) -> Dictionary:
	var heading := float(pose.heading_rad)
	var roll := rng.randf_range(-0.4, 0.4) if phase > 0 else 0.0
	var wind := PackedFloat64Array([rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5), 0.0])
	var state: PackedFloat64Array = Body.make_state(
		PackedFloat64Array([pose.north, pose.east, -pose.height_m]),
		PackedFloat64Array([15.0, 0.0, 0.0]), Math3D.q_from_euler(heading, 0.0, roll),
		PackedFloat64Array([rng.randf_range(-0.1, 0.1), 0.0, 0.0]))
	return {state = state, airspeed_m_s = 15.0, wind_ned = wind,
		ground_clearance_m = 35.0, trim = Trim}

func _traffic(snapshot: Dictionary, rng: RandomNumberGenerator, phase: int) -> Array:
	if phase == 4 or phase == 5: return []
	var own: PackedFloat64Array = snapshot.state
	var heading: float = Math3D.q_to_euler(own.slice(Body.ATT, Body.ATT + 4))[0]
	var traffic: Array = []
	var near: bool = phase in [1, 2, 6, 7]
	for index in (4 if phase == 2 or phase == 7 else 1):
		var distance := rng.randf_range(35.0, 90.0) if near else 1000.0
		var offset := rng.randf_range(-0.8, 0.8) if near else 0.0
		traffic.append({id = "other-%d" % index, is_player = index == 0, wingspan_m = 1.7,
			state = Body.make_state(PackedFloat64Array([
				own[0] + distance * cos(heading + offset), own[1] + distance * sin(heading + offset), own[2]]),
				PackedFloat64Array([15.0, 0.0, 0.0]), Math3D.q_from_euler(heading + PI, 0.0, 0.0),
				PackedFloat64Array([0.0, 0.0, 0.0])), wind_ned = snapshot.wind_ned})
	return traffic

func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL: ", label)

func _finish() -> void:
	var report := {format = "openrc-afc-clear-fast-path-proof v1", checks = _checks, failures = _failures,
		comparisons = _comparisons, clear_comparisons = _clear_comparisons,
		held_comparisons = _held_comparisons, avoided_score_evaluations = _saved_scores,
		baseline_sha256 = FileAccess.get_sha256(BaselinePath),
		candidate_sha256 = FileAccess.get_sha256(CandidatePath),
		fixture_sha256 = FileAccess.get_sha256(get_script().resource_path),
		scope = "synthetic differential command/state oracle; not physical-flight or timing qualification"}
	var file := FileAccess.open(_output, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write fast-path proof")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("clear fast path: %d checks, %d failed; %d paired commands" % [_checks, _failures, _comparisons])
	quit(1 if _failures > 0 else 0)

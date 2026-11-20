# Draft only: root runs this through the checked runner after import.
# Uses the stock strict 3 m disarmed drop from test_mr_graded_crashes.gd.
# The early checkpoint is captured without modification inside a real crash event.
extends SceneTree

const Session := preload("res://sim/multirotor/session.gd")
const Fixtures := preload("res://tests/mr_fixtures.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const Plant := preload("res://physics/multirotor/controlled_plant.gd")

var checks: Array[Dictionary] = []
var failures := 0
var observations: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _check(name: String, passed: bool) -> void:
	checks.append({"name": name, "passed": passed})
	if not passed:
		failures += 1


func _new_session() -> Node:
	var s: Node = Session.new()
	root.add_child(s)
	var ok: bool = s.prepare({}, {"start": "air", "altitude_m": 3.0, "crash_model": "strict"})
	_check("session prepared with stock strict 3 m drop", ok)
	return s


func _finish() -> void:
	print("ROUND2_QUAD_CHECKPOINT_COMPLETE " + JSON.stringify({
		"checks": checks, "check_count": checks.size(), "failures": failures,
		"observations": observations,
	}))
	quit(1 if failures > 0 else 0)


func _run() -> void:
	var source: Node = _new_session()
	if not source.prepared:
		observations["prepare_error"] = str(source.load_error)
		source.free()
		_finish()
		return

	# A normal checkpoint before a collision remains a valid restore control.
	var before: Dictionary = source.checkpoint()
	_check("pre-crash checkpoint is available", not before.is_empty())
	var captured: Array[Dictionary] = []
	var signalled_reasons: Array[String] = []
	source.sim.events_located.connect(func(_tick: int, events: Array[Dictionary]) -> void:
		for event: Dictionary in events:
			if str(event.get("type", "")) == "crash":
				captured.append(source.checkpoint()))
	source.crashed.connect(func(reason: String) -> void: signalled_reasons.append(reason))
	_check("source starts", source.resume())
	var accepted := true
	var neutral: PackedFloat64Array = Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0)
	for _i: int in 480:
		if not source.tick_once(neutral):
			accepted = false
			break
		if not source.crash.is_empty():
			break
	var after: Dictionary = source.checkpoint()
	_check("real stock drop accepts ticks and reports one hard impact", accepted \
		and str(source.crash.get("reason", "")) == "Hard impact" and signalled_reasons.size() == 1)
	_check("real crash event invoked the checkpoint observer once", captured.size() == 1)
	_check("post-tick crash checkpoint is available", not after.is_empty())
	if captured.size() != 1 or after.is_empty() or source.crash.is_empty():
		observations["source"] = {"tick": int(source.sim.tick), "reason": str(source.crash.get("reason", "")),
			"callback_count": captured.size(), "fault": str(source.fault_reason)}
		source.free()
		_finish()
		return

	var early: Dictionary = captured[0]
	var callback_available: bool = not early.is_empty()
	var early_motor := -1
	var early_cut := -1.0
	var early_tape := -1
	if callback_available:
		early_motor = int(early.kernel.modes[FC.MODE_MOTOR])
		early_cut = float(early.kernel.continuous[Plant.C_CUT_LATCH])
		early_tape = int(early.tape_ticks)
		_check("callback and post-tick checkpoints contain the same committed kernel", \
			var_to_bytes(early.kernel) == var_to_bytes(after.kernel))
	_check("post-tick checkpoint preserves the accepted terminal record and cut", \
		not after.crash.is_empty() and int(after.kernel.modes[FC.MODE_MOTOR]) == FC.MOTOR_CRASHED \
		and float(after.kernel.continuous[Plant.C_CUT_LATCH]) == 1.0)
	# Either refusal at this in-progress owner boundary, or a complete matching envelope, is coherent.
	var callback_coherent: bool = not callback_available
	if callback_available:
		callback_coherent = early.crash == after.crash and int(early.tape_ticks) == int(after.tape_ticks)
	_check("callback checkpoint is unavailable or contains the complete accepted session boundary", callback_coherent)
	observations["source"] = {"crash_reason": str(source.crash.get("reason", "")),
		"crash_tick": int(source.sim.tick), "callback_available": callback_available,
		"callback_crash_present": callback_available and not early.get("crash", {}).is_empty(),
		"callback_motor": early_motor, "callback_cut": early_cut, "callback_tape_ticks": early_tape,
		"post_crash_present": not after.crash.is_empty(), "post_tape_ticks": int(after.tape_ticks)}

	var clean: Node = _new_session()
	var good: Node = _new_session()
	var bad: Node = _new_session()
	if not clean.prepared or not good.prepared or not bad.prepared:
		source.free()
		clean.free()
		good.free()
		bad.free()
		_finish()
		return

	var restored_before: bool = clean.restore_checkpoint(before)
	var clean_resume: bool = clean.resume() if restored_before else false
	_check("ordinary pre-crash checkpoint restores and resumes", restored_before and clean_resume \
		and clean.crash.is_empty() and int(clean.sim.modes[FC.MODE_MOTOR]) != FC.MOTOR_CRASHED)

	var restored_after: bool = good.restore_checkpoint(after)
	good.pause("probe control")
	var good_resume: bool = good.resume() if restored_after else false
	_check("post-crash checkpoint restores the cut and refuses resume", restored_after \
		and not good.crash.is_empty() and not good_resume \
		and int(good.sim.modes[FC.MODE_MOTOR]) == FC.MOTOR_CRASHED \
		and float(good.sim.continuous[Plant.C_CUT_LATCH]) == 1.0)

	var restored_early := false
	var bad_resume := false
	var bad_crashed := false
	var bad_motor := -1
	var bad_cut := -1.0
	if callback_available:
		restored_early = bad.restore_checkpoint(early)
		if restored_early:
			bad.pause("probe control")
			bad_resume = bad.resume()
			bad_crashed = bool(bad.telemetry().get("crashed", false))
			bad_motor = int(bad.sim.modes[FC.MODE_MOTOR])
			bad_cut = float(bad.sim.continuous[Plant.C_CUT_LATCH])
			_check("restored terminal frame reports its crash and refuses resume", \
				bad_crashed and not bad.crash.is_empty() and not bad_resume)
	observations["restore"] = {"pre_restored": restored_before, "pre_resume": clean_resume,
		"normal_restored": restored_after, "normal_resume": good_resume,
		"callback_restored": restored_early, "callback_resume": bad_resume,
		"callback_telemetry_crashed": bad_crashed, "callback_motor": bad_motor, "callback_cut": bad_cut}

	source.free()
	clean.free()
	good.free()
	bad.free()
	_finish()

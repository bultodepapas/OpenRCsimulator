extends SceneTree

## A replayed manual recovery pauses the session exactly as the live one does, so the replay must
## re-arm with a neutral sample and resume before the next recorded tick, as the pilot did live.
const Session = preload("res://sim/ground_vehicle/session.gd")
const SEGMENT_TICKS := 96
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")

func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		push_error("FAIL: " + label)

func _neutral() -> Dictionary:
	return {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true}

## Live re-arm: a neutral armed sample while paused, then an explicit resume.
func _arm(session) -> bool:
	return session.tick_once(_neutral()) and session.resume() and not session.paused

## Varying, non-neutral controls so the control tape carries arbitrary float64 values.
func _drive(session, ticks: int, phase: float) -> bool:
	var ok := true
	for index in ticks:
		var t := float(index)
		var controls := {"throttle": 0.6 + 0.4 * sin(0.05 * t + phase), "steering": 0.3 * sin(0.031 * t + phase),
			"brake": 0.25 if index % 48 >= 40 else 0.0, "reverse": false, "armed": true}
		ok = session.tick_once(controls) and ok
	return ok

## Replay the live tape and actions on a fresh session; it must end bytewise where the live run ended.
func _expect_exact_replay(label: String, live, vehicle_id: String) -> void:
	live.pause()
	var expected: Dictionary = live.checkpoint()
	var replayer = Session.new()
	_check(label + ": replay session prepares", replayer.prepare_default({}, vehicle_id))
	var replayed: bool = replayer.replay(live.control_tape_snapshot(), live.recovery_actions_snapshot())
	if not replayed:
		print("%s: replay error: %s" % [label, replayer.load_error])
	_check(label + ": replay succeeds", replayed)
	_check(label + ": replay reaches the live final tick (%d vs %d)" % [replayer.tick, live.tick],
		replayer.tick == live.tick)
	_check(label + ": replay state is byte exact",
		replayer.state_snapshot().to_byte_array() == live.state_snapshot().to_byte_array())
	var actual: Dictionary = replayer.checkpoint()
	_check(label + ": replay checkpoint is identical", not expected.is_empty() and not actual.is_empty()
		and str(actual.get("checkpoint_sha256", "")) == str(expected.get("checkpoint_sha256", "-"))
		and JSON.stringify(actual, "", true, true) == JSON.stringify(expected, "", true, true))
	_check(label + ": replay ends paused and marked invalid", replayer.paused and not replayer.run_valid)
	replayer.free()

func _run() -> void:
	# Two recoveries mid-tape: the second action is reachable only if the first one re-armed.
	var twice = Session.new()
	_check("two recoveries: prepares", twice.prepare_default())
	var ok: bool = _arm(twice) and _drive(twice, SEGMENT_TICKS, 0.0)
	var before_recovery: PackedFloat64Array = twice.state_snapshot()
	ok = twice.manual_recovery() and twice.paused and ok
	_check("two recoveries: recovery moves the vehicle back",
		twice.state_snapshot().to_byte_array() != before_recovery.to_byte_array())
	ok = _arm(twice) and _drive(twice, SEGMENT_TICKS, 1.0) and ok
	ok = twice.manual_recovery() and _arm(twice) and _drive(twice, SEGMENT_TICKS, 2.0) and ok
	_check("two recoveries: live run", ok and twice.tick == 3 * SEGMENT_TICKS
		and twice.recovery_actions_snapshot().size() == 2)
	_expect_exact_replay("two recoveries", twice, "mt8-bisonte")
	twice.free()
	# One recovery mid-tape as the last action: the controls after it must still be replayed.
	var last = Session.new()
	_check("last-action recovery: prepares", last.prepare_default())
	ok = _arm(last) and _drive(last, SEGMENT_TICKS, 0.5) and last.manual_recovery()
	ok = _arm(last) and _drive(last, SEGMENT_TICKS, 1.5) and ok
	_check("last-action recovery: live run", ok and last.tick == 2 * SEGMENT_TICKS
		and last.recovery_actions_snapshot().size() == 1)
	_expect_exact_replay("last-action recovery", last, "mt8-bisonte")
	last.free()
	# A recovery on the final tape tick has no later controls to re-arm for.
	var at_end = Session.new()
	_check("end-of-tape recovery: prepares", at_end.prepare_default())
	ok = _arm(at_end) and _drive(at_end, SEGMENT_TICKS, 2.5) and at_end.manual_recovery()
	_check("end-of-tape recovery: live run", ok and at_end.tick == SEGMENT_TICKS
		and int(at_end.recovery_actions_snapshot()[0].tick) == SEGMENT_TICKS)
	_expect_exact_replay("end-of-tape recovery", at_end, "mt8-bisonte")
	at_end.free()
	# Nitro service then recovery at one tick: the re-arm follows the last action, whatever its type.
	var nitro = Session.new()
	_check("service then recovery: prepares", nitro.prepare_default({}, "monster-car-2"))
	ok = _arm(nitro)
	for _index in 2 * SEGMENT_TICKS: ok = nitro.tick_once(_neutral()) and ok
	nitro.pause()
	_check("service then recovery: idle vehicle is stationary", ok and nitro.nitro_service_stationary())
	ok = nitro.service_nitro("stop") and nitro.manual_recovery() and ok
	ok = _arm(nitro) and _drive(nitro, SEGMENT_TICKS, 3.0) and ok
	var nitro_actions: Array = nitro.recovery_actions_snapshot()
	_check("service then recovery: live run", ok and nitro.tick == 3 * SEGMENT_TICKS and nitro_actions.size() == 2
		and nitro_actions[0].type == "nitro_service" and nitro_actions[1].type == "manual_recovery"
		and int(nitro_actions[0].tick) == int(nitro_actions[1].tick))
	_expect_exact_replay("service then recovery", nitro, "monster-car-2")
	nitro.free()
	print("RCV recovery replay: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)

extends SceneTree

const Motion := preload("res://audio/mechanical_motion.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_accepted_servo_motion()
	_test_gear_target_and_endpoint()
	_test_pause_and_rewind_prime()
	_test_invalid_and_duplicate_inputs()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_accepted_servo_motion() -> void:
	var observer: Dictionary = {}
	var result: Dictionary = Motion.observe(observer, _snapshot(1, 0.0, 0.0, false, true))
	observer = result.state
	_check("initial servo state primes without events", result.primed and result.events.is_empty())
	result = Motion.observe(observer, _snapshot(2, 0.0, 0.0, false, true))
	observer = result.state
	_check("unchanged accepted position stays quiet", result.events.is_empty() and not result.channels[0].moving)
	result = Motion.observe(observer, _snapshot(3, 5.0, 0.5, true, true))
	observer = result.state
	_check("accepted servo and gear movement emit one start each", _event_keys(result.events) == ["servo:roll:start", "gear:gear:start"])
	_check("servo speed uses accepted angle delta and tick rate", is_equal_approx(float(result.channels[0].speed_per_s), 1200.0))
	_check("same tick never fabricates another movement event", Motion.observe(observer,
		_snapshot(3, 20.0, 0.9, true, true)).events.is_empty())
	result = Motion.observe(observer, _snapshot(4, 3.0, 0.3, false, true))
	observer = result.state
	var reversal_keys: Array[String] = _event_keys(result.events)
	if reversal_keys != ["servo:roll:reverse", "gear:gear:reverse"]:
		print("observed reversal events: ", result.events)
	_check("accepted direction changes are reversals", reversal_keys == ["servo:roll:reverse", "gear:gear:reverse"])
	result = Motion.observe(observer, _snapshot(5, 3.0, 0.3, false, true))
	observer = result.state
	var stop_keys: Array[String] = _event_keys(result.events)
	if stop_keys != ["servo:roll:stop", "gear:gear:stop"]:
		print("observed stop events: ", result.events)
	_check("stationary accepted state emits stop once", stop_keys == ["servo:roll:stop", "gear:gear:stop"])
	result = Motion.observe(observer, _snapshot(6, 3.0, 0.3, false, true))
	_check("stopped channels do not retrigger on later ticks", result.events.is_empty())


func _test_gear_target_and_endpoint() -> void:
	var observer: Dictionary = Motion.observe({}, _snapshot(10, 0.0, 0.0, false, true)).state
	var result: Dictionary = Motion.observe(observer, _snapshot(11, 0.0, 0.0, true, true))
	observer = result.state
	_check("gear request alone does not play", result.events.is_empty() and not result.gear.moving)
	result = Motion.observe(observer, _snapshot(12, 0.0, 0.6, true, true))
	observer = result.state
	_check("gear starts only after extension changes", _event_keys(result.events) == ["gear:gear:start"])
	result = Motion.observe(observer, _snapshot(13, 0.0, 1.0, true, true))
	observer = result.state
	_check("moving to the endpoint is not yet a lock event", result.events.is_empty() and result.gear.moving)
	result = Motion.observe(observer, _snapshot(14, 0.0, 1.0, true, true))
	_check("accepted arrival at requested down endpoint emits lock", _event_keys(result.events) == ["gear:gear:lock"])
	_check("endpoint lock predicate follows requested direction", Motion.is_locked_endpoint(1.0, true)
		and Motion.is_locked_endpoint(0.0, false) and not Motion.is_locked_endpoint(0.5, true))
	var primed_endpoint: Dictionary = Motion.observe({}, _snapshot(1, 0.0, 1.0, true, true))
	_check("already-down launch does not invent lock audio", primed_endpoint.events.is_empty() and primed_endpoint.primed)


func _test_pause_and_rewind_prime() -> void:
	var observer: Dictionary = Motion.observe({}, _snapshot(20, 0.0, 0.0, false, true)).state
	var moving: Dictionary = Motion.observe(observer, _snapshot(21, 2.0, 0.1, false, true))
	observer = moving.state
	var paused: Dictionary = Motion.observe(observer, _snapshot(21, 15.0, 0.8, true, true, true))
	observer = paused.state
	_check("pause primes changed presentation state without an event", paused.primed and paused.events.is_empty())
	var resumed: Dictionary = Motion.observe(observer, _snapshot(22, 15.0, 0.8, true, true))
	observer = resumed.state
	_check("resume does not replay paused or stale movement", resumed.events.is_empty())
	var rewound: Dictionary = Motion.observe(observer, _snapshot(2, -4.0, 0.2, true, false))
	_check("tick rewind primes silently", rewound.primed and rewound.events.is_empty())


func _test_invalid_and_duplicate_inputs() -> void:
	var invalid: Dictionary = Motion.observe({}, {tick = -1, tick_rate = 240.0})
	_check("negative tick is rejected without state change", not invalid.valid and invalid.state.is_empty())
	var duplicated: Dictionary = Motion.observe({}, {tick = 1, tick_rate = 240.0, channels = [
		{id = "roll", angle_deg = 1.0, position = Vector3.ZERO},
		{id = "roll", angle_deg = 99.0, position = Vector3.ONE},
	], gear = {available = false}})
	_check("duplicate servo IDs count once", duplicated.channels.size() == 1 and is_equal_approx(duplicated.channels[0].value, 1.0))
	var no_tick: Dictionary = Motion.observe(duplicated.state, {channels = [], gear = {}})
	_check("missing tick produces no motion sample", not no_tick.valid and no_tick.events.is_empty())


func _snapshot(tick: int, roll_angle: float, extension: float, target_down: bool,
		has_gear: bool = true, paused: bool = false) -> Dictionary:
	var gear: Dictionary = {available = has_gear, extension = extension,
		target_down = target_down, status = "down" if extension == 1.0 else "up" if extension == 0.0 else "moving",
		position = Vector3(0.0, 0.0, 0.0)}
	return {tick = tick, tick_rate = 240.0, paused = paused,
		channels = [{id = "roll", angle_deg = roll_angle, position = Vector3(1.0, 0.0, 0.0)}],
		gear = gear}


func _event_keys(events: Array) -> Array[String]:
	var keys: Array[String] = []
	for event: Dictionary in events:
		keys.append("%s:%s:%s" % [event.system, event.id, event.event])
	return keys


func _check(label: String, condition: bool) -> void:
	_checks += 1
	print(("ok   " if condition else "FAIL ") + label)
	if not condition:
		_failures += 1

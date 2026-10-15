extends SceneTree

const Settlement := preload("res://economy/settlement.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_duration_and_once()
	_pause_does_not_advance()
	_unsafe_duplicate_resets()
	_motion_airborne_and_bounce_reset()
	_tick_discontinuities_reset()
	_invalid_samples_reset()
	_reset_rearms()
	print("accident settlement: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
	print(("ok   " if passed else "FAIL ") + label)


func _duration_and_once() -> void:
	var detector = Settlement.new()
	_check("first stable sample establishes the timer origin", not detector.observe(1, 0.05, true, 0.1, 0.1))
	for tick in range(2, 41):
		detector.observe(tick, 0.05, true, 0.1, 0.1)
	_check("settlement does not fire before two seconds", not detector.observe(40, 0.05, true, 0.1, 0.1))
	_check("two seconds between accepted samples emits one edge", detector.observe(41, 0.05, true, 0.1, 0.1))
	_check("settled detector emits no second edge", not detector.observe(42, 0.05, true, 0.1, 0.1))
	_check("edge remains once-only while still resting", not detector.observe(43, 0.05, true, 0.0, 0.0))


func _pause_does_not_advance() -> void:
	var detector = Settlement.new()
	_check("pause fixture starts without settlement", not detector.observe(10, 0.05, true, 0.0, 0.0))
	var repeated_edges := 0
	for _repeat in 100:
		if detector.observe(10, 0.05, true, 0.0, 0.0):
			repeated_edges += 1
	_check("repeated tick is inert", repeated_edges == 0)
	for tick in range(11, 50):
		detector.observe(tick, 0.05, true, 0.0, 0.0)
	_check("repeated ticks add no stable time", not detector.observe(49, 0.05, true, 0.0, 0.0))
	_check("settles after two accepted seconds after pause", detector.observe(50, 0.05, true, 0.0, 0.0))


func _unsafe_duplicate_resets() -> void:
	var detector = Settlement.new()
	for tick in range(1, 12):
		detector.observe(tick, 0.1, true, 0.0, 0.0)
	_check("unsafe duplicate does not emit or advance", not detector.observe(11, 0.1, true, 0.3, 0.0))
	_check("first safe tick after unsafe duplicate establishes a new baseline",
		not detector.observe(12, 0.1, true, 0.0, 0.0))
	for tick in range(13, 32):
		detector.observe(tick, 0.1, true, 0.0, 0.0)
	_check("unsafe duplicate reset cannot settle early", not detector.observe(31, 0.1, true, 0.0, 0.0))
	_check("unsafe duplicate requires a full new stable interval", detector.observe(32, 0.1, true, 0.0, 0.0))


func _motion_airborne_and_bounce_reset() -> void:
	var detector = Settlement.new()
	for tick in range(1, 11):
		detector.observe(tick, 0.1, true, 0.1, 0.1)
	_check("linear motion clears a pending stable interval", not detector.observe(11, 0.1, true, 0.51, 0.0))
	_check("post-motion sample restarts the interval", not detector.observe(12, 0.1, true, 0.0, 0.0))
	for tick in range(13, 23):
		detector.observe(tick, 0.1, true, 0.0, 0.0)
	_check("airborne bounce clears a pending stable interval", not detector.observe(23, 0.1, false, 0.0, 0.0))
	_check("landing after bounce starts a new interval", not detector.observe(24, 0.1, true, 0.0, 0.0))
	for tick in range(25, 44):
		detector.observe(tick, 0.1, true, 0.0, 0.0)
	_check("go-around or bounce cannot settle early", not detector.observe(43, 0.1, true, 0.0, 0.0))
	_check("full grounded interval after bounce settles", detector.observe(44, 0.1, true, 0.0, 0.0))


func _tick_discontinuities_reset() -> void:
	var detector = Settlement.new()
	for tick in range(1, 12):
		detector.observe(tick, 0.1, true, 0.0, 0.0)
	_check("forward tick gap starts a fresh window", not detector.observe(20, 0.1, true, 0.0, 0.0))
	for tick in range(21, 31):
		detector.observe(tick, 0.1, true, 0.0, 0.0)
	_check("backward tick discontinuity starts a fresh window", not detector.observe(5, 0.1, true, 0.0, 0.0))
	for tick in range(6, 25):
		detector.observe(tick, 0.1, true, 0.0, 0.0)
	_check("post-discontinuity interval remains pending", not detector.observe(24, 0.1, true, 0.0, 0.0))
	_check("settles only after full stable interval following discontinuity", detector.observe(25, 0.1, true, 0.0, 0.0))


func _invalid_samples_reset() -> void:
	var invalid_dts: Array[float] = [0.0, -0.01, NAN, INF, 0.101]
	for invalid_dt in invalid_dts:
		var detector = Settlement.new()
		for sample in range(1, 11):
			detector.observe(sample, 0.1, true, 0.0, 0.0)
		_check("invalid dt clears the pending window", not detector.observe(11, invalid_dt, true, 0.0, 0.0))
		for sample in range(12, 22):
			detector.observe(sample, 0.1, true, 0.0, 0.0)
		_check("invalid dt cannot be counted", not detector.observe(21, 0.1, true, 0.0, 0.0))
	var invalid_speeds: Array[float] = [-0.1, NAN, INF]
	for invalid_speed in invalid_speeds:
		var detector = Settlement.new()
		for sample in range(1, 11):
			detector.observe(sample, 0.1, true, 0.0, 0.0)
		_check("invalid linear speed clears the pending window", not detector.observe(11, 0.1, true, invalid_speed, 0.0))
		var angular_detector = Settlement.new()
		for sample in range(1, 11):
			angular_detector.observe(sample, 0.1, true, 0.0, 0.0)
		_check("invalid angular speed clears the pending window", not angular_detector.observe(11, 0.1, true, 0.0, invalid_speed))
	var moving := Settlement.new()
	_check("speed boundaries are accepted as low speed", not moving.observe(1, 0.05, true,
		Settlement.MAX_LINEAR_SPEED_MPS, Settlement.MAX_ANGULAR_SPEED_RAD_S))
	_check("angular movement above its policy threshold clears stability",
		not moving.observe(2, 0.05, true, 0.0, Settlement.MAX_ANGULAR_SPEED_RAD_S + 0.001))
	_check("shared stability policy accepts its inclusive thresholds", Settlement.is_stable(true,
		Settlement.MAX_LINEAR_SPEED_MPS, Settlement.MAX_ANGULAR_SPEED_RAD_S))
	_check("shared stability policy rejects airborne samples", not Settlement.is_stable(false, 0.0, 0.0))


func _reset_rearms() -> void:
	var detector = Settlement.new()
	for tick in range(1, 12):
		detector.observe(tick, 0.1, true, 0.0, 0.0)
	_check("reset clears an in-progress interval", not detector.observe(12, 0.1, true, 0.0, 0.0))
	detector.reset()
	_check("reset accepts a new baseline", not detector.observe(1, 0.1, true, 0.0, 0.0))
	for tick in range(2, 21):
		detector.observe(tick, 0.1, true, 0.0, 0.0)
	_check("reset requires a complete new duration", detector.observe(21, 0.1, true, 0.0, 0.0))

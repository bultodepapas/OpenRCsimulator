extends SceneTree

const InputSampler := preload("res://input/ground_vehicle_input.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	_test_keyboard_mapping_and_interlocks()
	_test_gamepad_neutral_arm_and_mapping()
	_test_modal_rearm_and_disconnect()
	_test_malformed_gamepad_fails_safe()
	_test_resting_deadzone_and_full_range()
	print("RCV input: %d checks, %d failed" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		push_error("FAIL: " + label)


func _neutral() -> Dictionary:
	return {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false}


func _test_keyboard_mapping_and_interlocks() -> void:
	var sampler = InputSampler.new()
	var result: Dictionary = sampler.sample({"accelerate": true, "left": true}, {})
	_check("W/A map to forward and left", result.throttle == 1.0 and result.steering == -1.0 and not result.reverse)
	result = sampler.sample({"reverse": true, "right": true}, {})
	_check("S/D map to reverse and right", result.throttle == 1.0 and result.reverse and result.steering == 1.0)
	result = sampler.sample({"accelerate": true, "reverse": true, "left": true, "right": true}, {})
	_check("opposed keys cancel safely", result.throttle == 0.0 and not result.reverse and result.steering == 0.0)
	result = sampler.sample({"accelerate": true, "brake": true}, {})
	_check("space brake overrides drive", result.throttle == 0.0 and result.brake == 1.0)
	result = sampler.sample({"accelerate": true, "blocked": true}, {})
	_check("modal held keys are immediately neutral", result == {"throttle": 0.0, "steering": 0.0, "brake": 0.0,
		"reverse": false, "source": "none", "armed": false})
	result = sampler.sample({"accelerate": true}, {})
	_check("closing modal cannot reuse held key", result.throttle == 0.0 and not result.armed)
	result = sampler.sample({}, {})
	_check("neutral key sample rearms only", result.throttle == 0.0 and result.armed)
	result = sampler.sample({"accelerate": true}, {})
	_check("fresh key press works after neutral", result.throttle == 1.0)


func _test_gamepad_neutral_arm_and_mapping() -> void:
	var sampler = InputSampler.new()
	var neutral_joy := {"connected": true, "device_id": 3, "left_x": 0.0,
		"right_trigger": 0.0, "left_trigger": 0.0, "reverse": false}
	var first_drive := neutral_joy.duplicate(true)
	first_drive.right_trigger = 0.7
	var result: Dictionary = sampler.sample({"accelerate": true}, first_drive)
	_check("gamepad connection is exclusive and requires neutral", result.source == "gamepad"
		and result.throttle == 0.0 and not result.armed)
	result = sampler.sample({}, neutral_joy)
	_check("neutral gamepad sample arms", result.armed and result.throttle == 0.0)
	var drive_joy := {"connected": true, "device_id": 3, "left_x": 0.56,
		"right_trigger": 0.72, "left_trigger": 0.0, "reverse": false}
	result = sampler.sample({}, drive_joy)
	_check("left X and right trigger map to steering and throttle",
		absf(result.steering - ((0.56 - 0.12) / 0.88)) < 1.0e-12 and is_equal_approx(result.throttle, (0.72 - 0.04) / 0.96))
	drive_joy.left_trigger = 0.4
	result = sampler.sample({}, drive_joy)
	_check("left trigger brakes and cuts throttle", is_equal_approx(result.brake, (0.4 - 0.04) / 0.96) and result.throttle == 0.0)
	drive_joy.left_trigger = 0.0
	drive_joy.reverse = true
	result = sampler.sample({}, drive_joy)
	_check("B selects reverse", result.reverse and is_equal_approx(result.throttle, (0.72 - 0.04) / 0.96))
	var replacement := neutral_joy.duplicate(true)
	replacement.device_id = 4
	replacement.right_trigger = 0.8
	result = sampler.sample({}, replacement)
	_check("replacement controller must neutral-arm", not result.armed and result.throttle == 0.0)


func _test_modal_rearm_and_disconnect() -> void:
	var sampler = InputSampler.new()
	var neutral_joy := {"connected": true, "device_id": 1, "left_x": 0.0,
		"right_trigger": 0.0, "left_trigger": 0.0, "reverse": false}
	sampler.sample({}, neutral_joy)
	sampler.sample({}, neutral_joy)
	var drive_joy := neutral_joy.duplicate(true)
	drive_joy.right_trigger = 0.8
	var result: Dictionary = sampler.sample({}, drive_joy)
	_check("armed pad drives before modal", is_equal_approx(result.throttle, (0.8 - 0.04) / 0.96))
	result = sampler.sample({"blocked": true}, drive_joy)
	_check("modal stops gamepad controls", result.throttle == 0.0 and not result.armed)
	result = sampler.sample({}, drive_joy)
	_check("held trigger stays inhibited after modal", result.throttle == 0.0 and not result.armed)
	sampler.sample({}, neutral_joy)
	result = sampler.sample({}, drive_joy)
	_check("gamepad works again after neutral rearm", is_equal_approx(result.throttle, (0.8 - 0.04) / 0.96) and result.armed)
	result = sampler.sample({"accelerate": true}, {})
	_check("device loss outputs one neutral sample", result.throttle == 0.0 and result.source == "none")
	result = sampler.sample({"accelerate": true}, {})
	_check("keyboard cannot take over while key remains held", result.throttle == 0.0 and not result.armed)
	sampler.sample({}, {})
	result = sampler.sample({"accelerate": true}, {})
	_check("keyboard can take over after a neutral sample", result.throttle == 1.0 and result.source == "keyboard")


func _test_malformed_gamepad_fails_safe() -> void:
	var sampler = InputSampler.new()
	var neutral_joy := {"connected": true, "device_id": 5, "left_x": 0.0,
		"right_trigger": 0.0, "left_trigger": 0.0, "reverse": false}
	sampler.sample({}, neutral_joy)
	sampler.sample({}, neutral_joy)
	var bad_joy := neutral_joy.duplicate(true)
	bad_joy.right_trigger = NAN
	var result: Dictionary = sampler.sample({}, bad_joy)
	_check("nonfinite gamepad axis disarms to neutral", result.throttle == 0.0 and not result.armed)
	bad_joy.right_trigger = 1.5
	result = sampler.sample({}, bad_joy)
	_check("out-of-range gamepad axis disarms to neutral", result.throttle == 0.0 and not result.armed)


func _test_resting_deadzone_and_full_range() -> void:
	var sampler = InputSampler.new()
	var joy := {"connected": true, "device_id": 4, "left_x": 0.10,
		"right_trigger": 0.03, "left_trigger": 0.02, "reverse": false}
	for i in 4:
		var rest: Dictionary = sampler.sample({}, joy)
		_check("resting drift stays armed and exactly neutral, sample %d" % i,
			rest.armed and rest.throttle == 0.0 and rest.brake == 0.0 and rest.steering == 0.0)
	joy.left_x = -1.0
	joy.right_trigger = 1.0
	var full: Dictionary = sampler.sample({}, joy)
	_check("deadzone preserves full throttle and full left", full.throttle == 1.0 and full.steering == -1.0)
	joy.left_x = 1.0
	joy.left_trigger = 1.0
	full = sampler.sample({}, joy)
	_check("full brake overrides throttle and full right survives", full.brake == 1.0 and full.throttle == 0.0 and full.steering == 1.0)
	joy.left_x = 0.0
	joy.left_trigger = 0.041
	full = sampler.sample({}, joy)
	_check("brake just outside deadzone already cuts drive", full.brake > 0.0 and full.throttle == 0.0)
	joy.left_trigger = 0.0
	joy.right_trigger = 0.04
	full = sampler.sample({}, joy)
	_check("trigger deadzone boundary is exactly zero", full.throttle == 0.0)
	joy.right_trigger = -0.1
	full = sampler.sample({}, joy)
	_check("negative mapped trigger disarms instead of becoming neutral", not full.armed)

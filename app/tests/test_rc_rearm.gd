# D6b-R2: calibration needs fresh low-throttle evidence; raw connection history stays intact.
extends SceneTree

const Radio = preload("res://input/rc_input.gd")
const Calibration = preload("res://input/rc_calibration.gd")
const ID: int = 15
const INFO: Dictionary = {name = "Fake EdgeTX"}
const DT: float = 1.0 / 240.0
var checks: int = 0
var failures: int = 0


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)


func profile(axis: int, minimum: float, maximum: float, inverted: bool) -> Dictionary:
	var result: Dictionary = Radio.DEFAULT_PROFILE.duplicate(true)
	result.throttle = {axis = axis, min = minimum, center = minimum, max = maximum, invert = inverted}
	var available: Array[int] = []
	for index: int in Radio.AXES:
		if index != axis:
			available.append(index)
	for index: int in 3:
		result[["roll", "pitch", "yaw"][index]].axis = available[index]
	return result


func poll(radio: Radio, throttle: float) -> void:
	var throttle_axis: int = radio.profile.throttle.axis
	radio.poll(func(_device: int, axis: int) -> float: return throttle if axis == throttle_axis else 0.0, DT)


func safe(radio: Radio) -> bool:
	return not radio.armed and radio.sticks().throttle == 0.0


func calibration_boundary(axis: int, endpoints: Array) -> void:
	var p: Dictionary = profile(axis, endpoints[0], endpoints[1], endpoints[2])
	var label: String = "axis %d endpoints %s" % [axis, endpoints]
	check(label + " valid fixture", Calibration.valid(p))
	var low: float = p.throttle.max if p.throttle.invert else p.throttle.min
	var high: float = p.throttle.min if p.throttle.invert else p.throttle.max
	var radio: Radio = Radio.new()
	radio.connect_device(ID, INFO, p)
	radio.on_motion(ID, axis, low)
	poll(radio, low)
	check(label + " positive control arms", radio.armed)
	# Every raw axis has actually reported before the new calibration is applied.
	for index: int in Radio.AXES:
		radio.on_motion(ID, index, low if index == axis else 0.25)
	var raw_before: PackedByteArray = radio.axes.to_byte_array()
	radio.use_profile(p, "calibrated")
	check(label + " applying calibration disarms", safe(radio))
	var history: bool = radio.axes.to_byte_array() == raw_before
	for index: int in Radio.AXES:
		history = history and radio.has_axis_sample(index)
	check(label + " calibration retains raw values and connection history", history)
	poll(radio, low)
	check(label + " stale pre-profile event cannot arm", safe(radio))
	radio.on_motion(ID + 1, axis, low)
	radio.on_motion(ID, -1, low)
	radio.on_motion(ID, Radio.AXES, low)
	radio.on_motion(ID, p.roll.axis, low)
	poll(radio, low)
	check(label + " other devices or axes cannot rearm", safe(radio))
	radio.on_motion(ID, axis, high)
	poll(radio, low)
	check(label + " fresh high event and low poll cannot arm", safe(radio))
	radio.on_motion(ID, axis, low)
	poll(radio, high)
	check(label + " low event with high current poll remains safe", safe(radio))
	radio.on_motion(ID, axis, high)
	poll(radio, low)
	check(label + " later high event replaces low evidence", safe(radio))
	radio.on_motion(ID, axis, low)
	poll(radio, low)
	check(label + " fresh low event and current low arm", radio.armed)
	poll(radio, high)
	check(label + " armed throttle still follows the stick", absf(radio.sticks().throttle - 1.0) < 1e-12)
	# Applying even the same profile starts a new arming interval.
	radio.use_profile(p, "calibrated")
	poll(radio, low)
	check(label + " repeated profile cannot reuse prior low event", safe(radio))
	for invalid: float in [NAN, INF, -INF]:
		radio.on_motion(ID, axis, invalid)
		poll(radio, low)
		check(label + " nonfinite event is not low-throttle evidence " + str(invalid), safe(radio))
	for fraction: float in [0.06, 0.04]:
		var value: float = low + fraction * (high - low)
		radio.on_motion(ID, axis, value)
		poll(radio, value)
		check(label + " arming threshold " + str(fraction), radio.armed == (fraction < Radio.ARM_THROTTLE))
	radio.disconnect_device()
	radio.connect_device(ID, INFO, p)
	poll(radio, low)
	check(label + " reconnect clears low evidence", safe(radio) and not radio.has_axis_sample(axis))
	radio.on_motion(ID, axis, low)
	poll(radio, low)
	check(label + " reconnect accepts a fresh low event", radio.armed)
	radio.connect_device(ID, INFO, p)
	poll(radio, low)
	check(label + " direct device replacement cannot reuse low evidence", safe(radio) and not radio.has_axis_sample(axis))


func changed_channel() -> void:
	var radio: Radio = Radio.new()
	radio.connect_device(ID, INFO)
	radio.on_motion(ID, 2, -1.0)
	radio.on_motion(ID, 9, -1.0)
	poll(radio, -1.0)
	check("channel-change positive control", radio.armed)
	radio.use_profile(profile(9, -1.0, 1.0, false), "calibrated")
	radio.on_motion(ID, 2, -1.0)
	poll(radio, -1.0)
	check("old throttle axis cannot arm newly assigned axis", safe(radio) and radio.has_axis_sample(9))
	radio.on_motion(ID, 9, -1.0)
	poll(radio, -1.0)
	check("new throttle axis low event arms", radio.armed)


func gamepad_control() -> void:
	var radio: Radio = Radio.new()
	radio.connect_device(ID, {name = "Fake gamepad", known = true})
	for _tick: int in 240:
		poll(radio, -1.0)
	check("gamepad rate throttle rises normally without radio events", radio.armed and absf(radio.sticks().throttle - 0.5) < 1e-9)
	radio.use_profile(Radio.GAMEPAD_PROFILE, "gamepad")
	poll(radio, 0.0)
	check("gamepad profile reset starts armed at idle", radio.armed and radio.sticks().throttle == 0.0)


func _initialize() -> void:
	for axis: int in [0, 2, 9]:
		for endpoints: Array in [[-1.0, 1.0, false], [-1.0, 1.0, true], [0.0, 1.0, false], [0.0, 1.0, true], [-0.8, 0.9, false], [-0.8, 0.9, true]]:
			calibration_boundary(axis, endpoints)
	changed_channel()
	gamepad_control()
	print("D6b-R2: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

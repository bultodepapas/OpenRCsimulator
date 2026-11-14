extends SceneTree
const Pilot = preload("res://input/airship_input.gd")
const Session = preload("res://sim/airship/session.gd")
const DT := 1.0 / 240.0
var keys := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
var axes := {}
func _initialize() -> void:
	var session := Session.new()
	session.prepared = true # Isolate the production resume gate; no vehicle physics is run.
	var keyboard := Pilot.new()
	keyboard.read_keys = func() -> Dictionary: return keys.duplicate()
	keys.throttle = 1.0
	var sample: Dictionary
	for i in 240:
		sample = keyboard.sample(DT, true)
	print("Keyboard before pause: throttle=", sample.sticks[3])
	keys.throttle = -1.0
	for i in 1200:
		sample = keyboard.sample(DT, false)
	print("Keyboard 5s S while paused: throttle=", sample.sticks[3], " resume=", session.resume(sample.sticks), " reason=", session.pause_reason)
	var yaw := Pilot.new()
	yaw.read_keys = func() -> Dictionary: return keys.duplicate()
	keys.throttle = 0.0
	keys.yaw = 1.0
	for i in 240:
		sample = yaw.sample(DT, true)
	print("Keyboard before pause: yaw=", sample.sticks[2])
	keys.yaw = 0.0
	for i in 1200:
		sample = yaw.sample(DT, false)
	print("Keyboard 5s released yaw while paused: yaw=", sample.sticks[2], " resume=", session.resume(sample.sticks), " reason=", session.pause_reason)
	var pad := Pilot.new()
	pad.read_axis = func(_id: int, axis: int) -> float: return float(axes.get(axis, 0.0))
	pad.read_button = func(_id: int, _button: int) -> bool: return false
	pad.radio.confirmed_gamepad_connection = func(_id: int) -> bool: return true
	pad.radio.connect_device(3, {name = "Mock known pad", known = true})
	axes[1] = -1.0
	for i in 240:
		sample = pad.sample(DT, true)
	print("Gamepad before pause: armed=", sample.armed, " throttle=", sample.sticks[3])
	axes[1] = 1.0
	for i in 1200:
		sample = pad.sample(DT, false)
	print("Gamepad 5s down while paused: armed=", sample.armed, " throttle=", sample.sticks[3], " resume=", session.resume(sample.sticks), " reason=", session.pause_reason)
	session.free()
	print("airship pause probe complete")
	quit()

extends SceneTree
const MR = preload("res://input/multirotor_input.gd")
const Airship = preload("res://input/airship_input.gd")
const Profile = preload("res://input/controller_profile.gd")
const FC = preload("res://physics/multirotor/flight_controller.gd")
var axes := {0: 0.0, 1: 0.0, 2: -1.0, 3: 0.0}
var arm := false
func _initialize() -> void:
	var mr := MR.new()
	mr.read_axis = func(_device: int, axis: int) -> float: return float(axes.get(axis, 0.0))
	mr.read_button = func(_device: int, _button: int) -> bool: return false
	mr.read_keys = func() -> Dictionary: return {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0, arm = arm, mode = false}
	mr.connect_device(7, {name = "Mock radio", kind = "radio"}, Profile.defaults("radio", "radio_custom"))
	var s: Dictionary = mr.sample(1.0 / 240.0, true)
	print("MR initial: radio_armed=", mr.radio.armed, " ready=", s.ready, " source_ready=", s.pilot[FC.IN_SOURCE_READY], " arm=", s.pilot[FC.IN_ARM], " throttle=", s.pilot[FC.IN_THROTTLE])
	arm = true
	s = mr.sample(1.0 / 240.0, true)
	print("MR fresh keyboard arm: radio_armed=", mr.radio.armed, " ready=", s.ready, " source_ready=", s.pilot[FC.IN_SOURCE_READY], " arm=", s.pilot[FC.IN_ARM], " throttle=", s.pilot[FC.IN_THROTTLE])
	axes[2] = 1.0
	s = mr.sample(1.0 / 240.0, true)
	print("MR poll full throttle: radio_armed=", mr.radio.armed, " ready=", s.ready, " source_ready=", s.pilot[FC.IN_SOURCE_READY], " arm=", s.pilot[FC.IN_ARM], " throttle=", s.pilot[FC.IN_THROTTLE], " rc_reader_throttle=", mr.radio.sticks().throttle)
	var air := Airship.new()
	air.read_axis = func(_device: int, _axis: int) -> float: return 0.0
	air.read_button = func(_device: int, _button: int) -> bool: return false
	air.radio.connect_device(3, {name = "Mock standard gamepad", known = true})
	var a: Dictionary
	for i in 240:
		a = air.sample(1.0 / 240.0, false)
	print("AIRSHIP after 1s neutral polling, no events: armed=", a.armed, " verifier_bound=", air.radio.confirmed_gamepad_connection.is_valid())
	for name in ["roll", "pitch", "yaw", "throttle"]:
		air.radio.on_motion(3, int(air.radio.profile[name].axis), 0.0)
	for i in 60:
		a = air.sample(1.0 / 240.0, false)
	print("AIRSHIP after four axis motion events and 0.25s neutral: armed=", a.armed)
	print("probe complete")
	quit()

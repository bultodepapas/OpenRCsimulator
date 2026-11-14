extends SceneTree
const MR = preload("res://input/multirotor_input.gd")
const Profile = preload("res://input/controller_profile.gd")
const FC = preload("res://physics/multirotor/flight_controller.gd")
const Plant = preload("res://physics/multirotor/controlled_plant.gd")
const Fixtures = preload("res://tests/mr_fixtures.gd")
const Rates = preload("res://physics/multirotor/rates.gd")
var axes := {0: 0.0, 1: 0.0, 2: -1.0, 3: 0.0}
var arm := false
func _initialize() -> void:
	var mr := MR.new()
	mr.read_axis = func(_device: int, axis: int) -> float: return float(axes.get(axis, 0.0))
	mr.read_button = func(_device: int, _button: int) -> bool: return false
	mr.read_keys = func() -> Dictionary: return {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0, arm = arm, mode = false}
	mr.connect_device(7, {name = "Mock radio", kind = "radio"}, Profile.defaults("radio", "radio_custom"))
	var made: Dictionary = Plant.create(Fixtures.electric(), Rates.default_profile(), FC.THROTTLE_ABSOLUTE)
	if not made.ok:
		print("plant failed: ", made.errors)
		quit(1)
		return
	var plant: RefCounted = made.plant
	var frame: Dictionary = plant.initial_frame(Fixtures.body(0.1), mr.source_generation)
	var sample: Dictionary = mr.sample(1.0 / 240.0, true)
	var next: Dictionary = plant.sample_tick(frame, sample.pilot, {dt = 1.0 / 240.0})
	frame.aux = next.aux
	frame.modes = next.modes
	print("OFF: input_ready=", sample.ready, " radio_armed=", mr.radio.armed, " motor=", frame.modes[FC.MODE_MOTOR])
	arm = true
	sample = mr.sample(1.0 / 240.0, true)
	next = plant.sample_tick(frame, sample.pilot, {dt = 1.0 / 240.0})
	frame.aux = next.aux
	frame.modes = next.modes
	print("ON: input_ready=", sample.ready, " radio_armed=", mr.radio.armed, " motor=", frame.modes[FC.MODE_MOTOR], " motor_armed_enum=", FC.MOTOR_ARMED)
	axes[2] = 1.0
	sample = mr.sample(1.0 / 240.0, true)
	next = plant.sample_tick(frame, sample.pilot, {dt = 1.0 / 240.0})
	frame.aux = next.aux
	frame.modes = next.modes
	print("FULL: radio_armed=", mr.radio.armed, " motor=", frame.modes[FC.MODE_MOTOR], " collective=", frame.aux[FC.AUX_COLLECTIVE], " command0=", frame.aux[FC.AUX_COMMAND])
	print("quad FC probe complete")
	quit()

extends SceneTree

const ControlSurfaces := preload("res://physics/control_surfaces.gd")
const Commands := preload("res://input/commands.gd")
const Aero := preload("res://physics/aero.gd")

var _checks := 0
var _failures := 0

func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])

func _bits(value: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	return bytes.hex_encode()

func _same_surfaces(actual: Dictionary, expected: Dictionary) -> bool:
	for name: String in ["aileron_right", "aileron_left", "elevator", "rudder"]:
		if _bits(actual[name]) != _bits(expected[name]):
			return false
	return true

func _near_surfaces(actual: Dictionary, expected: Dictionary) -> bool:
	for name: String in ["aileron_right", "aileron_left", "elevator", "rudder"]:
		if absf(actual[name] - expected[name]) >= 1e-12:
			return false
	return true

func _initialize() -> void:
	var throws_deg := {"aileron": 30.0, "aileron_down": 10.0, "elevator": 20.0, "rudder": 40.0}
	var positive := ControlSurfaces.surface_deflections_deg({"roll": 1.0, "pitch": 1.0, "yaw": 1.0}, throws_deg)
	_check("positive roll raises right aileron", positive.aileron_right == 30.0)
	_check("positive roll lowers differential left aileron", positive.aileron_left == -10.0)
	_check("positive pitch raises elevator", positive.elevator == 20.0)
	_check("positive yaw moves rudder right", positive.rudder == 40.0)
	var negative := ControlSurfaces.surface_deflections_deg({"roll": -1.0, "pitch": -1.0, "yaw": -1.0}, throws_deg)
	_check("negative roll lowers right aileron by down throw", negative.aileron_right == -10.0)
	_check("negative roll raises left aileron by up throw", negative.aileron_left == 30.0)
	_check("negative pitch lowers elevator", negative.elevator == -20.0)
	_check("negative yaw moves rudder left", negative.rudder == -40.0)
	var extreme := ControlSurfaces.surface_deflections_deg({"roll": 2.0, "pitch": -1.5, "yaw": 1.25}, throws_deg)
	_check("axis extremes preserve extrapolation", extreme.aileron_right == 60.0 and extreme.aileron_left == -20.0
		and extreme.elevator == -30.0 and extreme.rudder == 50.0, str(extreme))
	var symmetric := ControlSurfaces.surface_deflections_deg({"roll": 1.0, "pitch": 0.0, "yaw": 0.0},
		{"aileron": 30.0, "elevator": 20.0, "rudder": 40.0})
	_check("absent down throw stays symmetric", symmetric.aileron_left == -30.0)

	var hinge := ControlSurfaces.hinge_rotations({"roll": 1.0, "pitch": 1.0, "yaw": 1.0}, throws_deg)
	_check("aileron hinges preserve x-axis signs", hinge.aileron_right.x == -deg_to_rad(30.0)
		and hinge.aileron_left.x == -deg_to_rad(-10.0), str(hinge))
	_check("elevator hinge preserves x-axis sign", hinge.elevator.x == -deg_to_rad(20.0))
	_check("rudder hinge preserves positive y-axis sign", hinge.rudder.y == deg_to_rad(40.0))
	var aero := ControlSurfaces.deflections_from_surfaces(positive)
	_check("aero convention negates all pilot-positive deflections",
		aero.aileron_right == -deg_to_rad(30.0) and aero.aileron_left == -deg_to_rad(-10.0)
		and aero.elevator == -deg_to_rad(20.0) and aero.rudder == -deg_to_rad(40.0), str(aero))
	var inverse := ControlSurfaces.from_hinge_rotations(hinge)
	_check("hinge inverse recovers all surface angles", _near_surfaces(inverse, positive), str(inverse))
	var signed_hinge := {
		"aileron_right": {"x": deg_to_rad(-67.5), "y": 0.0},
		"aileron_left": {"x": deg_to_rad(45.25), "y": 0.0},
		"elevator": {"x": deg_to_rad(-12.75), "y": 0.0},
		"rudder": {"x": 0.0, "y": deg_to_rad(-81.125)},
	}
	var signed_inverse := ControlSurfaces.from_hinge_rotations(signed_hinge)
	_check("hinge inverse supports arbitrary signed poses",
		absf(signed_inverse.aileron_right - 67.5) < 1e-12
		and absf(signed_inverse.aileron_left + 45.25) < 1e-12
		and absf(signed_inverse.elevator - 12.75) < 1e-12
		and absf(signed_inverse.rudder + 81.125) < 1e-12, str(signed_inverse))

	var negative_zero_bytes := PackedByteArray([0, 0, 0, 0, 0, 0, 0, 128])
	var negative_zero: float = negative_zero_bytes.decode_double(0)
	_check("negative-zero test fixture has the sign bit", _bits(negative_zero) != _bits(0.0), _bits(negative_zero))
	var zero_inputs := {"roll": negative_zero, "pitch": negative_zero, "yaw": negative_zero}
	var zero_surfaces := ControlSurfaces.surface_deflections_deg(zero_inputs, throws_deg)
	_check("negative zero survives aileron and axial products",
		_bits(zero_surfaces.aileron_right) == _bits(negative_zero)
		and _bits(zero_surfaces.aileron_left) == _bits(0.0)
		and _bits(zero_surfaces.elevator) == _bits(negative_zero)
		and _bits(zero_surfaces.rudder) == _bits(negative_zero), str(zero_surfaces))
	var zero_hinge := ControlSurfaces.hinge_rotations(zero_inputs, throws_deg)
	_check("negative zero survives hinge sign mapping",
		_bits(zero_hinge.aileron_right.x) == _bits(0.0)
		and _bits(zero_hinge.aileron_left.x) == _bits(negative_zero)
		and _bits(zero_hinge.elevator.x) == _bits(0.0)
		and _bits(zero_hinge.rudder.y) == _bits(negative_zero), str(zero_hinge))
	var zero_aero := ControlSurfaces.deflections_from_surfaces(zero_surfaces)
	_check("negative zero survives aero convention mapping",
		_bits(zero_aero.aileron_right) == _bits(0.0)
		and _bits(zero_aero.aileron_left) == _bits(negative_zero)
		and _bits(zero_aero.elevator) == _bits(0.0)
		and _bits(zero_aero.rudder) == _bits(0.0), str(zero_aero))

	var commands := {"roll": -0.37, "pitch": 0.22, "yaw": -0.63}
	var wrapper_surfaces := Commands.surface_deflections_deg(commands, throws_deg)
	_check("Commands wrapper is bit-identical to shared mapping",
		_same_surfaces(wrapper_surfaces, ControlSurfaces.surface_deflections_deg(commands, throws_deg)))
	_check("legacy _aileron wrapper remains identical",
		_bits(Commands._aileron(-0.37, throws_deg)) == _bits(ControlSurfaces._aileron(-0.37, throws_deg)))
	var wrapper_hinge := Commands.hinge_rotations(commands, throws_deg)
	_check("Commands hinge wrapper is bit-identical to shared mapping",
		JSON.stringify(wrapper_hinge) == JSON.stringify(ControlSurfaces.hinge_rotations(commands, throws_deg)))
	_check("Commands empty-throws default still uses aircraft data",
		_same_surfaces(Commands.surface_deflections_deg(Commands.neutral_commands()),
			ControlSurfaces.surface_deflections_deg(Commands.neutral_commands(), Commands.data_throws_deg())))
	_check("Commands hinge empty-throws default still uses aircraft data",
		JSON.stringify(Commands.hinge_rotations(Commands.neutral_commands()))
		== JSON.stringify(ControlSurfaces.hinge_rotations(Commands.neutral_commands(), Commands.data_throws_deg())))
	var wrapper_aero := Aero.deflections_from_surfaces(wrapper_surfaces)
	_check("Aero wrapper is bit-identical to shared sign mapping",
		JSON.stringify(wrapper_aero) == JSON.stringify(ControlSurfaces.deflections_from_surfaces(wrapper_surfaces)))

	print("Control surfaces: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)

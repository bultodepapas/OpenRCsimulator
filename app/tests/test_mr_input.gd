# DR-14/15 (INPUT-01…06, 08): the FPV quad pilot adapter through its read seams. Radio and gamepad axis signs (roll
# right, pitch stick back, yaw right positive); calibrated endpoints/centre/inversion (FPV/04 §2 example); gamepad
# pre-expo linearity with only the rescaled deadzone; absolute versus rate throttle policy per source; arm toggle level,
# radio arm switch and mode toggle; source generation on reconnect and source switch; no-source readiness; one-shot
# actions; every frame inside the controller's domain. Simulated devices only: no real radio is qualified here.
extends SceneTree

const PilotInput := preload("res://input/multirotor_input.gd")
const ControllerProfile := preload("res://input/controller_profile.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")

const DT := 1.0 / 240.0

var _count := 0
var _failures := 0
var _axes := {}
var _buttons := {}
var _keys := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0, arm = false, mode = false}


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _seamed() -> RefCounted:
	var input: RefCounted = PilotInput.new()
	input.profiles_path = "user://test_mr_input_unused.cfg"
	input.read_axis = func(_device: int, axis: int) -> float: return float(_axes.get(axis, 0.0))
	input.read_button = func(_device: int, button: int) -> bool: return bool(_buttons.get(button, false))
	input.read_keys = func() -> Dictionary: return _keys.duplicate()
	return input


func _valid(sample: Dictionary) -> bool:
	var policy := FC.THROTTLE_RATE if sample.throttle_policy == "rate" else FC.THROTTLE_ABSOLUTE
	return FC.input_is_valid({throttle_policy = policy}, sample.pilot)


func _run() -> void:
	_radio()
	_calibration()
	_gamepad()
	_keyboard()
	_generations()
	_radio_switch()
	_throttle_limits()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _radio() -> void:
	_axes = {0: 0.0, 1: 0.0, 2: -1.0, 3: 0.0}
	var input := _seamed()
	input.connect_device(0, {name = "EdgeTX test radio", kind = "radio"}, ControllerProfile.defaults("radio", "radio_custom"))
	var s: Dictionary = input.sample(DT, true)
	_check("radio is a ready absolute-throttle source", s.source == "radio" and s.ready and s.throttle_policy == "absolute",
		"%s %s %s %s" % [s.source, s.ready, s.throttle_policy, s.error])
	_check("radio defaults to Acro", s.pilot[FC.IN_MODE] == float(FC.FLIGHT_ACRO))
	_check("radio throttle low end = 0", s.pilot[FC.IN_THROTTLE] == 0.0)
	_axes = {0: 0.6, 1: -0.4, 2: 1.0, 3: 0.3}
	s = input.sample(DT, true)
	_check("radio roll right positive", is_equal_approx(s.pilot[FC.IN_ROLL], 0.6), str(s.pilot))
	_check("radio pitch: stick back (inverted HID axis) is positive", is_equal_approx(s.pilot[FC.IN_PITCH], 0.4), str(s.pilot[FC.IN_PITCH]))
	_check("radio yaw right positive", is_equal_approx(s.pilot[FC.IN_YAW], 0.3))
	_check("radio throttle full = 1", is_equal_approx(s.pilot[FC.IN_THROTTLE], 1.0))
	_axes[2] = 0.0
	s = input.sample(DT, true)
	_check("radio throttle centre = 0.5", is_equal_approx(s.pilot[FC.IN_THROTTLE], 0.5))
	_check("radio raw display carries the pre-expo values", is_equal_approx(float(s.raw.roll), 0.6) and s.raw.arm_source == "toggle")
	_check("radio frames lie in the absolute-policy domain", _valid(s))


func _calibration() -> void:
	var profile := ControllerProfile.defaults("radio", "radio_custom")
	profile.roll.min = -0.9
	profile.roll.center = 0.1
	profile.roll.max = 0.8
	profile.yaw.min = -0.9
	profile.yaw.center = 0.1
	profile.yaw.max = 0.8
	profile.yaw.invert = true
	_axes = {0: 0.1, 1: 0.0, 2: -1.0, 3: 0.45}
	var input := _seamed()
	input.connect_device(0, {name = "EdgeTX test radio", kind = "radio"}, profile)
	var s: Dictionary = input.sample(DT, true)
	_check("calibrated centre maps to 0", absf(s.pilot[FC.IN_ROLL]) < 1.0e-9, str(s.pilot[FC.IN_ROLL]))
	_check("calibrated raw 0.45 maps to +0.5, inverted to -0.5", is_equal_approx(s.pilot[FC.IN_YAW], -0.5), str(s.pilot[FC.IN_YAW]))
	_axes[0] = -0.4
	_axes[0 + 3] = -0.9
	s = input.sample(DT, true)
	_check("calibrated raw -0.4 maps to -0.5", is_equal_approx(s.pilot[FC.IN_ROLL], -0.5), str(s.pilot[FC.IN_ROLL]))
	_check("calibrated endpoint maps to the inverted end", is_equal_approx(s.pilot[FC.IN_YAW], 1.0))
	_axes[0] = 1.0
	s = input.sample(DT, true)
	_check("travel beyond the endpoint clamps to 1", s.pilot[FC.IN_ROLL] == 1.0)


func _gamepad() -> void:
	_axes = {}
	_buttons = {}
	var input := _seamed()
	input.radio.confirmed_gamepad_connection = func(_device: int) -> bool: return true
	input.connect_device(1, {name = "Test gamepad", known = true})
	var s: Dictionary = input.sample(DT, true)
	_check("gamepad is a ready centred-throttle (rate) source", s.source == "gamepad" and s.ready and s.throttle_policy == "rate",
		"%s %s %s %s" % [s.source, s.ready, s.throttle_policy, s.error])
	_check("gamepad defaults to Angle", s.pilot[FC.IN_MODE] == float(FC.FLIGHT_ANGLE))
	var channel: Dictionary = input.radio.profile.roll
	var dz := float(channel.deadzone)
	var raw := dz + 0.5 * (1.0 - dz)
	_axes = {2: raw, 3: 0.6, 0: -0.7, 1: -1.0}
	s = input.sample(DT, true)
	var cubic := ControllerProfile.channel_value(raw, "roll", input.radio.profile)
	_check("gamepad 0.5 beyond the deadzone is linear 0.5 (no cubic expo)", absf(s.pilot[FC.IN_ROLL] - 0.5) < 1.0e-6 and absf(cubic - 0.5) > 0.05,
		"pre-expo %.6f, shaped %.6f" % [s.pilot[FC.IN_ROLL], cubic])
	_check("gamepad pitch: right stick down (back) is positive", is_equal_approx(s.pilot[FC.IN_PITCH], (0.6 - dz) / (1.0 - dz)))
	_check("gamepad yaw left negative", is_equal_approx(s.pilot[FC.IN_YAW], -(0.7 - dz) / (1.0 - dz)))
	_check("gamepad throttle stick up = +1 rate (not integrated here)", s.pilot[FC.IN_THROTTLE] == 1.0)
	_check("gamepad frames lie in the rate-policy domain", _valid(s))
	_axes = {2: 0.05, 3: -0.05, 0: 0.0, 1: 1.0}
	s = input.sample(DT, true)
	_check("gamepad deadzone holds zero", s.pilot[FC.IN_ROLL] == 0.0 and s.pilot[FC.IN_PITCH] == 0.0)
	_check("gamepad throttle stick down = -1 rate", s.pilot[FC.IN_THROTTLE] == -1.0 and _valid(s))
	_axes = {}
	_buttons = {PilotInput.ARM_BUTTON: true}
	s = input.sample(DT, true)
	_check("gamepad arm button press latches ON", s.pilot[FC.IN_ARM] == 1.0)
	s = input.sample(DT, true)
	_check("holding the button keeps the level (no re-toggle)", s.pilot[FC.IN_ARM] == 1.0)
	_buttons = {}
	input.sample(DT, true)
	_buttons = {PilotInput.ARM_BUTTON: true, PilotInput.MODE_BUTTON: true}
	s = input.sample(DT, true)
	_check("second press latches OFF; mode button toggles to Acro", s.pilot[FC.IN_ARM] == 0.0 and s.pilot[FC.IN_MODE] == float(FC.FLIGHT_ACRO))


func _keyboard() -> void:
	_keys = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0, arm = false, mode = false}
	var input := _seamed()
	var s: Dictionary = input.sample(DT, true)
	_check("no device: keyboard, ready, rate policy, Angle", s.source == "keyboard" and s.ready and s.throttle_policy == "rate"
		and s.pilot[FC.IN_MODE] == float(FC.FLIGHT_ANGLE) and s.pilot[FC.IN_SOURCE_READY] == 1.0)
	_keys = {roll = 1.0, pitch = 1.0, yaw = -1.0, throttle = 1.0, arm = true, mode = false}
	for i in 240:
		s = input.sample(DT, true)
	_check("keyboard right arrow rolls right, Down pitches back (positive), A yaws left",
		s.pilot[FC.IN_ROLL] == 1.0 and s.pilot[FC.IN_PITCH] == 1.0 and s.pilot[FC.IN_YAW] == -1.0, str(s.pilot))
	_check("keyboard W is the centred +1 rate, not an integrated position", s.pilot[FC.IN_THROTTLE] == 1.0)
	_check("arm key latches ON once while held", s.pilot[FC.IN_ARM] == 1.0)
	_keys.throttle = -1.0
	s = input.sample(DT, true)
	_check("keyboard S is -1 rate and inside the rate domain", s.pilot[FC.IN_THROTTLE] == -1.0 and _valid(s))
	_keys.arm = false
	input.sample(DT, true)
	_keys.arm = true
	s = input.sample(DT, false)
	_check("a hold (no integration) cannot toggle the arm level", s.pilot[FC.IN_ARM] == 1.0)
	_keys.arm = false
	input.sample(DT, true)
	_keys.arm = true
	s = input.sample(DT, true)
	_check("a fresh press while flying latches OFF", s.pilot[FC.IN_ARM] == 0.0)
	_keys.mode = true
	s = input.sample(DT, true)
	_check("mode key toggles Angle to Acro", s.pilot[FC.IN_MODE] == float(FC.FLIGHT_ACRO) and s.raw.mode == "acro")
	input.request_throttle_reset()
	s = input.sample(DT, false)
	_check("one-shot actions wait for an integrating sample", s.pilot[FC.IN_ACTIONS] == 0.0)
	s = input.sample(DT, true)
	_check("throttle reset is set on the next integrating sample", s.pilot[FC.IN_ACTIONS] == float(FC.ACTION_THROTTLE_RESET))
	s = input.sample(DT, true)
	_check("and only on that one", s.pilot[FC.IN_ACTIONS] == 0.0)
	input.attest_recovery()
	input.request_throttle_reset()
	s = input.sample(DT, true)
	_check("recovery attestation combines with a throttle reset", s.pilot[FC.IN_ACTIONS] == float(FC.ACTION_THROTTLE_RESET | FC.ACTION_RECOVERY) and _valid(s))
	input.reset_for_restart()
	_keys = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0, arm = false, mode = false}
	s = input.sample(DT, true)
	_check("a pad restart returns the virtual arm switch to OFF and keeps the mode", s.pilot[FC.IN_ARM] == 0.0
		and s.pilot[FC.IN_MODE] == float(FC.FLIGHT_ACRO))


func _generations() -> void:
	_keys = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0, arm = false, mode = false}
	_axes = {0: 0.0, 1: 0.0, 2: -1.0, 3: 0.0}
	_buttons = {}
	var input := _seamed()
	var s: Dictionary = input.sample(DT, true)
	_check("generation starts at 0", s.source_generation == 0 and s.pilot[FC.IN_SOURCE_GENERATION] == 0.0)
	input.connect_device(0, {name = "EdgeTX test radio", kind = "radio"}, ControllerProfile.defaults("radio", "radio_custom"))
	s = input.sample(DT, true)
	_check("a connection is a new generation", s.source_generation == 1 and s.pilot[FC.IN_SOURCE_GENERATION] == 1.0)
	_check("the radio's policy differs from the keyboard's (a mid-flight switch needs a pad restart)", s.throttle_policy == "absolute")
	input.on_connection_changed(0, false)
	s = input.sample(DT, true)
	_check("a disconnection is a new generation back on the keyboard", s.source_generation == 2 and s.source == "keyboard")
	input.connect_device(0, {name = "EdgeTX test radio", kind = "radio"}, ControllerProfile.defaults("radio", "radio_custom"))
	var before: int = input.source_generation
	_check("a switch to another profile on the same device is a new generation",
		input.use_profile(ControllerProfile.defaults("joystick", "radio_custom"), "test") and input.source_generation == before + 1)
	var lost := _seamed()
	lost.connect_device(3, {name = "Mystery stick", known = false})
	s = lost.sample(DT, true)
	_check("an unconfigured device is not a ready source", not s.ready and s.pilot[FC.IN_SOURCE_READY] == 0.0 and not str(s.error).is_empty(),
		str(s.error))
	_check("a not-ready frame is neutral and still inside the domain", s.pilot[FC.IN_THROTTLE] == 0.0 and s.pilot[FC.IN_ROLL] == 0.0 and _valid(s))


## Throttle limit: full range for a radio, 45% for gamepad and keyboard; the menu cycles 35/45/60/100% per source;
## the value reaches the session as an option and changes its identity (test_mr_activity covers the activity path).
func _throttle_limits() -> void:
	_axes = {0: 0.0, 1: 0.0, 2: -1.0, 3: 0.0}
	_buttons = {}
	_keys = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0, arm = false, mode = false}
	var input := _seamed()
	_check("keyboard default limit 45%", is_equal_approx(input.throttle_limit(), 0.45))
	_check("keyboard bindings: E arms, W adds throttle", input.bindings().arm == "E" and input.bindings().throttle_up == "W"
		and not input.bindings().arm_switch, str(input.bindings()))
	var cycle := []
	for i in 4:
		cycle.append(input.cycle_throttle_limit())
	_check("the menu cycles 60, 100, 35, 45%", cycle == [0.6, 1.0, 0.35, 0.45], str(cycle))
	input.cycle_throttle_limit()
	input.connect_device(0, {name = "EdgeTX test radio", kind = "radio"}, ControllerProfile.defaults("radio", "radio_custom"))
	_check("radio default limit 100% (absolute throttle)", input.source() == "radio" and is_equal_approx(input.throttle_limit(), 1.0))
	input.cycle_throttle_limit()
	_check("a radio pilot may choose a limit too", is_equal_approx(input.throttle_limit(), 0.35))
	input.on_connection_changed(0, false)
	_check("each source keeps its own choice (keyboard back at 60%)", input.source() == "keyboard"
		and is_equal_approx(input.throttle_limit(), 0.6))
	var pad := _seamed()
	pad.radio.confirmed_gamepad_connection = func(_device: int) -> bool: return true
	pad.connect_device(1, {name = "Test gamepad", known = true})
	_check("gamepad default limit 45%, LB arms", pad.source() == "gamepad" and is_equal_approx(pad.throttle_limit(), 0.45)
		and pad.bindings().arm == "LB")
	_check("an unlisted value cycles to the next choice above it", is_equal_approx(PilotInput.next_throttle_limit(0.5), 0.6)
		and is_equal_approx(PilotInput.next_throttle_limit(1.0), 0.35))
	var Session: GDScript = load("res://sim/multirotor/session.gd")
	var a: Node = Session.new()
	var b: Node = Session.new()
	var ok_a: bool = a.prepare({}, {throttle_policy = "rate", throttle_limit = PilotInput.default_throttle_limit("keyboard")})
	var ok_b: bool = b.prepare({}, {throttle_policy = "rate", throttle_limit = 1.0})
	_check("the limit is a session option that changes the session identity", ok_a and ok_b
		and is_equal_approx(float(a.options.throttle_limit), 0.45) and str(a.identity().controller) != str(b.identity().controller),
		"%s %s %s" % [ok_a, ok_b, a.load_error])
	a.free()
	b.free()


func _radio_switch() -> void:
	var profile := ControllerProfile.defaults("radio", "radio_custom")
	profile.aux = {gear = {type = "axis", axis = 4, invert = false, off = -1.0, on = 1.0}}
	_axes = {0: 0.0, 1: 0.0, 2: -1.0, 3: 0.0, 4: 1.0}
	_keys = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0, arm = true, mode = false}
	var input := _seamed()
	input.connect_device(0, {name = "EdgeTX test radio", kind = "radio"}, profile)
	_check("a radio with a Landing gear switch arms from that switch", input.arm_from_switch())
	var s: Dictionary = input.sample(DT, true)
	_check("a switch held ON at connection is not an arm level (no OFF evidence)", s.pilot[FC.IN_ARM] == 0.0 and s.raw.arm_source == "switch:gear")
	var off := InputEventJoypadMotion.new()
	off.device = 0
	off.axis = JOY_AXIS_TRIGGER_LEFT
	off.axis_value = -1.0
	input.on_event(off)
	_axes[4] = -1.0
	s = input.sample(DT, true)
	_check("switch OFF reads 0", s.pilot[FC.IN_ARM] == 0.0)
	var on := InputEventJoypadMotion.new()
	on.device = 0
	on.axis = JOY_AXIS_TRIGGER_LEFT
	on.axis_value = 1.0
	input.on_event(on)
	_axes[4] = 1.0
	s = input.sample(DT, true)
	_check("switch ON after OFF reads 1; the keyboard toggle cannot override it", s.pilot[FC.IN_ARM] == 1.0, str(s.raw))
	_check("switch frames lie in the absolute-policy domain", _valid(s))

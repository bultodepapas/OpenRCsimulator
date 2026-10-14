extends SceneTree

const RcInput := preload("res://input/rc_input.gd")
const Profile := preload("res://input/controller_profile.gd")

const DT := 1.0 / 240.0
const PAD_ID := 17

var checks := 0
var failures := 0


func check(label: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func _neutral_events(reader: RcInput, id: int, throttle_value: float = 0.0) -> void:
	for axis in [2, 3, 0, 1]:
		reader.on_motion(id, axis, throttle_value if axis == 1 else 0.0)


func _ticks(reader: RcInput, count: int, values: Dictionary = {}, integrate: bool = true, button_reader: Callable = Callable()) -> void:
	for _tick in count:
		reader.poll(func(_device: int, axis: int) -> float: return float(values.get(axis, 0.0)), DT, button_reader, integrate)


func _initialize() -> void:
	var input := RcInput.new()
	input.connect_device(PAD_ID, {"id": PAD_ID, "name": "Synthetic Xbox pad", "known": true})
	check("new gamepad starts unarmed and neutral", input.is_gamepad() and not input.armed and input.sticks() == {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": 0.0})
	check("Mode 2 is the default mapping", [input.profile.roll.axis, input.profile.pitch.axis, input.profile.yaw.axis, input.profile.throttle.axis] == [2, 3, 0, 1])
	_neutral_events(input, PAD_ID)
	_ticks(input, 47, {}, true, func(_device: int, _button: int) -> bool: return false)
	check("fresh neutral dwell is required before arming", not input.armed)
	_ticks(input, 1, {}, true, func(_device: int, _button: int) -> bool: return false)
	check("four mapped axes and 200 ms neutral arm", input.armed, str(input._neutral_elapsed))
	check("unbound axes do not need event freshness", input.has_axis_sample(2) and input.has_axis_sample(3) and input.has_axis_sample(0) and input.has_axis_sample(1) and not input.has_axis_sample(4))

	# Scalar shaping stays independent by axis and does not clip individual endpoints.
	input.on_motion(PAD_ID, 2, 0.5)
	input.poll(func(_device: int, axis: int) -> float: return 0.5 if axis == 2 else 0.0, DT)
	var shaped: float = Profile.conditioned_axis(0.5, input.profile.roll, "gamepad")
	check("gamepad roll receives one scalar deadzone/expo stage", absf(input.sticks().roll - shaped) < 1e-12)
	input.on_motion(PAD_ID, 3, -1.0)
	input.on_motion(PAD_ID, 2, 1.0)
	input.poll(func(_device: int, axis: int) -> float: return 1.0 if axis == 2 else (-1.0 if axis == 3 else 0.0), DT)
	check("diagonal full individual endpoints remain full", input.sticks().roll == 1.0 and input.sticks().pitch == -1.0)

	# A rate integrator moves only on accepted ticks and holds through an ordinary pause.
	input.on_motion(PAD_ID, 2, 0.0)
	input.on_motion(PAD_ID, 3, 0.0)
	input.on_motion(PAD_ID, 0, 0.0)
	input.on_motion(PAD_ID, 1, -1.0)
	_ticks(input, 240, {1: -1.0})
	check("rate throttle integrates at configured 0.5 per second", absf(input.throttle_position() - 0.5) < 1e-9, str(input.throttle_position()))
	input.require_neutral(true)
	check("pause disarms but preserves virtual throttle", not input.armed and absf(input.throttle_position() - 0.5) < 1e-9)
	_ticks(input, 240, {1: -1.0}, false)
	check("held/menu polling never advances throttle", absf(input.throttle_position() - 0.5) < 1e-9)
	_neutral_events(input, PAD_ID)
	_ticks(input, 48)
	check("pause neutral gate reuses connection freshness", input.armed and absf(input.throttle_position() - 0.5) < 1e-9)

	# The button reader observes buttons held before the first input event.
	input.use_profile(Profile.defaults("gamepad", "mode2"), "test-profile")
	_neutral_events(input, PAD_ID)
	var held: Array[bool] = [true]
	var read_button := func(_device: int, button: int) -> bool: return held[0] and button == 4
	_ticks(input, 80, {}, true, read_button)
	check("held button is discovered by polling and blocks arming", not input.armed and input._neutral_release_pending and input._pressed_buttons.has(4))
	held[0] = false
	_ticks(input, 48, {}, true, read_button)
	check("all held buttons must release before arming", input.armed and not input._neutral_release_pending)

	# Profile replacement clears mapped freshness and rate throttle.
	input.on_motion(PAD_ID, 1, -1.0)
	_ticks(input, 240, {1: -1.0})
	check("profile-change setup has a live throttle fixture", absf(input.throttle_position() - 0.5) < 1e-9)
	var replacement: Dictionary = input.profile.duplicate(true)
	replacement.roll.invert = true
	check("valid profile replacement is accepted", input.use_profile(replacement, "test-profile"))
	check("profile replacement is disarmed with cleared freshness and idle rate", not input.armed and not input.has_axis_sample(2) and input.throttle_position() == 0.0)
	_ticks(input, 80)
	check("polling alone cannot satisfy post-profile axis evidence", not input.armed)
	_neutral_events(input, PAD_ID)
	_ticks(input, 48)
	check("fresh mapped neutral after profile change arms", input.armed)

	# Trigger throttle is still a gamepad and uses direct 0...1 semantics.
	var trigger_profile := Profile.defaults("gamepad", "trigger_absolute")
	check("absolute-trigger profile applies", input.use_profile(trigger_profile, "trigger-preset") and input.is_gamepad() and not input.is_rate_throttle())
	for axis in [2, 3, 0, 5]:
		input.on_motion(PAD_ID, axis, 0.0)
	_ticks(input, 48)
	check("released absolute trigger can arm at rest", input.armed and input.throttle_position() == 0.0)
	input.on_motion(PAD_ID, 5, 0.7)
	input.on_motion(PAD_ID, 2, 0.5)
	input.poll(func(_device: int, axis: int) -> float: return 0.7 if axis == 5 else (0.5 if axis == 2 else 0.0), DT)
	check("absolute trigger stays direct and is not rate integrated", absf(input.throttle_position() - 0.7) < 1e-12)
	check("trigger profile still uses gamepad-shaped flight axes", absf(input.sticks().roll - Profile.conditioned_axis(0.5, trigger_profile.roll, "gamepad")) < 1e-12)

	# Any non-finite sample is a safe invalidation, then requires new evidence.
	input.on_motion(PAD_ID, 2, NAN)
	check("NaN axis event immediately disarms and zeros commands", not input.armed and input.sticks().roll == 0.0 and input.sticks().throttle == 0.0)
	input.poll(func(_device: int, axis: int) -> float: return INF if axis == 5 else 0.0, DT)
	check("infinite polled sample stays safe", not input.armed and not input.input_error.is_empty())
	for axis in [2, 3, 0, 5]:
		input.on_motion(PAD_ID, axis, 0.0)
	_ticks(input, 48)
	check("fresh post-error evidence is required again", input.armed)
	input.require_neutral(false)
	check("ownership boundary resets virtual throttle to idle and clears freshness", input.throttle_position() == 0.0 and not input.armed and not input.has_axis_sample(2))

	# Smoke AUX remains isolated and uses its existing event-evidence rule.
	var aux_profile: Dictionary = Profile.defaults("radio", "radio_custom")
	aux_profile.aux = {"smoke": {"type": "button", "button": 7, "mode": "level"}}
	check("radio AUX profile is valid", Profile.validate(aux_profile).ok)
	var radio := RcInput.new()
	radio.connect_device(2, {"name": "EdgeTX transmitter"}, aux_profile)
	radio.on_button(2, 7, false)
	radio.poll(func(_device: int, _axis: int) -> float: return 0.0, DT)
	radio.on_button(2, 7, true)
	check("smoke AUX preserves button isolation", radio.smoke_is_armed() and radio.smoke_amount() == 1.0 and not radio.armed)
	var runtime_aux: Dictionary = Profile.defaults("radio", "radio_custom")
	runtime_aux.aux = {&"smoke": {&"type": "button", &"button": 8, &"mode": "level"}}
	check("radio profile handoff accepts StringName AUX dictionary keys", radio.use_profile(runtime_aux, "runtime-aux"))
	radio.on_button(2, 8, false)
	radio.on_button(2, 8, true)
	check("normalized radio AUX still routes only to smoke", radio.smoke_is_armed() and radio.smoke_amount() == 1.0 and not radio.armed)

	print("Controller conditioning: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

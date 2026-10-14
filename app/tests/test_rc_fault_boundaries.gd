extends SceneTree

const RcInput := preload("res://input/rc_input.gd")
const Profile := preload("res://input/controller_profile.gd")
const Calibration := preload("res://input/rc_calibration.gd")
const DEVICE_ID := 41
const INFO := {"name": "EdgeTX fault-boundary radio"}
const DT := 1.0 / 240.0

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_test_rejected_profile_is_transactional()
	_test_active_profile_mutation_rearms()
	_test_fault_outputs_are_neutral()
	_test_focus_rearm_requires_fresh_low()
	_test_paused_gamepad_rearm_is_revoked_by_movement()
	_test_calibration_rejects_bad_samples()
	_test_button_bounds()
	print("RC fault boundaries: %d/%d checks passed" % [_checks - _failures, _checks])
	quit(1 if _failures else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)


func _poll(radio: RcInput, values: Dictionary = {}, integrate := true) -> void:
	radio.poll(func(_device: int, axis: int) -> float: return float(values.get(axis, 0.0)), DT,
		func(_device: int, _button: int) -> bool: return false, integrate)


func _neutral_gamepad(radio: RcInput, integrate := true, ticks := 48) -> void:
	for axis in [2, 3, 0, 1]:
		radio.on_motion(0, axis, 0.0)
	for _tick in ticks:
		_poll(radio, {}, integrate)


func _test_rejected_profile_is_transactional() -> void:
	var active: Dictionary = Profile.defaults("radio", "radio_custom")
	active["aux"] = {"smoke": {"type": "button", "button": 7, "mode": "toggle_edge"}}
	var radio := RcInput.new()
	radio.connect_device(DEVICE_ID, INFO, active)
	radio.on_button(DEVICE_ID, 7, false)
	radio.on_motion(DEVICE_ID, 2, -1.0)
	_poll(radio, {2: -1.0})
	radio.on_button(DEVICE_ID, 7, true)
	var previous_sticks := radio.sticks().duplicate(true)
	var previous_profile := radio.profile.duplicate(true)
	var invalid := radio.profile.duplicate(true)
	invalid.roll.axis = RcInput.AXES
	var applied := radio.use_profile(invalid, "invalid draft")
	_check("invalid candidate is rejected", not applied)
	_check("candidate rejection does not become an active-profile error", radio.profile_error.is_empty(), radio.profile_error)
	_check("candidate rejection has its own diagnostic", not str(radio.get("profile_rejection_error")).is_empty())
	_check("rejection preserves the running profile, arming, and sticks", radio.armed and radio.profile == previous_profile and radio.sticks() == previous_sticks)
	_check("rejection preserves the existing AUX request", radio.smoke_is_armed() and radio.auxiliary_amount("smoke") == 1.0)


func _test_active_profile_mutation_rearms() -> void:
	var radio := RcInput.new()
	radio.connect_device(DEVICE_ID, INFO)
	radio.on_motion(DEVICE_ID, 2, -1.0)
	_poll(radio, {2: -1.0})
	_check("profile mutation setup is armed", radio.armed)
	radio.profile.roll.axis = 5
	_poll(radio, {2: 1.0, 5: 0.75})
	_check("valid direct mapping change clears prior throttle evidence", not radio.armed and radio.sticks().throttle == 0.0)
	_check("poll values alone cannot re-arm the changed mapping", not radio.armed)
	radio.profile.throttle.axis = RcInput.AXES
	_poll(radio, {2: -1.0})
	_check("invalid active profile faults the flight controls", not radio.profile_error.is_empty() and radio.sticks().throttle == 0.0)


func _test_fault_outputs_are_neutral() -> void:
	var saved: Dictionary = RcInput.DEFAULT_PROFILE.duplicate(true)
	saved.roll.center = 0.2
	var radio := RcInput.new()
	radio.connect_device(DEVICE_ID, INFO, saved)
	radio.on_motion(DEVICE_ID, 2, -1.0)
	_poll(radio, {2: -1.0})
	_check("off-centre radio profile setup is armed", radio.armed)
	radio.on_motion(DEVICE_ID, 9, NAN)
	_check("non-finite event neutralizes all flight outputs", not radio.armed and radio.sticks().roll == 0.0 and radio.sticks().throttle == 0.0 and radio.throttle_position() == 0.0)


func _test_focus_rearm_requires_fresh_low() -> void:
	var radio := RcInput.new()
	radio.connect_device(DEVICE_ID, INFO)
	radio.on_motion(DEVICE_ID, 2, -1.0)
	_poll(radio, {2: -1.0})
	radio.set_auxiliary_enabled(false)
	radio.require_neutral(true, true)
	_check("focus boundary disarms a radio and clears its axis history", not radio.armed and not radio.has_axis_sample(2))
	radio.on_motion(DEVICE_ID, 2, -1.0)
	_poll(radio, {2: -1.0}, false)
	_check("fresh low event can prepare resume while paused", radio.armed)
	radio.on_motion(DEVICE_ID, 2, 1.0)
	_poll(radio, {2: 1.0}, false)
	_check("raising throttle while paused revokes resume readiness", not radio.armed)
	radio.on_motion(DEVICE_ID, 2, -1.0)
	_poll(radio, {2: -1.0}, false)
	_check("a new low event restores paused resume readiness", radio.armed)


func _test_paused_gamepad_rearm_is_revoked_by_movement() -> void:
	var radio := RcInput.new()
	radio.connect_device(0, {"name": "Synthetic gamepad", "known": true})
	_neutral_gamepad(radio)
	_check("gamepad neutral setup arms", radio.armed)
	_check("test start throttle is accepted", radio.set_rate_throttle_for_start(0.4))
	radio.require_neutral(true)
	_neutral_gamepad(radio, false)
	_check("neutral evidence can prepare resume while paused", radio.armed and absf(radio.throttle_position() - 0.4) < 1e-12)
	radio.on_button(0, 0, true)
	_check("menu confirm button does not consume paused readiness", radio.armed)
	radio.on_motion(0, 2, 0.5)
	_poll(radio, {2: 0.5}, false)
	_check("movement while paused revokes readiness and preserves rate throttle", not radio.armed and absf(radio.throttle_position() - 0.4) < 1e-12)


func _test_calibration_rejects_bad_samples() -> void:
	var calibration := Calibration.new()
	var short := PackedFloat64Array([0.0])
	_check("short rest sample stays on the rest step with an error", not calibration.advance(short) and calibration.step == 0 and not calibration.error.is_empty())
	var rest := PackedFloat64Array()
	rest.resize(RcInput.AXES)
	calibration.advance(rest)
	var bad := rest.duplicate()
	bad[4] = NAN
	calibration.sample(bad)
	_check("non-finite sweep sample is rejected and clears partial sweep", not calibration.error.is_empty())
	var outside := rest.duplicate()
	outside[4] = 1.1
	_check("out-of-range sweep sample is rejected", not calibration.advance(outside) and not calibration.error.is_empty())
	_check("bad calibration sample cannot create a valid profile", not Calibration.valid(calibration.profile))


func _test_button_bounds() -> void:
	var radio := RcInput.new()
	radio.connect_device(0, {"name": "Synthetic gamepad", "known": true})
	radio.on_button(0, JOY_BUTTON_MAX, true)
	_check("out-of-range button events cannot add held state", radio._pressed_buttons.is_empty())
	radio.observe_pressed_buttons([-1, JOY_BUTTON_MAX, 0.5, "0", JOY_BUTTON_MAX - 1])
	_check("observed held buttons retain only valid bounded indices", radio._pressed_buttons == {JOY_BUTTON_MAX - 1: true})

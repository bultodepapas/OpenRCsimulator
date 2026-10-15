extends SceneTree

const Profile := preload("res://input/controller_profile.gd")
const RcInput := preload("res://input/rc_input.gd")
const Calibration := preload("res://input/rc_calibration.gd")
const DT := 1.0 / 240.0
const DEVICE_ID := 42
const INFO := {
	"guid": "03000000091200004f54000000000000",
	"name": "EdgeTX RadioMaster TX16S",
	"vendor_id": 0x1209,
	"product_id": 0x4f54,
}

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var profile := _profile({
		"flaps": _axis_binding(9),
		"gear": _button_binding(127, "level"),
		"smoke": _button_binding(126, "toggle_edge"),
	})
	var validation: Dictionary = Profile.validate(profile)
	_check("profile accepts independent flap, gear, and smoke AUX", bool(validation.get("ok", false)), str(validation.get("errors", [])))
	_check("axis 9 and button 127 are valid AUX sources", Profile.validate(profile).ok)

	var radio := RcInput.new()
	radio.connect_device(DEVICE_ID, INFO, profile)
	_check("connected radio applies the saved three-channel AUX profile", radio.profile_source == "calibrated" and radio.profile.aux.size() == 3)

	# A different device cannot supply release evidence or drive an assigned AUX source.
	radio.on_motion(DEVICE_ID + 1, 9, -1.0)
	radio.on_button(DEVICE_ID + 1, 127, false)
	radio.on_button(DEVICE_ID + 1, 126, false)
	_poll(radio, {9: 1.0}, {127: true, 126: true})
	_check("another device cannot arm or activate AUX channels", _all_aux_zero(radio) and not radio.smoke_is_armed())

	# Each channel requires a matching, selected-device OFF/release event before it can arm.
	radio.on_motion(DEVICE_ID, 9, -1.0)
	radio.on_button(DEVICE_ID, 127, false)
	radio.on_button(DEVICE_ID, 126, false)
	_poll(radio, {9: -1.0}, {})
	_check("axis 9 OFF and button releases arm only their own channels", _all_aux_zero(radio) and radio.smoke_is_armed())
	radio.on_motion(DEVICE_ID, 9, 0.0)
	radio.on_button(DEVICE_ID, 127, true)
	radio.on_button(DEVICE_ID, 126, true)
	_poll(radio, {9: 0.0}, {127: true, 126: true})
	_check("axis 9 maps an analog flap request", absf(radio.auxiliary_amount("flaps") - 0.5) < 1e-12)
	_check("button 127 level binding holds the gear request", radio.auxiliary_amount("gear") == 1.0)
	_check("smoke toggle edge is independent from flap and gear inputs", radio.auxiliary_amount("smoke") == 1.0 and radio.auxiliary_amount("flaps") == 0.5)
	_check("bound AUX refuses a competing semantic action", not radio.auxiliary_action("flaps_cycle") and not radio.auxiliary_action("gear_toggle") and not radio.auxiliary_action("smoke_toggle"))
	radio.on_button(DEVICE_ID, 127, false)
	radio.on_button(DEVICE_ID, 126, false)
	_poll(radio, {9: 0.0}, {})
	_check("maintained gear button returns to zero on release", radio.auxiliary_amount("gear") == 0.0)
	_check("toggle smoke stays on after button release", radio.auxiliary_amount("smoke") == 1.0)
	radio.on_button(DEVICE_ID, 126, true)
	_poll(radio, {9: 0.0}, {126: true})
	_check("second toggle edge turns smoke off", radio.auxiliary_amount("smoke") == 0.0)

	# A pause/focus/menu boundary drops every current request and ignores events until re-armed.
	radio.on_button(DEVICE_ID, 126, false)
	radio.on_motion(DEVICE_ID, 9, 1.0)
	radio.on_button(DEVICE_ID, 127, true)
	radio.on_button(DEVICE_ID, 126, true)
	_poll(radio, {9: 1.0}, {127: true, 126: true})
	_check("AUX channels are active before the pause boundary", radio.auxiliary_amount("flaps") == 1.0 and radio.auxiliary_amount("gear") == 1.0 and radio.auxiliary_amount("smoke") == 1.0)
	radio.set_auxiliary_enabled(false)
	_check("disabling AUX clears requests immediately", _all_aux_zero(radio))
	_check("disabled AUX rejects semantic actions", not radio.auxiliary_action("gear_toggle"))
	radio.on_motion(DEVICE_ID, 9, -1.0)
	radio.on_button(DEVICE_ID, 127, false)
	radio.on_button(DEVICE_ID, 126, false)
	_poll(radio, {9: -1.0}, {}, false)
	_check("disabled events do not queue an AUX request", _all_aux_zero(radio))
	radio.set_auxiliary_enabled(true)
	_poll(radio, {9: 1.0}, {127: true, 126: true})
	_check("resume needs fresh OFF/release evidence", _all_aux_zero(radio))

	# Invalid analog input fails closed and leaves no non-finite auxiliary request.
	radio.on_motion(DEVICE_ID, 9, NAN)
	_check("non-finite axis input clears AUX and reports an input error", _all_aux_zero(radio) and not radio.input_error.is_empty())
	_check("all reported AUX requests remain finite", _all_aux_finite(radio))

	# A profile change clears old requests and old bindings; new ones need fresh evidence.
	radio.on_motion(DEVICE_ID, 9, -1.0)
	radio.on_motion(DEVICE_ID, 9, 1.0)
	radio.on_button(DEVICE_ID, 127, false)
	radio.on_button(DEVICE_ID, 127, true)
	radio.on_button(DEVICE_ID, 126, false)
	radio.on_button(DEVICE_ID, 126, true)
	_poll(radio, {9: 1.0}, {127: true, 126: true})
	_check("AUX events cannot bypass an unresolved input fault", _all_aux_zero(radio))
	var replacement := _profile({
		"flaps": _axis_binding(8),
		"gear": _button_binding(125, "level"),
		"smoke": _button_binding(124, "toggle_edge"),
	})
	_check("replacement profile is valid", Profile.validate(replacement).ok)
	_check("profile change applies and clears previous requests", radio.use_profile(replacement, "calibrated") and _all_aux_zero(radio))
	radio.on_motion(DEVICE_ID, 9, -1.0)
	radio.on_button(DEVICE_ID, 127, false)
	radio.on_button(DEVICE_ID, 126, false)
	_poll(radio, {9: -1.0}, {})
	_check("old bindings cannot activate the replacement profile", _all_aux_zero(radio))
	radio.on_motion(DEVICE_ID, 8, -1.0)
	radio.on_button(DEVICE_ID, 125, false)
	radio.on_button(DEVICE_ID, 124, false)
	_poll(radio, {8: -1.0}, {})
	radio.on_motion(DEVICE_ID, 8, 1.0)
	radio.on_button(DEVICE_ID, 125, true)
	radio.on_button(DEVICE_ID, 124, true)
	_poll(radio, {8: 1.0}, {125: true, 124: true})
	_check("replacement bindings independently arm and drive AUX", radio.auxiliary_amount("flaps") == 1.0 and radio.auxiliary_amount("gear") == 1.0 and radio.auxiliary_amount("smoke") == 1.0)
	radio.disconnect_device()
	_check("disconnect clears requests and rejects actions", _all_aux_zero(radio) and not radio.auxiliary_action("smoke_toggle"))
	radio.on_motion(DEVICE_ID, 8, -1.0)
	radio.on_button(DEVICE_ID, 125, false)
	_check("disconnected events cannot re-arm AUX", _all_aux_zero(radio))

	# Semantic actions cover a three-position flap cycle and two-position gear/smoke toggles.
	var action_radio := RcInput.new()
	var action_profile := _profile({})
	action_radio.connect_device(DEVICE_ID, INFO, action_profile)
	_check("flap cycle step one is the 40% takeoff detent", action_radio.auxiliary_action("flaps_cycle") and absf(action_radio.auxiliary_amount("flaps") - 0.4) < 1e-12)
	_check("flap cycle step two is full", action_radio.auxiliary_action("flaps_cycle") and action_radio.auxiliary_amount("flaps") == 1.0)
	_check("flap cycle step three returns to zero", action_radio.auxiliary_action("flaps_cycle") and action_radio.auxiliary_amount("flaps") == 0.0)
	_check("flap up and down set deterministic endpoints", action_radio.auxiliary_action("flaps_down") and action_radio.auxiliary_amount("flaps") == 1.0 and action_radio.auxiliary_action("flaps_up") and action_radio.auxiliary_amount("flaps") == 0.0)
	_check("gear semantic action toggles a two-position request", action_radio.auxiliary_action("gear_toggle") and action_radio.auxiliary_amount("gear") == 1.0 and action_radio.auxiliary_action("gear_toggle") and action_radio.auxiliary_amount("gear") == 0.0)
	_check("smoke semantic action toggles a request", action_radio.auxiliary_action("smoke_toggle") and action_radio.auxiliary_amount("smoke") == 1.0 and action_radio.auxiliary_action("smoke_toggle") and action_radio.auxiliary_amount("smoke") == 0.0)
	_check("unknown semantic action is rejected", not action_radio.auxiliary_action("unknown"))

	# Button 127 also supports the toggle-edge mode, with release evidence on this selected device.
	var toggle_radio := RcInput.new()
	toggle_radio.connect_device(DEVICE_ID, INFO, _profile({"gear": _button_binding(127, "toggle_edge")}))
	toggle_radio.on_button(DEVICE_ID, 127, false)
	_poll(toggle_radio, {}, {})
	toggle_radio.on_button(DEVICE_ID, 127, true)
	_poll(toggle_radio, {}, {127: true})
	_check("button 127 toggle-edge mode turns on at the first press", toggle_radio.auxiliary_amount("gear") == 1.0)
	toggle_radio.on_button(DEVICE_ID, 127, false)
	_poll(toggle_radio, {}, {})
	toggle_radio.on_button(DEVICE_ID, 127, true)
	_poll(toggle_radio, {}, {127: true})
	_check("button 127 toggle-edge mode turns off at the next press", toggle_radio.auxiliary_amount("gear") == 0.0)

	# The radio wizard retains non-overlapping auxiliary controls and drops only an AUX axis
	# that becomes a newly calibrated AETR axis.
	var calibration_source := _profile({
		"flaps": _axis_binding(9),
		"gear": _button_binding(127, "level"),
		"smoke": _button_binding(126, "toggle_edge"),
	})
	var preserved := _calibrate(calibration_source, 4)
	var preserved_profile: Dictionary = preserved.profile
	_check("calibration completes and preserves distinct flap, gear, and smoke sources", preserved.done and preserved_profile.get("aux", {}).size() == 3 and Profile.upgrade_legacy(preserved_profile).size() > 0, str(preserved.get("warning", "")))
	var overlapping := _calibrate(calibration_source, 9)
	var overlapping_profile: Dictionary = overlapping.profile
	var overlapping_aux: Dictionary = overlapping_profile.get("aux", {})
	_check("calibration drops a flap AUX that overlaps the new primary axis", overlapping.done and not overlapping_aux.has("flaps") and overlapping_aux.has("gear") and overlapping_aux.has("smoke"), str(overlapping.get("warning", "")))
	_check("overlapping calibrated profile still activates with the remaining AUX", Profile.upgrade_legacy(overlapping_profile).size() > 0)

	print("Controller auxiliary runtime: %d/%d checks passed" % [_checks - _failures, _checks])
	quit(1 if _failures > 0 else 0)


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL ", label, " ", detail)


func _profile(aux: Dictionary) -> Dictionary:
	var result: Dictionary = Profile.defaults("radio", "radio_custom")
	result["aux"] = aux.duplicate(true)
	return result


func _axis_binding(axis: int) -> Dictionary:
	return {"type": "axis", "axis": axis, "invert": false, "off": -1.0, "on": 1.0}


func _button_binding(button: int, mode: String) -> Dictionary:
	return {"type": "button", "button": button, "mode": mode}


func _poll(radio: RcInput, values: Dictionary = {}, held: Dictionary = {}, integrate := true) -> void:
	radio.poll(
		func(_device_id: int, axis: int) -> float: return float(values.get(axis, 0.0)),
		DT,
		func(_device_id: int, button: int) -> bool: return bool(held.get(button, false)),
		integrate
	)


func _all_aux_zero(radio: RcInput) -> bool:
	return radio.auxiliary_amount("flaps") == 0.0 and radio.auxiliary_amount("gear") == 0.0 and radio.auxiliary_amount("smoke") == 0.0


func _all_aux_finite(radio: RcInput) -> bool:
	return is_finite(radio.auxiliary_amount("flaps")) and is_finite(radio.auxiliary_amount("gear")) and is_finite(radio.auxiliary_amount("smoke"))


func _calibrate(existing_profile: Dictionary, roll_axis: int) -> Dictionary:
	var wizard := Calibration.new(existing_profile)
	var samples := PackedFloat64Array()
	samples.resize(RcInput.AXES)
	wizard.advance(samples) # centre / throttle-low rest sample
	var selected_axes := [2, roll_axis, 5, 6] # throttle, roll, pitch, yaw
	for axis in selected_axes:
		for value in [1.0, -1.0, 0.0]:
			samples.fill(0.0)
			samples[axis] = value
			wizard.sample(samples)
		wizard.advance(samples)
	return {"profile": wizard.profile.duplicate(true), "warning": wizard.aux_warning, "done": wizard.done()}

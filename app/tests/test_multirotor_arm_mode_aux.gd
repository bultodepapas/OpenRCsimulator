# D6-UX-01: explicit FPV quad Arm and Flight mode AUX channels. Legacy profiles that arm from the Landing gear AUX
# keep arming unchanged; an explicit "arm" binding wins; a "flight_mode" switch sets Angle/Acro and the M key/RB
# toggle stops fighting it; both keep the shared AUX fresh-OFF arming, validation, conflicts, persistence,
# calibration merge and diagnostics; the Extra channels page shows the rows for the quad only. Simulated devices only.
extends SceneTree

const PilotInput := preload("res://input/multirotor_input.gd")
const ControllerProfile := preload("res://input/controller_profile.gd")
const ControllerActions := preload("res://input/controller_actions.gd")
const ControllerStore := preload("res://input/controller_profile_store.gd")
const Diagnostics := preload("res://input/controller_diagnostics.gd")
const RcInput := preload("res://input/rc_input.gd")
const ControllerSetup := preload("res://ui/controller_setup.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")

const DT := 1.0 / 240.0
const STORE_PATH := "user://test_multirotor_arm_mode_aux_profiles.cfg"
const LEGACY_STORE_PATH := "user://test_multirotor_arm_mode_aux_legacy.cfg"

var _count := 0
var _failures := 0
var _axes := {}
var _buttons := {}
var _keys := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0, arm = false, mode = false}


class FakeRegistry extends RefCounted:
	signal devices_changed

	var devices: Array[Dictionary] = [
		{"id": 9, "name": "Radio transmitter", "raw_name": "Radio transmitter", "kind": "radio", "known": false, "connected": true},
	]

	func get_devices() -> Array[Dictionary]:
		return devices.duplicate(true)

	func selected_device_id(_role: String) -> int:
		return 9

	func device_for_id(device_id: int) -> Dictionary:
		for device: Dictionary in devices:
			if int(device.id) == device_id:
				return device.duplicate(true)
		return {}

	func connection_generation(_device_id: int) -> int:
		return 1


class FakeStore extends RefCounted:
	func load_all() -> Dictionary:
		return {"ok": true, "profiles": [], "errors": []}

	func import_legacy_radio() -> Dictionary:
		return {"ok": true, "profiles": [], "errors": []}

	func save_profile(_candidate: Dictionary) -> Dictionary:
		return {"ok": false, "profile": {}, "error": "not used"}

	func match_profile(_info: Dictionary, _connected: Array = []) -> Dictionary:
		return {}


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_capabilities()
	_legacy_gear_radio()
	_legacy_v1_radio()
	_explicit_arm_wins()
	_flight_mode_switch()
	_flight_mode_three_position()
	_gamepad()
	_validation()
	_persistence_and_merge()
	_diagnostics()
	await _setup_rows()
	print("test_multirotor_arm_mode_aux: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _seamed() -> RefCounted:
	var input: RefCounted = PilotInput.new()
	input.profiles_path = "user://test_multirotor_arm_mode_aux_unused.cfg"
	input.read_axis = func(_device: int, axis: int) -> float: return float(_axes.get(axis, 0.0))
	input.read_button = func(_device: int, button: int) -> bool: return bool(_buttons.get(button, false))
	input.read_keys = func() -> Dictionary: return _keys.duplicate()
	return input


func _motion(input: RefCounted, axis: int, value: float, device := 0) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = axis as JoyAxis
	event.axis_value = value
	input.on_event(event)
	_axes[axis] = value


func _press(input: RefCounted, button: int, pressed: bool, device := 0) -> void:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = button as JoyButton
	event.pressed = pressed
	input.on_event(event)
	_buttons[button] = pressed


## Move a maintained switch group to `position` (index into `buttons`) with release-then-press events.
func _switch_to(input: RefCounted, buttons: Array, position: int) -> void:
	for index in buttons.size():
		if index != position and bool(_buttons.get(buttons[index], false)):
			_press(input, int(buttons[index]), false)
	_press(input, int(buttons[position]), true)


func _radio_profile(aux: Dictionary) -> Dictionary:
	var profile := ControllerProfile.defaults("radio", "radio_custom")
	profile.aux = aux.duplicate(true)
	return profile


func _axis(axis: int) -> Dictionary:
	return {"type": "axis", "axis": axis, "invert": false, "off": -1.0, "on": 1.0}


func _reset_devices() -> void:
	_axes = {0: 0.0, 1: 0.0, 2: -1.0, 3: 0.0}
	_buttons = {}
	_keys = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0, arm = false, mode = false}


func _capabilities() -> void:
	var extra_aux := Array(ControllerActions.AUX_CHANNEL_IDS)
	extra_aux.erase("smoke")
	_check("calibration preserves every non-smoke AUX channel", Array(preload("res://input/rc_calibration.gd").EXTRA_AUX_CHANNELS) == extra_aux)
	var standalone := preload("res://input/rc_calibration.gd").new({"kind": "radio", "aux": {
		"arm": {"type": "button", "button": 3, "mode": "level"},
		"flight_mode": {"type": "switch", "buttons": [5, 6], "invert": false}}})
	_check("standalone recalibration keeps Arm and Flight mode bindings",
		standalone._preserved_extra_aux.has("arm") and standalone._preserved_extra_aux.has("flight_mode"))
	var quad := ControllerActions.MULTIROTOR_CAPABILITIES
	var plane := ControllerActions.AIRPLANE_CAPABILITIES
	_check("arm and flight_mode AUX apply to the multirotor only",
		ControllerActions.aux_applies("arm", quad) and ControllerActions.aux_applies("flight_mode", quad)
		and not ControllerActions.aux_applies("arm", plane) and not ControllerActions.aux_applies("flight_mode", ControllerActions.HELICOPTER_CAPABILITIES))
	_check("smoke, flaps and gear AUX follow their equipment",
		ControllerActions.aux_applies("smoke", {"smoke": true}) and ControllerActions.aux_applies("flaps", plane)
		and ControllerActions.aux_applies("gear", plane) and not ControllerActions.aux_applies("gear", quad)
		and not ControllerActions.aux_applies("smoke", quad) and ControllerActions.aux_applies("unknown_future", {}))
	_check("the shared AUX list keeps the airplane channels first", ControllerActions.AUX_CHANNEL_IDS
		== PackedStringArray(["smoke", "flaps", "gear", "arm", "flight_mode"]))


## The hard requirement: a profile saved before D6-UX-01 with the arm switch on the Landing gear AUX still arms.
func _legacy_gear_radio() -> void:
	_reset_devices()
	var profile := _radio_profile({"gear": _axis(4)})
	var before := profile.duplicate(true)
	_check("a legacy gear-bound V2 profile loads unchanged", ControllerProfile.upgrade_legacy(profile) == before
		and ControllerProfile.validate(profile).ok)
	_axes[4] = 1.0
	var input := _seamed()
	input.connect_device(0, {name = "EdgeTX test radio", kind = "radio"}, profile)
	_check("legacy profile arms from the Landing gear switch", input.arm_from_switch() and input.arm_aux() == "gear"
		and not input.mode_from_switch())
	var s: Dictionary = input.sample(DT, true)
	_check("legacy gear switch held ON at connection is not an arm level", s.pilot[FC.IN_ARM] == 0.0
		and s.raw.arm_source == "switch:gear" and s.raw.mode_source == "toggle")
	_check("legacy radio still defaults to Acro", s.pilot[FC.IN_MODE] == float(FC.FLIGHT_ACRO))
	_motion(input, 4, -1.0)
	s = input.sample(DT, true)
	_check("legacy gear switch OFF reads 0", s.pilot[FC.IN_ARM] == 0.0)
	_keys.arm = true
	_motion(input, 4, 1.0)
	s = input.sample(DT, true)
	_check("legacy gear switch ON after OFF arms; the arm key cannot override it", s.pilot[FC.IN_ARM] == 1.0, str(s.raw))
	_keys.arm = false
	_keys.mode = true
	s = input.sample(DT, true)
	_check("legacy profile: the M key still toggles the flight mode", s.pilot[FC.IN_MODE] == float(FC.FLIGHT_ANGLE))
	_keys.mode = false
	var bindings: Dictionary = input.bindings()
	_check("legacy OSD bindings keep their keys and add the new ones", bindings.arm == "E" and bindings.arm_switch
		and bindings.throttle_up == "" and bindings.source == "radio" and bindings.arm_aux == "gear"
		and bindings.mode == "M" and not bindings.mode_switch, str(bindings))


## A pre-V2 RcCalibration radio dictionary with a gear AUX upgrades and keeps arming from it.
func _legacy_v1_radio() -> void:
	_reset_devices()
	var legacy := RcInput.DEFAULT_PROFILE.duplicate(true)
	legacy["aux"] = {"gear": {"type": "button", "button": 12, "mode": "level"}}
	var input := _seamed()
	input.connect_device(0, {name = "EdgeTX test radio", kind = "radio"}, legacy)
	_check("a V1 radio profile with a gear button upgrades and arms from it", input.arm_aux() == "gear"
		and input.radio.profile.get("aux", {}).get("gear", {}) == legacy.aux.gear, str(input.radio.profile.get("aux", {})))
	var s: Dictionary = input.sample(DT, true)
	_press(input, 12, false)
	s = input.sample(DT, true)
	_press(input, 12, true)
	s = input.sample(DT, true)
	_check("V1 gear button arms after its release evidence", s.pilot[FC.IN_ARM] == 1.0 and s.raw.arm_source == "switch:gear", str(s.raw))


func _explicit_arm_wins() -> void:
	_reset_devices()
	var input := _seamed()
	input.connect_device(0, {name = "EdgeTX test radio", kind = "radio"}, _radio_profile({"gear": _axis(4), "arm": _axis(5)}))
	_check("an explicit Arm binding replaces the gear fallback", input.arm_aux() == "arm" and input.bindings().arm_aux == "arm")
	_axes[5] = 1.0
	var s: Dictionary = input.sample(DT, true)
	_check("Arm held ON at connection is not an arm level (fresh-OFF rule)", s.pilot[FC.IN_ARM] == 0.0 and s.raw.arm_source == "switch:arm")
	_motion(input, 5, -1.0)
	_motion(input, 4, -1.0)
	s = input.sample(DT, true)
	_motion(input, 4, 1.0)
	s = input.sample(DT, true)
	_check("the gear switch no longer arms when Arm is bound", s.pilot[FC.IN_ARM] == 0.0)
	_motion(input, 5, 1.0)
	s = input.sample(DT, true)
	_check("Arm ON after OFF arms", s.pilot[FC.IN_ARM] == 1.0, str(s.raw))
	input.sample(DT, false)
	s = input.sample(DT, true)
	_check("a hold boundary clears Arm until fresh OFF evidence", s.pilot[FC.IN_ARM] == 0.0)
	_motion(input, 5, -1.0)
	s = input.sample(DT, true)
	_motion(input, 5, 1.0)
	s = input.sample(DT, true)
	_check("Arm re-arms after OFF then ON", s.pilot[FC.IN_ARM] == 1.0)


func _flight_mode_switch() -> void:
	_reset_devices()
	var buttons := [20, 21]
	_buttons = {21: true}
	var input := _seamed()
	input.connect_device(0, {name = "EdgeTX test radio", kind = "radio"},
		_radio_profile({"gear": _axis(4), "flight_mode": {"type": "switch", "buttons": buttons, "invert": false, "label": "SF"}}))
	_check("a flight-mode switch is reported for the OSD", input.mode_from_switch() and input.bindings().mode_switch)
	var s: Dictionary = input.sample(DT, true)
	_check("an unconfirmed mode switch starts in Angle (its OFF position)", s.pilot[FC.IN_MODE] == float(FC.FLIGHT_ANGLE)
		and s.raw.mode_source == "switch:flight_mode", str(s.raw))
	_keys.mode = true
	s = input.sample(DT, true)
	_keys.mode = false
	s = input.sample(DT, true)
	_check("the M key does not fight a bound mode switch", s.pilot[FC.IN_MODE] == float(FC.FLIGHT_ANGLE))
	_switch_to(input, buttons, 0)
	s = input.sample(DT, true)
	_check("mode switch OFF after its baseline arms the channel: Angle", s.pilot[FC.IN_MODE] == float(FC.FLIGHT_ANGLE))
	_switch_to(input, buttons, 1)
	s = input.sample(DT, true)
	_check("mode switch ON: Acro", s.pilot[FC.IN_MODE] == float(FC.FLIGHT_ACRO), str(s.raw))
	_keys.mode = true
	s = input.sample(DT, true)
	_keys.mode = false
	_check("the M key cannot leave Acro while the switch says Acro", s.pilot[FC.IN_MODE] == float(FC.FLIGHT_ACRO))
	input.sample(DT, false)
	s = input.sample(DT, true)
	_check("a pause boundary keeps the last accepted mode (no snap to Angle)", s.pilot[FC.IN_MODE] == float(FC.FLIGHT_ACRO))
	_switch_to(input, buttons, 0)
	s = input.sample(DT, true)
	_check("after the boundary, OFF re-arms the switch and selects Angle", s.pilot[FC.IN_MODE] == float(FC.FLIGHT_ANGLE))
	_check("arming still follows the gear fallback beside a mode switch", input.arm_aux() == "gear")
	_check("mode-switch frames lie in the controller's domain", FC.input_is_valid({throttle_policy = FC.THROTTLE_ABSOLUTE}, s.pilot))


func _flight_mode_three_position() -> void:
	_reset_devices()
	var buttons := [30, 31, 32]
	_buttons = {30: true}
	var input := _seamed()
	input.connect_device(0, {name = "EdgeTX test radio", kind = "radio"},
		_radio_profile({"flight_mode": {"type": "switch", "buttons": buttons, "invert": false}}))
	var s: Dictionary = input.sample(DT, true)
	_switch_to(input, buttons, 1)
	s = input.sample(DT, true)
	_switch_to(input, buttons, 0)
	s = input.sample(DT, true)
	_check("3-position switch: first position is Angle", s.pilot[FC.IN_MODE] == float(FC.FLIGHT_ANGLE))
	_switch_to(input, buttons, 1)
	s = input.sample(DT, true)
	_check("3-position switch: middle position is Acro", s.pilot[FC.IN_MODE] == float(FC.FLIGHT_ACRO), str(s.raw))
	_switch_to(input, buttons, 2)
	s = input.sample(DT, true)
	_check("3-position switch: last position is Acro", s.pilot[FC.IN_MODE] == float(FC.FLIGHT_ACRO))
	_check("no gear and no Arm: the radio keeps the arm toggle", input.arm_aux() == "" and s.raw.arm_source == "toggle")


func _gamepad() -> void:
	_reset_devices()
	var pad := _seamed()
	pad.radio.confirmed_gamepad_connection = func(_device: int) -> bool: return true
	var legacy := ControllerProfile.defaults("gamepad", "mode2")
	legacy.aux = {"gear": {"type": "button", "button": 20, "mode": "level"}}
	pad.connect_device(1, {name = "Test gamepad", known = true}, legacy)
	var bindings: Dictionary = pad.bindings()
	_check("a gamepad never armed from gear and still does not (LB/RB unchanged)", pad.arm_aux() == "" and not bindings.arm_switch
		and bindings.arm == "LB" and bindings.mode == "RB" and not bindings.mode_switch, str(bindings))
	var explicit := ControllerProfile.defaults("gamepad", "mode2")
	explicit.aux = {"arm": {"type": "button", "button": 20, "mode": "toggle_edge"}}
	var pad2 := _seamed()
	pad2.radio.confirmed_gamepad_connection = func(_device: int) -> bool: return true
	pad2.connect_device(1, {name = "Test gamepad", known = true}, explicit)
	_check("an explicit Arm binding on a gamepad is honoured", pad2.arm_aux() == "arm" and pad2.bindings().arm_switch)


func _validation() -> void:
	var overlap := _radio_profile({"arm": _axis(0)})
	var report: Dictionary = ControllerProfile.validate(overlap)
	var paths: Array = []
	for issue: Dictionary in report.issues:
		paths.append_array(issue.paths)
	_check("Arm on a flight axis is invalid and names its field", not report.ok and paths.has("aux.arm.axis"), str(report.errors))
	var same_button := _radio_profile({"gear": {"type": "button", "button": 20, "mode": "level"},
		"arm": {"type": "button", "button": 20, "mode": "level"}})
	report = ControllerProfile.validate(same_button)
	_check("Arm and Landing gear on one button conflict", not report.ok and str(report.errors).contains("aux.gear and aux.arm"), str(report.errors))
	var switch_overlap := _radio_profile({"flight_mode": {"type": "switch", "buttons": [20, 21], "invert": false},
		"smoke": {"type": "button", "button": 21, "mode": "level"}})
	report = ControllerProfile.validate(switch_overlap)
	_check("a Flight mode switch reserves every member button", not report.ok and str(report.errors).contains("flight_mode"), str(report.errors))
	var action_conflict := _radio_profile({"arm": {"type": "button", "button": 20, "mode": "level"}})
	action_conflict.actions.camera_cycle = {"type": "button", "button": 20}
	report = ControllerProfile.validate(action_conflict)
	_check("an action on the Arm button conflicts", not report.ok and str(report.errors).contains("Action camera_cycle conflicts with aux.arm"), str(report.errors))
	var malformed := _radio_profile({"flight_mode": {"type": "switch", "buttons": [20, 20], "invert": false}})
	_check("a malformed Flight mode switch group is not silently upgraded", ControllerProfile.upgrade_legacy(malformed).is_empty())
	var future := _radio_profile({"gear": _axis(4), "future_channel": {"type": "button", "button": 20, "mode": "level"}})
	future.aux["arm_typo"] = {"anything": true}
	var input := _seamed()
	input.connect_device(0, {name = "EdgeTX test radio", kind = "radio"}, future)
	_check("unknown AUX keys stay ignored: the profile is valid and gear still arms", ControllerProfile.validate(future).ok
		and input.arm_aux() == "gear" and not input.mode_from_switch())


func _persistence_and_merge() -> void:
	for path: String in [STORE_PATH, STORE_PATH + ".rollback", LEGACY_STORE_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var store: RefCounted = ControllerStore.new(STORE_PATH, LEGACY_STORE_PATH)
	var profile := _radio_profile({"arm": _axis(5), "flight_mode": {"type": "switch", "buttons": [40, 41, 42], "invert": true, "label": "SF"}})
	var saved: Dictionary = store.save_profile(profile)
	var loaded: Dictionary = store.load_all()
	var found: Dictionary = {}
	for candidate: Dictionary in loaded.get("profiles", []):
		if str(candidate.get("profile_id", "")) == str(profile.profile_id):
			found = candidate
	_check("Arm and Flight mode survive a store round trip", saved.get("ok", false) and loaded.get("ok", false)
		and found.get("aux", {}) == profile.aux, "%s / %s" % [saved.get("error", ""), found.get("aux", {})])
	for path: String in [STORE_PATH, STORE_PATH + ".rollback", LEGACY_STORE_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var calibration := RcInput.DEFAULT_PROFILE.duplicate(true)
	calibration.roll.axis = 5
	calibration.yaw.axis = 3
	var merged := ControllerProfile.merge_radio_calibration(profile, calibration)
	_check("calibration drops an Arm axis it now uses and keeps the mode switch", not merged.is_empty()
		and not merged.get("aux", {}).has("arm") and merged.get("aux", {}).get("flight_mode", {}) == profile.aux.flight_mode,
		str(merged.get("aux", {})))


func _diagnostics() -> void:
	var profile := _radio_profile({"arm": _axis(5), "flight_mode": {"type": "switch", "buttons": [40, 41], "invert": false}})
	var report: Dictionary = Diagnostics.build({}, profile, {"activity_capabilities": {"multirotor": true}})
	_check("diagnostics export the quad AUX channels", report.profile.auxiliary.has("arm") and report.profile.auxiliary.has("flight_mode")
		and report.profile.auxiliary.flight_mode.buttons == [40, 41], str(report.profile.auxiliary))
	_check("diagnostics keep the multirotor activity capability", report.profile.effective_actions.activity_capabilities.values == {"multirotor": true},
		str(report.profile.effective_actions.activity_capabilities))


func _row(setup: Node, aux_name: String) -> Control:
	return setup.find_child("AuxChannel_%s" % aux_name, true, false) as Control


func _setup_rows() -> void:
	root.size = Vector2i(1920, 1080)
	var plane := ControllerSetup.new()
	plane.configure(FakeRegistry.new(), FakeStore.new(), 9, -1, ControllerActions.AIRPLANE_CAPABILITIES)
	root.add_child(plane)
	await process_frame
	plane._draft_profile = _radio_profile({"gear": _axis(4)})
	plane._update_aux_controls()
	_check("airplane: quad rows hidden, airplane rows shown", not _row(plane, "arm").visible and not _row(plane, "flight_mode").visible
		and _row(plane, "smoke").visible and _row(plane, "flaps").visible and _row(plane, "gear").visible)
	_check("airplane: no legacy arm hint", not plane.aux_legacy_arm_hint.visible)
	plane.show_all_vehicle_aux.button_pressed = true
	_check("Show channels for all vehicles reveals the quad rows", _row(plane, "arm").visible and _row(plane, "flight_mode").visible)
	_check("quad rows are named for assistive technology",
		str(plane._aux_controls.arm.type.accessibility_name) == "Arm (FPV quad) input type"
		and str(plane._aux_controls.flight_mode.type.accessibility_name) == "Flight mode (FPV quad) input type",
		str(plane._aux_controls.arm.type.accessibility_name))
	plane.free()
	var quad := ControllerSetup.new()
	quad.configure(FakeRegistry.new(), FakeStore.new(), 9, -1, ControllerActions.MULTIROTOR_CAPABILITIES)
	root.add_child(quad)
	await process_frame
	quad._draft_profile = _radio_profile({"gear": _axis(4), "smoke": {"type": "button", "button": 7, "mode": "level"}})
	quad._update_aux_controls()
	_check("quad: Arm and Flight mode rows shown", _row(quad, "arm").visible and _row(quad, "flight_mode").visible)
	_check("quad: the legacy gear arm row and hint stay visible; smoke and flaps are hidden but kept",
		_row(quad, "gear").visible and quad.aux_legacy_arm_hint.visible and not _row(quad, "smoke").visible
		and not _row(quad, "flaps").visible and quad._draft_profile.aux.has("smoke"))
	_check("the legacy hint names the Landing gear switch", quad.aux_legacy_arm_hint.text == ControllerSetup.AUX_LEGACY_ARM_HINT)
	var committed: bool = quad._commit_aux_binding("arm", _axis(5), false)
	_check("assigning Arm clears the hint and hides the gear row", committed and not quad.aux_legacy_arm_hint.visible
		and not _row(quad, "gear").visible and quad._draft_profile.aux.has("gear"))
	_check("a conflicting Flight mode switch is rejected by the shared validator",
		not quad._commit_aux_binding("flight_mode", {"type": "switch", "buttons": [7, 8], "invert": false}, false)
		and not quad._draft_profile.aux.has("flight_mode"))
	_check("the rejection reveals the hidden Smoke row it conflicts with", quad.show_all_vehicle_aux.button_pressed and _row(quad, "smoke").visible)
	quad.show_all_vehicle_aux.button_pressed = false
	quad._draft_profile = ControllerProfile.defaults("gamepad", "mode2")
	quad._draft_profile.aux = {"gear": {"type": "button", "button": 20, "mode": "level"}}
	quad._update_aux_controls()
	_check("quad: no legacy hint for a gamepad (gear never armed it)", not quad.aux_legacy_arm_hint.visible and not _row(quad, "gear").visible)
	quad.free()
	await process_frame

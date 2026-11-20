# DR-14d (docs/plans/drone-racing.md §17.1): preconfigured FPV controls. The EdgeTX FPV preset maps CH5 arm (only its
# high end arms), CH6 flight mode and CH9 restart; EdgeTX radios are recognized by USB pair or family name; the quad
# restarts on the pad from a pad's View/Back or the radio's restart switch, only on a fresh OFF-to-ON edge and never
# through a control an AUX channel owns; the help names it; the pause menu's crash setting reaches the session.
# Synthetic devices and events: no physical radio, gamepad or native event-dispatch claim.
extends SceneTree

const Activity := preload("res://vehicles/multirotor/multirotor_scene.gd")
const Profile := preload("res://input/controller_profile.gd")
const Actions := preload("res://input/controller_actions.gd")
const SmokeAux := preload("res://input/smoke_aux.gd")
const EdgeTx := preload("res://input/edgetx_radio.gd")
const Hud := preload("res://vehicles/multirotor/multirotor_hud.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const DT := 1.0 / 240.0

var _count := 0
var _failures := 0


class FakeRegistry extends RefCounted:
	signal selection_changed(role: String, id: int)
	var device := {}
	func selected_device_id(role: String) -> int:
		return int(device.id) if role == "flight" and not device.is_empty() else -1
	func device_for_id(id: int) -> Dictionary:
		return device if not device.is_empty() and id == int(device.id) else {}
	func connection_generation(_id: int) -> int:
		return 1


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_preset()
	_identity()
	_restart_from_gamepad()
	_restart_from_radio()
	_crash_setting()
	print("controls presets: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _preset() -> void:
	var p: Dictionary = Profile.defaults("radio", Profile.EDGETX_FPV_PRESET)
	_check("the EdgeTX FPV preset validates for the quad and for airplanes", not p.is_empty() and Profile.validate(p).ok
		and Actions.validate_profile_bindings(p, Actions.MULTIROTOR_CAPABILITIES).ok and Actions.validate_profile_bindings(p).ok)
	_check("AETR sticks on axes 0-3 like the custom radio", int(p.roll.axis) == 0 and int(p.pitch.axis) == 1
		and int(p.throttle.axis) == 2 and int(p.yaw.axis) == 3)
	var arm: Dictionary = p.aux.arm
	_check("arm on CH5 (axis 4): low and middle are OFF, only the high end is ON", int(arm.axis) == 4
		and SmokeAux.axis_amount(-1.0, arm) == 0.0 and SmokeAux.axis_amount(0.0, arm) == 0.0 and SmokeAux.axis_amount(1.0, arm) == 1.0)
	var mode: Dictionary = p.aux.flight_mode
	_check("flight mode on CH6 (axis 5): low Angle, middle and high Acro", int(mode.axis) == 5
		and SmokeAux.axis_amount(-1.0, mode) < 0.5 and SmokeAux.axis_amount(0.0, mode) >= 0.5 and SmokeAux.axis_amount(1.0, mode) >= 0.5)
	_check("restart on CH9 (joystick button 1 = button 0); CH7/CH8 left free", p.actions.restart_flight == {"type": "button", "button": 0}
		and not str(p.aux.keys()).contains("6") and p.aux.size() == 2)


func _identity() -> void:
	_check("EdgeTX by USB pair 1209:4F54", EdgeTx.matches({name = "Joystick", vendor_id = 0x1209, product_id = 0x4F54}))
	_check("EdgeTX by family name", EdgeTx.matches({name = "RadioMaster TX16S Joystick"}) and EdgeTx.matches({name = "Jumper T-Pro"}))
	_check("not a gamepad or a JETI radio", not EdgeTx.matches({name = "Xbox Wireless Controller", vendor_id = 0x045E, product_id = 0x0B13})
		and not EdgeTx.matches({name = "JETI DC-24 radio", vendor_id = 0x0483, product_id = 0xA07C}))


func _activity(device: Dictionary, profile: Dictionary, buttons: Dictionary) -> Node3D:
	var registry := FakeRegistry.new()
	registry.device = device
	var activity: Node3D = Activity.new()
	activity.enable_world = false
	activity.enable_audio = false
	activity.departure_managed = true
	activity.race_track = ""
	activity.controller_registry = registry
	var resolve := func(_id: int) -> Dictionary: return profile.duplicate(true)
	activity.controller_profile_for = resolve
	activity.controller_confirmation = func(_a: int, _b: int, _c: int) -> bool: return true
	activity.input.read_axis = func(_id: int, axis: int) -> float: return -1.0 if axis == 2 else 0.0
	activity.input.read_button = func(_id: int, button: int) -> bool: return bool(buttons.get(button, false))
	activity.input.read_keys = func() -> Dictionary: return {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0, arm = false, mode = false}
	root.add_child(activity)
	activity.set_physics_process(false)
	return activity


func _button(activity: Node3D, device: int, button: int, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = button as JoyButton
	event.pressed = pressed
	activity._input(event)


func _fly(activity: Node3D, ticks: int) -> void:
	activity.handle_action("resume")
	for i in ticks:
		activity._physics_process(DT)


func _restart_from_gamepad() -> void:
	var pad := {id = 7, connected = true, name = "Synthetic pad", guid = "pad", known = true, kind = "gamepad"}
	var back := int(JOY_BUTTON_BACK)
	var activity := _activity(pad, Profile.defaults("gamepad", "mode2"), {})
	_fly(activity, 10)
	_check("setup: the pad flies (ticks accepted)", int(activity.session.sim.tick) == 10)
	_button(activity, 7, back, true)
	_check("a View/Back held before any release does not restart (fresh OFF required)", int(activity.session.sim.tick) == 10)
	_button(activity, 7, back, false)
	_button(activity, 8, back, true)
	_check("another device's View/Back has no say", int(activity.session.sim.tick) == 10)
	activity._open_menu("Flight paused")
	_button(activity, 7, back, true)
	_check("with the menu (or a dialog over it) open, View/Back is only observed: no restart", int(activity.session.sim.tick) == 10)
	_button(activity, 7, back, false)
	activity.handle_action("resume")
	_button(activity, 7, back, true)
	_check("View/Back after a release restarts on the pad", int(activity.session.sim.tick) == 0)
	_check("the help names the controller's restart", "Restart on the pad: R or" in activity.hud.help.text
		or "Restart on the pad: R or" in "\n".join(activity.hud.controls_help_lines(activity.input.bindings())))
	activity.free()
	var owned := Profile.defaults("gamepad", "mode2")
	owned.aux = {"arm": {"type": "button", "button": back, "mode": "level"}}
	var aux_activity := _activity(pad, owned, {})
	_check("an AUX channel on View/Back takes it: no restart binding", aux_activity.input.restart_binding().is_empty())
	aux_activity.free()


func _restart_from_radio() -> void:
	var radio := {id = 3, connected = true, name = "RadioMaster TX16S Joystick", guid = "radio", known = false, kind = "radio"}
	var activity := _activity(radio, Profile.defaults("radio", Profile.EDGETX_FPV_PRESET), {})
	_check("the EdgeTX radio's restart binding is CH9 (button 0)", activity.input.restart_binding() == {"type": "button", "button": 0})
	_check("the help names it as the radio's button 1, never a gamepad face button", str(activity.input.bindings().restart_control)
		== "Button 1", str(activity.input.bindings().restart_control))
	# Fly a little from the keyboard-free radio fixture (the throttle reads low), then press CH9 after a release.
	activity.input.radio.on_motion(3, 2, -1.0)
	_fly(activity, 5)
	var before := int(activity.session.sim.tick)
	_button(activity, 3, 0, false)
	_button(activity, 3, 0, true)
	_check("the radio's CH9 switch restarts on the pad", before > 0 and int(activity.session.sim.tick) == 0, "tick %d" % before)
	activity.free()


func _crash_setting() -> void:
	var pad := {id = 7, connected = true, name = "Synthetic pad", guid = "pad", known = true, kind = "gamepad"}
	var activity := _activity(pad, Profile.defaults("gamepad", "mode2"), {})
	_check("the activity prepares graded crashes by default", str(activity.session.options.crash_model) == "graded")
	activity.handle_action("crash_model")
	_check("the pause menu's crash setting applies at once on the untouched pad", str(activity.session.options.crash_model) == "strict"
		and "every crash ends the flight" in activity.hud.crash_button.text, activity.hud.crash_button.text)
	_fly(activity, 5)
	activity._open_menu("Flight paused")
	activity.handle_action("crash_model")
	_check("after a flight the change waits for Restart on pad", str(activity.session.options.crash_model) == "strict"
		and activity.crash_model == "graded" and activity.hud.limit_note.visible)
	activity.handle_action("restart")
	_check("Restart on pad applies it", str(activity.session.options.crash_model) == "graded")
	activity.free()

# Observation probe for baseline 35c20367 / production cfb5acd5.
# A successful run observes a remapped Pause plus AUX on Start, then the real
# activity's two event handlers. It is not a desired-behavior regression test.
# Synthetic selected pad; no physical-controller or native event-dispatch claim.
extends SceneTree

const Activity := preload("res://vehicles/multirotor/multirotor_scene.gd")
const Profile := preload("res://input/controller_profile.gd")
const Actions := preload("res://input/controller_actions.gd")
const DT := 1.0 / 240.0
const DEVICE := 7

class Registry extends RefCounted:
	signal selection_changed(role: String, id: int)
	func selected_device_id(role: String) -> int:
		return 7 if role == "flight" else -1
	func device_for_id(id: int) -> Dictionary:
		return {"id": id, "connected": true, "name": "Synthetic pad", "guid": "audit-pad",
			"known": true, "kind": "gamepad"} if id == 7 else {}
	func connection_generation(_id: int) -> int:
		return 1

var pressed := false
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, condition: bool) -> void:
	checks += 1
	print("%s %s" % ["ok  " if condition else "FAIL", label])
	if not condition:
		failures += 1

func button(id: int, is_pressed: bool) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = id
	event.button_index = JOY_BUTTON_START
	event.pressed = is_pressed
	return event

func one_channel(channel: String) -> void:
	pressed = false
	var profile := Profile.defaults("gamepad", "mode2")
	profile.actions["pause"] = {"type": "key", "physical_keycode": KEY_P}
	profile.aux = {}
	profile.aux[channel] = {"type": "button", "button": JOY_BUTTON_START, "mode": "level"}
	var validation: Dictionary = Profile.validate(profile)
	check("%s on Start with Pause remapped validates" % channel, validation.ok)
	var effective: Dictionary = Actions.effective_bindings(profile, Actions.MULTIROTOR_CAPABILITIES)
	check("%s effective Pause is P, not Start" % channel, effective.pause.get("type", "") == "key" \
		and int(effective.pause.get("physical_keycode", 0)) == KEY_P)

	var activity := Activity.new()
	activity.enable_world = false
	activity.enable_audio = false
	activity.departure_managed = true
	activity.race_track = ""
	activity.controller_registry = Registry.new()
	activity.controller_profile_for = func(_id: int) -> Dictionary: return profile.duplicate(true)
	activity.controller_confirmation = func(id: int, expected_id: int, generation: int) -> bool:
		return id == DEVICE and expected_id == DEVICE and generation == 1
	activity.input.read_axis = func(_id: int, _axis: int) -> float: return 0.0
	activity.input.read_button = func(_id: int, index: int) -> bool:
		return pressed if index == JOY_BUTTON_START else false
	activity.input.read_keys = func() -> Dictionary:
		return {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": 0.0, "arm": false, "mode": false}
	root.add_child(activity)
	activity.set_physics_process(false)
	var started: bool = activity.startup_error.is_empty() and activity.session != null and activity.session.prepared
	check("%s real activity adopts selected profile" % channel, started and activity.input.radio.connected \
		and activity.input.radio.is_gamepad() and activity.input.radio.profile.get("aux", {}).has(channel))
	if not started:
		root.remove_child(activity)
		activity.free()
		return
	activity.handle_action("resume")
	activity._physics_process(DT) # Enable AUX on an integrating sample.
	var release := button(DEVICE, false)
	activity._input(release)
	activity._unhandled_input(release)
	activity._physics_process(DT)
	check("%s Start release is fresh OFF evidence" % channel, not activity.session.paused \
		and activity.input.radio.auxiliary_request_valid(channel) \
		and activity.input.radio.auxiliary_amount(channel) == 0.0)
	var foreign := button(DEVICE + 1, true)
	activity._input(foreign)
	activity._unhandled_input(foreign)
	check("%s foreign Start cannot pause or change AUX" % channel, not activity.session.paused \
		and activity.input.radio.auxiliary_amount(channel) == 0.0)
	pressed = true
	var event := button(DEVICE, true)
	activity._input(event) # Godot's input phase: AUX observes the selected pad press.
	check("%s Start press sets a valid AUX request" % channel, activity.input.radio.auxiliary_request_valid(channel) \
		and activity.input.radio.auxiliary_amount(channel) == 1.0)
	var previous_tick: int = activity.session.sim.tick
	activity._unhandled_input(event) # Godot's later unhandled phase: the scene also treats Start as Pause.
	check("%s same Start press opens the scene's Pause menu" % channel, activity.session.paused \
		and activity.hud.menu_visible and activity.session.sim.tick == previous_tick)
	root.remove_child(activity)
	activity.free()

func _run() -> void:
	one_channel("arm")
	one_channel("flight_mode")
	print("Start/AUX scene repro: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

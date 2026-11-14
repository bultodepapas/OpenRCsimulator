# CTRL-04/05: real airship input, pause/resume session and activity routing with
# synthetic controls and a registry. No rendered world or physical device.
extends SceneTree

const Activity := preload("res://vehicles/airship/airship_scene.gd")
const Session := preload("res://sim/airship/session.gd")
const Registry := preload("res://input/controller_registry.gd")
const Profile := preload("res://input/controller_profile.gd")
const DT := 1.0 / 240.0

class TestActivity extends Activity:
	func _ready() -> void:
		set_physics_process(false)
		set_process(false)

class TestHud extends CanvasLayer:
	var menu_visible := true
	var menu_reason := ""
	var last_flash := ""
	func show_menu(reason: String, _can_resume: bool) -> void:
		menu_visible = true
		menu_reason = reason
	func hide_menu() -> void: menu_visible = false
	func flash(message: String) -> void: last_flash = message

var axes := {}
var keys := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
var verified := true
var checks := 0
var failures := 0


func check(label: String, ok: bool) -> void:
	checks += 1
	print("%s %s" % ["ok  " if ok else "FAIL", label])
	if not ok: failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _setup() -> Node:
	var activity := TestActivity.new()
	root.add_child(activity)
	activity.session = Session.new()
	root.add_child(activity.session)
	activity.hud = TestHud.new()
	root.add_child(activity.hud)
	activity.input.read_axis = func(_id: int, axis: int) -> float: return float(axes.get(axis, 0.0))
	activity.input.read_button = func(_id: int, _button: int) -> bool: return false
	activity.input.read_keys = func() -> Dictionary: return keys.duplicate()
	check("real airship session prepares", activity.session.prepare({}, {}))
	return activity


func _dispose(activity: Node) -> void:
	activity.session.free()
	activity.session = null
	activity.hud.free()
	activity.hud = null
	activity.free()


func _pause_recovery() -> void:
	var activity := _setup()
	activity.handle_action("resume")
	check("keyboard resumes from the prepared state", not activity.session.paused)
	keys.throttle = 1.0
	keys.yaw = 1.0
	for i in 300: activity.input.sample(DT, true)
	var flying: Dictionary = activity.input.sample(DT, true)
	check("normal keyboard input creates nonzero throttle and yaw", flying.sticks[3] > 0.5 and flying.sticks[2] > 0.5)
	var tick_before: int = activity.session.sim.tick
	activity._open_menu("Paused")
	var held: Dictionary = activity.input.sample(DT, false)
	check("pause resets keyboard throttle and yaw and explains it", held.sticks[3] == 0.0 and held.sticks[2] == 0.0 \
		and "reset" in activity.hud.menu_reason)
	for i in 100: held = activity.input.sample(DT, false)
	check("held input cannot raise virtual controls or advance simulation while paused", held.sticks[3] == 0.0 \
		and activity.session.sim.tick == tick_before)
	keys.throttle = 0.0
	keys.yaw = 0.0
	activity.handle_action("resume")
	check("keyboard resumes without a restart", not activity.session.paused)
	activity._open_menu("Paused again")
	activity.handle_action("resume")
	check("repeated keyboard pause and resume works", not activity.session.paused)

	# Centered-stick gamepad accumulates throttle in the shared input reader.
	axes = {0: 0.0, 1: -1.0, 2: 0.0, 3: 0.0}
	var rate := Profile.defaults("gamepad", "mode2")
	activity.input.connect_device(7, {name = "Synthetic pad", known = true}, rate)
	activity.input.radio.confirmed_gamepad_connection = func(_id: int) -> bool: return verified
	for i in 300: activity.input.sample(DT, true)
	check("normal gamepad input accumulates rate throttle", activity.input.sample(DT, true).sticks[3] > 0.5)
	axes[0] = 0.8
	activity._open_menu("Paused")
	held = activity.input.sample(DT, false)
	check("pause clears rate throttle but preserves physical yaw", held.sticks[3] == 0.0 and held.sticks[2] > 0.05)
	activity.handle_action("resume")
	check("resume rejects deflected physical yaw", activity.session.paused and "yaw" in activity.hud.last_flash.to_lower())
	axes[0] = 0.0
	activity.handle_action("resume")
	check("centering physical yaw permits gamepad resume", not activity.session.paused)

	# A trigger's absolute throttle must still be physically lowered.
	var trigger := Profile.defaults("gamepad", "trigger_absolute")
	axes = {0: 0.0, 1: 0.0, 2: 0.0, 3: 0.0, 5: 1.0}
	activity.input.connect_device(7, {name = "Synthetic pad", known = true}, trigger)
	activity._open_menu("Paused")
	activity.handle_action("resume")
	check("absolute trigger remains subject to the low-throttle gate", activity.session.paused)
	axes[5] = -1.0
	activity.handle_action("resume")
	check("lowering the trigger permits resume", not activity.session.paused)

	var radio := Profile.defaults("radio", "radio_custom")
	axes = {0: 0.0, 1: 0.0, 2: -1.0, 3: 0.0}
	activity.input.connect_device(9, {name = "Synthetic radio", kind = "radio"}, radio)
	activity.input.radio.on_motion(9, 2, -1.0)
	activity.input.sample(DT, true)
	axes[2] = 1.0
	activity._open_menu("Paused")
	activity.handle_action("resume")
	check("absolute radio throttle is not reset behind the pilot's back", activity.session.paused)
	axes[2] = -1.0
	activity.handle_action("resume")
	check("lowering radio throttle permits resume", not activity.session.paused)
	activity._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check("focus loss pauses and requires fresh radio evidence", activity.session.paused \
		and not activity.input.sample(DT, false).armed)
	activity.input.radio.on_motion(9, 2, -1.0)
	activity.handle_action("resume")
	check("focus recovery accepts a new low radio event", not activity.session.paused)
	_dispose(activity)


func _button(id: int, button: int, pressed: bool) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = id
	event.button_index = button as JoyButton
	event.pressed = pressed
	return event


func _ownership() -> void:
	keys = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
	axes = {}
	var activity := _setup()
	var registry := Registry.new()
	var devices := [
		{id = 3, name = "Foreign pad", guid = "foreign", known = true, kind = "gamepad"},
		{id = 7, name = "Selected pad", guid = "selected", known = true, kind = "gamepad"},
		{id = 9, name = "Synthetic radio", guid = "radio", serial_number = "receiver-a", known = false, kind = "radio"},
	]
	registry.update_devices(devices)
	var pad := Profile.defaults("gamepad", "mode2")
	pad.roll.deadzone = 0.2
	pad.actions = {"pause": {"type": "button", "button": JOY_BUTTON_X}, "overlay_preset": {"type": "unbound"}}
	check("remapped gamepad fixture is a valid V2 profile", Profile.validate(pad).ok)
	var radio := Profile.defaults("radio", "radio_custom")
	radio.actions["pause"] = {"type": "button", "button": 20}
	var profiles := {7: pad, 9: radio}
	activity.controller_registry = registry
	activity.controller_profile_for = func(id: int) -> Dictionary: return profiles.get(id, {}).duplicate(true)
	activity.controller_confirmation = func(id: int, expected: int, generation: int) -> bool:
		return verified and id == expected and registry.selected_device_id("flight") == id \
			and registry.connection_generation(id) == generation
	registry.selection_changed.connect(activity._on_controller_selection_changed)
	activity._connect_selected_controller()
	activity._refresh_pause_bindings()
	check("explicit keyboard owns flight with pads connected", activity.input.source() == "keyboard")
	activity.handle_action("resume")
	activity._input(_button(3, JOY_BUTTON_START, true))
	check("a foreign Start cannot pause keyboard flight", not activity.session.paused)
	registry.select_device("ui", 7)
	registry.select_device("flight", 7)
	check("selecting the second pad pauses and applies its V2 profile", activity.session.paused \
		and activity.input.radio.device_id == 7 and is_equal_approx(float(activity.input.radio.profile.roll.deadzone), 0.2))
	check("selected pad is ready from verified neutral polling", activity.input.sample(DT, false).armed)
	verified = false
	check("verifier revocation removes readiness", not activity.input.sample(DT, false).armed)
	activity.handle_action("resume")
	check("resume cannot bypass revoked verification", activity.session.paused)
	verified = true
	activity.handle_action("resume")
	activity._joy_connection_changed(3, true)
	check("unrelated hotplug does not pause flight", not activity.session.paused)
	activity._input(_button(3, JOY_BUTTON_START, true))
	activity._input(_button(7, JOY_BUTTON_START, true))
	check("foreign and unmapped Start buttons do not pause", not activity.session.paused)
	activity._input(_button(7, JOY_BUTTON_X, true))
	check("the selected profile's remapped Pause works", activity.session.paused)
	activity._input(_button(7, JOY_BUTTON_X, false))
	activity._input(_button(7, JOY_BUTTON_X, true))
	check("the selected UI role's Pause resumes after release", not activity.session.paused)
	var changed := pad.duplicate(true)
	changed.roll.deadzone = 0.3
	changed.actions["pause"] = {"type": "key", "physical_keycode": KEY_K}
	profiles[7] = changed
	check("saved profile is adopted and flight is held", activity.apply_controller_selection(7) \
		and activity.session.paused and is_equal_approx(float(activity.input.radio.profile.roll.deadzone), 0.3))
	activity.handle_action("resume")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_K
	key.pressed = true
	activity._input(key)
	check("the saved keyboard Pause binding is honored", activity.session.paused)
	registry.select_device("flight", 3) # no service-resolved profile for this otherwise known pad
	check("an unresolved managed pad does not acquire a guessed default mapping", \
		activity.input.radio.connected and activity.input.radio.device_id == 3 \
		and not activity.input.sample(DT, false).armed and not str(activity.input.radio.profile_error).is_empty())
	registry.select_device("flight", 9)
	axes = {0: 0.0, 1: 0.0, 2: -1.0, 3: 0.0}
	activity.input.radio.on_motion(9, 2, -1.0)
	activity.handle_action("resume")
	activity._input(_button(9, JOY_BUTTON_START, true))
	check("raw transmitter button 6 is not an inherited Pause", not activity.session.paused)
	activity._input(_button(9, 20, true))
	check("a raw mapped Pause held ON at selection has no authority", not activity.session.paused)
	activity._input(_button(9, 20, false))
	activity._input(_button(9, 20, true))
	check("a raw mapped Pause works only after its OFF event", activity.session.paused)
	activity.handle_action("resume")
	activity._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	activity.input.radio.on_motion(9, 2, -1.0)
	activity.handle_action("resume")
	activity._input(_button(9, 20, true))
	check("focus loss invalidates the raw Pause switch's earlier OFF evidence", not activity.session.paused)
	registry.disconnect_device(9)
	check("loss of the selected radio pauses, selects keyboard and explains how to choose a controller", activity.session.paused \
		and activity.input.source() == "keyboard" and "return Home" in activity.hud.menu_reason)
	activity._joy_connection_changed(3, true)
	check("an unrelated controller does not take over after loss", activity.input.source() == "keyboard")
	check("an explicit Keyboard choice acknowledges the lost controller", activity.apply_controller_selection(-1))
	devices[2].serial_number = "receiver-b" # same model and reused handle, different physical unit
	registry.update_devices(devices)
	activity._joy_connection_changed(9, true)
	await process_frame
	check("a same-model radio with another serial cannot take ownership", activity.input.source() == "keyboard" \
		and registry.selected_device_id("flight") == -1)
	registry.select_device("flight", 9)
	check("explicitly reselected radio requires fresh readiness", activity.input.radio.connected \
		and activity.input.radio.device_id == 9 and not activity.input.sample(DT, false).armed)
	activity.input.radio.on_motion(9, 2, -1.0)
	activity.handle_action("resume")
	devices[2].serial_number = "receiver-c"
	registry.update_devices(devices)
	check("identity replacement on the same handle releases authority and explains recovery", activity.session.paused \
		and activity.input.source() == "keyboard" and "return Home" in activity.hud.menu_reason)
	_dispose(activity)


func _run() -> void:
	_pause_recovery()
	await _ownership()
	print("vehicle airship audit: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

# DR-14/16 (FPV audit 2026-11-16, A01-A05, A18, A19): desired controller authority of the FPV quad activity.
# Each case is the audit's diagnostic turned into the required behaviour: a refused managed profile stays unready, one
# physical control has one authority, an ordinary hold keeps a held arm switch (and discloses when it cannot), the
# direct route uses the managed controller service and UI device, the help follows the active bindings, and a changed
# connection re-resolves the source behind the menu instead of feeding a stale verifier. Synthetic devices and input:
# no physical controller, native event dispatch or flight qualification is claimed.
extends SceneTree

const Service := preload("res://input/controller_service.gd")
const Activity := preload("res://vehicles/multirotor/multirotor_scene.gd")
const PilotInput := preload("res://input/multirotor_input.gd")
const Profile := preload("res://input/controller_profile.gd")
const Hud := preload("res://vehicles/multirotor/multirotor_hud.gd")
const UiInput := preload("res://ui/ui_input.gd")
const AppRoot := preload("res://app_root.gd")
const Store := preload("res://input/controller_profile_store.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const Fixtures := preload("res://tests/mr_fixtures.gd")
const DT := 1.0 / 240.0

var _count := 0
var _failures := 0
var keys := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0, arm = false, mode = false}
var axes := {}
var buttons := {}
var observations: Array = []


class FakeRegistry extends RefCounted:
	signal selection_changed(role: String, id: int)
	var flight := -1
	var devices := {}
	var generations := {}
	func selected_device_id(role: String) -> int:
		return flight if role == "flight" else -1
	func device_for_id(id: int) -> Dictionary:
		return devices.get(id, {})
	func connection_generation(id: int) -> int:
		return int(generations.get(id, 1))


## Stands in for AppRoot on the direct route: no Home and no controller service.
class DirectApp extends Node:
	var controllers: Node = null
	var has_home := false
	var preferences_path := ""


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _refused_profile()
	_binding_ownership()
	await _start_ownership()
	await _hold_continuity()
	_help()
	await _connection_generation()
	await _direct_route()
	print("controller authority: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _pad(id: int, guid := "authority-pad", serial := "pad-a") -> Dictionary:
	return {id = id, name = "Synthetic pad", raw_name = "Synthetic pad", guid = guid, vendor_id = 700, product_id = 7,
		serial_number = serial, known = true, kind = "gamepad"}


func _activity(registry: RefCounted, resolver: Callable, confirmation: Callable) -> Node3D:
	var activity: Node3D = Activity.new()
	activity.enable_world = false
	activity.enable_audio = false
	activity.departure_managed = true
	activity.race_track = ""
	activity.controller_registry = registry
	activity.controller_profile_for = resolver
	activity.controller_confirmation = confirmation
	activity.input.read_axis = func(_id: int, axis: int) -> float: return float(axes.get(axis, 0.0))
	activity.input.read_button = func(_id: int, button: int) -> bool: return bool(buttons.get(button, false))
	activity.input.read_keys = func() -> Dictionary: return keys.duplicate()
	return activity


func _free(node: Node) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()


func _reset_input() -> void:
	keys = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0, arm = false, mode = false}
	axes = {}
	buttons = {}


## A01: an unsupported controller store refuses the selected known pad's profile; the quad keeps it connected but
## unready and cannot resume or arm. A healthy empty store still resolves the explicit default, which flies.
func _refused_profile() -> void:
	_reset_input()
	var path := "user://mr_authority_refused_%d.cfg" % OS.get_process_id()
	var cfg := ConfigFile.new()
	cfg.set_value(Store.STORAGE_SECTION, "schema_version", 999)
	cfg.set_value(Store.STORAGE_SECTION, "profiles", [])
	_check("A01 setup: unsupported store written", cfg.save(path) == OK)
	for healthy: bool in [false, true]:
		var service := Service.new()
		service.store = Service.Store.new(path + (".healthy" if healthy else ""), path + ".legacy")
		service.enumerate_devices = func() -> Array: return [_pad(7)]
		service.refresh()
		var confirm := func(id: int, expected: int, generation: int) -> bool:
			return id == expected and generation == service.registry.connection_generation(id)
		var activity := _activity(service.registry, Callable(service, "profile_for_device"), confirm)
		root.add_child(activity)
		activity.set_physics_process(false)
		var tag := "healthy store" if healthy else "refused store"
		_check("A01 %s: the selected pad is the connected source" % tag, activity.input.radio.connected
			and int(activity.input.radio.device_id) == 7)
		activity.handle_action("resume")
		activity._physics_process(DT)
		keys.arm = true
		activity._physics_process(DT)
		keys.arm = false
		var armed: bool = activity.session.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED
		if healthy:
			_check("A01 healthy store: the explicit default is ready, resumes and arms", activity.input.radio.is_gamepad()
				and not activity.session.paused and armed and not activity._profile_refused)
		else:
			_check("A01 refused store: no built-in pad mapping replaces the refusal", not activity.input.radio.is_gamepad()
				and activity.input.radio.profile_source == "unconfigured" and activity._profile_refused,
				str(activity.input.radio.profile_source))
			_check("A01 refused store: resume is refused with the repair hint and the motors never arm",
				activity.session.paused and not armed and activity.session.sim.tick == 0
				and Activity.PROFILE_REFUSED_TEXT in activity.hud.message.text, activity.hud.message.text)
			# The pilot repairs the store (here: removes the unsupported file); Continue resolves again.
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			service.refresh()
			activity.handle_action("resume")
			_check("A01 after the store is repaired, Continue resolves the explicit default and resumes",
				not activity._profile_refused and activity.input.radio.is_gamepad() and not activity.session.paused)
		_free(activity)
		service.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _input_with(profile: Dictionary, id: int, info: Dictionary) -> RefCounted:
	var input: RefCounted = PilotInput.new()
	input.read_axis = func(_id: int, axis: int) -> float: return float(axes.get(axis, 0.0))
	input.read_button = func(_id: int, button: int) -> bool: return bool(buttons.get(button, false))
	input.read_keys = func() -> Dictionary: return keys.duplicate()
	input.radio.confirmed_gamepad_connection = func(_id: int) -> bool: return true
	input.connect_device(id, info, profile)
	return input


func _press(input: RefCounted, sim: Node, button: int, pressed: bool) -> Dictionary:
	buttons[button] = pressed
	input.radio.on_button(1, button, pressed)
	var sample: Dictionary = input.sample(DT, true)
	Fixtures.run(sim, sample.pilot, 1)
	return sample


## A02: one authority per physical control. Flight mode AUX on LB changes the mode but never arms; Arm AUX on RB
## arms but never changes the mode; the default pad keeps LB arm and RB mode; an AUX on Start removes Start as Pause.
func _binding_ownership() -> void:
	_reset_input()
	var lb := int(JOY_BUTTON_LEFT_SHOULDER)
	var rb := int(JOY_BUTTON_RIGHT_SHOULDER)
	var mode_on_lb := Profile.defaults("gamepad", "mode2")
	mode_on_lb.aux = {"flight_mode": {"type": "button", "button": lb, "mode": "level"}}
	var input := _input_with(mode_on_lb, 1, {name = "Synthetic gamepad", known = true})
	var fixture: Dictionary = Fixtures.install(root, Fixtures.lab())
	Fixtures.reset(fixture.sim, fixture.plant.initial_frame(Fixtures.body(20.0)), FC.neutral_input())
	var sim: Node = fixture.sim
	_check("A02 Flight mode on LB: LB is no arm shortcut, RB stays the mode shortcut? no: the switch owns the mode",
		input.bindings().arm_button == "" and input.bindings().mode_button == "")
	_press(input, sim, lb, false)
	var pressed := _press(input, sim, lb, true)
	_check("A02 LB selects Acro through the Flight mode switch and does not arm", pressed.pilot[FC.IN_MODE] == float(FC.FLIGHT_ACRO)
		and pressed.pilot[FC.IN_ARM] == 0.0 and sim.modes[FC.MODE_MOTOR] != FC.MOTOR_ARMED)
	_press(input, sim, lb, false)
	keys.arm = true
	var armed := _press(input, sim, lb, false)
	keys.arm = false
	_press(input, sim, lb, false)
	_check("A02 E still arms with Flight mode on LB", armed.pilot[FC.IN_ARM] == 1.0 and sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED)
	var again := _press(input, sim, lb, true)
	_check("A02 the next LB mode press keeps the motors armed", again.pilot[FC.IN_ARM] == 1.0
		and sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED and again.pilot[FC.IN_MODE] == float(FC.FLIGHT_ACRO))
	sim.free()

	_reset_input()
	var arm_on_rb := Profile.defaults("gamepad", "mode2")
	arm_on_rb.aux = {"arm": {"type": "button", "button": rb, "mode": "level"}}
	input = _input_with(arm_on_rb, 1, {name = "Synthetic gamepad", known = true})
	fixture = Fixtures.install(root, Fixtures.lab())
	Fixtures.reset(fixture.sim, fixture.plant.initial_frame(Fixtures.body(20.0)), FC.neutral_input())
	sim = fixture.sim
	var mode_before: float = input.sample(DT, true).pilot[FC.IN_MODE]
	_press(input, sim, rb, false)
	var rb_arm := _press(input, sim, rb, true)
	_check("A02 Arm on RB: RB arms and does not toggle the mode", rb_arm.pilot[FC.IN_ARM] == 1.0
		and rb_arm.pilot[FC.IN_MODE] == mode_before and input.bindings().mode_button == "")
	sim.free()

	_reset_input()
	var plain := _input_with(Profile.defaults("gamepad", "mode2"), 1, {name = "Synthetic gamepad", known = true})
	_check("A02 default pad: LB arms, RB changes the mode, Start pauses", plain.bindings().arm_button == "LB"
		and plain.bindings().mode_button == "RB" and plain.pause_button() == int(JOY_BUTTON_START))
	var start_aux := Profile.defaults("gamepad", "mode2")
	start_aux.actions["pause"] = {"type": "key", "physical_keycode": KEY_P}
	start_aux.aux = {"arm": {"type": "button", "button": int(JOY_BUTTON_START), "mode": "level"}}
	var owned := _input_with(start_aux, 1, {name = "Synthetic gamepad", known = true})
	_check("A02 Arm AUX on Start with Pause remapped: Start is no controller Pause", owned.pause_button() == -1)
	var switch_lb := Profile.defaults("gamepad", "mode2")
	switch_lb.aux = {"flight_mode": {"type": "switch", "buttons": [lb, int(JOY_BUTTON_X)], "invert": false}}
	_check("A02 a switch group member (LB) is reserved even in its inactive position",
		_input_with(switch_lb, 1, {name = "Synthetic gamepad", known = true}).bindings().arm_button == "")


## A02 (follow-up): the scene pauses only on the active pad's effective Pause button.
func _start_ownership() -> void:
	_reset_input()
	var registry := FakeRegistry.new()
	registry.devices[7] = _pad(7)
	registry.devices[7].connected = true
	registry.flight = 7
	var profile := Profile.defaults("gamepad", "mode2")
	profile.actions["pause"] = {"type": "button", "button": int(JOY_BUTTON_Y)}
	profile.actions["camera_cycle"] = {"type": "unbound"} # Y moves from the camera to Pause
	var resolve := func(_id: int) -> Dictionary: return profile.duplicate(true)
	var confirm := func(id: int, expected: int, generation: int) -> bool: return id == expected and generation == 1
	var activity := _activity(registry, resolve, confirm)
	root.add_child(activity)
	activity.set_physics_process(false)
	activity.handle_action("resume")
	activity._physics_process(DT)
	for button: int in [int(JOY_BUTTON_START), int(JOY_BUTTON_Y)]:
		var event := InputEventJoypadButton.new()
		event.device = 7
		event.button_index = button as JoyButton
		event.pressed = true
		activity._unhandled_input(event)
		if button == int(JOY_BUTTON_START):
			_check("A02 Start does not pause when the profile moves Pause to Y", not activity.session.paused)
		else:
			_check("A02 the remapped Pause button (Y) pauses", activity.session.paused and activity.hud.menu_visible)
	_free(activity)


## Arms a 20 m research air start through the real activity with a radio whose arm AUX is `binding`.
func _armed_air_activity(binding: Dictionary) -> Node3D:
	_reset_input()
	axes = {0: 0.0, 1: 0.0, 2: -1.0, 3: 0.0}
	var registry := FakeRegistry.new()
	registry.devices[8] = {id = 8, connected = true, name = "Synthetic radio", guid = "authority-radio", known = false, kind = "radio"}
	registry.flight = 8
	var profile := Profile.defaults("radio", "radio_custom")
	profile.aux = {"arm": binding}
	var resolve := func(_id: int) -> Dictionary: return profile.duplicate(true)
	var activity := _activity(registry, resolve, Callable())
	root.add_child(activity)
	activity.set_physics_process(false)
	var options: Dictionary = activity._session_options()
	options.start = "air"
	options.altitude_m = 20.0
	activity.session.prepare(activity.field, options)
	activity.input.radio.on_motion(8, 2, -1.0)
	activity.handle_action("resume")
	activity._physics_process(DT)
	activity.input.radio.on_button(8, 20, false)
	activity._physics_process(DT)
	buttons[20] = true
	activity.input.radio.on_button(8, 20, true)
	activity._physics_process(DT)
	return activity


## A03: an ordinary hold keeps an arm switch held ON (no silent motor cut); a switch moved OFF during the hold, or
## one whose position cannot be read (an edge toggle), is disclosed in the menu and disarms on resume.
func _hold_continuity() -> void:
	var level := {"type": "button", "button": 20, "mode": "level"}
	var activity := _armed_air_activity(level)
	_check("A03 setup: the arm switch arms the air start", activity.session.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED)
	activity._open_menu("Flight paused")
	activity._physics_process(DT)
	_check("A03 a held switch: the menu offers a powered resume without a disarm note",
		activity.session.paused and not Activity.RESUME_DISARMS_TEXT in activity.hud.menu_reason.text, activity.hud.menu_reason.text)
	activity.handle_action("resume")
	for i in 3:
		activity._physics_process(DT)
	var tape: PackedFloat64Array = activity.session.tape()
	_check("A03 resuming with the switch still ON keeps the motors armed and records ON",
		activity.session.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED and activity._last_input.pilot[FC.IN_ARM] == 1.0
		and tape[tape.size() - FC.INPUT_SIZE + FC.IN_ARM] == 1.0)
	buttons[20] = false
	activity.input.radio.on_button(8, 20, false)
	activity._physics_process(DT)
	_check("A03 after the resume the switch OFF disarms (its own command)", activity.session.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_DISARMED)
	buttons[20] = true
	activity.input.radio.on_button(8, 20, true)
	activity._physics_process(DT)
	_check("A03 and ON arms again: the channel speaks normally", activity.session.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED)
	activity._open_menu("Flight paused")
	activity._physics_process(DT)
	buttons[20] = false
	activity._physics_process(DT)
	buttons[20] = true # OFF then ON again while paused: no stale authority, no queued edge
	activity._physics_process(DT)
	_check("A03 a switch moved during the hold is disclosed before resuming", Activity.RESUME_DISARMS_TEXT in activity.hud.menu_reason.text,
		activity.hud.menu_reason.text)
	activity.handle_action("resume")
	activity._physics_process(DT)
	_check("A03 that resume disarms (the switch needs fresh OFF evidence)", activity.session.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_DISARMED)
	_free(activity)

	activity = _armed_air_activity({"type": "button", "button": 20, "mode": "toggle_edge"})
	var edge_armed: bool = activity.session.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED
	activity._open_menu("Flight paused")
	_check("A03 an edge-toggle arm switch cannot be held: the menu says resuming disarms", not edge_armed
		or Activity.RESUME_DISARMS_TEXT in activity.hud.menu_reason.text, activity.hud.menu_reason.text)
	_free(activity)

	_reset_input()
	var registry := FakeRegistry.new()
	var keyboard := _activity(registry, Callable(), Callable())
	root.add_child(keyboard)
	keyboard.set_physics_process(false)
	var options: Dictionary = keyboard._session_options()
	options.start = "air"
	options.altitude_m = 20.0
	keyboard.session.prepare(keyboard.field, options)
	keyboard.handle_action("resume")
	keyboard._physics_process(DT)
	keys.arm = true
	keyboard._physics_process(DT)
	keys.arm = false
	keyboard._open_menu("Flight paused")
	keyboard._physics_process(DT)
	keyboard.handle_action("resume")
	keyboard._physics_process(DT)
	_check("A03 keyboard control: the arm toggle survives the same hold without a note",
		keyboard.session.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED)
	keyboard.input.invalidate_for_focus()
	keyboard._hold("Paused: the window lost focus.")
	_check("A03 focus loss while armed is disclosed as a disarming resume", Activity.RESUME_DISARMS_TEXT in keyboard.hud.menu_reason.text)
	_free(keyboard)


## A18: the help names the active controls, not a static Mode 2 / LB / RB / Landing gear list.
func _help() -> void:
	var hud := Hud.new()
	root.add_child(hud)
	var keyboard: String = "\n".join(hud.controls_help_lines({source = "keyboard"}))
	_check("A18 keyboard help: Mode 2 keys, E and M", "(Mode 2)" in keyboard and "Arm or disarm: E." in keyboard
		and "M." in keyboard and not "LB" in keyboard)
	_reset_input()
	var mode1 := _input_with(Profile.defaults("gamepad", "mode1"), 1, {name = "Synthetic gamepad", known = true})
	var pad: String = "\n".join(hud.controls_help_lines(mode1.bindings()))
	_check("A18 Mode 1 pad help: throttle on the right stick, pitch on the left, LB and RB", "Throttle: right stick up/down" in pad
		and "Pitch: left stick up/down" in pad and "LB" in pad and "RB" in pad, pad)
	var aux := Profile.defaults("radio", "radio_custom")
	aux.aux = {"arm": {"type": "button", "button": 20, "mode": "level"},
		"flight_mode": {"type": "switch", "buttons": [21, 22], "invert": false}}
	var radio := _input_with(aux, 1, {name = "Synthetic radio", kind = "radio"})
	var radio_help: String = "\n".join(hud.controls_help_lines(radio.bindings()))
	_check("A18 explicit AUX help names the Arm and Flight mode switches, not E, M or Landing gear",
		"the Arm switch" in radio_help and "the Flight mode switch" in radio_help and not "Landing gear" in radio_help
		and not "Arm or disarm: E" in radio_help and "(radio)" in radio_help, radio_help)
	var legacy := Profile.defaults("radio", "radio_custom")
	legacy.aux = {"gear": {"type": "button", "button": 20, "mode": "level"}}
	var legacy_help: String = "\n".join(hud.controls_help_lines(_input_with(legacy, 1, {name = "Synthetic radio", kind = "radio"}).bindings()))
	_check("A18 a legacy Landing gear arm switch is named as such", "Landing gear" in legacy_help, legacy_help)
	hud.set_controls_help(mode1.bindings())
	_check("A18 the shown help follows the active bindings", "Throttle: right stick up/down" in hud.help.text)
	_free(hud)


## A19: a matching pad arriving or leaving changes the selected pad's connection generation. The quad re-resolves the
## source and holds behind the menu with the reason; it never accepts an unready tick from a stale verifier.
func _connection_generation() -> void:
	_reset_input()
	var original := _pad(7, "pad-family", "pad-a")
	var duplicate := _pad(8, "pad-family", "pad-b")
	var other := _pad(9, "other-family", "pad-c")
	observations = [original]
	var service := Service.new()
	var prefix := "user://mr_authority_duplicate_%d" % OS.get_process_id()
	service.store = Service.Store.new(prefix + ".profiles", prefix + ".legacy")
	service.enumerate_devices = func() -> Array: return observations.duplicate(true)
	service.allow_automatic_selection = func() -> bool: return false
	root.add_child(service)
	service.set_process(false)
	var registry = service.registry
	registry.select_device("flight", 7)
	var confirm := func(id: int, expected: int, generation: int) -> bool:
		return id == expected and registry.selected_device_id("flight") == id 			and registry.connection_generation(id) == generation and bool(registry.device_for_id(id).get("connected", false))
	var activity := _activity(registry, Callable(service, "profile_for_device"), confirm)
	root.add_child(activity)
	activity.set_physics_process(false)
	activity.handle_action("resume")
	activity._physics_process(DT)
	keys.arm = true
	activity._physics_process(DT)
	keys.arm = false
	activity._physics_process(DT)
	_check("A19 setup: the selected pad is ready and armed", activity.session.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED)
	var source_generation: int = activity.input.source_generation
	observations = [original, other]
	service._connection_changed(9, true)
	activity._joy_connection_changed(9, true)
	await process_frame
	await process_frame
	activity._physics_process(DT)
	_check("A19 a different-family pad leaves the flight armed and running", not activity.session.paused
		and activity.input.source_generation == source_generation and activity.session.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED)
	observations = [original, other, duplicate]
	service._connection_changed(8, true)
	var tick: int = activity.session.sim.tick
	keys.arm = true # a held E on the same tick must not toggle: the guard's hold sample does not integrate
	activity._physics_process(DT) # before the deferred sync: the tick guard must catch the new generation
	keys.arm = false
	_check("A19 the guard's hold sample queues no arm toggle", not activity.input._arm_latch)
	_check("A19 a matching pad arriving holds the flight with the reason before any unready tick",
		activity.session.paused and activity.hud.menu_visible and activity.session.sim.tick == tick
		and Activity.RECONNECTED_TEXT in activity.hud.menu_reason.text, activity.hud.menu_reason.text)
	_check("A19 the source is re-resolved with a current verifier", activity.input.source_generation > source_generation
		and activity._controller_generation == registry.connection_generation(7) and activity.input.radio.can_confirm_gamepad_poll())
	_check("A19 the hold says resuming disarms", Activity.RESUME_DISARMS_TEXT in activity.hud.menu_reason.text)
	activity.handle_action("resume")
	activity._physics_process(DT)
	_check("A19 resuming is ready (no stale verifier) and disarmed, not faulted", bool(activity._last_input.ready)
		and activity.session.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_DISARMED and activity.session.fault_reason.is_empty())
	observations = [original, other]
	service._connection_changed(8, false)
	activity._joy_connection_changed(8, false)
	await process_frame
	await process_frame
	_check("A19 the duplicate leaving is also a re-resolved, held source with a current verifier", activity.session.paused
		and activity._controller_generation == registry.connection_generation(7) and activity.input.radio.can_confirm_gamepad_poll())
	_free(activity)
	service.free()


## A04/A05: the direct route resolves profiles through the managed controller service (current store, not the legacy
## calibration file) and gives the selected UI pad the menu's navigation; the real AppRoot route does the same.
func _direct_route() -> void:
	_reset_input()
	var app := DirectApp.new()
	var dir := "user://mr_authority_direct_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(dir)
	app.preferences_path = dir + "/settings.cfg"
	root.add_child(app)
	UiInput.isolate_joypads()
	var activity: Node3D = Activity.new()
	activity.enable_world = false
	activity.enable_audio = false
	activity.departure_managed = true
	activity.race_track = ""
	app.add_child(activity)
	var service: Node = activity._controller_service
	_check("A04 the direct route owns a controller service with the launcher's store", service != null
		and activity._owns_controller_service and str(service.store.path) == dir + "/settings.cfg.controllers",
		str(service.store.get("path")) if service != null else "none")
	_check("A04 profiles resolve through that service", activity.controller_profile_for.is_valid()
		and activity.controller_registry == service.registry)
	# A synthetic pad on that service: the UI role installs the menu navigation on that device only.
	service.enumerate_devices = func() -> Array: return [_pad(7)]
	service.refresh()
	service.registry.select_device("ui", 7)
	var events: PackedStringArray = UiInput.joypad_ui_events()
	var device_only := not events.is_empty()
	for event: String in events:
		device_only = device_only and event.ends_with("[device 7]")
	_check("A05 the selected UI pad gets Accept/Back/navigation on its device only", device_only
		and UiInput.selected_gamepad_id() == 7, str(events))
	service.registry.select_device("ui", -1)
	_check("A05 a keyboard UI selection removes the pad's menu mapping", UiInput.joypad_ui_events().is_empty())
	_free(app)
	_check("A05 leaving the direct route removes its menu mapping", UiInput.joypad_ui_events().is_empty())

	var real := AppRoot.new()
	real.user_args = PackedStringArray(["--multirotor=openrc-fpv5-x1"])
	root.add_child(real)
	await process_frame
	var quad: Node = real.ground_vehicle
	_check("A04 the real direct route uses the managed service and the current store (not the legacy file)", quad != null
		and quad._owns_controller_service and quad.controller_profile_for.is_valid()
		and str(quad._controller_service.store.path) == Store.DEFAULT_PATH)
	_free(real)
	UiInput.isolate_joypads()

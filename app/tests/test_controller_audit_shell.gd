extends SceneTree

const Shell := preload("res://app_root.gd")
const Main := preload("res://main.gd")
const Session := preload("res://sim/flight_session.gd")
const Registry := preload("res://input/controller_registry.gd")
const Profile := preload("res://input/controller_profile.gd")
const Screen := preload("res://ui/screen.gd")

var checks := 0
var failures := 0

class RoutingShell extends Shell:
	func _ready() -> void: pass

class ObservedFlight extends Main:
	var received: Array[String] = []
	func controller_action(action: String) -> bool:
		received.append(action)
		return true

class FixtureService extends Node:
	var registry := Registry.new()
	var profile := Profile.defaults("radio", "radio_custom")
	var ui_profile := Profile.defaults()
	func profile_for_device(id: int) -> Dictionary: return (ui_profile if id == 8 else profile).duplicate(true)

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func button(pressed: bool) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = 7
	event.button_index = 20
	event.pressed = pressed
	return event

func motion(value: float, device := 7) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = 9
	event.axis_value = value
	return event

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var shell := RoutingShell.new()
	var service := FixtureService.new()
	service.registry.update_devices([{id = 7, known = false, name = "Synthetic radio"}])
	service.registry.select_device("flight", 7)
	service.registry.select_device("ui", -1)
	service.profile.actions = {pause = {type = "button", button = 20}}
	var session := Session.new()
	session.physics_enabled = false
	session.input_enabled = false
	session.setup()
	var flight := ObservedFlight.new()
	flight.session = session
	shell.controllers = service
	shell.flight = flight
	root.add_child(shell)
	shell._input(button(false))
	shell._input(button(true))
	check("radio Pause reaches flight with keyboard menus", flight.received.count("pause") == 1)
	var pause := Screen.new()
	shell.screens.push("pause", pause, null, false)
	shell._input(button(false))
	shell.screens.pop(false, false)
	pause.free()
	shell._input(button(true))
	check("Pause release is observed while menus have no joypad owner", flight.received.count("pause") == 2)
	shell._input(button(false))
	# Menu and flight contexts may intentionally share a source.
	service.registry.select_device("ui", 7)
	service.profile.actions = {
		navigate_down = {type = "axis", axis = 9, sign = 1, threshold = 0.65},
		camera_cycle = {type = "axis", axis = 9, sign = 1, threshold = 0.65}}
	pause = Screen.new()
	shell.screens.push("pause", pause, null, false)
	shell._input(motion(0.0))
	shell._input(motion(0.8))
	shell.screens.pop(false, false)
	pause.free()
	for sequence in 100:
		shell._input(motion(0.80 + float(sequence % 3) * 0.01))
	check("100 held menu-axis samples cannot become a flight action", flight.received.count("camera_cycle") == 0)
	shell._input(motion(NAN))
	shell._input(motion(0.0, 99))
	shell._input(motion(0.81))
	check("nonfinite and foreign samples do not release a held source", flight.received.count("camera_cycle") == 0)
	shell._input(motion(0.0))
	shell._input(motion(0.8))
	check("matching OFF and fresh ON activate the flight action", flight.received.count("camera_cycle") == 1)
	# Opening setup must not forget a held generic action, even without a menu alias.
	service.profile.actions.erase("navigate_down")
	shell._clear_controller_actions(false)
	shell._input(motion(0.81))
	check("unchanged setup routing preserves generic held history", flight.received.count("camera_cycle") == 1)
	shell._clear_controller_actions()
	shell._input(motion(0.82))
	check("focus recovery requires genuine OFF", flight.received.count("camera_cycle") == 1)
	shell._input(motion(0.0))
	shell._input(motion(0.8))
	check("focus recovery re-arms after matching OFF", flight.received.count("camera_cycle") == 2)
	service.registry.update_devices([{id = 7, known = false, name = "Synthetic radio"},
		{id = 8, known = true, name = "Menu pad"}, {id = 9, known = false, name = "Other radio"}])
	service.registry.select_device("flight", 9)
	shell._clear_controller_actions(false)
	shell._input(motion(0.8, 9))
	check("new selected device cannot inherit an active generic source", flight.received.count("camera_cycle") == 2)
	shell._input(motion(0.0, 9))
	shell._input(motion(0.8, 9))
	check("new selected device re-arms on its own OFF", flight.received.count("camera_cycle") == 3)
	service.registry.disconnect_device(9)
	service.registry.update_devices([{id = 7, known = false, name = "Synthetic radio"},
		{id = 8, known = true, name = "Menu pad"}, {id = 9, known = false, name = "Other radio"}])
	service.registry.select_device("flight", 9)
	shell._input(motion(0.81, 9))
	check("same-ID reconnect changes generic activation identity", flight.received.count("camera_cycle") == 3)
	service.registry.select_device("flight", 7)
	service.profile.actions = {throttle_cut = {type = "axis", axis = 9, sign = 1, threshold = 0.65}}
	shell._input(motion(0.0))
	shell._input(motion(0.8))
	check("selected flight source activates throttle cut", session.controller_cut_held)
	pause = Screen.new()
	shell.screens.push("pause", pause, null, false)
	# No cut-source event occurs while paused; an unrelated release sees the menu.
	shell._input(button(false))
	check("menu releases actual cut while retaining its activation", not session.controller_cut_held)
	shell.screens.pop(false, false)
	pause.free()
	shell._input(button(false))
	check("unrelated event after resume cannot restore held cut", not session.controller_cut_held)
	shell._input(motion(0.81))
	check("cut jitter after resume waits for OFF", not session.controller_cut_held)
	shell._input(motion(0.0))
	shell._input(motion(0.8))
	check("cut works after a fresh OFF and ON", session.controller_cut_held)
	service.registry.select_device("ui", 8)
	pause = Screen.new()
	shell.screens.push("pause", pause, null, false)
	var pad_cut := InputEventJoypadButton.new()
	pad_cut.device = 8
	pad_cut.button_index = JOY_BUTTON_LEFT_SHOULDER
	pad_cut.pressed = true
	shell._input(pad_cut)
	shell.screens.pop(false, false)
	pause.free()
	shell._input(motion(0.0))
	check("menu device cannot cut the selected flight controller", not session.controller_cut_held)
	shell._clear_controller_actions()
	service.profile.actions.throttle_cut = {type = "button", button = 20}
	shell._input(button(false))
	shell._input(button(true))
	check("remap after focus loss re-arms using the new source", session.controller_cut_held)
	service.profile = {}
	check("unavailable profile cannot inherit gamepad action defaults", shell._controller_bindings(7).camera_cycle.type == "unbound")
	service.profile = {kind = "radio", configured = false}
	check("unconfigured placeholder cannot inherit gamepad actions", shell._controller_bindings(7).throttle_cut.type == "unbound")
	shell.flight = null
	shell.free()
	flight.free()
	session.free()
	service.free()
	print("controller audit shell: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

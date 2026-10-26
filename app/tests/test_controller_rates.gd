# D6-GP: airplane rate selection through effective bindings, persisted overrides and the real shell router.
# Synthetic devices establish software behavior only; no controller hardware qualification is implied.
extends SceneTree

const Shell := preload("res://app_root.gd")
const Main := preload("res://main.gd")
const Session := preload("res://sim/flight_session.gd")
const Registry := preload("res://input/controller_registry.gd")
const Profile := preload("res://input/controller_profile.gd")
const Actions := preload("res://input/controller_actions.gd")
const Store := preload("res://input/controller_profile_store.gd")
const Screen := preload("res://ui/screen.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const STORE_PATH := "user://controller_rates_regression.cfg"

var checks := 0
var failures := 0

class RoutingShell extends Shell:
	var controls_opened := 0
	var restarts := 0
	func _ready() -> void: pass
	func open_controls(_from: Control = null) -> void: controls_opened += 1
	func open_pause() -> void: pass
	func restart_flight() -> void: restarts += 1

class FixtureService extends Node:
	var registry := Registry.new()
	var profile := Profile.defaults()
	func profile_for_device(_id: int) -> Dictionary: return profile.duplicate(true)

func check(label: String, passed: bool, detail := "") -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label, " ", detail)

func near(left: float, right: float) -> bool:
	return absf(left - right) < 1e-12

func button(index: int, pressed := true, device := 7) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = index
	event.pressed = pressed
	return event

func motion(value: float, device := 7) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = 9
	event.axis_value = value
	return event

func clean_store() -> void:
	for suffix in ["", ".tmp", ".rollback", ".legacy"]:
		var path: String = STORE_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_bindings()
	_test_persistence()
	_test_routing_and_shaping()
	print("controller rates: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func _test_bindings() -> void:
	var profile := Profile.defaults()
	var before := profile.duplicate(true)
	var bindings := Actions.effective_bindings(profile, Actions.AIRPLANE_CAPABILITIES)
	check("airplane gamepad gets left-stick rate toggle", bindings.rates_toggle == {type = "button", button = JOY_BUTTON_LEFT_STICK})
	check("automatic rate assignment leaves saved profile untouched", profile == before)
	check("menu L3 still calibrates without toggling airplane rates", Actions.resolve_event(button(JOY_BUTTON_LEFT_STICK), bindings, 7, "menu") == PackedStringArray(["calibrate"]))
	check("flight L3 resolves only the rate toggle", Actions.resolve_event(button(JOY_BUTTON_LEFT_STICK), bindings, 7, "flight") == PackedStringArray(["rates_toggle"]))
	check("aircraft without rates gets no automatic rate assignment", Actions.effective_bindings(profile, {}).rates_toggle.type == "unbound")
	bindings = Actions.effective_bindings(profile, Actions.HELICOPTER_CAPABILITIES)
	check("helicopter keeps L3 trainer and no airplane rates", bindings.helicopter_trainer.button == JOY_BUTTON_LEFT_STICK and bindings.rates_toggle.type == "unbound")
	profile.actions.rates_toggle = {type = "button", button = 25}
	check("saved rate remap replaces L3", Actions.effective_bindings(profile).rates_toggle.button == 25)
	profile.actions.rates_toggle = {type = "unbound"}
	check("saved Clear suppresses automatic rate assignment", Actions.effective_bindings(profile).rates_toggle.type == "unbound")
	profile.actions = {lights_cycle = {type = "button", button = JOY_BUTTON_LEFT_STICK}}
	check("an explicit flight action owns L3 before automatic rates", Actions.validate_profile_bindings(profile).ok and Actions.effective_bindings(profile).rates_toggle.type == "unbound")
	profile.actions = {}
	profile.aux.smoke = {type = "button", button = JOY_BUTTON_LEFT_STICK, mode = "level"}
	check("AUX ownership prevents automatic rate collision", Actions.validate_profile_bindings(profile).ok and Actions.effective_bindings(profile).rates_toggle.type == "unbound")
	profile.actions.rates_toggle = {type = "button", button = JOY_BUTTON_LEFT_STICK}
	check("explicit rates cannot share an AUX button", not Actions.validate_profile_bindings(profile).ok)
	var joystick := Profile.defaults("joystick", "radio_custom")
	check("unknown joystick gets no inferred rate button", Actions.effective_bindings(joystick).rates_toggle.type == "unbound")
	joystick.actions.rates_toggle = {type = "button", button = 25}
	check("joystick accepts an explicit rate button", Actions.validate_profile_bindings(joystick).ok)
	joystick.actions.rates_toggle = {type = "axis", axis = 9, sign = 1, threshold = 0.65}
	check("joystick accepts an unused axis for the toggle", Actions.validate_profile_bindings(joystick).ok)
	joystick.actions.rates_toggle.axis = joystick.roll.axis
	check("rate toggle cannot claim a primary flight axis", not Actions.validate_profile_bindings(joystick).ok)

func _test_persistence() -> void:
	clean_store()
	var profile := Profile.defaults()
	profile.actions["rates_toggle"] = {"type": "button", "button": 25}
	var store := Store.new(STORE_PATH, STORE_PATH + ".legacy")
	var saved := store.save_profile(profile)
	check("rate remap saves through the controller store", saved.ok, str(saved.get("error", "")))
	var loaded := Store.new(STORE_PATH, STORE_PATH + ".legacy").load_all()
	check("rate remap survives a new store instance", loaded.ok and loaded.profiles.size() == 1 and Actions.effective_bindings(loaded.profiles[0]).rates_toggle.button == 25)
	profile.actions["rates_toggle"] = {"type": "unbound"}
	saved = store.save_profile(profile)
	check("explicit Clear saves through the controller store", saved.ok, str(saved.get("error", "")))
	loaded = Store.new(STORE_PATH, STORE_PATH + ".legacy").load_all()
	check("saved Clear remains unbound after reload", loaded.ok and loaded.profiles.size() == 1 and Actions.effective_bindings(loaded.profiles[0]).rates_toggle.type == "unbound")
	clean_store()

func _test_routing_and_shaping() -> void:
	var shell := RoutingShell.new()
	var service := FixtureService.new()
	service.registry.update_devices([{id = 7, known = true, name = "Synthetic Xbox"}, {id = 8, known = true, name = "Other controller"}])
	service.registry.select_device("flight", 7)
	service.registry.select_device("ui", 7)
	var session := Session.new()
	session.physics_enabled = false
	session.input_enabled = false
	session.external_controller_selection = true
	session.setup()
	session.rate_profile = "sport"
	session.radio.connect_device(7, {known = true, name = "Synthetic Xbox"}, service.profile)
	var flight := Main.new()
	flight.session = session
	shell.flight = flight
	shell.controllers = service
	root.add_child(shell)
	shell.set_process(false)
	check("actual airplane advertises available rates", flight.controller_capabilities().rates)
	var state_before: PackedFloat64Array = session.sim.state.duplicate()
	var aux_before: PackedFloat64Array = session.sim.aux.duplicate()
	shell._input(button(JOY_BUTTON_LEFT_STICK, true, 8))
	check("foreign controller cannot change rates", session.rate_profile == "sport")
	shell._input(button(JOY_BUTTON_LEFT_STICK))
	check("shell L3 reaches real Main and selects Normal", session.rate_profile == "normal" and flight._note == flight.tr("Rates: normal"))
	shell._input(button(JOY_BUTTON_LEFT_STICK))
	check("held L3 cannot toggle repeatedly", session.rate_profile == "normal")
	shell._input(button(JOY_BUTTON_LEFT_STICK, false))
	shell._input(button(JOY_BUTTON_LEFT_STICK))
	check("release and repress restores Sport", session.rate_profile == "sport")
	check("rate action does not directly mutate body or actuators", session.sim.state == state_before and session.sim.aux == aux_before)
	shell._input(button(JOY_BUTTON_LEFT_STICK, false))
	var menu := Screen.new()
	check("real screen stack enters menu context", shell.screens.push("home", menu, null, false))
	shell._input(button(JOY_BUTTON_LEFT_STICK))
	check("menu L3 opens controls without changing rates", shell.controls_opened == 1 and session.rate_profile == "sport")
	shell.screens.pop(false, false)
	menu.free()
	shell._input(button(JOY_BUTTON_LEFT_STICK))
	check("held menu L3 cannot become a flight toggle", session.rate_profile == "sport")
	shell._input(button(JOY_BUTTON_LEFT_STICK, false))
	shell._input(button(JOY_BUTTON_LEFT_STICK))
	check("new L3 press works after the menu transition", session.rate_profile == "normal")
	shell._input(button(JOY_BUTTON_LEFT_STICK, false))

	service.profile = Profile.defaults("joystick", "radio_custom")
	service.profile.actions.rates_toggle = {type = "button", button = 25}
	session.radio.connect_device(7, {known = false, name = "Configured joystick"}, service.profile)
	session.rate_profile = "sport"
	shell._clear_controller_actions()
	shell._input(button(JOY_BUTTON_LEFT_STICK))
	check("joystick has no inferred L3 toggle in the real router", session.rate_profile == "sport")
	shell._input(button(25))
	check("explicit joystick button switches to Normal", session.rate_profile == "normal")
	shell._input(button(25, false))
	service.profile.actions.rates_toggle = {type = "axis", axis = 9, sign = 1, threshold = 0.65}
	shell._clear_controller_actions()
	for value in [0.66, 0.64, 0.66]:
		shell._input(motion(value))
	check("axis activation and jitter create one rate switch", session.rate_profile == "sport")
	shell._input(motion(0.4))
	check("axis release does not toggle rates", session.rate_profile == "sport")
	shell._input(motion(0.7))
	check("axis crossing rearms after returning toward OFF", session.rate_profile == "normal")
	shell._input(motion(-0.8))
	check("opposite axis direction does not toggle", session.rate_profile == "normal")
	# The flight joystick owns this switch even when another gamepad navigates menus.
	shell._input(motion(0.0))
	service.registry.select_device("ui", 8)
	var axis_menu := Screen.new()
	check("separate menu controller enters a real pause screen", shell.screens.push("pause", axis_menu, null, false))
	shell._input(motion(0.7))
	check("activating a flight rate axis inside a menu does not change rates", session.rate_profile == "normal")
	# Opening controller setup clears ordinary actions while retaining rate-switch evidence.
	shell._clear_controller_actions(false)
	var nested_menu := Screen.new()
	check("controller settings can nest above the pause screen", shell.screens.push("controls", nested_menu, null, false))
	shell.screens.pop(false, false)
	nested_menu.free()
	shell.screens.pop(false, false)
	axis_menu.free()
	shell._input(motion(0.71))
	check("axis held through nested menu close cannot queue a rate switch", session.rate_profile == "normal")
	shell._input(motion(0.4))
	shell._input(motion(0.7))
	check("menu-held rate axis works after OFF then ON", session.rate_profile == "sport")
	shell._input(motion(0.0))
	service.registry.select_device("ui", 7)

	# Two-position hardware can jump directly between extremes without a centre sample.
	service.profile.actions["restart_flight"] = {"type": "axis", "axis": 9, "sign": -1, "threshold": 0.65}
	check("opposite directions of an unused axis can select rates and restart", Actions.validate_profile_bindings(service.profile).ok)
	shell._clear_controller_actions()
	session.rate_profile = "sport"
	shell._input(motion(0.8))
	check("positive axis direction selects Normal before shared-axis restart", session.rate_profile == "normal")
	shell._input(motion(-0.8))
	check("direct negative transition restarts without toggling rates", shell.restarts == 1 and session.rate_profile == "normal")
	shell._input(motion(0.8))
	check("restart direction releases the rate latch without a centre sample", session.rate_profile == "sport")
	shell._input(motion(-0.8))
	check("rate direction also releases the restart latch", shell.restarts == 2 and session.rate_profile == "sport")
	shell._input(motion(0.0))
	service.profile.actions.erase("restart_flight")
	service.profile.actions["throttle_cut"] = {"type": "axis", "axis": 9, "sign": -1, "threshold": 0.65}
	check("opposite axis directions can select rates and hold throttle cut", Actions.validate_profile_bindings(service.profile).ok)
	shell._clear_controller_actions()
	session.rate_profile = "sport"
	shell._input(motion(-0.8))
	check("negative axis direction holds throttle cut without changing rates", session.controller_cut_held and session.rate_profile == "sport")
	shell._input(motion(0.8))
	check("rate selection releases an opposite-direction throttle cut", not session.controller_cut_held and session.rate_profile == "normal")
	shell._input(motion(-0.8))
	check("throttle cut can rearm directly from the rate direction", session.controller_cut_held and session.rate_profile == "normal")
	shell._input(motion(0.8))
	check("second rate selection releases throttle cut and restores Sport", not session.controller_cut_held and session.rate_profile == "sport")
	shell._input(motion(0.0))
	service.profile.actions.erase("throttle_cut")
	session.rate_profile = "normal"

	# Raw joysticks remain linear through calibration; aircraft expo belongs to the session.
	session.trims = {roll = 0.1, pitch = -0.07, yaw = 0.03}
	session.radio.on_motion(7, int(session.radio.profile.roll.axis), 0.5)
	session.commands = {roll = session.radio._stick("roll"), pitch = -0.5, yaw = 0.4, throttle = 0.63}
	check("calibrated joystick half stick remains linear", near(session.commands.roll, 0.5))
	var normal: Dictionary = session.flown_commands()
	var rates: Dictionary = session.aircraft.model.controls.rates.normal
	var half_expo: float = 0.5 - 0.375 * float(rates.aileron_expo)
	check("joystick Normal applies aircraft expo once then adds trim", near(normal.roll, half_expo * float(rates.aileron) + 0.1))
	flight.controller_action("rates_toggle")
	var sport: Dictionary = session.flown_commands()
	check("joystick Sport keeps full roll travel with aircraft expo", session.rate_profile == "sport" and near(sport.roll, half_expo + 0.1))
	check("Sport and Normal preserve pitch yaw and throttle", sport.pitch == normal.pitch and sport.yaw == normal.yaw and sport.throttle == 0.63)
	check("rate switch preserves pilot input and trim", session.commands.roll == 0.5 and session.trims == {roll = 0.1, pitch = -0.07, yaw = 0.03})

	var pad := Profile.defaults()
	pad.roll.deadzone = 0.0
	pad.roll.expo = 0.4
	session.radio.connect_device(7, {known = true, name = "Synthetic Xbox"}, pad)
	session.radio.on_motion(7, int(pad.roll.axis), 0.5)
	session.commands.roll = session.radio._stick("roll")
	check("gamepad supplies its own conditioned half stick", near(session.commands.roll, 0.35))
	check("Sport never applies aircraft expo a second time to gamepad", near(session.flown_commands().roll, 0.45))
	flight.controller_action("rates_toggle")
	check("gamepad Normal scales conditioned travel without second expo", session.rate_profile == "normal" and near(session.flown_commands().roll, 0.35 * float(rates.aileron) + 0.1))
	session.rate_profile = "full"
	check("Full still advertises a usable low-rate switch", flight.controller_capabilities().rates)
	flight.controller_action("rates_toggle")
	check("Full switches down to Normal", session.rate_profile == "normal")
	flight.controller_action("rates_toggle")
	check("Normal restores selected Full high position", session.rate_profile == "full")

	session.rate_profile = "sport"
	session.radio.connect_device(7, {known = false, name = "Synthetic transmitter"}, Profile.defaults("radio", "radio_custom"))
	var radio_commands: Dictionary = session.flown_commands()
	check("transmitter rate shaping bypasses simulator profiles", not session.rate_profile_available() and near(radio_commands.roll, float(session.commands.roll) + 0.1))
	flight.controller_action("rates_toggle")
	check("transmitter refuses toggle and explains ownership", session.rate_profile == "sport" and flight._note == flight.tr("The radio sets its own rates."))
	session.radio.disconnect_device()
	session.external_driver_enabled = true
	check("external driver cannot select simulator rates", not session.toggle_rate_profile() and session.rate_profile == "sport" and not flight.controller_capabilities().rates)
	session.external_driver_enabled = false
	check("keyboard regains rate selection after external driver", session.rate_profile_available())
	var no_rates := Session.new()
	no_rates.physics_enabled = false
	no_rates.input_enabled = false
	no_rates.setup(Catalog.entry("turbo-lumber-evolution").data, "turbo-lumber-evolution")
	flight.session = no_rates
	check("aircraft without rates advertises no rate capability", not flight.controller_capabilities().rates and not no_rates.toggle_rate_profile())
	flight.controller_action("rates_toggle")
	check("unsupported aircraft explains the refused action", flight._note == flight.tr("This aircraft has no rate profile."))
	shell.flight = null
	shell.controllers = null
	shell.free()
	flight.free()
	session.free()
	no_rates.free()
	service.free()

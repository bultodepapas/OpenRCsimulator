extends SceneTree
const Shell := preload("res://app_root.gd")
const Registry := preload("res://input/controller_registry.gd")
const Profile := preload("res://input/controller_profile.gd")
const Actions := preload("res://input/controller_actions.gd")
var failures := 0
var checks := 0

class FakeSession extends Node:
	var calibration: Variant = null
	var cut := false
	func set_controller_cut(held: bool) -> void: cut = held

class FakeFlight extends Node:
	var session: Node
	var capabilities := {gear = true, smoke = false, flaps = false}
	var received: Array[String] = []
	func controller_capabilities() -> Dictionary: return capabilities.duplicate()
	func controller_action(action: String) -> bool:
		received.append(action)
		return false

class FakeService extends Node:
	var registry = Registry.new()
	var profile: Dictionary = Profile.defaults()
	func profile_for_device(_id: int) -> Dictionary: return profile.duplicate(true)

func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	var shell := Shell.new()
	var service := FakeService.new()
	service.registry.update_devices([{"id": 1, "known": true, "name": "Synthetic Xbox"}])
	service.registry.select_device("flight", 1)
	service.profile.actions = {"throttle_cut": {"type": "key", "keycode": KEY_K}}
	var flight := FakeFlight.new()
	var session := FakeSession.new()
	flight.session = session
	shell.flight = flight
	shell.controllers = service
	var key := InputEventKey.new()
	key.keycode = KEY_K
	key.pressed = true
	shell._input(key)
	check("logical-only key holds cut", session.cut)
	key = InputEventKey.new()
	key.keycode = KEY_L
	key.pressed = true
	shell._input(key)
	check("another logical-only key cannot release held cut", session.cut)
	key.keycode = KEY_K
	key.pressed = false
	shell._input(key)
	check("matching release clears hold and empty source", not session.cut and shell._controller_action_edges.is_empty())
	for id in range(2, 100):
		var other := InputEventJoypadButton.new()
		other.device = id
		other.button_index = JOY_BUTTON_A
		other.pressed = true
		shell._input(other)
	check("foreign devices cannot accumulate empty action state", shell._controller_action_edges.is_empty())
	shell._controller_action_edges = {"key:75": PackedStringArray(["throttle_cut"]), "1:button:6": PackedStringArray(["pause"])}
	session.cut = true
	shell._release_controller_holds()
	check("menu transition releases flight holds", not session.cut and not shell._controller_action_edges.has("key:75"))
	check("menu transition retains pause edge against held repeat", shell._controller_action_edges["1:button:6"] == PackedStringArray(["pause"]))
	flight.received.clear()
	var equipment := InputEventJoypadButton.new()
	equipment.device = 1
	equipment.button_index = JOY_BUTTON_B
	equipment.pressed = true
	shell._input(equipment)
	shell._input(equipment)
	check("automatic jet gear dispatches once per press through the shell", flight.received == ["gear_toggle"])
	equipment.pressed = false
	shell._input(equipment)
	flight.capabilities = {gear = false, smoke = true}
	equipment.pressed = true
	shell._input(equipment)
	check("changing to fixed gear removes the automatic action", flight.received == ["gear_toggle"])
	equipment.button_index = JOY_BUTTON_RIGHT_SHOULDER
	shell._input(equipment)
	check("installed smoke picks up the standard shoulder button", flight.received == ["gear_toggle", "smoke_toggle"])
	equipment.pressed = false
	shell._input(equipment)
	flight.capabilities = {}
	equipment.pressed = true
	shell._input(equipment)
	check("unsupported activities never inherit automatic equipment", flight.received == ["gear_toggle", "smoke_toggle"])
	flight.capabilities = {gear = true, smoke = false}
	flight.received.clear()
	equipment.button_index = JOY_BUTTON_B
	shell._controller_action_edges[Actions.event_source(equipment)] = PackedStringArray(["back"])
	shell._input(equipment)
	check("held menu Back cannot turn into a gear toggle after resume", flight.received.is_empty())
	equipment.pressed = false
	shell._input(equipment)
	equipment.pressed = true
	shell._input(equipment)
	check("gear works after releasing and pressing Back again in flight", flight.received == ["gear_toggle"])
	shell.free()
	flight.free()
	session.free()
	service.free()
	print("controller routing audit: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

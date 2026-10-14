extends SceneTree

const Ground := preload("res://vehicles/ground/ground_scene.gd")

class FakeRegistry extends RefCounted:
	signal selection_changed(role: String, id: int)
	var selected := {"flight": -1, "ui": -1}
	var devices := {}

	func selected_device_id(role: String) -> int:
		return int(selected.get(role, -1))

	func device_for_id(device_id: int) -> Dictionary:
		return devices.get(device_id, {}).duplicate(true)

	func select(role: String, device_id: int) -> void:
		selected[role] = device_id
		selection_changed.emit(role, device_id)

var checks := 0
var failures := 0
var polled_ids: Array[int] = []
var axis_values := {}

func check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label)

func gamepad(device_id: int, generation := 1) -> Dictionary:
	return {"id": device_id, "connected": true, "known": true, "kind": "gamepad", "generation": generation}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var registry := FakeRegistry.new()
	registry.devices[7] = gamepad(7)
	registry.devices[8] = gamepad(8)
	registry.devices[9] = {"id": 9, "connected": true, "known": false, "kind": "radio", "generation": 1}
	registry.devices[10] = {"id": 10, "connected": true, "known": false, "kind": "joystick", "generation": 1}
	registry.devices[11] = {"id": 11, "connected": true, "known": false, "kind": "gamepad", "generation": 1}
	var ground := Ground.new()
	ground.controller_registry = registry
	ground.joy_axis_reader = func(device_id: int, axis: JoyAxis) -> float:
		polled_ids.append(device_id)
		return float(axis_values.get(axis, 0.0))
	ground.joy_button_reader = func(device_id: int, _button: JoyButton) -> bool:
		polled_ids.append(device_id)
		return false
	ground._connect_controller_registry()
	registry.select("ui", 8)
	registry.select("flight", 7)
	check("selection captures only the flight gamepad", ground._controller_device_id == 7 and not ground._controller_requires_selection)
	axis_values[JOY_AXIS_LEFT_X] = 0.5
	axis_values[JOY_AXIS_TRIGGER_RIGHT] = 0.7
	axis_values[JOY_AXIS_TRIGGER_LEFT] = 0.3
	polled_ids.clear()
	var axes: Dictionary = ground._registry_joy_controls()
	check("ground sampler reads RT/LT and left-stick values", axes.right_trigger == 0.7 and axes.left_trigger == 0.3 and axes.left_x == 0.5)
	check("selected flight handle alone is polled", not polled_ids.is_empty() and polled_ids.all(func(id: int) -> bool: return id == 7))
	check("selected UI handle can send Start", ground._accept_controller_button(8))
	check("selected flight handle can send Start", ground._accept_controller_button(7))
	registry.select("ui", 11)
	check("selected connected UI gamepad can send Start", ground._accept_controller_button(11))
	registry.select("ui", 8)
	axis_values[JOY_AXIS_LEFT_X] = 0.0
	axis_values[JOY_AXIS_TRIGGER_RIGHT] = 0.0
	axis_values[JOY_AXIS_TRIGGER_LEFT] = 0.0
	var neutral_controls: Dictionary = ground._read_controls()
	check("ground drive sampler requires neutral gamepad sample", neutral_controls.source == "gamepad" and neutral_controls.throttle == 0.0)
	axis_values[JOY_AXIS_LEFT_X] = 0.5
	axis_values[JOY_AXIS_TRIGGER_RIGHT] = 0.7
	var drive_controls: Dictionary = ground._read_controls()
	check("RT accelerates and left stick steers using ground profile", is_equal_approx(drive_controls.throttle, 0.7) and is_equal_approx(drive_controls.steering, (0.5 - 0.12) / (1.0 - 0.12)))
	axis_values[JOY_AXIS_TRIGGER_LEFT] = 0.3
	var brake_controls: Dictionary = ground._read_controls()
	check("LT brakes and overrides RT throttle", brake_controls.brake == 0.3 and brake_controls.throttle == 0.0)

	registry.select("flight", 9)
	var radio_controls: Dictionary = ground._registry_joy_controls()
	check("radio selection blocks driving", ground._controller_requires_selection and not radio_controls.get("connected", true))
	check("radio Start is filtered", not ground._accept_controller_button(9))
	registry.select("flight", 10)
	var unknown_controls: Dictionary = ground._registry_joy_controls()
	check("unknown joystick cannot drive", ground._controller_requires_selection and not unknown_controls.get("connected", true))

	registry.devices[7] = gamepad(7)
	registry.select("flight", 7)
	check("valid explicit gamepad selection clears block", not ground._controller_requires_selection and ground._controller_device_id == 7)
	registry.devices[7].connected = false
	registry.select("flight", -1)
	var blocked := ground._read_controls()
	check("loss pauses input and forbids keyboard fallback", ground._controller_requires_selection and blocked.source == "none")
	check("explicit keyboard choice clears a prior loss", ground.apply_controller_selection(-1) and not ground._controller_requires_selection)
	check("keyboard transition starts neutral", ground._read_controls().source == "none")
	check("keyboard is available after explicit neutral transition", ground._read_controls().source == "keyboard")

	registry.devices[7] = gamepad(7, 1)
	registry.select("flight", 7)
	registry.devices[7] = gamepad(7, 2)
	var generation_controls: Dictionary = ground._registry_joy_controls()
	check("generation change pauses and requires reselection", not generation_controls.get("connected", true) and ground._controller_requires_selection)
	check("same handle can be explicitly reselected after generation change", ground.apply_controller_selection(7) and not ground._controller_requires_selection)
	registry.select("ui", 8)
	check("selected UI device remains accepted for Start", ground._accept_controller_button(8))
	check("unselected handle is rejected for Start", not ground._accept_controller_button(99))

	ground.controller_registry = null
	check("legacy route keeps prior unrestricted Start handling", ground._accept_controller_button(99))
	ground.free()
	print("Ground controller integration: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)

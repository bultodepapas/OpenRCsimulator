extends SceneTree
const Actions := preload("res://input/controller_actions.gd")
var checks := 0
var failures := 0

func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	var bindings := Actions.default_bindings()
	bindings.camera_cycle = {"type": "key", "physical_keycode": KEY_K}
	bindings.view_reset = {"type": "key", "physical_keycode": KEY_K, "ctrl": true}
	check("modifier chords do not collide with plain keys", Actions.validate(bindings).ok)
	var event := InputEventKey.new()
	event.pressed = true
	event.physical_keycode = KEY_Q
	event.keycode = KEY_A
	var physical := {"type": "key", "physical_keycode": KEY_A, "keycode": KEY_A}
	check("physical identity cannot alias a different layout key", not Actions.matches_binding(physical, event, 1))
	bindings.camera_cycle = {"type": "key", "physical_keycode": KEY_A}
	bindings.view_reset = {"type": "key", "keycode": KEY_A}
	check("matching physical/logical key forms are conflicting", not Actions.validate(bindings).ok)
	for malformed in [
		{"type": "button", "button": 5.5},
		{"type": "button", "button": "5"},
		{"type": "key", "physical_keycode": -1},
		{"type": "key", "physical_keycode": KEY_K, "ctrl": "yes"},
		{"type": "axis", "axis": 5, "sign": 1, "direction": -1},
		{"type": "axis", "axis": 5.5, "sign": 1},
	]:
		bindings = Actions.default_bindings()
		bindings.camera_cycle = malformed
		check("malformed action rejected: " + str(malformed), not Actions.validate(bindings).ok)
	var motion := InputEventJoypadMotion.new()
	motion.axis = 4
	motion.axis_value = INF
	check("nonfinite motion cannot be captured", Actions.binding_from_event(motion).is_empty())
	var chord := {"type": "key", "physical_keycode": KEY_K, "ctrl": true, "shift": true}
	check("prompt describes actual modifiers", Actions.binding_text(chord).contains("Ctrl") and Actions.binding_text(chord).contains("Shift"))
	print("controller binding audit: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

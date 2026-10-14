extends SceneTree
const UiInput := preload("res://ui/ui_input.gd")
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
	InputMap.load_from_project_settings()
	UiInput.set_gamepad(15, {"accept": physical})
	event.physical_keycode = KEY_A
	event.keycode = KEY_Q
	check("native GUI uses the same physical binding after layout change", InputMap.event_is_action(event, "ui_accept", true))
	event.physical_keycode = KEY_Q
	event.keycode = KEY_A
	check("native GUI rejects logical aliases from a different physical key", not InputMap.event_is_action(event, "ui_accept", true))
	UiInput.isolate_joypads()
	var existing := InputEventKey.new()
	existing.physical_keycode = KEY_Z
	InputMap.action_add_event("ui_accept", existing)
	UiInput.set_gamepad(15, {"accept": {"type": "key", "physical_keycode": KEY_Z}})
	UiInput.isolate_joypads()
	check("remap cleanup preserves a matching pre-existing keyboard recovery binding", InputMap.action_has_event("ui_accept", existing))
	InputMap.load_from_project_settings()
	print("controller binding audit: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

extends SceneTree

const RcInput := preload("res://input/rc_input.gd")
const Profile := preload("res://input/controller_profile.gd")

func _initialize() -> void:
	var rows: Array[Dictionary] = []
	for held in [false, true]:
		var radio := RcInput.new()
		radio.connect_device(7, {known = true, kind = "gamepad", name = "audit gamepad"}, Profile.defaults("gamepad", "mode2"))
		radio.confirmed_gamepad_connection = func(_id: int) -> bool: return true
		var counts := {axes = 0, buttons = 0}
		var reader := func(_id: int, _axis: int) -> float:
			counts.axes += 1
			return 0.0
		var buttons := func(_id: int, _button: int) -> bool:
			counts.buttons += 1
			return false
		for i in 240:
			radio.poll(reader, 1.0 / 240.0, buttons, not held)
		rows.append({kind = "held/menu" if held else "active", polls = 240,
			axes = counts.axes, buttons = counts.buttons, armed = radio.armed,
			input_error = radio.input_error, profile_error = radio.profile_error,
			throttle = radio.throttle_position()})
	var reproduced: bool = rows.all(func(row: Dictionary) -> bool:
		return row.axes == 2400 and row.buttons == 30720 and row.armed and row.input_error.is_empty() and row.profile_error.is_empty())
	print("INPUT_JSON ", JSON.stringify({rows = rows, scope = "callback counts, not device latency or timing"}))
	print("INPUT_PROBE_COMPLETE expected_observation=", reproduced)
	quit(0 if reproduced else 1)

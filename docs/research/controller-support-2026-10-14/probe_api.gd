## Read-only engine API probe; no project imports, preferences or hardware claims.
## Run with the pinned native engine, without --path app. See README.md.
extends SceneTree


func _init() -> void:
	print("engine: ", Engine.get_version_info().string)
	print("os: ", OS.get_name())
	for method in ["get_joy_info", "get_joy_guid", "is_joy_known", "add_joy_mapping",
			"has_joy_vibration", "start_joy_vibration", "stop_joy_vibration",
			"has_joy_light", "set_joy_light", "has_joy_motion_sensors",
			"get_joy_gyroscope", "set_joy_motion_sensors_enabled",
			"start_joy_motion_sensors_calibration", "get_joy_path"]:
		print("Input.%s: %s" % [method, Input.has_method(method)])
	print("JoyAxis.SDL_MAX=%d JoyAxis.MAX=%d JoyButton.MAX=%d" % [
		JOY_AXIS_SDL_MAX, JOY_AXIS_MAX, JOY_BUTTON_MAX])
	print("ignore_joypad_on_unfocused_application: ",
		Input.ignore_joypad_on_unfocused_application)
	InputMap.load_from_project_settings()
	for action in ["ui_accept", "ui_cancel", "ui_select", "ui_left", "ui_right", "ui_up", "ui_down"]:
		var events: Array[String] = []
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton:
				events.append("button %d" % event.button_index)
			elif event is InputEventJoypadMotion:
				events.append("axis %d %+.0f" % [event.axis, event.axis_value])
		print("%s joypad bindings: %s" % [action, str(events)])
	print("scope: API/default mappings only; headless device discovery is not hardware validation")
	quit()

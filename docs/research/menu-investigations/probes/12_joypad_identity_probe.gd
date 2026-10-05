# Investigation 12 probe (2026-10-05): joypad identity API and default ui_* joypad events in the pinned Godot.
# Run from the repo root, WITHOUT --path app (it lives outside app/ on purpose, so app/test.sh never parses it):
#   .tools/Godot_v4.7.2-stable_linux.x86_64 --headless --script docs/research/menu-investigations/probes/12_joypad_identity_probe.gd
#   SDL_GAMECONTROLLER_IGNORE_DEVICES=0x1209/0x4F54 .tools/Godot_v4.7.2-stable_linux.x86_64 --headless --script <same>
# No hardware: it never claims what a real radio reports. It only reads the engine API and the app's key format.
extends SceneTree


func _init() -> void:
	print("engine: ", Engine.get_version_info().string)
	# 1. Which identity methods exist on Input.
	var names := {}
	for m in ClassDB.class_get_method_list("Input"):
		names[m.name] = true
	for want in ["get_joy_guid", "get_joy_name", "get_joy_info", "is_joy_known", "should_ignore_device",
			"get_connected_joypads", "add_joy_mapping", "remove_joy_mapping", "get_joy_axis",
			"set_ignore_joypad_on_unfocused_application", "has_joy_light", "has_joy_motion_sensors",
			"get_joy_serial", "get_joy_vendor_id", "get_joy_product_id", "get_joy_path"]:
		print("Input.%s: %s" % [want, names.has(want)])
	print("signal joy_connection_changed: ", ClassDB.class_has_signal("Input", "joy_connection_changed"))
	print("JoyAxis.SDL_MAX=%d JoyAxis.MAX=%d JoyButton.SDL_MAX=%d JoyButton.MAX=%d" % [JOY_AXIS_SDL_MAX, JOY_AXIS_MAX, JOY_BUTTON_SDL_MAX, JOY_BUTTON_MAX])
	print("setting ignore_joypad_on_unfocused_application = ",
		ProjectSettings.get_setting("input_devices/joypads/ignore_joypad_on_unfocused_application", "<missing>"))
	print("connected joypads (this VM has none): ", Input.get_connected_joypads())

	# 2. Default ui_* actions that react to joypad events. In --script mode the InputMap starts with key events only;
	#    a project run loads input/* from ProjectSettings (app/project.godot has no [input] overrides), so do the same.
	print("ui_left at _init: ", InputMap.action_get_events("ui_left").size(), " events")
	InputMap.load_from_project_settings()
	for action in InputMap.get_actions():
		if not String(action).begins_with("ui_"):
			continue
		var joy := []
		for e in InputMap.action_get_events(action):
			if e is InputEventJoypadButton:
				joy.append("button %d" % e.button_index)
			elif e is InputEventJoypadMotion:
				joy.append("axis %d %+.0f" % [e.axis, e.axis_value])
		if not joy.is_empty():
			print("%s <- %s (deadzone %.2f)" % [action, ", ".join(joy), InputMap.action_get_deadzone(action)])

	# 3. Does the env var reach should_ignore_device? EdgeTX/OpenTX joystick VID:PID = 1209:4F54 (pid.codes).
	print("env SDL_GAMECONTROLLER_IGNORE_DEVICES = '%s'" % OS.get_environment("SDL_GAMECONTROLLER_IGNORE_DEVICES"))
	print("should_ignore_device(0x1209, 0x4F54) = ", Input.should_ignore_device(0x1209, 0x4F54))
	print("should_ignore_device(0x0912, 0x544F) [byte-swapped] = ", Input.should_ignore_device(0x0912, 0x544F))

	# 4. The app's calibration key with get_joy_info() as the SDL driver fills it (vendor_id/product_id are
	#    decimal STRINGS from itos()). The GUID and name below are illustrative, not read from a radio.
	var RcInput = load(ProjectSettings.globalize_path("res://").path_join("app/input/rc_input.gd"))
	var info := { guid = "03000000091200000000544f00000000", name = "OpenTX RadioMaster Boxer Joystick",
		vendor_id = "4617", product_id = "20308" }
	print("key_for(string ids) = ", RcInput.key_for(0, info))
	for n in ["OpenTX RadioMaster Boxer Joystick", "RadioMaster Boxer Joystick", "Fatfish F16 Joystick", "iFlight Commando 8 Joystick", "HelloRadioSky V16 Joystick"]:
		print("looks_like_radio('%s') = %s" % [n, RcInput.looks_like_radio(n)])
	quit()

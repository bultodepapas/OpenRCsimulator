# A radio flies the airplane; it never navigates menus (MENU-PLAN §6, step UI-01b, research 02/12/15).
# Godot 4.7.2's built-in ui_left/right/up/down answer joypad axes 0/1 and D-pad buttons 11-14, and ui_select
# button 3: an EdgeTX radio (AETR) moved the focus with its elevator and aileron sticks. This removes every joypad
# event from every ui_* action, so keyboard and mouse navigate alone. The raw axes the flight reads
# (Input.get_joy_axis, InputEventJoypadMotion) are untouched. A gamepad navigating menus comes later, chosen
# explicitly (UI-12). SDL_GAMECONTROLLER_IGNORE_DEVICES is not an option: it hides the radio from the flight too.
extends RefCounted


## Erases joypad buttons and axes from all ui_* actions. Returns how many events were removed.
static func isolate_joypads() -> int:
	var removed := 0
	for action in InputMap.get_actions():
		if not String(action).begins_with("ui_"):
			continue
		for e in InputMap.action_get_events(action):
			if e is InputEventJoypadButton or e is InputEventJoypadMotion:
				InputMap.action_erase_event(action, e)
				removed += 1
	return removed


## Joypad events still bound to ui_* actions, as "action: event" lines (empty when isolated).
static func joypad_ui_events() -> PackedStringArray:
	var found := PackedStringArray()
	for action in InputMap.get_actions():
		if String(action).begins_with("ui_"):
			for e in InputMap.action_get_events(action):
				if e is InputEventJoypadButton or e is InputEventJoypadMotion:
					found.append("%s: %s" % [action, e.as_text()])
	return found

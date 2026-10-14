# UI-04b: the controls reference (ui/controls_reference.gd) matches the keys the code really handles. Reads the
# source of input/keyboard.gd (the stick keys) and main.gd's _unhandled_input (the shortcuts), so a key added or
# removed there without updating Help fails here.
# Run: godot --headless --path . --script res://tests/test_controls_reference.gd
extends SceneTree

const Reference := preload("res://ui/controls_reference.gd")

var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


## KEY_* names used in `text`, as Key values.
func _keys_in(text: String) -> Array:
	var keys := []
	for m in RegEx.create_from_string("\\bKEY_[A-Z0-9_]+\\b").search_all(text):
		var value := _key_value(m.get_string())
		if value >= 0 and not value in keys:
			keys.append(value)
	return keys


func _key_value(key_name: String) -> int:
	# KEY_KP_ENTER -> "KP ENTER" -> the engine's own name lookup (case-insensitive), e.g. KEY_KP_ENTER.
	var code := OS.find_keycode_from_string(key_name.trim_prefix("KEY_").replace("_", " "))
	return code if code != KEY_NONE else -1


static func _function_body(source: String, header: String) -> String:
	var start := source.find(header)
	if start < 0:
		return ""
	var next := source.find("\nfunc ", start + header.length())
	return source.substr(start, (next if next >= 0 else source.length()) - start)


func _initialize() -> void:
	var stick_keys := _keys_in(_function_body(FileAccess.get_file_as_string("res://input/keyboard.gd"), "static func read_raw"))
	var shortcut_keys := _keys_in(_function_body(FileAccess.get_file_as_string("res://main.gd"), "func _unhandled_input"))
	var helicopter_shortcut_keys := _keys_in(_function_body(FileAccess.get_file_as_string("res://helicopter_main.gd"), "func _unhandled_input"))
	_check("found the stick keys in keyboard.gd (%d)" % stick_keys.size(), stick_keys.size() == 8)
	_check("found the shortcuts in main.gd (%d)" % shortcut_keys.size(), shortcut_keys.size() >= 10)
	_check("found the helicopter shortcuts (%d)" % helicopter_shortcut_keys.size(), helicopter_shortcut_keys.size() >= 10)
	var handled := stick_keys + shortcut_keys
	# Shortcuts implemented through Input Map must also have their default physical keys listed.
	var shortcut_source := _function_body(FileAccess.get_file_as_string("res://main.gd"), "func _unhandled_input")
	for action_match in RegEx.create_from_string("is_action_pressed\\(\"([^\"]+)\"\\)").search_all(shortcut_source):
		for event: InputEvent in InputMap.action_get_events(action_match.get_string(1)):
			if event is InputEventKey:
				var key: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
				if not key in handled:
					handled.append(key)
	var listed := Reference.all_keys()
	var missing := handled.filter(func(k: int) -> bool: return not k in listed).map(func(k: int) -> String: return OS.get_keycode_string(k))
	var stale := listed.filter(func(k: int) -> bool: return not k in handled).map(func(k: int) -> String: return OS.get_keycode_string(k))
	_check("every handled key is in the Help tables", missing.is_empty(), "missing: %s" % str(missing))
	_check("every key in the Help tables is handled", stale.is_empty(), "handled nowhere: %s" % str(stale))
	var rotorcraft_handled := stick_keys + helicopter_shortcut_keys
	var rotorcraft_listed := Reference.all_keys(Reference.ROTORCRAFT)
	var rotorcraft_missing := rotorcraft_handled.filter(func(k: int) -> bool: return not k in rotorcraft_listed).map(func(k: int) -> String: return OS.get_keycode_string(k))
	var rotorcraft_stale := rotorcraft_listed.filter(func(k: int) -> bool: return not k in rotorcraft_handled).map(func(k: int) -> String: return OS.get_keycode_string(k))
	_check("every helicopter handled key is in its Help table", rotorcraft_missing.is_empty(), "missing: %s" % str(rotorcraft_missing))
	_check("every helicopter Help key is handled", rotorcraft_stale.is_empty(), "handled nowhere: %s" % str(rotorcraft_stale))
	var rotorcraft_flight := Reference.flight_table(Reference.ROTORCRAFT)
	var rotorcraft_shortcuts := Reference.shortcut_table(Reference.ROTORCRAFT)
	var rotorcraft_first := Reference.first_flight_table(Reference.ROTORCRAFT)
	_check("helicopter W/S is labelled collective", rotorcraft_flight.any(func(row: Array) -> bool: return row[1] == "Collective" and KEY_W in row[0] and KEY_S in row[0]))
	_check("helicopter shortcuts explain idle-up, trainer and zero-drive", rotorcraft_shortcuts.any(func(row: Array) -> bool: return KEY_I in row[0] and "curves" in row[1])
		and rotorcraft_shortcuts.any(func(row: Array) -> bool: return KEY_G in row[0] and "Trainer" in row[1])
		and rotorcraft_shortcuts.any(func(row: Array) -> bool: return KEY_H in row[0] and "Zero-drive" in row[1]))
	_check("helicopter shortcuts omit airplane-only trim, smoke, fuel and reload keys",
		rotorcraft_shortcuts.all(func(row: Array) -> bool: return not (KEY_BRACKETLEFT in row[0] or KEY_H in row[0] and "smoke" in row[1].to_lower()
			or KEY_F5 in row[0] or KEY_F6 in row[0] or KEY_F7 in row[0] or KEY_F8 in row[0] or KEY_F9 in row[0]))
		and rotorcraft_shortcuts.all(func(row: Array) -> bool: return not ("trim" in row[1].to_lower() or "fuel" in row[1].to_lower() or "smoke" in row[1].to_lower())))
	var first := []
	for row in Reference.FIRST_FLIGHT:
		first.append_array(row[0])
	_check("first-flight hint: at most 3 items, keys from the tables", Reference.FIRST_FLIGHT.size() <= 3
		and first.all(func(k: int) -> bool: return k in listed))
	_check("helicopter first-flight hint uses collective rather than throttle",
		rotorcraft_first.size() <= 3 and rotorcraft_first.any(func(row: Array) -> bool: return row[1] == "Collective" and KEY_W in row[0] and KEY_S in row[0])
		and rotorcraft_first.all(func(row: Array) -> bool: return row[1] != "Throttle"))
	print("all controls reference checks passed" if _failures == 0 else "%d failed" % _failures)
	quit(1 if _failures > 0 else 0)

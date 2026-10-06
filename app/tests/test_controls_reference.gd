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
	_check("found the stick keys in keyboard.gd (%d)" % stick_keys.size(), stick_keys.size() == 8)
	_check("found the shortcuts in main.gd (%d)" % shortcut_keys.size(), shortcut_keys.size() >= 10)
	var handled := stick_keys + shortcut_keys
	var listed := Reference.all_keys()
	var missing := handled.filter(func(k: int) -> bool: return not k in listed).map(func(k: int) -> String: return OS.get_keycode_string(k))
	var stale := listed.filter(func(k: int) -> bool: return not k in handled).map(func(k: int) -> String: return OS.get_keycode_string(k))
	_check("every handled key is in the Help tables", missing.is_empty(), "missing: %s" % str(missing))
	_check("every key in the Help tables is handled", stale.is_empty(), "handled nowhere: %s" % str(stale))
	var first := []
	for row in Reference.FIRST_FLIGHT:
		first.append_array(row[0])
	_check("first-flight hint: at most 3 items, keys from the tables", Reference.FIRST_FLIGHT.size() <= 3
		and first.all(func(k: int) -> bool: return k in listed))
	print("all controls reference checks passed" if _failures == 0 else "%d failed" % _failures)
	quit(1 if _failures > 0 else 0)

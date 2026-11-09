extends SceneTree

var differences: Array = []


func _record(path: Array, left: Variant, right: Variant, reason: String) -> void:
	differences.append({path = path.duplicate(), reason = reason,
		left_type = type_string(typeof(left)), right_type = type_string(typeof(right)),
		left_bytes = var_to_bytes(left).hex_encode(), right_bytes = var_to_bytes(right).hex_encode(),
		left_text = str(left), right_text = str(right)})


func _compare(left: Variant, right: Variant, path: Array) -> void:
	if var_to_bytes(left) == var_to_bytes(right):
		return
	if typeof(left) != typeof(right):
		_record(path, left, right, "type")
		return
	if left is Dictionary:
		var left_keys: Array = left.keys()
		var right_keys: Array = right.keys()
		if var_to_bytes(left_keys) != var_to_bytes(right_keys):
			_record(path + ["<keys>"], left_keys, right_keys, "typed key order or set")
		for key: Variant in left_keys:
			var match_key: Variant = null
			var found := false
			for other: Variant in right_keys:
				if var_to_bytes(key) == var_to_bytes(other):
					match_key = other
					found = true
					break
			if found:
				_compare(left[key], right[match_key], path + [str(key)])
			else:
				_record(path + [str(key)], left[key], null, "missing right key")
		for key: Variant in right_keys:
			var found := false
			for other: Variant in left_keys:
				if var_to_bytes(key) == var_to_bytes(other):
					found = true
					break
			if not found:
				_record(path + [str(key)], null, right[key], "missing left key")
		return
	if left is Array or typeof(left) in [TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY,
			TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY,
			TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY,
			TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY]:
		if left.size() != right.size():
			_record(path + ["<size>"], left.size(), right.size(), "size")
		for index: int in mini(left.size(), right.size()):
			_compare(left[index], right[index], path + [index])
		return
	_record(path, left, right, "typed value")


func _initialize() -> void:
	var out := OS.get_environment("OPENRC_AUDIT_COMPARISON")
	if out.is_empty() or FileAccess.file_exists(out):
		printerr("FAIL comparison output must be a fresh path")
		quit(1)
		return
	var left: Variant = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("OPENRC_AUDIT_LEFT")))
	var right: Variant = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("OPENRC_AUDIT_RIGHT")))
	if not left is Dictionary or not right is Dictionary or left.get("format") != right.get("format") \
			or left.get("engine") != right.get("engine") or left.get("os") != right.get("os") \
			or not left.get("cases") is Dictionary or not right.get("cases") is Dictionary \
			or left.cases.keys() != right.cases.keys():
		printerr("FAIL incomparable capture identity or case set")
		quit(1)
		return
	for name: String in left.cases:
		var a: Dictionary = left.cases[name]
		var b: Dictionary = right.cases[name]
		if a.frames.size() != 25 or b.frames.size() != 25:
			printerr("FAIL incomplete case ", name)
			quit(1)
			return
		_compare(bytes_to_var(a.configuration.hex_decode()), bytes_to_var(b.configuration.hex_decode()), [name, "configuration_fields"])
		for tick: int in 25:
			_compare(bytes_to_var(a.frames[tick].hex_decode()), bytes_to_var(b.frames[tick].hex_decode()), [name, tick])
	var file := FileAccess.open(out, FileAccess.WRITE)
	if file == null:
		printerr("FAIL comparison output unavailable")
		quit(1)
		return
	file.store_string(JSON.stringify({format = "ci-audit-typed-diff-v1", engine = left.engine,
		os = left.os, cases = left.cases.keys(), differences = differences}))
	file.close()
	print("CI_AUDIT_TYPED_DIFF cases=%d endpoints=%d differences=%d" % [left.cases.size(), left.cases.size() * 25, differences.size()])
	quit(0)

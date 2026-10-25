extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var before: Resource = ResourceLoader.load(args[0], "Resource", ResourceLoader.CACHE_MODE_IGNORE)
	var after: Resource = ResourceLoader.load(args[1], "Resource", ResourceLoader.CACHE_MODE_IGNORE)
	if before == null or after == null:
		quit(2)
		return
	var fields: Array = []
	var changed: Array[String] = []
	var geometry_unchanged := true
	var names: Array = Array(before.get_meta_list())
	for key: StringName in after.get_meta_list():
		if not names.has(key):
			names.append(key)
	for key: StringName in names:
		var old_value: Variant = before.get_meta(key, null)
		var new_value: Variant = after.get_meta(key, null)
		var old_bytes := var_to_bytes(old_value)
		var new_bytes := var_to_bytes(new_value)
		var equal := old_bytes == new_bytes
		if not equal:
			changed.append(String(key))
			if key != &"engine_hex" and key != &"sources":
				geometry_unchanged = false
		var row := {"field": String(key), "byte_exact": equal,
			"before_sha256": _sha(old_bytes), "after_sha256": _sha(new_bytes)}
		if typeof(old_value) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_DICTIONARY]:
			row["before"] = old_value
			row["after"] = new_value
		fields.append(row)
	var report := {"format": "openrc-gdu03-lake-metadata-comparison v1",
		"scope": "Existing owner-generator candidate compared with retained resource using complete var_to_bytes metadata payloads.",
		"changed_fields": changed, "geometry_and_input_metadata_byte_exact": geometry_unchanged,
		"fields": fields}
	print("GDU03_LAKE_METADATA_COMPARE ", JSON.stringify(report))
	var file := FileAccess.open(args[2], FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	quit(0 if geometry_unchanged else 1)


func _sha(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

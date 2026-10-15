## Frozen RCV-40 artifact and SHA validation oracle.
extends RefCounted

static func _reference_implementation_artifact(source_path: String) -> Dictionary:
	if FileAccess.file_exists(source_path):
		var source_sha256 := FileAccess.get_sha256(source_path)
		if _sha256_is_valid(source_sha256):
			return {"sha256": source_sha256, "kind": "gdscript_source"}
	var remap_path := source_path + ".remap"
	if not FileAccess.file_exists(remap_path):
		return {"sha256": "", "kind": ""}
	var remap := ConfigFile.new()
	if remap.load(remap_path) != OK:
		return {"sha256": "", "kind": ""}
	var target_value: Variant = remap.get_value("remap", "path", "")
	if typeof(target_value) != TYPE_STRING or not str(target_value).begins_with("res://"):
		return {"sha256": "", "kind": ""}
	var bytecode_path := str(target_value)
	if not FileAccess.file_exists(bytecode_path):
		return {"sha256": "", "kind": ""}
	var bytecode_sha256 := FileAccess.get_sha256(bytecode_path)
	if not _sha256_is_valid(bytecode_sha256):
		return {"sha256": "", "kind": ""}
	return {"sha256": bytecode_sha256, "kind": "gdscript_remapped_bytecode"}

static func _sha256_is_valid(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var digest := str(value)
	if digest.length() != 64 or digest.to_lower() != digest:
		return false
	for character in digest:
		if not str(character) in "0123456789abcdef":
			return false
	return true

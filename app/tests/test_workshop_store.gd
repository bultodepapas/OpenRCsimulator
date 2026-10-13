extends SceneTree

const Store = preload("res://workshop/store.gd")
const BASE_PATH: String = "res://data/aircraft/jensen_ugly_stik_60.json"

var _checks: int = 0
var _failures: int = 0
var _root: String = ""


func _initialize() -> void:
	_root = "user://workshop_store_test_%d_%d" % [int(Time.get_unix_time_from_system()), int(Time.get_ticks_usec())]
	_test_root_guard()
	var base_bytes: PackedByteArray = FileAccess.get_file_as_bytes(BASE_PATH)
	var recipe: Dictionary = _recipe()
	_check("base fixture read", not base_bytes.is_empty())
	var saved: Dictionary = Store.save_variant("Store test Stik", "jensen-das-ugly-stik-60", base_bytes, recipe, "", _root)
	_check("first variant save succeeds", bool(saved["ok"]), str(saved["errors"]))
	if not bool(saved["ok"]):
		_finish()
		return
	var first: Dictionary = saved["variant"]
	var id: String = str(first["id"])
	_check("generated ID is a lowercase UUID", id.length() == 36 and id[14] == "4")
	_check("revision starts at one", int(first["revision"]) == 1)
	_check("exact base bytes are returned", first["base_bytes"] == base_bytes)
	_check("base SHA-256 covers exact source bytes", str(first["base_sha256"]) == _sha256(base_bytes))
	_check("parsed base retains its aircraft identity", str(first["base"].get("id", "")) == "jensen-das-ugly-stik-60")
	_check("catalog descriptor is pinned with the exact source snapshot", typeof(first.get("workshop_descriptor", null)) == TYPE_DICTIONARY and str(first["workshop_descriptor"].get("base_sha256", "")) == _sha256(base_bytes))
	_check("variant list discovers the saved item", _contains_variant(Store.list_variants(_root), id))

	var renamed_recipe: Dictionary = _recipe()
	renamed_recipe["scale"] = 1.25
	renamed_recipe["name"] = "Renamed Stik"
	var renamed: Dictionary = Store.save_variant("Renamed Stik", "jensen-das-ugly-stik-60", base_bytes, renamed_recipe, id, _root)
	_check("same-base save creates a new revision", bool(renamed["ok"]), str(renamed["errors"]))
	if bool(renamed["ok"]):
		_check("revision increments monotonically", int(renamed["variant"]["revision"]) == 2)
		_check("rename changes display metadata", str(renamed["variant"]["name"]) == "Renamed Stik")
		_check("revision still pins original base bytes", renamed["variant"]["base_bytes"] == base_bytes)
		_check("later revisions retain the original Workshop descriptor", renamed["variant"].get("workshop_descriptor", {}) == first.get("workshop_descriptor", {}))
		_check("load returns latest saved revision", int(Store.load_variant(id, _root)["variant"]["revision"]) == 2)

	var edited_base: Dictionary = first["base"].duplicate(true)
	edited_base["description"] = str(edited_base["description"]) + " changed"
	var changed_base_bytes: PackedByteArray = (JSON.stringify(edited_base, "\t", true, true) + "\n").to_utf8_buffer()
	var changed_base_save: Dictionary = Store.save_variant("Renamed Stik", "jensen-das-ugly-stik-60", changed_base_bytes, renamed_recipe, id, _root)
	_check("an existing variant cannot replace its base snapshot", not bool(changed_base_save["ok"]) and _has_error(changed_base_save["errors"], "immutable"), str(changed_base_save["errors"]))
	_check("rejected base change leaves saved revision untouched", int(Store.load_variant(id, _root)["variant"]["revision"]) == 2)

	var bad_recipe: Dictionary = _recipe()
	bad_recipe["power_multiplier"] = INF
	var bad_recipe_save: Dictionary = Store.save_variant("Bad recipe", "jensen-das-ugly-stik-60", base_bytes, bad_recipe, "", _root)
	_check("non-finite recipe numbers are rejected", not bool(bad_recipe_save["ok"]) and _has_error(bad_recipe_save["errors"], "finite"), str(bad_recipe_save["errors"]))
	var malformed_base: Dictionary = Store.save_variant("Bad base", "jensen-das-ugly-stik-60", "{".to_utf8_buffer(), _recipe(), "", _root)
	_check("malformed base JSON is rejected", not bool(malformed_base["ok"]), str(malformed_base["errors"]))
	var wrong_schema_bytes: PackedByteArray = "{\"format\":\"other\",\"version\":1,\"id\":\"jensen-das-ugly-stik-60\"}".to_utf8_buffer()
	var wrong_schema: Dictionary = Store.save_variant("Wrong schema", "jensen-das-ugly-stik-60", wrong_schema_bytes, _recipe(), "", _root)
	_check("wrong aircraft schema is rejected", not bool(wrong_schema["ok"]) and _has_error(wrong_schema["errors"], "openrc-aircraft v2"), str(wrong_schema["errors"]))
	var bad_id_load: Dictionary = Store.load_variant("../escape", _root)
	_check("path-like variant IDs are rejected", not bool(bad_id_load["ok"]) and _has_error(bad_id_load["errors"], "UUID"), str(bad_id_load["errors"]))
	var bad_id_save: Dictionary = Store.save_variant("Bad ID", "jensen-das-ugly-stik-60", base_bytes, _recipe(), "../escape", _root)
	_check("path-like IDs cannot create files", not bool(bad_id_save["ok"]) and not FileAccess.file_exists(ProjectSettings.globalize_path(_root + "/../escape.json")))
	var unsafe_root: Array = Store.list_variants("user://../escape")
	_check("path traversal roots cannot enumerate or write outside user data", unsafe_root.is_empty())

	_test_manifest_recovery(id)
	_test_persisted_integrity(id)
	var deleted: Dictionary = Store.delete_variant(id, _root)
	_check("delete moves a valid item to local trash", bool(deleted["ok"]), str(deleted["errors"]))
	_check("trashed variant leaves the active library", Store.list_variants(_root).is_empty())
	var restored: Dictionary = Store.restore_variant(id, _root)
	_check("trashed item can be restored", bool(restored["ok"]), str(restored["errors"]))
	if bool(restored["ok"]):
		_check("restored item retains its latest revision", int(restored["variant"]["revision"]) == 2)
		_check("restored item retains exact base bytes", restored["variant"]["base_bytes"] == base_bytes)
	_finish()


func _test_root_guard() -> void:
	_check("unsafe resource roots are rejected", Store.list_variants("res://aircraft_variants").is_empty())
	var rejected: Dictionary = Store.save_variant("Unsafe root", "jensen-das-ugly-stik-60", PackedByteArray(), _recipe(), "", "res://data/aircraft")
	_check("store writes are limited to user data", not bool(rejected["ok"]) and not rejected["errors"].is_empty())


func _test_manifest_recovery(id: String) -> void:
	var manifest_path: String = ProjectSettings.globalize_path(_root + "/" + id + "/manifest.json")
	var backup_path: String = manifest_path + ".bak"
	_check("prior manifest is retained as a backup", FileAccess.file_exists(backup_path))
	if not FileAccess.file_exists(manifest_path) or not FileAccess.file_exists(backup_path):
		return
	var current_bytes: PackedByteArray = FileAccess.get_file_as_bytes(manifest_path)
	var move_error: Error = DirAccess.rename_absolute(manifest_path, manifest_path + ".interrupted")
	_check("simulate interrupted manifest commit", move_error == OK)
	if move_error != OK:
		return
	var recovered: Dictionary = Store.load_variant(id, _root)
	_check("missing current manifest recovers from backup", bool(recovered["ok"]) and bool(recovered["variant"].get("recovered_from_manifest_backup", false)), str(recovered["errors"]))
	_check("backup recovers the last committed revision", bool(recovered["ok"]) and int(recovered["variant"]["revision"]) == 1)
	var restore_error: Error = DirAccess.rename_absolute(manifest_path + ".interrupted", manifest_path)
	_check("restore interrupted-write fixture", restore_error == OK)


func _test_persisted_integrity(id: String) -> void:
	var record_path: String = ProjectSettings.globalize_path(_root + "/" + id + "/revisions/00000002.json")
	if not FileAccess.file_exists(record_path):
		_check("latest revision record exists for integrity fixture", false)
		return
	var original: PackedByteArray = FileAccess.get_file_as_bytes(record_path)
	var parser := JSON.new()
	var parse_error: Error = parser.parse(original.get_string_from_utf8())
	_check("integrity fixture parses", parse_error == OK and typeof(parser.data) == TYPE_DICTIONARY)
	if parse_error != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return
	var record: Dictionary = parser.data
	record["base_sha256"] = "0".repeat(64)
	var tampered: PackedByteArray = (JSON.stringify(record, "\t", true, true) + "\n").to_utf8_buffer()
	_check("tampered revision fixture writes", _write_file(record_path, tampered))
	var rejected_hash: Dictionary = Store.load_variant(id, _root)
	_check("base hash mismatch is rejected", not bool(rejected_hash["ok"]) and _has_error(rejected_hash["errors"], "SHA-256"), str(rejected_hash["errors"]))
	_check("corrupt hash removes item from the usable library", not _contains_variant(Store.list_variants(_root), id))
	_check("restore valid hash fixture", _write_file(record_path, original))
	var restored_hash: Dictionary = Store.load_variant(id, _root)
	_check("restored hash loads again", bool(restored_hash["ok"]), str(restored_hash["errors"]))
	var restored_record: Dictionary = JSON.parse_string(original.get_string_from_utf8())
	restored_record["version"] = 99
	var unknown_version: PackedByteArray = (JSON.stringify(restored_record, "\t", true, true) + "\n").to_utf8_buffer()
	_check("tampered schema fixture writes", _write_file(record_path, unknown_version))
	var rejected_version: Dictionary = Store.load_variant(id, _root)
	_check("unknown persisted schema version is rejected", not bool(rejected_version["ok"]) and _has_error(rejected_version["errors"], "version"), str(rejected_version["errors"]))
	_check("restore valid schema fixture", _write_file(record_path, original))
	var descriptor_tamper: Dictionary = JSON.parse_string(original.get_string_from_utf8())
	if typeof(descriptor_tamper.get("workshop_descriptor", null)) == TYPE_DICTIONARY:
		descriptor_tamper["workshop_descriptor"]["base_sha256"] = "0".repeat(64)
		var bad_descriptor: PackedByteArray = (JSON.stringify(descriptor_tamper, "\t", true, true) + "\n").to_utf8_buffer()
		_check("tampered descriptor fixture writes", _write_file(record_path, bad_descriptor))
		var rejected_descriptor: Dictionary = Store.load_variant(id, _root)
		_check("pinned descriptor integrity is validated on load", not bool(rejected_descriptor["ok"]) and _has_error(rejected_descriptor["errors"], "descriptor source SHA-256"), str(rejected_descriptor["errors"]))
		_check("restore valid descriptor fixture", _write_file(record_path, original))


func _recipe() -> Dictionary:
	return {
		"scale": 1.0,
		"mass_policy": "constant_wing_loading",
		"weight_multiplier": 1.0,
		"power_multiplier": 1.0,
		"control_multiplier": 1.0,
	}


func _contains_variant(variants: Array, id: String) -> bool:
	for variant: Dictionary in variants:
		if str(variant.get("id", "")) == id:
			return true
	return false


func _has_error(errors: PackedStringArray, needle: String) -> bool:
	for message: String in errors:
		if needle in message:
			return true
	return false


func _write_file(path: String, bytes: PackedByteArray) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.flush()
	var ok: bool = file.get_error() == OK
	file.close()
	return ok


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(bytes)
	return context.finish().hex_encode()


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _finish() -> void:
	_remove_tree(ProjectSettings.globalize_path(_root))
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _remove_tree(path: String) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var entry: String = directory.get_next()
		if entry.is_empty():
			break
		if entry == "." or entry == "..":
			continue
		var child: String = path.path_join(entry)
		if directory.current_is_dir():
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
	directory.list_dir_end()
	directory = null
	DirAccess.remove_absolute(path)

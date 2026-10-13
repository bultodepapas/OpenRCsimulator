extends SceneTree

const Catalog = preload("res://app_state/aircraft_catalog.gd")
const Descriptor = preload("res://workshop/descriptor.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_test_catalog_descriptors()
	_test_stale_binding()
	_test_unfamiliar_identity()
	_test_rejections()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_catalog_descriptors() -> void:
	var ids: PackedStringArray = Catalog.ids()
	_check("every current catalog aircraft is discovered", ids.size() == Catalog.ENTRIES.size() and not ids.is_empty(), str(ids))
	for id: String in ids:
		var entry: Dictionary = Catalog.entry(id)
		var base_bytes: PackedByteArray = FileAccess.get_file_as_bytes(str(entry.get("data", "")))
		var loaded: Dictionary = Descriptor.load_for(id, base_bytes)
		_check("catalog descriptor loads for " + id, bool(loaded["ok"]), str(loaded["errors"]))
		if not bool(loaded["ok"]):
			continue
		var descriptor: Dictionary = loaded["descriptor"]
		_check("exact source bytes are pinned for " + id, str(descriptor["base_sha256"]) == _sha256(base_bytes))
		_check("catalog identity and scale root are bound for " + id, descriptor["base_id"] == id and descriptor["presentation"]["visual_id"] == id and descriptor["presentation"]["scale_root"] == "airplane")
		_check("inventory bindings cover every source item for " + id, descriptor["inventory_bindings"].size() == JSON.parse_string(base_bytes.get_string_from_utf8())["inventory"].size())
		_check("descriptor names its generated source for " + id, str(descriptor["_generated_do_not_edit"]).contains("do not edit"))


func _test_stale_binding() -> void:
	var id: String = "jensen-das-ugly-stik-60"
	var entry: Dictionary = Catalog.entry(id)
	var base_bytes: PackedByteArray = FileAccess.get_file_as_bytes(str(entry["data"]))
	var loaded: Dictionary = Descriptor.load_for(id, base_bytes)
	if not bool(loaded["ok"]):
		_check("stale binding fixture descriptor loads", false, str(loaded["errors"]))
		return
	var changed_base: Dictionary = JSON.parse_string(base_bytes.get_string_from_utf8())
	changed_base["inventory"][0]["name"] = str(changed_base["inventory"][0]["name"]) + " renamed"
	var changed_bytes: PackedByteArray = (JSON.stringify(changed_base, "\t", true, true) + "\n").to_utf8_buffer()
	var stale_descriptor: Dictionary = loaded["descriptor"].duplicate(true)
	stale_descriptor["base_sha256"] = _sha256(changed_bytes)
	var rejected: Dictionary = Descriptor.validate(stale_descriptor, id, changed_bytes)
	_check("a matching source hash cannot hide a stale inventory name binding", not bool(rejected["ok"]) and _has_error(rejected["errors"], "stale"), str(rejected["errors"]))
	var byte_changed: PackedByteArray = base_bytes.duplicate()
	byte_changed[byte_changed.size() - 1] = 32 if byte_changed[byte_changed.size() - 1] != 32 else 10
	var hash_rejected: Dictionary = Descriptor.validate(loaded["descriptor"], id, byte_changed)
	_check("changed source bytes fail the pinned SHA-256", not bool(hash_rejected["ok"]) and _has_error(hash_rejected["errors"], "SHA-256"), str(hash_rejected["errors"]))


func _test_unfamiliar_identity() -> void:
	var source_id: String = "jensen-das-ugly-stik-60"
	var source_bytes: PackedByteArray = FileAccess.get_file_as_bytes(str(Catalog.entry(source_id)["data"]))
	var source_descriptor: Dictionary = Descriptor.load_for(source_id, source_bytes)["descriptor"]
	var unfamiliar_id: String = "synthetic-unfamiliar-airframe-20"
	var unfamiliar_base: Dictionary = JSON.parse_string(source_bytes.get_string_from_utf8())
	unfamiliar_base["id"] = unfamiliar_id
	var unfamiliar_bytes: PackedByteArray = (JSON.stringify(unfamiliar_base, "\t", true, true) + "\n").to_utf8_buffer()
	var unfamiliar_descriptor: Dictionary = source_descriptor.duplicate(true)
	unfamiliar_descriptor["base_id"] = unfamiliar_id
	unfamiliar_descriptor["base_sha256"] = _sha256(unfamiliar_bytes)
	unfamiliar_descriptor["presentation"]["visual_id"] = unfamiliar_id
	var accepted: Dictionary = Descriptor.validate(unfamiliar_descriptor, unfamiliar_id, unfamiliar_bytes)
	_check("unfamiliar data-only identity validates from its descriptor", bool(accepted["ok"]), str(accepted["errors"]))
	if bool(accepted["ok"]):
		_check("unfamiliar identity keeps the shared inventory module data", accepted["descriptor"]["modules"] == source_descriptor["modules"])


func _test_rejections() -> void:
	var id: String = "jensen-das-ugly-stik-60"
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(str(Catalog.entry(id)["data"]))
	var valid: Dictionary = Descriptor.load_for(id, bytes)
	if not bool(valid["ok"]):
		_check("rejection fixtures have a valid source descriptor", false, str(valid["errors"]))
		return
	var unknown_format: Dictionary = valid["descriptor"].duplicate(true)
	unknown_format["format"] = "openrc-aircraft-workshop v99"
	var version_result: Dictionary = Descriptor.validate(unknown_format, id, bytes)
	_check("unsupported descriptor version is rejected", not bool(version_result["ok"]) and _has_error(version_result["errors"], "format"), str(version_result["errors"]))
	var wrong_modules: Dictionary = valid["descriptor"].duplicate(true)
	wrong_modules["modules"].append("propulsion.unknown.v9")
	var module_result: Dictionary = Descriptor.validate(wrong_modules, id, bytes)
	_check("module assertions must match raw aircraft capabilities", not bool(module_result["ok"]) and _has_error(module_result["errors"], "module assertions"), str(module_result["errors"]))
	var extra_fields: Dictionary = valid["descriptor"].duplicate(true)
	extra_fields["wing_area"] = 0.464515
	var extra_result: Dictionary = Descriptor.validate(extra_fields, id, bytes)
	_check("descriptor cannot copy physical constants", not bool(extra_result["ok"]) and _has_error(extra_result["errors"], "unsupported fields"), str(extra_result["errors"]))
	var wrong_identity: Dictionary = Descriptor.validate(valid["descriptor"], "gp-extra-300s-60", bytes)
	_check("descriptor cannot bind another aircraft source", not bool(wrong_identity["ok"]))
	var unsafe_root: Dictionary = Descriptor.load_for(id, bytes, "res://data/../aircraft")
	_check("path traversal descriptor roots are rejected", not bool(unsafe_root["ok"]))


func _has_error(errors: PackedStringArray, needle: String) -> bool:
	for message: String in errors:
		if needle in message:
			return true
	return false


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

extends RefCounted
## Independently proved one-family overlay; legacy customization remains untouched.
const Models := preload("res://aircraft/model_overlay_registry.gd")
const Legacy := preload("res://render/aircraft_customization.gd")
const FAMILY := "moonrunner-x99"
const DIRECTORY := "res://data/aircraft_customization_overlays"
const PATH := DIRECTORY + "/" + FAMILY + ".json"
const BASE_PATH := "res://data/aircraft_customization.json"
const FORMAT := "openrc-aircraft-customization-registry"

static func describe(family: String) -> Dictionary:
	if family != FAMILY:
		return _failure("Unknown overlay customization family.")
	var model: Dictionary = Models.describe(family)
	if not model.get("ok", false):
		return model
	return describe_for_model(family, str(model.manifest_sha256))

static func describe_for_model(family: String, expected_model_hash: String) -> Dictionary:
	if family != FAMILY:
		return _failure("Unknown overlay customization family.")
	# Resolve independently on every use: the requested model hash is not proof.
	var model: Dictionary = Models.describe(family)
	if not model.get("ok", false):
		return model
	if expected_model_hash != str(model.manifest_sha256):
		return _failure("Overlay customization model hash does not match the verified model.")
	var directory := DirAccess.open(DIRECTORY)
	if directory == null:
		return _failure("Overlay customization directory is missing.")
	var files := directory.get_files()
	if files.size() != 1 or files[0] != FAMILY + ".json" or not directory.get_directories().is_empty():
		return _failure("Overlay customization directory contains missing or unregistered entries.")
	var base: Variant = JSON.parse_string(FileAccess.get_file_as_string(BASE_PATH))
	var overlay: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	var selected := _select(base, overlay)
	if not selected.get("ok", false):
		return selected
	var bindings: Dictionary = selected.bindings
	var checked: Dictionary = Legacy.validate_bindings(bindings, FAMILY, expected_model_hash)
	if not checked.get("ok", false):
		return checked
	return {"ok": true, "visual_family": FAMILY, "model_manifest_sha256": expected_model_hash,
		"bindings": bindings.duplicate(true), "slots_sha256": str(bindings.slots_sha256), "errors": []}

static func _select(base: Variant, overlay: Variant) -> Dictionary:
	if not _is_registry(base) or not _is_registry(overlay):
		return _failure("Customization registry is malformed.")
	var seen := {}
	for item: Variant in base.families:
		if not item is Dictionary or not item.get("visual_family") is String:
			return _failure("Base customization registry contains a malformed family.")
		var family: String = item.visual_family
		if family.is_empty() or seen.has(family) or family == FAMILY:
			return _failure("Overlay family collides with the base customization registry.")
		seen[family] = true
	if overlay.families.size() != 1 or not overlay.families[0] is Dictionary \
			or overlay.families[0].get("visual_family") != FAMILY:
		return _failure("Customization overlay must contain exactly the registered family.")
	return {"ok": true, "bindings": overlay.families[0]}

static func _is_registry(value: Variant) -> bool:
	return value is Dictionary and value.size() == 3 and value.has_all(["format", "version", "families"]) \
		and value.format == FORMAT and typeof(value.version) in [TYPE_INT, TYPE_FLOAT] \
		and value.version == 1 and value.families is Array

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "errors": PackedStringArray([message])}

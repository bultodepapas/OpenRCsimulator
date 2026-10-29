extends RefCounted
## Separately proved, closed registration for the new visual family.
const BaseRegistry := preload("res://aircraft/model_registry.gd")
const SourceProof := preload("res://aircraft/overlay_source_proof.gd")
const FAMILY := "moonrunner-x99"
const DIRECTORY := "res://data/aircraft_model_overlays"
const PATH := DIRECTORY + "/" + FAMILY + ".json"
const BASE_PATH := "res://data/aircraft_models/" + FAMILY + ".json"

static func describe(family: String) -> Dictionary:
	if family != FAMILY:
		return _failure("Unknown overlay model family.")
	if FileAccess.file_exists(BASE_PATH):
		return _failure("Overlay family collides with a base model manifest.")
	var directory := DirAccess.open(DIRECTORY)
	if directory == null:
		return _failure("Overlay model directory is missing.")
	var files := directory.get_files()
	var subdirectories := directory.get_directories()
	if files.size() != 1 or files[0] != FAMILY + ".json" or not subdirectories.is_empty():
		return _failure("Overlay model directory contains missing or unregistered entries.")
	var bytes := FileAccess.get_file_as_bytes(PATH)
	var value: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not value is Dictionary:
		return _failure("Overlay model manifest is malformed.")
	var checked: Dictionary = BaseRegistry.validate_manifest(value, FAMILY)
	if not checked.get("ok", false):
		return checked
	var proof: Dictionary = SourceProof.verify(checked.manifest)
	if not proof.get("ok", false):
		return proof
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	checked["manifest_sha256"] = hash.finish().hex_encode()
	return checked

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "errors": PackedStringArray([message])}

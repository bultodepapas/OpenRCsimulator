extends RefCounted
## Separately proved, closed registration for the new visual family.
const BaseRegistry := preload("res://aircraft/model_registry.gd")
const SourceProof := preload("res://aircraft/overlay_source_proof.gd")
const FAMILY := "moonrunner-x99" # Historical public constant.
const FAMILIES := ["moonrunner-x99", "stik-electric-6s"]
const DIRECTORY := "res://data/aircraft_model_overlays"
const PATH := DIRECTORY + "/" + FAMILY + ".json"

static func describe(family: String) -> Dictionary:
	if not FAMILIES.has(family):
		return _failure("Unknown overlay model family.")
	for registered: String in FAMILIES:
		if FileAccess.file_exists("res://data/aircraft_models/" + registered + ".json"):
			return _failure("Overlay family collides with a base model manifest.")
	var directory := DirAccess.open(DIRECTORY)
	if directory == null:
		return _failure("Overlay model directory is missing.")
	var files := directory.get_files()
	var subdirectories := directory.get_directories()
	var expected := PackedStringArray()
	for registered: String in FAMILIES: expected.append(registered + ".json")
	files.sort()
	expected.sort()
	if files != expected or not subdirectories.is_empty():
		return _failure("Overlay model directory contains missing or unregistered entries.")
	var bytes := FileAccess.get_file_as_bytes(DIRECTORY + "/" + family + ".json")
	var value: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not value is Dictionary:
		return _failure("Overlay model manifest is malformed.")
	var checked: Dictionary = BaseRegistry.validate_manifest(value, family)
	if not checked.get("ok", false):
		return checked
	var proof: Dictionary = SourceProof.verify(checked.manifest, family)
	if not proof.get("ok", false):
		return proof
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	checked["manifest_sha256"] = hash.finish().hex_encode()
	return checked

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "errors": PackedStringArray([message])}

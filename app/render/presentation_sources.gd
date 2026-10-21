extends RefCounted

## Closed package proof contract for the customization adapter and smoke renderers.
const ENGINE_VERSION_PIN := "4.7.2"
const PACKAGE_PATH := "res://data/aircraft_customization_package.json"
const PACKAGE_FORMAT := "openrc-aircraft-presentation-package v1"
const PROOF_ROOT := "res://data/aircraft_customization_proofs/"
const SOURCE_PATHS := [
	"res://render/aircraft_customization.gd",
	"res://render/presentation_sources.gd",
	"res://render/smoke/exhaust.gd",
	"res://render/smoke/process.gdshader",
	"res://render/smoke/profile_process.gdshader",
	"res://render/smoke/profile_smoke.gd",
	"res://render/smoke/profile_smoke_schedule.gd",
]
const SOURCE_PATHS_V2 := [
	"res://render/aircraft_customization.gd",
	"res://render/presentation_sources.gd",
	"res://render/smoke/exhaust.gd",
	"res://render/smoke/process.gdshader",
	"res://render/smoke/profile_process.gdshader",
	"res://render/smoke/profile_smoke.gd",
	"res://render/smoke/profile_smoke_schedule.gd",
	"res://render/smoke/smoke_system.gd",
	"res://render/smoke/stock_profile.gd",
	"res://workshop/presentation.gd",
]
## Raw assets must enter this closed set before they can be proved. No assets yet.
const RAW_ASSET_PATHS: Array[String] = []

static func paths_for_version(version: int = 2) -> Array:
	if version == 1:
		return SOURCE_PATHS.duplicate()
	if version == 2:
		return SOURCE_PATHS_V2.duplicate()
	return []

const SHA256_RE := "^[0-9a-f]{64}$"


## Hash the exact current source bytes after normalizing line endings to LF.
## The fixed path list is the only source inventory accepted by validate().
static func current_records(version: int = 2) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for source_path: String in paths_for_version(version):
		var bytes := FileAccess.get_file_as_bytes(source_path) if FileAccess.file_exists(source_path) else PackedByteArray()
		records.append({"path": source_path, "sha256": _sha256_lf(bytes)})
	return records


static func expected_proof_path(source_path: String) -> String:
	if not SOURCE_PATHS_V2.has(source_path) and not RAW_ASSET_PATHS.has(source_path):
		return ""
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK or context.update(source_path.to_utf8_buffer()) != OK:
		return ""
	return PROOF_ROOT + context.finish().hex_encode() + ".bin"


## Validate the closed source set from local text files in development or from
## the dedicated presentation proof table in an exported PCK.
static func validate(records: Variant, engine_version: Variant, version: int = 1) -> Dictionary:
	var paths: Array = paths_for_version(version)
	var errors := PackedStringArray()
	var diagnostics: Array[Dictionary] = []
	if typeof(engine_version) != TYPE_STRING or str(engine_version) != ENGINE_VERSION_PIN:
		_add_error(errors, diagnostics, "PRESENTATION_ENGINE_PIN_INVALID", "presentation_engine_version", "presentation engine version must be pinned to Godot " + ENGINE_VERSION_PIN)
	if _runtime_version() != ENGINE_VERSION_PIN:
		_add_error(errors, diagnostics, "PRESENTATION_ENGINE_RUNTIME_MISMATCH", "presentation_engine_version", "running Godot version does not match the presentation engine pin")
	if typeof(records) != TYPE_ARRAY or records.size() != paths.size() or paths.is_empty():
		_add_error(errors, diagnostics, "PRESENTATION_SOURCE_SET_INVALID", "presentation_sources", "presentation_sources must contain the exact registered source records for its proof version")
		return {"ok": false, "errors": errors, "diagnostics": diagnostics}
	var normalized_records: Array[Dictionary] = []
	for index in paths.size():
		var value: Variant = records[index]
		if not (value is Dictionary) or not _exact_keys(value, ["path", "sha256"]):
			_add_error(errors, diagnostics, "PRESENTATION_SOURCE_RECORD_INVALID", "presentation_sources[%d]" % index, "presentation source record has unknown or missing keys")
			continue
		var record: Dictionary = value
		if typeof(record.get("path")) != TYPE_STRING or str(record.path) != str(paths[index]):
			_add_error(errors, diagnostics, "PRESENTATION_SOURCE_PATH_INVALID", "presentation_sources[%d].path" % index, "presentation source path does not match the closed ordered source set")
		if typeof(record.get("sha256")) != TYPE_STRING or not _matches(SHA256_RE, str(record.sha256)):
			_add_error(errors, diagnostics, "PRESENTATION_SOURCE_HASH_INVALID", "presentation_sources[%d].sha256" % index, "presentation source sha256 must be lowercase hexadecimal")
		normalized_records.append(record)
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "diagnostics": diagnostics}
	var package := _read_package(version)
	if not bool(package.get("ok", false)):
		for issue: Dictionary in package.get("diagnostics", []):
			diagnostics.append(issue)
			errors.append(str(issue.get("message", "invalid presentation source package")))
		return {"ok": false, "errors": errors, "diagnostics": diagnostics}
	var proofs: Dictionary = package.get("files", {})
	for index in normalized_records.size():
		var source_record: Dictionary = normalized_records[index]
		var source_path := str(source_record.path)
		var absolute := str(proofs.get(source_path, "")) if bool(package.get("packaged", false)) else ProjectSettings.globalize_path(source_path)
		if absolute.is_empty() or not FileAccess.file_exists(absolute):
			_add_error(errors, diagnostics, "PRESENTATION_SOURCE_MISSING", "presentation_sources[%d].path" % index, "presentation source or proof bytes are missing: " + source_path)
			continue
		var actual := _sha256_lf(FileAccess.get_file_as_bytes(absolute))
		if actual != str(source_record.sha256):
			_add_error(errors, diagnostics, "PRESENTATION_SOURCE_HASH_MISMATCH", "presentation_sources[%d].sha256" % index, "SHA-256 mismatch for presentation source " + source_path)
	return {"ok": errors.is_empty(), "errors": errors, "diagnostics": diagnostics}


static func _read_package(version: int = 1) -> Dictionary:
	var paths: Array = paths_for_version(version)
	if not FileAccess.file_exists(PACKAGE_PATH):
		if FileAccess.file_exists("res://project.binary") or OS.has_feature("template"):
			return _package_failure("PRESENTATION_PACKAGE_MISSING", PACKAGE_PATH, "exported presentation runtime requires its source proof package")
		return {"ok": true, "packaged": false, "files": {}}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PACKAGE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY or not _exact_keys(parsed, ["format", "files"]):
		return _package_failure("PRESENTATION_PACKAGE_INVALID", PACKAGE_PATH, "presentation package marker has unknown or missing fields")
	if parsed.get("format") != (PACKAGE_FORMAT if version == 1 else "openrc-aircraft-presentation-package v2") or typeof(parsed.get("files")) != TYPE_DICTIONARY:
		return _package_failure("PRESENTATION_PACKAGE_INVALID", PACKAGE_PATH, "presentation package format or files map is unsupported")
	var files: Dictionary = parsed.get("files", {})
	if files.size() != paths.size():
		return _package_failure("PRESENTATION_PACKAGE_INVALID", PACKAGE_PATH, "presentation package must pin the exact registered source paths")
	var verified_files := {}
	var destinations := {}
	for source_path: String in paths:
		if not files.has(source_path) or typeof(files[source_path]) != TYPE_STRING:
			return _package_failure("PRESENTATION_PACKAGE_INVALID", PACKAGE_PATH, "presentation package is missing registered source " + source_path)
		var proof_path := str(files[source_path])
		if proof_path != expected_proof_path(source_path):
			return _package_failure("PRESENTATION_PACKAGE_INVALID", PACKAGE_PATH, "presentation proof destination is not deterministic for " + source_path)
		if destinations.has(proof_path):
			return _package_failure("PRESENTATION_PACKAGE_INVALID", PACKAGE_PATH, "multiple presentation sources map to the same proof file")
		if not FileAccess.file_exists(proof_path):
			return _package_failure("PRESENTATION_PACKAGE_PROOF_MISSING", proof_path, "presentation source proof bytes are missing")
		if not ResourceLoader.exists(source_path) or ResourceLoader.load(source_path) == null:
			return _package_failure("PRESENTATION_RESOURCE_MISSING", source_path, "packaged presentation resource does not resolve")
		destinations[proof_path] = true
		verified_files[source_path] = proof_path
	for source_variant: Variant in files.keys():
		if typeof(source_variant) != TYPE_STRING or not paths.has(str(source_variant)):
			return _package_failure("PRESENTATION_PACKAGE_INVALID", PACKAGE_PATH, "presentation package contains an unregistered source path")
	return {"ok": true, "packaged": true, "files": verified_files}


static func _package_failure(code: String, path: String, message: String) -> Dictionary:
	return {"ok": false, "diagnostics": [{"code": code, "path": path, "message": message}]}


static func _add_error(errors: PackedStringArray, diagnostics: Array[Dictionary], code: String, path: String, message: String) -> void:
	errors.append(message)
	diagnostics.append({"code": code, "path": path, "message": message})


static func _sha256_lf(bytes: PackedByteArray) -> String:
	if bytes.is_empty():
		return ""
	var source_text := bytes.get_string_from_utf8().replace("\r\n", "\n").replace("\r", "\n")
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK or context.update(source_text.to_utf8_buffer()) != OK:
		return ""
	return context.finish().hex_encode()


static func _runtime_version() -> String:
	var version: Dictionary = Engine.get_version_info()
	return "%d.%d.%d" % [int(version.get("major", 0)), int(version.get("minor", 0)), int(version.get("patch", 0))]


static func _matches(pattern: String, value: String) -> bool:
	var expression := RegEx.new()
	return expression.compile(pattern) == OK and expression.search(value) != null


static func _exact_keys(value: Dictionary, keys: Array[String]) -> bool:
	if value.size() != keys.size() or not value.has_all(keys):
		return false
	for key: Variant in value.keys():
		if typeof(key) != TYPE_STRING or not keys.has(str(key)):
			return false
	return true

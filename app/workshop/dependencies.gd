extends RefCounted
## Pins the bundled source files that affect a Workshop compilation.

const FORMAT: String = "openrc-aircraft-workshop-dependencies v1"
const WHEEL_PROFILES_PATH: String = "res://data/ground/wheel_profiles.json"
const GLOW_DIRECTORY: String = "res://data/glow/"
const MANIFEST_KEYS: PackedStringArray = ["format", "files"]


static func capture(base: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	var paths_result: Dictionary = _current_paths(base)
	if not bool(paths_result["ok"]):
		return _result(false, paths_result["errors"])
	var files: Dictionary = {}
	for path: String in paths_result["paths"]:
		var read_result: Dictionary = _read_dependency(path)
		if not bool(read_result["ok"]):
			errors.append_array(read_result["errors"])
			continue
		files[path] = read_result["sha256"]
	if not errors.is_empty():
		return _result(false, errors)
	var manifest: Dictionary = {"format": FORMAT, "files": files}
	var checked: Dictionary = validate_manifest(base, manifest)
	if not bool(checked["ok"]):
		return checked
	return _result(true, errors, manifest)


static func verify(base: Dictionary, expected: Variant) -> Dictionary:
	var checked: Dictionary = validate_manifest(base, expected)
	if not bool(checked["ok"]):
		return checked
	var captured: Dictionary = capture(base)
	if not bool(captured["ok"]):
		return captured
	var current: Dictionary = captured["manifest"]
	var pinned_files: Dictionary = checked["manifest"]["files"]
	var current_files: Dictionary = current["files"]
	if current != checked["manifest"]:
		var changed: PackedStringArray = PackedStringArray()
		var names: Array[String] = []
		for path_variant: Variant in pinned_files.keys():
			names.append(str(path_variant))
		for path_variant: Variant in current_files.keys():
			if not names.has(str(path_variant)):
				names.append(str(path_variant))
		names.sort()
		for path: String in names:
			if pinned_files.get(path, "") != current_files.get(path, ""):
				changed.append(path)
		var message: String = "Pinned Workshop dependencies changed"
		if not changed.is_empty():
			message += ": " + ", ".join(changed)
		message += ". The saved variant remains unchanged; create a new variant to use current dependencies."
		return _result(false, PackedStringArray([message]), current)
	return _result(true, PackedStringArray(), current)


## Checks schema and safe source bindings without consulting current dependency files.
## This lets an old saved variant remain visible when a bundled dependency has changed or disappeared.
static func validate_manifest(base: Dictionary, value: Variant) -> Dictionary:
	var errors := PackedStringArray()
	var source_result: Dictionary = _source_bindings(base)
	if not bool(source_result["ok"]):
		return _result(false, source_result["errors"])
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("Pinned Workshop dependency manifest must be a JSON object.")
		return _result(false, errors)
	var manifest: Dictionary = value
	if manifest.size() != MANIFEST_KEYS.size() or not manifest.has_all(MANIFEST_KEYS):
		errors.append("Pinned Workshop dependency manifest has missing or unsupported fields.")
		return _result(false, errors)
	if typeof(manifest["format"]) != TYPE_STRING or manifest["format"] != FORMAT:
		errors.append("Pinned Workshop dependency manifest format is unsupported.")
	if typeof(manifest["files"]) != TYPE_DICTIONARY:
		errors.append("Pinned Workshop dependency files must be an object.")
		return _result(false, errors)
	var files: Dictionary = manifest["files"]
	var bindings: Dictionary = source_result["bindings"]
	var expected_count: int = 1 + (2 if bindings.has("glow_installation") else 0)
	if files.size() != expected_count or not files.has(WHEEL_PROFILES_PATH):
		errors.append("Pinned Workshop dependency files do not match the base aircraft's declared dependency families.")
	if files.get(WHEEL_PROFILES_PATH, "") is not String or not _valid_sha256(str(files.get(WHEEL_PROFILES_PATH, ""))):
		errors.append("Pinned wheel-profile dependency SHA-256 is malformed.")
	if bindings.has("glow_installation"):
		var installation_path: String = str(bindings["glow_installation"])
		if not files.has(installation_path):
			errors.append("Pinned glow installation dependency is missing.")
		if files.get(installation_path, "") is not String or not _valid_sha256(str(files.get(installation_path, ""))):
			errors.append("Pinned glow installation dependency SHA-256 is malformed.")
		var profile_paths: Array[String] = []
		for path_variant: Variant in files.keys():
			var path: String = str(path_variant)
			if path != WHEEL_PROFILES_PATH and path != installation_path:
				if not _valid_glow_path(path):
					errors.append("Pinned Workshop dependency path is outside bundled glow data.")
				else:
					profile_paths.append(path)
				if files[path_variant] is not String or not _valid_sha256(str(files[path_variant])):
					errors.append("Pinned glow profile dependency SHA-256 is malformed.")
		if profile_paths.size() != 1:
			errors.append("Pinned glow profile dependency must name exactly one safe bundled profile.")
	for path_variant: Variant in files.keys():
		if typeof(path_variant) != TYPE_STRING:
			errors.append("Pinned Workshop dependency paths must be strings.")
			break
		var path: String = str(path_variant)
		if path != WHEEL_PROFILES_PATH and not _valid_glow_path(path):
			errors.append("Pinned Workshop dependency path is not an allowed bundled resource.")
			break
		if typeof(files[path_variant]) != TYPE_STRING or not _valid_sha256(str(files[path_variant])):
			errors.append("Pinned Workshop dependency SHA-256 is malformed.")
			break
	if not errors.is_empty():
		return _result(false, errors)
	return _result(true, errors, manifest.duplicate(true))


static func _current_paths(base: Dictionary) -> Dictionary:
	var bindings_result: Dictionary = _source_bindings(base)
	if not bool(bindings_result["ok"]):
		return bindings_result
	var paths: Array[String] = [WHEEL_PROFILES_PATH]
	if bindings_result["bindings"].has("glow_installation"):
		var installation_path: String = str(bindings_result["bindings"]["glow_installation"])
		var installation_result: Dictionary = _read_dependency(installation_path)
		if not bool(installation_result["ok"]):
			return installation_result
		var installation_bytes: PackedByteArray = installation_result["bytes"]
		var text: String = installation_bytes.get_string_from_utf8()
		if text.to_utf8_buffer() != installation_bytes:
			return _failure("Glow installation dependency is not valid UTF-8: " + installation_path)
		var parser := JSON.new()
		if parser.parse(text) != OK or typeof(parser.data) != TYPE_DICTIONARY:
			return _failure("Glow installation dependency is not a valid JSON object: " + installation_path)
		var profile_path: Variant = parser.data.get("profile", null)
		if not _valid_glow_path(profile_path):
			return _failure("Glow installation declares a profile outside bundled res://data/glow JSON: " + str(profile_path))
		paths.append(installation_path)
		paths.append(str(profile_path))
	paths.sort()
	return {"ok": true, "errors": PackedStringArray(), "paths": paths}


static func _source_bindings(base: Dictionary) -> Dictionary:
	if str(base.get("format", "")) != "openrc-aircraft v2":
		return _failure("Workshop dependencies require an openrc-aircraft v2 base snapshot.")
	var propulsion: Variant = base.get("propulsion", null)
	if typeof(propulsion) != TYPE_DICTIONARY:
		return _failure("Workshop dependency source needs a propulsion object.")
	var engine: Variant = propulsion.get("engine", {})
	if typeof(engine) != TYPE_DICTIONARY:
		return _failure("Workshop dependency source has a malformed engine object.")
	var bindings: Dictionary = {}
	if engine.has("glow_installation"):
		var installation_path: Variant = engine["glow_installation"]
		if not _valid_glow_path(installation_path):
			return _failure("Glow installation path must be a flat bundled res://data/glow JSON path.")
		bindings["glow_installation"] = str(installation_path)
	return {"ok": true, "errors": PackedStringArray(), "bindings": bindings}


static func _valid_glow_path(path: Variant) -> bool:
	if typeof(path) != TYPE_STRING or not str(path).begins_with(GLOW_DIRECTORY) or not str(path).ends_with(".json") or ".." in str(path):
		return false
	var basename: String = str(path).substr(GLOW_DIRECTORY.length())
	if basename.is_empty() or "/" in basename or "\\" in basename:
		return false
	for index: int in basename.length():
		var code: int = basename.unicode_at(index)
		if code == 46 or code == 45 or code == 95 or (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122):
			continue
		return false
	return true


static func _read_dependency(path: String) -> Dictionary:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return _failure("Cannot read bundled Workshop dependency: " + path)
	return {"ok": true, "errors": PackedStringArray(), "bytes": bytes, "sha256": _sha256(bytes)}


static func _valid_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for index: int in value.length():
		var code: int = value.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
			return false
	return true


static func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(bytes)
	return context.finish().hex_encode()


static func _failure(message: String) -> Dictionary:
	return _result(false, PackedStringArray([message]))


static func _result(ok: bool, errors: PackedStringArray, manifest: Dictionary = {}) -> Dictionary:
	return {"ok": ok, "errors": errors, "manifest": manifest}

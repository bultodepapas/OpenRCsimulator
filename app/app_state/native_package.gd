## NK-3: identity of the exact exported Linux executable, including its embedded pack.
## The embedded manifest pins native inputs; the external artifact receipt binds the final executable bytes.
## This is artifact consistency, not a signature or a claim about other builds/platforms.
extends RefCounted

const MANIFEST_PATH := "res://native/kernel/package.json"
const MANIFEST_FORMAT := "openrc-native-kernel-package v1"
const ARTIFACT_FORMAT := "openrc-native-kernel-package-artifact v1"
const RELATIVE_DIRECTORY := "native/kernel"
static var _checked := false
static var _result: Dictionary = {}


static func identity() -> Dictionary:
	if not _checked:
		_checked = true
		_result = _inspect()
	return _result.duplicate(true)


static func directory() -> String:
	return OS.get_executable_path().get_base_dir().path_join(RELATIVE_DIRECTORY)


static func _inspect() -> Dictionary:
	if not OS.has_feature("template_release") or OS.get_name() != "Linux" or Engine.get_architecture_name() != "x86_64":
		return _refuse("native package requires the Linux x86_64 release template")
	var manifest := _read_object(MANIFEST_PATH)
	if manifest.get("format") != MANIFEST_FORMAT or manifest.get("platform") != "linux" \
			or manifest.get("architecture") != "x86_64" or manifest.get("engine_version") != Engine.get_version_info().string \
			or typeof(manifest.get("native_receipt")) != TYPE_DICTIONARY \
			or not _sha256(manifest.get("solver_sha256")) or typeof(manifest.get("qualification_sources")) != TYPE_DICTIONARY:
		return _refuse("native package manifest is missing, malformed or for another engine")
	var artifact := _read_object(directory().path_join("package-receipt.json"))
	if artifact.get("format") != ARTIFACT_FORMAT or not _sha256(artifact.get("executable_sha256")) \
			or not _sha256(artifact.get("manifest_sha256")):
		return _refuse("native package artifact receipt is missing or malformed")
	if FileAccess.get_sha256(MANIFEST_PATH) != artifact.manifest_sha256:
		return _refuse("native package manifest differs from its artifact receipt")
	var executable_hash := FileAccess.get_sha256(OS.get_executable_path())
	if executable_hash != artifact.executable_sha256:
		return _refuse("native package executable differs from its artifact receipt")
	return {ok = true, reason = "", manifest = manifest, executable_sha256 = executable_hash}


static func _sha256(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and value.length() == 64 and value.is_valid_hex_number()


static func _read_object(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return {}
	return parser.data


static func _refuse(reason: String) -> Dictionary:
	return {ok = false, reason = reason, manifest = {}, executable_sha256 = ""}

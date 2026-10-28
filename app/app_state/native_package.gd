## NK-3: identity of the exact exported Linux executable, including its embedded pack.
## The embedded manifest pins native inputs; the external artifact receipt binds the final executable bytes.
## This is artifact consistency, not a signature or a claim about other builds/platforms.
extends RefCounted

const MANIFEST_PATH := "res://native/kernel/package.json"
const MANIFEST_FORMAT := "openrc-native-kernel-package v1"
const ARTIFACT_FORMAT := "openrc-native-kernel-package-artifact v1"
const RELATIVE_DIRECTORY := "native/kernel"
const DIAGNOSTICS := ["session_probe.gd", "test_native_stage.gd", "test_native_session.gd", "test_native_replay.gd"]
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
	if not _complete_manifest(manifest):
		return _refuse("native package manifest has incomplete verification identities")
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


static func _complete_manifest(manifest: Dictionary) -> bool:
	var receipt: Dictionary = manifest.native_receipt
	if receipt.get("format") != "openrc-native-kernel-receipt" or not _backend(receipt) \
			or typeof(receipt.get("platforms")) != TYPE_DICTIONARY:
		return false
	var row: Variant = receipt.platforms.get("linux")
	if typeof(row) != TYPE_DICTIONARY or not _backend(row) or row.get("platform") != "linux" \
			or row.get("architecture") != "x86_64" or row.get("engine_version") != manifest.engine_version \
			or typeof(row.get("mirrored_sources")) != TYPE_DICTIONARY or row.mirrored_sources.is_empty():
		return false
	for key: String in ["binary_sha256", "source_sha256", "lock_sha256", "engine_sha256"]:
		if not _sha256(row.get(key)):
			return false
	for path: Variant in row.mirrored_sources:
		if typeof(path) != TYPE_STRING or not path.begins_with("app/") or not _sha256(row.mirrored_sources[path]):
			return false
	var diagnostics: Dictionary = manifest.qualification_sources
	if diagnostics.size() != DIAGNOSTICS.size():
		return false
	for name: String in DIAGNOSTICS:
		if not _sha256(diagnostics.get(name)):
			return false
	return true


static func _backend(receipt: Dictionary) -> bool:
	var abi: Variant = receipt.get("abi_version")
	return receipt.get("backend") == "native" and receipt.get("backend_version") == "openrc-native-kernel-stage-v1" \
		and (typeof(abi) == TYPE_INT or typeof(abi) == TYPE_FLOAT) and abi == 1


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

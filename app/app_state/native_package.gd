## NK-3: identity of the exact exported Linux executable, including its embedded pack.
## The embedded manifest pins native inputs; the external artifact receipt binds the final executable bytes.
## This is artifact consistency, not a signature or a claim about other builds/platforms.
extends RefCounted

const MANIFEST_PATH := "res://native/kernel/package.json"
const MANIFEST_FORMAT := "openrc-native-kernel-package v1"
const ARTIFACT_FORMAT := "openrc-native-kernel-package-artifact v1"
const RELATIVE_DIRECTORY := "native/kernel"
const DIAGNOSTICS := ["session_probe.gd", "test_native_stage.gd", "test_native_session.gd", "test_native_replay.gd",
	"test_native_helicopter_session.gd", "test_heli_restore_radio.gd"]
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
	return receipt.get("backend") == "native" and receipt.get("backend_version") == "openrc-native-kernel-stage-v2" \
		and (typeof(abi) == TYPE_INT or typeof(abi) == TYPE_FLOAT) and abi == 2


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


## A separate, reference-only Mac identity. The external receipt is made after
## signing, and covers every regular file inside the .app, including its PCK and
## any sidecars. It establishes consistency, not signature or publisher trust.
const MAC_RECEIPT_FORMAT := "openrc-macos-reference-bundle-v1"
const MAC_IDENTITY_KIND := "macos-reference-bundle-v1"
const MAC_RECEIPT_SUFFIX := ".openrc-reference-receipt"
const MAC_MAX_RECEIPT := 4 * 1024 * 1024
const MAC_MAX_FILES := 10000


static func mac_reference_identity(executable: String, architecture: String, arguments := PackedStringArray()) -> Dictionary:
	for arg: String in arguments:
		var option := arg.split("=", true, 1)[0]
		if option in ["--main-pack", "--path", "--script", "-s", "--editor", "-e", "--project-manager", "--remote-fs"]:
			return _refuse("Mac bundle identity refuses resource or script overrides")
	var macos := executable.get_base_dir()
	var contents := macos.get_base_dir()
	var bundle := contents.get_base_dir()
	if macos.get_file() != "MacOS" or contents.get_file() != "Contents" or not bundle.get_file().ends_with(".app"):
		return _refuse("executable is not in a Mac app bundle")
	var settings_override := str(ProjectSettings.get_setting("application/config/project_settings_override", ""))
	if not settings_override.is_empty() and not settings_override.begins_with("res://"):
		return _refuse("external project settings override is not bound to the Mac bundle")
	var parent := DirAccess.open(bundle.get_base_dir())
	var receipt_path := bundle + MAC_RECEIPT_SUFFIX
	if parent == null or parent.is_link(bundle.get_file()) or parent.is_link(receipt_path.get_file()):
		return _refuse("Mac bundle or receipt is redirected")
	var file := FileAccess.open(receipt_path, FileAccess.READ)
	if file == null or file.get_length() <= 0 or file.get_length() > MAC_MAX_RECEIPT:
		return _refuse("Mac bundle receipt is missing or oversized")
	var raw := file.get_buffer(file.get_length())
	var text := raw.get_string_from_utf8()
	if text.to_utf8_buffer() != raw or not text.ends_with("\n") or text.contains("\r"):
		return _refuse("Mac bundle receipt is malformed")
	var lines := text.trim_suffix("\n").split("\n")
	var fields := ["bundle", "architectures", "executable", "pack", "source_commit", "source_tree",
		"source_worktree_sha256", "source_receipt_sha256", "probe_sha256"]
	if lines.size() < 11 or lines[0] != MAC_RECEIPT_FORMAT:
		return _refuse("Mac bundle receipt version or fields are invalid")
	var values := {}
	for index in fields.size():
		var row := lines[index + 1].split("\t")
		if row.size() != 2 or row[0] != fields[index] or not _mac_text(row[1]):
			return _refuse("Mac bundle receipt field is invalid")
		values[fields[index]] = row[1]
	var architectures: PackedStringArray = values.architectures.split(",")
	if architectures not in [PackedStringArray(["arm64"]), PackedStringArray(["x86_64"]), PackedStringArray(["arm64", "x86_64"])] \
			or architecture not in architectures:
		return _refuse("Mac bundle receipt does not admit this architecture")
	if values.bundle != bundle.get_file() or values.executable != "Contents/MacOS/" + executable.get_file():
		return _refuse("Mac bundle receipt identifies a different app or executable")
	for key: String in ["source_commit", "source_tree"]:
		var value: String = values[key]
		if value.length() not in [40, 64] or not value.is_valid_hex_number() or value != value.to_lower():
			return _refuse("Mac bundle source identity is invalid")
	for key: String in ["source_worktree_sha256", "source_receipt_sha256", "probe_sha256"]:
		if not _sha256(values[key]) or values[key] != values[key].to_lower():
			return _refuse("Mac bundle receipt digest is invalid")
	var expected := {}
	var previous := ""
	for index in range(10, lines.size()):
		var row := lines[index].split("\t")
		if row.size() != 3 or row[0] != "file" or not _sha256(row[1]) or row[1] != row[1].to_lower() \
				or not _mac_relative(row[2]) or (not previous.is_empty() and row[2] <= previous):
			return _refuse("Mac bundle file inventory is malformed")
		previous = row[2]
		expected[row[2]] = row[1]
		if expected.size() > MAC_MAX_FILES:
			return _refuse("Mac bundle inventory is too large")
	var packs: Array[String] = []
	var executables: Array[String] = []
	for path: String in expected:
		if path.to_lower().ends_with(".pck"): packs.append(path)
		if path.begins_with("Contents/MacOS/") and path.count("/") == 2: executables.append(path)
	var pack_names := ["Contents/Resources/" + executable.get_file().get_basename() + ".pck",
		"Contents/Resources/" + executable.get_file() + ".pck"]
	if executables != [values.executable] or packs != [values.pack] or values.pack not in pack_names:
		return _refuse("Mac bundle must contain the identified executable and one Resources PCK")
	var actual := {}
	if not _mac_inventory(bundle, "", actual, 0, {count = 0}) or actual != expected:
		return _refuse("Mac bundle contents differ from the receipt")
	if not _mac_pack_header(bundle.path_join(values.pack)):
		return _refuse("Mac bundle PCK is invalid, encrypted or sparse")
	var binary := FileAccess.open(executable, FileAccess.READ)
	if binary == null or binary.get_length() < 32:
		return _refuse("Mac executable is unreadable")
	binary.seek(binary.get_length() - 4)
	if binary.get_buffer(4) == "GDPC".to_ascii_buffer():
		return _refuse("Mac executable has an embedded PCK marker")
	var receipt_hash := FileAccess.get_sha256(receipt_path)
	if not _sha256(receipt_hash) or receipt_hash != text.sha256_text():
		return _refuse("Mac bundle receipt could not be hashed")
	return {ok = true, reason = "", kind = MAC_IDENTITY_KIND,
		sha256 = (receipt_hash + "\n" + architecture).sha256_text(), receipt_sha256 = receipt_hash,
		executable_sha256 = expected[values.executable], pack_sha256 = expected[values.pack],
		probe_sha256 = values.probe_sha256, architecture = architecture}


## The native receipt is separate from, and binds, the final reference bundle
## receipt. Its manifest is inside the PCK; no signed bundle bytes are rewritten.
const MAC_NATIVE_RECEIPT_FORMAT := "openrc-macos-native-bundle-v1"
const MAC_NATIVE_IDENTITY_KIND := "macos-arm64-native-bundle-v1"
const MAC_NATIVE_RECEIPT_SUFFIX := ".openrc-native-receipt"
const MAC_NATIVE_MANIFEST_PATH := "res://native/kernel/package-macos.json"
const MAC_NATIVE_MANIFEST_FORMAT := "openrc-macos-native-kernel-package-v1"
const MAC_NATIVE_LIBRARY := "Contents/Frameworks/libopenrc_native_kernel.dylib"
const MAC_NATIVE_DESCRIPTOR := "Contents/Resources/openrc_native_kernel_macos.gdextension"
const MAC_NATIVE_LICENSE := "Contents/Resources/LICENSE.godot-cpp.md"
const MAC_NATIVE_SCOPE := "macos-arm64-fixed-wing-experimental-v1"
const MAC_NATIVE_DIAGNOSTICS := ["session_probe.gd", "test_native_stage.gd", "test_native_session.gd", "test_native_replay.gd"]


static func mac_native_identity(executable: String, architecture: String, arguments := PackedStringArray()) -> Dictionary:
	if architecture != "arm64":
		return _refuse("Mac native package requires an arm64 process")
	var reference := mac_reference_identity(executable, architecture, arguments)
	if not reference.get("ok", false): return reference
	var bundle := executable.get_base_dir().get_base_dir().get_base_dir()
	var parent := DirAccess.open(bundle.get_base_dir())
	var path := bundle + MAC_NATIVE_RECEIPT_SUFFIX
	if parent == null or parent.is_link(path.get_file()):
		return _refuse("Mac native bundle receipt is redirected")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() <= 0 or file.get_length() > MAC_MAX_RECEIPT:
		return _refuse("Mac native bundle receipt is missing or oversized")
	var raw := file.get_buffer(file.get_length())
	var text := raw.get_string_from_utf8()
	if text.to_utf8_buffer() != raw or not text.ends_with("\n") or text.contains("\r"):
		return _refuse("Mac native bundle receipt is malformed")
	var lines := text.trim_suffix("\n").split("\n")
	var fields := ["bundle", "architecture", "reference_receipt_sha256", "manifest_sha256", "descriptor_sha256", "library_sha256"]
	if lines.size() != fields.size() + 1 or lines[0] != MAC_NATIVE_RECEIPT_FORMAT:
		return _refuse("Mac native bundle receipt version or fields are invalid")
	var values := {}
	for index in fields.size():
		var row := lines[index + 1].split("\t")
		if row.size() != 2 or row[0] != fields[index] or not _mac_text(row[1]):
			return _refuse("Mac native bundle receipt field is invalid")
		values[fields[index]] = row[1]
	if values.bundle != bundle.get_file() or values.architecture != "arm64" \
			or values.reference_receipt_sha256 != reference.receipt_sha256:
		return _refuse("Mac native receipt identifies another bundle or reference receipt")
	for key: String in ["reference_receipt_sha256", "manifest_sha256", "descriptor_sha256", "library_sha256"]:
		if not _sha256(values[key]) or values[key] != values[key].to_lower():
			return _refuse("Mac native receipt digest is invalid")
	if FileAccess.get_sha256(MAC_NATIVE_MANIFEST_PATH) != values.manifest_sha256 \
			or FileAccess.get_sha256(bundle.path_join(MAC_NATIVE_DESCRIPTOR)) != values.descriptor_sha256 \
			or FileAccess.get_sha256(bundle.path_join(MAC_NATIVE_LIBRARY)) != values.library_sha256:
		return _refuse("Mac native manifest, descriptor or library differs from its receipt")
	var license_path := bundle.path_join(MAC_NATIVE_LICENSE)
	if not FileAccess.file_exists(license_path):
		return _refuse("Mac native licence is missing")
	var license_hash := FileAccess.get_sha256(license_path)
	var manifest_file := FileAccess.open(MAC_NATIVE_MANIFEST_PATH, FileAccess.READ)
	if manifest_file == null or manifest_file.get_length() <= 0 or manifest_file.get_length() > MAC_MAX_RECEIPT:
		return _refuse("Mac native manifest is missing or oversized")
	var manifest := _read_object(MAC_NATIVE_MANIFEST_PATH)
	if not _mac_native_manifest_valid(manifest, reference.probe_sha256, values.library_sha256, license_hash):
		return _refuse("Mac native manifest or fixed diagnostics are invalid")
	var receipt_hash := FileAccess.get_sha256(path)
	if not _sha256(receipt_hash) or receipt_hash != text.sha256_text():
		return _refuse("Mac native bundle receipt could not be hashed")
	return {ok = true, reason = "", kind = MAC_NATIVE_IDENTITY_KIND,
		sha256 = (receipt_hash + "\n" + architecture).sha256_text(), receipt_sha256 = receipt_hash,
		reference_receipt_sha256 = reference.receipt_sha256, manifest = manifest,
		library_path = bundle.path_join(MAC_NATIVE_LIBRARY), descriptor_path = bundle.path_join(MAC_NATIVE_DESCRIPTOR)}


static func _mac_native_manifest_valid(manifest: Dictionary, reference_probe: String, library_hash: String, license_hash: String) -> bool:
	if not _mac_native_manifest_schema_valid(manifest, reference_probe, library_hash, license_hash): return false
	for name: String in MAC_NATIVE_DIAGNOSTICS:
		if FileAccess.get_sha256("res://native/kernel/qualification/" + name) != manifest.qualification_sources[name]:
			return false
	return true


static func _mac_native_manifest_schema_valid(manifest: Dictionary, reference_probe: String, library_hash: String, license_hash: String) -> bool:
	if manifest.get("format") != MAC_NATIVE_MANIFEST_FORMAT or manifest.get("platform") != "macos" \
			or manifest.get("architecture") != "arm64" or manifest.get("engine_version") != Engine.get_version_info().string \
			or not _sha256(manifest.get("solver_sha256")) or not _sha256(manifest.get("license_sha256")) \
			or manifest.get("license_sha256") != license_hash or typeof(manifest.get("native_receipt")) != TYPE_DICTIONARY \
			or typeof(manifest.get("qualification_sources")) != TYPE_DICTIONARY:
		return false
	var receipt: Dictionary = manifest.native_receipt
	if receipt.get("format") != "openrc-native-kernel-receipt" or not _backend(receipt) \
			or typeof(receipt.get("platforms")) != TYPE_DICTIONARY:
		return false
	var row: Variant = receipt.platforms.get("macos")
	if typeof(row) != TYPE_DICTIONARY or not _backend(row) or row.get("platform") != "macos" \
			or row.get("architecture") != "arm64" or row.get("qualification_scope") != MAC_NATIVE_SCOPE \
			or row.get("engine_version") != manifest.engine_version or row.get("binary_sha256") != library_hash \
			or typeof(row.get("runtime_os_version")) != TYPE_STRING or str(row.runtime_os_version).is_empty() \
			or typeof(row.get("runtime_os_build")) != TYPE_STRING or str(row.runtime_os_build).is_empty() \
			or typeof(row.get("mirrored_sources")) != TYPE_DICTIONARY or row.mirrored_sources.is_empty() \
			or typeof(row.get("verification")) != TYPE_DICTIONARY or row.verification.is_empty():
		return false
	for key: String in ["binary_sha256", "source_sha256", "lock_sha256", "engine_sha256"]:
		if not _sha256(row.get(key)): return false
	for name: Variant in row.mirrored_sources:
		if typeof(name) != TYPE_STRING or not name.begins_with("app/") or not _mac_relative(name.trim_prefix("app/")) \
				or not _sha256(row.mirrored_sources[name]):
			return false
	var diagnostics: Dictionary = manifest.qualification_sources
	if diagnostics.size() != MAC_NATIVE_DIAGNOSTICS.size() or diagnostics.get("session_probe.gd") != reference_probe:
		return false
	for name: String in MAC_NATIVE_DIAGNOSTICS:
		var expected: Variant = diagnostics.get(name)
		if not _sha256(expected): return false
	return true


static func _mac_text(value: String) -> bool:
	return not value.is_empty() and not value.contains("\t") and not value.contains("\r") \
		and not value.contains("\n") and not value.contains("\\")


static func _mac_pack_header(path: String) -> bool:
	var pack := FileAccess.open(path, FileAccess.READ)
	if pack == null or pack.get_length() < 40 or pack.get_buffer(4) != "GDPC".to_ascii_buffer(): return false
	var version := pack.get_32()
	var major := pack.get_32()
	var minor := pack.get_32()
	pack.get_32() # patch version
	var flags := pack.get_32()
	pack.get_64() # file base
	var directory := pack.get_64() if version in [3, 4] else 96
	if version not in [2, 3, 4] or major != 4 or minor > 8 or (flags & ~2) != 0 \
			or directory < 40 or directory > pack.get_length() - 4:
		return false
	pack.seek(directory)
	var count := pack.get_32()
	return count > 0 and count <= 200000


static func _mac_relative(value: String) -> bool:
	if not _mac_text(value) or value.begins_with("/"): return false
	for part: String in value.split("/"):
		if part in ["", ".", ".."]: return false
	return true


static func _mac_inventory(bundle: String, relative: String, files: Dictionary, depth: int, entries: Dictionary) -> bool:
	if depth > 32: return false
	var directory := DirAccess.open(bundle.path_join(relative))
	if directory == null: return false
	directory.include_hidden = true
	if directory.list_dir_begin() != OK: return false
	var name := directory.get_next()
	while not name.is_empty():
		entries["count"] += 1
		if entries["count"] > MAC_MAX_FILES: return false
		var path := name if relative.is_empty() else relative.path_join(name)
		if not _mac_relative(path) or directory.is_link(name): return false
		if directory.current_is_dir():
			if not _mac_inventory(bundle, path, files, depth + 1, entries): return false
		else:
			var digest := FileAccess.get_sha256(bundle.path_join(path))
			if not _sha256(digest): return false
			files[path] = digest
			if files.size() > MAC_MAX_FILES: return false
		name = directory.get_next()
	directory.list_dir_end()
	return true

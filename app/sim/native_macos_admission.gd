## Source-editor promotion receipt. Artifact consistency, not a signing authority.
## Release packages retain their separately qualified delivery route.
extends RefCounted

const PATH := "res://native/kernel/default-admission-macos.json"
const RECEIPT := "res://native/kernel/build-receipt-macos.json"
const DOMAIN := "res://sim/native_macos_domain.gd"
const FORMAT := "openrc-macos-native-default v1"
const SCOPE := "source-editor-macos-arm64"
const MAX_BYTES := 2 * 1024 * 1024


static func read_marker() -> Dictionary:
	if OS.has_feature("template_release") or OS.get_name() != "macOS" or Engine.get_architecture_name() != "arm64":
		return {}
	var marker_document := _read_document(PATH)
	if marker_document.is_empty(): return {}
	var receipt_document := _read_document(RECEIPT)
	var marker: Variant = marker_document.get("data")
	var receipt: Variant = receipt_document.get("data")
	if not marker is Dictionary or not receipt is Dictionary or not receipt.get("platforms") is Dictionary:
		return {}
	var row: Variant = receipt.platforms.get("macos")
	if not row is Dictionary or not identity_error(marker, receipt_document.get("sha256", ""), row,
			_hash_bytes(_read_bytes(DOMAIN)), OS.get_processor_name()).is_empty():
		return {}
	if OS.get_model_name() != marker.get("hardware_model"):
		return {}
	return marker


## Optional admission artifacts fail closed without emitting JSON parser errors.
## Parse and hash one bounded buffer, so a replacement cannot change the bytes cited.
static func _read_document(path: String) -> Dictionary:
	var bytes := _read_bytes(path)
	if bytes.is_empty() or not _valid_utf8(bytes): return {}
	var text := bytes.get_string_from_utf8()
	if text.to_utf8_buffer() != bytes: return {}
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		return {}
	return {data = parser.data, sha256 = _hash_bytes(bytes)}


## Check before decoding: Godot can log errors while replacing malformed UTF-8.
static func _valid_utf8(bytes: PackedByteArray) -> bool:
	var index := 0
	while index < bytes.size():
		var first := int(bytes[index])
		if first < 0x80:
			index += 1
			continue
		var count := 0
		if first >= 0xc2 and first <= 0xdf: count = 2
		elif first >= 0xe0 and first <= 0xef: count = 3
		elif first >= 0xf0 and first <= 0xf4: count = 4
		if count == 0 or index + count > bytes.size(): return false
		for offset: int in range(1, count):
			if bytes[index + offset] < 0x80 or bytes[index + offset] > 0xbf: return false
		var second := int(bytes[index + 1])
		if (first == 0xe0 and second < 0xa0) or (first == 0xed and second >= 0xa0) \
				or (first == 0xf0 and second < 0x90) or (first == 0xf4 and second >= 0x90): return false
		index += count
	return true


static func _read_bytes(path: String) -> PackedByteArray:
	if not FileAccess.file_exists(path): return PackedByteArray()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return PackedByteArray()
	var length := file.get_length()
	if length < 2 or length > MAX_BYTES:
		file.close()
		return PackedByteArray()
	var bytes := file.get_buffer(length)
	file.close()
	return bytes if bytes.size() == length else PackedByteArray()


static func _hash_bytes(bytes: PackedByteArray) -> String:
	if bytes.is_empty(): return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


## The normal NativeStage loader independently verifies actual engine, OS, library and mirrored bytes.
static func identity_error(marker: Dictionary, receipt_sha: String, row: Dictionary,
		domain_sha: String, cpu: String) -> String:
	if marker.get("format") != FORMAT or marker.get("scope") != SCOPE:
		return "Mac default qualification is missing or has another scope"
	var expected := {receipt_sha256 = receipt_sha, domain_sha256 = domain_sha, cpu = cpu,
		binary_sha256 = row.get("binary_sha256"), source_sha256 = row.get("source_sha256"),
		lock_sha256 = row.get("lock_sha256"), engine_sha256 = row.get("engine_sha256"),
		os_version = row.get("runtime_os_version"), os_build = row.get("runtime_os_build")}
	for key: String in expected:
		if typeof(expected[key]) != TYPE_STRING or str(expected[key]).is_empty() or marker.get(key) != expected[key]:
			return "Mac default qualification differs: " + key
	if cpu != "Apple M1" or marker.get("hardware_model") != "MacBookAir10,1":
		return "Mac default hardware has not been qualified"
	if not marker.get("allowed_selections") is Array or marker.allowed_selections.is_empty() \
			or marker.allowed_selections.size() > 1428:
		return "Mac default qualification has no bounded selection set"
	return ""


static func selection_allowed(marker: Dictionary, selection: Dictionary, soft_hull: bool) -> bool:
	if not selection.get("ok", false) or selection.get("profile") != "production":
		return false
	var expected := {aircraft = selection.get("aircraft"), battery = selection.get("battery"),
		start = selection.get("start"), weather = selection.get("weather"), soft_hull = soft_hull,
		trim_profile = "production", start_sha256 = selection.get("start_sha256")}
	if typeof(expected.start_sha256) != TYPE_STRING or str(expected.start_sha256).length() != 64 \
			or not str(expected.start_sha256).is_valid_hex_number(): return false
	var rows: Variant = marker.get("allowed_selections")
	if not rows is Array: return false
	for row: Variant in rows:
		if row is Dictionary and row.size() == expected.size() and row == expected:
			return true
	return false


## A new disk receipt cannot qualify an older library retained by Godot's process cache.
static func loaded_identity_error(marker: Dictionary, receipt_sha: String, row: Dictionary) -> String:
	if marker.get("receipt_sha256") != receipt_sha or receipt_sha.is_empty():
		return "Mac default receipt differs from the loaded library; restart required"
	for key: String in ["binary_sha256", "source_sha256", "lock_sha256", "engine_sha256"]:
		if marker.get(key) != row.get(key) or typeof(row.get(key)) != TYPE_STRING or str(row[key]).is_empty():
			return "Mac default identity differs from the loaded library; restart required"
	return ""

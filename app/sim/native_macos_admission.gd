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
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null or file.get_length() < 2 or file.get_length() > MAX_BYTES:
		return {}
	var marker: Variant = JSON.parse_string(file.get_as_text())
	var receipt: Variant = JSON.parse_string(FileAccess.get_file_as_string(RECEIPT))
	if not marker is Dictionary or not receipt is Dictionary or not receipt.get("platforms") is Dictionary:
		return {}
	var row: Variant = receipt.platforms.get("macos")
	if not row is Dictionary or not identity_error(marker, FileAccess.get_sha256(RECEIPT), row,
			FileAccess.get_sha256(DOMAIN), OS.get_processor_name()).is_empty():
		return {}
	if OS.get_model_name() != marker.get("hardware_model"):
		return {}
	return marker


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

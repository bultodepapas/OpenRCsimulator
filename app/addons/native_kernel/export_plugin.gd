## NK-3: embed the oracle-qualified identity and existing diagnostics, without registering a GDExtension.
@tool
extends EditorExportPlugin

const FlightLog := preload("res://sim/flight_log.gd")
const MANIFEST := "res://native/kernel/package.json"
const SOURCES := {
	"session_probe.gd": "../research/performance/session_probe.gd",
	"test_native_stage.gd": "tests/test_native_stage.gd",
	"test_native_session.gd": "tests/test_native_session.gd",
	"test_native_replay.gd": "tests/test_native_replay.gd",
}
var _manifest: Dictionary = {}


func _get_name() -> String:
	return "native_kernel_identity"


func _export_begin(features: PackedStringArray, is_debug: bool, _path: String, _flags: int) -> void:
	_manifest = {}
	if not features.has("linux") or not features.has("x86_64") or is_debug:
		return
	var parser := JSON.new()
	if not FileAccess.file_exists(MANIFEST) or parser.parse(FileAccess.get_file_as_string(MANIFEST)) != OK \
			or typeof(parser.data) != TYPE_DICTIONARY:
		_fail("Run research/native-kernel/package.py prepare before exporting Linux")
		return
	_manifest = parser.data
	if not _inputs_match():
		_fail("NK-3 export inputs differ from the prepared verified manifest")
		return
	add_file(MANIFEST, FileAccess.get_file_as_bytes(MANIFEST), false)
	for name: String in SOURCES:
		var path := ProjectSettings.globalize_path("res://").path_join(SOURCES[name])
		add_file("res://native/kernel/qualification/" + name, FileAccess.get_file_as_bytes(path), false)


func _inputs_match() -> bool:
	if _manifest.get("format") != "openrc-native-kernel-package v1" \
			or _manifest.get("engine_version") != Engine.get_version_info().string \
			or _manifest.get("solver_sha256") != FlightLog.solver_identity():
		return false
	var receipt: Variant = _manifest.get("native_receipt")
	if typeof(receipt) != TYPE_DICTIONARY or typeof(receipt.get("platforms")) != TYPE_DICTIONARY:
		return false
	var row: Variant = receipt.platforms.get("linux")
	if typeof(row) != TYPE_DICTIONARY or typeof(row.get("mirrored_sources")) != TYPE_DICTIONARY \
			or row.mirrored_sources.is_empty() or row.get("engine_sha256") != FileAccess.get_sha256(OS.get_executable_path()) \
			or row.get("binary_sha256") != FileAccess.get_sha256("res://native/kernel/libopenrc_native_kernel.so"):
		return false
	for name: Variant in row.mirrored_sources:
		if typeof(name) != TYPE_STRING or not name.begins_with("app/"):
			return false
		if FileAccess.get_sha256("res://" + name.trim_prefix("app/")) != row.mirrored_sources[name]:
			return false
	var diagnostics: Variant = _manifest.get("qualification_sources")
	if typeof(diagnostics) != TYPE_DICTIONARY or diagnostics.size() != SOURCES.size():
		return false
	for name: String in SOURCES:
		var path := ProjectSettings.globalize_path("res://").path_join(SOURCES[name])
		if diagnostics.get(name) != FileAccess.get_sha256(path):
			return false
	return true


func _export_end() -> void:
	if not _manifest.is_empty() and not _inputs_match():
		_fail("NK-3 source or binary changed during export")
	_manifest = {}


func _fail(message: String) -> void:
	push_error(message)
	add_file(MANIFEST, "{}".to_utf8_buffer(), false)
	_manifest = {}

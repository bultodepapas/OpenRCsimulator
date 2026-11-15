## NK-3: embed the oracle-qualified identity and existing diagnostics, without registering a GDExtension.
@tool
extends EditorExportPlugin

const FlightLog := preload("res://sim/flight_log.gd")
const MANIFEST := "res://native/kernel/package.json"
const MAC_MANIFEST := "res://native/kernel/package-macos.json"
const MAC_PAIR_FORMAT := "openrc-macos-engine-pair-binding v1"
const RESEARCH_SCOPE := "source-editor-local-custom-engine-research-v1"
const PLUGIN_SOURCE := "res://addons/native_kernel/export_plugin.gd"
const MAC_DIAGNOSTICS := ["session_probe.gd", "test_native_stage.gd", "test_native_session.gd", "test_native_replay.gd"]
const SOURCES := {
	"session_probe.gd": "../research/performance/session_probe.gd",
	"test_native_stage.gd": "tests/test_native_stage.gd",
	"test_native_session.gd": "tests/test_native_session.gd",
	"test_native_replay.gd": "tests/test_native_replay.gd",
	"test_native_helicopter_session.gd": "tests/test_native_helicopter_session.gd",
	"test_heli_restore_radio.gd": "tests/test_heli_restore_radio.gd",
}
var _manifest: Dictionary = {}
var _mac_probe_sha256 := ""
var _mac_manifest: Dictionary = {}
var _mac_manifest_sha256 := ""
var _mac_export_preset: Object = null
var _mac_template_path := ""
var _mac_experimental := false


func _get_name() -> String:
	return "native_kernel_identity"


func _export_begin(features: PackedStringArray, is_debug: bool, _path: String, _flags: int) -> void:
	_manifest = {}
	_mac_probe_sha256 = ""
	_mac_manifest = {}
	_mac_manifest_sha256 = ""
	_mac_export_preset = null
	_mac_template_path = ""
	_mac_experimental = false
	if features.has("macos") and not is_debug:
		# The Mac reference benchmark needs only this fixed probe, not an NK-3 receipt.
		var probe := ProjectSettings.globalize_path("res://").path_join(SOURCES["session_probe.gd"])
		_mac_probe_sha256 = FileAccess.get_sha256(probe)
		if _mac_probe_sha256.length() != 64:
			push_error("Cannot read the Mac reference session probe")
			return
		add_file("res://native/kernel/qualification/session_probe.gd", FileAccess.get_file_as_bytes(probe), false)
		# Ordinary Mac exports remain reference-only. This switch is for an
		# explicitly prepared experimental package on the qualified editor.
		if OS.get_environment("OPENRC_EXPERIMENTAL_NATIVE_MACOS_PACKAGE") == "1":
			_mac_experimental = true
			var parser := JSON.new()
			var manifest_file := FileAccess.open(MAC_MANIFEST, FileAccess.READ)
			if manifest_file == null or manifest_file.get_length() <= 0 or manifest_file.get_length() > 4 * 1024 * 1024:
				_fail("Prepare the experimental Mac native package before export")
				return
			var bytes := manifest_file.get_buffer(manifest_file.get_length())
			manifest_file.close()
			_mac_manifest_sha256 = _bytes_sha256(bytes)
			if bytes.is_empty() or _mac_manifest_sha256 != FileAccess.get_sha256(MAC_MANIFEST) \
					or parser.parse(bytes.get_string_from_utf8()) != OK \
					or typeof(parser.data) != TYPE_DICTIONARY:
				_fail("Prepare the experimental Mac native package before export")
				return
			_mac_manifest = parser.data
			_mac_export_preset = get_export_preset()
			if is_instance_valid(_mac_export_preset):
				var template: Variant = _mac_export_preset.get("custom_template/release")
				if typeof(template) == TYPE_STRING: _mac_template_path = template
			if not _mac_inputs_match():
				_fail("Experimental Mac native package inputs differ from the verified manifest")
				return
			add_file(MAC_MANIFEST, bytes, false)
			for name: String in MAC_DIAGNOSTICS:
				if name == "session_probe.gd": continue
				var path := ProjectSettings.globalize_path("res://").path_join(SOURCES[name])
				add_file("res://native/kernel/qualification/" + name, FileAccess.get_file_as_bytes(path), false)
			_mac_pair_marker("BEGIN")
		return
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


func _bytes_sha256(bytes: PackedByteArray) -> String:
	if bytes.is_empty(): return ""
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK or context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode()


func _mac_pair_marker(phase: String) -> void:
	var pair: Variant = _mac_manifest.get("engine_pair")
	if typeof(pair) == TYPE_DICTIONARY:
		print("OPENRC_MAC_PAIR_EXPORT_" + phase + " " + pair.editor_sha256 + " " + pair.export_template_sha256)


func _sha(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or value.length() != 64: return false
	for index: int in value.length():
		var code: int = value.unicode_at(index)
		if not (code >= 48 and code <= 57) and not (code >= 97 and code <= 102): return false
	return true


func _mac_pair_matches(row: Dictionary) -> bool:
	return _mac_pair_matches_with_preset(row, get_export_preset())


func _mac_pair_matches_with_preset(row: Dictionary, preset: Object) -> bool:
	var engine: Variant = row.get("engine")
	var provenance: Variant = engine.get("research_engine") if typeof(engine) == TYPE_DICTIONARY else null
	var pair: Variant = _mac_manifest.get("engine_pair")
	if provenance == null and pair == null: return true # Existing official-engine route.
	if typeof(engine) != TYPE_DICTIONARY or typeof(provenance) != TYPE_DICTIONARY \
			or typeof(pair) != TYPE_DICTIONARY or pair.size() != 10 or pair.get("format") != MAC_PAIR_FORMAT:
		return false
	if not _sha(_mac_manifest.get("export_plugin_sha256")) \
			or FileAccess.get_sha256(PLUGIN_SOURCE) != _mac_manifest.export_plugin_sha256: return false
	for key: String in ["editor_sha256", "template_sha256", "editor_receipt_sha256", "template_receipt_sha256",
			"pair_receipt_sha256", "export_template_sha256", "source_archive_sha256", "source_catalog_sha256"]:
		if not _sha(pair.get(key)): return false
	var patches: Variant = provenance.get("ordered_patches")
	if provenance.get("scope") != RESEARCH_SCOPE or provenance.get("runtime_version") != row.get("engine_version") \
			or engine.get("sha256") != row.get("engine_sha256") or pair.editor_sha256 != row.get("engine_sha256") \
			or pair.editor_receipt_sha256 != provenance.get("build_receipt_sha256") \
			or pair.source_archive_sha256 != provenance.get("source_archive_sha256") \
			or pair.source_catalog_sha256 != provenance.get("source_catalog_sha256") \
			or typeof(patches) != TYPE_ARRAY or typeof(pair.get("patch_sha256")) != TYPE_ARRAY \
			or patches.is_empty() or patches.size() > 64 or patches.size() != pair.patch_sha256.size():
		return false
	for index: int in range(patches.size()):
		if typeof(patches[index]) != TYPE_DICTIONARY or not _sha(pair.patch_sha256[index]) \
				or patches[index].get("sha256") != pair.patch_sha256[index]: return false
	if not is_instance_valid(preset) or not is_instance_valid(_mac_export_preset) \
			or preset.get_instance_id() != _mac_export_preset.get_instance_id(): return false
	var template: Variant = preset.get("custom_template/release")
	if typeof(template) != TYPE_STRING or template.is_empty() or template != _mac_template_path \
			or preset.get("binary_format/architecture") != "arm64" \
			or FileAccess.get_sha256(template) != pair.export_template_sha256 \
			or FileAccess.get_sha256(OS.get_executable_path()) != pair.editor_sha256:
		return false
	return true


func _mac_inputs_match() -> bool:
	if _mac_manifest.get("format") != "openrc-macos-native-kernel-package-v1" \
			or _mac_manifest.get("platform") != "macos" or _mac_manifest.get("architecture") != "arm64" \
			or _mac_manifest.get("engine_version") != Engine.get_version_info().string \
			or _mac_manifest.get("solver_sha256") != FlightLog.solver_identity() \
			or _mac_manifest_sha256.is_empty() or FileAccess.get_sha256(MAC_MANIFEST) != _mac_manifest_sha256:
		return false
	var receipt: Variant = _mac_manifest.get("native_receipt")
	if typeof(receipt) != TYPE_DICTIONARY or typeof(receipt.get("platforms")) != TYPE_DICTIONARY:
		return false
	var row: Variant = receipt.platforms.get("macos")
	if typeof(row) != TYPE_DICTIONARY or row.get("qualification_scope") != "macos-arm64-fixed-wing-experimental-v1" \
			or row.get("platform") != "macos" or row.get("architecture") != "arm64" \
			or typeof(row.get("mirrored_sources")) != TYPE_DICTIONARY or row.mirrored_sources.is_empty() \
			or row.get("engine_sha256") != FileAccess.get_sha256(OS.get_executable_path()) \
			or row.get("binary_sha256") != FileAccess.get_sha256("res://native/kernel/libopenrc_native_kernel.dylib"):
		return false
	if not _mac_pair_matches(row): return false
	for name: Variant in row.mirrored_sources:
		if typeof(name) != TYPE_STRING or not name.begins_with("app/") \
				or FileAccess.get_sha256("res://" + name.trim_prefix("app/")) != row.mirrored_sources[name]:
			return false
	var diagnostics: Variant = _mac_manifest.get("qualification_sources")
	if typeof(diagnostics) != TYPE_DICTIONARY or diagnostics.size() != MAC_DIAGNOSTICS.size():
		return false
	for name: String in MAC_DIAGNOSTICS:
		var path := ProjectSettings.globalize_path("res://").path_join(SOURCES[name])
		if diagnostics.get(name) != FileAccess.get_sha256(path): return false
	return true


func _export_end() -> void:
	var mac_probe_ok := _mac_probe_sha256.is_empty() or FileAccess.get_sha256(ProjectSettings.globalize_path("res://").path_join(SOURCES["session_probe.gd"])) == _mac_probe_sha256
	if not mac_probe_ok:
		push_error("Mac reference session probe changed during export")
	_mac_probe_sha256 = ""
	if not _manifest.is_empty() and not _inputs_match():
		_fail("NK-3 source or binary changed during export")
	if not _mac_manifest.is_empty():
		if not _mac_inputs_match():
			_fail("Experimental Mac native sources or binary changed during export")
		elif mac_probe_ok:
			_mac_pair_marker("END")
	_manifest = {}
	_mac_manifest = {}
	_mac_manifest_sha256 = ""
	_mac_export_preset = null
	_mac_template_path = ""
	_mac_experimental = false


func _fail(message: String) -> void:
	push_error(message)
	add_file(MANIFEST, "{}".to_utf8_buffer(), false)
	if _mac_experimental: add_file(MAC_MANIFEST, "{}".to_utf8_buffer(), false)
	_manifest = {}

extends Node

const PerformanceProbe := preload("res://research/glow-engines/performance_probe.gd")
const BUILD_MANIFEST_PATH := "res://research/glow-engines/release_probe_build_manifest.json"


func _ready() -> void:
	var manifest_bytes: PackedByteArray = FileAccess.get_file_as_bytes(BUILD_MANIFEST_PATH)
	if manifest_bytes.is_empty():
		printerr("Wrapped release performance probe has no embedded source manifest")
		get_tree().quit(2)
		return
	var parsed: Variant = JSON.parse_string(manifest_bytes.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		printerr("Wrapped release performance probe source manifest is invalid")
		get_tree().quit(2)
		return
	var manifest: Dictionary = parsed
	if not manifest.has("source_hashes") or not manifest.has("input_hashes") or not manifest.has("source_tree_sha256") or not manifest.has("input_tree_sha256"):
		printerr("Wrapped release performance probe source manifest is incomplete")
		get_tree().quit(2)
		return
	var probe: SceneTree = PerformanceProbe.new()
	probe.runtime_pack_path = "embedded"
	probe.runtime_mode = "wrapped_exported_release"
	probe.release_manifest = manifest
	probe.release_manifest_sha256 = _sha256_bytes(manifest_bytes)
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	var preflight_only: bool = user_args.has("--extended-preflight")
	var extended_glow: bool = user_args.has("--extended-glow") or preflight_only
	for arg: String in user_args:
		if arg.begins_with("--repo-root="):
			probe.repository_root_override = arg.trim_prefix("--repo-root=")
		elif arg.begins_with("--runtime-mode="):
			probe.runtime_mode = arg.trim_prefix("--runtime-mode=")
	probe._initialize()
	if preflight_only:
		var preflight: Dictionary = probe.report.get("extended_glow_preflight", {})
		if not preflight.get("ok", false) or preflight.get("measurements_collected", true) != false:
			printerr("Wrapped release probe did not complete an untimed extended preflight")
			probe.free()
			get_tree().quit(1)
			return
		print("WRAPPED_RELEASE_EXTENDED_PREFLIGHT scenarios=", preflight.get("scenarios", []).size(), " timing_collected=false")
		probe.free()
		get_tree().quit(0)
		return
	if not probe.report.has("summary"):
		printerr("Wrapped release performance probe did not produce a summary")
		probe.free()
		get_tree().quit(1)
		return
	if extended_glow:
		var extended: Dictionary = probe.report.get("extended_glow", {})
		if not extended.get("ok", false) or extended.get("gate_500us_applies", true) != false:
			printerr("Wrapped release probe did not complete separate extended glow diagnostics")
			probe.free()
			get_tree().quit(1)
			return
	print("WRAPPED_RELEASE_FEATURES debug=", OS.has_feature("debug"), " release=", OS.has_feature("release"))
	print("WRAPPED_RELEASE_SUMMARY=", JSON.stringify(probe.report.summary, "\t", true, true))
	if extended_glow:
		print("WRAPPED_RELEASE_EXTENDED_GLOW scenarios=", probe.report.extended_glow.scenarios.size(), " gate_500us_applies=false")
	probe.free()
	get_tree().quit(0)


func _sha256_bytes(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

## AS-09: preserve the verified authoring bytes alongside Godot's compiled/imported resources.
## These proofs identify exporter inputs; they do not claim byte identity with platform artifacts.
@tool
extends EditorExportPlugin

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const MARKER := "res://data/aircraft_models/package_proofs.json"


func _get_name() -> String:
	return "aircraft_contract_proofs"


func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	var registry: Script = load("res://aircraft/model_registry.gd")
	var sources: Dictionary = {}
	for family: String in Catalog.airplane_visual_families():
		var result: Dictionary = registry.describe(family)
		if not result.get("ok", false):
			push_error("Cannot export an invalid aircraft model: " + str(result.get("errors", [])))
			add_file(MARKER, "{}".to_utf8_buffer(), false)
			return
		var manifest: Dictionary = result.manifest
		for record: Dictionary in [manifest.source_registry, manifest.geometry.source]:
			sources[str(record.path)] = true
		for key: String in ["authoring_sources", "dependencies"]:
			for record: Dictionary in manifest[key]:
				sources[str(record.path)] = true
	var paths: Array = sources.keys()
	paths.sort()
	var files: Dictionary = {}
	for source: String in paths:
		var source_path: String = source if source.begins_with("res://") else ProjectSettings.globalize_path("res://").path_join("../").path_join(source)
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(source_path)
		if bytes.is_empty():
			push_error("Cannot export missing aircraft source proof: " + source)
			add_file(MARKER, "{}".to_utf8_buffer(), false)
			return
		var proof: String = "res://data/aircraft_models/proofs/" + source.sha256_text() + ".bin"
		add_file(proof, bytes, false)
		files[source] = proof
	add_file(MARKER, (JSON.stringify({format = "openrc-aircraft-model-package v1", files = files}, "\t", true) + "\n").to_utf8_buffer(), false)

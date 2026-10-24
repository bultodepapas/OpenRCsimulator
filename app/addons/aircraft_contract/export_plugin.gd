## AS-09: preserve verified physical-model and presentation authoring bytes in exported packages.
## These proofs identify exporter inputs; they do not claim byte identity with platform artifacts.
@tool
extends EditorExportPlugin

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const AircraftCustomization := preload("res://render/aircraft_customization.gd")
const PresentationSources := preload("res://render/presentation_sources.gd")
const RotorcraftModel := preload("res://aircraft/hx700_model.gd")
const MODEL_MARKER := "res://data/aircraft_models/package_proofs.json"
const PRESENTATION_MARKER := "res://data/aircraft_customization_package.json"
const PRESENTATION_FORMAT := "openrc-aircraft-presentation-package v2"


func _get_name() -> String:
	return "aircraft_contract_proofs"


func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	# Godot remaps the imported GLB to a PackedScene. Rotor profile validation
	# also needs its reviewed authoring bytes, avoiding geometry analysis at launch.
	if FileAccess.get_sha256(RotorcraftModel.SCENE_PATH) != RotorcraftModel.GLB_SHA256:
		_fail_export("Cannot export an unverified HX-700 source model")
		return
	add_file(RotorcraftModel.SCENE_PATH, FileAccess.get_file_as_bytes(RotorcraftModel.SCENE_PATH), false)
	var registry: Script = load("res://aircraft/model_registry.gd")
	var model_sources: Dictionary = {}
	var manifests_by_family: Dictionary = {}
	var presentation_families: Dictionary = {}
	for family: String in Catalog.airplane_visual_families():
		var result: Dictionary = registry.describe(family)
		if not result.get("ok", false):
			_fail_export("Cannot export an invalid aircraft model: " + str(result.get("errors", [])))
			return
		var manifest: Dictionary = result.manifest
		for record: Dictionary in [manifest.source_registry, manifest.geometry.source]:
			model_sources[str(record.path)] = true
		for key: String in ["authoring_sources", "dependencies"]:
			for record: Dictionary in manifest[key]:
				model_sources[str(record.path)] = true
		# F4U-16: the registry verifies a selected livery's GLB and import sidecar on use.
		for record: Dictionary in manifest.get("liveries", []):
			model_sources[str(record.path)] = true
			model_sources[str(record.path) + ".import"] = true
		manifests_by_family[family] = result
	for aircraft_id: String in Catalog.ids():
		if Catalog.is_rotorcraft(aircraft_id):
			continue
		var family := Catalog.visual_family(aircraft_id)
		var result: Dictionary = manifests_by_family.get(family, {})
		if result.is_empty() or not result.get("ok", false):
			_fail_export("Cannot export presentation bindings without a validated model for " + aircraft_id)
			return
		var companion: Dictionary = AircraftCustomization.describe_for_model(aircraft_id, str(result.get("manifest_sha256", "")))
		if not companion.get("ok", false):
			_fail_export("Cannot export an invalid presentation companion for " + family + ": " + str(companion.get("errors", [])))
			return
		var bindings: Dictionary = companion.get("bindings", {})
		var source_check: Dictionary = PresentationSources.validate(
			bindings.get("presentation_sources"), bindings.get("presentation_engine_version"), int(bindings.get("source_proof_version", 1)))
		if not source_check.get("ok", false):
			_fail_export("Cannot export an invalid presentation source pin for " + family + ": " + str(source_check.get("errors", [])))
			return
		for source_record: Dictionary in bindings.presentation_sources:
			presentation_families[str(source_record.path)] = true
	var model_paths: Array = model_sources.keys()
	model_paths.sort()
	var model_files: Dictionary = {}
	for source: String in model_paths:
		var source_path: String = source if source.begins_with("res://") else ProjectSettings.globalize_path("res://").path_join("../").path_join(source)
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(source_path)
		if bytes.is_empty():
			_fail_export("Cannot export missing aircraft source proof: " + source)
			return
		var proof: String = registry._expected_proof_path(source)
		add_file(proof, bytes, false)
		model_files[source] = proof
	add_file(MODEL_MARKER, (JSON.stringify({format = "openrc-aircraft-model-package v1", files = model_files}, "\t", true) + "\n").to_utf8_buffer(), false)
	var presentation_files := _collect_presentation_proofs(presentation_families)
	if not bool(presentation_files.get("ok", false)):
		_fail_export("Cannot export presentation proofs: " + str(presentation_files.get("error", "invalid closed source set")))
		return
	var presentation_marker := {"format": PRESENTATION_FORMAT, "files": presentation_files.files}
	add_file(PRESENTATION_MARKER, (JSON.stringify(presentation_marker, "\t", true) + "\n").to_utf8_buffer(), false)


func _collect_presentation_proofs(family_sources: Dictionary) -> Dictionary:
	if family_sources.size() != PresentationSources.paths_for_version(2).size():
		return {"ok": false, "error": "validated companions do not cover the exact versioned presentation sources"}
	var files := {}
	for source_path: String in PresentationSources.paths_for_version(2):
		if not family_sources.has(source_path):
			return {"ok": false, "error": "validated companions omit " + source_path}
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(source_path)
		if bytes.is_empty():
			return {"ok": false, "error": "presentation authoring source is missing: " + source_path}
		var proof_path := PresentationSources.expected_proof_path(source_path)
		if proof_path.is_empty():
			return {"ok": false, "error": "cannot compute deterministic proof path for " + source_path}
		add_file(proof_path, bytes, false)
		files[source_path] = proof_path
	return {"ok": true, "files": files}


func _fail_export(message: String) -> void:
	push_error(message)
	add_file(MODEL_MARKER, "{}".to_utf8_buffer(), false)
	add_file(PRESENTATION_MARKER, "{}".to_utf8_buffer(), false)

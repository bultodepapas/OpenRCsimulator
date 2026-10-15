## Export the exact native catalog visuals as self-contained GLB assets for the site.
## Run with the pinned Godot version, --path app, and optional -- --out-dir=<path>.
extends SceneTree

const Builder := preload("res://render/airplane.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")

const MODEL_SPECS: Array[Dictionary] = [
	{"key": "stik", "id": "jensen-das-ugly-stik-60"},
	{"key": "extra", "id": "gp-extra-300s-60"},
	{"key": "mustang", "id": "p51d-mustang-120"},
	{"key": "jet", "id": "sebart-avanti-s-a200-p100rx"},
	{"key": "timber", "id": "turbo-lumber-evolution"},
	{"key": "heli", "id": "xcell-60-research"},
]

const SOURCE_FILES: Array[String] = [
	"app/render/airplane.gd",
	"app/app_state/aircraft_catalog.gd",
	"app/aircraft/model_registry.gd",
	"app/aircraft/ugly_stik_model.gd",
	"app/aircraft/ugly_stik_geometry.gd",
	"app/aircraft/ugly_stik_finish.gd",
	"app/aircraft/ugly_stik_appearance.gd",
	"app/aircraft/ugly_stik_equipment.gd",
	"app/aircraft/ugly_stik_controls.gd",
	"app/aircraft/ugly_stik_fracture.gd",
	"app/aircraft/ugly_stik_gear_flex.gd",
	"app/aircraft/ugly_stik_grain.res",
	"app/aircraft/extra_300s_model.gd",
	"app/aircraft/extra_300s_geometry.gd",
	"app/aircraft/extra_300s_finish.gd",
	"app/aircraft/extra_300s_appearance.gd",
	"app/aircraft/p51d_model.gd",
	"app/aircraft/p51d_geometry.gd",
	"app/aircraft/p51d_finish.gd",
	"app/aircraft/p51d_appearance.gd",
	"app/aircraft/avanti_s_model.gd",
	"app/aircraft/avanti_s_geometry.gd",
	"app/aircraft/avanti_s_blender_geometry.gd",
	"app/aircraft/retractable_model.gd",
	"app/aircraft/timber_model.gd",
	"app/aircraft/timber_geometry.gd",
	"app/aircraft/imported_model.gd",
	"app/aircraft/imported_model_contract.gd",
	"app/aircraft/model_manifest.gd",
	"app/aircraft/hx700_model.gd",
	"app/data/aircraft_models/jensen-das-ugly-stik-60.json",
	"app/data/aircraft_models/gp-extra-300s-60.json",
	"app/data/aircraft_models/p51d-mustang-120.json",
	"app/data/aircraft_models/sebart-avanti-s-a200-p100rx.json",
	"app/data/aircraft_models/turbo-lumber-evolution.json",
	"app/data/aircraft/jensen_ugly_stik_60.json",
	"app/data/aircraft/gp_extra_300s_60.json",
	"app/data/aircraft/p51d_mustang_120.json",
	"app/data/aircraft/sebart_avanti_s_a200.json",
	"app/data/aircraft/turbo_lumber_evolution.json",
	"app/assets/aircraft/avanti-s-a200/avanti_s.glb",
	"app/assets/aircraft/avanti-s-a200/avanti_s.glb.import",
	"app/assets/aircraft/turbo-lumber-evolution/timber.glb",
	"app/assets/aircraft/turbo-lumber-evolution/timber.glb.import",
	"app/assets/aircraft/hx-700/hx-700.glb",
	"app/assets/aircraft/hx-700/hx-700.glb.import",
]

const GLB_IMAGE_FORMAT := "Lossy WebP"
const GLB_LOSSY_QUALITY := 0.9
const ROOT_NODE_MODE := GLTFDocument.ROOT_NODE_MODE_SINGLE_ROOT
const VISIBILITY_MODE := GLTFDocument.VISIBILITY_MODE_EXCLUDE

var output_dir := ""
var repo_root := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	repo_root = ProjectSettings.globalize_path("res://..").simplify_path()
	output_dir = repo_root.path_join("site/assets/models")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out-dir="):
			output_dir = argument.trim_prefix("--out-dir=").simplify_path()
	if output_dir.is_empty() or DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		push_error("Provide a writable output directory for the GLB assets.")
		quit(1)
		return

	var version: Dictionary = Engine.get_version_info()
	print("WEB_MODEL_EXPORTER|engine=%s|image_format=%s|lossy_quality=%.2f|root_node_mode=single_root|visibility=exclude_hidden" % [version.get("string", "unknown"), GLB_IMAGE_FORMAT, GLB_LOSSY_QUALITY])
	var provenance_hash := _source_closure_sha256()
	if provenance_hash.is_empty():
		quit(1)
		return
	print("EXPORT_INPUTS_SHA256|%s" % provenance_hash)

	var stage := Node3D.new()
	stage.name = "web_model_export_stage"
	root.add_child(stage)
	for spec: Dictionary in MODEL_SPECS:
		var model_id := str(spec.id)
		var model_key := str(spec.key)
		if Catalog.entry(model_id).is_empty():
			push_error("Web model export ID is absent from the aircraft catalog: " + model_id)
			quit(1)
			return
		var model: Dictionary = Builder.build(model_id)
		var airplane := model.get("root") as Node3D
		if model.is_empty() or airplane == null:
			push_error("The native aircraft builder failed for: " + model_id)
			quit(1)
			return

		stage.add_child(airplane)
		await process_frame
		var bounds := _bounds(airplane, Transform3D.IDENTITY)
		if bounds.size.length_squared() <= 0.0:
			push_error("The catalog visual has no visible mesh bounds: " + model_id)
			quit(1)
			return
		var original_position := airplane.position
		airplane.position = original_position - bounds.get_center()

		var expected_names: Array[String] = []
		_append_node_names(airplane, expected_names)
		var output_path := output_dir.path_join(model_key + ".glb")
		var document := GLTFDocument.new()
		document.image_format = GLB_IMAGE_FORMAT
		document.lossy_quality = GLB_LOSSY_QUALITY
		document.root_node_mode = ROOT_NODE_MODE
		document.visibility_mode = VISIBILITY_MODE
		var state := GLTFState.new()
		var result := document.append_from_scene(airplane, state)
		if result != OK:
			push_error("Could not encode native model '%s' as glTF: %s" % [model_id, error_string(result)])
			quit(1)
			return
		result = document.write_to_filesystem(state, output_path)
		if result != OK or not FileAccess.file_exists(output_path):
			push_error("Could not write model GLB '%s': %s" % [output_path, error_string(result)])
			quit(1)
			return

		var bytes := FileAccess.get_file_as_bytes(output_path)
		var model_manifest_hash := str(model.get("model_manifest_sha256", ""))
		print("MODEL|%s|%s|bytes=%d|sha256=%s|manifest_sha256=%s|node_count=%d|mesh_nodes=%d|node_names_sha256=%s|bounds_min=%s|bounds_size=%s" % [
			model_key, model_id, bytes.size(), _sha256(bytes), model_manifest_hash,
			expected_names.size(), _mesh_node_count(airplane), _node_names_sha256(expected_names),
			_vector_string(bounds.position), _vector_string(bounds.size)])

		stage.remove_child(airplane)
		airplane.free()
		await process_frame

	print("WEB_MODEL_EXPORT_OK|models=%d|output=%s" % [MODEL_SPECS.size(), output_dir])
	quit(0)


func _bounds(node: Node3D, parent_transform: Transform3D) -> AABB:
	var transform: Transform3D = parent_transform * node.transform
	var result := AABB()
	if node is MeshInstance3D and node.visible and node.mesh != null:
		result = transform * node.get_aabb()
	for child: Node in node.get_children():
		if child is Node3D and child.visible:
			var child_bounds := _bounds(child, transform)
			if child_bounds.size.length_squared() > 0.0:
				result = child_bounds if result.size.length_squared() == 0.0 else result.merge(child_bounds)
	return result


func _append_node_names(node: Node, names: Array[String]) -> void:
	if node is Node3D and not (node as Node3D).is_visible_in_tree():
		return
	names.append(str(node.name))
	for child: Node in node.get_children():
		_append_node_names(child, names)


func _mesh_node_count(node: Node) -> int:
	if node is Node3D and not (node as Node3D).is_visible_in_tree():
		return 0
	var count := 1 if node is MeshInstance3D and node.mesh != null else 0
	for child: Node in node.get_children():
		count += _mesh_node_count(child)
	return count


func _node_names_sha256(names: Array[String]) -> String:
	var sorted_names := PackedStringArray()
	for node_name: String in names:
		sorted_names.append(node_name)
	sorted_names.sort()
	return _sha256("\n".join(sorted_names).to_utf8_buffer())


func _source_closure_sha256() -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		push_error("Could not start source provenance hash.")
		return ""
	var paths := SOURCE_FILES.duplicate()
	paths.append("site/export_web_models.gd")
	for relative_path: String in paths:
		var absolute_path := repo_root.path_join(relative_path)
		if not FileAccess.file_exists(absolute_path):
			push_error("Source input is missing for provenance: " + relative_path)
			return ""
		if context.update(relative_path.to_utf8_buffer()) != OK or context.update(FileAccess.get_file_as_bytes(absolute_path)) != OK:
			push_error("Could not hash source input: " + relative_path)
			return ""
	return context.finish().hex_encode()


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK or context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode()


func _vector_string(value: Vector3) -> String:
	return "%.9f,%.9f,%.9f" % [value.x, value.y, value.z]

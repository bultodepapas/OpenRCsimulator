extends SceneTree

const FieldLoader = preload("res://data/field_loader.gd")
const FieldBuilder = preload("res://render/field.gd")

var _failures: int = 0
var _checks: int = 0
var _stages: PackedStringArray = PackedStringArray()
var _cancel_stages: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	_run()


func _run() -> void:
	var loaded: Dictionary = FieldLoader.load_from()
	_check("default field fixture loads", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if not bool(loaded.get("ok", false)):
		_finish()
		return
	var field: Dictionary = loaded.field
	var lighting: Dictionary = {}
	var synchronous: Node3D = FieldBuilder.build(field, lighting)
	var synchronous_structure: Dictionary = _node_signature(synchronous, false)
	var synchronous_metadata: Dictionary = _metadata_tree_signature(synchronous)
	var staged: Node3D = await FieldBuilder.build_staged(field, lighting, [],
		Callable(self, "_continue_at_checkpoint"))
	_check("staged build returns a field", staged != null)
	if staged != null:
		var staged_structure: Dictionary = _node_signature(staged, false)
		var staged_metadata: Dictionary = _metadata_tree_signature(staged)
		_check("sync and staged node structure, transforms, and mesh arrays match",
			synchronous_structure == staged_structure,
			_first_mismatch(synchronous_structure, staged_structure, "Field"))
		_check("sync and staged metadata match apart from build timing",
			synchronous_metadata == staged_metadata,
			_first_mismatch(synchronous_metadata, staged_metadata, "Field.metadata"))
		var staged_work_ms: Variant = staged.get_meta("field_build_ms", null)
		_check("staged field reports synchronous work time separately from yields",
			staged_work_ms is float and is_finite(float(staged_work_ms)) and float(staged_work_ms) >= 0.0,
			str(staged_work_ms))
	_check("field checkpoints run in order through final landscape attachment",
		not _stages.is_empty() and _stages[0] == "Field ground"
		and _stages.has("Flight cue shadows")
		and _stages.has("Projected shadows")
		and _stages[_stages.size() - 1] == "Attaching landscape", str(_stages))
	if synchronous != null:
		synchronous.free()
	if staged != null:
		staged.free()
	await process_frame
	await process_frame

	var objects_before_cancel: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var cancelled: Node3D = await FieldBuilder.build_staged(field, lighting, [],
		Callable(self, "_cancel_after_first_surface"))
	await process_frame
	var objects_after_cancel: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	_check("false checkpoint cancels after a ground surface and returns null",
		cancelled == null and _cancel_stages.size() == 3
		and _cancel_stages[0] == "Field ground" and _cancel_stages[1] == "Field ground"
		and _cancel_stages[2] == "Field trees", str(_cancel_stages))
	_check("cancelled detached field nodes and resources are disposed",
		objects_after_cancel <= objects_before_cancel + 1,
		"objects before=%d after=%d" % [objects_before_cancel, objects_after_cancel])
	_finish()


func _continue_at_checkpoint(stage: String) -> bool:
	_stages.append(stage)
	await process_frame
	return true


func _cancel_after_first_surface(stage: String) -> bool:
	_cancel_stages.append(stage)
	await process_frame
	return _cancel_stages.size() < 3


func _node_signature(node: Node, include_metadata: bool) -> Dictionary:
	var children: Array[Dictionary] = []
	for child: Node in node.get_children():
		children.append(_node_signature(child, include_metadata))
	var signature: Dictionary = {
		"name": _stable_node_name(node),
		"class": node.get_class(),
		"children": children,
	}
	if node is Node3D:
		var spatial: Node3D = node as Node3D
		signature["transform"] = spatial.transform
		signature["visible"] = spatial.visible
	if node is MeshInstance3D:
		var instance: MeshInstance3D = node as MeshInstance3D
		signature["mesh"] = _mesh_signature(instance.mesh)
		signature["material_override"] = _stable_value(instance.material_override)
	if include_metadata:
		signature["metadata"] = _metadata_signature(node)
	return signature


func _mesh_signature(mesh: Mesh) -> Dictionary:
	if mesh == null:
		return {}
	var surface_arrays: Array = []
	var surface_materials: Array = []
	for surface_index: int in range(mesh.get_surface_count()):
		surface_arrays.append(mesh.surface_get_arrays(surface_index))
		surface_materials.append(_stable_value(mesh.surface_get_material(surface_index)))
	return {
		"class": mesh.get_class(),
		"aabb": mesh.get_aabb(),
		"surface_arrays": surface_arrays,
		"surface_materials": surface_materials,
	}


func _metadata_signature(node: Node) -> Dictionary:
	var signature: Dictionary = {}
	for key: Variant in node.get_meta_list():
		if _is_timing_key(key):
			continue # Build and scene instrumentation timings intentionally differ between runs.
		signature[str(key)] = _stable_value(node.get_meta(key))
	return signature


func _metadata_tree_signature(node: Node) -> Dictionary:
	var child_metadata: Array[Dictionary] = []
	for child: Node in node.get_children():
		child_metadata.append(_metadata_tree_signature(child))
	return {"metadata": _metadata_signature(node), "children": child_metadata}


func _stable_value(value: Variant) -> Variant:
	if typeof(value) == TYPE_FLOAT and is_nan(float(value)):
		return "<nan>"
	if value is Node:
		var node: Node = value as Node
		return {"class": node.get_class(), "name": _stable_node_name(node)}
	if value is ShaderMaterial:
		var shader_material: ShaderMaterial = value as ShaderMaterial
		return {"class": value.get_class(), "shader": _stable_value(shader_material.shader)}
	if value is Shader:
		var shader: Shader = value as Shader
		return {"class": value.get_class(), "path": shader.resource_path, "code": shader.code}
	if value is Resource:
		var resource: Resource = value as Resource
		return {"class": resource.get_class(), "path": resource.resource_path}
	if value is RefCounted:
		var ref_counted: RefCounted = value as RefCounted
		var script: Script = ref_counted.get_script() as Script
		return {"class": ref_counted.get_class(), "script": script.resource_path if script != null else ""}
	if value is Dictionary:
		var stable_dictionary: Dictionary = {}
		for key: Variant in value:
			if _is_timing_key(key):
				continue
			stable_dictionary[key] = _stable_value(value[key])
		return stable_dictionary
	if value is Array:
		var stable_array: Array = []
		for item: Variant in value:
			stable_array.append(_stable_value(item))
		return stable_array
	return value


func _stable_node_name(node: Node) -> String:
	var node_name: String = str(node.name)
	return "<auto>" if node_name.begins_with("@") else node_name


func _is_timing_key(key: Variant) -> bool:
	var name: String = str(key).to_lower()
	return name == "field_build_ms" or name == "timing_ms" or name.ends_with("_ms") or name.ends_with("_usec")


func _first_mismatch(left: Variant, right: Variant, path: String) -> String:
	if typeof(left) != typeof(right):
		return "%s: %s != %s" % [path, type_string(typeof(left)), type_string(typeof(right))]
	if left is Dictionary:
		var left_dictionary: Dictionary = left
		var right_dictionary: Dictionary = right
		if left_dictionary.size() != right_dictionary.size():
			return "%s: dictionary sizes %d != %d" % [path, left_dictionary.size(), right_dictionary.size()]
		for key: Variant in left_dictionary:
			if not right_dictionary.has(key):
				return "%s.%s: missing from staged output" % [path, str(key)]
			var mismatch := _first_mismatch(left_dictionary[key], right_dictionary[key], "%s.%s" % [path, str(key)])
			if not mismatch.is_empty():
				return mismatch
		return ""
	if left is Array:
		var left_array: Array = left
		var right_array: Array = right
		if left_array.size() != right_array.size():
			return "%s: array sizes %d != %d" % [path, left_array.size(), right_array.size()]
		for index: int in range(left_array.size()):
			var mismatch := _first_mismatch(left_array[index], right_array[index], "%s[%d]" % [path, index])
			if not mismatch.is_empty():
				return mismatch
		return ""
	return "" if left == right else "%s: %s != %s" % [path, _brief(left), _brief(right)]


func _brief(value: Variant) -> String:
	if value is PackedVector2Array or value is PackedVector3Array or value is PackedColorArray \
			or value is PackedFloat32Array or value is PackedFloat64Array or value is PackedInt32Array \
			or value is PackedInt64Array:
		return "%s(%d)" % [type_string(typeof(value)), value.size()]
	var text_value: String = str(value)
	return text_value.substr(0, 80)


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _finish() -> void:
	print("%d field staged build checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)

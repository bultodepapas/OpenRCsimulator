extends SceneTree

const FieldLoader = preload("res://data/field_loader.gd")
const FieldBuilder = preload("res://render/field.gd")
const Scenery = preload("res://scenery/scenery.gd")
const SceneryLoader = preload("res://scenery/scenery_loader.gd")
const BirdDirector = preload("res://scenery/birds/bird_director.gd")

var _reference_builder: Script = FieldBuilder
var _reference_scenery: Script = Scenery
var _failures: int = 0
var _checks: int = 0
var _stages: PackedStringArray = PackedStringArray()
var _cancel_stages: PackedStringArray = PackedStringArray()
var _scenery_checkpoints := 0
var _changing_field: Dictionary
var _changing_lighting: Dictionary
var _changing_exclusions: Array
var _changed_inputs := false


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--reference-scenery="):
			_reference_scenery = load(argument.trim_prefix("--reference-scenery="))
			if _reference_scenery == null:
				push_error("reference scenery builder could not load")
				quit(2)
				return
		if argument.begins_with("--reference-field="):
			_reference_builder = load(argument.trim_prefix("--reference-field="))
			if _reference_builder == null:
				push_error("reference field builder could not load")
				quit(2)
				return
	_run()


func _run() -> void:
	var loaded: Dictionary = FieldLoader.load_from()
	_check("default field fixture loads", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if not bool(loaded.get("ok", false)):
		_finish()
		return
	var field: Dictionary = loaded.field
	var lighting: Dictionary = {}
	var synchronous: Node3D = _reference_builder.build(field, lighting)
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
	_changing_field = field.duplicate(true)
	_changing_lighting = lighting.duplicate(true)
	_changing_exclusions = []
	var frozen_field: Node3D = await FieldBuilder.build_staged(_changing_field, _changing_lighting,
		_changing_exclusions, _change_field_inputs)
	_check("field input edits at a scenery checkpoint leave completed geometry unchanged",
		_changed_inputs and frozen_field != null and _node_signature(frozen_field, false) == synchronous_structure)
	_check("field input edits leave completed metadata unchanged",
		frozen_field != null and _metadata_tree_signature(frozen_field) == synchronous_metadata)
	if frozen_field != null: frozen_field.free()
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
	await _scenery_lifecycle(field, lighting)
	_finish()


func _scenery_lifecycle(field: Dictionary, lighting: Dictionary) -> void:
	var loaded: Dictionary = SceneryLoader.load_from(SceneryLoader.DEFAULT_PATH, field)
	_check("scenery fixture loads", loaded.get("ok", false))
	if not loaded.get("ok", false): return
	_scenery_matrix(field, loaded.scenery, lighting)
	var opts := {enabled = true, theme = "", quality = "high", audio = true, birds = true}
	var expected: Node3D = Scenery.build(field, loaded.scenery, opts, lighting)
	var geometry := _node_signature(expected, false)
	var metadata := _metadata_tree_signature(expected)
	expected.free()
	await process_frame
	await process_frame
	for target: String in ["Building scenery placements", "Building parked aircraft", "Building scenery trees",
			"Building scenery botanicals", "Building scenery cells", "Building scenery shadows"]:
		var before: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
		var job: RefCounted = Scenery.begin_build(field, loaded.scenery, opts, lighting)
		var units := 0
		while not Scenery.build_finished(job) and Scenery.next_build_stage(job) != target and units < 10000:
			Scenery.advance_build(job)
			units += 1
		_check("cancellation target is reached: " + target, not Scenery.build_finished(job) and units < 10000)
		# Exercise owned resources within the phase, not only an empty job before SETUP.
		Scenery.advance_build(job)
		var partial: WeakRef = weakref(job.root)
		Scenery.cancel_build(job)
		Scenery.cancel_build(job)
		_check("cancel frees detached scenery and refuses transfer: " + target,
			partial.get_ref() == null and Scenery.build_finished(job) and Scenery.take_build(job) == null)
		job = null
		partial = null
		await process_frame
		await process_frame
		_check("cancel releases scenery resources: " + target,
			int(Performance.get_monitor(Performance.OBJECT_COUNT)) <= before + 1)

	var abandoned: RefCounted = Scenery.begin_build(field, loaded.scenery, opts, lighting)
	Scenery.advance_build(abandoned)
	var abandoned_root: WeakRef = weakref(abandoned.root)
	abandoned = null
	_check("dropping an unfinished job frees its detached root", abandoned_root.get_ref() == null)

	var changing_field: Dictionary = field.duplicate(true)
	var changing_scenery: Dictionary = loaded.scenery.duplicate(true)
	var changing_options: Dictionary = opts.duplicate(true)
	var changing_lighting := lighting.duplicate(true)
	var changing_lake := {}
	var frozen: RefCounted = Scenery.begin_build(changing_field, changing_scenery, changing_options,
		changing_lighting, changing_lake)
	Scenery.advance_build(frozen) # setup samples shadow and bird conditions together
	var previous_preference: String = BirdDirector.preference
	var previous_serial: int = BirdDirector.preference_serial
	BirdDirector.set_preference("off" if previous_preference != "off" else "many")
	changing_field.pilot.north += 1000.0
	changing_scenery.groups.clear()
	changing_options.quality = "low"
	changing_options.audio = false
	changing_options.birds = false
	changing_lighting["sun_elevation_deg"] = -20.0
	changing_lake["invalid_after_begin"] = true
	var units := 0
	while not Scenery.build_finished(frozen) and units < 10000:
		Scenery.advance_build(frozen)
		units += 1
	BirdDirector.preference = previous_preference
	BirdDirector.preference_serial = previous_serial
	var completed: Node3D = Scenery.take_build(frozen)
	frozen = null
	_check("taken scene survives job release", is_instance_valid(completed) and units < 10000)
	if is_instance_valid(completed):
		_check("input and bird-preference edits between chunks cannot alter scenery geometry", _node_signature(completed, false) == geometry)
		_check("input and bird-preference edits between chunks cannot alter scenery metadata", _metadata_tree_signature(completed) == metadata)
		completed.free()

	var empty: Dictionary = loaded.scenery.duplicate(true)
	empty.groups.clear()
	var empty_root: Node3D = Scenery.build(field, empty, opts, lighting)
	_check("empty groups complete without an invalid group access", empty_root != null and empty_root.get_meta("stats").instances == 0)
	if empty_root != null: empty_root.free()
	await process_frame
	await process_frame
	var before_field_cancel: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	_scenery_checkpoints = 0
	var cancelled: Node3D = await FieldBuilder.build_staged(field, lighting, [], _cancel_inside_scenery)
	await process_frame
	await process_frame
	_check("field cancellation reaches the interior of scenery construction", cancelled == null and _scenery_checkpoints == 3)
	_check("field cancellation releases its detached scenery job",
		int(Performance.get_monitor(Performance.OBJECT_COUNT)) <= before_field_cancel + 1)
	var retried: Node3D = FieldBuilder.build(field, lighting)
	_check("a cancelled build does not prevent a complete retry", retried != null and retried.get_node_or_null("Scenery") != null)
	if retried != null: retried.free()


func _cancel_inside_scenery(stage: String) -> bool:
	if stage == "Building field scenery": _scenery_checkpoints += 1
	await process_frame
	return _scenery_checkpoints < 3


func _scenery_matrix(field: Dictionary, source: Dictionary, lighting: Dictionary) -> void:
	for tier: String in ["low", "balanced", "high"]:
		var definition := source.duplicate(true)
		# The same source identity can describe a different authored group order.
		if tier == "balanced": definition.groups.reverse()
		var opts := {theme = "summer" if tier == "low" else "temperate", quality = tier,
			audio = tier == "high", birds = tier != "low"}
		var expected: Node3D = _reference_scenery.build(field, definition, opts, lighting)
		var job: RefCounted = Scenery.begin_build(field, definition, opts, lighting)
		var units := 0
		while not Scenery.build_finished(job) and units < 10000:
			Scenery.advance_build(job)
			units += 1
		var actual: Node3D = Scenery.take_build(job)
		_check(tier + " ordered units preserve geometry, buffers and materials",
			actual != null and _node_signature(actual, false) == _node_signature(expected, false))
		_check(tier + " ordered units preserve metadata",
			actual != null and _metadata_tree_signature(actual) == _metadata_tree_signature(expected))
		if actual != null: actual.free()
		expected.free()


func _change_field_inputs(stage: String) -> bool:
	if stage == "Building field scenery" and not _changed_inputs:
		_changed_inputs = true
		_changing_field.surfaces.clear()
		_changing_field.objects.clear()
		_changing_lighting["sun_elevation_deg"] = -20.0
		_changing_exclusions.append({center = Vector2.ZERO, radius = 10000.0})
	await process_frame
	return true


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
	if node is MultiMeshInstance3D:
		var batch: MultiMesh = (node as MultiMeshInstance3D).multimesh
		signature["multimesh"] = {} if batch == null else {
			"format": batch.transform_format, "colors": batch.use_colors, "custom": batch.use_custom_data,
			"count": batch.instance_count, "visible_count": batch.visible_instance_count,
			"buffer": batch.buffer, "mesh": _mesh_signature(batch.mesh)}
	if node is GeometryInstance3D:
		var geometry: GeometryInstance3D = node as GeometryInstance3D
		signature["render"] = {"shadow": geometry.cast_shadow, "lod": geometry.lod_bias,
			"range_begin": geometry.visibility_range_begin, "range_end": geometry.visibility_range_end,
			"range_begin_margin": geometry.visibility_range_begin_margin,
			"range_end_margin": geometry.visibility_range_end_margin,
			"material_override": _stable_value(geometry.material_override)}
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
	if value is Material:
		var material: Material = value as Material
		var properties := {}
		for property: Dictionary in material.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_STORAGE:
				properties[str(property.name)] = _stable_value(material.get(property.name))
		return {"class": material.get_class(), "properties": properties}
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

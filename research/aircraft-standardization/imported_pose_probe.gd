extends SceneTree

const BUILDER_PATH := "res://aircraft/timber_model.gd"
const IMPORTED_MODEL_PATH := "res://aircraft/imported_model.gd"
const TRANSFORM_TOLERANCE := 0.000001

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var builder_source := _argument_value("--builder-source=")
	var builder: Script = null
	if builder_source.is_empty():
		builder = load(BUILDER_PATH) as Script
	else:
		var dynamic_builder := GDScript.new()
		dynamic_builder.source_code = FileAccess.get_file_as_string(builder_source)
		var load_error := dynamic_builder.reload()
		if load_error == OK:
			builder = dynamic_builder
	if builder == null:
		_failures.append("Could not load builder source " + (BUILDER_PATH if builder_source.is_empty() else builder_source))
		_finish({})
		return
	var imported_model := load(IMPORTED_MODEL_PATH) as Script
	var report: Dictionary = {
		"probe": "AS-09-10-imported-pose-v1",
		"godot_version": Engine.get_version_info().get("string", "unknown"),
		"builder_path": BUILDER_PATH if builder_source.is_empty() else builder_source,
		"tolerance": TRANSFORM_TOLERANCE,
		"states": {},
	}
	for state_name in ["neutral", "full_conventional", "full_flaps", "propeller_spin", "gear_spin_and_steer", "combined_full"]:
		var model_value: Variant = builder.call("build")
		if typeof(model_value) != TYPE_DICTIONARY:
			_failures.append("Builder did not return a model dictionary for " + state_name)
			continue
		var model: Dictionary = model_value
		var root := model.get("root") as Node3D
		if root == null:
			_failures.append("Builder model has no Node3D root for " + state_name)
			continue
		_apply_state(builder, imported_model, model, state_name)
		report["states"][state_name] = _capture_model(model)
		root.free()
	if _failures.is_empty() and report["states"].size() != 6:
		_failures.append("Not all six pose states were captured")
	var baseline_path := _argument_value("--baseline=")
	if not baseline_path.is_empty() and _failures.is_empty():
		var baseline := _read_json(baseline_path)
		if baseline.is_empty():
			_failures.append("Could not read baseline JSON: " + baseline_path)
		else:
			report["comparison"] = _compare_reports(baseline, report)
			if not bool(report["comparison"].get("ok", false)):
				_failures.append("Imported pose differs from the recorded legacy baseline")
	report["failures"] = _failures.duplicate()
	report["ok"] = _failures.is_empty()
	_finish(report)


func _apply_state(builder: Script, imported_model: Script, model: Dictionary, state_name: String) -> void:
	var zero_surfaces := {"aileron_right": 0.0, "aileron_left": 0.0, "elevator": 0.0, "rudder": 0.0}
	_apply_surfaces(builder, imported_model, model, zero_surfaces)
	_set_flaps(builder, imported_model, model, 0.0)
	match state_name:
		"neutral":
			return
		"full_conventional":
			_apply_surfaces(builder, imported_model, model, _full_surfaces(builder))
		"full_flaps":
			_set_flaps(builder, imported_model, model, 40.0)
		"propeller_spin":
			var propeller := model.get("propeller") as Node3D
			if propeller == null:
				_failures.append("Propeller node is missing")
			else:
				propeller.rotation.z = 0.73
		"gear_spin_and_steer":
			_set_gear(model, 0.61, -0.38)
		"combined_full":
			_apply_surfaces(builder, imported_model, model, _full_surfaces(builder))
			_set_flaps(builder, imported_model, model, 40.0)
			var combined_propeller := model.get("propeller") as Node3D
			if combined_propeller == null:
				_failures.append("Propeller node is missing in combined pose")
			else:
				combined_propeller.rotation.z = 0.73
			_set_gear(model, 0.61, -0.38)


func _full_surfaces(builder: Script) -> Dictionary:
	var throws: Dictionary = {}
	if builder.has_method("manual_throws_deg"):
		var value: Variant = builder.call("manual_throws_deg")
		if typeof(value) == TYPE_DICTIONARY:
			throws = value
	var aileron := float(throws.get("aileron", 25.0))
	var elevator := float(throws.get("elevator", 25.0))
	var rudder := float(throws.get("rudder", 25.0))
	return {
		"aileron_right": aileron,
		"aileron_left": -aileron,
		"elevator": elevator,
		"rudder": rudder,
	}


func _apply_surfaces(builder: Script, imported_model: Script, model: Dictionary, surfaces: Dictionary) -> void:
	if builder.has_method("apply_surfaces"):
		builder.call("apply_surfaces", model, surfaces)
	elif imported_model != null and imported_model.has_method("apply_surfaces"):
		imported_model.call("apply_surfaces", model, surfaces)
	else:
		_failures.append("No apply_surfaces implementation is available")


func _set_flaps(builder: Script, imported_model: Script, model: Dictionary, degrees: float) -> void:
	if builder.has_method("set_flaps"):
		builder.call("set_flaps", model, degrees)
	elif imported_model != null and imported_model.has_method("set_visual_surfaces"):
		imported_model.call("set_visual_surfaces", model, {"flap_left": degrees, "flap_right": degrees})
	else:
		_failures.append("No flap posing implementation is available")


func _set_gear(model: Dictionary, wheel_x: float, steering_y: float) -> void:
	var gear: Dictionary = model.get("gear", {})
	for role in ["left", "right", "tail"]:
		var wheel := gear.get(role) as Node3D
		if wheel == null:
			_failures.append("Gear wheel node is missing: " + role)
		else:
			wheel.rotation.x = wheel_x
	var steering := gear.get("steering") as Node3D
	if steering == null:
		_failures.append("Tailwheel steering node is missing")
	else:
		steering.rotation.y = steering_y


func _capture_model(model: Dictionary) -> Dictionary:
	var root := model.get("root") as Node3D
	var rows: Array[Dictionary] = []
	var overrides: Array[Dictionary] = []
	_collect_nodes(root, root, "", "", rows, overrides)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["path"]) < str(b["path"]))
	overrides.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if str(a["path"]) == str(b["path"]): return int(a["surface"]) < int(b["surface"])
		return str(a["path"]) < str(b["path"]))
	return {
		"aircraft_id": str(model.get("aircraft_id", "")),
		"root_name": str(root.name),
		"tree": rows,
		"material_overrides": overrides,
	}


func _collect_nodes(root: Node3D, node: Node, path: String, parent_path: String, rows: Array[Dictionary], overrides: Array[Dictionary]) -> void:
	var row: Dictionary = {
		"path": path,
		"name": str(node.name),
		"parent_path": parent_path,
		"class": node.get_class(),
	}
	if node is Node3D:
		var node3d := node as Node3D
		row["root_transform"] = _transform_array(_relative(root, node3d))
		row["local_transform"] = _transform_array(node3d.transform)
	var section_metadata := _section_metadata(node)
	if not section_metadata.is_empty():
		row["section_metadata"] = section_metadata
	if node is MeshInstance3D:
		_collect_material_overrides(node as MeshInstance3D, path, overrides)
	rows.append(row)
	for child in node.get_children():
		var child_path := str(child.name) if path.is_empty() else path + "/" + str(child.name)
		_collect_nodes(root, child, child_path, path, rows, overrides)


func _relative(root: Node3D, node: Node3D) -> Transform3D:
	var value := Transform3D.IDENTITY
	var cursor: Node = node
	while cursor != null and cursor != root:
		if cursor is Node3D:
			value = (cursor as Node3D).transform * value
		cursor = cursor.get_parent()
	return value


func _transform_array(value: Transform3D) -> Array[float]:
	return [
		value.basis.x.x, value.basis.x.y, value.basis.x.z,
		value.basis.y.x, value.basis.y.y, value.basis.y.z,
		value.basis.z.x, value.basis.z.y, value.basis.z.z,
		value.origin.x, value.origin.y, value.origin.z,
	]


func _section_metadata(node: Node) -> Dictionary:
	var output: Dictionary = {}
	var keys: Array[String] = []
	for key in node.get_meta_list():
		var key_name := str(key)
		keys.append(key_name)
	keys.sort()
	for key_name in keys:
		var value: Variant = node.get_meta(key_name)
		if key_name.to_lower().contains("section"):
			output[key_name] = _json_safe(value)
		elif typeof(value) == TYPE_DICTIONARY:
			for nested_key in value.keys():
				if str(nested_key).to_lower().contains("section"):
					output[str(nested_key)] = _json_safe(value[nested_key])
	return output


func _json_safe(value: Variant) -> Variant:
	match typeof(value):
		TYPE_VECTOR2:
			return [value.x, value.y]
		TYPE_VECTOR3:
			return [value.x, value.y, value.z]
		TYPE_COLOR:
			return [value.r, value.g, value.b, value.a]
		TYPE_ARRAY:
			var result: Array = []
			for item in value:
				result.append(_json_safe(item))
			return result
		TYPE_DICTIONARY:
			var result: Dictionary = {}
			for key in value.keys():
				result[str(key)] = _json_safe(value[key])
			return result
		TYPE_STRING, TYPE_STRING_NAME, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_NIL:
			return value
		_:
			return str(value)


func _collect_material_overrides(mesh_node: MeshInstance3D, path: String, output: Array[Dictionary]) -> void:
	if mesh_node.mesh == null:
		return
	for surface in mesh_node.mesh.get_surface_count():
		var override := mesh_node.get_surface_override_material(surface)
		if override == null:
			continue
		var source := mesh_node.mesh.surface_get_material(surface)
		var row: Dictionary = {
			"path": path,
			"surface": surface,
			"source_material": str(source.resource_name) if source != null else "",
			"override_material": str(override.resource_name),
			"override_class": override.get_class(),
		}
		if override is StandardMaterial3D:
			var standard := override as StandardMaterial3D
			row["grow"] = standard.grow
			row["grow_amount"] = standard.grow_amount
		output.append(row)


func _compare_reports(baseline: Dictionary, candidate: Dictionary) -> Dictionary:
	var differences: Array[Dictionary] = []
	var baseline_states: Dictionary = baseline.get("states", {})
	var candidate_states: Dictionary = candidate.get("states", {})
	var state_names: Array = baseline_states.keys()
	state_names.sort()
	for state_name in state_names:
		if not candidate_states.has(state_name):
			differences.append({"state": str(state_name), "kind": "missing_state"})
			continue
		_compare_state(str(state_name), baseline_states[state_name], candidate_states[state_name], differences)
	for state_name in candidate_states.keys():
		if not baseline_states.has(state_name):
			differences.append({"state": str(state_name), "kind": "unexpected_state"})
	return {
		"tolerance": TRANSFORM_TOLERANCE,
		"ok": differences.is_empty(),
		"difference_count": differences.size(),
		"differences": differences,
	}


func _compare_state(state_name: String, baseline: Dictionary, candidate: Dictionary, output: Array[Dictionary]) -> void:
	var baseline_nodes := _rows_by_path(baseline.get("tree", []))
	var candidate_nodes := _rows_by_path(candidate.get("tree", []))
	var paths: Array = baseline_nodes.keys()
	paths.sort()
	for path_value in paths:
		var path := str(path_value)
		if not candidate_nodes.has(path):
			output.append({"state": state_name, "path": path, "kind": "missing_node"})
			continue
		var expected: Dictionary = baseline_nodes[path]
		var actual: Dictionary = candidate_nodes[path]
		for key in ["name", "class", "parent_path"]:
			if expected.get(key) != actual.get(key):
				output.append({"state": state_name, "path": path, "kind": "tree_mismatch", "field": key,
					"baseline": expected.get(key), "candidate": actual.get(key)})
		if expected.has("root_transform") and actual.has("root_transform"):
			var error := _max_abs_difference(expected["root_transform"], actual["root_transform"])
			if error > TRANSFORM_TOLERANCE:
				output.append({"state": state_name, "path": path, "kind": "transform_mismatch", "max_abs_error": error})
		elif expected.has("root_transform") != actual.has("root_transform"):
			output.append({"state": state_name, "path": path, "kind": "transform_presence_mismatch"})
		if expected.get("section_metadata", {}) != actual.get("section_metadata", {}):
			output.append({"state": state_name, "path": path, "kind": "section_metadata_mismatch"})
	for path_value in candidate_nodes.keys():
		var path := str(path_value)
		if not baseline_nodes.has(path):
			output.append({"state": state_name, "path": path, "kind": "unexpected_node"})
	var expected_overrides: Array = baseline.get("material_overrides", [])
	var actual_overrides: Array = candidate.get("material_overrides", [])
	if expected_overrides != actual_overrides:
		output.append({"state": state_name, "kind": "material_override_mismatch",
			"baseline": expected_overrides, "candidate": actual_overrides})


func _rows_by_path(rows: Array) -> Dictionary:
	var result: Dictionary = {}
	for row in rows:
		result[str(row.get("path", ""))] = row
	return result


func _max_abs_difference(left: Array, right: Array) -> float:
	if left.size() != right.size():
		return INF
	var maximum := 0.0
	for index in left.size():
		maximum = maxf(maximum, absf(float(left[index]) - float(right[index])))
	return maximum


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _argument_value(prefix: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if str(argument).begins_with(prefix):
			return str(argument).trim_prefix(prefix)
	return ""


func _finish(report: Dictionary) -> void:
	var output_path := _argument_value("--out=")
	if output_path.is_empty():
		output_path = ProjectSettings.globalize_path("res://../docs/research/aircraft-standardization/AS-09-10-import/pose-baseline.json")
	var directory := output_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(directory)
	var output := FileAccess.open(output_path, FileAccess.WRITE)
	if output == null:
		_failures.append("Could not write probe output: " + output_path)
		push_error("Could not write probe output: " + output_path)
		call_deferred("quit", 1)
		return
	output.store_string(JSON.stringify(report, "\t") + "\n")
	output.close()
	print("AS_IMPORT_POSE_PROBE ", "ok=" if _failures.is_empty() else "failed=", output_path)
	call_deferred("quit", 0 if _failures.is_empty() else 1)

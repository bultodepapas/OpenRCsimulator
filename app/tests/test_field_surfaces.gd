extends SceneTree

const Loader := preload("res://data/field_loader.gd")
const Builder := preload("res://render/field.gd")
const Ground := preload("res://render/ground.gd")

var _count: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_default_surface_is_consolidated()
	_test_priority_ignores_json_order()
	_test_shifted_ned_coordinates()
	_test_capacity_and_shader_arrays_agree()
	_test_outside_rough_falls_back_whole_field()
	_test_missing_rough_falls_back()
	_test_surface_overflow_falls_back_whole_field()
	_test_overlay_outside_flat_horizon_falls_back()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _test_default_surface_is_consolidated() -> void:
	var loaded: Dictionary = Loader.load_from()
	_check("default field loads", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if not bool(loaded.get("ok", false)):
		return
	var field: Node3D = Builder.build(loaded.field)
	var rough: MeshInstance3D = field.get_node_or_null("rough") as MeshInstance3D
	_check("default field uses one ground pass", bool(field.get_meta("surfaces_consolidated", false))
		and rough != null and field.get_node_or_null("runway") == null,
		"consolidated=%s children=%s" % [field.get_meta("surfaces_consolidated", false), _child_names(field)])
	if rough != null:
		var material: ShaderMaterial = rough.material_override as ShaderMaterial
		_check("default runway rectangle is retained in the shader data", material != null
			and material.get_shader_parameter("surface_count") == 1
			and _rect_at(material, 0) == Vector4(0.0, -15.0, 50.0, 6.0)
			and _kind_at(material, 0) == 2,
			str(material.get_shader_parameter("surface_rects")) if material != null else "missing material")
	field.free()


func _test_priority_ignores_json_order() -> void:
	var first_raw: Dictionary = _small_overlap_field()
	var first_result: Dictionary = Loader.validate(first_raw)
	_check("overlapping custom rectangles validate", bool(first_result.get("ok", false)), str(first_result.get("errors", [])))
	if not bool(first_result.get("ok", false)):
		return
	var first: Node3D = Builder.build(first_result.field)
	var second_raw: Dictionary = first_raw.duplicate(true)
	var surfaces: Array = second_raw["surfaces"]
	surfaces = [surfaces[2], surfaces[0], surfaces[1]]
	second_raw["surfaces"] = surfaces
	var second_result: Dictionary = Loader.validate(second_raw)
	_check("reordered rectangles remain valid", bool(second_result.get("ok", false)), str(second_result.get("errors", [])))
	if not bool(second_result.get("ok", false)):
		first.free()
		return
	var second: Node3D = Builder.build(second_result.field)
	var first_material: ShaderMaterial = (first.get_node("rough") as MeshInstance3D).material_override as ShaderMaterial
	var second_material: ShaderMaterial = (second.get_node("rough") as MeshInstance3D).material_override as ShaderMaterial
	_check("mown then runway priority is stable when JSON surfaces reorder",
		bool(first.get_meta("surfaces_consolidated", false))
		and bool(second.get_meta("surfaces_consolidated", false))
		and first_material.get_shader_parameter("surface_count") == 2
		and second_material.get_shader_parameter("surface_count") == 2
		and _kind_at(first_material, 0) == 1 and _kind_at(first_material, 1) == 2
		and _kind_at(second_material, 0) == 1 and _kind_at(second_material, 1) == 2
		and _rect_at(first_material, 0) == _rect_at(second_material, 0)
		and _rect_at(first_material, 1) == _rect_at(second_material, 1))
	first.free()
	second.free()


func _test_shifted_ned_coordinates() -> void:
	var raw: Dictionary = _small_overlap_field()
	var pilot: Dictionary = raw["pilot"]
	(pilot["north"] as Dictionary)["value"] = 1200.0
	(pilot["east"] as Dictionary)["value"] = -700.0
	var surfaces: Array = raw["surfaces"]
	surfaces[0] = _surface("rough", "rough", 1200.0, -700.0, 1000.0, 1000.0)
	surfaces[1] = _surface("mown", "mown", 1210.0, -695.0, 200.0, 100.0)
	surfaces[2] = _surface("runway", "runway", 1215.0, -690.0, 132.0, 18.0)
	raw["surfaces"] = surfaces
	var validated: Dictionary = Loader.validate(raw)
	_check("shifted NED field validates", bool(validated.get("ok", false)), str(validated.get("errors", [])))
	if not bool(validated.get("ok", false)):
		return
	var field: Node3D = Builder.build(validated.field)
	var rough: MeshInstance3D = field.get_node("rough") as MeshInstance3D
	var material: ShaderMaterial = rough.material_override as ShaderMaterial
	_check("east maps to render x and north maps to negative render z",
		bool(field.get_meta("surfaces_consolidated", false))
		and _rect_at(material, 0) == Vector4(-695.0, -1210.0, 100.0, 50.0)
		and _rect_at(material, 1) == Vector4(-690.0, -1215.0, 66.0, 9.0)
		and material.get_shader_parameter("surface_bounds") == Vector4(-795.0, -1260.0, -595.0, -1160.0),
		str(material.get_shader_parameter("surface_bounds")))
	field.free()


func _test_outside_rough_falls_back_whole_field() -> void:
	var raw: Dictionary = _small_overlap_field()
	var surfaces: Array = raw["surfaces"]
	surfaces[2] = _surface("runway", "runway", 0.0, 600.0, 10.0, 4.0)
	raw["surfaces"] = surfaces
	var validated: Dictionary = Loader.validate(raw)
	_check("valid runway outside rough is accepted by the L5 format", bool(validated.get("ok", false)), str(validated.get("errors", [])))
	if not bool(validated.get("ok", false)):
		return
	var field: Node3D = Builder.build(validated.field)
	var rough: MeshInstance3D = field.get_node("rough") as MeshInstance3D
	var runway: MeshInstance3D = field.get_node_or_null("runway") as MeshInstance3D
	var rough_material: ShaderMaterial = rough.material_override as ShaderMaterial
	_check("uncontained runway uses complete legacy planes without partial shader merge",
		not bool(field.get_meta("surfaces_consolidated", true)) and runway != null
		and runway.mesh is PlaneMesh and is_equal_approx(runway.position.y, 0.03)
		and [null, 0].has(rough_material.get_shader_parameter("surface_count")),
		"children=%s" % _child_names(field))
	field.free()


func _test_capacity_and_shader_arrays_agree() -> void:
	var shader_source: String = FileAccess.get_file_as_string("res://render/ground.gdshader")
	var capacity: int = Ground.MAX_SURFACES
	_check("shader declarations and loop use the GDScript surface capacity",
		shader_source.contains("uniform vec4 surface_rects[%d];" % capacity)
		and shader_source.contains("uniform int surface_kinds[%d];" % capacity)
		and shader_source.contains("min(surface_count, %d)" % capacity), str(capacity))
	var raw: Dictionary = _batch_field(capacity - 1)
	var validated: Dictionary = Loader.validate(raw)
	_check("exact shader capacity is valid field data", bool(validated.get("ok", false)), str(validated.get("errors", [])))
	if not bool(validated.get("ok", false)):
		return
	var field: Node3D = Builder.build(validated.field)
	var rough: MeshInstance3D = field.get_node("rough") as MeshInstance3D
	var material: ShaderMaterial = rough.material_override as ShaderMaterial
	_check("exactly %d rectangles are packed without truncation" % capacity,
		bool(field.get_meta("surfaces_consolidated", false))
		and material.get_shader_parameter("surface_count") == capacity
		and (material.get_shader_parameter("surface_rects") as PackedVector4Array).size() == capacity
		and (material.get_shader_parameter("surface_kinds") as PackedInt32Array).size() == capacity
		and _kind_at(material, capacity - 1) == 2,
		"count=%s" % material.get_shader_parameter("surface_count"))
	field.free()


func _test_missing_rough_falls_back() -> void:
	var raw: Dictionary = _small_overlap_field()
	raw["surfaces"] = [_surface("runway", "runway", 12000.0, 23000.0, 132.0, 18.0)]
	var validated: Dictionary = Loader.validate(raw)
	_check("field without rough remains valid L5 field data", bool(validated.get("ok", false)), str(validated.get("errors", [])))
	if not bool(validated.get("ok", false)):
		return
	var field: Node3D = Builder.build(validated.field)
	var runway: MeshInstance3D = field.get_node_or_null("runway") as MeshInstance3D
	_check("far runway without a rough mesh stays in the legacy render path",
		not bool(field.get_meta("surfaces_consolidated", true))
		and field.get_node_or_null("rough") == null and runway != null
		and runway.mesh is PlaneMesh and runway.position.is_equal_approx(Vector3(23000.0, 0.03, -12000.0)))
	field.free()


func _test_surface_overflow_falls_back_whole_field() -> void:
	var raw: Dictionary = _batch_field(Ground.MAX_SURFACES)
	var validated: Dictionary = Loader.validate(raw)
	_check("more than the shader capacity remains valid L5 field data", bool(validated.get("ok", false)), str(validated.get("errors", [])))
	if not bool(validated.get("ok", false)):
		return
	var field: Node3D = Builder.build(validated.field)
	var rough: MeshInstance3D = field.get_node("rough") as MeshInstance3D
	var rough_material: ShaderMaterial = rough.material_override as ShaderMaterial
	var all_planes_present: bool = field.get_node_or_null("runway") is MeshInstance3D
	for index: int in Ground.MAX_SURFACES:
		all_planes_present = all_planes_present and field.get_node_or_null("mown-%02d" % index) is MeshInstance3D
	_check("overflow falls back for the entire field instead of truncating rectangles",
		not bool(field.get_meta("surfaces_consolidated", true)) and all_planes_present
		and [null, 0].has(rough_material.get_shader_parameter("surface_count")),
		"children=%d" % field.get_child_count())
	field.free()


func _batch_field(mown_count: int) -> Dictionary:
	var raw: Dictionary = _small_overlap_field()
	raw["objects"] = []
	var surfaces: Array = [
		_surface("rough", "rough", 0.0, 0.0, 1000.0, 1000.0),
		_surface("runway", "runway", 0.0, 0.0, 132.0, 18.0),
	]
	for index: int in mown_count:
		surfaces.append(_surface("mown-%02d" % index, "mown", 100.0, -124.0 + 4.0 * index, 2.0, 2.0))
	raw["surfaces"] = surfaces
	return raw


func _test_overlay_outside_flat_horizon_falls_back() -> void:
	var raw: Dictionary = _raw_default()
	raw["objects"] = []
	var surfaces: Array = raw["surfaces"]
	for index: int in surfaces.size():
		var surface: Dictionary = surfaces[index]
		if surface.get("id") == "runway":
			(surface["center_north"] as Dictionary)["value"] = 1495.0
			surfaces[index] = surface
	raw["surfaces"] = surfaces
	var validated: Dictionary = Loader.validate(raw)
	_check("runway crossing the L7 flat-ring boundary remains valid field data", bool(validated.get("ok", false)), str(validated.get("errors", [])))
	if not bool(validated.get("ok", false)):
		return
	var field: Node3D = Builder.build(validated.field)
	var rough: MeshInstance3D = field.get_node("rough") as MeshInstance3D
	_check("overlay crossing into raised terrain keeps the legacy overlay",
		not bool(field.get_meta("surfaces_consolidated", true))
		and field.get_node_or_null("runway") is MeshInstance3D
		and (rough.mesh as Mesh).get_class() != "PlaneMesh")
	field.free()


func _small_overlap_field() -> Dictionary:
	return {
		"format": "openrc-field v1",
		"id": "field-surfaces-test",
		"runway": "runway",
		"pilot": {"id": "pilot", "north": _quantity(0.0), "east": _quantity(0.0), "down": _quantity(0.0), "eye_height": _quantity(1.7)},
		"surfaces": [
			_surface("rough", "rough", 0.0, 0.0, 1000.0, 1000.0),
			_surface("mown", "mown", 0.0, 0.0, 200.0, 100.0),
			_surface("runway", "runway", 0.0, 0.0, 132.0, 18.0),
		],
		"objects": [],
	}


func _raw_default() -> Dictionary:
	var parser: JSON = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(Loader.DEFAULT_PATH)) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return {}
	return (parser.data as Dictionary).duplicate(true)


func _surface(id: String, kind: String, north: float, east: float, length: float, width: float) -> Dictionary:
	return {"id": id, "type": kind, "center_north": _quantity(north), "center_east": _quantity(east),
		"length_east_west": _quantity(length), "width_north_south": _quantity(width)}


func _quantity(value: float) -> Dictionary:
	return {"value": value, "unit": "m", "kind": "estimated", "source": "landscape surface test fixture"}


func _rect_at(material: ShaderMaterial, index: int) -> Vector4:
	var value: PackedVector4Array = material.get_shader_parameter("surface_rects")
	return value[index] if index < value.size() else Vector4(INF, INF, INF, INF)


func _kind_at(material: ShaderMaterial, index: int) -> int:
	var value: PackedInt32Array = material.get_shader_parameter("surface_kinds")
	return value[index] if index < value.size() else -1


func _child_names(node: Node) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	for child: Node in node.get_children():
		names.append(String(child.name))
	return names


func _check(name: String, ok: bool, detail: String = "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + name + ("  " + detail if not detail.is_empty() else ""))
	if not ok:
		_failures += 1

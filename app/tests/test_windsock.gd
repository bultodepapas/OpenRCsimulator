extends SceneTree

const Windsock = preload("res://render/windsock.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const FieldBuilder = preload("res://render/field.gd")
var _count: int = 0
var _failed: int = 0


func _initialize() -> void:
	var loaded: Dictionary = FieldLoader.load_from()
	var cues: Array = loaded.get("field", {}).get("flight_cues", []).filter(func(c: Dictionary) -> bool: return c.type == "windsock")
	_check("committed field provides one validated windsock", bool(loaded.get("ok", false))
		and cues.size() == 1)
	if _failed:
		quit(1)
		return
	var cue: Dictionary = cues[0]
	var field: Node3D = FieldBuilder.build(loaded.field)
	_check("production field builder attaches the configured cue", field.get_node_or_null(str(cue.id)) is Node3D
		and field.get_node_or_null(str(cue.id) + "/Fabric") is MeshInstance3D)
	field.free()
	var legacy: Dictionary = loaded.field.duplicate(true)
	legacy.erase("flight_cues")
	field = FieldBuilder.build(legacy)
	_check("fields without cues retain the original scene", field.get_node_or_null(str(cue.id)) == null)
	field.free()
	var first: Node3D = Windsock.build(cue)
	var second: Node3D = Windsock.build(cue)
	_check("NED placement", first.position == Vector3(cue.east, 0.0, -cue.north))
	_check("two visual meshes and no update callback", first.get_child_count() == 2 and not first.is_processing())
	var fabric: MeshInstance3D = first.get_node("Fabric") as MeshInstance3D
	var support: MeshInstance3D = first.get_node("Support") as MeshInstance3D
	var arrays: Array = fabric.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var centres: PackedVector3Array = fabric.get_meta("centreline")
	var arc: float = 0.0
	var rigid: bool = true
	for i: int in range(1, centres.size()):
		arc += centres[i].distance_to(centres[i - 1])
		if float(i) / Windsock.SECTIONS <= 0.375:
			rigid = rigid and is_equal_approx(centres[i].y, centres[0].y)
	_check("cloth centreline follows field length", absf(arc - cue.length) < 0.002 * cue.length)
	_check("first 3/8 is held open, remainder hangs", rigid and centres[-1].y < centres[0].y - 1.0)
	var upper: Vector3 = Windsock.cloth_point(0.0, 0.0, cue) + centres[0]
	var lower: Vector3 = Windsock.cloth_point(0.0, PI, cue) + centres[0]
	_check("throat diameter comes from field and is present in built mesh",
		is_equal_approx(upper.distance_to(lower), cue.throat_diameter) and _contains(vertices, upper) and _contains(vertices, lower))
	_check("cloth stays clear of ground", fabric.mesh.get_aabb().position.y > 0.1)
	_check("pole and throat bounds follow mount height", is_equal_approx(support.mesh.get_aabb().end.y, cue.pole_height + cue.throat_diameter * 0.5 + 0.0045))
	var transitions: int = 0
	var last: Color = colours[0]
	for i: int in Windsock.SECTIONS:
		var colour: Color = colours[i * Windsock.SIDES * 6]
		if colour != last:
			transitions += 1
		last = colour
	_check("five uninterrupted stripe bands", transitions == 4)
	var finite: bool = true
	for vertex: Vector3 in vertices:
		finite = finite and vertex.is_finite()
	for normal: Vector3 in normals:
		finite = finite and normal.is_finite() and absf(normal.length() - 1.0) < 0.00001
	_check("finite vertices and unit normals", finite)
	_check("top of rigid cloth faces outward", normals[0].y > 0.9)
	var material := fabric.mesh.surface_get_material(0) as ShaderMaterial
	_check("opaque double-sided cloth, no engine shadow", material != null and not material.shader.code.contains("ALPHA")
		and material.shader.code.contains("cull_disabled")
		and fabric.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var triangle_count: int = (vertices.size() + support.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()) / 3
	_check("two draws and fewer than 6000 triangles", fabric.mesh.get_surface_count() == 1 and support.mesh.get_surface_count() == 1 and triangle_count < 6000)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	var mapped := uvs.size() == vertices.size() and tangents.size() == vertices.size() * 4
	for i in vertices.size():
		mapped = mapped and uvs[i].is_finite() and uvs[i].x >= 0.0 and uvs[i].x <= 1.0 and uvs[i].y >= 0.0 and uvs[i].y <= 1.0
		var tangent := Vector3(tangents[i*4], tangents[i*4+1], tangents[i*4+2])
		mapped = mapped and tangent.is_finite() and absf(tangent.dot(normals[i])) < 0.001 and absf(tangent.length() - 1.0) < 0.001
	_check("finite sleeve UVs and orthonormal tangent frame", mapped)
	_check("independent deterministic builds", fabric.mesh != second.get_node("Fabric").mesh
		and vertices.to_byte_array() == second.get_node("Fabric").mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].to_byte_array())
	first.free()
	second.free()
	print("%d checks, %d failed" % [_count, _failed])
	quit(1 if _failed else 0)


func _contains(vertices: PackedVector3Array, point: Vector3) -> bool:
	for vertex: Vector3 in vertices:
		if vertex.distance_to(point) < 0.000001:
			return true
	return false


func _check(label: String, passed: bool) -> void:
	_count += 1
	if not passed:
		_failed += 1
		printerr("FAIL: ", label)

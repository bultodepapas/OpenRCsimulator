## CR-17a: keep intact scenery merged; rebuild only an affected cell from its pristine triangle arrays.
## These meshes are presentation only. The float64 session decides which object has failed.
extends RefCounted
const MeshKit := preload("res://scenery/mesh_kit.gd")

static func capture(node: MeshInstance3D, ranges: Array[Dictionary]) -> void:
	if ranges.is_empty():
		return
	node.set_meta("damage_ranges", ranges.duplicate(true))
	node.set_meta("damage_pristine_mesh", node.mesh)
	node.set_meta("damage_applied_ids", [])

static func apply(node: MeshInstance3D, damage: Dictionary) -> bool:
	var ranges: Array = node.get_meta("damage_ranges", [])
	var removed: Array[String] = []
	for item: Dictionary in ranges:
		if damage.get(item.id, {}).get("state", "") == "broken":
			removed.append(item.id)
	removed.sort()
	if removed == node.get_meta("damage_applied_ids", []):
		return false
	var original: ArrayMesh = node.get_meta("damage_pristine_mesh") as ArrayMesh
	if removed.is_empty():
		node.mesh = original
	else:
		var source := original.surface_get_arrays(0)
		var vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = source[Mesh.ARRAY_NORMAL]
		var colors: PackedColorArray = source[Mesh.ARRAY_COLOR]
		var kit := MeshKit.new()
		var cursor := 0
		for item: Dictionary in ranges:
			if not removed.has(str(item.id)):
				continue
			_append(kit, vertices, normals, colors, cursor, int(item.first))
			cursor = int(item.end)
		_append(kit, vertices, normals, colors, cursor, vertices.size())
		node.mesh = kit.to_mesh(original.surface_get_material(0))
	node.set_meta("damage_applied_ids", removed)
	return true

static func _append(kit: MeshKit, vertices: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, first: int, end: int) -> void:
	kit.verts.append_array(vertices.slice(first, end))
	kit.norms.append_array(normals.slice(first, end))
	kit.cols.append_array(colors.slice(first, end))

## Exact source geometry for the failed prop, detached from the surviving cell.
static func piece(node: MeshInstance3D, id: String) -> MeshKit:
	var kit := MeshKit.new()
	var original: ArrayMesh = node.get_meta("damage_pristine_mesh") as ArrayMesh
	if original == null or original.get_surface_count() == 0:
		return kit
	var source := original.surface_get_arrays(0)
	for item: Dictionary in node.get_meta("damage_ranges", []):
		if str(item.id) == id:
			_append(kit, source[Mesh.ARRAY_VERTEX], source[Mesh.ARRAY_NORMAL], source[Mesh.ARRAY_COLOR], item.first, item.end)
	return kit

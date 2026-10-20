## LU-30: imported CC0 transmission tower. Source meshes remain unmodified;
## only centering and uniform metre scaling happen at the rendering boundary.
extends RefCounted
const MeshKit = preload("res://scenery/mesh_kit.gd")
const TOWER_PATH := "res://assets/landscape/power-lines/transmission-tower-3tier-ipoly3d.glb"
const HEIGHT_M := 30.0
static var _tower := {}

static func tower_arrays() -> Dictionary:
	if not _tower.is_empty():
		return _tower
	var raw := source_arrays(TOWER_PATH)
	var bounds := AABB(raw.pos[0], Vector3.ZERO)
	for p: Vector3 in raw.pos:
		bounds = bounds.expand(p)
	var scale := HEIGHT_M / bounds.size.y
	var center := Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	var xf := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale), -center * scale)
	raw.pos = xf * raw.pos
	raw.size = bounds.size * scale
	_tower = raw
	return _tower

static func append_tower(kit: MeshKit) -> void:
	var a := tower_arrays()
	kit.append_arrays(a.pos, a.nrm, a.col, Transform3D.IDENTITY)

static func source_arrays(path: String) -> Dictionary:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	assert(document.append_from_file(path, state) == OK, "Missing imported power-line asset: " + path)
	var model := document.generate_scene(state)
	var result := {pos = PackedVector3Array(), nrm = PackedVector3Array(), col = PackedColorArray()}
	_collect(model, Transform3D.IDENTITY, result)
	model.free()
	return result

static func _collect(node: Node, parent: Transform3D, result: Dictionary) -> void:
	var xf := parent
	if node is Node3D:
		xf *= node.transform
	if node is MeshInstance3D:
		var instance: MeshInstance3D = node
		for surface in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var material := instance.get_active_material(surface) as StandardMaterial3D
			var color := material.albedo_color if material != null else Color.WHITE
			var normal_basis := xf.basis.inverse().transposed()
			for i in (indices.size() if not indices.is_empty() else vertices.size()):
				var index := indices[i] if not indices.is_empty() else i
				result.pos.append(xf * vertices[index])
				result.nrm.append((normal_basis * normals[index]).normalized())
				result.col.append(color)
	for child in node.get_children():
		_collect(child, xf, result)

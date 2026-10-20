## LU-30: imported CC0 transmission tower. Source meshes remain unmodified;
## only centering and uniform metre scaling happen at the rendering boundary.
extends RefCounted
const MeshKit = preload("res://scenery/mesh_kit.gd")
const TOWER_SCENE: PackedScene = preload("res://assets/landscape/power-lines/transmission-tower-3tier-ipoly3d.glb")
const HEIGHT_M := 30.0
const CABLE_DATA := "res://data/scenery/power_cable.json"
const SAG_RATIO := 0.023
# Measured crossarm tips of the downloaded, uniformly scaled source.
const ATTACHMENTS: Array[Vector3] = [
	Vector3(-4.20, 17.40, -0.0365), Vector3(4.20, 17.40, -0.0365),
	Vector3(-3.86, 22.75, -0.0365), Vector3(3.86, 22.75, -0.0365),
	Vector3(-3.67, 28.30, -0.0365), Vector3(3.67, 28.30, -0.0365),
	Vector3(0.0, 29.98, -0.0365),
]
static var _tower := {}
static var _cable := {}

static func tower_arrays() -> Dictionary:
	if not _tower.is_empty():
		return _tower
	var raw := source_arrays(TOWER_SCENE)
	var bounds := AABB(raw.pos[0], Vector3.ZERO)
	for p: Vector3 in raw.pos:
		bounds = bounds.expand(p)
	var scale := HEIGHT_M / bounds.size.y
	var center := Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	var xf := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale), -center * scale)
	raw.pos = xf * raw.pos
	raw.size = bounds.size * scale
	for i in raw.col.size():
		# The supplier supplies an untextured white material. Fit its finish to
		# galvanized steel; retain pale concrete on the imported footing geometry.
		raw.col[i] = Color("aeb8bc") if raw.pos[i].y > 0.55 else Color("bbbcb5")
	_tower = raw
	return _tower

static func append_tower(kit: MeshKit) -> void:
	var a := tower_arrays()
	kit.append_arrays(a.pos, a.nrm, a.col, Transform3D.IDENTITY)

## Place the downloaded rope-span topology between the measured sockets.
## No curve is synthesized: normalized centers retain the supplier's sag profile.
## These thin conductors are visual only; tower proxies belong to CollisionWorld.
static func append_span(kit: MeshKit, from: Transform3D, to: Transform3D) -> void:
	if _cable.is_empty():
		_cable = JSON.parse_string(FileAccess.get_file_as_string(CABLE_DATA))
	for socket: Vector3 in ATTACHMENTS:
		var a := from * socket
		var b := to * socket
		var delta := b - a
		var length := delta.length()
		if length < 0.01:
			continue
		var along := delta / length
		var side := along.cross(Vector3.UP).normalized()
		var basis := Basis(along, Vector3.UP, side)
		var positions := PackedVector3Array()
		for vertex: Dictionary in _cable.vertices:
			var center: Array = vertex.center
			var radial: Array = vertex.radial
			positions.append(a.lerp(b, center[0]) + Vector3.UP * (center[1] * length * SAG_RATIO)
				+ basis * Vector3(radial[0], radial[1], radial[2]))
		var indices: Array = _cable.triangles
		for i in range(0, indices.size(), 3):
			kit.tri(positions[indices[i]], positions[indices[i + 1]], positions[indices[i + 2]], Color("343b3f"))

static func source_arrays(scene: PackedScene) -> Dictionary:
	var model := scene.instantiate()
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

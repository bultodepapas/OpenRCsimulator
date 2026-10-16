# HELI-26a: render boundary for the advanced HX-700 reduced flex modes.
# Builds instance-owned morphs FROM the admitted mesh; never edits the GLB/source.
# Geometry anchors come from the immutable source generator, not the old heli.
extends RefCounted

const IDS := ["visual.tren_de_aterrizaje", "visual.carenado"]
const REFERENCE_M := [0.010, 0.010, 0.004]
const LIMIT_M := [0.020, 0.020, 0.008]
const SPLAY := (0.084 - 0.0108) / (0.0858 - 0.039)
const GEAR_MATERIALS := ["Plastico_Grafito", "Aluminio_Anodizado_Negro", "Conector_Amarillo", "Acero_Pulido", "Acero_Hueco_Hexagonal"]
var gear: MeshInstance3D
var canopy: MeshInstance3D


func configure(preview: Dictionary) -> bool:
	if not preview.get("ok", false):
		return false
	var meshes: Array[ArrayMesh] = []
	for id: String in IDS:
		if not preview.bindings.get(id) is MeshInstance3D:
			return false
		var node: MeshInstance3D = preview.bindings[id]
		if not node.basis.is_equal_approx(Basis.IDENTITY):
			return false
		if id == IDS[0]:
			if node.mesh.get_surface_count() != GEAR_MATERIALS.size():
				return false
			for s in GEAR_MATERIALS.size():
				if node.mesh.surface_get_material(s).resource_name != GEAR_MATERIALS[s]:
					return false
		meshes.append(_build(node, id == IDS[0]))
	gear = preview.bindings[IDS[0]]
	canopy = preview.bindings[IDS[1]]
	gear.mesh = meshes[0]
	canopy.mesh = meshes[1]
	return apply(PackedFloat64Array([0, 0, 0]))


func apply(q: PackedFloat64Array) -> bool:
	if gear == null or canopy == null or q.size() != 3:
		return false
	for i in 3:
		if not is_finite(q[i]) or absf(q[i]) > LIMIT_M[i]:
			return false
	gear.set_blend_shape_value(0, q[0] / REFERENCE_M[0])
	gear.set_blend_shape_value(1, q[1] / REFERENCE_M[1])
	canopy.set_blend_shape_value(0, q[2] / REFERENCE_M[2])
	return true


# Unit-displacement basis in the admitted root frame (+X nose, +Y up, -Z left).
# Rail tubes, end caps, low clamps and screws translate together. Upper mounting
# blocks/bolts are fixed; only the graphite struts interpolate between the ends.
# Splay preserves the support endpoint chord length to first order. It is a
# reduced bending approximation, not an inextensible nonlinear beam solution.
static func mode_offset(mode: int, p: Vector3, material: String) -> Vector3:
	if mode < 2:
		var side := -1.0 if mode == 0 else 1.0
		if p.z * side <= 0:
			return Vector3.ZERO
		var weight := 1.0
		if material == "Plastico_Grafito":
			# Source base boxes end at |Z|=.042; reserve their entire extent.
			weight = 0.0 if absf(p.z) <= 0.044 else smoothstep(0.074, 0.022, p.y)
		elif material in ["Acero_Pulido", "Acero_Hueco_Hexagonal"]:
			weight = 0.0 if p.y > 0.05 else 1.0
		return Vector3(0, weight, side * SPLAY * weight)
	# Shell's lateral bending mode. Four 8 mm attachment patches remain fixed;
	# the source grommets and posts are untouched. Patch extent/mode are estimates.
	var weight := smoothstep(-0.08, 0.28, p.x)
	for station in [Vector2(0.150, 0.145), Vector2(-0.040, 0.204)]:
		weight *= smoothstep(0.008, 0.045, Vector2(p.x, p.y).distance_to(station))
	return Vector3(0, 0, weight)


func _build(node: MeshInstance3D, is_gear: bool) -> ArrayMesh:
	var result := ArrayMesh.new()
	result.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
	var modes := [0, 1] if is_gear else [2]
	for mode: int in modes:
		result.add_blend_shape(["left_skid", "right_skid", "canopy_lateral"][mode])
	for s in node.mesh.get_surface_count():
		var arrays := node.mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		var material: Material = node.mesh.surface_get_material(s)
		var shapes: Array[Array] = []
		for mode: int in modes:
			var shape: Array = []
			shape.resize(Mesh.ARRAY_MAX)
			var moved := vertices.duplicate()
			var n := normals.duplicate()
			var t := tangents.duplicate()
			for index in vertices.size():
				var p := node.transform * vertices[index]
				var offset: Vector3 = mode_offset(mode, p, material.resource_name) * REFERENCE_M[mode]
				moved[index] += offset
				# Inverse-transpose normal and forward tangent for each morph target.
				# One-time finite difference; the GPU only blends cached arrays per frame.
				var jacobian := Basis.IDENTITY
				for axis in 3:
					var step := Vector3.ZERO
					step[axis] = 0.0001
					jacobian[axis] += (mode_offset(mode, p + step, material.resource_name) - mode_offset(mode, p - step, material.resource_name)) * (REFERENCE_M[mode] / 0.0002)
				if not n.is_empty():
					n[index] = (jacobian.inverse().transposed() * normals[index]).normalized()
				if not t.is_empty():
					var tangent := (jacobian * Vector3(tangents[index * 4], tangents[index * 4 + 1], tangents[index * 4 + 2])).normalized()
					for axis in 3:
						t[index * 4 + axis] = tangent[axis]
			shape[Mesh.ARRAY_VERTEX] = moved
			shape[Mesh.ARRAY_NORMAL] = n
			shape[Mesh.ARRAY_TANGENT] = t
			shapes.append(shape)
		result.add_surface_from_arrays(node.mesh.surface_get_primitive_type(s), arrays, shapes)
		result.surface_set_material(s, material)
	# Include negative excursions and both rail modes in culling/shadow bounds.
	result.custom_aabb = node.mesh.get_aabb().grow(0.05)
	return result

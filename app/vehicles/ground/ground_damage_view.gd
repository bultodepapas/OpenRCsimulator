class_name GroundDamageView
extends RefCounted
## Render-only local deformation for the supplied Bisonte body shell and bumpers.
## It copies the imported ArrayMesh and keeps the source geometry/materials intact.

const MAX_DENT_M := 0.014
const FRONT_BUMPER_SHIFT_M := 0.018
const REAR_BUMPER_SHIFT_M := 0.018

var _prepared := false
var _body: MeshInstance3D
var _front_bumper: Node3D
var _rear_bumper: Node3D
var _source_mesh: ArrayMesh
var _working_mesh: ArrayMesh
var _base_arrays: Array = []
var _surface_primitives: Array[int] = []
var _surface_formats: Array[int] = []
var _surface_names: Array[String] = []
var _surface_materials: Array[Material] = []
var _surface_deformable: Array[bool] = []
var _body_bounds := AABB()
var _front_bumper_base := Transform3D.IDENTITY
var _rear_bumper_base := Transform3D.IDENTITY
var _last_signature := ""


func prepare(visual: Dictionary) -> bool:
	if _prepared:
		return false
	if not bool(visual.get("ok", false)) or typeof(visual.get("nodes")) != TYPE_DICTIONARY:
		return false
	var nodes: Dictionary = visual.nodes
	var body_value: Variant = nodes.get("Body")
	var front_value: Variant = nodes.get("Bumper_F")
	var rear_value: Variant = nodes.get("Bumper_R")
	if not body_value is MeshInstance3D or not front_value is Node3D or not rear_value is Node3D:
		return false
	var source_value: Variant = body_value.mesh
	if not source_value is ArrayMesh:
		return false
	var source: ArrayMesh = source_value
	if source.get_surface_count() <= 0 or source.get_blend_shape_count() > 0:
		return false
	var arrays_by_surface: Array = []
	var primitives: Array[int] = []
	var formats: Array[int] = []
	var names: Array[String] = []
	var materials: Array[Material] = []
	var deformable: Array[bool] = []
	var bounds := AABB()
	var has_vertex := false
	for surface in source.get_surface_count():
		var arrays: Array = source.surface_get_arrays(surface)
		if arrays.size() <= Mesh.ARRAY_VERTEX or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
			return false
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if vertices.is_empty():
			return false
		for vertex in vertices:
			if not has_vertex:
				bounds = AABB(vertex, Vector3.ZERO)
				has_vertex = true
			else:
				bounds = bounds.expand(vertex)
		arrays_by_surface.append(arrays.duplicate(true))
		primitives.append(source.surface_get_primitive_type(surface))
		# Array formats are inferred from the copied arrays. Only the optional
		# dynamic-update flag is needed for the private runtime copy.
		formats.append(Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
		names.append(source.surface_get_name(surface))
		var material := source.surface_get_material(surface)
		materials.append(material)
		deformable.append(_material_can_dent(material, names[surface]))
	if not has_vertex or bounds.size.x <= 0.0 or bounds.size.y <= 0.0 or bounds.size.z <= 0.0:
		return false
	var working := _make_mesh(source, arrays_by_surface, primitives, formats, names, materials,
		deformable, PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0]))
	if working == null:
		return false
	_body = body_value
	_front_bumper = front_value
	_rear_bumper = rear_value
	_source_mesh = source
	_working_mesh = working
	_base_arrays = arrays_by_surface
	_surface_primitives = primitives
	_surface_formats = formats
	_surface_names = names
	_surface_materials = materials
	_surface_deformable = deformable
	_body_bounds = bounds
	_front_bumper_base = _front_bumper.transform
	_rear_bumper_base = _rear_bumper.transform
	_prepared = true
	reset()
	return true


func update(damage: Dictionary) -> bool:
	if not _prepared or not _damage_state_is_valid(damage):
		return false
	var signature := _signature(damage)
	if signature == _last_signature:
		return true
	var body_channels := PackedFloat64Array([
		float(damage.get("body_front_damage", 0.0)),
		float(damage.get("body_rear_damage", 0.0)),
		float(damage.get("body_left_damage", 0.0)),
		float(damage.get("body_right_damage", 0.0)),
		float(damage.get("body_bottom_damage", 0.0)),
	])
	var deformed := _make_mesh(
		_source_mesh, _base_arrays, _surface_primitives, _surface_formats,
		_surface_names, _surface_materials, _surface_deformable, body_channels,
	)
	if deformed == null:
		return false
	_working_mesh = deformed
	_body.mesh = _working_mesh
	var front_damage := float(damage.get("body_front_damage", 0.0))
	var rear_damage := float(damage.get("body_rear_damage", 0.0))
	_front_bumper.transform = _bumper_transform(
		_front_bumper_base, FRONT_BUMPER_SHIFT_M * front_damage, front_damage,
	)
	_rear_bumper.transform = _bumper_transform(
		_rear_bumper_base, -REAR_BUMPER_SHIFT_M * rear_damage, rear_damage,
	)
	_last_signature = signature
	return true


func reset() -> void:
	if not _prepared:
		return
	_working_mesh = _source_mesh
	_body.mesh = _source_mesh
	_front_bumper.transform = _front_bumper_base
	_rear_bumper.transform = _rear_bumper_base
	_last_signature = _signature({
		"body_front_damage": 0.0,
		"body_rear_damage": 0.0,
		"body_left_damage": 0.0,
		"body_right_damage": 0.0,
		"body_bottom_damage": 0.0,
	})


func _make_mesh(
	source: ArrayMesh,
	base_arrays: Array,
	primitives: Array[int],
	formats: Array[int],
	names: Array[String],
	materials: Array[Material],
	deformable: Array[bool],
	damage: PackedFloat64Array,
) -> ArrayMesh:
	var result := ArrayMesh.new()
	result.resource_name = source.resource_name + " Damage Copy"
	if source.custom_aabb.size.length_squared() > 0.0:
		result.custom_aabb = source.custom_aabb.grow(MAX_DENT_M)
	for surface in base_arrays.size():
		var arrays: Array = base_arrays[surface].duplicate(true)
		if deformable[surface]:
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX].duplicate()
			for vertex_index in vertices.size():
				vertices[vertex_index] = _dent_vertex(vertices[vertex_index], damage)
			arrays[Mesh.ARRAY_VERTEX] = vertices
			if arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array:
				var indices := PackedInt32Array()
				if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
					indices = arrays[Mesh.ARRAY_INDEX]
				arrays[Mesh.ARRAY_NORMAL] = _recalculate_normals(vertices, indices)
		result.add_surface_from_arrays(primitives[surface], arrays, [], {}, formats[surface])
		if not names[surface].is_empty():
			result.surface_set_name(surface, names[surface])
		result.surface_set_material(surface, materials[surface])
	return result


func _dent_vertex(vertex: Vector3, damage: PackedFloat64Array) -> Vector3:
	var min_corner := _body_bounds.position
	var max_corner := _body_bounds.position + _body_bounds.size
	var span := _body_bounds.size
	var x_mid := 0.5 * (min_corner.x + max_corner.x)
	var z_mid := 0.5 * (min_corner.z + max_corner.z)
	var front_weight := _falloff(vertex.z - min_corner.z, span.z * 0.36) \
		* _falloff(absf(vertex.x - x_mid), span.x * 0.52)
	var rear_weight := _falloff(max_corner.z - vertex.z, span.z * 0.36) \
		* _falloff(absf(vertex.x - x_mid), span.x * 0.52)
	var left_weight := _falloff(vertex.x - min_corner.x, span.x * 0.24) \
		* _falloff(absf(vertex.z - z_mid), span.z * 0.72)
	var right_weight := _falloff(max_corner.x - vertex.x, span.x * 0.24) \
		* _falloff(absf(vertex.z - z_mid), span.z * 0.72)
	var bottom_weight := _falloff(vertex.y - min_corner.y, span.y * 0.32)
	var depth := MAX_DENT_M
	var offset := Vector3.ZERO
	offset += Vector3(0.0, -depth * 0.25, depth) * float(damage[0]) * front_weight
	offset += Vector3(0.0, -depth * 0.25, -depth) * float(damage[1]) * rear_weight
	offset += Vector3(depth, -depth * 0.18, 0.0) * float(damage[2]) * left_weight
	offset += Vector3(-depth, -depth * 0.18, 0.0) * float(damage[3]) * right_weight
	offset += Vector3(0.0, depth, 0.0) * float(damage[4]) * bottom_weight
	var magnitude := offset.length()
	if magnitude > depth:
		offset *= depth / magnitude
	return vertex + offset


func _recalculate_normals(vertices: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for vertex_index in normals.size():
		normals[vertex_index] = Vector3.ZERO
	if indices.size() >= 3:
		for triangle_start in range(0, indices.size() - 2, 3):
			_add_face_normal(normals, vertices, indices[triangle_start], indices[triangle_start + 1], indices[triangle_start + 2])
	else:
		for triangle_start in range(0, vertices.size() - 2, 3):
			_add_face_normal(normals, vertices, triangle_start, triangle_start + 1, triangle_start + 2)
	for vertex_index in normals.size():
		if normals[vertex_index].length_squared() > 1.0e-12:
			normals[vertex_index] = normals[vertex_index].normalized()
	return normals


func _add_face_normal(
	normals: PackedVector3Array,
	vertices: PackedVector3Array,
	index_a: int,
	index_b: int,
	index_c: int,
) -> void:
	if index_a < 0 or index_a >= vertices.size() or index_b < 0 or index_b >= vertices.size() \
			or index_c < 0 or index_c >= vertices.size():
		return
	var normal := (vertices[index_b] - vertices[index_a]).cross(vertices[index_c] - vertices[index_a])
	normals[index_a] += normal
	normals[index_b] += normal
	normals[index_c] += normal


func _material_can_dent(material: Material, surface_name: String) -> bool:
	var identity := surface_name.to_lower()
	if material != null:
		identity += " " + material.resource_name.to_lower()
	return not identity.contains("glass") and not identity.contains("light")


func _falloff(distance: float, radius: float) -> float:
	if radius <= 0.0:
		return 0.0
	var t := clampf(1.0 - maxf(distance, 0.0) / radius, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _bumper_transform(base: Transform3D, local_z_offset: float, damage: float) -> Transform3D:
	var result := base
	result.origin += Vector3(0.0, -0.003 * damage, local_z_offset)
	return result


func _damage_state_is_valid(damage: Dictionary) -> bool:
	for key in ["body_front_damage", "body_rear_damage", "body_left_damage",
			"body_right_damage", "body_bottom_damage"]:
		var value: Variant = damage.get(key, 0.0)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or typeof(value) == TYPE_BOOL \
				or not is_finite(float(value)) or float(value) < 0.0 or float(value) > 1.0:
			return false
	return true


func _signature(damage: Dictionary) -> String:
	return "%0.6f,%0.6f,%0.6f,%0.6f,%0.6f" % [
		float(damage.get("body_front_damage", 0.0)),
		float(damage.get("body_rear_damage", 0.0)),
		float(damage.get("body_left_damage", 0.0)),
		float(damage.get("body_right_damage", 0.0)),
		float(damage.get("body_bottom_damage", 0.0)),
	]

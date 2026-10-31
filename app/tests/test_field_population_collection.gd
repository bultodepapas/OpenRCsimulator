## DT-11a: exact population selection and ordered shadow-triangle runs.
extends SceneTree

const FieldShadows := preload("res://render/field_projected_shadows.gd")
const Projected := preload("res://render/projected_shadow.gd")
const CELL_KEY := Vector2i(0, 0)

var _checks := 0
var _failed := 0


func _initialize() -> void:
	var base_mesh := _triangle_mesh(PackedVector3Array([
		Vector3(-2, 0.5, -1), Vector3(-1, 0.5, -1), Vector3(-2, 0.5, 0),
	]))
	var person_mesh := _triangle_mesh(PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0.5, 1),
	]))
	var flat_mesh := _triangle_mesh(PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1),
	]))
	var empty_mesh := ArrayMesh.new()
	var cell := MeshInstance3D.new()
	cell.name = "cell_0_0"
	cell.mesh = base_mesh
	cell.transform = Transform3D(Basis.IDENTITY, Vector3(10, 0, 0))
	var offset := Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0))
	var placement := _placement(Vector3(0.5, 0, 0), 0.2)
	var owners := {"standing:0": CELL_KEY}

	_expect_base("wrong owner", cell, base_mesh, person_mesh,
		_make_child(person_mesh, placement, offset), {"standing:0": Vector2i(9, 9)})
	_expect_base("out of range", cell, base_mesh, person_mesh,
		_make_child(person_mesh, _placement(Vector3(2, 0, 0)), offset), owners)
	_expect_base("hidden population", cell, base_mesh, person_mesh,
		_make_child(person_mesh, placement, offset, 1, false), owners)
	_expect_base("zero instance count", cell, base_mesh, person_mesh,
		_make_child(person_mesh, placement, offset, 0), owners)
	_expect_base("empty face stream", cell, base_mesh, empty_mesh,
		_make_child(empty_mesh, placement, offset), owners)
	_expect_base("cutoff removes selected triangle", cell, base_mesh, flat_mesh,
		_make_child(flat_mesh, placement, Transform3D.IDENTITY), owners)
	_test_append_above()
	_expect_added(cell, base_mesh, person_mesh, placement, offset)
	_test_added_bounds_after_mesh_roundtrip()
	cell.free()
	print("field population collection: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed else 0)


func _test_append_above() -> void:
	var exact := _face(0, 0.5, 0.5, 0.5)
	var crossing := _face(4, 0.5, 0.5, 0.75)
	var below := _face(8, 0.0, 0.25, 0.375)
	var above := _face(12, 0.75, 1.0, 1.25)
	var threshold := float(exact[0].y)
	_append_case("reject first at exact threshold", _join([exact, crossing]), threshold)
	_append_case("reject last", _join([crossing, below]), threshold)
	_append_case("reject all including exact threshold", _join([exact, below]), threshold)
	_append_case("reject none", _join([crossing, above]), threshold)
	_append_case("flush across consecutive rejects", _join([crossing, exact, below, above]), threshold)
	_append_case("alternating accepted and rejected runs",
		_join([crossing, below, above, exact, crossing]), threshold)
	_append_case("appends accepted run into empty destination",
		_join([crossing, below, above]), threshold, false)
	_append_case("empty faces preserve seeded destination", PackedVector3Array(), threshold)
	var empty := PackedVector3Array()
	var empty_destination := PackedVector3Array()
	var added := Projected.append_above(empty_destination, empty, threshold)
	_check("empty faces leave empty destination and report zero triangles",
		empty.is_empty() and empty_destination.is_empty() and added == 0)


func _append_case(label: String, faces: PackedVector3Array, threshold: float,
		seed_destination: bool = true) -> void:
	var initial := _face(-8, 0.5, 0.5, 0.5) if seed_destination else PackedVector3Array()
	var faces_before := faces.to_byte_array()
	var accepted := _scalar_above(faces, threshold)
	var expected := initial.duplicate()
	expected.append_array(accepted)
	var actual := initial.duplicate()
	var added := Projected.append_above(actual, faces, threshold)
	_check(label + " appends scalar-selected vertices in exact order",
		actual.to_byte_array() == expected.to_byte_array())
	_check(label + " reports the scalar accepted triangle count",
		added == accepted.size() / 3)
	_check(label + " preserves exact scalar AABB bounds",
		var_to_bytes(_bounds(actual)) == var_to_bytes(_bounds(expected)))
	_check(label + " leaves the source face stream unchanged",
		faces.to_byte_array() == faces_before)


func _scalar_above(faces: PackedVector3Array, threshold: float) -> PackedVector3Array:
	var accepted := PackedVector3Array()
	for first in range(0, faces.size(), 3):
		var a := faces[first]
		var b := faces[first + 1]
		var c := faces[first + 2]
		if maxf(a.y, maxf(b.y, c.y)) <= threshold:
			continue
		accepted.append(a)
		accepted.append(b)
		accepted.append(c)
	return accepted


func _face(x: float, y0: float, y1: float, y2: float) -> PackedVector3Array:
	return PackedVector3Array([
		Vector3(x, y0, 0), Vector3(x + 0.25, y1, 0), Vector3(x + 0.5, y2, 1),
	])


func _join(pieces: Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	for face: PackedVector3Array in pieces:
		result.append_array(face)
	return result


func _expect_base(label: String, cell: MeshInstance3D, base: ArrayMesh,
		population_mesh: ArrayMesh, child: MultiMeshInstance3D, owners: Dictionary) -> void:
	var population := Node3D.new()
	population.transform = Transform3D(Basis.IDENTITY, Vector3(12, 0, 0))
	population.add_child(child)
	var base_before := _mesh_bytes(base)
	var population_before := _mesh_bytes(population_mesh)
	var shape: Dictionary = FieldShadows.collect_cell_shape(cell, population, Vector2.ZERO,
		1.0, 0.04, owners)
	var actual := PackedVector3Array()
	if not shape.is_empty():
		actual = shape.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var expected := base.get_faces()
	_check(label + " keeps exact base vertices and bounds",
		not shape.is_empty() and int(shape.triangles) == 1
			and actual.to_byte_array() == expected.to_byte_array()
			and var_to_bytes(shape.bounds) == var_to_bytes(_bounds(expected)))
	_check(label + " reports zero added population geometry",
		int(shape.get("population_placements", -1)) == 0
			and int(shape.get("population_elevated_placements", -1)) == 0
			and int(shape.get("population_triangles", -1)) == 0)
	_check(label + " leaves source mesh arrays unchanged",
		base_before == _mesh_bytes(base) and population_before == _mesh_bytes(population_mesh))
	population.free()


func _expect_added(cell: MeshInstance3D, base: ArrayMesh, person: ArrayMesh,
		placement: Dictionary, local_offset: Transform3D) -> void:
	var population := Node3D.new()
	population.transform = Transform3D(Basis.IDENTITY, Vector3(12, 0, 0))
	var child := _make_child(person, placement, local_offset)
	child.transform = Transform3D(Basis.IDENTITY, Vector3(0, 0, 1))
	population.add_child(child)
	var base_before := _mesh_bytes(base)
	var person_before := _mesh_bytes(person)
	var shape: Dictionary = FieldShadows.collect_cell_shape(cell, population, Vector2.ZERO,
		1.0, 0.04, {"standing:0": CELL_KEY})
	var expected := base.get_faces()
	# cell^-1 * population * child * instance_offset translates the face stream by (2, .5, 1).
	expected.append_array(PackedVector3Array([
		Vector3(2, 0.5, 1), Vector3(3, 0.5, 1), Vector3(2, 1, 2),
	]))
	var actual: PackedVector3Array = shape.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_check("selected placement appends exact transformed face order and counts",
		actual.to_byte_array() == expected.to_byte_array() and int(shape.triangles) == 2
			and int(shape.population_placements) == 1 and int(shape.population_triangles) == 1
			and int(shape.population_elevated_placements) == 1)
	_check("selected placement keeps the incremental scalar bounds exactly",
		var_to_bytes(shape.bounds) == var_to_bytes(_bounds(expected)))
	_check("added shape owns a separate mesh and leaves both sources unchanged",
		shape.mesh != base and shape.mesh != person
			and base_before == _mesh_bytes(base) and person_before == _mesh_bytes(person))
	population.free()


## Compare with the original complete ordered scan, including the static mesh
## readback that precedes population appends in collect_cell_shape().
func _test_added_bounds_after_mesh_roundtrip() -> void:
	var cell := MeshInstance3D.new()
	cell.name = "cell_0_0"
	var base := _triangle_mesh(PackedVector3Array([
		Vector3(-40000.125, 1.234567, -901.875), Vector3(0.000123, 2.345678, 3.456789),
		Vector3(40000.625, 0.456789, 902.375), Vector3(-40000.0, 2.111111, 900.25),
		Vector3(0.000234, 1.987654, -900.5), Vector3(40000.0, 0.654321, 0.123456),
	]))
	cell.mesh = base
	var person := _triangle_mesh(_join([_face(0, 0.2, 0.7, 1.2), _face(3, 1.5, 1.8, 2.1)]))
	var population := Node3D.new()
	var instance := Transform3D(Basis.from_euler(Vector3(0.37, -0.83, 0.12)).scaled(
		Vector3(-2.0, 0.5, 3.0)), Vector3(40000.75, 3.125, -903.25))
	var child := _make_child(person, _placement(Vector3.ZERO, 0.2), instance)
	population.add_child(child)
	var before_cell := _mesh_bytes(base)
	var before_person := _mesh_bytes(person)
	var static_shape: Dictionary = Projected.collect(cell, 0.04)
	var expected: PackedVector3Array = static_shape.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].duplicate()
	var placed: PackedVector3Array = instance * person.get_faces()
	var accepted := _scalar_above(placed, 0.04)
	expected.append_array(accepted)
	var actual: Dictionary = FieldShadows.collect_cell_shape(cell, population, Vector2.ZERO,
		100.0, 0.04, {"standing:0": CELL_KEY})
	var actual_vertices: PackedVector3Array = actual.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_check("large asymmetric base and transformed population preserve face order and counts",
		actual_vertices.to_byte_array() == expected.to_byte_array()
			and int(actual.triangles) == expected.size() / 3
			and int(actual.population_triangles) == accepted.size() / 3
			and int(actual.population_placements) == 1
			and int(actual.population_elevated_placements) == 1)
	_check("population bounds equal a complete scan of the round-tripped base and appended faces",
		var_to_bytes(actual.bounds) == var_to_bytes(_bounds(expected)))
	_check("bounds fixture preserves independent source meshes",
		actual.mesh != cell.mesh and actual.mesh != person
			and before_cell == _mesh_bytes(base) and before_person == _mesh_bytes(person))
	population.free()
	cell.free()


func _make_child(mesh: Mesh, placement: Dictionary, local_offset: Transform3D,
		count: int = 1, shown: bool = true) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = count
	var child := MultiMeshInstance3D.new()
	child.multimesh = multi
	child.set_meta("source_asset", "standing")
	child.set_meta("placements", [placement])
	child.set_meta("instance_transforms", [local_offset])
	child.visible = shown
	return child


func _placement(origin: Vector3, foot_height: float = 0.0) -> Dictionary:
	return {"transform": Transform3D(Basis.IDENTITY, origin), "foot_height": foot_height}


func _triangle_mesh(points: PackedVector3Array) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _mesh_bytes(mesh: ArrayMesh) -> PackedByteArray:
	return var_to_bytes(mesh.surface_get_arrays(0) if mesh.get_surface_count() > 0 else [])


func _bounds(points: PackedVector3Array) -> AABB:
	var box := AABB(points[0], Vector3.ZERO)
	for point: Vector3 in points:
		box = box.expand(point)
	return box


func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failed += 1
		printerr("FAIL ", label)

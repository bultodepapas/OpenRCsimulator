## DT-11a: exact face ordering and height thresholds after native bulk transforms.
extends SceneTree

var Collector: Script
var _checks := 0
var _failed := 0

func _initialize() -> void:
	Collector = load("res://render/projected_shadow.gd")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--collector="): Collector = load(arg.trim_prefix("--collector="))
	var points := PackedVector3Array([
		Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1),
		Vector3(-1, 0.04, 0), Vector3(1, 0.04, 0), Vector3(0, 0.04, 1),
		Vector3(-1, 0.039, 0), Vector3(1, 0.041, 0), Vector3(0, 0, 1),
		Vector3(2, -4, 3), Vector3(2, -4, 3), Vector3(2, -4, 3),
	])
	var mesh := _mesh(points)
	# Compare the mesh's face stream: upload/readback may quantize authored vertices.
	points = mesh.get_faces()
	var before := var_to_bytes(mesh.surface_get_arrays(0))
	var model := Node3D.new()
	model.position = Vector3(40, 90, 12) # Root placement never enters local silhouette coordinates.
	var frame := Node3D.new()
	model.add_child(frame)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	frame.add_child(instance)
	var poses: Array[Transform3D] = [Transform3D.IDENTITY,
		Transform3D(Basis.from_euler(Vector3(0.37, -0.83, 0.12)).scaled(Vector3(-2, 0.5, 3)), Vector3(1.2, -3.1, 4.7)),
		Transform3D(Basis(Vector3(1, 0.2, 0), Vector3(0.3, 1, 0), Vector3(0, 0.1, 2)), Vector3(-40000, 2, 40000)),
		Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)]
	for pose in poses:
		frame.transform = pose
		for threshold: float in [-INF, -4.0, 0.0, 0.04, 0.041, float(points[3].y), INF, NAN]:
			var expected := PackedVector3Array()
			for first in range(0, points.size(), 3):
				var a := pose * points[first]
				var b := pose * points[first + 1]
				var c := pose * points[first + 2]
				if maxf(a.y, maxf(b.y, c.y)) <= threshold: continue
				expected.append(a)
				expected.append(b)
				expected.append(c)
			_check_shape(Collector.collect(model, threshold), expected)
	_check("source mesh arrays remain unchanged", before == var_to_bytes(mesh.surface_get_arrays(0)))
	frame.visible = false
	_check("hidden ancestor excludes packed geometry", Collector.collect(model).is_empty())
	frame.visible = true
	frame.name = "propeller"
	_check("propeller subtree stays excluded", Collector.collect(model).is_empty())
	model.free()
	var root_mesh := MeshInstance3D.new()
	root_mesh.mesh = mesh
	root_mesh.position = Vector3(9, 8, 7)
	_check_shape(Collector.collect(root_mesh), points)
	root_mesh.free()
	var empty := Node3D.new()
	_check("empty model remains empty", Collector.collect(empty).is_empty())
	empty.free()
	print("shadow collection: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed else 0)

func _mesh(points: PackedVector3Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _check_shape(shape: Dictionary, expected: PackedVector3Array) -> void:
	if expected.is_empty():
		_check("height cutoff rejects all faces", shape.is_empty())
		return
	_check("accepted faces produce a mesh", not shape.is_empty())
	if shape.is_empty(): return
	var arrays: Array = shape.mesh.surface_get_arrays(0)
	_check("complete face bytes and order match scalar oracle",
		(arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).to_byte_array() == expected.to_byte_array())
	var bounds := AABB(expected[0], Vector3.ZERO)
	for point in expected: bounds = bounds.expand(point)
	_check("incremental bounds and triangle count stay exact", var_to_bytes(bounds) == var_to_bytes(shape.bounds) and shape.triangles == expected.size() / 3)

func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failed += 1
		printerr("FAIL ", label)

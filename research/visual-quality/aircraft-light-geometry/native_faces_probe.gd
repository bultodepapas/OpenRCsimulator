extends SceneTree
const Lights = preload("res://render/world/aircraft_lights.gd")

func _initialize() -> void:
	var model := Node3D.new()
	var item := MeshInstance3D.new()
	model.add_child(item)
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.BACK])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.BACK, Vector3(1, 0, 1)])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays)
	item.mesh = mesh
	var current := Lights.triangles(model)
	var native := mesh.get_faces()
	print("Current triangle-surface vertices: ", current.size(), "; native get_faces vertices: ", native.size())
	var mismatch := current.size() == 3 and native.size() == 9
	model.free()
	quit(0 if mismatch else 1)

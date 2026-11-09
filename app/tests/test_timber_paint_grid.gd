## TT-21: indexed paint coverage preserves exhaustive geometry and material order.
extends SceneTree

const Details := preload("res://aircraft/timber_visual_details.gd")
var _checks := 0
var _failed := 0


func _check(passed: bool, label: String) -> void:
	_checks += 1
	if not passed:
		_failed += 1
		printerr("FAIL ", label)


func _face(material: String, offset: Vector3 = Vector3.ZERO) -> Dictionary:
	var vertices := PackedVector3Array([
		offset + Vector3(-0.02, -0.02, 0), offset + Vector3(0.02, -0.02, 0), offset + Vector3(-0.02, 0.02, 0)])
	return {material = material, vertices = vertices, normal = Vector3.BACK,
		bounds = AABB(vertices[0], Vector3.ZERO).expand(vertices[1]).expand(vertices[2]).grow(0.002)}


func _initialize() -> void:
	var faces: Array[Dictionary] = [_face("red"), _face("blue"), _face("red", Vector3(0, 0, 0.001))]
	var index: Dictionary = Details._build_paint_face_index(faces)
	_check(not index.is_empty(), "face index covers signed cells")
	for x: float in [-0.03, -0.02, -0.010001, -0.01, -0.000001, 0, 0.009999, 0.01, 0.02, 0.03]:
		for y: float in [-0.02, -0.01, 0, 0.01, 0.02]:
			for z: float in [-0.001, 0, 0.001]:
				var point := Vector3(x, y, z)
				var exhaustive: Dictionary = Details._covering_paint_at(point, Vector3.BACK, faces, 0.002, 0.9)
				var indexed: Dictionary = Details._covering_paint_at(point, Vector3.BACK, faces, 0.002, 0.9, index)
				_check(var_to_bytes(indexed) == var_to_bytes(exhaustive), "indexed coverage matches ordered exhaustive results at " + str(point))
	var interior := Vector3(-0.01, -0.01, 0)
	_check(Details._covering_paint_at(interior, Vector3.FORWARD, faces, 0.002, 0.9, index).is_empty(), "opposite normals reject coverage")
	_check(Details._covering_paint_at(interior + Vector3(0, 0, 0.0015), Vector3.BACK, faces, 0.0001, 0.9, index).is_empty(), "distance threshold rejects coverage")
	var missing_bucket := {Vector3i(100, 100, 100): []}
	_check(Details._covering_paint_at(interior, Vector3.BACK, faces, 0.002, 0.9, missing_bucket).is_empty(), "missing bucket does not fall back to covering faces")
	var empty: Array[Dictionary] = []
	_check(Details._build_paint_face_index(empty).is_empty(), "empty input retains empty-index fallback")
	var a := Vector3(-0.015, -0.015, 0)
	var b := Vector3(-0.01, -0.015, 0)
	var c := Vector3(-0.015, -0.01, 0)
	_check(Details._fully_covered_paint(a, b, c, Vector3.BACK, faces, 0.002, 0.9, index) == "red", "equal material distances retain first material")
	faces.reverse()
	index = Details._build_paint_face_index(faces)
	_check(var_to_bytes(Details._covering_paint_at(interior, Vector3.BACK, faces, 0.002, 0.9, index))
		== var_to_bytes(Details._covering_paint_at(interior, Vector3.BACK, faces, 0.002, 0.9)), "reordered input preserves material insertion order")
	print("Timber paint grid: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed else 0)

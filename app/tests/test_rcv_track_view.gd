extends SceneTree
const Course := preload("res://physics/ground_vehicle/airfield_course.gd")
const Field := preload("res://data/field_loader.gd")
const View := preload("res://vehicles/ground/airfield_track_view.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok: failures += 1

func _initialize() -> void:
	var built := Course.build(Field.load_from())
	check(built.ok, "default course loads")
	if not built.ok:
		printerr(built.errors)
		quit(1)
		return
	var course: Dictionary = built.course
	var road := func(n: float, e: float) -> Dictionary: return Course.sample(course, n, e)
	var view := View.build(course, road)
	var surface := view.get_node("DirtLoopSurface") as MeshInstance3D
	var arrays := surface.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var max_vertex_error := 0.0
	var max_face_error := 0.0
	var max_normal_error := 0.0
	var winding_valid := true
	for triangle in range(0, int(indices.size() / 3), 17):
		var a := vertices[indices[triangle * 3]]
		var b := vertices[indices[triangle * 3 + 1]]
		var c := vertices[indices[triangle * 3 + 2]]
		var normal := normals[indices[triangle * 3]]
		winding_valid = winding_valid and (b - a).cross(c - a).dot(normal) < 0.0
		var sample: Dictionary = road.call(-a.z, a.x)
		max_vertex_error = maxf(max_vertex_error, absf(a.y - float(sample.height_m) - 0.002))
		var nd: PackedFloat64Array = sample.normal_ned
		max_normal_error = maxf(max_normal_error, normal.distance_to(Vector3(nd[1], -nd[2], -nd[0])))
		var midpoint := (a + b + c) / 3.0
		max_face_error = maxf(max_face_error, absf(midpoint.y - float(road.call(-midpoint.z, midpoint.x).height_m) - 0.002))
	check(max_vertex_error < 0.00001, "render vertices match physics height plus 2 mm separation: %.8f m" % max_vertex_error)
	check(max_face_error < 0.008, "triangle interpolation error stays below 8 mm: %.6f m" % max_face_error)
	# ArrayMesh packs normals; its angular quantization is distinct from the float64 sampler.
	check(max_normal_error < 0.0002, "render normals match physical gradient within packed-normal precision: %.8f" % max_normal_error)
	check(winding_valid, "terrain uses visible clockwise Godot front faces")
	for wall: Dictionary in course.track.walls:
		var rendered := view.get_node(str(wall.id)) as MeshInstance3D
		var bounds := rendered.get_aabb()
		var lower := bounds.position + rendered.position
		var upper := lower + bounds.size
		check(lower.is_equal_approx(Vector3(wall.east_min_m, wall.bottom_up_m, -float(wall.north_max_m))) and upper.is_equal_approx(Vector3(wall.east_max_m, wall.top_up_m, -float(wall.north_min_m))), "wall mesh matches its collision bounds: " + str(wall.id))
	check(view.find_children("*", "CollisionObject3D", true, false).is_empty(), "renderer creates no second physical world")
	view.free()
	print("RCV track view: %d failures" % failures)
	quit(1 if failures else 0)

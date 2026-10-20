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
	var barrier_triangles := 0
	for wall: Dictionary in course.track.walls:
		var rendered := view.get_node(str(wall.id)) as MeshInstance3D
		var bounds := rendered.get_aabb()
		var lower := bounds.position + rendered.position
		var upper := lower + bounds.size
		check(lower.is_equal_approx(Vector3(wall.east_min_m, wall.bottom_up_m, -float(wall.north_max_m))) and upper.is_equal_approx(Vector3(wall.east_max_m, wall.top_up_m, -float(wall.north_min_m))), "wall mesh matches its collision bounds: " + str(wall.id))
		var barrier_mesh := rendered.mesh as ArrayMesh
		check(barrier_mesh != null and barrier_mesh.get_surface_count() > 0, "wall has fitted source geometry: " + str(wall.id))
		if barrier_mesh != null and barrier_mesh.get_surface_count() > 0:
			var barrier_arrays := barrier_mesh.surface_get_arrays(0)
			var barrier_vertices: PackedVector3Array = barrier_arrays[Mesh.ARRAY_VERTEX]
			var barrier_uvs: PackedVector2Array = barrier_arrays[Mesh.ARRAY_TEX_UV]
			var barrier_indices: PackedInt32Array = barrier_arrays[Mesh.ARRAY_INDEX]
			barrier_triangles += barrier_indices.size() / 3
			check(barrier_vertices.size() > 500 and barrier_uvs.size() == barrier_vertices.size(), "wall retains detailed mapped geometry: " + str(wall.id))
			var finish := barrier_mesh.surface_get_material(0) as BaseMaterial3D
			check(finish != null and finish.albedo_texture != null and finish.normal_texture != null, "wall retains source PBR maps: " + str(wall.id))
	check(barrier_triangles > 0 and barrier_triangles < 40000, "five fitted barriers stay within render geometry budget: %d triangles" % barrier_triangles)
	var furniture := view.get_node("TrackFurniture") as Node3D
	var clear_signs := true
	for sign_name in ["AccessSign", "JumpsSign", "SlalomSign", "RollersSign"]:
		var sign_root := furniture.get_node(sign_name) as Node3D
		for sample_index in range(8):
			var angle := TAU * float(sample_index) / 8.0
			var east := sign_root.position.x + cos(angle) * 0.65
			var north := -sign_root.position.z + sin(angle) * 0.65
			clear_signs = clear_signs and float(road.call(north, east).track_coverage) < 0.0001
	check(clear_signs, "all sign footprints remain clear of the sampled road")
	var stacks := view.get_node("TrackTyreStacks") as Node3D
	var tyres := stacks.find_children("WornTyre*", "MeshInstance3D", true, false)
	var clear_tyres := true
	for stack in stacks.get_children():
		var anchor := stack as Node3D
		for sample_index in range(8):
			var angle := TAU * float(sample_index) / 8.0
			var east := anchor.position.x + cos(angle) * 0.35
			var north := -anchor.position.z + sin(angle) * 0.35
			clear_tyres = clear_tyres and float(road.call(north, east).track_coverage) < 0.0001
	check(clear_tyres, "tyre stacks remain beyond the sampled road shoulder")
	check(tyres.size() == 8, "eight sourced worn tyres dress the off-course margins")
	if not tyres.is_empty():
		var tyre_mesh := (tyres[0] as MeshInstance3D).mesh
		var tyre_finish := tyre_mesh.surface_get_material(0) as BaseMaterial3D
		check(tyre_finish != null and tyre_finish.albedo_texture != null and tyre_finish.normal_texture != null and tyre_finish.roughness_texture != null, "tyre source retains color, normal and roughness maps")
	check(view.find_children("*", "CollisionObject3D", true, false).is_empty(), "renderer creates no second physical world")
	view.free()
	print("RCV track view: %d failures" % failures)
	quit(1 if failures else 0)

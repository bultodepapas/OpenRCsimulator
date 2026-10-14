extends SceneTree
const Builder = preload("res://render/airplane.gd")
const Candidate = preload("res://render/crash/airframe_scuffs.gd")
const FLEET = ["jensen-das-ugly-stik-60", "stik-glow-61fx-2t", "stik-glow-55ax-2t", "stik-glow-fs64v-4t", "gp-extra-300s-60", "p51d-mustang-120", "sebart-avanti-s-a200-p100rx", "turbo-lumber-evolution"]
var failed := 0
var reference_path := ""
var output_path := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--reference="): reference_path = arg.trim_prefix("--reference=")
		if arg.begins_with("--out="): output_path = arg.trim_prefix("--out=")
	_run.call_deferred()

func _run() -> void:
	var reference = load(reference_path)
	var results: Array = []
	for aircraft in FLEET:
		var plane: Dictionary = Builder.build(aircraft)
		root.add_child(plane.root)
		plane.root.position = Vector3(10, 2, 20)
		plane.root.rotation = Vector3(0.11, 0.37, -0.08)
		var before = reference.new()
		var after = Candidate.new()
		var stamp := Time.get_ticks_usec()
		after.prepare(plane.root)
		var prepare_us := Time.get_ticks_usec() - stamp
		var meshes: Array = []
		for mi: MeshInstance3D in reference._candidates(plane.root):
			var faces := mi.mesh.get_faces()
			if faces.size() >= 3: meshes.append({node=mi, faces=faces})
		meshes.sort_custom(func(a, b): return a.faces.size() > b.faces.size())
		for item in meshes.slice(0, 4):
			var mi: MeshInstance3D = item.node
			var faces: PackedVector3Array = item.faces
			var point := Vector3.ZERO
			var lowest := INF
			for i in range(0, faces.size(), 3):
				var center := mi.global_transform * ((faces[i] + faces[i+1] + faces[i+2]) / 3.0)
				if center.y < lowest:
					lowest = center.y
					point = center
			point += Vector3.DOWN * 0.005
			stamp = Time.get_ticks_usec()
			var old_mark: MeshInstance3D = before.add(plane.root, point, Vector3(3, 0, -15), 0.6, "mown")
			var reference_us := Time.get_ticks_usec() - stamp
			stamp = Time.get_ticks_usec()
			var new_mark: MeshInstance3D = after.add(plane.root, point, Vector3(3, 0, -15), 0.6, "mown")
			var candidate_us := Time.get_ticks_usec() - stamp
			var error := 0.0
			var reference_on := 0
			var candidate_on := 0
			var ok := (old_mark == null) == (new_mark == null)
			if old_mark != null and new_mark != null:
				ok = old_mark.get_parent() == new_mark.get_parent()
				var a: PackedVector3Array = old_mark.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				var b: PackedVector3Array = new_mark.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				for j in a.size(): error = maxf(error, a[j].distance_to(b[j]))
				# The existing skin fit contract is 1.5 mm; near-tangent rays may differ
				# below 1 mm when world-space float32 tests move into mesh-local space.
				ok = ok and error < 0.001
				var normal: Vector3 = (new_mark.global_basis * (new_mark.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL] as PackedVector3Array)[0]).normalized()
				var center := new_mark.global_transform * b[8]
				var triangles: PackedVector3Array = reference._nearby_triangles(reference._candidates(plane.root), center, 0.3)
				for j in b.size():
					if _on_skin(triangles, old_mark.global_transform * a[j], normal): reference_on += 1
					if _on_skin(triangles, new_mark.global_transform * b[j], normal): candidate_on += 1
				ok = ok and candidate_on >= reference_on
			if not ok: failed += 1
			var row := {aircraft=aircraft, mesh=str(mi.name), hit=old_mark != null, ok=ok, max_vertex_error_m=error, reference_on_skin=reference_on, candidate_on_skin=candidate_on, reference_us=reference_us, candidate_us=candidate_us, prepare_us=prepare_us}
			results.append(row)
			print(JSON.stringify(row))
		before.clear()
		after.clear()
		plane.root.free()
	FileAccess.open(output_path, FileAccess.WRITE).store_string(JSON.stringify(results, "\t"))
	print("32 scuff comparisons, %d failed" % failed)
	quit(1 if failed else 0)

func _on_skin(triangles: PackedVector3Array, world: Vector3, normal: Vector3) -> bool:
	var a := (world + normal * 0.0015) * 1000.0
	var b := (world - normal * 0.0015) * 1000.0
	for i in range(0, triangles.size(), 3):
		if Geometry3D.segment_intersects_triangle(a, b, triangles[i] * 1000.0, triangles[i+1] * 1000.0, triangles[i+2] * 1000.0) != null:
			return true
	return false

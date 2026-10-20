extends SceneTree
const Timber := preload("res://aircraft/timber_model.gd")
const Details := preload("res://aircraft/timber_visual_details.gd")
const Imported := preload("res://aircraft/imported_model.gd")
func _initialize() -> void:
	var model = Timber.build()
	var root = model.root as Node3D
	get_root().add_child(root)
	var cowl := root.find_child("cowl", true, false) as MeshInstance3D
	var paint_faces: Array[Dictionary] = []
	var white_surfaces: Array[int] = []
	for surface in cowl.mesh.get_surface_count():
		var material := cowl.get_active_material(surface) as Material
		var name := material.resource_name if material else ""
		var arrays := cowl.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices := Details._triangle_indices(arrays, vertices.size())
		if name == "white":
			white_surfaces.append(surface)
		elif name in ["black", "red", "dark_grey"]:
			for triangle in range(indices.size() / 3):
				var ia := indices[triangle * 3]
				var ib := indices[triangle * 3 + 1]
				var ic := indices[triangle * 3 + 2]
				var a := vertices[ia]
				var b := vertices[ib]
				var d := vertices[ic]
				var normal := Details._surface_triangle_normal(arrays, vertices, ia, ib, ic)
				var bounds := AABB(a, Vector3.ZERO).expand(b).expand(d).grow(0.004)
				paint_faces.append({vertices = PackedVector3Array([a,b,d]), bounds = bounds, normal = normal, material = name})
	var white_count := 0
	for surface in white_surfaces:
		var arrays := cowl.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices := Details._triangle_indices(arrays, vertices.size())
		for triangle in range(indices.size() / 3):
			var ia := indices[triangle * 3]
			var ib := indices[triangle * 3 + 1]
			var ic := indices[triangle * 3 + 2]
			var a := vertices[ia]
			var b := vertices[ib]
			var d := vertices[ic]
			var center := (a + b + d) / 3.0
			var normal := Details._surface_triangle_normal(arrays, vertices, ia, ib, ic)
			var bounds := AABB(a, Vector3.ZERO).expand(b).expand(d)
			if center.y < 0.014 or center.z > -0.15 or center.z < -0.24 or bounds.size.x > 0.025:
				continue
			var strict := Details._fully_covered_paint(a,b,d,normal,paint_faces,0.002,0.82)
			var relaxed := Details._fully_covered_paint(a,b,d,normal,paint_faces,0.004,-0.1)
			var patch := ""
			if absf(center.x) < 0.05 and center.y > 0.02 and center.z > -0.18:
				patch = "aft-upper"
			elif absf(center.x) < 0.05 and center.y > 0.02 and center.z < -0.215:
				patch = "nose-upper"
			if not strict.is_empty() or not relaxed.is_empty() or not patch.is_empty():
				print("WHITE cowl tri=%d center=%s normal=%s strict=%s relaxed=%s patch=%s verts=%s %s %s" % [triangle, center, normal, strict, relaxed, patch, a,b,d])
				white_count += 1
	print("white upper candidates=", white_count)
	quit()

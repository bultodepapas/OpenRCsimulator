extends SceneTree
const Timber := preload("res://aircraft/timber_model.gd")
const Details := preload("res://aircraft/timber_visual_details.gd")
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
		if name == "white": white_surfaces.append(surface)
		elif name in ["black", "red", "dark_grey"]:
			for t in range(indices.size() / 3):
				var ia = indices[t * 3]; var ib = indices[t * 3 + 1]; var ic = indices[t * 3 + 2]
				var a = vertices[ia]; var b = vertices[ib]; var c = vertices[ic]
				paint_faces.append({vertices=PackedVector3Array([a,b,c]),bounds=AABB(a,Vector3.ZERO).expand(b).expand(c).grow(0.01),normal=Details._surface_triangle_normal(arrays,vertices,ia,ib,ic),material=name})
	var stats: Dictionary = {}
	for surface in white_surfaces:
		var arrays := cowl.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices := Details._triangle_indices(arrays, vertices.size())
		for t in range(indices.size() / 3):
			var ia = indices[t * 3]; var ib = indices[t * 3 + 1]; var ic = indices[t * 3 + 2]
			var a = vertices[ia]; var b = vertices[ib]; var c = vertices[ic]
			var center: Vector3 = (a+b+c)/3.0
			if center.y < 0.012 or absf(center.x) > 0.05: continue
			var zone := "aft" if center.z > -0.185 else "mid" if center.z > -0.213 else "nose"
			for label in ["d2_n82", "d4_n10", "d8_n10", "d8_n50"]:
				var distance = 0.002 if label == "d2_n82" else 0.004 if label == "d4_n10" else 0.008
				var dot = 0.82 if label == "d2_n82" else -0.1 if label != "d8_n50" else -0.5
				var covered := Details._fully_covered_paint(a,b,c,Details._surface_triangle_normal(arrays,vertices,ia,ib,ic),paint_faces,distance,dot)
				var key: String = zone + "/" + label + "/" + covered
				stats[key] = int(stats.get(key,0)) + 1
	print(JSON.stringify(stats, "  "))
	quit()


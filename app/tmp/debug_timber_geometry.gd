extends SceneTree

const Timber := preload("res://aircraft/timber_model.gd")
const TimberGeometry := preload("res://aircraft/timber_geometry.gd")
const VisualData := preload("res://assets/aircraft/turbo-lumber-evolution/visual-upgrade/visual_detail_data.gd")
const Imported := preload("res://aircraft/imported_model.gd")

func _initialize() -> void:
	var model := Timber.build()
	var root := model.root as Node3D
	get_root().add_child(root)
	for target_name: String in ["gear_cables", "fuselage_core", "cowl", "wing_left_fixed", "wing_right_fixed"]:
		var target := root.find_child(target_name, true, false) as MeshInstance3D
		print("TARGET ", target_name, " surfaces=", target.mesh.get_surface_count(), " transform=", Imported.relative(root, target))
		for surface_index in target.mesh.get_surface_count():
			var arrays := target.mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var low := Vector3(INF, INF, INF)
			var high := Vector3(-INF, -INF, -INF)
			for vertex in vertices:
				low = low.min(vertex)
				high = high.max(vertex)
			print("SURFACE ", surface_index, " material=", target.get_active_material(surface_index).resource_name, " count=", vertices.size(), " local_bounds=", low, " -> ", high)
		if target_name in ["cowl", "fuselage_core", "wing_left_fixed", "wing_right_fixed"]:
			_report_coverage(target)
		if target_name == "gear_cables":
			var vertices: PackedVector3Array = target.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for cable: Dictionary in VisualData.DATA.main_gear_cables:
				print("CABLE ", cable)
				var a := Vector3(cable.start[0], cable.start[1], cable.start[2])
				var b := Vector3(cable.end[0], cable.end[1], cable.end[2])
				var axis := (b - a).normalized()
				var counts := PackedInt32Array()
				var min_radii := PackedFloat32Array()
				var max_radii := PackedFloat32Array()
				for bin in 10:
					counts.append(0)
					min_radii.append(INF)
					max_radii.append(0.0)
				for vertex in vertices:
					var t := (vertex - a).dot(axis) / a.distance_to(b)
					if t < 0.0 or t > 1.0:
						continue
					var radial := (vertex - (a + (b - a) * t)).length()
					if radial > 0.012:
						continue
					var bin := clampi(floori(t * 10.0), 0, 9)
					counts[bin] += 1
					min_radii[bin] = minf(min_radii[bin], radial)
					max_radii[bin] = maxf(max_radii[bin], radial)
				print("  bins count=", counts, " min_radius=", min_radii, " max_radius=", max_radii)
	var root_meshes: Array = root.find_children("*", "MeshInstance3D", true, false)
	for mesh_instance: MeshInstance3D in root_meshes:
		if "cowl" in mesh_instance.name.to_lower() or "fuselage" in mesh_instance.name.to_lower():
			print("SURFACE HOST ", mesh_instance.name, " bounds=", mesh_instance.mesh.get_aabb())
	quit()

func _report_coverage(target: MeshInstance3D) -> void:
	var paint_triangles: Array[Dictionary] = []
	for surface_index in target.mesh.get_surface_count():
		var material := target.get_active_material(surface_index) as StandardMaterial3D
		if material == null or not ["black", "red", "dark_grey"].has(material.resource_name):
			continue
		var arrays := target.mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			indices.resize(vertices.size())
			for vertex_index in vertices.size(): indices[vertex_index] = vertex_index
		for triangle in range(0, indices.size(), 3):
			var a := vertices[indices[triangle]]
			var b := vertices[indices[triangle + 1]]
			var c := vertices[indices[triangle + 2]]
			paint_triangles.append({center = (a + b + c) / 3.0, normal = (b - a).cross(c - a).normalized(), material = material})
	var thresholds := PackedInt32Array([0, 0, 0, 0, 0])
	var total := 0
	var indices := target.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array
	var vertices := target.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	if indices.is_empty():
		indices.resize(vertices.size())
		for vertex_index in vertices.size(): indices[vertex_index] = vertex_index
	for triangle in range(0, indices.size(), 3):
		var a := vertices[indices[triangle]]
		var b := vertices[indices[triangle + 1]]
		var c := vertices[indices[triangle + 2]]
		var center := (a + b + c) / 3.0
		var normal := (b - a).cross(c - a).normalized()
		var nearest_distance := INF
		var nearest_dot := -1.0
		for paint: Dictionary in paint_triangles:
			var distance := center.distance_to(paint.center)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_dot = normal.dot(paint.normal)
		total += 1
		for threshold_index in thresholds.size():
			if nearest_distance <= [0.001, 0.002, 0.004, 0.008, 0.016][threshold_index] and nearest_dot >= 0.7:
				thresholds[threshold_index] += 1
	print("  paint coverage candidates=", paint_triangles.size(), " white_triangles=", total, " covered=", thresholds)

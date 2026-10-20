extends SceneTree

const Timber := preload("res://aircraft/timber_model.gd")
const TimberGeometry := preload("res://aircraft/timber_geometry.gd")
const Imported := preload("res://aircraft/imported_model.gd")

func _initialize() -> void:
	var model := Timber.build()
	var root := model.root as Node3D
	get_root().add_child(root)
	for target_name: String in ["gear_cables", "fuselage_core"]:
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
		if target_name == "gear_cables":
			for i in range(0, 4):
				var cable: Dictionary = TimberGeometry.DATA.main_gear_cables[i]
				print("CABLE ", cable)
				var a := Vector3(cable.start[0], cable.start[1], cable.start[2])
				var b := Vector3(cable.end[0], cable.end[1], cable.end[2])
				for j in range(0, 11):
					var t := float(j) / 10.0
					var p := a.lerp(b, t)
					print("  ", t, " -> ", p)
	quit()

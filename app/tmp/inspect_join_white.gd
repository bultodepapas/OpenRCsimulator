extends SceneTree
const Timber := preload("res://aircraft/timber_model.gd")
const Details := preload("res://aircraft/timber_visual_details.gd")
func _initialize() -> void:
	var model = Timber.build()
	var root = model.root as Node3D
	Details.apply(root)
	get_root().add_child(root)
	for mesh_name in ["cowl", "fuselage_core"]:
		var host := root.find_child(mesh_name, true, false) as MeshInstance3D
		print("HOST ", mesh_name, " meta=", host.get_meta_list(), " remap=", host.get_meta("timber_paint_seam_faces", -1), " surfaces=", host.mesh.get_surface_count())
		for s in host.mesh.get_surface_count():
			var material := host.get_active_material(s) as Material
			if material == null or material.resource_name != "white": continue
			var arrays := host.mesh.surface_get_arrays(s)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices := Details._triangle_indices(arrays, vertices.size())
			for t in range(indices.size()/3):
				var ia=indices[t*3]; var ib=indices[t*3+1]; var ic=indices[t*3+2]
				var a=vertices[ia]; var b=vertices[ib]; var c=vertices[ic]
				var center: Vector3=(a+b+c)/3.0
				if center.z > -0.162 and center.z < -0.154 and center.y > 0.005 and absf(center.x) < 0.055:
					print(" white surface ",s," tri ",t," center=",center," normal=",Details._surface_triangle_normal(arrays,vertices,ia,ib,ic)," verts=",a," / ",b," / ",c)
	quit()

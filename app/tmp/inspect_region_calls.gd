extends SceneTree
const Timber := preload("res://aircraft/timber_model.gd")
const Details := preload("res://aircraft/timber_visual_details.gd")
const Data := preload("res://assets/aircraft/turbo-lumber-evolution/visual-upgrade/visual_detail_data.gd")
func _initialize() -> void:
	var model = Timber.build(); var root = model.root as Node3D; get_root().add_child(root)
	var host := root.find_child("cowl", true, false) as MeshInstance3D
	var faces: Array[Dictionary] = []
	for s in host.mesh.get_surface_count():
		var material := host.get_active_material(s) as Material
		if material == null or material.resource_name not in ["black", "red", "dark_grey"]: continue
		var arrays := host.mesh.surface_get_arrays(s); var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]; var indices := Details._triangle_indices(arrays,vertices.size())
		for t in range(indices.size()/3):
			var ia=indices[t*3]; var ib=indices[t*3+1]; var ic=indices[t*3+2]; var a=vertices[ia]; var b=vertices[ib]; var c=vertices[ic]
			faces.append({vertices=PackedVector3Array([a,b,c]),bounds=AABB(a,Vector3.ZERO).expand(b).expand(c).grow(0.004),normal=Details._surface_triangle_normal(arrays,vertices,ia,ib,ic),material=material.resource_name})
	var arrays := host.mesh.surface_get_arrays(0); var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]; var indices := Details._triangle_indices(arrays,vertices.size())
	for target_tri in [43,44,45,46,1066,1067,1077,1079]:
		var ia=indices[target_tri*3]; var ib=indices[target_tri*3+1]; var ic=indices[target_tri*3+2]; var a=vertices[ia]; var b=vertices[ib]; var c=vertices[ic]; var normal=Details._surface_triangle_normal(arrays,vertices,ia,ib,ic)
		print("tri ",target_tri," centroid=",(a+b+c)/3.0," strict=",Details._fully_covered_paint(a,b,c,normal,faces,0.002,0.82)," relaxed=",Details._fully_covered_paint(a,b,c,normal,faces,0.004,-0.1)," regions=",Details._authored_paint_region(root,host,a,b,c,normal,faces,Data.DATA.paint_seam_repair.authored_paint_regions))
	quit()

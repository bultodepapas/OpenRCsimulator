extends SceneTree
const Timber := preload("res://aircraft/timber_model.gd")
const Details := preload("res://aircraft/timber_visual_details.gd")
func _initialize() -> void:
	var raw_model = Timber.build(); var raw_root = raw_model.root as Node3D
	var visual_model = Timber.build(); var visual_root = visual_model.root as Node3D; Details.apply(visual_root)
	for name in ["cowl", "fuselage_core"]:
		var raw := raw_root.find_child(name,true,false) as MeshInstance3D
		var visual := visual_root.find_child(name,true,false) as MeshInstance3D
		var after: Dictionary = {}
		for s in visual.mesh.get_surface_count():
			var material := visual.get_active_material(s) as Material
			var mat_name = material.resource_name if material else "?"
			var arrays := visual.mesh.surface_get_arrays(s); var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]; var indices := Details._triangle_indices(arrays,vertices.size())
			for t in range(indices.size()/3):
				var key := _key(vertices[indices[t*3]],vertices[indices[t*3+1]],vertices[indices[t*3+2]])
				after[key] = mat_name
		for s in raw.mesh.get_surface_count():
			var material := raw.get_active_material(s) as Material
			if material == null or material.resource_name != "white": continue
			var arrays := raw.mesh.surface_get_arrays(s); var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]; var indices := Details._triangle_indices(arrays,vertices.size())
			for t in range(indices.size()/3):
				var ia=indices[t*3]; var ib=indices[t*3+1]; var ic=indices[t*3+2]; var a=vertices[ia]; var b=vertices[ib]; var c=vertices[ic]; var center:Vector3=(a+b+c)/3.0
				if absf(center.x)>0.051 or center.y<0.012 or center.z < -0.160 or center.z > -0.154: continue
				var key := _key(a,b,c)
				print("raw tri=",t," center=",center," normal=",Details._surface_triangle_normal(arrays,vertices,ia,ib,ic)," after=",after.get(key,"MISSING"))
	quit()
func _key(a:Vector3,b:Vector3,c:Vector3)->String:
	var points := [a,b,c]
	points.sort_custom(func(x:Vector3,y:Vector3)->bool:return x.x < y.x if not is_equal_approx(x.x,y.x) else x.y < y.y if not is_equal_approx(x.y,y.y) else x.z < y.z)
	return "%.6f,%.6f,%.6f|%.6f,%.6f,%.6f|%.6f,%.6f,%.6f" % [points[0].x,points[0].y,points[0].z,points[1].x,points[1].y,points[1].z,points[2].x,points[2].y,points[2].z]


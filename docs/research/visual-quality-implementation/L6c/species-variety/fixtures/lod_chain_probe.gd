extends SceneTree
const Library = preload("res://scenery/imported_vegetation.gd")
func _initialize() -> void:
	for id: String in ["landscapelab_quercus", "landscapelab_pine", "landscapelab_fagus", "landscapelab_quercus2", "maple_tree"]:
		for part: Dictionary in Library.get_parts(id):
			var mesh: Mesh = part.mesh
			var aabb: AABB = mesh.get_aabb()
			for s in mesh.get_surface_count():
				var info: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), s)
				var base := int(info.get("index_count", 0)) / 3
				var mat: Material = mesh.surface_get_material(s)
				var lods: Array = info.get("lods", [])
				var chain := []
				for lod: Dictionary in lods:
					chain.append("%.4f:%d(%.0f%%)" % [float(lod.edge_length), lod.index_data.size() / (4 if base * 3 > 65535 else 2) / 3, 100.0 * float(lod.index_data.size() / (4 if base * 3 > 65535 else 2) / 3) / base])
				print("LOD %s surf %d %s tris %d aabb_h %.2f lods %s" % [id, s, mat.resource_name if mat else "-", base, aabb.size.y, " ".join(chain)])
	quit(0)

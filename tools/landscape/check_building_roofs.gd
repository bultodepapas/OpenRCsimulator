## Standalone source-geometry check; does not depend on the shared scenery loader.
extends SceneTree

const BuildingRoofs = preload("res://scenery/building_roofs.gd")

func _initialize() -> void:
	var count := 0
	var triangles := 0
	for item: Array in [["pavilion", 7, 2], ["shed", 1, 1], ["barn", 2, 1],
			["farmhouse", 3, 1], ["village_house", 23, 1], ["church", 4, 1]]:
		var id := "prop:roof-check:%d" % count
		var roofs: Array[MeshInstance3D] = BuildingRoofs.create(item[0], Transform3D.IDENTITY, item[1], id)
		if roofs.size() != item[2]:
			_fail("wrong roof surface count for " + item[0])
			return
		for roof: MeshInstance3D in roofs:
			if roof.get_meta("damage_motion_id", "") != id or roof.mesh.get_surface_count() != 1:
				_fail("missing damage id or material surface")
				return
			var arrays := roof.mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var material := roof.mesh.surface_get_material(0) as ShaderMaterial
			if verts.size() == 0 or verts.size() != normals.size() or verts.size() != uvs.size() \
					or material == null or not (material.get_shader_parameter("albedo_map") is Texture2D) \
					or not (material.get_shader_parameter("normal_map") is Texture2D) \
					or not (material.get_shader_parameter("arm_map") is Texture2D):
				_fail("missing UVs, normals or PBR maps")
				return
			for i in range(0, verts.size(), 3):
				var facing := (verts[i + 2] - verts[i]).cross(verts[i + 1] - verts[i]).dot(normals[i])
				if facing <= 0.0 or not is_finite(uvs[i].x) or not is_finite(uvs[i].y):
					_fail("reversed or invalid roof triangle")
					return
			triangles += verts.size() / 3
			count += 1
			roof.free()
	if not BuildingRoofs.create("bench", Transform3D.IDENTITY, 0, "unused").is_empty():
		_fail("non-building prefab received a roof")
		return
	print("PASS building roofs: %d surfaces, %d triangles, PBR maps and clockwise faces" % [count, triangles])
	quit()

func _fail(message: String) -> void:
	printerr("FAIL building roofs: " + message)
	quit(1)

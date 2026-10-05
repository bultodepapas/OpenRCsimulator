# Checks built mesh UV coordinates and instance resource boundaries, not chosen RGB values.
extends RefCounted
const Finish := preload("res://aircraft/ugly_stik_finish.gd")
const Geometry := preload("res://aircraft/ugly_stik_geometry.gd")
var checks := 0
var failures: Array[String] = []

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok: failures.append(label)

func run(airplane: Dictionary) -> Dictionary:
	var skin := Finish.covering()
	check("atlas loaded", skin.albedo_texture != null)
	if skin.albedo_texture == null: return {"checks": checks, "failures": failures, "ok": false}
	var image := skin.albedo_texture.get_image()
	check("atlas has mip chain", image.has_mipmaps())
	check("atlas is square and intended resolution", image.get_size() == Vector2i(1024, 1024))
	check("atlas does not multiply colored tint", skin.albedo_color.is_equal_approx(Color.WHITE))
	var total_uvs := 0
	var winding_triangles := 0
	for node in airplane.root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		for surface in instance.mesh.get_surface_count():
			var mesh_arrays := instance.mesh.surface_get_arrays(surface)
			var positions: PackedVector3Array = mesh_arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = mesh_arrays[Mesh.ARRAY_NORMAL]
			var indices: Variant = mesh_arrays[Mesh.ARRAY_INDEX]
			var count: int = positions.size() if indices == null or indices.is_empty() else indices.size()
			var valid_winding := true
			for i in range(0, count, 3):
				var a: int = i if indices == null or indices.is_empty() else indices[i]
				var b: int = i+1 if indices == null or indices.is_empty() else indices[i+1]
				var c: int = i+2 if indices == null or indices.is_empty() else indices[i+2]
				var face := (positions[c] - positions[a]).cross(positions[b] - positions[a])
				if face.length_squared() < 1e-20: continue
				var expected := normals[a] + normals[b] + normals[c]
				valid_winding = valid_winding and face.dot(expected) > 0.000001 * face.length() * expected.length()
				winding_triangles += 1
			check("clockwise faces agree with normals " + String(instance.name) + ":" + str(surface), valid_winding)
			if instance.mesh.surface_get_material(surface) != skin: continue
			var arrays := instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			check("UV vertex cardinality " + String(instance.name), vertices.size() == uv.size())
			if vertices.size() != uv.size(): continue
			var valid := true
			var aligned := true
			var frame: Node3D = null
			if String(instance.name).begins_with("wing_") or String(instance.name).begins_with("fixed_te_"):
				frame = instance.get_parent() as Node3D
			elif String(instance.name).begins_with("aileron_"):
				frame = instance.get_parent().get_parent() as Node3D
			for i in uv.size():
				valid = valid and is_finite(uv[i].x) and is_finite(uv[i].y) and uv[i].x >= 0 and uv[i].x <= 1 and uv[i].y >= 0 and uv[i].y <= 1
				if frame != null:
					var point := frame.to_local(instance.to_global(vertices[i]))
					aligned = aligned and uv[i].distance_to(Finish.uv(point, "wing")) < 0.00001
			check("finite atlas UV " + String(instance.name), valid)
			if frame != null: check("neutral fixed/moving atlas registration " + String(instance.name), aligned)
			total_uvs += uv.size()
	check("skin vertices audited", total_uvs > 100)
	var a := MeshInstance3D.new()
	var b := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.material = skin
	a.mesh = mesh
	b.mesh = mesh
	a.material_override = skin.duplicate() as StandardMaterial3D
	a.material_override.roughness = 0.99
	check("inspection override stays local", b.get_active_material(0) == skin and a.get_active_material(0) != skin and skin.roughness != 0.99)
	check("same color different finishes stay distinct", Finish.material(Color.GRAY, "rubber") != Finish.material(Color.GRAY, "steel"))
	a.free()
	b.free()
	return {"checks": checks, "failures": failures, "ok": failures.is_empty(), "textured_vertices": total_uvs, "winding_triangles": winding_triangles}

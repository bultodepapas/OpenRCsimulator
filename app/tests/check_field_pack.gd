# L5 export smoke. Run from an EMPTY project root so a missing pack resource cannot fall back to the source tree.
extends SceneTree


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2 or not ProjectSettings.load_resource_pack(args[0], true):
		printerr("Could not mount field pack: ", args)
		quit(1)
		return
	var path: String = "res://data/fields/default.json"
	if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != args[1]:
		printerr("Pack has missing or different default field: ", args[0])
		quit(1)
		return
	var loader: Script = load("res://data/field_loader.gd")
	if loader == null:
		printerr("Pack has no field loader")
		quit(1)
		return
	var result: Dictionary = loader.load_from()
	if not result.ok or result.field.id != "default":
		printerr("Pack field rejected: ", result.errors)
		quit(1)
		return
	print("Pack field validated, SHA-256 ", args[1])
	var trees: Script = load("res://render/tree_assets.gd")
	if trees == null or not FileAccess.file_exists("res://assets/landscape/trees/LICENSE.txt"):
		printerr("Pack has no tree assets adapter/license")
		quit(1)
		return
	var catalog: Dictionary = trees.catalog()
	if not catalog.ok:
		printerr("Pack tree catalog rejected: ", catalog.errors)
		quit(1)
		return
	for entry: Dictionary in catalog.catalog.species:
		var mesh: ArrayMesh = trees.card_mesh(entry.id)
		if mesh == null:
			printerr("Missing imported tree asset in pack: ", entry.id)
			quit(1)
			return
		var material: StandardMaterial3D = mesh.surface_get_material(0) as StandardMaterial3D
		var picture: Image = material.albedo_texture.get_image() if material != null else null
		if picture == null or picture.get_size() != Vector2i(1024, 1024) or not picture.has_mipmaps():
			printerr("Pack tree atlas lost its size or mipmaps: ", entry.id)
			quit(1)
			return
	var builder: Script = load("res://render/field.gd")
	var field: Node3D = builder.build(result.field)
	var horizon: Script = load("res://render/horizon.gd")
	var rough: MeshInstance3D = field.get_node_or_null("rough") as MeshInstance3D
	if horizon == null or horizon.profile().is_empty() or rough == null or not rough.mesh is ArrayMesh \
		or rough.mesh.get_aabb().size.y <= 30.0:
		printerr("Pack missing or invalid L7 hill profile/mesh")
		field.free()
		quit(1)
		return
	print("Pack L7 hill profile checksum and rendered relief validated")
	var grove: Node3D = field.get_node_or_null("treeline")
	if grove == null or grove.get_child_count() != 8:
		printerr("Pack missing L7 treeline/shader or sector groups")
		field.free()
		quit(1)
		return
	var count: int = 0
	for node: MultiMeshInstance3D in grove.get_children():
		count += node.multimesh.instance_count
		var shader_material: ShaderMaterial = node.multimesh.mesh.surface_get_material(0) as ShaderMaterial
		if shader_material == null or shader_material.shader == null:
			printerr("Pack treeline shader missing")
			field.free()
			quit(1)
			return
	var grass: Node3D = field.get_node_or_null("NearGrass") as Node3D
	if grass == null or grass.get_child_count() != 4:
		printerr("Pack missing L11a placement, grass shader or chunks")
		field.free()
		quit(1)
		return
	var clumps: int = 0
	for chunk: MultiMeshInstance3D in grass.get_children():
		clumps += chunk.multimesh.instance_count
		if chunk.multimesh.mesh.surface_get_array_len(0) != 21 or chunk.multimesh.mesh.surface_get_material(0) == null:
			printerr("Pack invalid L11a clump mesh/material")
			field.free()
			quit(1)
			return
	if clumps <= 0 or clumps > 6000:
		printerr("Pack invalid L11a clipped clump count: ", clumps)
		field.free()
		quit(1)
		return
	print("Pack L11a placement checksum and %d opaque clumps validated" % clumps)
	field.free()
	var expected_count: int = result.field.objects[0].positions.size()
	if count != expected_count:
		printerr("Pack tree count mismatch: ", count)
		quit(1)
		return
	print("Pack tree catalog, imported atlas, license and %d-tree field validated" % expected_count)
	quit(0)

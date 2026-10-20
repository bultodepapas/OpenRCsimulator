# L5 export smoke. Run from an EMPTY project root so a missing pack resource cannot fall back to the source tree.
extends SceneTree

const EXPECTED_GRASS_ASSETS: Array[String] = ["grass_common_short", "grass_common_tall", "grass_wispy_tall"]


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var lake_only := args.size() == 3 and args[2] == "--lake-only"
	if (args.size() != 2 and not lake_only) or not ProjectSettings.load_resource_pack(args[0], true):
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
	# L24: field JSON is loaded by path, so every registered landscape must survive export filtering.
	var landscapes: Script = load("res://landscapes/catalog.gd")
	if landscapes == null or not landscapes.has(landscapes.DEFAULT_ID):
		printerr("Pack has no landscape catalog/default")
		quit(1)
		return
	for id: String in landscapes.ids():
		var definition: Dictionary = landscapes.entry(id)
		var landscape_field: Dictionary = loader.load_from(str(definition.field_path))
		if not landscape_field.ok:
			printerr("Pack landscape field rejected: ", id, " ", landscape_field.errors)
			quit(1)
			return
		print("Pack landscape validated: ", id)
	# DT-11a: procedural fallback must not hide a missing/stale packaged geometry bake.
	var lake_loader: Script = load("res://data/lake_loader.gd")
	var ground_surfaces: Script = load("res://physics/ground_surfaces.gd")
	var lake_terrain: Script = load("res://render/lake/lake_terrain.gd")
	if lake_loader == null or ground_surfaces == null or lake_terrain == null \
			or not ResourceLoader.exists(lake_terrain.BAKED_PATH):
		printerr("Pack missing lake geometry loader/bake")
		quit(1)
		return
	var lake: Dictionary = lake_loader.load_from()
	var ground_table: Dictionary = ground_surfaces.load_table()
	var ground: Dictionary = ground_surfaces.build(ground_table.table, result.field) if ground_table.ok else {}
	var baked: Resource = load(lake_terrain.BAKED_PATH)
	if not lake.ok or not ground.get("ok", false) or not lake_terrain.baked_matches(
			baked, var_to_bytes([lake.lake, ground.rects]), var_to_bytes(lake.lake)) \
			or baked.get_meta("basin_key", null) != var_to_bytes([lake.lake, ground.rects]):
		printerr("Pack has incompatible lake geometry")
		quit(1)
		return
	print("Pack default lake geometry and compiled source stamp validated")
	if lake_only:
		quit(0)
		return
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
	var tree_atlas: Texture2D = load(String(catalog.catalog.atlas)) as Texture2D
	var foliage_mask: Texture2D = load(String(catalog.catalog.foliage_mask)) as Texture2D
	if tree_atlas == null or foliage_mask == null or tree_atlas.get_width() != 1024 \
			or tree_atlas.get_height() != 1024 or foliage_mask.get_width() != 1024 \
			or foliage_mask.get_height() != 1024 or not _image_alpha_equal(tree_atlas.get_image(), foliage_mask.get_image()):
		printerr("Pack tree material mask missing or not alpha-aligned with its atlas")
		quit(1)
		return
	print("Pack source-material mask alpha matches its runtime atlas")
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
	var expected_imported: bool = field.has_node("Scenery") and result.field.id == "default"
	var grass_error := _grass_error(grass, expected_imported)
	if not grass_error.is_empty():
		printerr("Pack invalid L11a grass: ", grass_error)
		field.free()
		quit(1)
		return
	print("Pack L11a %s grass and %d clumps validated" % [
		"imported" if expected_imported else "procedural", grass.get_meta("clumps")])
	var cue: Node3D = field.get_node_or_null("windsock") as Node3D
	if cue == null or cue.get_child_count() != 2 or not cue.get_node_or_null("Fabric") is MeshInstance3D:
		printerr("Pack missing L10a windsock data, mesh builder or material")
		field.free()
		quit(1)
		return
	print("Pack L10a calm windsock validated")
	var station: Node3D = field.get_node_or_null("pilot_station") as Node3D
	if station == null or station.get_child_count() != 1 or not station.get_node_or_null("Station") is MeshInstance3D:
		printerr("Pack missing L10b pilot station")
		field.free()
		quit(1)
		return
	print("Pack L10b pilot station validated")
	var barrier: Node3D = field.get_node_or_null("flightline_barrier") as Node3D
	var contact: MeshInstance3D = field.get_node_or_null("FlightCueShadows") as MeshInstance3D
	if barrier == null or not barrier.get_node_or_null("Barrier") is MeshInstance3D \
		or contact == null or contact.mesh == null or contact.mesh.get_surface_count() != 1:
		printerr("Pack missing L10c flightline barrier or L10d cue contact shadows")
		field.free()
		quit(1)
		return
	print("Pack L10c barrier and L10d contact shadows validated")
	field.free()
	var expected_count: int = result.field.objects[0].positions.size()
	if count != expected_count:
		printerr("Pack tree count mismatch: ", count)
		quit(1)
		return
	print("Pack tree catalog, imported atlas, license and %d-tree field validated" % expected_count)
	quit(0)


func _image_alpha_equal(left: Image, right: Image) -> bool:
	if left == null or right == null or left.get_size() != right.get_size() \
			or left.get_format() != Image.FORMAT_RGBA8 or right.get_format() != Image.FORMAT_RGBA8:
		return false
	var left_data: PackedByteArray = left.get_data()
	var right_data: PackedByteArray = right.get_data()
	if left_data.size() != right_data.size():
		return false
	for alpha_index in range(3, left_data.size(), 4):
		if left_data[alpha_index] != right_data[alpha_index]:
			return false
	return true


## Export coverage: require real source meshes/materials and nonempty instance data.
## Detailed layout/mask behavior belongs to test_imported_near_grass/test_near_grass.
func _grass_error(grass: Node3D, imported: bool) -> String:
	if grass == null or bool(grass.get_meta("imported", false)) != imported:
		return "missing root or wrong field/scenery grass branch"
	if grass.get_child_count() < 1 or grass.get_child_count() > (3 if imported else 4):
		return "invalid number of nonempty source batches/quadrants"
	if imported and grass.get_child_count() != EXPECTED_GRASS_ASSETS.size():
		return "missing downloaded grass source batch"
	var adapter: Script = load("res://scenery/imported_vegetation.gd") if imported else null
	var clumps := 0
	var triangles := 0
	var assets := {}
	for node: Node in grass.get_children():
		if not node is MultiMeshInstance3D:
			return "grass child is not a MultiMeshInstance3D"
		var batch := node as MultiMeshInstance3D
		var mm := batch.multimesh
		if mm == null or mm.instance_count <= 0 or mm.transform_format != MultiMesh.TRANSFORM_3D:
			return "missing grass instances or invalid transform format"
		var mesh := mm.mesh as ArrayMesh
		if mesh == null or mesh.get_surface_count() < 1:
			return "missing source geometry"
		var source: Mesh
		if imported:
			var asset_id := str(node.name).get_slice("_Part_", 0)
			if not EXPECTED_GRASS_ASSETS.has(asset_id):
				return "unknown imported grass source"
			var parts: Array = adapter.get_parts(asset_id)
			var part_index := int(str(node.name).get_slice("_Part_", 1))
			if part_index < 0 or part_index >= parts.size() or not mm.use_colors or not mm.use_custom_data:
				return "missing imported mesh part or instance attributes"
			source = parts[part_index].mesh
			if source == null or source.get_surface_count() != mesh.get_surface_count():
				return "source surface count mismatch"
			assets[asset_id] = true
		elif mesh.get_surface_count() != 1 or mesh.surface_get_array_len(0) != 21:
			return "invalid procedural clump geometry"
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES or mesh.surface_get_material(surface) == null:
				return "missing triangle surface/material"
			if imported:
				var material := mesh.surface_get_material(surface) as BaseMaterial3D
				if material == null or material.albedo_texture == null \
						or material.albedo_texture.get_width() <= 0 or material.albedo_texture.get_height() <= 0:
					return "missing imported grass texture"
				var original := source.surface_get_arrays(surface)
				if arrays[Mesh.ARRAY_VERTEX] != original[Mesh.ARRAY_VERTEX] or arrays[Mesh.ARRAY_INDEX] != original[Mesh.ARRAY_INDEX] \
						or mesh.surface_get_material(surface) != source.surface_get_material(surface):
					return "imported source geometry/material changed"
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			var count: int = indices.size() if indices is PackedInt32Array and not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()
			triangles += (count / 3) * mm.instance_count
		clumps += mm.instance_count
	if clumps <= 0 or clumps > 6000 or int(grass.get_meta("clumps", -1)) != clumps:
		return "clump metadata/count mismatch"
	if imported and (clumps > 150 or assets.size() != EXPECTED_GRASS_ASSETS.size() \
			or triangles <= 0 or triangles > 50000 or int(grass.get_meta("triangles", -1)) != triangles \
			or int(grass.get_meta("asset_batches", -1)) != assets.size()):
		return "imported triangle budget or batch metadata mismatch"
	return ""

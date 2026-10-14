extends SceneTree

const ImportedHedge := preload("res://scenery/imported_hedge.gd")
const ImportedVegetation := preload("res://scenery/imported_vegetation.gd")
const ATLAS_PATH := "res://assets/landscape/vegetation/impostors/bush_common_flowers_4view.png"
const MANIFEST_PATH := "res://assets/landscape/vegetation/impostors/bush_common_flowers_4view.json"

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_test_source_atlas()
	_test_stable_layouts()
	_test_batched_build()
	print("%d imported-hedge checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_source_atlas() -> void:
	var manifest_file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	_check("bush impostor provenance manifest exists", manifest_file != null)
	if manifest_file == null:
		return
	var manifest_value: Variant = JSON.parse_string(manifest_file.get_as_text())
	manifest_file.close()
	_check("atlas records the green downloaded Bush_Common_Flowers source", manifest_value is Dictionary
		and str(manifest_value.get("derived_from_asset_id", "")) == "bush_common_flowers"
		and str(manifest_value.get("source_geometry_sha256", "")) == "08768c680e3abeafd25858c9d3f369bcb7eed014661d3b6825a397f2a6a3deea"
		and int(manifest_value.get("source_triangles", 0)) == 1368
		and int(manifest_value.get("source_surfaces", 0)) == 2
		and int(manifest_value.get("source_materials", 0)) == 2)
	_check("atlas records CC0 source archive and license evidence", manifest_value is Dictionary
		and str(manifest_value.get("source_archive_sha256", "")) == "298f6732b872e4cf7b30e6e7abf9641c7f6dc6b326df37ac089533ed7e3d58c9"
		and str(manifest_value.get("license_evidence", "")) == "assets/landscape/vegetation/source/License_Standard.txt")
	var azimuths: Array = manifest_value.get("baked_azimuth_deg", []) if manifest_value is Dictionary else []
	var atlas_size: Array = manifest_value.get("atlas_size_px", []) if manifest_value is Dictionary else []
	_check("source tree bakes four azimuths into a compact 4 by 1 atlas", azimuths.size() == 4
		and int(azimuths[0]) == 0 and int(azimuths[1]) == 90 and int(azimuths[2]) == 180 and int(azimuths[3]) == 270
		and atlas_size.size() == 2 and int(atlas_size[0]) == 1024 and int(atlas_size[1]) == 256)
	var source_textures: Array = manifest_value.get("source_textures", []) if manifest_value is Dictionary else []
	_check("atlas provenance pins the license evidence and source texture hashes", manifest_value is Dictionary
		and str(manifest_value.get("license_evidence_sha256", "")) == "120710e542c3ebaf83856c4eb55b4a1e680593b39302eba7fdc5d942dfe78c58"
		and source_textures.size() == 2
		and str(source_textures[0].get("sha256", "")) == "5c531f2329c241c625aafd6cb769de29f33b480ef2a16491c2489f3c68e62a6a"
		and str(source_textures[1].get("sha256", "")) == "998612bdf0b76a22f5f54d65cd7a457815d2842d89653fa4348a4ebb42933ad3")
	var color_pipeline: Dictionary = manifest_value.get("color_pipeline", {}) if manifest_value is Dictionary else {}
	_check("atlas preserves unshaded source albedo and glTF alpha mask", color_pipeline is Dictionary
		and str(color_pipeline.get("source_color", "")).contains("Base Color")
		and str(color_pipeline.get("lighting", "")).contains("no light objects")
		and is_equal_approx(float(color_pipeline.get("alpha_cutoff", -1.0)), 0.2))
	var base_factors: Array = manifest_value.get("source_base_color_factors", []) if manifest_value is Dictionary else []
	var vertex_colors: Dictionary = manifest_value.get("source_vertex_colors", {}) if manifest_value is Dictionary else {}
	var color_attributes: Array = vertex_colors.get("attributes", []) if vertex_colors is Dictionary else []
	var material_routes: Array = color_pipeline.get("material_routes", []) if color_pipeline is Dictionary else []
	var complete_routes := material_routes.size() == 2
	for route_value: Variant in material_routes:
		if not route_value is Dictionary:
			complete_routes = false
			continue
		var base_network: Array = route_value.get("base_color_input_network", [])
		complete_routes = complete_routes and base_network.has("VERTEX_COLOR") and base_network.has("TEX_IMAGE")
	var white_color_attributes := not color_attributes.is_empty()
	for attribute_value: Variant in color_attributes:
		white_color_attributes = white_color_attributes and attribute_value is Dictionary \
			and str(attribute_value.get("gltf_semantic", "")) == "COLOR_0" \
			and _rgba_is_white(attribute_value.get("mean_rgba", []))
	var default_factors := base_factors.size() == 2
	for factor_value: Variant in base_factors:
		default_factors = default_factors and factor_value is Dictionary \
			and factor_value.get("explicit_in_source", true) == false \
			and _rgba_is_white(factor_value.get("gltf_value", []))
	_check("atlas records both source materials, COLOR_0 and baseColorFactor chains", complete_routes
		and white_color_attributes and default_factors)
	var green_parts := ImportedVegetation.get_parts("bush_common_flowers")
	_check("green shrub near variant retains its two original source materials", _has_source_shrub_materials(green_parts))
	var red_parts := ImportedVegetation.get_parts("bush_common")
	_check("red Bush_Common remains available as an accent source", not red_parts.is_empty()
		and ImportedVegetation.get_asset("bush_common").get("source_triangles", 0) == 900
		and ImportedVegetation.resolve_id("green_bush") == "bush_common_flowers"
		and ImportedVegetation.resolve_id("red_bush") == "bush_common")
	var bush_palette_is_green_first := true
	for seed: int in range(7):
		bush_palette_is_green_first = bush_palette_is_green_first \
			and ImportedVegetation.resolve_id("bush", seed) == "bush_common_flowers"
	_check("generic bush variety reserves red source for a sparse accent", bush_palette_is_green_first
		and ImportedVegetation.resolve_id("bush", 7) == "bush_common")
	var atlas_texture := load(ATLAS_PATH) as Texture2D
	var atlas := atlas_texture.get_image() if atlas_texture != null else null
	_check("source render atlas loads as a 1024 by 256 image", atlas != null and atlas.get_width() == 1024 and atlas.get_height() == 256)
	if atlas == null:
		return
	var transparent_samples := 0
	var foliage_samples := 0
	var green_foliage_samples := 0
	var warm_flower_samples := 0
	for frame_index: int in range(4):
		var frame_has_foliage := false
		var frame_has_transparency := false
		for y: int in range(0, atlas.get_height(), 8):
			for x: int in range(frame_index * 256, (frame_index + 1) * 256, 8):
				var pixel := atlas.get_pixel(x, y)
				var alpha := pixel.a
				if alpha > 0.2:
					foliage_samples += 1
					frame_has_foliage = true
					if pixel.g > pixel.r * 1.15 and pixel.g > pixel.b * 1.25:
						green_foliage_samples += 1
					if pixel.r > pixel.g * 1.15 and pixel.r > pixel.b * 1.15:
						warm_flower_samples += 1
				elif alpha <= 0.01:
					transparent_samples += 1
					frame_has_transparency = true
		_check("each source view retains both foliage and transparent cutout", frame_has_foliage and frame_has_transparency)
	_check("green source foliage dominates while authored flower accents remain", green_foliage_samples > 500 and warm_flower_samples >= 8)


func _test_stable_layouts() -> void:
	var points: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(54.0, 0.0), Vector2(108.0, 8.0)]
	var low := ImportedHedge.layout(points, 2.2, 1.3, 417, "low")
	var balanced := ImportedHedge.layout(points, 2.2, 1.3, 417, "balanced")
	var high := ImportedHedge.layout(points, 2.2, 1.3, 417, "high")
	_check("card layout is deterministic", _layout_signature(high) == _layout_signature(ImportedHedge.layout(points, 2.2, 1.3, 417, "high")))
	_check("card quality levels are nested low ⊆ balanced ⊆ high", _subset(low, balanced) and _subset(balanced, high))
	_check("quality tiers use one source atlas and stay within the card budget", high.size() <= 256 and _all_source_cards(high))
	_check("source-derived clumps retain a natural height range and uniform scale", _uniform_card_fits(high, 2.2))
	var low_trees := ImportedHedge.tree_layout(points, 417, "low")
	var balanced_trees := ImportedHedge.tree_layout(points, 417, "balanced")
	var high_trees := ImportedHedge.tree_layout(points, 417, "high")
	_check("sparse imported tree quality subsets are deterministic and nested",
		_layout_signature(high_trees) == _layout_signature(ImportedHedge.tree_layout(points, 417, "high"))
		and _subset(low_trees, balanced_trees) and _subset(balanced_trees, high_trees)
		and high_trees.size() <= 4)
	var packed_root := ImportedHedge.build_packed(PackedVector2Array(points), 2.2, 1.3, 417, "high", false)
	_check("packed scenery polyline wrapper matches the Array API",
		_layout_signature(packed_root.get_meta("cpu_placements", [])) == _layout_signature(high))
	packed_root.free()


func _test_batched_build() -> void:
	var points: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(52.0, 0.0), Vector2(108.0, 0.0)]
	var root := ImportedHedge.build(points, 2.2, 1.4, 9182, "high", true)
	_check("runtime hedge seam has a stable ImportedHedge root", root.name == "ImportedHedge")
	_check("root identifies the geometry as imported source-derived vegetation", bool(root.get_meta("imported", false))
		and bool(root.get_meta("source_only", false)))
	_check("bush cards use one batched source atlas and no per-plant nodes", _has_card_batch(root)
		and int(root.get_meta("bush_cards", 0)) > 0)
	_check("sparse canopy trees use imported CommonTree_3 geometry", int(root.get_meta("trees", 0)) > 0
		and _has_source_tree_batch(root))
	_check("CPU placements retain stable IDs, source assets, transforms and source triangle counts",
		_cpu_placements_valid(root.get_meta("cpu_placements", [])))
	_check("tree and atlas cards stay within the 20k source-triangle budget",
		int(root.get_meta("source_triangles", -1)) <= int(root.get_meta("triangle_budget", 0))
		and int(root.get_meta("source_triangles", -1)) == _placement_triangles(root.get_meta("cpu_placements", [])))
	_check("vegetation batches cast no shadows and create no colliders", _shadows_off(root) and _collision_count(root) == 0)
	root.free()
	var default_root := ImportedHedge.build(points, 2.2, 1.4, 9182)
	_check("production hedge defaults to the card row without optional trees", int(default_root.get_meta("trees", -1)) == 0
		and int(default_root.get_meta("bush_cards", 0)) > 0)
	default_root.free()
	var no_tree_root := ImportedHedge.build(points, 2.2, 1.4, 9182, "balanced", false)
	_check("tree meshes can be omitted while retaining the imported hedge card batch",
		int(no_tree_root.get_meta("trees", -1)) == 0 and int(no_tree_root.get_meta("bush_cards", 0)) > 0)
	no_tree_root.free()


func _layout_signature(placements: Array) -> String:
	var ids := PackedStringArray()
	for placement_value: Variant in placements:
		if placement_value is Dictionary:
			ids.append(str(placement_value.get("id", "")))
	return "\n".join(ids)


func _rgba_is_white(value: Variant) -> bool:
	if not value is Array or value.size() != 4:
		return false
	for component: Variant in value:
		if not is_equal_approx(float(component), 1.0):
			return false
	return true


func _subset(source: Array, target: Array) -> bool:
	var target_ids := {}
	for item: Variant in target:
		if item is Dictionary:
			target_ids[str(item.get("id", ""))] = true
	for item: Variant in source:
		if not item is Dictionary or not target_ids.has(str(item.get("id", ""))):
			return false
	return true


func _all_source_cards(placements: Array[Dictionary]) -> bool:
	for placement: Dictionary in placements:
		if str(placement.get("asset_id", "")) != "bush_common_flowers_4view_impostor" \
			or str(placement.get("source_asset_id", "")) != "bush_common_flowers" \
			or int(placement.get("source_triangles", -1)) != 2:
			return false
	return not placements.is_empty()


func _uniform_card_fits(placements: Array[Dictionary], nominal_height: float) -> bool:
	if placements.is_empty():
		return false
	for placement: Dictionary in placements:
		var height := float(placement.get("height_m", 0.0))
		if height < nominal_height * 0.82 or height > nominal_height * 1.12:
			return false
		var transform: Transform3D = placement.get("transform", Transform3D.IDENTITY)
		var scale := transform.basis.get_scale()
		if not is_equal_approx(scale.x, scale.y) or not is_equal_approx(scale.x, scale.z):
			return false
	return true


func _has_card_batch(root: Node) -> bool:
	for child: Node in root.get_children():
		if child is MultiMeshInstance3D and str(child.name) == "Bush_Common_Flowers_4View":
			var instance := child as MultiMeshInstance3D
			return instance.multimesh != null and instance.multimesh.instance_count > 0 \
				and instance.material_override is ShaderMaterial
	return false


func _has_source_shrub_materials(parts: Array[Dictionary]) -> bool:
	if parts.is_empty():
		return false
	var part: Dictionary = parts[0]
	var mesh := part.get("mesh") as Mesh
	var materials: Array = part.get("materials", [])
	if mesh == null or mesh.get_surface_count() != 2 or materials.size() != 2:
		return false
	var texture_paths := {}
	for material_value: Variant in materials:
		if not material_value is BaseMaterial3D:
			return false
		var material := material_value as BaseMaterial3D
		if material.albedo_texture != null:
			texture_paths[material.albedo_texture.resource_path.get_file()] = true
	return texture_paths.has("Leaves_NormalTree_C.png") and texture_paths.has("Flowers.png")


func _has_source_tree_batch(root: Node) -> bool:
	var source_parts := ImportedVegetation.get_parts("common_tree_3")
	if source_parts.is_empty():
		return false
	for child: Node in root.get_children():
		for part: Node in child.get_children():
			if not part is MultiMeshInstance3D:
				continue
			var mesh: Mesh = (part as MultiMeshInstance3D).multimesh.mesh
			if mesh == null or mesh.get_surface_count() != (source_parts[0].mesh as Mesh).get_surface_count():
				return false
			return mesh.surface_get_material(0) == (source_parts[0].mesh as Mesh).surface_get_material(0)
	return false


func _cpu_placements_valid(placements: Array) -> bool:
	if placements.is_empty():
		return false
	var seen_ids := {}
	for placement_value: Variant in placements:
		if not placement_value is Dictionary:
			return false
		var placement: Dictionary = placement_value
		var stable_id := str(placement.get("id", ""))
		var source_asset_id := str(placement.get("source_asset_id", ""))
		if stable_id.is_empty() or seen_ids.has(stable_id) or source_asset_id.is_empty():
			return false
		if not placement.get("transform", Transform3D.IDENTITY) is Transform3D:
			return false
		if int(placement.get("source_triangles", 0)) <= 0:
			return false
		seen_ids[stable_id] = true
	return true


func _placement_triangles(placements: Array) -> int:
	var total := 0
	for placement_value: Variant in placements:
		if placement_value is Dictionary:
			total += int(placement_value.get("source_triangles", 0))
	return total


func _shadows_off(root: Node) -> bool:
	for child: Node in root.get_children():
		if child is MultiMeshInstance3D and child.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			return false
		if not _shadows_off(child):
			return false
	return true


func _collision_count(root: Node) -> int:
	var total := 1 if root is CollisionObject3D else 0
	for child: Node in root.get_children():
		total += _collision_count(child)
	return total


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])

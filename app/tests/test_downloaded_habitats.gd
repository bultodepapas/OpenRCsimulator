## LU-23: all runtime habitat plants resolve to downloaded source assets and stay within the interim budget.
extends SceneTree

const Habitats := preload("res://scenery/botanical_habitats.gd")
const PlantLibrary := preload("res://scenery/imported_vegetation.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const SceneryLoader := preload("res://scenery/scenery_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const LakeSurface := preload("res://physics/lake_surface.gd")
const GroundSurfaces := preload("res://physics/ground_surfaces.gd")
const GroundTerrain := preload("res://physics/ground_terrain.gd")
const Grass := preload("res://render/near_grass.gd")

const REALISTIC_FERN_ID := "polyhaven_fern_02_a"
const REALISTIC_FLOWER_ID := "polyhaven_flower_empodium_a"
const ALLOWED_ASSETS := {
	"grass_common_short": true,
	"grass_common_tall": true,
	"grass_wispy_tall": true,
	"polyhaven_fern_02_a": true,
	"clover_1": true,
	"polyhaven_flower_empodium_a": true,
	"flower_4_group": true,
	"corn_4": true,
	"wheat_4": true,
	"reed_aredon": true,
	"bush_common_flowers": true,
	"grass_lolipop_small": true,
	"grass_lolipop_tall": true,
	"forest_leafy_shrub": true,
}
const FLOWER_ASSETS := ["clover_1", "polyhaven_flower_empodium_a", "flower_4_group"]
const GRASS_ASSETS := ["grass_common_short", "grass_common_tall", "grass_wispy_tall", "polyhaven_fern_02_a"]

var _failures := 0
var _checks := 0


func _initialize() -> void:
	var field_result := FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	_check("bundled field loads", bool(field_result.get("ok", false)))
	var scenery_result := SceneryLoader.load_from(SceneryLoader.DEFAULT_PATH, field_result.get("field", {}))
	_check("bundled scenery loads", bool(scenery_result.get("ok", false)))
	var lake_result := LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	_check("bundled lake loads", bool(lake_result.get("ok", false)))
	if _failures > 0:
		quit(1)
		return
	var field: Dictionary = field_result.field
	var scenery: Dictionary = scenery_result.scenery
	var lake: Dictionary = lake_result.lake
	_test_default_guard(field, scenery, lake)
	_test_shore_retry(field, scenery, lake)
	var high := Habitats.layout(field, scenery, "high", lake)
	_test_layout(field, scenery, lake, high)
	_test_quality_subsets(field, scenery, lake, high)
	_test_build(field, scenery, lake, high)
	print("downloaded habitat checks: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_default_guard(field: Dictionary, scenery: Dictionary, lake: Dictionary) -> void:
	var repeat := Habitats.layout(field, scenery, "high", lake)
	_check("layout is deterministic", var_to_bytes(repeat) == var_to_bytes(Habitats.layout(field, scenery, "high", lake)))
	var without_lake := Habitats.layout(field, scenery, "high")
	var has_shore_without_context := false
	for plant: Dictionary in without_lake:
		has_shore_without_context = has_shore_without_context or plant.get("zone", "") == "shore"
	_check("omitted lake context places no shoreline reeds", not has_shore_without_context)
	var other_field := field.duplicate(true)
	other_field["id"] = "custom"
	_check("custom field gets no bundled recipes", Habitats.layout(other_field, scenery, "high", lake).is_empty())
	_check("custom scenery gets no bundled recipes", Habitats.layout(field, {"groups": []}, "high", lake).is_empty())
	_check("invalid lake input fails closed", Habitats.layout(field, scenery, "high", {"invalid": true}).is_empty())


func _test_layout(field: Dictionary, scenery: Dictionary, lake: Dictionary, plants: Array[Dictionary]) -> void:
	var exclusions := Habitats.exclusions_for(scenery, lake)
	var shared_exclusions := Habitats.exclusions_for(scenery)
	var surface_table := _surface_rects(field)
	var assets_seen: Dictionary = {}
	var zone_counts: Dictionary = {}
	var triangle_total := 0
	var flower_count := 0
	var crop_count := 0
	var farm_accent_count := 0
	var accent_triangles := 0
	var corn_count := 0
	var wheat_count := 0
	var reed_count := 0
	var shore_count := 0
	var shore_bank_plant_count := 0
	var shore_shrub_count := 0
	var reed_clusters: Dictionary = {}
	var grasses_seen: Dictionary = {}
	var flowers_seen: Dictionary = {}
	var all_roots_match_physical_ground := true
	var clear_of_collision_proxies := true
	var meadow_clear_of_bank := true
	var shore_roots_match_lake_ground := true
	var heights_valid := true
	for plant: Dictionary in plants:
		var asset_id := str(plant.get("asset_id", ""))
		var zone := str(plant.get("zone", ""))
		var source := PlantLibrary.get_asset(asset_id)
		var source_triangles := int(source.get("source_triangles", 0))
		assets_seen[asset_id] = true
		zone_counts[zone] = int(zone_counts.get(zone, 0)) + 1
		triangle_total += source_triangles
		if int(plant.seed) >= Habitats.DOWNLOADED_GRASS_SEED_START:
			accent_triangles += source_triangles
			if zone == "farm": farm_accent_count += 1
		_check("placement uses a catalogued download", ALLOWED_ASSETS.has(asset_id) and source_triangles > 0)
		var ground_sample := GroundTerrain.sample_validated(float(plant.north), float(plant.east), surface_table, lake)
		all_roots_match_physical_ground = all_roots_match_physical_ground and ground_sample.size() == 3 \
			and absf(float(plant.ground_up_m) - ground_sample[0]) < 1e-10 \
			and absf(float(plant.ground_down_m) + ground_sample[0]) < 1e-10
		if zone == "shore":
			shore_count += 1
			var bank_sample := LakeSurface.sample_terrain_validated(lake, float(plant.north), float(plant.east))
			shore_roots_match_lake_ground = shore_roots_match_lake_ground \
				and str(bank_sample.get("region", "")) == "bank" \
				and float(bank_sample.get("signed_shore_distance_m", 0.0)) <= -0.75 \
				and absf(float(plant.get("lake_ground_down_m", NAN)) - float(bank_sample.get("ground_down_m", NAN))) < 1e-9
			clear_of_collision_proxies = clear_of_collision_proxies \
				and Grass.accepts(float(plant.north), float(plant.east), field, shared_exclusions)
			if asset_id == "reed_aredon":
				reed_count += 1
				var cluster_id := str(plant.get("cluster_id", ""))
				reed_clusters[cluster_id] = int(reed_clusters.get(cluster_id, 0)) + 1
				heights_valid = heights_valid and float(plant.height_m) >= 0.9 and float(plant.height_m) <= 1.5
			elif asset_id == "bush_common_flowers":
				shore_shrub_count += 1
				heights_valid = heights_valid and float(plant.height_m) >= 0.72 and float(plant.height_m) <= 1.0
			elif asset_id in FLOWER_ASSETS or asset_id in GRASS_ASSETS:
				shore_bank_plant_count += 1
				if asset_id == REALISTIC_FLOWER_ID:
					heights_valid = heights_valid and float(plant.height_m) >= 0.14 and float(plant.height_m) <= 0.24
				elif asset_id in FLOWER_ASSETS:
					heights_valid = heights_valid and float(plant.height_m) >= 0.3 and float(plant.height_m) <= 0.65
				elif asset_id == REALISTIC_FERN_ID:
					heights_valid = heights_valid and float(plant.height_m) >= 0.22 and float(plant.height_m) <= 0.42
				else:
					heights_valid = heights_valid and float(plant.height_m) >= 0.2 and float(plant.height_m) <= 0.5
		else:
			meadow_clear_of_bank = meadow_clear_of_bank \
				and not bool(LakeSurface.sample_terrain_validated(lake, float(plant.north), float(plant.east)).get("covered", false))
			clear_of_collision_proxies = clear_of_collision_proxies \
				and Grass.accepts(float(plant.north), float(plant.east), field, exclusions)
			if asset_id in FLOWER_ASSETS:
				flower_count += 1
				flowers_seen[asset_id] = true
				if asset_id == REALISTIC_FLOWER_ID:
					heights_valid = heights_valid and float(plant.height_m) >= 0.14 and float(plant.height_m) <= 0.24
				else:
					heights_valid = heights_valid and float(plant.height_m) >= 0.3 and float(plant.height_m) <= 0.65
			elif asset_id in GRASS_ASSETS:
				grasses_seen[asset_id] = true
				if asset_id == REALISTIC_FERN_ID:
					heights_valid = heights_valid and float(plant.height_m) >= 0.22 and float(plant.height_m) <= 0.42
				else:
					heights_valid = heights_valid and float(plant.height_m) >= 0.2 and float(plant.height_m) <= 0.5
			elif asset_id == "corn_4" or asset_id == "wheat_4":
				crop_count += 1
				corn_count += 1 if asset_id == "corn_4" else 0
				wheat_count += 1 if asset_id == "wheat_4" else 0
	_check("field, club and meadow use only downloaded grass, fern, clover and flower groups", grasses_seen.size() == 4 and flowers_seen.size() == 3)
	_check("accepted recipe uses both realistic fern and open-flower sources",
		assets_seen.has("polyhaven_fern_02_a") and assets_seen.has("polyhaven_flower_empodium_a"))
	_check("downloaded flower clusters replace the removed synthetic meadow", flower_count >= 45 and flower_count <= 60)
	_check("two downloaded crop plots coexist with 24 farm-margin accents",
		crop_count >= 70 and farm_accent_count == 24 and zone_counts.get("farm", 0) == crop_count + farm_accent_count)
	_check("budget trim preserves separate 22-plant corn and 62-plant wheat plots",
		corn_count == 22 and wheat_count == 62 and crop_count == 84,
		"corn=%d wheat=%d" % [corn_count, wheat_count])
	var clusters_valid := reed_clusters.size() == 4
	for cluster_count: Variant in reed_clusters.values():
		clusters_valid = clusters_valid and int(cluster_count) == 7
	_check("shore reeds form four irregular seven-clump clusters", reed_count == 28 and clusters_valid,
		"reeds=%d clusters=%s" % [reed_count, reed_clusters])
	_check("dry bank adds 24 downloaded grass, fern and flower clumps", shore_bank_plant_count == 24)
	_check("dry bank adds four downloaded green shrubs", shore_shrub_count == 4)
	_check("all shoreline plants remain on dry bank ground outside water", shore_count == 56)
	_check("every recipe includes the physical field and lake ground sample", all_roots_match_physical_ground)
	_check("shore reeds use the sampled dry lake bank", shore_roots_match_lake_ground)
	_check("meadow and crops stay outside the lake bank footprint", meadow_clear_of_bank)
	_check("all planting clears shared paths, structures and surface proxies", clear_of_collision_proxies)
	_check("uniform target heights stay in natural ranges", heights_valid)
	_check("imported plants stay below the 90k provisional triangle budget", triangle_total <= 90000,
		"%d triangles" % triangle_total)
	_check("original habitat recipe retains 87,669 triangles",
		triangle_total - accent_triangles == 87669, "%d original triangles" % (triangle_total - accent_triangles))
	_check("downloaded grass and shrub accents add exactly 1,986 triangles",
		accent_triangles == 1986 and triangle_total == 89655, "%d accent triangles; %d total" % [accent_triangles, triangle_total])
	_check("zone metadata can distinguish club, edge, meadow, farm and shore", ["club", "edge", "meadow", "farm", "shore"].all(func(zone: String) -> bool: return zone_counts.has(zone)))
	_check("recipe has all expected zones", zone_counts.get("club", 0) > 0 and zone_counts.get("edge", 0) > 0 \
		and zone_counts.get("meadow", 0) > 0 and zone_counts.get("farm", 0) > 0 and zone_counts.get("shore", 0) > 0)
	print("downloaded habitat layout: %d placements, %d source triangles, zone counts %s" % [plants.size(), triangle_total, zone_counts])


func _test_quality_subsets(field: Dictionary, scenery: Dictionary, lake: Dictionary, high: Array[Dictionary]) -> void:
	var by_seed: Dictionary = {}
	for plant: Dictionary in high:
		by_seed[int(plant.seed)] = plant
	for quality: String in ["balanced", "low"]:
		var subset := Habitats.layout(field, scenery, quality, lake)
		var is_subset := not subset.is_empty() and subset.size() < high.size()
		for plant: Dictionary in subset:
			var plant_seed := int(plant.seed)
			is_subset = is_subset and by_seed.has(plant_seed) and var_to_bytes(by_seed.get(plant_seed, {})) == var_to_bytes(plant)
		_check("%s habitat quality is a stable source-plant subset" % quality, is_subset)


func _test_build(field: Dictionary, scenery: Dictionary, lake: Dictionary, high: Array[Dictionary]) -> void:
	var node := Habitats.build(field, scenery, "temperate", "high", lake)
	var built_plants: Array = node.get_meta("plants", [])
	var expected_triangles := 0
	for plant: Dictionary in high:
		expected_triangles += int(PlantLibrary.get_asset(str(plant.asset_id)).get("source_triangles", 0))
	_check("runtime uses every accepted source placement", built_plants.size() == high.size())
	_check("runtime reports source triangles only", int(node.get_meta("triangles", -1)) == expected_triangles \
		and int(node.get_meta("imported_triangles", -1)) == expected_triangles)
	_check("runtime records its hard budget", int(node.get_meta("triangle_budget", 0)) == 90000 \
		and expected_triangles <= int(node.get_meta("triangle_budget", 0)))
	_check("runtime draw batches meet target", node.get_child_count() <= 24 \
		and int(node.get_meta("batches", 99)) == node.get_child_count())
	_check("runtime contains only downloaded MultiMesh batches", not node.get_children().is_empty() \
		and node.get_children().all(func(child: Node) -> bool: return child is MultiMeshInstance3D))
	var group_zones: Dictionary = node.get_meta("group_zones", {})
	var zones: Dictionary = node.get_meta("zones", {})
	_check("runtime retains source-group to placement-zone counts", group_zones.size() > 0 \
		and group_zones.has("reed_aredon") and zones.has("shore"))
	var source_meshes_match := true
	var tint_channels_valid := true
	var tint_varies := false
	for plant: Dictionary in built_plants:
		var tint: Color = plant.get("instance_tint", Color.WHITE)
		tint_channels_valid = tint_channels_valid and tint.r >= 0.86 and tint.r <= 1.0 \
			and tint.g >= 0.86 and tint.g <= 1.0 and tint.b >= 0.86 and tint.b <= 1.0 \
			and is_equal_approx(tint.a, 1.0)
		tint_varies = tint_varies or tint.r < 0.999 or tint.g < 0.999 or tint.b < 0.999
	var color_data_enabled := true
	var drawn_triangles := 0
	for child: Node in node.get_children():
		var batch := child as MultiMeshInstance3D
		color_data_enabled = color_data_enabled and batch.multimesh.use_colors
		var asset_id := str(child.name).get_slice("_Part_", 0)
		var part_index := int(str(child.name).get_slice("_Part_", 1))
		var parts := PlantLibrary.get_parts(asset_id)
		if part_index >= parts.size():
			source_meshes_match = false
			continue
		var source_part: Dictionary = parts[part_index]
		var mesh: Mesh = batch.multimesh.mesh
		source_meshes_match = source_meshes_match and mesh != null \
			and mesh.get_surface_count() == int(source_part.get("source_surfaces", -1))
		for surface_index in range(mesh.get_surface_count()):
			var source_materials: Array = source_part.get("materials", [])
			source_meshes_match = source_meshes_match and surface_index < source_materials.size() \
				and mesh.surface_get_material(surface_index) == source_materials[surface_index]
		drawn_triangles += int(source_part.get("source_triangles", 0)) * batch.multimesh.instance_count
	_check("each batch retains the downloaded mesh surfaces and source materials", source_meshes_match)
	var bounds: Array = node.get_meta("_imported_vegetation_state", {}).get("bounds", [])
	var retained_tints_valid := bounds.size() == built_plants.size()
	for record: Dictionary in bounds:
		var tint: Color = record.get("tint", Color.WHITE)
		retained_tints_valid = retained_tints_valid and tint.r >= 0.86 and tint.r <= 1.0 \
			and tint.g >= 0.86 and tint.g <= 1.0 and tint.b >= 0.86 and tint.b <= 1.0 \
			and is_equal_approx(tint.a, 1.0)
	_check("plant instance tints are retained within subtle bounds", tint_channels_valid and tint_varies and retained_tints_valid)
	_check("MultiMesh batches enable instance color data", color_data_enabled)
	_check("drawn batch geometry matches metadata", drawn_triangles == expected_triangles)
	node.free()


func _surface_rects(field: Dictionary) -> PackedFloat64Array:
	var table := GroundSurfaces.load_table()
	if not bool(table.get("ok", false)):
		return PackedFloat64Array()
	var built := GroundSurfaces.build(table.table, field)
	return built.rects if bool(built.get("ok", false)) else PackedFloat64Array()


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	printerr("FAIL: %s %s" % [label, detail])


## DT-11a: rejecting a crowded candidate must preserve the deterministic seed tape.
func _test_shore_retry(field: Dictionary, scenery: Dictionary, lake: Dictionary) -> void:
	var exclusions := Habitats.exclusions_for(scenery) # Shore plants must not exclude the bank itself.
	var surfaces := _surface_rects(field)
	var anchor: Dictionary = Habitats._shore_cluster_anchors(lake)[0]
	var selected: Array[Dictionary] = []
	var sequence := {next = 1}
	var first := Habitats._append_shore_plant(selected, field, exclusions, surfaces, lake,
		sequence, anchor, "reed_aredon", 0, 0, "reed", 0.85)
	_check("shore retry fixture accepts a seed-1 search", not first.is_empty())
	if first.is_empty(): return
	_check("accepted search consumes through its seed without appending selected",
		sequence.next == int(first.seed) + 1 and selected.is_empty())
	selected.append(first.duplicate(true))
	var selected_bytes := var_to_bytes(selected)
	sequence.next = int(first.seed)
	var next := Habitats._append_shore_plant(selected, field, exclusions, surfaces, lake,
		sequence, anchor, "reed_aredon", 0, 0, "reed", 0.85)
	_check("retry rejects the occupied seed and finds another shore point", not next.is_empty())
	if next.is_empty(): return
	_check("retry keeps the exact spacing and seed progression",
		int(next.seed) > int(first.seed) and sequence.next == int(next.seed) + 1
		and Vector2(next.north, next.east).distance_to(Vector2(first.north, first.east)) >= 0.85)
	var bank := LakeSurface.sample_terrain_validated(lake, next.north, next.east)
	_check("retry still satisfies dry-bank and exclusion constraints",
		bank.covered and bank.region == "bank" and bank.signed_shore_distance_m <= -0.75
		and bank.signed_shore_distance_m >= -4.5 and bank.ground_down_m > 0.0
		and bank.signed_bank_distance_m > 0.0 and Grass.accepts(next.north, next.east, field, exclusions))
	sequence.next = 900001
	var exhausted := Habitats._append_shore_plant(selected, field, exclusions, surfaces, lake,
		sequence, anchor, "reed_aredon", 0, 0, "reed", 1000000000.0)
	_check("crowded search consumes exactly 64 candidates and preserves selected",
		exhausted.is_empty() and sequence.next == 900065 and var_to_bytes(selected) == selected_bytes)

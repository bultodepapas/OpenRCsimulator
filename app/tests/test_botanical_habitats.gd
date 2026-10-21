## LU-23: the default scene's understory uses downloaded geometry and retained damage IDs.
extends SceneTree

const FieldLoader := preload("res://data/field_loader.gd")
const SceneryLoader := preload("res://scenery/scenery_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const Scenery := preload("res://scenery/scenery.gd")
const ImportedVegetation := preload("res://scenery/imported_vegetation.gd")
const Clock := preload("res://render/shader_clock.gd")
const Habitats := preload("res://scenery/botanical_habitats.gd")
const Grass := preload("res://render/near_grass.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	Clock.register()
	var field_result: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	_check("default field loads", bool(field_result.get("ok", false)))
	if not bool(field_result.get("ok", false)):
		quit(1)
		return
	var field: Dictionary = field_result.field
	var scenery_result: Dictionary = SceneryLoader.load_from(SceneryLoader.DEFAULT_PATH, field)
	_check("downloaded scenery layout loads", bool(scenery_result.get("ok", false)))
	if not bool(scenery_result.get("ok", false)):
		quit(1)
		return
	var lake_result: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	_check("downloaded lake definition loads", bool(lake_result.get("ok", false)))
	if not bool(lake_result.get("ok", false)):
		quit(1)
		return
	var source_scenery: Dictionary = scenery_result.scenery
	_check("generated default has no retired procedural cushion group",
		not source_scenery.groups.any(func(group: Dictionary) -> bool: return str(group.get("id", "")) == "wildflowers"))
	var built := Scenery.build(field, source_scenery, {audio = false, birds = false, theme = "", quality = "high"}, {}, lake_result.lake)
	var expanded := Habitats.layout(field, source_scenery, "high", lake_result.lake)
	var repeated := Habitats.layout(field, source_scenery, "high", lake_result.lake)
	var identical := expanded.size() == repeated.size()
	for index in mini(expanded.size(), repeated.size()):
		for key in ["asset_id", "seed", "zone", "north", "east", "height_m", "yaw_rad", "ground_up_m"]:
			identical = identical and expanded[index][key] == repeated[index][key]
	_check("downloaded accents rebuild deterministically", identical)
	var exclusions := Habitats.exclusions_for(source_scenery, lake_result.lake)
	var added_species := {}
	var added_zones := {}
	var added_triangles := 0
	var added_clear := true
	for plant: Dictionary in expanded:
		if int(plant.seed) < Habitats.DOWNLOADED_GRASS_SEED_START:
			continue
		added_species[plant.asset_id] = true
		added_zones[plant.zone] = true
		added_triangles += int(ImportedVegetation.get_asset(plant.asset_id).get("source_triangles", 0))
		added_clear = added_clear and Grass.accepts(float(plant.north), float(plant.east), field, exclusions)
	_check("both grass forms and the forest shrub are placed", added_species.size() == 3)
	_check("downloaded accents reach club, meadow and farm", added_zones.has("club")
		and added_zones.has("meadow") and added_zones.has("farm"))
	_check("new small plants remain outside runway, paths and foundations", added_clear)
	_check("new accents use at most 1,986 source triangles", added_triangles > 0 and added_triangles <= 1986)
	_test_imported_habitats(built.get_node_or_null("BotanicalHabitats") as Node3D)
	_test_downloaded_damage(built.get_node_or_null("ImportedVegetationBatches") as Node3D)
	built.free()
	print("downloaded vegetation scene checks: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _test_imported_habitats(root: Node3D) -> void:
	var plants: Array = root.get_meta("plants", []) if root != null else []
	var triangle_total := int(root.get_meta("triangles", 0)) if root != null else 0
	var budget := int(root.get_meta("triangle_budget", 0)) if root != null else 0
	var batch_limit := int(root.get_meta("batch_limit", 0)) if root != null else 0
	var batches := int(root.get_meta("batches", 0)) if root != null else 0
	var fern_range: Vector2 = Habitats.HEIGHT_RANGES.get(Habitats.FERN_ASSET_ID, Vector2.ZERO)
	var flower_range: Vector2 = Habitats.HEIGHT_RANGES.get(Habitats.FLOWER_ASSET_ID, Vector2.ZERO)
	var reeds := 0
	var dry_bank_plants := 0
	var green_shrubs := 0
	var tints_valid := true
	var candidate_counts := {
		Habitats.FERN_ASSET_ID: 0,
		Habitats.FLOWER_ASSET_ID: 0,
	}
	var candidate_geometry_valid := true
	var candidate_heights_valid := true
	var candidate_triangles := 0
	for plant_value: Variant in plants:
		if not plant_value is Dictionary:
			continue
		var plant: Dictionary = plant_value
		var asset_id := str(plant.get("asset_id", ""))
		if candidate_counts.has(asset_id):
			candidate_counts[asset_id] = int(candidate_counts[asset_id]) + 1
			var catalog_asset := ImportedVegetation.get_asset(asset_id)
			var source_triangles := int(catalog_asset.get("source_triangles", 0))
			var expected_range: Vector2 = Habitats.HEIGHT_RANGES.get(asset_id, Vector2.ZERO)
			candidate_triangles += source_triangles
			candidate_geometry_valid = candidate_geometry_valid and source_triangles > 0 \
				and source_triangles <= Habitats.MAX_ADDED_TRIANGLES \
				and int(plant.get("source_triangles", 0)) == source_triangles
			candidate_heights_valid = candidate_heights_valid and expected_range.x > 0.0 \
				and expected_range.y >= expected_range.x \
				and float(plant.get("height_m", 0.0)) >= expected_range.x \
				and float(plant.get("height_m", 0.0)) <= expected_range.y
		if str(plant.get("zone", "")) == "shore":
			if asset_id == "reed_aredon":
				reeds += 1
			elif asset_id == "bush_common_flowers":
				green_shrubs += 1
			else:
				dry_bank_plants += 1
		var tint: Color = plant.get("instance_tint", Color.WHITE)
		tints_valid = tints_valid and tint.r >= 0.86 and tint.r <= 1.0 \
			and tint.g >= 0.86 and tint.g <= 1.0 and tint.b >= 0.86 and tint.b <= 1.0 \
			and is_equal_approx(tint.a, 1.0)
	_check("production attaches downloaded habitat batches", root != null and not plants.is_empty()
		and root.get_children().all(func(child: Node) -> bool: return child is MultiMeshInstance3D))
	_check("source geometry stays within the provisional triangle budget",
		triangle_total > 0 and budget == 90000 and triangle_total <= budget)
	_check("shore habitats contain 28 reeds, 24 low source plants and four green shrubs",
		reeds == 28 and dry_bank_plants == 24 and green_shrubs == 4,
		"reeds=%d dry-bank=%d shrubs=%d" % [reeds, dry_bank_plants, green_shrubs])
	_check("source vegetation carries bounded subtle instance tints", tints_valid)
	_check("source meshes share no more than 24 runtime batches", batch_limit == 24 and batches <= batch_limit
		and batches == root.get_child_count())
	_check("accepted fern and Empodium source IDs are used in the built habitat",
		int(candidate_counts.get(Habitats.FERN_ASSET_ID, 0)) > 0
		and int(candidate_counts.get(Habitats.FLOWER_ASSET_ID, 0)) > 0)
	_check("accepted candidate source triangles fit the 90,000 triangle scene cap",
		candidate_geometry_valid and candidate_triangles > 0 and candidate_triangles <= Habitats.MAX_ADDED_TRIANGLES)
	_check("fern and Empodium use the requested 0.22-0.42 m and 0.14-0.24 m ranges",
		is_equal_approx(fern_range.x, 0.22) and is_equal_approx(fern_range.y, 0.42)
		and is_equal_approx(flower_range.x, 0.14) and is_equal_approx(flower_range.y, 0.24)
		and candidate_heights_valid)
	var only_downloads := true
	for plant_value: Variant in plants:
		if not plant_value is Dictionary:
			only_downloads = false
			continue
		var plant: Dictionary = plant_value
		var asset_id := str(plant.get("asset_id", ""))
		only_downloads = only_downloads and not ImportedVegetation.get_asset(asset_id).is_empty()
		only_downloads = only_downloads and int(plant.get("source_triangles", 0)) > 0
	_check("every habitat placement resolves to a downloaded catalog mesh", only_downloads)


func _test_downloaded_damage(root: Node3D) -> void:
	var state: Dictionary = root.get_meta("_imported_vegetation_state", {}) if root != null else {}
	var damage: Dictionary = state.get("damage", {})
	var damage_ids: Array = damage.keys()
	damage_ids.sort()
	_check("near vegetation retains production damage IDs", not damage_ids.is_empty())
	if root == null or damage_ids.is_empty():
		return
	var damage_id := str(damage_ids[0])
	var hidden := ImportedVegetation.set_damage_hidden(root, damage_id, true)
	var after_hide: Dictionary = root.get_meta("_imported_vegetation_state", {})
	var bounds_records: Array = after_hide.get("bounds", [])
	var records_hidden := hidden
	for item: Dictionary in damage.get(damage_id, []):
		var bounds_index := int(item.get("bounds_index", -1))
		records_hidden = records_hidden and bounds_index >= 0 and bounds_index < bounds_records.size()
		if bounds_index >= 0 and bounds_index < bounds_records.size():
			records_hidden = records_hidden and bool(bounds_records[bounds_index].get("hidden", false))
	_check("breaking one prop hides its downloaded mesh record", records_hidden, damage_id)
	_check("damage reset restores its downloaded mesh record", ImportedVegetation.set_damage_hidden(root, damage_id, false), damage_id)


func _check(label: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if condition:
		return
	failures += 1
	printerr("FAIL: %s %s" % [label, detail])

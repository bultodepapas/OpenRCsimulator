## LU-23 downloaded vegetation placement. This module only batches catalogued source meshes.
extends RefCounted

const Palette := preload("res://scenery/palette.gd")
const Frames := preload("res://render/frames.gd")
const Grass := preload("res://render/near_grass.gd")
const Mask := preload("res://render/landscape_upgrade/scenery_grass_mask.gd")
const PlantLibrary := preload("res://scenery/imported_vegetation.gd")
const GroundSurfaces := preload("res://physics/ground_surfaces.gd")
const GroundTerrain := preload("res://physics/ground_terrain.gd")
const LakeSurface := preload("res://physics/lake_surface.gd")

const SEED := 221013
const MAX_ADDED_TRIANGLES := 90000
const MAX_VISIBLE_BATCHES := 24
const FERN_ASSET_ID := "polyhaven_fern_02_a"
const FLOWER_ASSET_ID := "polyhaven_flower_empodium_a"
const SHORE_CLUSTER_VERTICES := [2, 7, 12, 17]
const SHORE_REEDS_PER_CLUSTER := 7
const SHORE_BANK_PLANTS_PER_CLUSTER := 6
const SHORE_SHRUBS_PER_CLUSTER := 1
const CORN_OMITTED_CELLS := [
	Vector2i(0, 0), Vector2i(0, 6), Vector2i(1, 0),
	Vector2i(2, 6), Vector2i(3, 0), Vector2i(3, 6),
]
const WHEAT_EXTENSION_SEED_START := 100000
const DOWNLOADED_GRASS_SEED_START := 200000
const DOWNLOADED_GRASS_PATCHES := [
	{zone = "club", north = -49.0, east = 16.0, radius_n = 1.4, radius_e = 2.2},
	{zone = "meadow", north = 57.0, east = 100.0, radius_n = 1.8, radius_e = 2.6},
	{zone = "meadow", north = 66.0, east = 154.0, radius_n = 2.1, radius_e = 1.5},
	{zone = "farm", north = 555.0, east = 319.0, radius_n = 1.5, radius_e = 2.4},
	{zone = "farm", north = 570.0, east = 352.0, radius_n = 2.0, radius_e = 1.6},
]
const DOWNLOADED_GRASS_MIX := [
	"grass_lolipop_small", "grass_lolipop_small", "grass_lolipop_tall", "grass_lolipop_small",
	"grass_lolipop_tall", "grass_lolipop_small", "grass_lolipop_small", "grass_lolipop_tall",
	"grass_lolipop_small", "grass_lolipop_tall", "grass_lolipop_small", "grass_lolipop_tall",
]
const DOWNLOADED_SHRUB_PATCHES := [
	{north = -50.5, east = 19.5}, {north = 60.0, east = 104.0},
	{north = 554.0, east = 315.0}, {north = 573.0, east = 354.0},
]
const SHORE_CANDIDATE_LIMIT := 64
const SHORE_REED_MIN_SPACING_M := 0.85
const SHORE_BANK_MIN_SPACING_M := 0.65
const SHORE_SHRUB_MIN_SPACING_M := 1.1
const SHORE_MIN_DISTANCE_M := 0.75
const SHORE_MAX_DISTANCE_M := 4.5

const SHORE_BANK_ASSETS := [
	"grass_common_short", "grass_common_tall", FERN_ASSET_ID, "grass_common_short", "clover_1", FLOWER_ASSET_ID,
]

const HEIGHT_RANGES := {
	"grass_lolipop_small": Vector2(0.22, 0.38),
	"grass_lolipop_tall": Vector2(0.40, 0.65),
	"forest_leafy_shrub": Vector2(0.65, 0.95),
	"clover_1": Vector2(0.30, 0.52),
	FLOWER_ASSET_ID: Vector2(0.14, 0.24),
	"flower_4_group": Vector2(0.48, 0.65),
	"grass_common_short": Vector2(0.20, 0.34),
	"grass_common_tall": Vector2(0.32, 0.50),
	"grass_wispy_tall": Vector2(0.34, 0.50),
	FERN_ASSET_ID: Vector2(0.22, 0.42),
	"corn_4": Vector2(1.15, 1.42),
	"wheat_4": Vector2(0.72, 0.92),
	"reed_aredon": Vector2(0.90, 1.50),
	"bush_common_flowers": Vector2(0.72, 1.0),
}

const FLOWER_PATCHES := [
	{zone = "club", north = -15.0, east = -3.0, radius_n = 0.35, radius_e = 2.0,
		assets = ["clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", FLOWER_ASSET_ID]},
	{zone = "club", north = -15.0, east = 3.0, radius_n = 0.35, radius_e = 2.0,
		assets = ["clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", FLOWER_ASSET_ID]},
	{zone = "meadow", north = 58.0, east = 98.0, radius_n = 8.0, radius_e = 13.0,
		assets = ["clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", FLOWER_ASSET_ID, "flower_4_group"]},
	{zone = "meadow", north = 64.0, east = 154.0, radius_n = 7.0, radius_e = 13.0,
		assets = ["clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "grass_lolipop_small", "grass_lolipop_small"]},
	{zone = "meadow", north = 47.0, east = 128.0, radius_n = 5.0, radius_e = 11.0,
		assets = ["clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1"]},
]

const GRASS_PATCHES := [
	{zone = "club", north = -52.0, east = -23.0, radius_n = 1.2, radius_e = 2.5,
		assets = ["grass_common_short", FERN_ASSET_ID]},
	{zone = "club", north = -54.0, east = 7.0, radius_n = 1.2, radius_e = 2.5,
		assets = ["grass_common_short", FERN_ASSET_ID]},
	{zone = "club", north = -29.5, east = -54.0, radius_n = 1.4, radius_e = 3.0,
		assets = ["grass_common_short", FERN_ASSET_ID]},
	{zone = "club", north = -30.5, east = 54.0, radius_n = 1.4, radius_e = 3.0,
		assets = [FERN_ASSET_ID]},
	{zone = "edge", north = 25.5, east = -42.0, radius_n = 2.0, radius_e = 7.0,
		assets = ["grass_common_short", "grass_common_tall", "grass_wispy_tall"]},
	{zone = "edge", north = 25.5, east = 42.0, radius_n = 2.0, radius_e = 7.0,
		assets = ["grass_common_short", "grass_common_tall", "grass_wispy_tall"]},
	{zone = "meadow", north = 58.0, east = 98.0, radius_n = 8.0, radius_e = 13.0,
		assets = ["grass_common_short", "grass_common_tall", FERN_ASSET_ID]},
	{zone = "meadow", north = 64.0, east = 154.0, radius_n = 7.0, radius_e = 13.0,
		assets = ["grass_common_short", "grass_common_tall", FERN_ASSET_ID]},
	{zone = "meadow", north = 47.0, east = 128.0, radius_n = 5.0, radius_e = 11.0,
		assets = ["grass_common_tall", FERN_ASSET_ID]},
]


## Deterministic source-asset recipe. Quality changes only a seeded subset, never positions or identities.
static func layout(field: Dictionary, scenery: Dictionary, quality: String, lake: Dictionary = {}) -> Array[Dictionary]:
	var plants: Array[Dictionary] = []
	if not _layout_applies(field, scenery):
		return plants
	if not lake.is_empty() and not LakeSurface.is_valid_definition(lake):
		return plants
	var surface_rects := _surface_rects(field)
	var shared_exclusions := exclusions_for(scenery)
	var land_exclusions := shared_exclusions.duplicate()
	if not lake.is_empty():
		var bank_record := _bank_footprint(lake)
		if not bank_record.is_empty():
			land_exclusions.append(bank_record)
	var land_exclusion_grid := Grass._build_exclusion_grid(land_exclusions)
	var shore_exclusion_grid: Dictionary = {}
	if not lake.is_empty():
		shore_exclusion_grid = Grass._build_exclusion_grid(shared_exclusions)
	var sequence := {"next": 1}
	var pilot_north := float(field.get("pilot", {}).get("north", 0.0))
	var pilot_east := float(field.get("pilot", {}).get("east", 0.0))

	for patch: Dictionary in FLOWER_PATCHES:
		_append_cluster(plants, field, land_exclusions, surface_rects, lake, sequence,
			str(patch.zone), pilot_north + float(patch.north), pilot_east + float(patch.east),
			float(patch.radius_n), float(patch.radius_e), patch.assets, quality, land_exclusion_grid)
	for patch: Dictionary in GRASS_PATCHES:
		_append_cluster(plants, field, land_exclusions, surface_rects, lake, sequence,
			str(patch.zone), pilot_north + float(patch.north), pilot_east + float(patch.east),
			float(patch.radius_n), float(patch.radius_e), patch.assets, quality, land_exclusion_grid)

	# Two restrained downloaded crop plots near the existing farm: 22 corn and 62 wheat.
	_append_grid(plants, field, land_exclusions, surface_rects, lake, sequence, "farm", "corn_4",
		pilot_north + 561.0, pilot_east + 324.0, 4, 7, 0.86, 0.82, quality, CORN_OMITTED_CELLS,
		land_exclusion_grid)
	_append_grid(plants, field, land_exclusions, surface_rects, lake, sequence, "farm", "wheat_4",
		pilot_north + 561.0, pilot_east + 346.0, 7, 8, 0.78, 0.43, quality, [], land_exclusion_grid)

	if not lake.is_empty():
		_append_shore_reeds(plants, field, shared_exclusions, surface_rects, lake, sequence, quality,
			shore_exclusion_grid)
		_append_shore_bank_plants(plants, field, shared_exclusions, surface_rects, lake, sequence, quality,
			shore_exclusion_grid)
	# Extend the distinct wheat plot by one short row; a reserved seed range leaves all existing IDs intact.
	var wheat_extension_sequence := {"next": WHEAT_EXTENSION_SEED_START}
	_append_grid(plants, field, land_exclusions, surface_rects, lake, wheat_extension_sequence, "farm", "wheat_4",
		pilot_north + 561.0 + 3.12, pilot_east + 346.0, 1, 6, 0.78, 0.43, quality, [], land_exclusion_grid)
	# Separate seed range preserves all existing habitat IDs. Unequal elliptical
	# clusters add source-textured tufts at the club, meadow and farm margins.
	var downloaded_grass_sequence := {"next": DOWNLOADED_GRASS_SEED_START}
	for patch: Dictionary in DOWNLOADED_GRASS_PATCHES:
		_append_cluster(plants, field, land_exclusions, surface_rects, lake, downloaded_grass_sequence,
			str(patch.zone), pilot_north + float(patch.north), pilot_east + float(patch.east),
			float(patch.radius_n), float(patch.radius_e), DOWNLOADED_GRASS_MIX, quality, land_exclusion_grid)
	for patch: Dictionary in DOWNLOADED_SHRUB_PATCHES:
		_append_cluster(plants, field, land_exclusions, surface_rects, lake, downloaded_grass_sequence,
			"understory", pilot_north + float(patch.north), pilot_east + float(patch.east),
			0.35, 0.5, ["forest_leafy_shrub"], quality, land_exclusion_grid)
	return plants


## Worn footpaths, foundations, gravel and (when present) the bounded lake bank stay clear of land planting.
static func exclusions_for(scenery: Dictionary, lake: Dictionary = {}) -> Array[Dictionary]:
	var result := _shared_exclusions(scenery)
	if not lake.is_empty() and LakeSurface.is_valid_definition(lake):
		var bank_record := _bank_footprint(lake)
		if not bank_record.is_empty():
			result.append(bank_record)
	return result


static func build(field: Dictionary, scenery: Dictionary, _theme: String, quality: String,
	lake: Dictionary = {}) -> Node3D:
	var plants := layout(field, scenery, quality, lake)
	var batches: Dictionary = {}
	var placed_plants: Array[Dictionary] = []
	var zone_stats: Dictionary = {}
	var group_zones: Dictionary = {}
	var group_stats: Dictionary = {}
	var triangles := 0
	for plant: Dictionary in plants:
		var asset_id := str(plant.get("asset_id", ""))
		var asset := PlantLibrary.get_asset(asset_id)
		var source_triangles := int(asset.get("source_triangles", 0))
		if source_triangles <= 0:
			continue
		var yaw := float(plant.get("yaw_rad", 0.0))
		var ground_up := float(plant.get("ground_up_m", 0.0))
		var origin := Frames.ned_to_render([float(plant.north), float(plant.east), -ground_up])
		var placement := Transform3D(Basis(Vector3.UP, yaw), origin)
		placement = PlantLibrary.fit_to_height(asset_id, float(plant.get("height_m", 0.3)), placement)
		var tint := _habitat_tint(int(plant.seed))
		var queued_id := PlantLibrary.queue(batches, asset_id, placement, int(plant.seed), "", tint)
		if queued_id.is_empty():
			continue
		var committed := plant.duplicate(true)
		committed["asset_id"] = queued_id
		committed["source_triangles"] = source_triangles
		committed["instance_tint"] = tint
		placed_plants.append(committed)
		triangles += source_triangles
		var zone := str(committed.get("zone", ""))
		var zone_record: Dictionary = zone_stats.get(zone, {"plants": 0, "triangles": 0})
		zone_record["plants"] = int(zone_record.plants) + 1
		zone_record["triangles"] = int(zone_record.triangles) + source_triangles
		zone_stats[zone] = zone_record
		var asset_zones: Dictionary = group_zones.get(queued_id, {})
		asset_zones[zone] = int(asset_zones.get(zone, 0)) + 1
		group_zones[queued_id] = asset_zones
		var group_record: Dictionary = group_stats.get(queued_id, {"plants": 0, "triangles": 0})
		group_record["plants"] = int(group_record.plants) + 1
		group_record["triangles"] = int(group_record.triangles) + source_triangles
		group_stats[queued_id] = group_record

	var root := PlantLibrary.build(batches)
	root.name = "BotanicalHabitats"
	for child: Node in root.get_children():
		if child is MultiMeshInstance3D:
			(child as MultiMeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.set_meta("plants", placed_plants)
	root.set_meta("triangles", triangles)
	root.set_meta("imported_triangles", triangles)
	root.set_meta("triangle_budget", MAX_ADDED_TRIANGLES)
	root.set_meta("batches", root.get_child_count())
	root.set_meta("batch_limit", MAX_VISIBLE_BATCHES)
	root.set_meta("zones", zone_stats)
	root.set_meta("group_zones", group_zones)
	root.set_meta("groups", group_stats)
	root.set_meta("quality", quality)
	root.set_meta("lake_id", str(lake.get("id", "")))
	return root


static func _habitat_tint(seed: int) -> Color:
	var value := 0.89 + 0.11 * Palette.hash01(SEED, seed, 781)
	var offset := 0.018 + 0.012 * Palette.hash01(SEED, seed, 782)
	var warm := Palette.hash01(SEED, seed, 783) < 0.5
	var red := value + offset if warm else value - offset
	var blue := value - offset if warm else value + offset
	return Color(clampf(red, 0.86, 1.0), clampf(value, 0.86, 1.0), clampf(blue, 0.86, 1.0), 1.0)


static func _layout_applies(field: Dictionary, scenery: Dictionary) -> bool:
	if str(field.get("id", "")) != "default":
		return false
	var bundled_groups: Dictionary = {}
	for group: Dictionary in scenery.get("groups", []):
		bundled_groups[str(group.get("id", ""))] = true
	return bundled_groups.has("shade-trees") and bundled_groups.has("farm-barn")


static func _shared_exclusions(scenery: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = Mask.footprints(scenery)
	for group: Dictionary in scenery.get("groups", []):
		if group.get("type", "") != "track" or group.get("surface", "") != "worn":
			continue
		var points := PackedVector2Array()
		for point: Vector2 in group.get("points", []):
			points.append(point)
		for polygon: PackedVector2Array in Geometry2D.offset_polyline(points, float(group.get("width", 0.0)) * 0.5,
				Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND):
			var record := Mask._record(str(group.get("id", "")), "footpath", polygon)
			if not record.is_empty():
				result.append(record)
	return result


static func _bank_footprint(lake: Dictionary) -> Dictionary:
	var bank: Variant = lake.get("bank_ne_m", PackedFloat64Array())
	if not bank is PackedFloat64Array or bank.size() < 6 or bank.size() % 2 != 0:
		return {}
	var points := PackedVector2Array()
	for index: int in range(0, bank.size(), 2):
		points.append(Vector2(bank[index], bank[index + 1]))
	return Mask._record("lake:%s" % str(lake.get("id", "")), "lake_bank", points)


static func _surface_rects(field: Dictionary) -> PackedFloat64Array:
	var table := GroundSurfaces.load_table()
	if not bool(table.get("ok", false)):
		return PackedFloat64Array()
	var built := GroundSurfaces.build(table.table, field)
	return built.rects if bool(built.get("ok", false)) else PackedFloat64Array()


static func _append_cluster(output: Array[Dictionary], field: Dictionary, exclusions: Array,
	surface_rects: PackedFloat64Array, lake: Dictionary, sequence: Dictionary, zone: String,
	center_north: float, center_east: float, radius_north: float, radius_east: float,
	assets: Array, quality: String, exclusion_grid: Dictionary = {}) -> void:
	for asset_value: Variant in assets:
		var plant_seed := _take_seed(sequence)
		var angle := TAU * Palette.hash01(SEED, plant_seed, 1)
		var radius := sqrt(Palette.hash01(SEED, plant_seed, 2))
		var north := center_north + cos(angle) * radius * radius_north
		var east := center_east + sin(angle) * radius * radius_east
		if not Grass.accepts(north, east, field, exclusions, exclusion_grid) \
				or not _quality_keeps(plant_seed, quality):
			continue
		var plant := _plant_record(str(asset_value), zone, north, east, plant_seed, surface_rects, lake)
		if not plant.is_empty():
			output.append(plant)


static func _append_grid(output: Array[Dictionary], field: Dictionary, exclusions: Array,
	surface_rects: PackedFloat64Array, lake: Dictionary, sequence: Dictionary, zone: String,
	asset_id: String, center_north: float, center_east: float, rows: int, columns: int,
	spacing_north: float, spacing_east: float, quality: String, omitted_cells: Array = [],
	exclusion_grid: Dictionary = {}) -> void:
	for row: int in range(rows):
		for column: int in range(columns):
			var plant_seed := _take_seed(sequence)
			if Vector2i(row, column) in omitted_cells:
				continue
			var jitter_north := (Palette.hash01(SEED, plant_seed, 6) - 0.5) * 0.12
			var jitter_east := (Palette.hash01(SEED, plant_seed, 7) - 0.5) * 0.12
			var north := center_north + (float(row) - float(rows - 1) * 0.5) * spacing_north + jitter_north
			var east := center_east + (float(column) - float(columns - 1) * 0.5) * spacing_east + jitter_east
			if not Grass.accepts(north, east, field, exclusions, exclusion_grid) \
					or not _quality_keeps(plant_seed, quality):
				continue
			var plant := _plant_record(asset_id, zone, north, east, plant_seed, surface_rects, lake)
			if not plant.is_empty():
				output.append(plant)


static func _append_shore_reeds(output: Array[Dictionary], field: Dictionary, exclusions: Array,
	surface_rects: PackedFloat64Array, lake: Dictionary, sequence: Dictionary, quality: String,
	exclusion_grid: Dictionary = {}) -> void:
	var anchors := _shore_cluster_anchors(lake)
	var selected: Array[Dictionary] = []
	for cluster_index in anchors.size():
		var anchor: Dictionary = anchors[cluster_index]
		for plant_index in SHORE_REEDS_PER_CLUSTER:
			var reed := _append_shore_plant(selected, field, exclusions, surface_rects, lake, sequence,
				anchor, "reed_aredon", cluster_index, plant_index, "reed", SHORE_REED_MIN_SPACING_M,
				exclusion_grid)
			if not reed.is_empty():
				reed["cluster_id"] = "reed_cluster_%d" % cluster_index
				selected.append(reed)
	for plant: Dictionary in selected:
		if _quality_keeps(int(plant.seed), quality):
			output.append(plant)


static func _append_shore_bank_plants(output: Array[Dictionary], field: Dictionary, exclusions: Array,
	surface_rects: PackedFloat64Array, lake: Dictionary, sequence: Dictionary, quality: String,
	exclusion_grid: Dictionary = {}) -> void:
	var anchors := _shore_cluster_anchors(lake)
	var selected: Array[Dictionary] = []
	for cluster_index in anchors.size():
		var anchor: Dictionary = anchors[cluster_index]
		for plant_index in SHORE_BANK_PLANTS_PER_CLUSTER:
			var asset_id := str(SHORE_BANK_ASSETS[plant_index % SHORE_BANK_ASSETS.size()])
			var plant := _append_shore_plant(selected, field, exclusions, surface_rects, lake, sequence,
				anchor, asset_id, cluster_index, plant_index, "bank", SHORE_BANK_MIN_SPACING_M,
				exclusion_grid)
			if not plant.is_empty():
				plant["cluster_id"] = "bank_cluster_%d" % cluster_index
				selected.append(plant)
		for plant_index in SHORE_SHRUBS_PER_CLUSTER:
			var shrub_index := cluster_index * SHORE_SHRUBS_PER_CLUSTER + plant_index
			var shrub := _append_shore_plant(selected, field, exclusions, surface_rects, lake, sequence,
				anchor, "bush_common_flowers", cluster_index, shrub_index, "shrub", SHORE_SHRUB_MIN_SPACING_M,
				exclusion_grid)
			if not shrub.is_empty():
				shrub["cluster_id"] = "shore_shrub_cluster_%d" % cluster_index
				shrub["decorative_soft_vegetation"] = true
				selected.append(shrub)
	for plant: Dictionary in selected:
		if _quality_keeps(int(plant.seed), quality):
			output.append(plant)


static func _append_shore_plant(selected: Array[Dictionary], field: Dictionary, exclusions: Array,
	surface_rects: PackedFloat64Array, lake: Dictionary, sequence: Dictionary, anchor: Dictionary,
	asset_id: String, cluster_index: int, plant_index: int, kind: String, minimum_spacing: float,
	exclusion_grid: Dictionary = {}) -> Dictionary:
	for attempt in SHORE_CANDIDATE_LIMIT:
		var plant_seed := _take_seed(sequence)
		var tangent_radius := 2.8 if kind == "reed" else 4.1 if kind == "bank" else 5.0
		var tangent_offset := (Palette.hash01(SEED, plant_seed, 21) * 2.0 - 1.0) * tangent_radius
		if kind == "bank":
			var slot_position := float(plant_index % SHORE_BANK_ASSETS.size()) - 2.5
			tangent_offset = slot_position * 0.95 + (Palette.hash01(SEED, plant_seed, 23) - 0.5) * 0.65
		elif kind == "shrub":
			tangent_offset = (-4.8 if cluster_index % 2 == 0 else 4.8) \
				+ (Palette.hash01(SEED, plant_seed, 23) - 0.5) * 0.7
		var normal_min := -0.55 if kind == "reed" else 0.35 if kind == "bank" else 0.15
		var normal_max := 0.55 if kind == "reed" else 1.0 if kind == "bank" else 0.8
		var normal_offset := lerpf(normal_min, normal_max, Palette.hash01(SEED, plant_seed, 22))
		var point: Vector2 = anchor.point + anchor.tangent * tangent_offset + anchor.outward * normal_offset
		var north := point.x
		var east := point.y
		var spaced := true
		for other: Dictionary in selected:
			if Vector2(north, east).distance_to(Vector2(float(other.north), float(other.east))) < minimum_spacing:
				spaced = false
				break
		if not spaced:
			continue
		# Reject crowded candidates before the more expensive terrain and footprint queries.
		var bank_sample := _shore_sample(lake, north, east, field, exclusions, exclusion_grid)
		if bank_sample.is_empty():
			continue
		var plant := _plant_record(asset_id, "shore", north, east, plant_seed, surface_rects, lake)
		if plant.is_empty():
			continue
		plant["lake_ground_down_m"] = float(bank_sample.ground_down_m)
		plant["shore_distance_m"] = float(bank_sample.signed_shore_distance_m)
		plant["cluster_index"] = cluster_index
		return plant
	return {}


static func _shore_sample(lake: Dictionary, north: float, east: float, field: Dictionary,
	exclusions: Array, exclusion_grid: Dictionary = {}) -> Dictionary:
	var bank_sample := LakeSurface.sample_terrain_validated(lake, north, east)
	var shore_distance := float(bank_sample.get("signed_shore_distance_m", 0.0))
	if not bool(bank_sample.get("covered", false)) or str(bank_sample.get("region", "")) != "bank" \
		or shore_distance > -SHORE_MIN_DISTANCE_M or shore_distance < -SHORE_MAX_DISTANCE_M \
		or float(bank_sample.get("ground_down_m", 0.0)) <= 0.0 \
		or float(bank_sample.get("signed_bank_distance_m", 0.0)) <= 0.0:
		return {}
	if not Grass.accepts(north, east, field, exclusions, exclusion_grid):
		return {}
	return bank_sample


static func _shore_cluster_anchors(lake: Dictionary) -> Array[Dictionary]:
	var anchors: Array[Dictionary] = []
	var shoreline: Variant = lake.get("shoreline_ne_m", PackedFloat64Array())
	var bank: Variant = lake.get("bank_ne_m", PackedFloat64Array())
	if not shoreline is PackedFloat64Array or not bank is PackedFloat64Array \
		or shoreline.size() < 6 or bank.size() != shoreline.size() or shoreline.size() % 2 != 0:
		return anchors
	var vertex_count: int = bank.size() / 2
	for index in SHORE_CLUSTER_VERTICES:
		if index < 0 or index >= vertex_count:
			continue
		var prev := posmod(index - 1, vertex_count)
		var next := posmod(index + 1, vertex_count)
		var shore_point := Vector2(shoreline[index * 2], shoreline[index * 2 + 1])
		var bank_point := Vector2(bank[index * 2], bank[index * 2 + 1])
		var tangent := Vector2(shoreline[next * 2] - shoreline[prev * 2],
			shoreline[next * 2 + 1] - shoreline[prev * 2 + 1]).normalized()
		var outward := (bank_point - shore_point).normalized()
		if tangent.length_squared() <= 0.5 or outward.length_squared() <= 0.5:
			continue
		anchors.append({"point": shore_point.lerp(bank_point, 0.5), "tangent": tangent, "outward": outward})
	return anchors


static func _plant_record(asset_id: String, zone: String, north: float, east: float, plant_seed: int,
	surface_rects: PackedFloat64Array, lake: Dictionary) -> Dictionary:
	var terrain := GroundTerrain.sample_validated(north, east, surface_rects, lake)
	if terrain.size() != 3 or not is_finite(terrain[0]) or not is_finite(terrain[1]) or not is_finite(terrain[2]):
		return {}
	var height_range: Vector2 = HEIGHT_RANGES.get(asset_id, Vector2(0.2, 0.5))
	var height := lerpf(height_range.x, height_range.y, Palette.hash01(SEED, plant_seed, 31))
	return {
		"zone": zone,
		"asset_id": asset_id,
		"north": north,
		"east": east,
		"ground_up_m": terrain[0],
		"ground_down_m": -terrain[0],
		"height_m": height,
		"yaw_rad": TAU * Palette.hash01(SEED, plant_seed, 32),
		"seed": plant_seed,
		"lake_ground_down_m": -terrain[0] if zone == "shore" else NAN,
	}


static func _take_seed(sequence: Dictionary) -> int:
	var value := int(sequence.get("next", 1))
	sequence["next"] = value + 1
	return value


static func _quality_keeps(plant_seed: int, quality: String) -> bool:
	var fraction := 0.25 if quality == "low" else 0.55 if quality == "balanced" else 1.0
	return Palette.hash01(SEED, plant_seed, 4242) < fraction

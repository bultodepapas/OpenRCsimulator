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
const MAX_ADDED_TRIANGLES := 70000
const MAX_VISIBLE_BATCHES := 24
const SHORE_REED_COUNT := 12
const SHORE_CANDIDATE_LIMIT := 512
const SHORE_MIN_SPACING_M := 3.0
const SHORE_MIN_DISTANCE_M := 0.75
const SHORE_MAX_DISTANCE_M := 4.5

const HEIGHT_RANGES := {
	"clover_1": Vector2(0.30, 0.52),
	"flower_3_group": Vector2(0.38, 0.60),
	"flower_4_group": Vector2(0.48, 0.65),
	"grass_common_short": Vector2(0.20, 0.34),
	"grass_common_tall": Vector2(0.32, 0.50),
	"grass_wispy_tall": Vector2(0.34, 0.50),
	"fern_1": Vector2(0.22, 0.42),
	"corn_4": Vector2(1.15, 1.42),
	"wheat_4": Vector2(0.72, 0.92),
	"reed_aredon": Vector2(1.10, 1.40),
}

const FLOWER_PATCHES := [
	{zone = "club", north = -15.0, east = -3.0, radius_n = 0.35, radius_e = 2.0,
		assets = ["clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "flower_3_group"]},
	{zone = "club", north = -15.0, east = 3.0, radius_n = 0.35, radius_e = 2.0,
		assets = ["clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "flower_3_group"]},
	{zone = "meadow", north = 58.0, east = 98.0, radius_n = 8.0, radius_e = 13.0,
		assets = ["clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "flower_3_group", "flower_4_group"]},
	{zone = "meadow", north = 64.0, east = 154.0, radius_n = 7.0, radius_e = 13.0,
		assets = ["clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "flower_3_group", "flower_4_group"]},
	{zone = "meadow", north = 47.0, east = 128.0, radius_n = 5.0, radius_e = 11.0,
		assets = ["clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1", "clover_1"]},
]

const GRASS_PATCHES := [
	{zone = "club", north = -52.0, east = -23.0, radius_n = 1.2, radius_e = 2.5,
		assets = ["grass_common_short", "fern_1"]},
	{zone = "club", north = -54.0, east = 7.0, radius_n = 1.2, radius_e = 2.5,
		assets = ["grass_common_short", "fern_1"]},
	{zone = "club", north = -29.5, east = -54.0, radius_n = 1.4, radius_e = 3.0,
		assets = ["grass_common_short", "fern_1"]},
	{zone = "club", north = -30.5, east = 54.0, radius_n = 1.4, radius_e = 3.0,
		assets = ["fern_1"]},
	{zone = "edge", north = 25.5, east = -42.0, radius_n = 2.0, radius_e = 7.0,
		assets = ["grass_common_short", "grass_common_tall", "grass_wispy_tall"]},
	{zone = "edge", north = 25.5, east = 42.0, radius_n = 2.0, radius_e = 7.0,
		assets = ["grass_common_short", "grass_common_tall", "grass_wispy_tall"]},
	{zone = "meadow", north = 58.0, east = 98.0, radius_n = 8.0, radius_e = 13.0,
		assets = ["grass_common_short", "grass_common_tall", "fern_1"]},
	{zone = "meadow", north = 64.0, east = 154.0, radius_n = 7.0, radius_e = 13.0,
		assets = ["grass_common_short", "grass_common_tall", "fern_1"]},
	{zone = "meadow", north = 47.0, east = 128.0, radius_n = 5.0, radius_e = 11.0,
		assets = ["grass_common_tall", "fern_1"]},
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
	var sequence := {"next": 1}
	var pilot_north := float(field.get("pilot", {}).get("north", 0.0))
	var pilot_east := float(field.get("pilot", {}).get("east", 0.0))

	for patch: Dictionary in FLOWER_PATCHES:
		_append_cluster(plants, field, land_exclusions, surface_rects, lake, sequence,
			str(patch.zone), pilot_north + float(patch.north), pilot_east + float(patch.east),
			float(patch.radius_n), float(patch.radius_e), patch.assets, quality)
	for patch: Dictionary in GRASS_PATCHES:
		_append_cluster(plants, field, land_exclusions, surface_rects, lake, sequence,
			str(patch.zone), pilot_north + float(patch.north), pilot_east + float(patch.east),
			float(patch.radius_n), float(patch.radius_e), patch.assets, quality)

	# Two restrained downloaded crop plots near the existing farm: 28 corn and 56 wheat.
	_append_grid(plants, field, land_exclusions, surface_rects, lake, sequence, "farm", "corn_4",
		pilot_north + 561.0, pilot_east + 324.0, 4, 7, 0.86, 0.82, quality)
	_append_grid(plants, field, land_exclusions, surface_rects, lake, sequence, "farm", "wheat_4",
		pilot_north + 561.0, pilot_east + 346.0, 7, 8, 0.78, 0.43, quality)

	if not lake.is_empty():
		_append_shore_reeds(plants, field, shared_exclusions, surface_rects, lake, sequence, quality)
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
		var queued_id := PlantLibrary.queue(batches, asset_id, placement, int(plant.seed))
		if queued_id.is_empty():
			continue
		var committed := plant.duplicate(true)
		committed["asset_id"] = queued_id
		committed["source_triangles"] = source_triangles
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
	assets: Array, quality: String) -> void:
	for asset_value: Variant in assets:
		var plant_seed := _take_seed(sequence)
		var angle := TAU * Palette.hash01(SEED, plant_seed, 1)
		var radius := sqrt(Palette.hash01(SEED, plant_seed, 2))
		var north := center_north + cos(angle) * radius * radius_north
		var east := center_east + sin(angle) * radius * radius_east
		if not Grass.accepts(north, east, field, exclusions) or not _quality_keeps(plant_seed, quality):
			continue
		var plant := _plant_record(str(asset_value), zone, north, east, plant_seed, surface_rects, lake)
		if not plant.is_empty():
			output.append(plant)


static func _append_grid(output: Array[Dictionary], field: Dictionary, exclusions: Array,
	surface_rects: PackedFloat64Array, lake: Dictionary, sequence: Dictionary, zone: String,
	asset_id: String, center_north: float, center_east: float, rows: int, columns: int,
	spacing_north: float, spacing_east: float, quality: String) -> void:
	for row: int in range(rows):
		for column: int in range(columns):
			var plant_seed := _take_seed(sequence)
			var jitter_north := (Palette.hash01(SEED, plant_seed, 6) - 0.5) * 0.12
			var jitter_east := (Palette.hash01(SEED, plant_seed, 7) - 0.5) * 0.12
			var north := center_north + (float(row) - float(rows - 1) * 0.5) * spacing_north + jitter_north
			var east := center_east + (float(column) - float(columns - 1) * 0.5) * spacing_east + jitter_east
			if not Grass.accepts(north, east, field, exclusions) or not _quality_keeps(plant_seed, quality):
				continue
			var plant := _plant_record(asset_id, zone, north, east, plant_seed, surface_rects, lake)
			if not plant.is_empty():
				output.append(plant)


static func _append_shore_reeds(output: Array[Dictionary], field: Dictionary, exclusions: Array,
	surface_rects: PackedFloat64Array, lake: Dictionary, sequence: Dictionary, quality: String) -> void:
	var bank: PackedFloat64Array = lake.get("bank_ne_m", PackedFloat64Array())
	if bank.size() < 6:
		return
	var min_north := INF
	var max_north := -INF
	var min_east := INF
	var max_east := -INF
	for index: int in range(0, bank.size(), 2):
		min_north = minf(min_north, bank[index])
		max_north = maxf(max_north, bank[index])
		min_east = minf(min_east, bank[index + 1])
		max_east = maxf(max_east, bank[index + 1])
	var selected: Array[Dictionary] = []
	for _attempt: int in range(SHORE_CANDIDATE_LIMIT):
		if selected.size() >= SHORE_REED_COUNT:
			break
		var plant_seed := _take_seed(sequence)
		var north := lerpf(min_north, max_north, Palette.hash01(SEED, plant_seed, 21))
		var east := lerpf(min_east, max_east, Palette.hash01(SEED, plant_seed, 22))
		var bank_sample := LakeSurface.sample_terrain_validated(lake, north, east)
		var shore_distance := float(bank_sample.get("signed_shore_distance_m", 0.0))
		if not bool(bank_sample.get("covered", false)) or str(bank_sample.get("region", "")) != "bank" \
			or shore_distance > -SHORE_MIN_DISTANCE_M or shore_distance < -SHORE_MAX_DISTANCE_M \
			or float(bank_sample.get("ground_down_m", 0.0)) <= 0.0:
			continue
		if not Grass.accepts(north, east, field, exclusions):
			continue
		var spaced := true
		for other: Dictionary in selected:
			if Vector2(north, east).distance_to(Vector2(float(other.north), float(other.east))) < SHORE_MIN_SPACING_M:
				spaced = false
				break
		if not spaced:
			continue
		var plant := _plant_record("reed_aredon", "shore", north, east, plant_seed, surface_rects, lake)
		if plant.is_empty():
			continue
		plant["lake_ground_down_m"] = float(bank_sample.ground_down_m)
		plant["shore_distance_m"] = shore_distance
		selected.append(plant)
	for plant: Dictionary in selected:
		if _quality_keeps(int(plant.seed), quality):
			output.append(plant)


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
	}


static func _take_seed(sequence: Dictionary) -> int:
	var value := int(sequence.get("next", 1))
	sequence["next"] = value + 1
	return value


static func _quality_keeps(plant_seed: int, quality: String) -> bool:
	var fraction := 0.25 if quality == "low" else 0.55 if quality == "balanced" else 1.0
	return Palette.hash01(SEED, plant_seed, 4242) < fraction

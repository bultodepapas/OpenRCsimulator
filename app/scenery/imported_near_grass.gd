## LU-23 downloaded foreground clumps. Placement comes only from the pinned grass.json rows.
extends RefCounted

const NearGrass := preload("res://render/near_grass.gd")
const GrassMask := preload("res://render/landscape_upgrade/scenery_grass_mask.gd")
const Frames := preload("res://render/frames.gd")
const Palette := preload("res://scenery/palette.gd")
const PlantLibrary := preload("res://scenery/imported_vegetation.gd")

const ASSET_IDS: Array[String] = [
	"grass_common_short",
	"grass_common_tall",
	"grass_wispy_tall",
]
const SEED := 610708
const MIN_HEIGHT_M := 0.12
const MAX_HEIGHT_M := 0.25
const MAX_SOURCE_TRIANGLES := 50000
const QUALITY_LIMITS := {
	"low": {
		"grass_common_short": 17,
		"grass_common_tall": 11,
		"grass_wispy_tall": 10,
	},
	"balanced": {
		"grass_common_short": 34,
		"grass_common_tall": 21,
		"grass_wispy_tall": 21,
	},
	"high": {
		"grass_common_short": 67,
		"grass_common_tall": 42,
		"grass_wispy_tall": 41,
	},
}

static var _rows_cache: Array = []


## Stable nested quality subsets over the existing, checksum-validated rows.
static func layout(field: Dictionary, quality: String = "high", exclusions: Array = []) -> Array[Dictionary]:
	var rows := _placement_rows()
	var result: Array[Dictionary] = []
	if rows.is_empty() or not field.has("pilot") or not field.has("surfaces"):
		return result
	var candidates_by_asset: Dictionary = {}
	var triangle_counts: Dictionary = {}
	for asset_id: String in ASSET_IDS:
		candidates_by_asset[asset_id] = []
		var asset := PlantLibrary.get_asset(asset_id)
		triangle_counts[asset_id] = int(asset.get("source_triangles", 0))
	var pilot: Dictionary = field.get("pilot", {})
	var pilot_north := float(pilot.get("north", 0.0))
	var pilot_east := float(pilot.get("east", 0.0))
	for row_index: int in range(rows.size()):
		var row: Array = rows[row_index]
		var north := pilot_north + float(row[0]) * 0.001
		var east := pilot_east + float(row[1]) * 0.001
		if not NearGrass.accepts(north, east, field, exclusions):
			continue
		var asset_index := int(Palette.hash01(SEED, row_index, 101) * float(ASSET_IDS.size()))
		var asset_id := ASSET_IDS[mini(asset_index, ASSET_IDS.size() - 1)]
		var source_triangles := int(triangle_counts.get(asset_id, 0))
		if source_triangles <= 0:
			continue
		var yaw_u16 := int(row[2])
		var size_u8 := int(row[3])
		(candidates_by_asset[asset_id] as Array).append({
			"asset_id": asset_id,
			"source_triangles": source_triangles,
			"row_index": row_index,
			"rank": int(Palette.hash01(SEED, row_index, 202) * 65536.0),
			"north": north,
			"east": east,
			"yaw_u16": yaw_u16,
			"yaw_rad": float(yaw_u16) * TAU / 65536.0,
			"size_u8": size_u8,
			"height_m": lerpf(MIN_HEIGHT_M, MAX_HEIGHT_M, float(size_u8) / 255.0),
			"seed": SEED + row_index,
		})

	var quality_limits: Dictionary = QUALITY_LIMITS.get(quality, QUALITY_LIMITS.high)
	var triangles := 0
	for asset_id: String in ASSET_IDS:
		var candidates: Array = candidates_by_asset[asset_id]
		candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			var left_rank := int(left.get("rank", 0))
			var right_rank := int(right.get("rank", 0))
			if left_rank != right_rank:
				return left_rank < right_rank
			return int(left.get("row_index", 0)) < int(right.get("row_index", 0))
		)
		var keep_count := mini(int(quality_limits.get(asset_id, 0)), candidates.size())
		for candidate_index: int in range(keep_count):
			var candidate: Dictionary = candidates[candidate_index]
			triangles += int(candidate.source_triangles)
			result.append(candidate.duplicate(true))
	if triangles > MAX_SOURCE_TRIANGLES:
		push_error("Downloaded near grass exceeds its %d source-triangle budget (%d)" % [MAX_SOURCE_TRIANGLES, triangles])
		return []
	return result


## Merge normalized building/gravel footprints, every scenery path, and a normalized lake bank polygon.
static func exclusions_for(scenery: Dictionary = {}, lake: Dictionary = {}) -> Array[Dictionary]:
	var result := GrassMask.footprints(scenery)
	var groups_value: Variant = scenery.get("groups", [])
	if groups_value is Array:
		for group_value: Variant in groups_value:
			if not group_value is Dictionary:
				continue
			var group: Dictionary = group_value
			if str(group.get("type", "")) != "track" or str(group.get("surface", "")) == "gravel":
				continue
			var path_points := _points(group.get("points", []))
			if path_points.size() < 2:
				continue
			var half_width := maxf(float(group.get("width", 0.0)) * 0.5, 0.0)
			for polygon: PackedVector2Array in Geometry2D.offset_polyline(
				path_points, half_width, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND):
				var footprint := GrassMask._record(str(group.get("id", "path")), "path", polygon)
				if not footprint.is_empty():
					result.append(footprint)
	var bank: Variant = lake.get("bank_ne_m", PackedFloat64Array())
	if bank is PackedFloat64Array and bank.size() >= 6 and bank.size() % 2 == 0:
		var bank_points := PackedVector2Array()
		for index: int in range(0, bank.size(), 2):
			bank_points.append(Vector2(bank[index], bank[index + 1]))
		var bank_footprint := GrassMask._record("lake:%s" % str(lake.get("id", "")), "lake_bank", bank_points)
		if not bank_footprint.is_empty():
			result.append(bank_footprint)
	return result


## Build one source-material MultiMesh batch per downloaded grass asset; there are no authored plant meshes here.
static func build(field: Dictionary, quality: String = "high", exclusions: Array = []) -> Node3D:
	var plants := layout(field, quality, exclusions)
	var batches: Dictionary = {}
	var cpu_placements: Array[Dictionary] = []
	var group_stats: Dictionary = {}
	var triangles := 0
	for plant: Dictionary in plants:
		var asset_id := str(plant.get("asset_id", ""))
		var source_triangles := int(plant.get("source_triangles", 0))
		var origin := Frames.ned_to_render([float(plant.north), float(plant.east), 0.0])
		var placement := Transform3D(Basis(Vector3.UP, float(plant.yaw_rad)), origin)
		placement = PlantLibrary.fit_to_height(asset_id, float(plant.height_m), placement)
		var queued_id := PlantLibrary.queue(batches, asset_id, placement, int(plant.seed))
		if queued_id.is_empty():
			continue
		var batch_records: Array = batches[queued_id]
		var queued_record: Dictionary = batch_records[batch_records.size() - 1]
		var committed := plant.duplicate(true)
		committed["asset_id"] = queued_id
		committed["transform"] = queued_record.get("transform", placement)
		cpu_placements.append(committed)
		triangles += source_triangles
		var group_record: Dictionary = group_stats.get(queued_id, {"plants": 0, "triangles": 0})
		group_record["plants"] = int(group_record.plants) + 1
		group_record["triangles"] = int(group_record.triangles) + source_triangles
		group_stats[queued_id] = group_record

	var root := PlantLibrary.build(batches, false)
	root.name = "NearGrass"
	for child: Node in root.get_children():
		if child is MultiMeshInstance3D:
			(child as MultiMeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.set_meta("imported", true)
	root.set_meta("clumps", cpu_placements.size())
	root.set_meta("placements", cpu_placements)
	root.set_meta("cpu_placements", cpu_placements)
	root.set_meta("source_triangles", triangles)
	root.set_meta("triangles", triangles)
	root.set_meta("triangle_budget", MAX_SOURCE_TRIANGLES)
	root.set_meta("batches", batches.size())
	root.set_meta("asset_batches", batches.size())
	root.set_meta("groups", group_stats)
	root.set_meta("quality", quality)
	root.set_meta("source_assets", batches.keys())
	return root


static func _placement_rows() -> Array:
	if not _rows_cache.is_empty():
		return _rows_cache.duplicate(false)
	var file := FileAccess.open(NearGrass.DATA_PATH, FileAccess.READ)
	if file == null:
		push_warning("Downloaded near grass placement data is missing; foreground grass is empty")
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	_rows_cache = NearGrass.validated_rows(parsed)
	if _rows_cache.is_empty():
		push_warning("Downloaded near grass placement data failed validation; foreground grass is empty")
	return _rows_cache.duplicate(false)


static func _points(value: Variant) -> PackedVector2Array:
	if value is PackedVector2Array:
		return value
	var result := PackedVector2Array()
	if not value is Array:
		return result
	for item: Variant in value:
		if item is Vector2:
			result.append(item)
		elif item is Array and item.size() == 2 \
			and (item[0] is int or item[0] is float) and (item[1] is int or item[1] is float):
			result.append(Vector2(float(item[0]), float(item[1])))
	return result

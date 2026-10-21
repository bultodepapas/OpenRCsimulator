## LU-23: shared scalar dimensions for downloaded vegetation placement and coarse obstacle envelopes.
extends RefCounted
const Library := preload("res://scenery/imported_vegetation.gd")
const Palette := preload("res://scenery/palette.gd")
const MATURE_MAPLE_HEIGHT_M := 14.0
const CLUB_MAPLE_SEED := 793949324 # Existing shade-trees placement 6; keep the clubhouse Maple mature.
const ORCHARD_BERRY_GROUP_ID := "countryside-orchard"
const ORCHARD_BERRY_ASSET := "forest_leafy_shrub"

static func handles(prefab: String) -> bool:
	return prefab in ["shade_tree", "sapling", "bush", "flower_clump"]

static func spec(prefab: String, seed: int, group_id: String = "") -> Dictionary:
	var asset_id := Library.resolve_id(prefab, seed)
	if prefab == "bush" and group_id == ORCHARD_BERRY_GROUP_ID:
		# LU-28's compact berry rows reuse the downloaded forest shrub. Keeping the
		# choice here shares dimensions and fit with the scenery collision proxy.
		asset_id = ORCHARD_BERRY_ASSET
	var asset := Library.get_asset(asset_id)
	if asset.is_empty():
		return {}
	var height := 9.35 + 0.95 * Palette.hash01(seed, 1)
	if asset_id == "maple_tree":
		height = MATURE_MAPLE_HEIGHT_M if seed == CLUB_MAPLE_SEED else 9.5 + 2.5 * Palette.hash01(seed, 1)
	if prefab == "bush":
		height = 0.68 + 0.16 * Palette.hash01(seed, 1)
	elif prefab == "flower_clump":
		height = 0.32 + 0.06 * Palette.hash01(seed, 1)
	var bounds: Dictionary = asset.source_bounds_m
	if prefab == "sapling":
		height = 3.2 + 1.6 * Palette.hash01(seed, 1)
	var scale := height / float(bounds.height)
	var source_size: Array = bounds.size
	# Downloaded crowns are asymmetric about their grounded stems. Use the same
	# source bounds as rendering when centering the coarse collision envelope.
	var crown_x := 0.0
	var crown_z := 0.0
	if asset_id == "maple_tree" or str(asset.get("source_id", "")) == "landscapelab_tree_2026":
		crown_x = (float(bounds.min[0]) + float(bounds.max[0])) * 0.5 * scale
		crown_z = (float(bounds.min[2]) + float(bounds.max[2])) * 0.5 * scale
	return {asset_id = asset_id, height = height, scale = scale,
		width = float(source_size[0]) * scale, depth = float(source_size[2]) * scale,
		triangles = int(asset.source_triangles), wind_margin = 0.06,
		crown_offset_x = crown_x, crown_offset_z = crown_z}

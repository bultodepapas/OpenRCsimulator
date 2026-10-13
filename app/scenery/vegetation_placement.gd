## LU-23: shared scalar dimensions for downloaded vegetation placement and coarse obstacle envelopes.
extends RefCounted
const Library := preload("res://scenery/imported_vegetation.gd")
const Palette := preload("res://scenery/palette.gd")

static func handles(prefab: String) -> bool:
	return prefab in ["shade_tree", "sapling", "bush", "flower_clump"]

static func spec(prefab: String, seed: int) -> Dictionary:
	var asset_id := Library.resolve_id(prefab, seed)
	var asset := Library.get_asset(asset_id)
	if asset.is_empty():
		return {}
	var height := 9.35 + 0.95 * Palette.hash01(seed, 1)
	if prefab == "bush":
		height = 0.68 + 0.16 * Palette.hash01(seed, 1)
	elif prefab == "flower_clump":
		height = 0.32 + 0.06 * Palette.hash01(seed, 1)
	var bounds: Dictionary = asset.source_bounds_m
	if prefab == "sapling":
		height = 3.2 + 1.6 * Palette.hash01(seed, 1)
	var scale := height / float(bounds.height)
	var source_size: Array = bounds.size
	return {asset_id = asset_id, height = height, scale = scale,
		width = float(source_size[0]) * scale, depth = float(source_size[2]) * scale,
		triangles = int(asset.source_triangles), wind_margin = 0.06}

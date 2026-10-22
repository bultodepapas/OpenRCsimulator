## L8a-R1: field trees in front of the pilot as 3D LandscapeLab trees (rules in render/treeline.gd).
## They use the close trees' qualified wind, world-unit LOD and distant-foliage path, and cast no
## real-time shadow, like the cards they replace. Collision uses the same imported envelope.
extends RefCounted

const Treeline = preload("res://render/treeline.gd")
const Frames = preload("res://render/frames.gd")
const ImportedVegetation = preload("res://scenery/imported_vegetation.gd")
# One MultiMesh selects one LOD for all its instances, from its nearest point: a single batch per
# model drew all 127 trees at full detail. Cells let distant trees take their own LOD and cull.
const CELL_SIZE_M := 256
# These trees stand 313-600 m from the pilot; bark may show this many pixels of LOD error
# (foliage keeps 1 px, so crowns do not pop while the pilot camera zooms).
const BARK_LOD_ERROR_PX := 8.0


static func build(object_data: Dictionary, pilot: Dictionary, front_azimuth: float,
		half_angle_deg: float = Treeline.DETAIL_HALF_ANGLE_DEG) -> Node3D:
	var result := Node3D.new()
	result.name = str(object_data.get("id", "treeline")) + "Detail"
	result.position = Frames.ned_to_render([pilot.north, pilot.east, pilot.down])
	var batches := {}
	for index: int in object_data.positions.size():
		var point: Array = object_data.positions[index]
		var asset_id := Treeline.detail_asset(point[0], point[1], front_azimuth, half_angle_deg)
		if asset_id.is_empty():
			continue
		var tree: Dictionary = Treeline.identity(point[0], point[1])
		# Scenery's heading convention, shared with CollisionWorld's crown envelope.
		var heading := rad_to_deg(float(tree.yaw))
		var placement := Transform3D(Basis(Vector3.UP, -deg_to_rad(heading)), Frames.ned_to_render(point))
		ImportedVegetation.queue(batches, asset_id, ImportedVegetation.fit_to_height(asset_id, float(tree.height), placement), index)
	if batches.is_empty():
		return result
	var trees := ImportedVegetation.build(batches, false, {"tree_wind": _tree_wind_enabled(), "tree_cell_size_m": CELL_SIZE_M,
		"bark_lod_error_px": BARK_LOD_ERROR_PX})
	for child in trees.get_children():
		(child as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	result.add_child(trees)
	return result


## Mirrors Scenery.options(): --tree_wind=off or OPENRC_TREE_WIND=off keeps imported trees static.
static func _tree_wind_enabled() -> bool:
	var value := OS.get_environment("OPENRC_TREE_WIND")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--tree_wind="):
			value = argument.trim_prefix("--tree_wind=")
	return value.is_empty() or ["on", "1", "true", "yes"].has(value.to_lower())

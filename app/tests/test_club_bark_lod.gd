## L6c-R2: club LandscapeLab bark switches LOD at Scenery.CLUB_BARK_LOD_ERROR_PX; foliage and the
## protected maple keep the chain of a default ImportedVegetation build.
## Run: godot --headless --path . --script res://tests/test_club_bark_lod.gd
extends SceneTree

const Scenery := preload("res://scenery/scenery.gd")
const Loader := preload("res://scenery/scenery_loader.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const ImportedVegetation := preload("res://scenery/imported_vegetation.gd")
const ShaderClock := preload("res://render/shader_clock.gd")
const OPTS := {audio = false, birds = false, theme = "", quality = "high"}

var _failures := 0


func _initialize() -> void:
	ShaderClock.register()
	var field: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH).field
	var scenery: Dictionary = Loader.load_from(Loader.DEFAULT_PATH, field).scenery
	var root := Scenery.build(field, scenery, OPTS)
	var batches := root.get_node_or_null("ImportedVegetationBatches")
	_check("the club builds its imported vegetation", batches != null)
	var checked := {}
	if batches != null:
		for batch: MultiMeshInstance3D in batches.find_children("*", "MultiMeshInstance3D", true, false):
			var asset_id := str(batch.name).get_slice("_Part_", 0)
			if checked.has(asset_id) or not (asset_id.begins_with("landscapelab_") or asset_id == "maple_tree"):
				continue
			checked[asset_id] = true
			_check_asset(asset_id, batch.multimesh.mesh)
	_check("club LandscapeLab trees and the maple were checked", checked.has("landscapelab_quercus")
		and checked.has("landscapelab_fagus") and checked.has("landscapelab_pine") and checked.has("maple_tree"),
		str(checked.keys()))
	root.free()
	print("club bark LOD tests passed" if _failures == 0 else "%d club bark LOD test(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _check_asset(asset_id: String, club_mesh: Mesh) -> void:
	var batches := {}
	ImportedVegetation.queue(batches, asset_id, ImportedVegetation.fit_to_height(asset_id, 12.0, Transform3D()), 1)
	var reference := ImportedVegetation.build(batches, false, {"tree_wind": true})
	var default_mesh: Mesh = (reference.get_child(0) as MultiMeshInstance3D).multimesh.mesh
	var materials: Array = ImportedVegetation.get_parts(asset_id)[0].get("materials", [])
	for surface in club_mesh.get_surface_count():
		var club_lods: Array = RenderingServer.mesh_get_surface(club_mesh.get_rid(), surface).get("lods", [])
		var default_lods: Array = RenderingServer.mesh_get_surface(default_mesh.get_rid(), surface).get("lods", [])
		var foliage := (materials[surface] as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		if asset_id == "maple_tree" or foliage:
			_check("%s surface %d keeps the default LOD chain" % [asset_id, surface], club_lods == default_lods)
			continue
		var scaled := club_lods.size() == default_lods.size() and not default_lods.is_empty()
		for level in range(mini(club_lods.size(), default_lods.size())):
			scaled = scaled and club_lods[level].index_data == default_lods[level].index_data \
				and is_equal_approx(float(club_lods[level].edge_length),
					float(default_lods[level].edge_length) / Scenery.CLUB_BARK_LOD_ERROR_PX)
		_check("%s bark switches LOD at %.0f px" % [asset_id, Scenery.CLUB_BARK_LOD_ERROR_PX], scaled)
	reference.free()


func _check(label: String, condition: bool, detail: String = "") -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s %s" % [label, detail])

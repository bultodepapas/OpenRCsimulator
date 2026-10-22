## L8a-R1: near-ring field trees in front of the pilot render and collide as 3D LandscapeLab trees.
extends SceneTree

const FieldLoader := preload("res://data/field_loader.gd")
const Field := preload("res://render/field.gd")
const Treeline := preload("res://render/treeline.gd")
const FieldTreeDetail := preload("res://render/field_tree_detail.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
const ImportedVegetation := preload("res://scenery/imported_vegetation.gd")
const VegetationPlacement := preload("res://scenery/vegetation_placement.gd")

var _failures := 0


func _initialize() -> void:
	var field: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH).field
	var front := Treeline.front_azimuth_deg(field)
	_check("the default field's flying area lies north of the pilot", is_equal_approx(front, 0.0))
	var trees: Dictionary = field.objects[0]
	var detail: Array[int] = []
	for index: int in trees.positions.size():
		var point: Array = trees.positions[index]
		var asset_id := Treeline.detail_asset(point[0], point[1], front)
		if asset_id.is_empty():
			continue
		detail.append(index)
		var radius := Vector2(point[0], point[1]).length()
		var azimuth := rad_to_deg(atan2(point[1], point[0]))
		_check("tree %d lies in the front near ring" % index, radius <= Treeline.DETAIL_MAX_RADIUS_M
			and absf(wrapf(azimuth - front, -180.0, 180.0)) <= Treeline.DETAIL_HALF_ANGLE_DEG)
		_check("tree %d maps its card species to a LandscapeLab model" % index,
			asset_id == Treeline.DETAIL_ASSETS[int(Treeline.identity(point[0], point[1]).species)])
	_check("the front near ring holds 127 field trees", detail.size() == 127, str(detail.size()))
	_check("without a front azimuth every tree stays a card",
		Treeline.detail_asset(trees.positions[detail[0]][0], trees.positions[detail[0]][1], NAN).is_empty())
	_test_rendering(field, trees, front, detail.size())
	_test_collision(field, trees, front, detail)
	_test_wind_stays_inside_envelopes(trees, front)
	_test_lod_error()
	if _failures == 0:
		print("field tree detail tests passed")
		quit(0)
	else:
		push_error("%d field tree detail test(s) failed" % _failures)
		quit(1)


func _test_rendering(field: Dictionary, trees: Dictionary, front: float, detail_count: int) -> void:
	var cards := Treeline.build(trees, field.pilot, front)
	var card_count := 0
	for child: MultiMeshInstance3D in cards.get_children():
		card_count += child.multimesh.instance_count
	_check("cards keep the eight-sector contract", cards.get_child_count() == 8)
	_check("cards and 3D trees together keep every field tree", card_count + detail_count == trees.positions.size(),
		"%d + %d" % [card_count, detail_count])
	var detail := FieldTreeDetail.build(trees, field.pilot, front)
	var instances := 0
	var shadowless := true
	var tree_wind := true
	var cells := {}
	for batch: MultiMeshInstance3D in detail.find_children("*", "MultiMeshInstance3D", true, false):
		instances += batch.multimesh.instance_count
		# get_slice() returns the whole name when it has no cell suffix.
		cells[str(batch.name).get_slice("_Cell_", 1) if str(batch.name).contains("_Cell_") else ""] = true
		shadowless = shadowless and batch.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tree_wind = tree_wind and bool(batch.get_meta("_imported_vegetation_tree_wind_enabled", false))
		_check("%s selects LOD in world units" % batch.name, not is_equal_approx(batch.lod_bias, 1.0))
	_check("every front tree is one 3D instance", instances == detail_count, str(instances))
	_check("3D field trees are batched in %d m cells, so each cell selects its own LOD" % FieldTreeDetail.CELL_SIZE_M,
		cells.size() > 1 and not cells.has(""), str(cells.keys()))
	_check("3D field trees cast no real-time shadow, like the cards", shadowless)
	_check("3D field trees use the qualified tree wind", tree_wind)
	_check("a field without a runway direction builds no 3D trees",
		FieldTreeDetail.build(trees, field.pilot, NAN).get_child_count() == 0)
	var built := Field.build(field)
	_check("the production field places the 3D trees beside the cards",
		built.get_node_or_null("treelineDetail") != null and built.get_node_or_null("treeline") != null)
	cards.free()
	detail.free()
	built.free()


func _test_collision(field: Dictionary, trees: Dictionary, front: float, detail: Array[int]) -> void:
	var built: Dictionary = CollisionWorld.build(field, {groups = []})
	_check("the field collision world builds", bool(built.get("ok", false)), str(built.get("errors", [])))
	if not bool(built.get("ok", false)):
		return
	var world: Dictionary = built.world
	var by_id := {}
	for proxy: Dictionary in world.proxies:
		by_id[str(proxy.id)] = proxy
	for index: int in [detail[0], detail[detail.size() / 2], detail[-1]]:
		var point: Array = trees.positions[index]
		var tree: Dictionary = Treeline.identity(point[0], point[1])
		var spec: Dictionary = VegetationPlacement.asset_spec(Treeline.detail_asset(point[0], point[1], front), float(tree.height))
		var crown: Dictionary = by_id.get("tree:treeline:%04d:crown" % index, {})
		_check("3D tree %d collides with its imported crown envelope" % index, not crown.is_empty()
			and is_equal_approx(float(crown.half_x), float(spec.width) * 0.5 + float(spec.wind_margin))
			and is_equal_approx(float(crown.half_z), float(spec.depth) * 0.5 + float(spec.wind_margin))
			and is_equal_approx(float(crown.bounds_down_min), -float(tree.height)), str(crown))
		_check("3D tree %d keeps a trunk proxy" % index, by_id.has("tree:treeline:%04d:trunk" % index))
	var card_index := -1
	for index: int in trees.positions.size():
		if not detail.has(index):
			card_index = index
			break
	var card_tree: Dictionary = Treeline.identity(trees.positions[card_index][0], trees.positions[card_index][1])
	var card_crown: Dictionary = by_id["tree:treeline:%04d:crown" % card_index]
	var card_half := float(card_tree.height) * CollisionWorld.FIELD_TREE_CARD_FRAME_SIZE_M \
		* float(CollisionWorld.FIELD_TREE_ALPHA_HALF_WIDTH_FRACTIONS[int(card_tree.species)]) + CollisionWorld.FIELD_TREE_WIND_LEAN_M
	_check("card trees keep their card envelope", is_equal_approx(float(card_crown.half_x), card_half))
	_check("every field tree keeps a trunk and a crown proxy",
		world.proxies.filter(func(p: Dictionary) -> bool: return str(p.id).begins_with("tree:treeline:")).size()
			== 2 * trees.positions.size())


## The saturated crown sway of the smallest 3D field tree of each asset stays inside its crown box.
func _test_wind_stays_inside_envelopes(trees: Dictionary, front: float) -> void:
	var smallest := {}
	for point: Array in trees.positions:
		var asset_id := Treeline.detail_asset(point[0], point[1], front)
		if asset_id.is_empty():
			continue
		var height := float(Treeline.identity(point[0], point[1]).height)
		smallest[asset_id] = minf(float(smallest.get(asset_id, INF)), height)
	for asset_id: String in smallest:
		var height := float(smallest[asset_id])
		var spec: Dictionary = VegetationPlacement.asset_spec(asset_id, height)
		var limit := float(ImportedVegetation.TREE_WIND_LEAN_LIMITS_M[asset_id])
		var part: Dictionary = ImportedVegetation.get_parts(asset_id)[0]
		var part_bounds: AABB = part.bounds
		var ground_offset := float(ImportedVegetation.get_asset(asset_id).source_bounds_m.get("ground_offset", 0.0))
		var crown_bottom := minf(height * CollisionWorld.SHADE_TREE_TRUNK_HEIGHT_FRACTION,
			height * float(CollisionWorld.LANDSCAPELAB_CROWN_BOTTOM_FRACTIONS.get(asset_id, 1.0)))
		var half_x := float(spec.width) * 0.5 + float(spec.wind_margin)
		var half_z := float(spec.depth) * 0.5 + float(spec.wind_margin)
		var escape := -INF
		var mesh: Mesh = part.mesh
		for surface_index in mesh.get_surface_count():
			for vertex: Vector3 in mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_VERTEX]:
				if (vertex.y + ground_offset) * float(spec.scale) < crown_bottom:
					continue
				var weight := clampf((vertex.y - part_bounds.position.y) / part_bounds.size.y, 0.0, 1.0)
				var sway := limit * weight * weight
				escape = maxf(escape, maxf(absf(vertex.x * float(spec.scale) - float(spec.crown_offset_x)) + sway - half_x,
					absf(vertex.z * float(spec.scale) - float(spec.crown_offset_z)) + sway - half_z))
		_check("%s at %.1f m sways inside its 3D field-tree crown (escape %.3f m)" % [asset_id, height, escape], escape <= 0.0)


## Bark LOD errors are divided by BARK_LOD_ERROR_PX; foliage keeps the club trees' chain, and builds
## without the option (the club trees) keep the source errors.
func _test_lod_error() -> void:
	for asset_id: String in Treeline.DETAIL_ASSETS:
		var batches := {}
		ImportedVegetation.queue(batches, asset_id, ImportedVegetation.fit_to_height(asset_id, 18.0, Transform3D()), 1)
		var source_mesh: Mesh = ImportedVegetation.get_parts(asset_id)[0].mesh
		var materials: Array = ImportedVegetation.get_parts(asset_id)[0].get("materials", [])
		var club := ImportedVegetation.build(batches, false, {"tree_wind": true})
		var field := ImportedVegetation.build(batches, false, {"tree_wind": true,
			"bark_lod_error_px": FieldTreeDetail.BARK_LOD_ERROR_PX})
		var invalid := ImportedVegetation.build(batches, false, {"tree_wind": true, "bark_lod_error_px": 0.5})
		var club_mesh: Mesh = (club.get_child(0) as MultiMeshInstance3D).multimesh.mesh
		var field_mesh: Mesh = (field.get_child(0) as MultiMeshInstance3D).multimesh.mesh
		var invalid_mesh: Mesh = (invalid.get_child(0) as MultiMeshInstance3D).multimesh.mesh
		for surface_index in source_mesh.get_surface_count():
			var source_lods: Array = RenderingServer.mesh_get_surface(source_mesh.get_rid(), surface_index).get("lods", [])
			var club_lods: Array = RenderingServer.mesh_get_surface(club_mesh.get_rid(), surface_index).get("lods", [])
			var field_lods: Array = RenderingServer.mesh_get_surface(field_mesh.get_rid(), surface_index).get("lods", [])
			var invalid_lods: Array = RenderingServer.mesh_get_surface(invalid_mesh.get_rid(), surface_index).get("lods", [])
			_check("%s surface %d: an invalid bark error falls back to the default chain" % [asset_id, surface_index],
				invalid_lods == club_lods)
			if (materials[surface_index] as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
				_check("%s foliage keeps the club trees' LOD chain" % asset_id, field_lods == club_lods)
				continue
			var scaled := field_lods.size() == source_lods.size() and club_lods == source_lods and not source_lods.is_empty()
			for level in range(mini(field_lods.size(), source_lods.size())):
				scaled = scaled and field_lods[level].index_data == source_lods[level].index_data \
					and is_equal_approx(float(field_lods[level].edge_length),
						float(source_lods[level].edge_length) / FieldTreeDetail.BARK_LOD_ERROR_PX)
			_check("%s bark switches LOD at %.0f px of error; club bark keeps its source errors" % [
				asset_id, FieldTreeDetail.BARK_LOD_ERROR_PX], scaled)
		club.free()
		field.free()
		invalid.free()
	_check("an invalid bark LOD error warns once", ImportedVegetation._option_warnings.has("bark_lod_error_px"))


func _check(label: String, condition: bool, detail: String = "") -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s %s" % [label, detail])

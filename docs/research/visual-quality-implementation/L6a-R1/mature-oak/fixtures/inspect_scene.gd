## Inventory the production tree population and scalar collision identity.
extends SceneTree

const FieldLoader = preload("res://data/field_loader.gd")
const SceneryLoader = preload("res://scenery/scenery_loader.gd")
const Placement = preload("res://scenery/vegetation_placement.gd")
const World = preload("res://scenery/collision_world.gd")


func _initialize() -> void:
	var field_result: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	if not field_result.ok:
		push_error(str(field_result.errors))
		quit(1)
		return
	var scenery_result: Dictionary = SceneryLoader.load_from(SceneryLoader.DEFAULT_PATH, field_result.field)
	if not scenery_result.ok:
		push_error(str(scenery_result.errors))
		quit(1)
		return
	var world: Dictionary = World.build(field_result.field, scenery_result.scenery)
	if not world.ok:
		push_error(str(world.errors))
		quit(1)
		return
	var report := {world_identity_without_lights = world.world.identity, proxy_count = world.world.proxies.size(),
		trees = [], tree_counts = {}, tree_source_triangles = 0}
	for group: Dictionary in scenery_result.scenery.groups:
		if str(group.get("type", "")) != "instances":
			continue
		for index in group.placements.size():
			var item: Dictionary = group.placements[index]
			if str(item.prefab) not in ["shade_tree", "sapling"]:
				continue
			var spec: Dictionary = Placement.spec(item.prefab, item.seed)
			report.trees.append({id = "prop:%s:%02d" % [group.id, index], placement = item, spec = spec})
			report.tree_counts[spec.asset_id] = int(report.tree_counts.get(spec.asset_id, 0)) + 1
			report.tree_source_triangles += int(spec.triangles)
	print(JSON.stringify(report, "\t", true))
	quit(0)

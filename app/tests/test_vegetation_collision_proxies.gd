extends SceneTree

const CollisionWorld := preload("res://scenery/collision_world.gd")
const VegetationPlacement := preload("res://scenery/vegetation_placement.gd")
const Palette := preload("res://scenery/palette.gd")
const SceneryCollision := preload("res://sim/scenery_collision.gd")
const RB := preload("res://physics/rigid_body.gd")

var checks := 0
var failures := 0
const TEST_TRUNK_RADIUS_FRACTION := 0.05
const TEST_TRUNK_HEIGHT_FRACTION := 0.355
const TEST_TRUNK_HEIGHT_VARIATION_FRACTION := 0.025


func _initialize() -> void:
	var field := {pilot = {north = 0.0, east = 0.0, down = 0.0}, objects = []}
	var scenery := {groups = [{id = "garden", type = "instances", placements = [
		{north = 100.0, east = 50.0, heading = 37.0, prefab = "shade_tree", seed = 31, source_index = 17},
		{north = 40.0, east = -20.0, heading = 123.0, prefab = "bush", seed = 5, source_index = 29},
	]}]}
	var built: Dictionary = CollisionWorld.build(field, scenery)
	_check("imported vegetation proxy world builds", bool(built.get("ok", false)), str(built.get("errors", [])))
	if not bool(built.get("ok", false)):
		quit(1)
		return
	var world: Dictionary = built.world
	var tree_spec: Dictionary = VegetationPlacement.spec("shade_tree", 31)
	var bush_spec: Dictionary = VegetationPlacement.spec("bush", 5)
	var trunk := _proxy(world, "tree:shade-tree:garden:00:trunk")
	var crown := _proxy(world, "tree:shade-tree:garden:00:crown")
	var bush := _proxy(world, "vegetation:garden:01:bush")
	_check("shade-tree source spec resolves", not tree_spec.is_empty())
	_check("bush source spec resolves", not bush_spec.is_empty())
	_check("stable shade-tree trunk and crown proxy IDs remain present", not trunk.is_empty() and not crown.is_empty())
	_check("stable bush proxy ID remains present", not bush.is_empty())
	if trunk.is_empty() or crown.is_empty() or bush.is_empty():
		quit(1)
		return

	var crown_height := float(tree_spec.height) - float(trunk.bounds_down_max - trunk.bounds_down_min)
	# The trunk occupies the deterministic lower stem envelope; imported bounds size both parts.
	var expected_trunk_height := float(tree_spec.height) * (TEST_TRUNK_HEIGHT_FRACTION
		+ TEST_TRUNK_HEIGHT_VARIATION_FRACTION * Palette.hash01(31, 2))
	var expected_radius := minf(float(tree_spec.width), float(tree_spec.depth)) \
		* TEST_TRUNK_RADIUS_FRACTION + float(tree_spec.wind_margin)
	_check("trunk width comes from source bounds with its wind allowance",
		is_equal_approx(float(trunk.radius), expected_radius)
		and is_equal_approx(float(trunk.bounds_down_min), -expected_trunk_height)
		and is_equal_approx(float(trunk.bounds_down_max), 0.0))
	_check("crown spans the imported upper uniform-height bounds",
		crown.shape == "box" and crown.kind == "tree_foliage" and crown.part == "crown"
		and is_equal_approx(float(crown.half_x), float(tree_spec.width) * 0.5 + float(tree_spec.wind_margin))
		and is_equal_approx(float(crown.half_z), float(tree_spec.depth) * 0.5 + float(tree_spec.wind_margin))
		and is_equal_approx(float(crown.half_down), crown_height * 0.5)
		and is_equal_approx(float(crown.bounds_down_min), -float(tree_spec.height))
		and is_equal_approx(float(crown.bounds_down_max), -expected_trunk_height))
	_check("shade-tree damage keys remain stable by source placement and part",
		str(trunk.damage_id) == "prop:garden:17:trunk" and str(crown.damage_id) == "prop:garden:17:crown")
	_check("bush box uses imported uniform-height source bounds and wind margin",
		bush.shape == "box" and bush.kind == "tree_foliage" and bush.part == "bush"
		and is_equal_approx(float(bush.half_x), float(bush_spec.width) * 0.5 + float(bush_spec.wind_margin))
		and is_equal_approx(float(bush.half_z), float(bush_spec.depth) * 0.5 + float(bush_spec.wind_margin))
		and is_equal_approx(float(bush.half_down), float(bush_spec.height) * 0.5)
		and is_equal_approx(float(bush.down), -float(bush_spec.height) * 0.5)
		and str(bush.damage_id) == "prop:garden:29")
	var repeated: Dictionary = CollisionWorld.build(field, scenery)
	_check("same imported vegetation records keep collision identity", repeated.ok
		and repeated.world.identity == world.identity)

	var tree_hit: SceneryCollision.Event = _sweep(world, 100.0, 50.0, float(crown.down))
	_check("shade-tree imported crown remains a physical soft-contact proxy",
		tree_hit != null and tree_hit.obstacle_part == "crown" and not tree_hit.terminal)
	var bush_hit: SceneryCollision.Event = _sweep(world, 40.0, -20.0, float(bush.down))
	_check("bush imported bounds remain a physical soft-contact proxy",
		bush_hit != null and bush_hit.obstacle_part == "bush" and not bush_hit.terminal)
	print("vegetation collision proxies: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _sweep(world: Dictionary, north: float, east: float, down: float) -> SceneryCollision.Event:
	var previous := _state(north - 3.0, east, down, 20.0)
	var candidate := _state(north + 3.0, east, down, 20.0)
	return SceneryCollision.first_hit(previous, candidate, PackedFloat64Array([0.0, 0.0, 0.0]),
		world, 1, 1.0, PackedFloat64Array([1.0, 1.0, 1.0, 0.0, 0.0, 0.0]))


func _state(north: float, east: float, down: float, speed: float) -> PackedFloat64Array:
	return RB.make_state(PackedFloat64Array([north, east, down]), PackedFloat64Array([speed, 0.0, 0.0]),
		PackedFloat64Array([1.0, 0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]))


func _proxy(world: Dictionary, id: String) -> Dictionary:
	for proxy: Dictionary in world.get("proxies", []):
		if str(proxy.get("id", "")) == id:
			return proxy
	return {}


func _check(label: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if condition:
		print("ok ", label)
	else:
		failures += 1
		printerr("FAIL ", label, " ", detail)

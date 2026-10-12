extends SceneTree

const FieldLoader := preload("res://data/field_loader.gd")
const SceneryLoader := preload("res://scenery/scenery_loader.gd")
const FieldLights := preload("res://render/world/field_lights.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
const Scenery := preload("res://scenery/scenery.gd")
const Prefabs := preload("res://scenery/prefabs.gd")
const Models := preload("res://scenery/models.gd")

const ENVIRONMENT_KEYS: Array[String] = [
	"OPENRC_LANDSCAPE_UPGRADE",
	"OPENRC_SCENERY",
	"OPENRC_SCENERY_QUALITY",
	"OPENRC_SCENERY_FILE",
]

var failures := 0
var checks := 0
var saved_environment: Dictionary = {}


func _initialize() -> void:
	for key: String in ENVIRONMENT_KEYS:
		saved_environment[key] = OS.get_environment(key)
	var field_result: Dictionary = FieldLoader.load_from()
	_check("production field normalizes", field_result.ok)
	if field_result.ok:
		_run(field_result.field)
	_restore_environment()
	for key: String in ENVIRONMENT_KEYS:
		_check("environment restored: %s" % key, OS.get_environment(key) == str(saved_environment[key]))
	print("landscape collision setup: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _run(field: Dictionary) -> void:
	_test_landscape_disabled(field)
	_test_scenery_disabled(field)
	_test_quality_filter(field)


func _test_landscape_disabled(field: Dictionary) -> void:
	_set_options("off", "on", "high")
	var built: Dictionary = CollisionSetup.build(field)
	_check("landscape-upgrade off builds an empty collision world", built.ok
		and typeof(built.get("world")) == TYPE_DICTIONARY and built.world.is_empty())


func _test_scenery_disabled(field: Dictionary) -> void:
	_set_options("on", "off", "high")
	var built: Dictionary = CollisionSetup.build(field)
	_check("scenery-off collision world builds", built.ok)
	if not built.ok:
		return
	var tree_parts := 0
	var lamp_parts := 0
	var forbidden := false
	for proxy: Dictionary in built.world.proxies:
		if proxy.kind in ["tree_trunk", "tree_foliage"]:
			tree_parts += 1
		if proxy.kind == "lamp":
			lamp_parts += 1
		if proxy.kind in ["vehicle", "person", "building", "parked_aircraft"]:
			forbidden = true
	_check("scenery off retains both proxies for every field tree", tree_parts == 3360)
	_check("scenery off retains default field lamps", lamp_parts >= 3)
	_check("scenery off excludes cars, people, buildings, and parked aircraft", not forbidden)


func _test_quality_filter(field: Dictionary) -> void:
	var source_result: Dictionary = SceneryLoader.load_from(SceneryLoader.DEFAULT_PATH, field)
	var lights_result: Dictionary = FieldLights.load_from()
	_check("normalized scenery and default lamps load for quality comparison", source_result.ok and lights_result.ok)
	if not source_result.ok or not lights_result.ok:
		return
	var high_expected := _visible_filter(source_result.scenery, "high")
	var low_expected := _visible_filter(source_result.scenery, "low")
	_check("low retained visible placement IDs are a subset of high", _is_subset(low_expected.ids, high_expected.ids))
	_check("low quality drops ornament placements", low_expected.ids.size() < high_expected.ids.size())
	var expected_high: Dictionary = CollisionWorld.build(field, high_expected.scenery, lights_result.lights)
	var expected_low: Dictionary = CollisionWorld.build(field, low_expected.scenery, lights_result.lights)
	_check("independently filtered high and low collision inventories build", expected_high.ok and expected_low.ok)
	if not expected_high.ok or not expected_low.ok:
		return

	_set_options("on", "on", "high")
	var high_a: Dictionary = CollisionSetup.build(field)
	var high_b: Dictionary = CollisionSetup.build(field)
	_check("high-quality collision setup builds", high_a.ok and high_b.ok)
	if not high_a.ok or not high_b.ok:
		return
	_check("high proxy IDs match high visible placements", _proxy_ids(high_a.world) == _proxy_ids(expected_high.world))
	_check("repeated high build keeps identity stable", high_a.world.identity == high_b.world.identity)
	_check("repeated high build keeps proxy IDs stable", _proxy_ids(high_a.world) == _proxy_ids(high_b.world))

	_set_options("on", "on", "low")
	var low: Dictionary = CollisionSetup.build(field)
	_check("low-quality collision setup builds", low.ok)
	if not low.ok:
		return
	_check("low proxy IDs match low retained visible placements", _proxy_ids(low.world) == _proxy_ids(expected_low.world))
	_check("quality option changes collision-world identity", low.world.identity != high_a.world.identity)
	_check("quality option changes the retained collision inventory", _proxy_ids(low.world) != _proxy_ids(high_a.world))


func _visible_filter(source: Dictionary, quality: String) -> Dictionary:
	var filtered := source.duplicate(true)
	var retained_ids: Array[String] = []
	for group: Dictionary in filtered.groups:
		if str(group.type) != "instances":
			continue
		var kept: Array = []
		for source_index: int in group.placements.size():
			var placement: Dictionary = group.placements[source_index]
			var prefab := str(placement.get("prefab", group.get("prefab", "")))
			var spec: Dictionary = Prefabs.CATALOG[prefab] if Prefabs.CATALOG.has(prefab) else Models.CATALOG[prefab]
			if not Scenery.keep(str(spec.tier), int(placement.seed), quality):
				continue
			kept.append(placement)
			retained_ids.append("%s:%04d:%s:%d" % [group.id, source_index, prefab, int(placement.seed)])
		group.placements = kept
	retained_ids.sort()
	return {scenery = filtered, ids = retained_ids}


func _proxy_ids(world: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for proxy: Dictionary in world.get("proxies", []):
		ids.append(str(proxy.get("id", "")))
	ids.sort()
	return ids


func _is_subset(candidate: Array[String], complete: Array[String]) -> bool:
	var complete_set := {}
	for key: String in complete:
		complete_set[key] = true
	for key: String in candidate:
		if not complete_set.has(key):
			return false
	return true


func _set_options(landscape: String, scenery: String, quality: String) -> void:
	OS.set_environment("OPENRC_LANDSCAPE_UPGRADE", landscape)
	OS.set_environment("OPENRC_SCENERY", scenery)
	OS.set_environment("OPENRC_SCENERY_QUALITY", quality)
	OS.unset_environment("OPENRC_SCENERY_FILE")


func _restore_environment() -> void:
	for key: String in ENVIRONMENT_KEYS:
		var previous := str(saved_environment[key])
		if previous.is_empty():
			OS.unset_environment(key)
		else:
			OS.set_environment(key, previous)


func _check(label: String, condition: bool) -> void:
	checks += 1
	if condition:
		print("ok ", label)
	else:
		failures += 1
		printerr("FAIL ", label)

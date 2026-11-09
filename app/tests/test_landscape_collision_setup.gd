extends SceneTree

const FieldLoader := preload("res://data/field_loader.gd")
const SceneryLoader := preload("res://scenery/scenery_loader.gd")
const FieldLights := preload("res://render/world/field_lights.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
const Scenery := preload("res://scenery/scenery.gd")
const Prefabs := preload("res://scenery/prefabs.gd")
const Models := preload("res://scenery/models.gd")
const Track := preload("res://physics/ground_vehicle/airfield_track.gd")
const SceneDetail := preload("res://render/scene_detail.gd")

const ENVIRONMENT_KEYS: Array[String] = [
	"OPENRC_LANDSCAPE_UPGRADE",
	"OPENRC_SCENERY",
	"OPENRC_SCENERY_QUALITY",
	"OPENRC_SCENERY_FILE",
	"OPENRC_WORN_PATH_TURF",
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
	_set_options("off", "on", "low")
	var loaded: Dictionary = SceneryLoader.load_from(SceneryLoader.DEFAULT_PATH, field)
	var baseline: Dictionary = CollisionSetup.build(field)
	var expected: Dictionary = CollisionWorld.build(field, loaded.scenery) if loaded.ok else {ok = false}
	_check("landscape baseline retains the visible field and scenery inventory",
		baseline.ok and expected.ok and baseline.world == expected.world)
	if not baseline.ok: return
	var kinds := {}
	for proxy: Dictionary in baseline.world.proxies: kinds[str(proxy.kind)] = true
	_check("baseline retains field trees, barrier and scenery while omitting hidden daytime light fixtures",
		kinds.has("tree_trunk") and kinds.has("fence") and kinds.has("person")
		and kinds.has("building") and not kinds.has("lamp"))
	var track: Dictionary = Track.load_default()
	var with_track: Dictionary = CollisionSetup.build(field, track.track) if track.ok else {ok = false}
	var track_count := 0
	if with_track.ok:
		for proxy: Dictionary in with_track.world.proxies:
			if proxy.kind == "rc_track": track_count += 1
	_check("explicit circuit keeps its visible solid hazards in the landscape baseline",
		with_track.ok and track_count == 17 and with_track.world.identity != baseline.world.identity)
	_set_options("off", "off", "high")
	var bare: Dictionary = CollisionSetup.build(field)
	var bare_kinds := {}
	if bare.ok:
		for proxy: Dictionary in bare.world.proxies: bare_kinds[str(proxy.kind)] = true
	_check("scenery-off baseline retains field trees and barrier but removes scenery", bare.ok
		and bare_kinds.has("tree_trunk") and bare_kinds.has("fence")
		and not bare_kinds.has("person") and not bare_kinds.has("building"))


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
	_check("normalized scenery and default lamps load", source_result.ok and lights_result.ok)
	if not source_result.ok or not lights_result.ok:
		return
	# Check the visual-retention policy against the actual collision builder for every
	# catalog instance, including currently unused ornaments, so a future proxy cannot be hidden.
	var mismatches: Array[String] = []
	var catalog := Prefabs.CATALOG.keys()
	for id: Variant in Models.CATALOG.keys():
		if not catalog.has(id): catalog.append(id)
	for raw_id: Variant in catalog:
		var prefab := str(raw_id)
		var proxies: Array[Dictionary] = []
		var fixture := {groups = [{type = "instances", id = "policy", placements = [
			{prefab = prefab, north = 0.0, east = 0.0, heading = 0.0, seed = 123}]}]}
		CollisionWorld._add_scenery(proxies, fixture, [], {})
		if CollisionWorld.instance_has_collision(prefab) != not proxies.is_empty():
			mismatches.append(prefab)
	_check("render-retention policy matches actual catalog collision builders: %s" % [mismatches], mismatches.is_empty())
	var expected: Dictionary = CollisionWorld.build(field, source_result.scenery, lights_result.lights)
	_check("unfiltered physical scenario builds", expected.ok)
	if not expected.ok: return
	var expected_bench := false
	for proxy: Dictionary in expected.world.proxies:
		if proxy.part == "bench_seat": expected_bench = true
	_check("fixture includes a collidable bench", expected_bench)
	var adapters := [PackedStringArray(["llvmpipe", "Mesa"]),
		PackedStringArray(["Intel UHD Graphics 620", "Intel"]),
		PackedStringArray(["NVIDIA GeForce RTX 3090", "NVIDIA"])]
	for quality: String in ["low", "balanced", "high"]:
		_set_options("on", "on", quality)
		for adapter: PackedStringArray in adapters:
			SceneDetail.adapter_override = adapter
			SceneDetail.set_preference(SceneDetail.AUTO)
			var built: Dictionary = CollisionSetup.build(field)
			_check("%s with %s keeps the full world identity and proxies" % [quality, adapter[0]],
				built.ok and built.world == expected.world)
		var missing: Array[String] = []
		for group: Dictionary in source_result.scenery.groups:
			if str(group.type) != "instances": continue
			for placement: Dictionary in group.placements:
				var prefab := str(placement.prefab)
				var spec: Dictionary = Prefabs.CATALOG[prefab] if Prefabs.CATALOG.has(prefab) else Models.CATALOG[prefab]
				if CollisionWorld.instance_has_collision(prefab) and not Scenery.keep_instance(
						prefab, str(spec.tier), int(placement.seed), quality):
					missing.append(prefab)
		_check("%s retains every visible physical placement: %s" % [quality, missing], missing.is_empty())
	OS.unset_environment("OPENRC_SCENERY_QUALITY")
	for level: String in ["low", "medium", "high", "extreme", "auto"]:
		SceneDetail.set_preference(level)
		for adapter: PackedStringArray in adapters:
			SceneDetail.adapter_override = adapter
			var automatic_world: Dictionary = CollisionSetup.build(field)
			_check("detail %s on %s retains the full scenario" % [level, adapter[0]],
				automatic_world.ok and automatic_world.world == expected.world)
	SceneDetail.adapter_override = PackedStringArray()
	SceneDetail.set_preference("")
	_set_options("on", "on", "low")
	OS.set_environment("OPENRC_WORN_PATH_TURF", "off")
	var low_a: Dictionary = CollisionSetup.build(field)
	OS.set_environment("OPENRC_WORN_PATH_TURF", "on")
	var low_b: Dictionary = CollisionSetup.build(field)
	_check("worn-path turf leaves the full collision world unchanged", low_a.ok and low_b.ok and low_a.world == low_b.world)


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

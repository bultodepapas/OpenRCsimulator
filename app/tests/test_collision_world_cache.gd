# UI-34c / DT-11a: bounded collision construction reuse, full-byte parity and caller ownership.
extends SceneTree

const FieldLoader := preload("res://data/field_loader.gd")
const SceneryLoader := preload("res://scenery/scenery_loader.gd")
const FieldLights := preload("res://render/world/field_lights.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var field_result: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	_check("default field loads", bool(field_result.get("ok", false)), str(field_result.get("errors", [])))
	if not field_result.get("ok", false):
		_finish()
		return
	var field: Dictionary = field_result.field
	var scenery_result: Dictionary = SceneryLoader.load_from(SceneryLoader.DEFAULT_PATH, field)
	_check("default scenery loads", bool(scenery_result.get("ok", false)), str(scenery_result.get("errors", [])))
	if not scenery_result.get("ok", false):
		_finish()
		return
	var lights_result: Dictionary = FieldLights.load_from()
	_check("default field lights load", bool(lights_result.get("ok", false)), str(lights_result.get("errors", [])))
	if not lights_result.get("ok", false):
		_finish()
		return
	var scenery: Dictionary = scenery_result.scenery
	var lights: Dictionary = lights_result.lights
	_test_default_build(field, scenery, lights)
	_test_cache_keys_and_mutation(lights)
	_test_parked_snapshot_key()
	_test_failures_and_budget()
	_finish()


func _test_default_build(field: Dictionary, scenery: Dictionary, lights: Dictionary) -> void:
	CollisionWorld.clear_cache()
	var cold_start := Time.get_ticks_usec()
	var cold: Dictionary = CollisionWorld.build(field, scenery, lights)
	var cold_us: int = Time.get_ticks_usec() - cold_start
	_check("default collision world builds", bool(cold.get("ok", false)), str(cold.get("errors", [])))
	if not cold.get("ok", false):
		return
	var expected: PackedByteArray = var_to_bytes(cold.world)
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(expected)
	print("collision world bytes: %d, sha256=%s" % [expected.size(), digest.finish().hex_encode()])
	var reference_script: Script = _reference_script()
	if reference_script != null:
		var baseline: Variant = reference_script.call("build", field, scenery, lights)
		_check("reference collision world builds", typeof(baseline) == TYPE_DICTIONARY and baseline.get("ok", false))
		if typeof(baseline) == TYPE_DICTIONARY and baseline.get("ok", false):
			_check("cold world bytes match baseline", expected == var_to_bytes(baseline.world))
	var warm_start := Time.get_ticks_usec()
	var warm: Dictionary = CollisionWorld.build(field, scenery, lights)
	var warm_us: int = Time.get_ticks_usec() - warm_start
	_check("default cache hit returns exact world bytes", warm.get("ok", false)
		and var_to_bytes(warm.get("world", {})) == expected)
	var diagnostics: Dictionary = CollisionWorld.cache_diagnostics()
	_check("default build retained one bounded cache entry",
		int(diagnostics.get("entry_bytes", -1)) > 0
		and int(diagnostics.entry_bytes) <= int(diagnostics.budget_bytes)
		and int(diagnostics.hits) == 1 and int(diagnostics.misses) == 1)
	print("collision world cache: entry=%d/%d bytes, cold=%.3f ms, hit=%.3f ms" % [
		int(diagnostics.get("entry_bytes", -1)), int(diagnostics.get("budget_bytes", -1)),
		float(cold_us) / 1000.0, float(warm_us) / 1000.0])


func _test_cache_keys_and_mutation(lights: Dictionary) -> void:
	var field := _field_fixture()
	var scenery := _scenery_fixture()
	CollisionWorld.clear_cache()
	var cold: Dictionary = CollisionWorld.build(field, scenery, lights)
	_check("synthetic collision world has proxies and bins", cold.ok
		and not cold.world.proxies.is_empty() and not cold.world.bins.is_empty())
	if not cold.ok or cold.world.proxies.is_empty() or cold.world.bins.is_empty():
		return
	var expected: PackedByteArray = var_to_bytes(cold.world)
	var first_proxy: Dictionary = cold.world.proxies[0]
	first_proxy.north = float(first_proxy.north) + 1000.0
	cold.world.proxies[0] = first_proxy
	var first_bin: String = str(cold.world.bins.keys()[0])
	cold.world.bins[first_bin] = PackedInt64Array([999999])
	var restored: Dictionary = CollisionWorld.build(field, scenery, lights)
	_check("mutating a returned proxy and bin cannot poison the cache",
		restored.ok and var_to_bytes(restored.world) == expected)
	var first_hit_proxy: Dictionary = restored.world.proxies[0]
	first_hit_proxy.east = float(first_hit_proxy.east) - 1000.0
	restored.world.proxies[0] = first_hit_proxy
	var first_hit_bin: String = str(restored.world.bins.keys()[0])
	restored.world.bins[first_hit_bin] = PackedInt64Array([888888])
	var other_hit: Dictionary = CollisionWorld.build(field, scenery, lights)
	_check("mutating the first decoded hit also leaves the next hit pristine",
		other_hit.ok and var_to_bytes(other_hit.world) == expected)

	CollisionWorld.clear_cache()
	var original: Dictionary = CollisionWorld.build(field, scenery, lights)
	var misses_before: int = int(CollisionWorld.cache_diagnostics().misses)
	var changed_field: Dictionary = field.duplicate(true)
	changed_field.pilot.north = 1.0
	var changed_field_result: Dictionary = CollisionWorld.build(changed_field, scenery, lights)
	_check("same-id field changes miss the cache", changed_field_result.ok
		and int(CollisionWorld.cache_diagnostics().misses) == misses_before + 1)
	_check("pilot movement changes the field-tree collision geometry",
		original.ok and changed_field_result.ok
		and original.world.identity != changed_field_result.world.identity)
	var changed_scenery: Dictionary = scenery.duplicate(true)
	changed_scenery.groups[0].placements[0].east = 4.0
	var changed_scenery_result: Dictionary = CollisionWorld.build(field, changed_scenery, lights)
	_check("same-id scenery changes miss the cache", changed_scenery_result.ok
		and int(CollisionWorld.cache_diagnostics().misses) == misses_before + 2)
	var changed_lights: Dictionary = lights.duplicate(true)
	var installations: Array = changed_lights.get("installations", [])
	_check("normalized default light file has collision installations", not installations.is_empty())
	if not installations.is_empty():
		var changed_installation: Dictionary = installations[0].duplicate(true)
		changed_installation.height = float(changed_installation.get("height", 0.0)) + 0.25
		installations[0] = changed_installation
		changed_lights.installations = installations
	var changed_lights_result: Dictionary = CollisionWorld.build(field, scenery, changed_lights)
	_check("same-id light input changes miss the cache", changed_lights_result.ok
		and int(CollisionWorld.cache_diagnostics().misses) == misses_before + 3)
	_check("changing a lamp installation height changes collision geometry",
		changed_lights_result.ok and changed_lights_result.world.identity != changed_scenery_result.world.identity)
	_check("changed scenery retains a distinct geometry identity",
		original.ok and changed_scenery_result.ok
		and original.world.identity != changed_scenery_result.world.identity)

	CollisionWorld.clear_cache()
	var first_key_input: Dictionary = CollisionWorld.build(field, scenery, lights)
	var alternate_scenery: Dictionary = scenery.duplicate(true)
	alternate_scenery.groups[0].placements[0].north = 6.0
	var second_key_input: Dictionary = CollisionWorld.build(field, alternate_scenery, lights)
	var after_eviction: Dictionary = CollisionWorld.build(field, scenery, lights)
	var eviction_stats: Dictionary = CollisionWorld.cache_diagnostics()
	_check("one-entry cache evicts the previous key on replacement",
		first_key_input.ok and second_key_input.ok and after_eviction.ok
		and int(eviction_stats.misses) == 3 and int(eviction_stats.hits) == 0
		and int(eviction_stats.entry_bytes) <= int(eviction_stats.budget_bytes))


func _test_parked_snapshot_key() -> void:
	var field := _field_fixture()
	var lights := {"fixtures": []}
	var scenery := {"groups": [{"id": "fleet", "type": "fleet", "placements": [
		{"aircraft": "p51d-mustang-120", "configuration": "assembled", "north": 0.0, "east": 0.0,
			"heading": 0.0, "scale": 1.0, "elevation": 0.0},
		{"aircraft": "p51d-mustang-120", "configuration": "assembled", "north": 5.0, "east": 0.0,
			"heading": 0.0, "scale": 1.0, "elevation": 0.0},
	]}]}
	var snapshots: Dictionary = CollisionWorld._parked_aircraft_snapshots(scenery)
	var p51_snapshots: Dictionary = snapshots.get("p51d-mustang-120", {})
	_check("duplicate fleet placements share one frozen info snapshot",
		p51_snapshots.size() == 1 and p51_snapshots.has("assembled"))
	var first_key: PackedByteArray = CollisionWorld._make_build_cache_key(field, scenery, lights, snapshots)
	var changed_snapshots: Dictionary = snapshots.duplicate(true)
	var changed_by_configuration: Dictionary = changed_snapshots.get("p51d-mustang-120", {})
	var changed_info: Dictionary = changed_by_configuration.get("assembled", {}).duplicate(true)
	var changed_parts: Array = changed_info.get("collision_parts", []).duplicate(true)
	_check("parked-aircraft snapshot exposes collision parts", not changed_parts.is_empty())
	if not changed_parts.is_empty():
		var changed_part: Dictionary = changed_parts[0].duplicate(true)
		var changed_center: Array = changed_part.get("center", []).duplicate()
		if changed_center.size() == 3:
			changed_center[0] = float(changed_center[0]) + 0.5
			changed_part.center = changed_center
		else:
			var changed_size: Array = changed_part.get("size", []).duplicate()
			if changed_size.size() == 3:
				changed_size[0] = float(changed_size[0]) + 0.5
				changed_part.size = changed_size
		changed_parts[0] = changed_part
		changed_info.collision_parts = changed_parts
	changed_by_configuration["assembled"] = changed_info
	changed_snapshots["p51d-mustang-120"] = changed_by_configuration
	var changed_key: PackedByteArray = CollisionWorld._make_build_cache_key(field, scenery, lights, changed_snapshots)
	_check("parked metadata snapshots participate in exact cache keys",
		not first_key.is_empty() and not changed_key.is_empty() and first_key != changed_key)
	var original_world: Dictionary = CollisionWorld._build_uncached(field, scenery, lights, snapshots)
	var changed_world: Dictionary = CollisionWorld._build_uncached(field, scenery, lights, changed_snapshots)
	_check("changing parked collision-part geometry changes full world bytes",
		original_world.ok and changed_world.ok
		and var_to_bytes(original_world.world) != var_to_bytes(changed_world.world))


func _test_failures_and_budget() -> void:
	var field := _field_fixture()
	var scenery := _scenery_fixture()
	var lights := {"fixtures": []}
	CollisionWorld.clear_cache()
	var malformed: Dictionary = CollisionWorld.build({}, scenery, lights)
	_check("invalid outer shape is rejected before cache access",
		not malformed.get("ok", true) and int(CollisionWorld.cache_diagnostics().entry_bytes) == 0)
	var invalid_geometry: Dictionary = scenery.duplicate(true)
	invalid_geometry.groups[0].placements[0].north = NAN
	var failed_build: Dictionary = CollisionWorld.build(field, invalid_geometry, lights)
	_check("failed proxy validation does not publish a cache entry",
		not failed_build.get("ok", false) and int(CollisionWorld.cache_diagnostics().entry_bytes) == 0)
	var success_after_failure: Dictionary = CollisionWorld.build(field, scenery, lights)
	_check("successful build still caches after a failed candidate", success_after_failure.ok
		and int(CollisionWorld.cache_diagnostics().entry_bytes) > 0)

	CollisionWorld.clear_cache()
	var oversized: Dictionary = scenery.duplicate(true)
	oversized.cache_probe = "x".repeat(CollisionWorld.MAX_BUILD_CACHE_BYTES + 1)
	var oversized_result: Dictionary = CollisionWorld.build(field, oversized, lights)
	var oversized_stats: Dictionary = CollisionWorld.cache_diagnostics()
	_check("oversized exact input bypasses retention but still builds",
		oversized_result.ok and int(oversized_stats.entry_bytes) == 0
		and int(oversized_stats.bypasses) == 1)

	CollisionWorld.clear_cache()
	var recursive: Array = []
	recursive.append(recursive)
	var recursive_input: Dictionary = scenery.duplicate(true)
	recursive_input.cache_probe = recursive
	var recursive_result: Dictionary = CollisionWorld.build(field, recursive_input, lights)
	_check("recursive input falls back uncached without serialization", recursive_result.ok
		and int(CollisionWorld.cache_diagnostics().entry_bytes) == 0
		and int(CollisionWorld.cache_diagnostics().bypasses) == 1)
	recursive.clear()

	CollisionWorld.clear_cache()
	var object_input: Dictionary = scenery.duplicate(true)
	var marker := Node.new()
	object_input.object_probe = marker
	var object_result: Dictionary = CollisionWorld.build(field, object_input, lights)
	var object_stats: Dictionary = CollisionWorld.cache_diagnostics()
	_check("Object input falls back uncached", object_result.ok
		and int(object_stats.entry_bytes) == 0 and int(object_stats.bypasses) == 1)
	marker.free()

	CollisionWorld.clear_cache()
	var large_field := _field_fixture()
	var many_points: Array = []
	for index: int in 14000:
		many_points.append([0.0, float(index) * 0.1, 0.0])
	large_field.objects = [{"id": "cache_limit_trees", "type": "treeline", "positions": many_points}]
	var small_scenery := {"groups": []}
	var small_lights := {"fixtures": []}
	var large_result: Dictionary = CollisionWorld.build(large_field, small_scenery, small_lights)
	var large_key: PackedByteArray = CollisionWorld._make_build_cache_key(large_field, small_scenery,
		small_lights, {})
	var large_world_size: int = var_to_bytes(large_result.world).size() if large_result.ok else 0
	var large_stats: Dictionary = CollisionWorld.cache_diagnostics()
	_check("successful world above the combined byte budget is returned uncached",
		large_result.ok and large_key.size() + large_world_size > CollisionWorld.MAX_BUILD_CACHE_BYTES
		and int(large_stats.entry_bytes) == 0 and int(large_stats.bypasses) == 1)

	CollisionWorld.clear_cache()
	var thread := Thread.new()
	var start_error: Error = thread.start(Callable(self, "_build_off_main").bind(field, scenery, lights))
	_check("off-main build thread starts", start_error == OK)
	if start_error == OK:
		var off_main_result: Variant = thread.wait_to_finish()
		var off_main_stats: Dictionary = CollisionWorld.cache_diagnostics()
		_check("off-main build returns an exact successful world without touching shared cache",
			typeof(off_main_result) == TYPE_DICTIONARY and off_main_result.get("ok", false)
			and var_to_bytes(off_main_result.world) == var_to_bytes(
				CollisionWorld._build_uncached(field, scenery, lights, {}).world)
			and int(off_main_stats.entry_bytes) == 0 and int(off_main_stats.hits) == 0
			and int(off_main_stats.misses) == 0)


func _field_fixture() -> Dictionary:
	return {
		"id": "cache-probe",
		"pilot": {"north": 0.0, "east": 0.0, "down": 0.0},
		"objects": [{"id": "cache_probe_tree", "type": "treeline", "positions": [[10.0, 5.0, 0.0]]}],
		"flight_cues": [],
	}


func _scenery_fixture() -> Dictionary:
	return {"groups": [{
		"id": "pavilion",
		"type": "instances",
		"prefab": "pavilion",
		"placements": [{"north": 0.0, "east": 0.0, "heading": 0.0}],
	}]}


func _reference_script() -> Script:
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--reference="):
			continue
		var reference_path := argument.trim_prefix("--reference=")
		var loaded: Resource = load(reference_path)
		if loaded is Script:
			return loaded as Script
		_check("reference script loads: %s" % reference_path, false)
	return null


func _build_off_main(field: Dictionary, scenery: Dictionary, lights: Dictionary) -> Dictionary:
	return CollisionWorld.build(field, scenery, lights)


func _check(label: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if condition:
		return
	failures += 1
	printerr("FAIL: ", label, " ", detail)


func _finish() -> void:
	print("collision world cache: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

## DT-11a: the packaged default-lake CPU buffers match one fresh procedural build.
## Run: godot --headless --path app --script res://tests/test_lake_geometry_bake.gd
extends SceneTree

const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const GroundSurfaces := preload("res://physics/ground_surfaces.gd")
const LakeTerrain := preload("res://render/lake/lake_terrain.gd")
const GeometryStamp := preload("res://render/lake/generated_geometry_stamp.gd")

# Keep this list in sync with tools/ground/bake_lake_geometry.gd.
const SOURCES: Array[String] = [
	"res://render/lake/lake_terrain.gd",
	"res://physics/ground_terrain.gd",
	"res://physics/lake_surface.gd",
	"res://physics/math3d.gd",
]

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var field_result: Dictionary = FieldLoader.load_from()
	var lake_result: Dictionary = LakeLoader.load_from()
	var table_result: Dictionary = GroundSurfaces.load_table()
	_check("default field, lake and surface table load",
		bool(field_result.get("ok", false)) and bool(lake_result.get("ok", false))
		and bool(table_result.get("ok", false)))
	if not field_result.get("ok", false) or not lake_result.get("ok", false) \
			or not table_result.get("ok", false):
		_finish()
		return

	var surfaces_result: Dictionary = GroundSurfaces.build(table_result.table, field_result.field)
	_check("default field produces validated ground surfaces", bool(surfaces_result.get("ok", false)))
	if not surfaces_result.get("ok", false):
		_finish()
		return
	var lake: Dictionary = lake_result.lake
	var surfaces: PackedFloat64Array = surfaces_result.rects
	var basin_key: PackedByteArray = var_to_bytes([lake, surfaces])
	var water_key: PackedByteArray = var_to_bytes(lake)
	var baked: Resource = ResourceLoader.load(
		LakeTerrain.BAKED_PATH, "Resource", ResourceLoader.CACHE_MODE_IGNORE)
	_check("default lake geometry resource loads", baked != null)
	if baked == null:
		_finish()
		return

	_check("bake accepts the exact normalized default inputs",
		LakeTerrain.baked_matches(baked, basin_key, water_key))
	_test_source_stamp(baked)
	_test_procedural_parity(lake, surfaces, baked)
	_test_rejections_and_partial_reuse(lake, surfaces, baked, basin_key, water_key)
	_finish()


func _test_source_stamp(baked: Resource) -> void:
	var current_sources: Dictionary = {}
	var all_sources_exist := true
	for path: String in SOURCES:
		if not FileAccess.file_exists(path):
			all_sources_exist = false
			continue
		var source_text: String = FileAccess.get_file_as_string(path).replace("\r\n", "\n")
		current_sources[path] = source_text.sha256_text()
	var baked_sources: Variant = baked.get_meta("sources", null)
	var passed: bool = all_sources_exist and baked_sources is Dictionary \
		and baked_sources == current_sources \
		and LakeTerrain.geometry_digest([current_sources]) == GeometryStamp.SOURCE_SHA256 \
		and LakeTerrain.geometry_digest([baked_sources]) == GeometryStamp.SOURCE_SHA256
	_check("bake source hashes match LF-normalized sources and the generated stamp", passed)


func _test_procedural_parity(lake: Dictionary, surfaces: PackedFloat64Array, baked: Resource) -> void:
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	var bank: PackedFloat64Array = lake.bank_ne_m
	for index in range(0, bank.size(), 2):
		minimum.x = minf(minimum.x, bank[index])
		minimum.y = minf(minimum.y, bank[index + 1])
		maximum.x = maxf(maximum.x, bank[index])
		maximum.y = maxf(maximum.y, bank[index + 1])

	# Call each generator exactly once, bypassing both the baked-resource and warm CPU caches.
	var procedural_basin: Array = LakeTerrain._build_basin_arrays(lake, surfaces, minimum, maximum)
	var procedural_water: Array = LakeTerrain._build_water_arrays(lake)
	var baked_basin: Variant = baked.get_meta("basin_arrays", null)
	var baked_water: Variant = baked.get_meta("water_arrays", null)
	var basin_exact := baked_basin is Array \
		and var_to_bytes(procedural_basin) == var_to_bytes(baked_basin) \
		and LakeTerrain.geometry_digest(procedural_basin) == str(baked.get_meta("basin_sha256", ""))
	var water_exact := baked_water is Array \
		and var_to_bytes(procedural_water) == var_to_bytes(baked_water) \
		and LakeTerrain.geometry_digest(procedural_water) == str(baked.get_meta("water_sha256", ""))
	_check("one fresh procedural basin build matches every baked array exactly", basin_exact)
	_check("one fresh procedural water build matches every baked array exactly", water_exact)


func _test_rejections_and_partial_reuse(lake: Dictionary, surfaces: PackedFloat64Array,
		baked: Resource, basin_key: PackedByteArray, water_key: PackedByteArray) -> void:
	_check("missing resource is rejected", not LakeTerrain.baked_matches(null, basin_key, water_key))
	var missing_metadata_rejected := true
	for key: StringName in baked.get_meta_list():
		var missing := _copy_bake(baked)
		missing.remove_meta(key)
		missing_metadata_rejected = missing_metadata_rejected and not LakeTerrain.baked_matches(missing, basin_key, water_key)
	_check("every required metadata omission is rejected without engine errors", missing_metadata_rejected)

	var stale_format := _copy_bake(baked)
	stale_format.set_meta("format", "openrc-lake-geometry v0")
	_check("stale format is rejected", not LakeTerrain.baked_matches(stale_format, basin_key, water_key))

	var stale_engine := _copy_bake(baked)
	stale_engine.set_meta("engine_hex", int(baked.get_meta("engine_hex", 0)) + 1)
	_check("stale Godot engine version is rejected",
		not LakeTerrain.baked_matches(stale_engine, basin_key, water_key))

	var stale_precision := _copy_bake(baked)
	stale_precision.set_meta("double_precision", not bool(baked.get_meta("double_precision", false)))
	_check("stale precision mode is rejected",
		not LakeTerrain.baked_matches(stale_precision, basin_key, water_key))

	var stale_sources := _copy_bake(baked)
	var source_hashes: Dictionary = stale_sources.get_meta("sources", {}).duplicate(true)
	source_hashes[SOURCES[0]] = "stale-source-hash"
	stale_sources.set_meta("sources", source_hashes)
	_check("stale geometry source hashes are rejected",
		not LakeTerrain.baked_matches(stale_sources, basin_key, water_key))

	var corrupt_arrays := _copy_bake(baked)
	corrupt_arrays.set_meta("basin_arrays", [])
	_check("corrupt matched arrays are rejected",
		not LakeTerrain.baked_matches(corrupt_arrays, basin_key, water_key))

	var missing_arrays := _copy_bake(baked)
	missing_arrays.remove_meta("water_arrays")
	_check("missing matched arrays are rejected",
		not LakeTerrain.baked_matches(missing_arrays, basin_key, water_key))

	var wrong_digest := _copy_bake(baked)
	wrong_digest.set_meta("water_sha256", "stale-array-hash")
	_check("arrays with a stale content digest are rejected",
		not LakeTerrain.baked_matches(wrong_digest, basin_key, water_key))

	var changed_lake: Dictionary = lake.duplicate(true)
	var changed_shoreline: PackedFloat64Array = changed_lake.shoreline_ne_m
	changed_shoreline[1] += 0.75
	changed_lake["shoreline_ne_m"] = changed_shoreline
	var changed_basin_key: PackedByteArray = var_to_bytes([changed_lake, surfaces])
	var changed_water_key: PackedByteArray = var_to_bytes(changed_lake)
	_check("changed lake inputs invalidate both generated meshes",
		changed_basin_key != basin_key and changed_water_key != water_key
		and not LakeTerrain.baked_matches(baked, changed_basin_key, changed_water_key))

	var changed_surfaces := surfaces.duplicate()
	if changed_surfaces.size() > 5:
		changed_surfaces[5] = 7.5 if changed_surfaces[5] != 7.5 else 2.5
	var changed_ground_key: PackedByteArray = var_to_bytes([lake, changed_surfaces])
	_check("ground-only input changes may retain matching baked water",
		changed_ground_key != basin_key and var_to_bytes(lake) == water_key
		and LakeTerrain.baked_matches(baked, changed_ground_key, water_key))


func _copy_bake(source: Resource) -> Resource:
	var result := Resource.new()
	for key: StringName in source.get_meta_list():
		result.set_meta(key, source.get_meta(key))
	return result


func _finish() -> void:
	print("%d lake geometry bake checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(label: String, passed: bool) -> void:
	_checks += 1
	print(("ok   " if passed else "FAIL ") + label)
	if not passed:
		_failures += 1

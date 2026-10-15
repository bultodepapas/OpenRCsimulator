extends SceneTree

const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const GroundSurfaces := preload("res://physics/ground_surfaces.gd")
const LakeTerrain := preload("res://render/lake/lake_terrain.gd")
const GeometryStamp := preload("res://render/lake/generated_geometry_stamp.gd")

const SOURCES: Array[String] = [
	"res://render/lake/lake_terrain.gd",
	"res://physics/ground_terrain.gd",
	"res://physics/lake_surface.gd",
	"res://physics/math3d.gd",
]


func _initialize() -> void:
	var field_result: Dictionary = FieldLoader.load_from()
	var lake_result: Dictionary = LakeLoader.load_from()
	var table_result: Dictionary = GroundSurfaces.load_table()
	if not field_result.get("ok", false) or not lake_result.get("ok", false) \
			or not table_result.get("ok", false):
		printerr("LAKE_BAKE_DIAG_ERROR definitions failed to load")
		quit(2)
		return
	var surface_result: Dictionary = GroundSurfaces.build(table_result.table, field_result.field)
	if not surface_result.get("ok", false):
		printerr("LAKE_BAKE_DIAG_ERROR ground surfaces failed to build")
		quit(2)
		return

	var lake: Dictionary = lake_result.lake
	var surfaces: PackedFloat64Array = surface_result.rects
	var basin_key: PackedByteArray = var_to_bytes([lake, surfaces])
	var water_key: PackedByteArray = var_to_bytes(lake)
	var baked: Resource = ResourceLoader.load(
		LakeTerrain.BAKED_PATH, "Resource", ResourceLoader.CACHE_MODE_IGNORE)
	if baked == null:
		printerr("LAKE_BAKE_DIAG_ERROR baked resource failed to load")
		quit(2)
		return

	var current_sources: Dictionary = {}
	for path: String in SOURCES:
		var source_text: String = FileAccess.get_file_as_string(path).replace("\r\n", "\n")
		current_sources[path] = source_text.sha256_text()
	var baked_sources: Variant = baked.get_meta("sources", null)
	var source_rows: Array[Dictionary] = []
	if baked_sources is Dictionary:
		for path: String in SOURCES:
			source_rows.append({"path": path, "baked_sha256": baked_sources.get(path, ""),
				"current_lf_sha256": current_sources.get(path, ""),
				"matches": baked_sources.get(path, "") == current_sources.get(path, "")})

	var corrupt_basin := _copy_bake(baked)
	corrupt_basin.set_meta("basin_arrays", [])
	var corrupt_water := _copy_bake(baked)
	corrupt_water.set_meta("water_arrays", [])
	var report := {
		"current_sources": current_sources,
		"baked_sources": baked_sources,
		"per_source_comparison": source_rows,
		"current_source_digest": LakeTerrain.geometry_digest([current_sources]),
		"baked_source_digest": LakeTerrain.geometry_digest([baked_sources]) if baked_sources is Dictionary else "invalid",
		"generated_stamp_sha256": GeometryStamp.SOURCE_SHA256,
		"current_digest_matches_stamp": LakeTerrain.geometry_digest([current_sources]) == GeometryStamp.SOURCE_SHA256,
		"baked_digest_matches_stamp": baked_sources is Dictionary \
			and LakeTerrain.geometry_digest([baked_sources]) == GeometryStamp.SOURCE_SHA256,
		"basin_input_key_matches": baked.get_meta("basin_key", PackedByteArray()) == basin_key,
		"water_input_key_matches": baked.get_meta("water_key", PackedByteArray()) == water_key,
		"baked_matches_unmodified": LakeTerrain.baked_matches(baked, basin_key, water_key),
		"baked_matches_with_empty_basin_arrays": LakeTerrain.baked_matches(corrupt_basin, basin_key, water_key),
		"baked_matches_with_empty_water_arrays": LakeTerrain.baked_matches(corrupt_water, basin_key, water_key),
		"ground_surface_rects_length": surfaces.size(),
	}
	print("LAKE_BAKE_DIAGNOSTIC " + JSON.stringify(report))
	quit(0)


func _copy_bake(source: Resource) -> Resource:
	var result := Resource.new()
	for key: StringName in source.get_meta_list():
		result.set_meta(key, source.get_meta(key))
	return result

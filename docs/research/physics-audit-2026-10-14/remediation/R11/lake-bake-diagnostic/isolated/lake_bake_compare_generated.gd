extends SceneTree
const LakeTerrain := preload("res://render/lake/lake_terrain.gd")

func _initialize() -> void:
	var old: Resource = ResourceLoader.load("res://assets/landscape/lake/before_default_geometry.res", "Resource", ResourceLoader.CACHE_MODE_IGNORE)
	var fresh: Resource = ResourceLoader.load("res://assets/landscape/lake/default_geometry.res", "Resource", ResourceLoader.CACHE_MODE_IGNORE)
	if old == null or fresh == null:
		printerr("COMPARE_ERROR load old/new failed")
		quit(2)
		return
	var old_basin: Variant = old.get_meta("basin_arrays", null)
	var new_basin: Variant = fresh.get_meta("basin_arrays", null)
	var old_water: Variant = old.get_meta("water_arrays", null)
	var new_water: Variant = fresh.get_meta("water_arrays", null)
	var report := {
		"old_basin_key_sha256": LakeTerrain.geometry_digest(old.get_meta("basin_key", PackedByteArray())),
		"new_basin_key_sha256": LakeTerrain.geometry_digest(fresh.get_meta("basin_key", PackedByteArray())),
		"basin_keys_equal": var_to_bytes(old.get_meta("basin_key")) == var_to_bytes(fresh.get_meta("basin_key")),
		"water_keys_equal": var_to_bytes(old.get_meta("water_key")) == var_to_bytes(fresh.get_meta("water_key")),
		"basin_array_equal": var_to_bytes(old_basin) == var_to_bytes(new_basin),
		"water_array_equal": var_to_bytes(old_water) == var_to_bytes(new_water),
		"old_basin_sha256": old.get_meta("basin_sha256", ""),
		"new_basin_sha256": fresh.get_meta("basin_sha256", ""),
		"old_water_sha256": old.get_meta("water_sha256", ""),
		"new_water_sha256": fresh.get_meta("water_sha256", ""),
		"fresh_sources": fresh.get_meta("sources", {}),
	}
	print("LAKE_BAKE_REGEN_COMPARE " + JSON.stringify(report))
	quit(0)

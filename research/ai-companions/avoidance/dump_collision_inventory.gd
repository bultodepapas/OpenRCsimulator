extends SceneTree

const FieldLoader := preload("res://data/field_loader.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")

func _initialize() -> void:
	var output_path := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output_path = arg.get_slice("=", 1)
	if output_path.is_empty():
		push_error("--out=<absolute path> is required")
		quit(2)
		return
	var field_result: Dictionary = FieldLoader.load_from()
	if not field_result.get("ok", false):
		push_error("field load failed: %s" % str(field_result.get("errors", [])))
		quit(2)
		return
	var collision_result: Dictionary = CollisionSetup.build(field_result.field)
	if not collision_result.get("ok", false):
		push_error("collision inventory build failed: %s" % str(collision_result.get("errors", [])))
		quit(2)
		return
	var world: Dictionary = collision_result.world
	var output := {
		"format": "afc-collision-inventory-dump-v1",
		"identity": str(world.get("identity", "")),
		"proxy_count": world.get("proxies", []).size(),
		"cell_size_m": world.get("cell_size_m", 0.0),
		"proxies": world.get("proxies", []),
	}
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("cannot open output %s (error %d)" % [output_path, FileAccess.get_open_error()])
		quit(2)
		return
	file.store_string(JSON.stringify(output, "\t") + "\n")
	file.close()
	print("AFC_COLLISION_INVENTORY ", JSON.stringify({
		"identity": output.identity,
		"proxy_count": output.proxy_count,
		"output": output_path,
	}))
	quit(0)

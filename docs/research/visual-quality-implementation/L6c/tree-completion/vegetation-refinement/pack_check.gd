extends SceneTree

func _initialize() -> void:
	var errors: Array[String] = []
	var paths := ["res://assets/landscape/vegetation/woodland/LICENSE.txt", "res://assets/landscape/vegetation/woodland/source.json",
		"res://assets/landscape/vegetation/impostors/fern_1_4view.json", "res://assets/landscape/vegetation/impostors/grass_common_tall_4view.json"]
	for path in paths:
		if not FileAccess.file_exists(path): errors.append(path)
	for path in ["res://scenery/woodland_cards.gdshader", "res://scenery/woodland_floor.gdshader",
		"res://assets/landscape/vegetation/impostors/fern_1_4view.png", "res://assets/landscape/vegetation/impostors/grass_common_tall_4view.png",
		"res://assets/landscape/vegetation/woodland/forest_leaves_02_diffuse_1k.jpg"]:
		if load(path) == null: errors.append(path)
	var clock: Script = load("res://render/shader_clock.gd")
	clock.register()
	var loader: Script = load("res://data/field_loader.gd")
	var scenery_loader: Script = load("res://scenery/scenery_loader.gd")
	var lake_loader: Script = load("res://data/lake_loader.gd")
	var woodland: Script = load("res://scenery/woodland_edge_habitat.gd")
	var field: Dictionary = loader.load_from().field
	var built: Node3D = woodland.build(field, scenery_loader.load_from(scenery_loader.DEFAULT_PATH, field).scenery, "high", lake_loader.load_from().lake)
	if built.get_meta("triangles") != 1988 or built.get_meta("batches") != 6: errors.append("exported habitat budget")
	built.free()
	print("PACK CHECK: ", errors)
	quit(0 if errors.is_empty() else 1)

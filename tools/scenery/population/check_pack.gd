## Run from an empty project: godot --headless --path EMPTY --script THIS -- PACK CREDIT_SHA256
extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or not ProjectSettings.load_resource_pack(args[0]):
		printerr("FAIL population pack load")
		quit(1)
		return
	var ok := FileAccess.get_sha256("res://assets/landscape/UPGRADE_CREDITS.md") == args[1]
	for asset: String in ["sedan", "hatch", "crossover", "standing", "sitting", "pilot"]:
		var scene := load("res://assets/scenery/population/%s.glb" % asset) as PackedScene
		ok = ok and scene != null
		if scene != null:
			var node := scene.instantiate()
			ok = ok and node != null
			node.free()
		print("pack asset ", asset, ": ", scene != null)
	for path: String in ["scenery/population.gd", "scenery/population_person.gdshader", "scenery/support_surfaces.gd"]:
		ok = ok and ResourceLoader.exists("res://" + path)
	print("Population resources load and exported credits match source: ", ok)
	quit(0 if ok else 1)

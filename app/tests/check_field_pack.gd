# L5 export smoke. Run from an EMPTY project root so a missing pack resource cannot fall back to the source tree.
extends SceneTree


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2 or not ProjectSettings.load_resource_pack(args[0], true):
		printerr("Could not mount field pack: ", args)
		quit(1)
		return
	var path: String = "res://data/fields/default.json"
	if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != args[1]:
		printerr("Pack has missing or different default field: ", args[0])
		quit(1)
		return
	var loader: Script = load("res://data/field_loader.gd")
	if loader == null:
		printerr("Pack has no field loader")
		quit(1)
		return
	var result: Dictionary = loader.load_from()
	if not result.ok or result.field.id != "default":
		printerr("Pack field rejected: ", result.errors)
		quit(1)
		return
	print("Pack field validated, SHA-256 ", args[1])
	quit(0)

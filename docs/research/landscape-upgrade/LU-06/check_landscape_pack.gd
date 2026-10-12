extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or not ProjectSettings.load_resource_pack(args[0]):
		printerr("FAIL pack load")
		quit(1)
		return
	var credit := "res://assets/landscape/UPGRADE_CREDITS.md"
	var ok := FileAccess.get_sha256(credit) == args[1]
	ok = ok and FileAccess.get_file_as_string(credit).contains("Copyright (c) 2026 OpenRCsimulator contributors")
	for id: String in ["stik", "extra", "p51", "avanti"]:
		ok = ok and FileAccess.file_exists("res://data/scenery/models/fleet_%s.json" % id)
	for path: String in ["res://render/landscape_upgrade/ridges.gd", "res://render/landscape_upgrade/sun_glare.gdshader",
		"res://render/landscape_upgrade/airfield_lighting.gd", "res://scenery/people.gd", "res://sim/scenery_collision.gd"]:
		ok = ok and ResourceLoader.exists(path)
	print("Pack credits match source SHA-256; all four fleet files and landscape resources present: ", ok)
	quit(0 if ok else 1)

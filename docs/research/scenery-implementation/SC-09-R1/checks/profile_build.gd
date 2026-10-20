extends SceneTree
const FieldLoader = preload("res://data/field_loader.gd")
const Loader = preload("res://scenery/scenery_loader.gd")
const Scenery = preload("res://scenery/scenery.gd")
const ShaderClock = preload("res://render/shader_clock.gd")
func _initialize() -> void:
	ShaderClock.register()
	var field: Dictionary = FieldLoader.load_from().field
	var scenery: Dictionary = Loader.load_from(Loader.DEFAULT_PATH, field).scenery
	var with_fleet := not OS.get_cmdline_user_args().has("--no-fleet")
	if not with_fleet:
		scenery.groups = scenery.groups.filter(func(group: Dictionary) -> bool: return group.type != "fleet")
	var node := Scenery.build(field, scenery, {audio = false, birds = false, theme = "", quality = "high"})
	print(JSON.stringify({"with_fleet": with_fleet, "stats": node.get_meta("stats")}, "  "))
	node.free()
	quit(0)

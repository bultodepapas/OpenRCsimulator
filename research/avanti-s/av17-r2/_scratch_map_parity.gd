extends SceneTree
const Data := preload("res://physics/aircraft_data.gd")
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		printerr("expected one raw input path")
		quit(2)
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if typeof(raw) != TYPE_DICTIONARY:
		printerr("invalid raw JSON")
		quit(2)
		return
	var result: Dictionary = Data.validate_and_derive(raw)
	if not result.ok:
		printerr("loader error: ", result.errors)
		quit(1)
		return
	var env: Dictionary = result.model.envelope
	var offset := 0.0
	for value: float in env.strip_cl0:
		offset += value / float(env.strip_cl0.size())
	print("AV17_R2_MAP ", JSON.stringify({"section_slope":env.strip_slope,"map":env.induced_map,"strip_cl0":env.strip_cl0,"offset":offset,"station_ys":env.station_ys}))
	quit(0)

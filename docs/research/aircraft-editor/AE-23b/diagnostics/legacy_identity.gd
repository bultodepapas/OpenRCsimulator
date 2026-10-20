extends SceneTree
func _initialize() -> void:
	var compiler := preload("res://workshop/compiler.gd")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft/jensen_ugly_stik_60.json"))
	var rows := []
	for scale: float in [0.35, 0.5, 1.0, 1.5, 2.0, 2.25]:
		for policy: String in ["constant_wing_loading", "geometric"]:
			var recipe := {"scale":scale,"mass_policy":policy}
			var result := compiler.compile(raw, recipe)
			rows.append({"recipe":recipe,"ok":result.ok,"version":compiler.version_for_recipe(recipe),"raw":JSON.stringify(result.raw,"",true,true).sha256_text(),"data":var_to_bytes(result.data).hex_encode().sha256_text()})
	var output := FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
	output.store_string(JSON.stringify(rows,"\t",true,true))
	output.close()
	quit()

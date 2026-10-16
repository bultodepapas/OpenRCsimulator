## Build a local inspection fixture from unmodified fresh imported resources.
## Raw GLB remains present for byte admission. This is not a production export.
extends SceneTree


func _initialize() -> void:
	var destination := ""
	var omit := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			destination = arg.trim_prefix("--out=")
		if arg.begins_with("--omit="):
			omit = arg.trim_prefix("--omit=")
	if destination.is_empty():
		quit(1)
		return
	var asset_path := "res://assets/aircraft/hx-700/articulated/hx-700.glb"
	var files := {
		"res://project.godot": "res://project.godot",
		"res://aircraft/hx700_articulated_model.gd": "res://aircraft/hx700_articulated_model.gd",
		"res://smoke.gd": "res://smoke.gd",
		"res://.godot/uid_cache.bin": "res://.godot/uid_cache.bin",
		asset_path: asset_path,
		"res://assets/aircraft/hx-700/articulated/construction.json": "res://assets/aircraft/hx-700/articulated/construction.json",
	}
	var packer := PCKPacker.new()
	# Optional HELI-26a mechanical inspection fixture, still separate from flight exports.
	for path: String in ["res://render/rotor/hx700_motion_equations.gd", "res://render/rotor/hx700_mechanism.gd",
			"res://render/rotor/hx700_mechanics_view.gd", "res://tools/inspect_hx700.gd", "res://tests/test_heli_mechanism.gd",
			"res://tests/test_heli_mechanics_view.gd"]:
		if FileAccess.file_exists(path):
			files[path] = path
	if packer.pck_start(destination) != OK:
		quit(1)
		return
	for target: String in files:
		if (omit == "profile" and target.ends_with("construction.json")) or (omit == "raw-glb" and target == asset_path):
			continue
		if packer.add_file(target, ProjectSettings.globalize_path(files[target])) != OK:
			printerr("Unable to add package dependency: ", target)
			quit(1)
			return
	# Preserve the engine's original scene/texture graph and import metadata.
	# Re-saving a PackedScene with BUNDLE_RESOURCES can lose texture references.
	var asset_directory := asset_path.get_base_dir()
	var import_files := DirAccess.get_files_at(asset_directory)
	var remap_count := 0
	for filename: String in import_files:
		if not filename.ends_with(".import"):
			continue
		var config := ConfigFile.new()
		if config.load(asset_directory.path_join(filename)) != OK:
			quit(1)
			return
		var imported_path: String = config.get_value("remap", "path", "")
		if imported_path.is_empty():
			quit(1)
			return
		var metadata_path := asset_directory.path_join(filename)
		if packer.add_file(metadata_path, ProjectSettings.globalize_path(metadata_path)) != OK:
			quit(1)
			return
		remap_count += 1
	if remap_count != 4:
		printerr("Expected scene and three texture remaps; got ", remap_count)
		quit(1)
		return
	var textures := DirAccess.get_files_at("res://.godot/imported")
	textures.sort()
	var texture_count := 0
	for filename: String in textures:
		if not filename.ends_with(".ctex") and not filename.ends_with(".scn"):
			continue
		if filename.ends_with(".ctex"):
			texture_count += 1
			if omit == "texture" and texture_count == 1:
				continue
		var texture_path := "res://.godot/imported/" + filename
		if packer.add_file(texture_path, ProjectSettings.globalize_path(texture_path)) != OK:
			quit(1)
			return
	if texture_count != 3:
		printerr("Expected three fresh imported texture payloads; got ", texture_count)
		quit(1)
		return
	if packer.flush() != OK:
		quit(1)
		return
	print("HELI-25c local fixture pack: ", destination, " omitted=", omit)
	quit(0)

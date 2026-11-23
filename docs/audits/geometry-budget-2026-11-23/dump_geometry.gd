## Read-only measurement of a hydrated app using its own scenery, meshes and budget counter.
extends SceneTree

const Furniture = preload("res://scenery/club_furniture.gd")
const Kit = preload("res://scenery/mesh_kit.gd")
const Scenery = preload("res://scenery/scenery.gd")
const Loader = preload("res://scenery/scenery_loader.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const Budget = preload("res://tests/scene_source_budget.gd")
const ShaderClock = preload("res://render/shader_clock.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or not DirAccess.dir_exists_absolute(args[0]):
		printerr("Pass one existing absolute output directory after --")
		quit(1)
		return
	var output := args[0]
	for prefab: String in ["picnic", "bench"]:
		var kit := Kit.new()
		if prefab == "picnic":
			Furniture.picnic(kit)
		else:
			Furniture.bench(kit)
		var mesh := kit.to_mesh(null)
		var arrays := {"verts": kit.verts, "norms": kit.norms, "cols": kit.cols,
			"rendercols": mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]}
		for attribute: String in arrays:
			var file := FileAccess.open(output.path_join(prefab + "-" + attribute + ".bin"), FileAccess.WRITE)
			if file == null:
				quit(1)
				return
			file.store_buffer(arrays[attribute].to_byte_array())
	ShaderClock.register()
	var field: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH).field
	var scenery: Dictionary = Loader.load_from(Loader.DEFAULT_PATH, field).scenery
	var world := Scenery.build(field, scenery, {audio = false, birds = false, theme = "", quality = "high"})
	var result := {subsystems = Budget.counts(world), nodes = {}, damage_groups = {}}
	for child: Node in world.get_children():
		var key := Budget.subsystem(str(child.name))
		if key in ["other", "cells"]:
			result.nodes[str(child.name)] = Budget._triangles(child)
		if key == "cells":
			for item: Dictionary in child.get_meta("damage_ranges", []):
				var group := str(item.id).get_slice(":", 1)
				var triangles := (int(item.end) - int(item.first)) / 3
				result.damage_groups[group] = result.damage_groups.get(group, 0) + triangles
	var summary := FileAccess.open(output.path_join("scene.json"), FileAccess.WRITE)
	if summary == null:
		world.free()
		quit(1)
		return
	summary.store_string(JSON.stringify(result, "\t") + "\n")
	world.free()
	print("Geometry evidence written")
	quit(0)

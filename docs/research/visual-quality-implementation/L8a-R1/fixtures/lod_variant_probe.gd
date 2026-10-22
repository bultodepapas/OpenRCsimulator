## L8a-R1 fixture: the 3D front trees per bark/foliage LOD error (256 m cells): captures in the production world,
## then true drawn cost (every instance) with only the trees drawn. Args: --out=<dir> --views=<json>
extends SceneTree
const FieldLoader = preload("res://data/field_loader.gd")
const World = preload("res://render/world/world.gd")
const ShaderClock = preload("res://render/shader_clock.gd")
const Frames = preload("res://render/frames.gd")
const Treeline = preload("res://render/treeline.gd")
const ImportedVegetation = preload("res://scenery/imported_vegetation.gd")
# [bark px, foliage px]
const VARIANTS := [[1.0, 1.0], [8.0, 1.0], [8.0, 2.0], [8.0, 4.0]]
var _args := {}


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		_args[pair[0]] = pair[1] if pair.size() > 1 else "on"
	_run.call_deferred()


func _measure() -> int:
	for _i in 3:
		await RenderingServer.frame_post_draw
	return int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))


func _variant(field: Dictionary, bark_px: float, foliage_px: float) -> Node3D:
	var object_data: Dictionary = field.objects[0]
	var front := Treeline.front_azimuth_deg(field)
	var result := Node3D.new()
	result.position = Frames.ned_to_render([field.pilot.north, field.pilot.east, field.pilot.down])
	var batches := {}
	for index: int in object_data.positions.size():
		var point: Array = object_data.positions[index]
		var asset_id := Treeline.detail_asset(point[0], point[1], front)
		if asset_id.is_empty():
			continue
		var tree: Dictionary = Treeline.identity(point[0], point[1])
		var heading := rad_to_deg(float(tree.yaw))
		var placement := Transform3D(Basis(Vector3.UP, -deg_to_rad(heading)), Frames.ned_to_render(point))
		ImportedVegetation.queue(batches, asset_id, ImportedVegetation.fit_to_height(asset_id, float(tree.height), placement), index)
	var trees := ImportedVegetation.build(batches, false, {"tree_wind": true, "tree_cell_size_m": 256})
	var scaled := {}
	for child: MultiMeshInstance3D in trees.get_children():
		child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mesh := child.multimesh.mesh as ArrayMesh
		if scaled.has(mesh.get_instance_id()):
			continue
		scaled[mesh.get_instance_id()] = true
		var surfaces: Array = mesh.get("_surfaces")
		for s in surfaces.size():
			var material := mesh.surface_get_material(s) as ShaderMaterial
			var px := foliage_px if material != null and bool(material.get_shader_parameter("use_alpha_scissor")) else bark_px
			var lods: Array = surfaces[s].get("lods", [])
			for pair in range(0, lods.size(), 2):
				lods[pair] = float(lods[pair]) / px
			surfaces[s]["lods"] = lods
		mesh.set("_surfaces", surfaces)
	result.add_child(trees)
	return result


func _true_cost(node: Node3D) -> int:
	var complete := await _measure()
	var total := 0
	for batch: MultiMeshInstance3D in node.find_children("*", "MultiMeshInstance3D", true, false):
		batch.visible = false
		var counted: int = complete - await _measure()
		batch.visible = true
		if counted <= 0:
			continue
		var mm := batch.multimesh
		mm.visible_instance_count = 1
		var one: int = counted - (complete - await _measure())
		mm.visible_instance_count = -1
		total += mm.instance_count * one
	return total


func _run() -> void:
	var out := str(_args.out)
	DirAccess.make_dir_recursive_absolute(out)
	OS.set_environment("OPENRC_SCENERY_AUDIO", "off")
	OS.set_environment("OPENRC_SCENERY_BIRDS", "off")
	ShaderClock.register()
	ShaderClock.update(1.5)
	var world := Node3D.new()
	root.add_child(world)
	var field: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH).field
	var built: Dictionary = World.build(world, field)
	var field_node: Node3D = built.field
	field_node.get_node("treelineDetail").visible = false
	var camera := Camera3D.new()
	camera.near = 0.1
	camera.far = 21000.0
	world.add_child(camera)
	camera.current = true
	var variants := []
	for spec: Array in VARIANTS:
		var v := _variant(field, spec[0], spec[1])
		v.visible = false
		world.add_child(v)
		variants.append(v)
	camera.look_at_from_position(Vector3(0, 30, 0), Vector3(50, 0, 50), Vector3.UP)
	for _index in 120:
		await RenderingServer.frame_post_draw
	var views: Array = JSON.parse_string(FileAccess.get_file_as_string(str(_args.views)))
	for view: Dictionary in views:
		camera.fov = float(view.fov)
		camera.look_at_from_position(Frames.ned_to_render(view.eye_ned), Frames.ned_to_render(view.at_ned), Vector3.UP)
		for index in variants.size():
			variants[index].visible = true
			for _i in 4:
				await RenderingServer.frame_post_draw
			root.get_viewport().get_texture().get_image().save_png(out.path_join("%s_b%d_f%d.png" % [view.id, VARIANTS[index][0], VARIANTS[index][1]]))
			variants[index].visible = false
	field_node.visible = false
	for child in world.get_children():
		if child is Node3D and child != camera and not variants.has(child):
			(child as Node3D).visible = false
	for view: Dictionary in views:
		camera.fov = float(view.fov)
		camera.look_at_from_position(Frames.ned_to_render(view.eye_ned), Frames.ned_to_render(view.at_ned), Vector3.UP)
		var line := "%-18s" % view.id
		for index in variants.size():
			variants[index].visible = true
			line += "  b%d/f%d: %7d" % [VARIANTS[index][0], VARIANTS[index][1], await _true_cost(variants[index])]
			variants[index].visible = false
		print("TRUE ", line)
	quit(0)

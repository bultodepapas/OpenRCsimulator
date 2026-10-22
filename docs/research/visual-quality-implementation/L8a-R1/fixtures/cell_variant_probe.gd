## L8a-R1 fixture: true drawn cost (every instance) of the 3D front trees per cell size and bark LOD
## error, with only the trees drawn. Views: five postcards plus VIEWS_JSON=<views.json>.
extends SceneTree
const FieldLoader = preload("res://data/field_loader.gd")
const World = preload("res://render/world/world.gd")
const ShaderClock = preload("res://render/shader_clock.gd")
const Frames = preload("res://render/frames.gd")
const Postcards = preload("res://scenery/postcards.gd")
const Treeline = preload("res://render/treeline.gd")
const ImportedVegetation = preload("res://scenery/imported_vegetation.gd")
const POSTCARDS := ["runway_zoom_300", "runway_zoom_100", "pilot_north", "aerial_overview", "top_140"]
const VARIANTS := [[0, 1.0], [128, 1.0], [256, 1.0], [0, 4.0], [128, 4.0], [256, 4.0], [128, 8.0], [256, 8.0]]


func _initialize() -> void:
	_run.call_deferred()


func _measure() -> Dictionary:
	for _i in 3:
		await RenderingServer.frame_post_draw
	return {p = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		d = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))}


func _variant(field: Dictionary, cell: int, bark_error_px: float) -> Node3D:
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
	var trees := ImportedVegetation.build(batches, false, {"tree_wind": true, "tree_cell_size_m": cell})
	var scaled := {}
	for child: MultiMeshInstance3D in trees.get_children():
		child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mesh := child.multimesh.mesh as ArrayMesh
		if bark_error_px != 1.0 and not scaled.has(mesh.get_instance_id()):
			scaled[mesh.get_instance_id()] = true
			var surfaces: Array = mesh.get("_surfaces")
			for s in surfaces.size():
				var material := mesh.surface_get_material(s) as ShaderMaterial
				if material != null and bool(material.get_shader_parameter("use_alpha_scissor")):
					continue
				var lods: Array = surfaces[s].lods
				for pair in range(0, lods.size(), 2):
					lods[pair] = float(lods[pair]) / bark_error_px
				surfaces[s]["lods"] = lods
			mesh.set("_surfaces", surfaces)
	result.add_child(trees)
	return result


func _true_cost(node: Node3D, complete: int) -> int:
	var total := 0
	for batch: MultiMeshInstance3D in node.find_children("*", "MultiMeshInstance3D", true, false):
		batch.visible = false
		var counted: int = complete - (await _measure()).p
		batch.visible = true
		if counted <= 0:
			continue
		var mm := batch.multimesh
		var previous := mm.visible_instance_count
		mm.visible_instance_count = 1
		var one: int = counted - (complete - (await _measure()).p)
		mm.visible_instance_count = previous
		total += mm.instance_count * one
	return total


func _run() -> void:
	OS.set_environment("OPENRC_SCENERY_AUDIO", "off")
	ShaderClock.register()
	ShaderClock.update(1.5)
	var world := Node3D.new()
	root.add_child(world)
	var field: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH).field
	# Counts are per object and LOD depends only on the camera, so only the variants are drawn.
	var field_node := Node3D.new()
	world.add_child(field_node)
	var camera := Camera3D.new()
	camera.near = 0.1
	camera.far = 21000.0
	world.add_child(camera)
	camera.current = true
	var variants := []
	for spec: Array in VARIANTS:
		var v := _variant(field, spec[0], spec[1])
		v.visible = false
		field_node.add_child(v)
		variants.append(v)
	var views := []
	for name: String in POSTCARDS:
		var view: Dictionary = Postcards.VIEWS[name]
		views.append({id = name, eye = view.eye, at = view.at, fov = view.fov})
	for view: Dictionary in JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("VIEWS_JSON"))):
		views.append({id = view.id, eye = view.eye_ned, at = view.at_ned, fov = view.fov})
	for view: Dictionary in views:
		camera.fov = float(view.fov)
		camera.look_at_from_position(Frames.ned_to_render(view.eye), Frames.ned_to_render(view.at), Vector3.UP)
		var base := await _measure()
		var line := "%-18s" % view.id
		for index in variants.size():
			variants[index].visible = true
			var complete := await _measure()
			var cost := await _true_cost(variants[index], complete.p)
			variants[index].visible = false
			line += "  c%d/e%d: %7d/%2d" % [VARIANTS[index][0], VARIANTS[index][1], cost, complete.d - base.d]
		print("TRUE ", line)
	quit(0)

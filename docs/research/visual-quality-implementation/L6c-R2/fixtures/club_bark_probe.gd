## L6c-R2 fixture: club LandscapeLab trees with bark LOD error 1/2/4/8 px: captures, then per-instance cost of the club batches (visible pass, sun hidden).
## Args: --out=<dir> --views=<json>
extends SceneTree
const FieldLoader = preload("res://data/field_loader.gd")
const World = preload("res://render/world/world.gd")
const ShaderClock = preload("res://render/shader_clock.gd")
const Frames = preload("res://render/frames.gd")
const Postcards = preload("res://scenery/postcards.gd")
const LEVELS := [1.0, 2.0, 4.0, 8.0]
const COST_VIEWS := ["pilot_north", "pilot_south", "runway_zoom_100", "runway_zoom_300", "car_park", "postcard_club", "postcard_pits", "fleet_close"]
var _args := {}
var _current := 1.0


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		_args[pair[0]] = pair[1] if pair.size() > 1 else "on"
	_run.call_deferred()


func _p() -> int:
	for _i in 3:
		await RenderingServer.frame_post_draw
	return int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))


func _set_bark(batches: Array, px: float) -> void:
	var seen := {}
	for batch: MultiMeshInstance3D in batches:
		var mesh := batch.multimesh.mesh as ArrayMesh
		if seen.has(mesh.get_instance_id()):
			continue
		seen[mesh.get_instance_id()] = true
		var surfaces: Array = mesh.get("_surfaces")
		for s in surfaces.size():
			var mat := mesh.surface_get_material(s) as ShaderMaterial
			if mat != null and bool(mat.get_shader_parameter("use_alpha_scissor")):
				continue
			var lods: Array = surfaces[s].get("lods", [])
			for pair in range(0, lods.size(), 2):
				lods[pair] = float(lods[pair]) * _current / px
			surfaces[s]["lods"] = lods
		mesh.set("_surfaces", surfaces)
	_current = px


func _true_cost(batches: Array) -> int:
	var complete := await _p()
	var total := 0
	for batch: MultiMeshInstance3D in batches:
		batch.visible = false
		var counted: int = complete - await _p()
		batch.visible = true
		if counted <= 0:
			continue
		var mm := batch.multimesh
		var custom := mm.custom_aabb
		mm.custom_aabb = mm.get_aabb()
		mm.visible_instance_count = 1
		var one: int = counted - (complete - await _p())
		mm.visible_instance_count = -1
		mm.custom_aabb = custom
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
	var built: Dictionary = World.build(world, FieldLoader.load_from(FieldLoader.DEFAULT_PATH).field)
	var club: Node = built.field.get_node("Scenery/ImportedVegetationBatches")
	var batches: Array = []
	for batch: MultiMeshInstance3D in club.find_children("*", "MultiMeshInstance3D", true, false):
		if str(batch.name).begins_with("landscapelab_"):
			batches.append(batch)
	print("CLUB landscapelab batches ", batches.size())
	var camera := Camera3D.new()
	camera.near = 0.1
	camera.far = 21000.0
	world.add_child(camera)
	camera.current = true
	camera.look_at_from_position(Vector3(0, 30, 0), Vector3(50, 0, 50), Vector3.UP)
	for _index in 120:
		await RenderingServer.frame_post_draw
	for view: Dictionary in JSON.parse_string(FileAccess.get_file_as_string(str(_args.views))):
		camera.fov = float(view.fov)
		camera.look_at_from_position(Frames.ned_to_render(view.eye_ned), Frames.ned_to_render(view.at_ned), Vector3.UP)
		for px: float in LEVELS:
			_set_bark(batches, px)
			for _i in 4:
				await RenderingServer.frame_post_draw
			root.get_viewport().get_texture().get_image().save_png(out.path_join("%s_b%d.png" % [view.id, int(px)]))
	# Cost with only the club trees drawn: counts are per object, LOD depends only on the camera.
	for child in world.get_children():
		if child is Node3D and child != camera:
			(child as Node3D).visible = false
	var keep: Node = club
	while keep != null and keep != world:
		(keep as Node3D).visible = true
		for sibling in keep.get_parent().get_children():
			if sibling != keep and sibling is Node3D and keep.get_parent() != world:
				(sibling as Node3D).visible = false
		keep = keep.get_parent()
	for name: String in COST_VIEWS:
		var view: Dictionary = Postcards.VIEWS[name]
		camera.fov = view.fov
		camera.look_at_from_position(Frames.ned_to_render(view.eye), Frames.ned_to_render(view.at), Vector3.UP)
		var line := "%-16s" % name
		for px: float in LEVELS:
			_set_bark(batches, px)
			line += "  b%d %7d" % [int(px), await _true_cost(batches)]
		print("COST ", line)
	quit(0)

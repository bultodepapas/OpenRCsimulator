## L8a-R2 fixture: LandscapeLab foliage roughness sweep (0.5/0.7/0.85/1.0) in the production world, club and field trees.
## Args: --out=<dir> --views=<json>
extends SceneTree
const FieldLoader = preload("res://data/field_loader.gd")
const World = preload("res://render/world/world.gd")
const ShaderClock = preload("res://render/shader_clock.gd")
const Frames = preload("res://render/frames.gd")
const ROUGHNESS := [0.5, 0.7, 0.85, 1.0]
var _args := {}


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		_args[pair[0]] = pair[1] if pair.size() > 1 else "on"
	_run.call_deferred()


func _foliage_materials(world: Node) -> Array[ShaderMaterial]:
	var found: Array[ShaderMaterial] = []
	for batch: MultiMeshInstance3D in world.find_children("*", "MultiMeshInstance3D", true, false):
		if not str(batch.name).begins_with("landscapelab_") or batch.multimesh == null or batch.multimesh.mesh == null:
			continue
		var mesh := batch.multimesh.mesh
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s) as ShaderMaterial
			if mat != null and bool(mat.get_shader_parameter("use_alpha_scissor")) and not found.has(mat):
				found.append(mat)
	return found


func _run() -> void:
	var out := str(_args.out)
	DirAccess.make_dir_recursive_absolute(out)
	OS.set_environment("OPENRC_SCENERY_AUDIO", "off")
	OS.set_environment("OPENRC_SCENERY_BIRDS", "off")
	ShaderClock.register()
	ShaderClock.update(1.5)
	var world := Node3D.new()
	root.add_child(world)
	World.build(world, FieldLoader.load_from(FieldLoader.DEFAULT_PATH).field)
	var materials := _foliage_materials(world)
	print("SWEEP foliage materials ", materials.size())
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
		for roughness: float in ROUGHNESS:
			for mat in materials:
				mat.set_shader_parameter("roughness", roughness)
			for _i in 4:
				await RenderingServer.frame_post_draw
			root.get_viewport().get_texture().get_image().save_png(out.path_join("%s_r%03d.png" % [view.id, int(roughness * 100)]))
	print("SWEEP DONE")
	quit(0)

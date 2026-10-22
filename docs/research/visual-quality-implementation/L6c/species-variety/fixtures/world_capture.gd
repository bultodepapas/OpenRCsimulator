## Scratch audit capture: the production World.build (field, scenery, lake, sky, sun) in the main
## 1280x720 window, saved per view. Args: --out=<dir> --views=<json [{id, eye_ned, at_ned, fov}]> [--t=1.5]
extends SceneTree
const FieldLoader = preload("res://data/field_loader.gd")
const World = preload("res://render/world/world.gd")
const ShaderClock = preload("res://render/shader_clock.gd")
const Frames = preload("res://render/frames.gd")
var _args := {}


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		_args[pair[0]] = pair[1] if pair.size() > 1 else "on"
	_run.call_deferred()


func _run() -> void:
	var out := str(_args.out)
	DirAccess.make_dir_recursive_absolute(out)
	OS.set_environment("OPENRC_SCENERY_AUDIO", "off")
	OS.set_environment("OPENRC_SCENERY_BIRDS", "off")
	ShaderClock.register()
	ShaderClock.update(float(_args.get("t", "1.5")))
	root.get_viewport().mesh_lod_threshold = float(_args.get("lod_threshold", "1.0"))
	var world := Node3D.new()
	root.add_child(world)
	World.build(world, FieldLoader.load_from(FieldLoader.DEFAULT_PATH).field)
	var camera := Camera3D.new()
	camera.near = 0.1
	camera.far = 21000.0
	world.add_child(camera)
	camera.current = true
	# Compatibility fills the lake ReflectionProbe cubemap over many frames; warm up first.
	camera.look_at_from_position(Vector3(0, 30, 0), Vector3(50, 0, 50), Vector3.UP)
	for _index in int(_args.get("warmup", "120")):
		await RenderingServer.frame_post_draw
	var views: Array = JSON.parse_string(FileAccess.get_file_as_string(str(_args.views)))
	for view: Dictionary in views:
		camera.fov = float(view.fov)
		camera.look_at_from_position(Frames.ned_to_render(view.eye_ned), Frames.ned_to_render(view.at_ned), Vector3.UP)
		for _index in 4:
			await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png(out.path_join(str(view.id) + ".png"))
	print("VIEWS DONE")
	quit(0)

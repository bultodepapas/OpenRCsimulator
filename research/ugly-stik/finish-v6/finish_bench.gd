# US-V09a bench: the Stik under the production atmosphere (sky radiance, sun, ACES exposure), fixed cameras.
# Engine shadows follow OPENRC_ENGINE_SHADOWS (on by default, as in interactive flight). Report: docs/research/ugly-stik-finish-v6.md.
extends SceneTree

const AirplaneBuilder := preload("res://render/airplane.gd")
const Atmosphere := preload("res://render/atmosphere.gd")

# name: [camera position, look target, fov]
const VIEWS := {
	"hinge": [Vector3(0.9, 0.45, 1.1), Vector3(0.35, 0.05, 0.1), 30.0],
	"quarter": [Vector3(-2.2, 1.1, -2.0), Vector3(0, 0, 0.1), 32.0],
	"rear_high": [Vector3(1.4, 1.6, 3.2), Vector3(0, 0, 0.2), 32.0],
	"side": [Vector3(-3.0, 0.15, 0.2), Vector3(0, 0, 0.2), 30.0],
	"under": [Vector3(-1.6, -1.4, -1.5), Vector3(0, 0, 0.1), 32.0],
	"tail": [Vector3(-0.7, 0.35, 1.55), Vector3(0, 0.08, 0.75), 30.0],
	"nose": [Vector3(-0.55, 0.2, -0.75), Vector3(0, 0, -0.2), 32.0],
	"propeller": [Vector3(-0.22, 0.10, -0.66), Vector3(0.0, 0.03, -0.41), 30.0],
	"throttle": [Vector3(-0.20, 0.11, -0.42), Vector3(-0.012, 0.018, -0.36), 24.0],
}


func _initialize() -> void:
	_run()


func _run() -> void:
	var out := ""
	var only := ""
	var throttle := 0.5
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
		elif arg.begins_with("--view="): only = arg.trim_prefix("--view=")
		elif arg.begins_with("--throttle="): throttle = float(arg.trim_prefix("--throttle="))
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	var world := WorldEnvironment.new()
	world.environment = Atmosphere.environment()
	root.add_child(world)
	Atmosphere.create_sun(root)
	var airplane: Dictionary = AirplaneBuilder.build(AirplaneBuilder.STIK_ID)
	root.add_child(airplane.root)
	# Older app copies (A/B baselines) have no throttle linkage API.
	var builder: GDScript = AirplaneBuilder
	for method in builder.get_script_method_list():
		if method.name == "apply_throttle": builder.call("apply_throttle", airplane, throttle)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	for name in VIEWS:
		if not only.is_empty() and name != only: continue
		var v: Array = VIEWS[name]
		camera.fov = v[2]
		camera.look_at_from_position(v[0], v[1], Vector3.UP)
		for i in 4: await process_frame
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
		print("wrote ", name)
	quit(0)

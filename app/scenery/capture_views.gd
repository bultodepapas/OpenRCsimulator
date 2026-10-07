## SCENERY-PLAN SC-03: renders the named views of postcards.gd with the production field, sky, haze and sun, and writes
## <out>/<view>.png plus <out>/views.json (draw calls, primitives, objects, build stats). Needs a real renderer:
##   xvfb-run -a -s '-screen 0 1920x1080x24' godot --path app --rendering-driver opengl3 --resolution 1280x720 \
##     --script res://scenery/capture_views.gd -- --out=/tmp/scn [--scenery=on] [--views=a,b] [--t=1.5]
## With --scenery=off the same views give the empty-field baseline the budget check subtracts.
extends SceneTree

const Atmosphere = preload("res://render/atmosphere.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const FieldBuilder = preload("res://render/field.gd")
const ShaderClock = preload("res://render/shader_clock.gd")
const Frames = preload("res://render/frames.gd")
const Postcards = preload("res://scenery/postcards.gd")
const Scenery = preload("res://scenery/scenery.gd")

var _args := {}


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "on"
	_run.call_deferred()


func _run() -> void:
	var out := str(_args.get("out", "/tmp/scenery-views"))
	DirAccess.make_dir_recursive_absolute(out)
	ShaderClock.register()
	ShaderClock.update(float(_args.get("t", "1.5")))
	var world := Node3D.new()
	root.add_child(world)
	var we := WorldEnvironment.new()
	we.environment = Atmosphere.environment()
	world.add_child(we)
	var loaded: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	if not loaded.ok:
		printerr("field invalid")
		quit(1)
		return
	var t0 := Time.get_ticks_usec()
	var field_node := FieldBuilder.build(loaded.field)
	var build_ms := (Time.get_ticks_usec() - t0) / 1000.0
	world.add_child(field_node)
	Atmosphere.create_sun(world)
	var cam := Camera3D.new()
	cam.near = 0.1
	cam.far = 21000.0
	world.add_child(cam)
	cam.current = true
	var scenery := field_node.get_node_or_null("Scenery")
	var report := {scenery = Scenery.enabled(), field_build_ms = build_ms, adapter = RenderingServer.get_video_adapter_name(),
		stats = scenery.get_meta("stats") if scenery else {}, views = {}}
	var wanted: Array = Postcards.names()
	if _args.has("views"):
		wanted = str(_args.views).split(",")
	for name: String in wanted:
		var v: Dictionary = Postcards.VIEWS[name]
		cam.fov = v.fov
		cam.look_at_from_position(Frames.ned_to_render(v.eye), Frames.ned_to_render(v.at), Vector3.UP)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join(name + ".png"))
		report.views[name] = {
			draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			primitives = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			objects = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			shadow_draw_calls = RenderingServer.viewport_get_render_info(root.get_viewport_rid(),
				RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		}
	var f := FileAccess.open(out.path_join("views.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  ", true))
	f.close()
	print("SCENERY VIEWS DONE ", out)
	quit(0)

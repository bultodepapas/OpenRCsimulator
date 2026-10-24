## SC-BIRD-01/05 capture: the production world with the bird layer, a long lens from the pilot's eye aimed at the
## position bird_tracks.gd predicts (float64) for one bird of every flock at a fixed sim_clock. Each view is rendered
## with the birds, again with the birds (byte-repeat check), and once without them, so check_birds.py can isolate the
## bird's pixels and confirm the shader draws it where the CPU reference says. Needs a real renderer:
##   xvfb-run -a -s '-screen 0 1920x1080x24' godot --path app --rendering-driver opengl3 --resolution 1920x1080 \
##     --script $PWD/tools/scenery/capture_birds.gd -- --out=<new dir> [--t=20] [--target_px=60]
extends SceneTree

const FieldLoader = preload("res://data/field_loader.gd")
const World = preload("res://render/world/world.gd")
const ShaderClock = preload("res://render/shader_clock.gd")
const Frames = preload("res://render/frames.gd")
const Birds = preload("res://scenery/birds.gd")
const BirdData = preload("res://scenery/birds/bird_data.gd")
const BirdTracks = preload("res://scenery/birds/bird_tracks.gd")

const EYE_NED := [0.0, 0.0, -1.7]

var _args := {}


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "on"
	_run.call_deferred()


func _run() -> void:
	var out := str(_args.get("out", ""))
	if out.is_empty():
		printerr("capture_birds: --out=<new directory> is required")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)
	var t := float(_args.get("t", "20"))
	var target_px := float(_args.get("target_px", "60"))
	ShaderClock.register()
	ShaderClock.update(t)
	var world := Node3D.new()
	root.add_child(world)
	var loaded: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	var built: Dictionary = World.build(world, loaded.field)
	var birds: Node3D = built.field.get_node_or_null("Scenery/" + Birds.NODE_NAME)
	if birds == null:
		printerr("capture_birds: no Birds node (scenery or birds off?)")
		quit(1)
		return
	var species: Dictionary = BirdData.load_from().species
	var cam := Camera3D.new()
	cam.near = 0.1
	cam.far = 21000.0
	world.add_child(cam)
	cam.current = true
	var eye: Vector3 = Frames.ned_to_render(EYE_NED)
	var report := {sim_clock = ShaderClock.last_clock, adapter = RenderingServer.get_video_adapter_name(),
		viewport = [root.size.x, root.size.y], views = {}}
	for mmi: MultiMeshInstance3D in birds.get_children():
		var tracks: Array = mmi.get_meta("tracks")
		var order: Array = mmi.get_meta("species")
		# Per flock, the birds with the smallest and the largest time offset: the second shows that the GPU applies the
		# whole offset the CPU reference uses (custom data may be stored at 16 bits).
		var picks: Dictionary = {}
		for item: Dictionary in mmi.get_meta("instances"):
			var early: Dictionary = picks.get(item.flock + "_early", item)
			var late: Dictionary = picks.get(item.flock + "_late", item)
			picks[item.flock + "_early"] = item if (item.custom as Color).r < (early.custom as Color).r else early
			picks[item.flock + "_late"] = item if (item.custom as Color).r > (late.custom as Color).r else late
		var keys: Array = picks.keys()
		keys.sort()
		for key: String in keys:
			var item: Dictionary = picks[key]
			var c: Color = item.custom
			var p: Array[float] = BirdTracks.evaluate(tracks[item.track], t + c.r)
			var at: Vector3 = mmi.global_transform * (item.transform * Vector3(p[0], p[2], -p[1]))
			var span: float = species[order[int(c.b)]].span
			var distance: float = eye.distance_to(at)
			var fov: float = rad_to_deg(2.0 * atan(span * root.size.y / (2.0 * target_px * distance)))
			cam.fov = fov
			cam.look_at_from_position(eye, at, Vector3.UP)
			var name := key
			var shots := {}
			for shot: String in ["on", "repeat", "off"]:
				birds.visible = shot != "off"
				for i: int in 3:
					await RenderingServer.frame_post_draw
				var image: Image = root.get_texture().get_image()
				var path := out.path_join("%s_%s.png" % [name, shot])
				image.save_png(path)
				shots[shot] = path.get_file()
			birds.visible = true
			report.views[name] = {shots = shots, species = order[int(c.b)], span_m = span, distance_m = distance,
				fov_deg = fov, expected_px = [root.size.x * 0.5, root.size.y * 0.5], expected_span_px = target_px,
				time_offset_s = c.r, bird_ned = [-at.z, at.x, -at.y],
				draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}
	var f := FileAccess.open(out.path_join("birds.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  ", true))
	f.close()
	print("BIRD VIEWS DONE ", out)
	quit(0)

## SC-BIRD efficiency bench: the bird layer alone (no world) under a pilot-eye camera, sim_clock advancing, with K
## copies of the layer so the vertex-shader cost is measurable on a software renderer. Prints the mean frame time
## for 0 and K copies, alternating rounds to cancel drift. llvmpipe numbers compare versions on one machine only;
## they do not qualify any GPU.
##   xvfb-run -a -s '-screen 0 1920x1080x24' godot --path app --rendering-driver opengl3 --resolution 1920x1080 \
##     --script $PWD/tools/scenery/bench_birds.gd -- [--copies=20] [--frames=120] [--rounds=3]
extends SceneTree

const Birds = preload("res://scenery/birds.gd")
const ShaderClock = preload("res://render/shader_clock.gd")
const Frames = preload("res://render/frames.gd")

var _args := {}


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "on"
	_run.call_deferred()


func _run() -> void:
	var copies := int(_args.get("copies", "20"))
	var frames := int(_args.get("frames", "120"))
	var rounds := int(_args.get("rounds", "3"))
	ShaderClock.register()
	ShaderClock.update(20.0)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.65, 0.8)
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	root.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.far = 21000.0
	root.add_child(cam)
	cam.current = true
	# Toward the kettle (birds_watch), wide enough to hold the kettle and the kites.
	cam.look_at_from_position(Frames.ned_to_render([0.0, 0.0, -1.7]), Frames.ned_to_render([420.0, -260.0, -60.0]), Vector3.UP)
	var layers: Array[Node3D] = []
	for i: int in copies:
		var b: Node3D = Birds.build({sun_elevation_deg = 45.0, sun_azimuth_deg = 180.0})
		b.visible = false
		root.add_child(b)
		layers.append(b)
	var results := {without = [], with = []}
	var clock := 20.0
	for r: int in rounds:
		for mode: String in ["without", "with"]:
			for b: Node3D in layers:
				b.visible = mode == "with"
			for i: int in 10: # settle
				await RenderingServer.frame_post_draw
			var start := Time.get_ticks_usec()
			for i: int in frames:
				clock += 1.0 / 60.0
				ShaderClock.update(clock)
				await RenderingServer.frame_post_draw
			(results[mode] as Array).append(float(Time.get_ticks_usec() - start) / frames / 1000.0)
	var without: float = (results.without as Array).min()
	var with_birds: float = (results.with as Array).min()
	var drawn := 0
	for b: Node3D in layers:
		drawn += Birds.drawn_primitives(b)
	print("BIRD BENCH copies=%d drawn_primitives=%d frame_ms without=%.3f with=%.3f delta=%.3f per_copy_us=%.1f rounds=%s" % [
		copies, drawn, without, with_birds, with_birds - without, (with_birds - without) * 1000.0 / maxf(copies, 1), str(results)])
	quit()

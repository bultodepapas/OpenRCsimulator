# CR-09e/f review bench: production Wreck breakup of the real Stik, synthetic report, fixed camera, frames over time.
#   xvfb-run -a "$(app/get-godot.sh)" --path app --rendering-driver opengl3 --script "$PWD/research/crash-damage/cr-09e/crash_bench.gd" -- --out=<abs dir> [--class=3|4] [--component=fin_top --tail] [--focus=<section kind>] [--tag=name]
extends SceneTree

const AirplaneBuilder := preload("res://render/airplane.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const WreckScript := preload("res://render/crash/wreck.gd")


func _initialize() -> void:
	_run()


func _run() -> void:
	var out := ""
	var crash_class := 4
	var tag := "c4"
	var focus_kind := ""
	var component := "fuselage"
	var contact_model := Vector3(0, -0.05, -0.30)
	var pitch_deg := -25.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
		elif arg.begins_with("--class="): crash_class = int(arg.trim_prefix("--class="))
		elif arg.begins_with("--tag="): tag = arg.trim_prefix("--tag=")
		elif arg.begins_with("--component="): component = arg.trim_prefix("--component=")
		elif arg.begins_with("--focus="): focus_kind = arg.trim_prefix("--focus=")
		elif arg.begins_with("--tail"):
			contact_model = Vector3(0, 0.05, 0.80)
			pitch_deg = 20.0
	DirAccess.make_dir_recursive_absolute(out)
	var world := WorldEnvironment.new()
	world.environment = Atmosphere.environment()
	root.add_child(world)
	Atmosphere.create_sun(root)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color(0.30, 0.42, 0.20)
	grass.roughness = 0.95
	plane.material = grass
	ground.mesh = plane
	root.add_child(ground)
	var airplane: Dictionary = AirplaneBuilder.build(AirplaneBuilder.STIK_ID)
	root.add_child(airplane.root)
	var wreck: Node3D = WreckScript.new()
	root.add_child(wreck)
	await process_frame
	wreck.prepare(airplane.root)
	airplane.root.visible = false
	# Nose-down impact: 15 m/s forward (−Z) and 7 m/s down, nose 25° down, contact at the nose.
	var pose := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(pitch_deg)), Vector3(0, 0.32, 0))
	var velocity := Vector3(0, -7.0, -15.0)
	var report := {"class": crash_class, "severity": 1.0, "mass_kg": 2.885, "surface": "grass", "component_group": component, "component": component,
		"contact_point_world": pose * contact_model, "seed": 7, "cg_model": Vector3(0, 0, 0.0)}
	wreck.start(pose, velocity, Vector3(3.0, 0.0, 0.4), report)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	camera.fov = 38.0
	var elapsed := 0.0
	for shot in [0.15, 0.5, 1.5, 4.0]:
		while elapsed < shot:
			await physics_frame
			elapsed += 1.0 / Engine.physics_ticks_per_second
		var focus: Vector3 = (wreck.get("_core_body") as Node3D).global_position
		var offset := Vector3(2.2, 1.3, 1.8)
		if not focus_kind.is_empty():
			var groups: Array = wreck.get("_groups")
			for i in groups.size():
				if String(groups[i].kind) == focus_kind:
					focus = (wreck.get("_bodies")[i] as Node3D).global_position
			offset = {"wing_right": Vector3(-0.6, 0.30, -0.35), "aileron_left": Vector3(0.18, 0.32, 0.30)}.get(focus_kind, Vector3(0.55, 0.35, -0.55))
		camera.look_at_from_position(focus + offset, focus, Vector3.UP)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png("%s/%s_%.2fs.png" % [out, tag, shot])
	print("stats ", wreck.get_stats())
	quit(0)

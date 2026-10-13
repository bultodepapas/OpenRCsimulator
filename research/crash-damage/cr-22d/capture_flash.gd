# CR-22d review capture: a 1.28 kg kerosene C4 crash's ignition flash, at ignition, 0.4 s and 2 s, on a grass plane.
#   xvfb-run -a "$(app/get-godot.sh)" --path app --rendering-driver opengl3 --script "$PWD/research/crash-damage/cr-22d/capture_flash.gd" -- --out=<abs dir>
extends SceneTree

const Effects := preload("res://render/crash/effects.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var out := "/tmp"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color(0.25, 0.42, 0.18)
	plane.material = grass
	ground.mesh = plane
	root.add_child(ground)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 40, 0)
	root.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.75, 0.9)
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.5
	root.add_child(env)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.look_at_from_position(Vector3(5, 2.2, 6), Vector3(0, 0.6, 0), Vector3.UP)
	camera.current = true
	root.size = Vector2i(960, 540)
	var fx := Effects.new()
	root.add_child(fx)
	fx.prepare()
	await process_frame
	var report := {"class": 4, "severity": 1.0, "component_group": "fuselage", "tank_ruptured": true, "surface": "grass"}
	fx.start(Vector3.ZERO, Vector3(18, -8, 0), report, 1.28, true, Vector3(2, 0, 0))
	fx.apply_energy(Effects.energy_outcome({kerosene = 1.28}, report, true, true))
	var elapsed := 0.0
	for shot in [[0.08, "ignition"], [0.4, "0.4s"], [2.0, "2s"]]:
		while elapsed < float(shot[0]):
			fx.update(1.0 / 60.0, false)
			await process_frame
			elapsed += 1.0 / 60.0
		root.get_texture().get_image().save_png("%s/flash_%s.png" % [out, shot[1]])
		print("saved flash_%s.png" % shot[1])
	quit(0)

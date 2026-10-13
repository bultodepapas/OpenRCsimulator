## CR-17a deterministic presentation gallery; synthetic impacts, not material-strength evidence.
extends SceneTree
const Scenery := preload("res://scenery/scenery.gd")
const Presentation := preload("res://render/crash/scenery_damage.gd")
const TestFixture := preload("res://tests/test_scenery_destruction.gd")
const ShaderClock := preload("res://render/shader_clock.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	ShaderClock.register()
	root.size = Vector2i(1280, 720)
	var scene := TestFixture.FlightFixture.new()
	root.add_child(scene)
	var field := {pilot = {north = 0.0, east = 0.0, down = 0.0}, objects = [], flight_cues = []}
	var scenery := {theme = "late_spring", groups = [
		{id = "timber", type = "fence", points = [Vector2(0,-8),Vector2(0,-1)], style = "rail", seed = 42},
		{id = "wire", type = "fence", points = [Vector2(0,1),Vector2(0,8)], style = "wire", seed = 43},
		{id = "props", type = "instances", placements = [
			{prefab = "picnic_table", north = -4.0, east = -4.0, heading = 25.0, seed = 1},
			{prefab = "round_bale", north = -4.0, east = 3.0, heading = 0.0, seed = 2}]}]}
	scene._field_node = Scenery.build(field, scenery, {theme = "", quality = "high", audio = false, birds = false})
	scene.add_child(scene._field_node)
	scene.add_child(scene.session)
	var plane := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(200,200)
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color("#657545")
	grass.roughness = 1.0
	mesh.material = grass
	plane.mesh = mesh
	scene.add_child(plane)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45,-35,0)
	scene.add_child(sun)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("#c0ced5")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("#b9c9cf")
	world.environment.ambient_light_energy = 0.5
	scene.add_child(world)
	var camera := Camera3D.new()
	camera.position = Vector3(6,4.5,12)
	camera.fov = 45.0
	scene.add_child(camera)
	camera.look_at(Vector3(0,0.4,1.5))
	camera.current = true
	var director := Presentation.new()
	scene.add_child(director)
	director.configure(scene)
	director.set_process(false)
	await _save("before")
	scene.session.damage = {
		"fence:timber:00:bay:01:0": _record("wood", Vector3(-4.5,0.45,0)),
		"fence:timber:00:bay:01:1": _record("wood", Vector3(-4.5,0.95,0)),
		"fence:wire:00:bay:00:0": _record("wire", Vector3(2.5,0.55,0)),
		"fence:wire:00:bay:00:1": _record("wire", Vector3(2.5,0.85,0)),
		"fence:wire:00:bay:00:2": _record("wire", Vector3(2.5,1.12,0)),
		"prop:props:00": _record("wood", Vector3(-4,0.7,4)),
		"prop:props:01": _record("straw", Vector3(3,0.6,4)),
	}
	scene.session.scenery_damage_changed.emit()
	for group: Dictionary in director._groups:
		group.age = 0.25
		director._update_group(group)
	await _save("impact")
	for group: Dictionary in director._groups:
		group.age = 5.0
		director._update_group(group)
		if group.particles != null:
			group.particles.free()
			group.particles = null
	await _save("after")
	scene.session.damage.clear()
	scene.session.scenery_damage_changed.emit()
	await _save("reset")
	scene.session.sim.free()
	scene.free()
	quit()

func _record(profile: String, point: Vector3) -> Dictionary:
	return {profile = profile, state = "broken", tick = 0, energy_j = 100.0,
		point_ned = PackedFloat64Array([-point.z,point.x,-point.y]), normal_ned = PackedFloat64Array([-1,0,0]),
		velocity_ned = PackedFloat64Array([15,0,0]), obstacle_id = "synthetic"}

func _save(label: String) -> void:
	for frame: int in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var out := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	if out.is_empty():
		out = ProjectSettings.globalize_path("res://../captures")
	DirAccess.make_dir_recursive_absolute(out)
	var result := root.get_texture().get_image().save_png(out.path_join(label + ".png"))
	print("capture ", label, ": ", result)

## Reproducible render evidence from accepted FlightSession gear states.
extends SceneTree

const Builder := preload("res://render/airplane.gd")
const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Observer := preload("res://render/ground_gear.gd")
var flight: Node


func _initialize() -> void:
	call_deferred("capture")


func capture() -> void:
	var directory := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): directory = arg.trim_prefix("--out=")
	if directory.is_empty():
		printerr("Expected --out=<absolute evidence directory>")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(directory)
	root.size = Vector2i(1440, 900)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.09, 0.12, 0.17)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.65
	world.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -30, 0)
	light.light_energy = 1.6
	world.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(45, 130, 0)
	fill.light_energy = 0.9
	world.add_child(fill)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(2.0, -1.0, -2.6)
	camera.look_at(Vector3(0, -0.04, 0.0))
	camera.fov = 32
	camera.current = true
	var airplane := Builder.build("sebart-avanti-s-a200-p100rx")
	if airplane.is_empty():
		quit(1)
		return
	world.add_child(airplane.root)
	flight = Flight.new()
	flight.setup(Catalog.entry("sebart-avanti-s-a200-p100rx").data)
	flight.input_enabled = false
	if not flight.is_flyable():
		quit(1)
		return
	var observer: Node = Observer.attach(airplane, flight)
	var title := Label.new()
	title.position = Vector2(32, 24)
	title.add_theme_font_size_override("font_size", 26)
	root.add_child(title)
	var evidence: Array = []
	for spec in [["01-stowed", 0, 0.0], ["02-transit", 300, 0.0], ["03-downlocked", 300, 0.0], ["04-steering", 90, 1.0]]:
		flight.sim.inputs[4] = 1.0
		flight.sim.inputs[2] = spec[2]
		for i in int(spec[1]): flight.sim.step()
		if not flight.sim.fault_reason.is_empty():
			printerr(flight.sim.fault_reason)
			quit(1)
			return
		observer._process(0.0)
		title.text = "Ventage Jet · " + str(spec[0]).substr(3) + " · extension %.3f" % flight.gear_state().extension
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var path: String = directory.path_join(str(spec[0]) + ".png")
		var err := root.get_texture().get_image().save_png(path)
		if err != OK:
			quit(1)
			return
		evidence.append({file = path.get_file(), tick = flight.sim.tick, gear = flight.gear_state(), servo_yaw = flight.sim.aux[3], model_sha256 = airplane.model_manifest_sha256})
	var output := FileAccess.open(directory.path_join("captures.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify(evidence, "  ") + "\n")
	output.close()
	observer.queue_free()
	await process_frame
	flight.free()
	print("Captured four accepted gear poses to ", directory)
	quit(0)

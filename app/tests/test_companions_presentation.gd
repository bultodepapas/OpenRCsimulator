extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Agent := preload("res://ai/companions/agent.gd")
const Manager := preload("res://ai/companions/manager.gd")
const Config := preload("res://ai/companions/config.gd")
const Field := preload("res://data/field_loader.gd")
const Frames := preload("res://render/frames.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
var _failed := 0
var _checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failed += 1
		printerr("FAIL ", label)


func _run() -> void:
	var player := Flight.new()
	player.setup(Catalog.entry(Catalog.DEFAULT_ID).data)
	var field: Dictionary = Field.load_from()
	_check("fixture field loads", field.ok and player.set_field(field.field))
	_check("fixture uses explicit clock", player.configure_external_driver())
	root.add_child(player)
	var agent := Agent.new()
	var configured: Dictionary = agent.configure(player, field.field, 0, 1, 1, true, true)
	_check("presentation fixture uses qualified real aircraft", configured.ok)
	if not configured.ok:
		agent.free()
		player.free()
		quit(1)
		return
	root.add_child(agent)
	await process_frame
	await process_frame
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	var pose: Vector3 = Frames.ned_to_render(Array(agent.session.sim.state.slice(0, 3)))
	camera.position = pose + Vector3(0.0, 0.0, 60.0)
	var manager := Manager.new()
	manager.agents.append(agent)
	var before := var_to_bytes([agent.session.sim.state, agent.session.sim.aux,
		agent.session.sim.inputs, agent.session.sim.tick, agent._last_command])
	var settings: Dictionary = Config.defaults()
	settings.show_labels = true
	settings.label_distance_m = 100.0
	settings.engine_volume = 0.0
	_check("valid cosmetic settings apply", manager.apply_presentation(settings).ok)
	agent.render(0.0, false)
	_check("muting pauses only the companion voice", agent._engine.stream_paused and agent._engine.volume_db == -80.0)
	_check("near label is visible and depth-tested", agent._traffic_label.visible and not agent._traffic_label.no_depth_test)
	_check("presentation never selects a camera", root.get_camera_3d() == camera)
	var label_identity: int = agent._traffic_label.get_instance_id()
	camera.position = pose + Vector3(0.0, 0.0, 101.0)
	agent.render(0.0, false)
	_check("labels obey the configured camera distance", not agent._traffic_label.visible)
	settings.engine_volume = 0.5
	settings.show_labels = false
	manager.apply_presentation(settings)
	agent.render(0.0, false)
	_check("volume changes retain the existing source", agent._engine.playing and not agent._engine.stream_paused
		and absf(agent._engine.volume_db - (-15.0 + linear_to_db(0.5))) < 0.0001)
	_check("disabling labels retains one bounded hidden node", not agent._traffic_label.visible
		and agent._traffic_label.get_instance_id() == label_identity)
	var invalid: Dictionary = settings.duplicate()
	invalid.engine_volume = NAN
	_check("invalid edits preserve live settings", not manager.apply_presentation(invalid).ok
		and agent._engine_volume == 0.5 and manager.config.engine_volume == 0.5)
	_check("cosmetic edits preserve simulation and held pilot commands", before == var_to_bytes([
		agent.session.sim.state, agent.session.sim.aux, agent.session.sim.inputs,
		agent.session.sim.tick, agent._last_command]))
	settings.show_labels = true
	manager.apply_presentation(settings)
	camera.position = pose + Vector3(0.0, 0.0, 60.0)
	agent.failure = "fixture fault"
	agent.render(0.0, false)
	_check("stopped flights hide labels and silence voices", not agent._traffic_label.visible and agent._engine.stream_paused)
	await _capture_if_requested(agent, camera, pose)
	manager.agents.clear()
	manager.free()
	agent.free()
	camera.free()
	player.free()
	# The native audio server retires the stopped generator after its bounded fade.
	await create_timer(0.25).timeout
	print("companion presentation: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed else 0)


## Optional native component evidence, independent of concurrently authored scenery.
func _capture_if_requested(agent: Node, camera: Camera3D, pose: Vector3) -> void:
	var path := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			path = argument.trim_prefix("--capture=")
	if path.is_empty():
		return
	if DisplayServer.get_name() == "headless" or FileAccess.file_exists(path):
		_failed += 1
		printerr("Native capture requires a new output file and a renderer.")
		return
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("546a75")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	root.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	root.add_child(light)
	root.size = Vector2i(1280, 720)
	camera.position = pose + Vector3(3.5, 2.0, 5.0)
	camera.look_at(pose + Vector3.UP * 0.8)
	camera.fov = 45.0
	agent.failure = ""
	agent.render(0.0, true)
	await process_frame
	await RenderingServer.frame_post_draw
	var captured: Image = root.get_texture().get_image()
	if captured == null or captured.is_empty() or captured.save_png(path) != OK:
		_failed += 1
		printerr("Native component capture failed.")
	light.free()
	environment.free()

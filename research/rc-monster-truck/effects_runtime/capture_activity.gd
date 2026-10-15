## Native proof of integrated effects during ordinary controls on the production airfield.
extends "../driving/run_drive.gd"

const Activity = preload("res://vehicles/ground/ground_scene.gd")
var output := ""
var night := false
var impact := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		elif arg == "--night": night = true
		elif arg == "--impact": impact = true
		else:
			printerr("Unknown capture argument: ", arg)
			quit(2)
			return
	if output.is_empty() or FileAccess.file_exists(output) or DisplayServer.get_name() == "headless":
		printerr("Native renderer and --output=<fresh.png> required")
		quit(2)
		return
	_capture_run.call_deferred()

func _capture_run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i.ZERO
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	TranslationServer.set_locale("es")
	var scene = Activity.new()
	scene.enable_audio = false
	if night:
		scene.lighting_config.mode = "astronomical"
		scene.lighting_config.local_seconds = 79200
	root.add_child(scene)
	scene.set_process(false)
	scene.set_physics_process(false)
	if not scene.startup_error.is_empty():
		printerr(scene.startup_error)
		scene.free()
		quit(1)
		return
	_session = scene.session
	var default_spawn: String = _session.spawn_id
	if not _session.reset("track_technical" if impact else "track_rollers"):
		quit(1)
		return
	scene._after_reset()
	for i in 20: await process_frame
	# Offscreen native captures cannot hold desktop focus. Release only the capture's
	# modal/focus holds, then use Session's ordinary neutral-armed resume sequence.
	for hold in _session.pause_holds(): _session.release_pause_hold(hold)
	_session.tick_once(NEUTRAL)
	if not _session.resume():
		quit(1)
		return
	scene.dashboard.set_menu(false)
	_scenario = "circuit"
	_pace = "fast"
	_route = _make_loop_route()
	_route_closed = true
	_route_length_m = LOOP_LENGTH_M
	var peak_dust := 0
	var accepted := true
	var contacted := false
	for frame in 180:
		for i in 4:
			var controls: Dictionary = _controls(_session.state_snapshot(),
				_session.telemetry_snapshot().speed_m_per_s, _session.time_s(), scene._course).controls
			if impact:
				contacted = contacted or _session.telemetry_snapshot().wall_contact_count > 0
				var state: PackedFloat64Array = _session.state_snapshot()
				var yaw: float = M.q_to_euler(state.slice(Vehicle.ATT, Vehicle.ATT + 4))[0]
				var target_yaw := M.atan2_(-6.0 - state[1], 44.0 - state[0])
				controls = NEUTRAL.duplicate()
				if not contacted:
					controls.throttle = 1.0
					controls.steering = clampf(wrapf(target_yaw - yaw, -PI, PI) * 1.8, -1.0, 1.0)
			scene._last_controls = controls
			accepted = accepted and _session.tick_once(controls)
		scene._process(1.0 / 60.0)
		peak_dust = maxi(peak_dust, scene._effects.diagnostic_snapshot().dust_active_wheels)
		var target: Vector3 = scene.visual.root.global_position + Vector3(0,0.18,0)
		var offset := Vector3(0.95,0.48,-1.2) if night or impact else Vector3(1.2,0.65,1.35)
		scene.camera.position = target + scene.visual.root.global_basis * offset
		scene.camera.look_at(target)
		await process_frame
	await RenderingServer.frame_post_draw
	var saved: bool = root.get_texture().get_image().save_png(output) == OK
	var sources := {}
	for path in ["res://vehicles/ground/ground_scene.gd", "res://vehicles/ground/ground_effects.gd",
		"res://vehicles/ground/ground_grime_overlay.gdshader", "res://vehicles/ground/ground_damage_view.gd",
		"res://sim/ground_vehicle/session.gd", "res://physics/ground_vehicle/vehicle_damage.gd",
		"res://physics/ground_vehicle/vehicle_dynamics.gd"]:
		sources[path] = FileAccess.get_sha256(path)
	var checkpoint: Dictionary = _session.checkpoint()
	var tape: PackedByteArray = _session.control_tape_snapshot().to_byte_array()
	var receipt := {"ok":saved and accepted and _session.tick == 720, "scope":"actual production scene; normal reset and controls; no post-spawn state injection",
		"physical_validation":false, "image":output, "night":night, "impact":impact,
		"wall_contact_observed":contacted, "default_spawn":default_spawn,
		"capture_spawn":_session.spawn_id, "ticks":_session.tick,
		"state":Array(_session.state_snapshot()), "damage":_session.damage_visual_state(),
		"effects":scene._effects.diagnostic_snapshot(), "peak_dust_active_wheels":peak_dust,
		"field_id":scene.field.get("id", ""), "track_rendered":scene.get_node_or_null("RCObstacleTrack") != null,
		"source_sha256":sources, "identities":_session.identities_snapshot(),
		"solver_identity":checkpoint.solver_identity, "controls_f64_base64":Marshalls.raw_to_base64(tape),
		"engine":Engine.get_version_info().string, "renderer":RenderingServer.get_video_adapter_name()}
	var file := FileAccess.open(output + ".json", FileAccess.WRITE)
	if file == null: saved = false
	else:
		file.store_string(JSON.stringify(receipt,"\t",true,true))
		file.close()
	print("Integrated RC capture: ",receipt.ok," ticks=",_session.tick," effects=",receipt.effects)
	scene.free()
	await process_frame
	quit(0 if saved and receipt.ok else 1)

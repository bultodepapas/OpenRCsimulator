## Actual lake entry using ordinary Session controls. Optional native renderer capture.
extends SceneTree

const Session := preload("res://sim/ground_vehicle/session.gd")
const Field := preload("res://data/field_loader.gd")
const Lake := preload("res://data/lake_loader.gd")
const Activity := preload("res://vehicles/ground/ground_scene.gd")
const M := preload("res://physics/math3d.gd")
const NEUTRAL := {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true}
var output := ""
var capture := false
var failures := 0

# Offscreen capture has no interactive keyboard or focus. Exercise the real
# Drive action with a neutral input fixture, rather than bypassing its UI state.
class CaptureActivity extends Activity:
	func _read_controls() -> Dictionary:
		return {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		elif arg == "--capture": capture = true
	if output.is_empty() or FileAccess.file_exists(output + ".json"):
		printerr("--output=<fresh absolute stem> required")
		quit(2)
		return
	_run.call_deferred()

func _check(label: String, value: bool) -> void:
	print("PASS " if value else "FAIL ", label)
	if not value: failures += 1

func _run() -> void:
	var session
	var scene
	if capture:
		root.size = Vector2i(1280, 720)
		root.content_scale_size = Vector2i.ZERO
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		TranslationServer.set_locale("es")
		scene = CaptureActivity.new()
		scene.enable_audio = false
		root.add_child(scene)
		scene.set_process(false)
		scene.set_physics_process(false)
		if not scene.startup_error.is_empty():
			printerr(scene.startup_error)
			scene.free()
			quit(1)
			return
		session = scene.session
	else:
		session = Session.new()
		root.add_child(session)
		_check("airfield prepares with the production lake", session.prepare_airfield(Field.load_from(), {}, Lake.load_from().lake))
	_check("default remains the aircraft runway", session.spawn_id == "start")
	_check("lake-shore reset is supported", session.reset("lake_shore"))
	if failures > 0:
		if scene != null: scene.free()
		else: session.free()
		quit(1)
		return
	if capture:
		scene._after_reset()
		for frame in 15: await process_frame
		_check("garage exposes lake entry", scene.dashboard.spawn_ids.has("lake_shore"))
		if scene._wet_effects != null: scene._wet_effects.audio_enabled = false
	for hold in session.pause_holds(): session.release_pause_hold(hold)
	if capture:
		scene._focused = true
		scene.handle_action("resume")
		_check("neutral-armed Drive action starts and closes the garage", not session.is_paused() and not scene.dashboard.menu_visible)
	else:
		_check("neutral-armed entry starts", session.tick_once(NEUTRAL) and session.resume())
	_check("wet recording starts", session.start_recording())
	var csv := FileAccess.open(output + ".csv", FileAccess.WRITE)
	if csv == null:
		quit(2)
		return
	csv.store_csv_line(PackedStringArray(["tick", "north_m", "east_m", "down_m", "speed_m_per_s", "water_depth_m", "body_submersion", "buoyancy_n", "drag_power_w", "wheel_submersion_max", "mud_max", "wheel_load_total_n", "body_damage", "suspension_damage", "tick_usec"]))
	var checkpoint := {}
	var replay_controls: Array[Dictionary] = []
	var replay_state := PackedFloat64Array()
	var replay_damage := PackedFloat64Array()
	var phases := {}
	var timings: Array[float] = []
	var max_depth := 0.0
	var max_immersion := 0.0
	var max_buoyancy := 0.0
	var minimum_drag_power := 0.0
	var peak_effects := {}
	var accepted := true
	for frame in 900:
		for substep in 4:
			var state: PackedFloat64Array = session.state_snapshot()
			var tele: Dictionary = session.telemetry_snapshot()
			var yaw := M.q_to_euler(state.slice(6,10))[0]
			var target_heading := M.atan2_(125.0 - state[1], -10.0)
			var controls := NEUTRAL.duplicate()
			controls.steering = clampf(wrapf(target_heading-yaw,-PI,PI)*2.0,-0.7,0.7)
			# Slow entry retains suspension/shore contact; fluid naturally sets the later speed.
			controls.throttle = clampf((1.6 - float(tele.forward_speed_m_per_s))*0.30, 0.0, 0.65)
			var start := Time.get_ticks_usec()
			accepted = session.tick_once(controls)
			timings.append(float(Time.get_ticks_usec()-start))
			if not accepted: break
			tele = session.telemetry_snapshot()
			state = session.state_snapshot()
			var wet: Dictionary = tele.environment
			var mud: float = _maximum(wet.wheel_mud)
			var wheel_wet: float = _maximum(wet.wheel_submersion)
			var load := 0.0
			for item in tele.wheel_load_n: load += item
			max_depth = maxf(max_depth, wet.water_depth_m)
			max_immersion = maxf(max_immersion, wet.body_submersion)
			max_buoyancy = maxf(max_buoyancy, wet.buoyancy_n)
			minimum_drag_power = minf(minimum_drag_power, wet.drag_power_w)
			var row := PackedStringArray()
			for item in [session.tick,state[0],state[1],state[2],tele.speed_m_per_s,wet.water_depth_m,wet.body_submersion,wet.buoyancy_n,wet.drag_power_w,wheel_wet,mud,load,tele.damage.body_damage,tele.damage.suspension_damage,timings.back()]: row.append(str(item))
			csv.store_csv_line(row)
			if checkpoint.is_empty() and float(wet.body_submersion) > 0.6:
				checkpoint = session.checkpoint()
				var checkpoint_file := FileAccess.open(output + ".checkpoint.json", FileAccess.WRITE)
				checkpoint_file.store_string(JSON.stringify(checkpoint,"\t",true,true))
				checkpoint_file.close()
			elif not checkpoint.is_empty() and replay_controls.size() < 48:
				replay_controls.append(controls.duplicate())
				if replay_controls.size() == 48:
					replay_state = state.duplicate()
					replay_damage = session.damage_snapshot()
			if capture: scene._last_controls = controls
		if not accepted: break
		if frame % 120 == 0:
			print("ENTRY_PROGRESS ", session.tick, " ", session.state_snapshot()[0])
			csv.flush()
		var tele: Dictionary = session.telemetry_snapshot()
		var wet: Dictionary = tele.environment
		var phase := ""
		if _maximum(wet.wheel_mud) > 0.2 and wet.water_depth_m < 0.04: phase = "mud"
		if wet.water_depth_m > 0.08 and wet.water_depth_m < 0.20: phase = "shallow"
		# Cells can be immersed before the tall shell: capture later for clear roof cover.
		if wet.body_submersion > 0.95 and wet.water_depth_m > 0.65: phase = "deep"
		if capture:
			scene._process(1.0/60.0)
			var target: Vector3 = scene.visual.root.global_position + Vector3(0,0.10,0)
			scene.camera.position = target + Vector3(0.95,0.75,1.25)
			scene.camera.position.y = maxf(scene.camera.position.y, -0.10)
			scene.camera.look_at(target)
			if scene._wet_effects != null:
				var diagnostic: Dictionary = scene._wet_effects.diagnostic_snapshot()
				for key in diagnostic:
					if typeof(diagnostic[key]) in [TYPE_INT, TYPE_FLOAT]: peak_effects[key] = maxf(float(peak_effects.get(key,0.0)),float(diagnostic[key]))
			await process_frame
		if not phase.is_empty() and not phases.has(phase):
			phases[phase] = {"tick":session.tick,"state":Array(session.state_snapshot()),"environment":wet.duplicate(true)}
			if capture:
				await RenderingServer.frame_post_draw
				_check("capture "+phase,root.get_texture().get_image().save_png(output+"-"+phase+".png") == OK)
				if phase == "deep" and scene._wet_effects != null:
					var immersed_effects: Dictionary = scene._wet_effects.diagnostic_snapshot()
					_check("immersed wheels stop surface spray and ballistic mud",immersed_effects.water_instances_visible == 0 and immersed_effects.mud_instances_visible == 0)
	csv.close()
	var tape_file := FileAccess.open(output + ".controls.f64", FileAccess.WRITE)
	tape_file.store_buffer(session.control_tape_snapshot().to_byte_array())
	tape_file.close()
	_check("all water-entry ticks accepted",accepted)
	_check("active entry develops buoyancy and dissipates fluid work",max_buoyancy > 20.0 and minimum_drag_power < -10.0)
	_check("entry visits mud, shallow and submerged stages",phases.has("mud") and phases.has("shallow") and phases.has("deep"))
	if capture:
		_check("actual entry activates bounded water and mud pools",float(peak_effects.get("water_instances_visible",0.0)) > 0.0 and float(peak_effects.get("mud_instances_visible",0.0)) > 0.0)
	var fork = Session.new()
	root.add_child(fork)
	# Exercise the actual serialized save, not just the original in-memory dictionary.
	var disk_checkpoint: Variant = JSON.parse_string(FileAccess.get_file_as_string(output + ".checkpoint.json"))
	var restored: bool = typeof(disk_checkpoint) == TYPE_DICTIONARY and not disk_checkpoint.is_empty() and fork.prepare_airfield(Field.load_from(), {}, Lake.load_from().lake) and fork.restore_checkpoint(disk_checkpoint)
	_check("submerged checkpoint restores",restored)
	if restored:
		fork.tick_once(NEUTRAL)
		_check("replay resumes",fork.resume())
		for controls in replay_controls: _check("replay tick",fork.tick_once(controls))
		_check("wet replay physical state is byte exact",fork.state_snapshot().to_byte_array() == replay_state.to_byte_array())
		_check("wet replay damage state is byte exact",fork.damage_snapshot().to_byte_array() == replay_damage.to_byte_array())
		var tampered: Dictionary = checkpoint.duplicate(true)
		tampered.solver_identity.environment_version = "other-water-model"
		_check("incompatible water identity rejected",not fork.can_restore_checkpoint(tampered))
		_check("submerged truck can be recovered to dry staging",fork.manual_recovery() and fork.is_paused() and not fork.run_valid and fork.telemetry_snapshot().environment.body_submersion == 0.0 and fork.telemetry_snapshot().environment.water_depth_m == 0.0)
	fork.free()
	_check("water recording stops",session.stop_recording())
	var recorded: Dictionary = session._recorded_telemetry((session._recording_sample_count()-1)*session._record_sample_width+Session.RECORD_TELEMETRY_OFFSET)
	_check("packed recording retains water channels",recorded.environment.body_submersion == session.telemetry_snapshot().environment.body_submersion)
	timings.sort()
	var receipt := {"ok":failures == 0,"physical_validation":false,"scope":"production lake, ordinary controls, no state injection", "capture":capture,"ticks":session.tick,"max_depth_m":max_depth,"max_body_submersion":max_immersion,"max_buoyancy_n":max_buoyancy,"minimum_drag_power_w":minimum_drag_power,"phases":phases,"peak_effects":peak_effects,"final_state":Array(session.state_snapshot()),"final_damage":session.damage_visual_state(),"solver_identity":session.checkpoint().solver_identity,"identities":session.identities_snapshot(),"tick_p50_us":timings[timings.size()/2],"tick_p95_us":timings[int(timings.size()*0.95)],"engine":Engine.get_version_info().string}
	var file := FileAccess.open(output+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(receipt,"\t",true,true))
	file.close()
	print("WATER_RESULT ",JSON.stringify(receipt))
	if scene != null: scene.free()
	else: session.free()
	await process_frame
	quit(0 if failures == 0 else 1)

func _maximum(values: PackedFloat64Array) -> float:
	var result := 0.0
	for value in values: result = maxf(result, value)
	return result

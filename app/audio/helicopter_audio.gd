## AUD-15: the rotorcraft route shares the spatial mix; rotor speed stays authoritative.
extends Node
const Soundscape = preload("res://audio/soundscape.gd")
const Powertrain = preload("res://audio/powertrain_audio.gd")
const Frames = preload("res://render/frames.gd")
const M = preload("res://physics/math3d.gd")
const Skids = preload("res://physics/rotorcraft/skid_contact.gd")
const Terrain = preload("res://physics/ground_terrain.gd")
const GroundAudio = preload("res://audio/ground_audio.gd")
const GroundAudioModel = preload("res://audio/ground_audio_model.gd")
var flight: Node3D
var soundscape: Node3D
var ground_audio: Node3D


func configure(scene: Node3D) -> void:
	flight = scene
	process_priority = 100
	soundscape = Soundscape.new()
	add_child(soundscape)
	var profile: Dictionary = Powertrain.profile_for(scene.aircraft_id, {})
	profile.max_rpm = float(scene.session.aircraft.context.drive_model.governor_target_main_rad_s) * 60.0 / TAU
	var audio_seed: int = Time.get_ticks_usec()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--audio-seed="):
			audio_seed = int(argument.trim_prefix("--audio-seed="))
		elif argument == "--audio-delay=off":
			soundscape.propagation_delay = false
		elif argument == "--audio-absorption=off":
			soundscape.air_absorption = false
	soundscape.configure(scene.field, "electric_prop", audio_seed, "", profile)
	ground_audio = GroundAudio.new()
	ground_audio.configure(self, soundscape.output_bus())
	ground_audio.bind_soundscape(soundscape)
	scene.session.resetting.connect(_on_resetting)
	for legacy: Node in scene.find_children("Ambience", "AudioStreamPlayer", true, false):
		(legacy as AudioStreamPlayer).stop()
		legacy.process_mode = Node.PROCESS_MODE_DISABLED


func snapshot() -> Dictionary:
	var session: Node = flight.session
	var state: PackedFloat64Array = session.sim.state
	var q: PackedFloat64Array = state.slice(6, 10)
	var main: Dictionary = session.aircraft.context.main_model
	var arm: PackedFloat64Array = M.v3(main.hub_x_m, main.hub_y_m, main.hub_z_m)
	var position: PackedFloat64Array = M.add(state.slice(0, 3), M.q_rotate(q, arm))
	var wind: Vector3 = Frames.ned_to_render(session.wind_at(session.sim.time()))
	var velocity: Vector3 = Frames.ned_to_render(M.q_rotate(q, state.slice(3, 6)))
	var hub_velocity: Vector3 = velocity + Frames.ned_to_render(M.q_rotate(q, M.cross(state.slice(10, 13), arm)))
	var maximum: float = float(session.aircraft.context.drive_model.governor_target_main_rad_s) * 60.0 / TAU
	return {
		rpm = maxf(float(session.sim.continuous[0]), 0.0) * 60.0 / TAU, max_rpm = maximum,
		running = session.power.armed and not session.zero_drive_hold,
		throttle = session.commands.throttle, load = clampf(absf(session.collective_pitch()) / deg_to_rad(12.0), 0.0, 1.0),
		source = Frames.ned_to_render(position), listener = flight._camera.global_position,
		source_velocity = hub_velocity, time = session.sim.time(), paused = session.sim.paused,
		airspeed = (velocity - wind).length(), wind_speed = wind.length(), wind_direction = wind,
		blades = 2, sun_elevation = float(flight._lighting_snapshot.get("sun_elevation_deg", 45.0)),
	}


func _process(delta: float) -> void:
	if flight == null or soundscape == null or flight.session.sim.state.is_empty():
		return
	var accepted: Dictionary = snapshot()
	soundscape.update_sound(accepted, delta)
	ground_audio.update_contacts(int(flight.session.sim.tick), bool(accepted.paused), contact_snapshot(),
		float(accepted.throttle) if bool(accepted.running) else 0.0, delta, accepted.listener)


func _on_resetting() -> void:
	soundscape.reset_observer()
	ground_audio.reset()


## Same accepted skid law as the session. Skids can touch down but never emit wheel rolling.
func contact_snapshot() -> Array:
	var session: Node = flight.session
	var state: PackedFloat64Array = session.sim.state
	var continuous: PackedFloat64Array = session.sim.continuous
	var result: Dictionary = Skids.evaluate(state, session.aircraft.skids, session.ground_surfaces, true,
		continuous.slice(6) if continuous.size() == 14 else PackedFloat64Array())
	var contacts: Array = []
	if not bool(result.get("ok", false)):
		return contacts
	var q: PackedFloat64Array = state.slice(6, 10)
	var points: PackedFloat64Array = session.aircraft.skids.points_body_frd_m
	for index: int in 4:
		var arm: PackedFloat64Array = points.slice(index * 3, index * 3 + 3)
		var position: PackedFloat64Array = M.add(state.slice(0, 3), M.q_rotate(q, arm))
		var velocity: PackedFloat64Array = M.q_rotate(q, M.add(state.slice(3, 6), M.cross(state.slice(10, 13), arm)))
		var terrain: PackedFloat64Array = Terrain.sample_validated(position[0], position[1], session.ground_surfaces)
		var approach: float = (velocity[2] + terrain[1] * velocity[0] + terrain[2] * velocity[1]) / sqrt(1.0 + terrain[1] * terrain[1] + terrain[2] * terrain[2])
		var material: String = GroundAudioModel.surface_name(flight.field, position[0], position[1])
		var force: float = float(result.normal_forces_n[index])
		contacts.append({id = "skid_%d" % index, position = Frames.ned_to_render(position),
			velocity_mps = Frames.ned_to_render(velocity), normal_force_n = force,
			reference_load_n = maxf(float(session.sim.mass) * float(session.sim.gravity) / 4.0, 1.0),
			compression_m = float(result.compressions_m[index]), approach_speed_mps = maxf(approach, 0.0),
			surface = material, grounded = force > 0.05, roll_enabled = false})
	return contacts

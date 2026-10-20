## AUD-15: the rotorcraft route shares the spatial mix; rotor speed stays authoritative.
extends Node
const Soundscape = preload("res://audio/soundscape.gd")
const Powertrain = preload("res://audio/powertrain_audio.gd")
const Frames = preload("res://render/frames.gd")
const M = preload("res://physics/math3d.gd")
var flight: Node3D
var soundscape: Node3D


func configure(scene: Node3D) -> void:
	flight = scene
	process_priority = 100
	soundscape = Soundscape.new()
	add_child(soundscape)
	var profile: Dictionary = Powertrain.profile_for(scene.aircraft_id, {})
	profile.max_rpm = float(scene.session.aircraft.context.drive_model.governor_target_main_rad_s) * 60.0 / TAU
	soundscape.configure(scene.field, "electric_prop", 4102026, "", profile)
	scene.session.resetting.connect(soundscape.reset_observer)
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
	var maximum: float = float(session.aircraft.context.drive_model.governor_target_main_rad_s) * 60.0 / TAU
	return {
		rpm = maxf(float(session.sim.continuous[0]), 0.0) * 60.0 / TAU, max_rpm = maximum,
		running = session.power.armed and not session.zero_drive_hold,
		throttle = session.commands.throttle, load = clampf(absf(session.collective_pitch()) / deg_to_rad(12.0), 0.0, 1.0),
		source = Frames.ned_to_render(position), listener = flight._camera.global_position,
		source_velocity = velocity, time = session.sim.time(), paused = session.sim.paused,
		airspeed = (velocity - wind).length(), wind_speed = wind.length(), wind_direction = wind,
		blades = 2, sun_elevation = float(flight._lighting_snapshot.get("sun_elevation_deg", 45.0)),
	}


func _process(delta: float) -> void:
	if flight == null or soundscape == null or flight.session.sim.state.is_empty():
		return
	soundscape.update_sound(snapshot(), delta)

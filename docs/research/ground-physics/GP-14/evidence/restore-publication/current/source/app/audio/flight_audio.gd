## AUD-03. Read-only presentation adapter; runs after main's pose/camera update.
extends Node

const Soundscape = preload("res://audio/soundscape.gd")
const SoundscapeModel = preload("res://audio/soundscape_model.gd")
const Frames = preload("res://render/frames.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const Propulsion = preload("res://physics/propulsion.gd")
const Turbine = preload("res://physics/turbine.gd")
const P51Geometry = preload("res://aircraft/p51d_geometry.gd")
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
const EngineSound = preload("res://render/engine_sound.gd")
const PowertrainAudio = preload("res://audio/powertrain_audio.gd")
const GroundAudio = preload("res://audio/ground_audio.gd")
const GroundAudioModel = preload("res://audio/ground_audio_model.gd")
const MechanicalAudio = preload("res://audio/mechanical_audio.gd")
const MechanicalProfile = preload("res://audio/mechanical_profile.gd")
const TIMBER_ID := "turbo-lumber-evolution"
var flight: Node3D
var soundscape: Soundscape
var ground_audio: GroundAudio
var mechanical_audio: Node3D
var _mechanical_channels: Array[Dictionary] = []
var _mechanical_anchors: Array[Array] = []
var _mechanical_snapshot: Dictionary = {}
var _mechanical_mask := 1.0
var _last_tick: int = -1
var _mechanical_session: Node
var _mechanical_sim: Node
var _accepted_mechanical_mode := false
var _accepted_ground_mode := false
var _windsock: WeakRef
var last_update_usec: int = 0
var last_mechanical_update_usec: int = 0


func configure(scene: Node3D) -> void:
	_disconnect_mechanical_observer()
	# Reconfiguration replaces a rig, rather than leaving duplicate bus/player
	# owners and accepted-tick connections attached to the previous session.
	for previous: Node in [mechanical_audio, ground_audio, soundscape]:
		if is_instance_valid(previous): previous.free()
	mechanical_audio = null
	ground_audio = null
	soundscape = null
	flight = scene
	_last_tick = -1
	_windsock = null
	process_priority = 100
	soundscape = Soundscape.new()
	add_child(soundscape)
	# Scene-local variety without touching the simulation/global RNG. Probes can pin the seed.
	var audio_seed: int = Time.get_ticks_usec()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--audio-seed="):
			audio_seed = int(argument.trim_prefix("--audio-seed="))
		elif argument == "--audio-delay=off": # AUD-11 (D6): comparison and tests
			soundscape.propagation_delay = false
		elif argument == "--audio-absorption=off": # AUD-11b: source-level calibration and comparison
			soundscape.air_absorption = false
	var propulsion: Dictionary = flight.session.aircraft.model.propulsion
	var glow_family: String = _glow_family(propulsion)
	soundscape.configure(flight.field, str(propulsion.get("kind", "glow_prop")), audio_seed, glow_family,
		PowertrainAudio.profile_for(flight.aircraft_id, propulsion))
	ground_audio = GroundAudio.new()
	ground_audio.configure(self, soundscape.output_bus())
	ground_audio.bind_soundscape(soundscape)
	mechanical_audio = MechanicalAudio.new()
	mechanical_audio.configure(self, soundscape.output_bus(),
		MechanicalProfile.resolve(flight.workshop_trial.get("presentation_profile", {})))
	mechanical_audio.bind_soundscape(soundscape)
	_bind_mechanical_channels()
	var field_node: Node3D = flight.get("_field_node") as Node3D
	if field_node != null:
		var cues: Array = field_node.get_meta("wind_cues", [])
		if not cues.is_empty():
			_windsock = weakref(cues[0])
	_connect_mechanical_observer()
	silence_legacy_ambience(flight)


func _connect_mechanical_observer() -> void:
	_disconnect_mechanical_observer()
	if not is_instance_valid(flight) or not is_instance_valid(mechanical_audio) \
		or not is_instance_valid(flight.session) or not is_instance_valid(flight.session.sim): return
	_mechanical_session = flight.session
	_mechanical_sim = _mechanical_session.sim
	mechanical_audio.set_accepted_tick_observation(true)
	_accepted_mechanical_mode = true
	_accepted_ground_mode = is_instance_valid(ground_audio)
	if _accepted_ground_mode: ground_audio.set_accepted_tick_observation(true)
	# FlightSession installs its commit handler during setup, before this rig.
	_mechanical_sim.stepped.connect(_on_accepted_mechanical_tick)
	_mechanical_sim.paused_changed.connect(_on_mechanical_pause_changed)
	_mechanical_session.resetting.connect(_on_resetting)
	_observe_mechanical_endpoint()
	_observe_ground_endpoint()


func _disconnect_mechanical_observer() -> void:
	if is_instance_valid(_mechanical_sim):
		if _mechanical_sim.stepped.is_connected(_on_accepted_mechanical_tick):
			_mechanical_sim.stepped.disconnect(_on_accepted_mechanical_tick)
		if _mechanical_sim.paused_changed.is_connected(_on_mechanical_pause_changed):
			_mechanical_sim.paused_changed.disconnect(_on_mechanical_pause_changed)
	if is_instance_valid(_mechanical_session) and _mechanical_session.resetting.is_connected(_on_resetting):
		_mechanical_session.resetting.disconnect(_on_resetting)
	_mechanical_sim = null
	_mechanical_session = null
	_accepted_mechanical_mode = false
	_accepted_ground_mode = false


func _enter_tree() -> void:
	if is_instance_valid(flight) and is_instance_valid(mechanical_audio):
		_disconnect_mechanical_observer()
		mechanical_audio.reset()
		if is_instance_valid(ground_audio): ground_audio.reset()
		call_deferred("_resume_mechanical_observer")


func _resume_mechanical_observer() -> void:
	if not is_inside_tree() or not is_instance_valid(flight) or not is_instance_valid(mechanical_audio): return
	# Children have re-entered by now. Bind synchronously before priming, so a
	# deferred bus refresh cannot reset and erase newly captured endpoint motion.
	if is_instance_valid(soundscape):
		mechanical_audio.bind_soundscape(soundscape)
		if is_instance_valid(ground_audio): ground_audio.bind_soundscape(soundscape)
	_connect_mechanical_observer()


func _exit_tree() -> void:
	_disconnect_mechanical_observer()
	if is_instance_valid(mechanical_audio): mechanical_audio.reset()
	_last_tick = -1


func _on_accepted_mechanical_tick(_tick: int, _time: float, _state: PackedFloat64Array,
		_loads: PackedFloat64Array, _inputs: PackedFloat64Array, _aux: PackedFloat64Array) -> void:
	if is_instance_valid(_mechanical_sim) and _tick == _mechanical_sim.tick:
		_observe_mechanical_endpoint()
		_observe_ground_endpoint()


func _on_mechanical_pause_changed(_paused: bool) -> void:
	_observe_mechanical_endpoint()
	_observe_ground_endpoint()


func _observe_mechanical_endpoint() -> void:
	if not _accepted_mechanical_mode or not is_instance_valid(mechanical_audio) \
		or not is_instance_valid(flight) or flight.session != _mechanical_session: return
	var endpoint := accepted_mechanical_snapshot()
	if not endpoint.is_empty(): mechanical_audio.observe_accepted(endpoint)


## The legacy contact law is re-evaluated read-only at accepted endpoints until
## the advanced contact owner supplies its accepted receipt. No players run here.
func _observe_ground_endpoint() -> void:
	if not _accepted_ground_mode or not is_instance_valid(ground_audio) \
		or not is_instance_valid(flight) or flight.session != _mechanical_session: return
	var active: bool = _mechanical_session.physics_enabled and bool(_mechanical_session.aircraft.get("ok", false))
	var paused: bool = _mechanical_sim.paused or not active
	var contacts: Array = [] if paused else contact_snapshot()
	ground_audio.observe_accepted({tick = _mechanical_sim.tick, tick_rate = 1.0 / _mechanical_sim.dt(),
		paused = paused, contacts = contacts})


## Actual accepted actuator values only. This path has no render transforms,
## air-data/load evaluation or target-to-motion reconstruction. Paused manual
## steps prime silently, so their cues cannot replay after resume.
func accepted_mechanical_snapshot() -> Dictionary:
	if not is_instance_valid(_mechanical_session) or not is_instance_valid(_mechanical_sim): return {}
	var active: bool = _mechanical_session.physics_enabled and bool(_mechanical_session.aircraft.get("ok", false))
	var channels: Array[Dictionary] = []
	var gear := {}
	if active:
		var angles: Dictionary = _mechanical_session.surface_angles_deg()
		for pair: Array in [["aileron", "aileron_right"], ["elevator", "elevator"], ["rudder", "rudder"]]:
			channels.append({id = pair[0], angle_deg = float(angles.get(pair[1], 0.0))})
		if _mechanical_session.flaps_available():
			channels.append({id = "flap", angle_deg = float(_mechanical_sim.aux[_mechanical_session.flap_aux_index()])
				* float(_mechanical_session.aircraft.model.flaps.max_angle_deg)})
		gear = _mechanical_session.gear_state()
	return {tick = _mechanical_sim.tick, tick_rate = 1.0 / _mechanical_sim.dt(),
		paused = _mechanical_sim.paused or not active, channels = channels, gear = gear}


static func silence_legacy_ambience(scene: Node) -> void:
	# The old scenery bed is explicitly superseded for this flight, without editing its owner's code.
	for legacy: Node in scene.find_children("Ambience", "AudioStreamPlayer", true, false):
		legacy.process_mode = Node.PROCESS_MODE_DISABLED
		(legacy as AudioStreamPlayer).stop()


## Current speed of sound from the accepted flight atmosphere, without building full audio telemetry.
func sound_speed_mps() -> float:
	var atmosphere: Dictionary = flight.session.atmosphere_configuration()
	return sqrt(1.4 * 287.05 * float(atmosphere.get("temperature_k", 288.15)))


func snapshot() -> Dictionary:
	var session: Node = flight.session
	var source_running: bool = propulsion_source_running(session)
	var wind: Vector3 = Frames.ned_to_render(Array(session.wind_at(session.sim.time())))
	var prop: Dictionary = session.aircraft.model.propulsion
	var atmosphere: Dictionary = session.atmosphere_configuration()
	var blades: int = propeller_blade_count(flight.aircraft_id)
	var glow_family: String = _glow_family(prop)
	var glow_profile: Dictionary = prop.get("glow", {}).get("profile", {})
	var air: Dictionary = session.air_data(session.sim.state)
	var rpm: float = session.sim.aux[0]
	var load_amount: float = session.sim.inputs[3]
	if str(prop.get("kind", "glow_prop")) != "turbine" and rpm > 30.0:
		# Read-only shaft load at accepted RPM/inflow, normalized to static torque at that RPM.
		# The mapping to timbre is authored; this is not an acoustic calibration.
		var torque: float = Propulsion.thrust_torque(air.v_air, rpm, prop, session.air_density())[1]
		var reference: float = Propulsion.prop_torque(rpm, 0.0, prop, session.air_density())
		load_amount = clampf(maxf(torque, 0.0) / maxf(reference, 0.00001), 0.0, 1.0)
	var elevation: float = float(flight._lighting.get("solar", {}).get("elevation_deg", flight._lighting.get("sun_elevation_deg", 45.0)))
	if not Atmosphere.state.is_empty():
		elevation = float(Atmosphere.state.get("sun_elevation_deg", elevation))
	var glow_state: Dictionary = {}
	if session.has_method("glow_state"):
		var accepted_glow: Variant = session.call("glow_state")
		if accepted_glow is Dictionary:
			glow_state = accepted_glow.duplicate()
	if not glow_family.is_empty():
		var operation: Dictionary = glow_profile.get("operation", {})
		glow_state["family"] = str(glow_state.get("family", glow_family))
		glow_state["rpm"] = float(glow_state.get("rpm", rpm))
		glow_state["max_rpm"] = float(glow_state.get("max_rpm", operation.get("max_rpm", EngineSound.reference_rpm(prop))))
		glow_state["running"] = source_running and bool(glow_state.get("running", true))
		glow_state["firing_fraction"] = float(glow_state.get("firing_fraction", 1.0))
		glow_state["load"] = float(glow_state.get("load", load_amount))
		glow_state["throttle"] = float(glow_state.get("throttle", session.sim.inputs[3]))
		glow_state["blade_count"] = int(glow_state.get("blade_count", blades))
		glow_state["sample_tick"] = int(session.sim.tick)
	# Doppler source velocity: accepted body velocity rotated to NED, converted at the render boundary.
	var s: PackedFloat64Array = session.sim.state
	var attitude: PackedFloat64Array = M.quat(s[RB.ATT], s[RB.ATT + 1], s[RB.ATT + 2], s[RB.ATT + 3])
	var velocity: Vector3 = Frames.ned_to_render(Array(M.q_rotate(attitude, M.v3(s[RB.VEL], s[RB.VEL + 1], s[RB.VEL + 2]))))
	# Engine/propeller emitter at the installed thrust line, not the imported mesh's origin.
	var offset: PackedFloat64Array = prop.get("offset", PackedFloat64Array([0.0, 0.0, 0.0]))
	var source_arm: PackedFloat64Array = M.v3(-offset[0], offset[1], -offset[2])
	var source_ned: PackedFloat64Array = M.add(s.slice(RB.POS, RB.POS + 3), M.q_rotate(attitude, source_arm))
	var source_velocity: Vector3 = velocity + Frames.ned_to_render(M.q_rotate(attitude,
		M.cross(s.slice(RB.RATE, RB.RATE + 3), source_arm)))
	# AUD-10: jet velocity V_j = gross thrust / mass flow from the accepted state (read-only pure functions), and the
	# exhaust direction (opposite the thrust axis) for directivity. Static V_j at maximum rpm normalizes it.
	var jet_velocity: float = 0.0
	var jet_velocity_max: float = 1.0
	var exhaust: Vector3 = Vector3.ZERO
	if Turbine.is_turbine(prop):
		var rho: float = session.air_density()
		var u: float = M.dot(air.v_air, prop.axis)
		var flow: float = Turbine.mass_flow(rpm, prop, rho, u)
		jet_velocity = Turbine.gross_thrust(rpm, prop, rho, u) / flow if flow > 0.0 else 0.0
		jet_velocity_max = Turbine.gross_thrust(float(prop.max_rpm), prop, rho) / Turbine.mass_flow(float(prop.max_rpm), prop, rho)
		var axis: PackedFloat64Array = prop.axis
		exhaust = Frames.ned_to_render(Array(M.q_rotate(attitude, M.v3(-axis[0], -axis[1], -axis[2]))))
	# AUD-11b: ISO 9613-1 inputs from the accepted atmosphere. The reference atmosphere is dry ISA air by
	# construction, so it takes the documented presentation humidity instead of 0 %.
	var temperature_k: float = float(atmosphere.get("temperature_k", 288.15))
	var pressure_pa: float = float(atmosphere.get("pressure_pa", SoundscapeModel.ISO_REFERENCE_PRESSURE_PA))
	var humidity: float = SoundscapeModel.humidity_molar_pct(SoundscapeModel.REFERENCE_RELATIVE_HUMIDITY_PCT, temperature_k, pressure_pa)
	if not session.atmosphere_is_reference() and pressure_pa > 0.0:
		humidity = 100.0 * float(atmosphere.get("vapor_pressure_pa", 0.0)) / pressure_pa
	# Turbine load uses throttle; propellers use accepted-state aerodynamic torque.
	var result: Dictionary = {
		rpm = rpm, max_rpm = EngineSound.reference_rpm(prop),
		load = load_amount, throttle = session.sim.inputs[3], running = source_running,
		blades = blades, sound_speed = sqrt(1.4 * 287.05 * float(atmosphere.get("temperature_k", 288.15))),
		airspeed = air.V,
		temperature_c = temperature_k - 273.15, pressure_pa = pressure_pa, humidity_molar_pct = humidity,
		wind_speed = wind.length(), wind_direction = wind,
		source = Frames.ned_to_render(source_ned), listener = listener_position(), source_velocity = source_velocity,
		paused = session.sim.paused, sun_elevation = elevation, time = session.sim.time(),
		jet_velocity = jet_velocity, jet_velocity_max = jet_velocity_max, exhaust_direction = exhaust,
		glow = glow_state,
	}
	var sock: Node3D = _windsock.get_ref() as Node3D if _windsock != null else null
	if is_instance_valid(sock):
		var cloth: Node3D = sock.get_node_or_null("Fabric") as Node3D
		if cloth != null and cloth.has_meta("centreline"):
			var centres: PackedVector3Array = cloth.get_meta("centreline")
			if centres.size() > 8:
				result.fabric_source = sock.global_transform * centres[8]
		if sock.has_meta("windsock_motion"):
			result.windsock_inflation = float(sock.get_meta("windsock_motion").inflation)
	return result


func listener_position() -> Vector3:
	var listener := flight.get_viewport().get_audio_listener_3d()
	return listener.get_listener_transform().origin if listener != null else flight._camera.global_position


static func propulsion_source_running(session: Node) -> bool:
	if session.has_method("propulsion_source_running"):
		return bool(session.call("propulsion_source_running"))
	return bool(session.get("engine_running"))


static func _glow_family(propulsion: Dictionary) -> String:
	var glow: Variant = propulsion.get("glow", {})
	if not glow is Dictionary:
		return ""
	var profile: Variant = glow.get("profile", {})
	if not profile is Dictionary:
		return ""
	var family: String = str(profile.get("family", ""))
	return family if family in ["glow_2t", "glow_4t"] else ""


static func propeller_blade_count(aircraft_id: String) -> int:
	if aircraft_id == "p51d-mustang-120":
		return int(P51Geometry.DATA.propeller.blades)
	if aircraft_id == TIMBER_ID or aircraft_id == "f4u-corsair-250":
		return 3
	return 2


func _on_resetting() -> void:
	_last_tick = -1
	if soundscape != null: soundscape.reset_observer()
	if ground_audio != null:
		ground_audio.reset()
	if mechanical_audio != null:
		mechanical_audio.reset()
	_mechanical_mask = 1.0


func contact_snapshot() -> Array[Dictionary]:
	return GroundAudioModel.snapshot_contacts(flight.session, flight.field)


## One source per accepted logical actuator. Mirrored visual surfaces do not invent
## independent servo state. The authored hinge centres approximate the installation.
func _bind_mechanical_channels() -> void:
	_mechanical_channels.clear()
	_mechanical_anchors.clear()
	_mechanical_snapshot.clear()
	var airplane: Dictionary = flight._airplane
	var controls: Dictionary = airplane.get("model_manifest", {}).get("bindings", {}).get("controls", {})
	var groups: Array = [["aileron_left", "aileron_right"], ["elevator"], ["rudder"]]
	if flight.session.flaps_available(): groups.append(["flap_left", "flap_right"])
	var ids := ["aileron", "elevator", "rudder", "flap"]
	for index: int in groups.size():
		var anchors: Array = []
		for surface: String in groups[index]:
			for binding: Dictionary in controls.get(surface, {}).get("hinges", []):
				var hinge: Variant = airplane.get("hinges", {}).get(str(binding.key))
				var node: Node3D = hinge as Node3D if hinge is Node3D else (hinge.get("node") as Node3D if hinge is Dictionary else null)
				if node != null and not anchors.has(node): anchors.append(node)
		_mechanical_anchors.append(anchors)
		_mechanical_channels.append({id = ids[index], angle_deg = 0.0, position = Vector3.ZERO})
	_mechanical_snapshot = {channels = _mechanical_channels, tick_rate = float(Engine.physics_ticks_per_second)}


func mechanical_snapshot(sound: Dictionary, delta: float) -> Dictionary:
	var angles: Dictionary = flight.session.surface_angles_deg()
	_mechanical_channels[0].angle_deg = float(angles.get("aileron_right", 0.0))
	_mechanical_channels[1].angle_deg = float(angles.get("elevator", 0.0))
	_mechanical_channels[2].angle_deg = float(angles.get("rudder", 0.0))
	if _mechanical_channels.size() > 3:
		# The status accessor also computes an overspeed advisory; audio only needs
		# the same accepted fraction/maximum angle, without another air-data solve.
		_mechanical_channels[3].angle_deg = float(flight.session.sim.aux[flight.session.flap_aux_index()]) \
			* float(flight.session.aircraft.model.flaps.max_angle_deg)
	var root_position: Vector3 = flight._airplane.root.global_position
	for index: int in _mechanical_channels.size():
		var position := Vector3.ZERO
		var count := 0
		for node: Node3D in _mechanical_anchors[index]:
			if is_instance_valid(node):
				position += node.global_position
				count += 1
		_mechanical_channels[index].position = position / float(count) if count > 0 else root_position
	var gear: Dictionary = flight.session.gear_state()
	gear["position"] = root_position
	gear["target"] = 1.0 if bool(gear.get("target_down", false)) else 0.0
	_mechanical_snapshot.gear = gear
	_mechanical_snapshot.tick = flight.session.sim.tick
	_mechanical_snapshot.paused = bool(sound.get("paused", false)) or not flight.session.physics_enabled
	_mechanical_snapshot.listener = sound.listener
	# Quiet mechanisms already sit below the engine. A modest, smoothed residual
	# reduction prevents stacking several near-field servos over a running engine.
	# Accepted RPM retains gasoline idle masking and electric coast; stick position
	# alone never hides or exposes sound. These are authored mix trims, not SPL data.
	var family: String = str(soundscape.voice_profile.get("family", ""))
	var rpm_fraction := clampf(float(sound.rpm) / maxf(float(sound.max_rpm), 1.0), 0.0, 1.0)
	var combustion: bool = family in ["gasoline", "glow_2t", "glow_4t", "turbine"]
	var active := bool(sound.get("running", false)) and float(sound.rpm) > 100.0
	var reduction_db: float = (8.0 + 12.0 * rpm_fraction) if combustion and active else 13.0 * smoothstep(0.10, 0.85, rpm_fraction)
	var target := db_to_linear(-reduction_db)
	_mechanical_mask += (target - _mechanical_mask) * (1.0 - exp(-clampf(delta, 0.0, 0.1) / 0.18))
	_mechanical_snapshot.engine_mask = _mechanical_mask
	return _mechanical_snapshot


func _process(delta: float) -> void:
	var started: int = Time.get_ticks_usec()
	if flight == null or soundscape == null:
		return
	var tick: int = flight.session.sim.tick
	if tick < _last_tick:
		soundscape.reset_observer()
		# Accepted mode already handled the rewind at its source. Do not erase
		# legitimate post-rewind transitions captured before this render frame.
		if mechanical_audio != null and not _accepted_mechanical_mode:
			mechanical_audio.reset()
	_last_tick = tick
	var sound_snapshot: Dictionary = snapshot()
	soundscape.update_sound(sound_snapshot, delta)
	var paused: bool = bool(sound_snapshot.get("paused", false))
	var ground_contacts: Array[Dictionary] = []
	if not paused and not _accepted_ground_mode:
		ground_contacts = contact_snapshot()
	var engine_power: float = float(sound_snapshot.get("throttle", 0.0)) if bool(sound_snapshot.get("running", false)) else 0.0
	ground_audio.update_contacts(tick, paused, ground_contacts,
		engine_power, delta, sound_snapshot.get("listener", Vector3.ZERO), float(Engine.physics_ticks_per_second))
	if mechanical_audio != null:
		var mechanical_started: int = Time.get_ticks_usec()
		mechanical_audio.update_sound(mechanical_snapshot(sound_snapshot, delta), delta)
		last_mechanical_update_usec = Time.get_ticks_usec() - mechanical_started
	last_update_usec = Time.get_ticks_usec() - started

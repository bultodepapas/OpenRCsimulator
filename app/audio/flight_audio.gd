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
const TIMBER_ID := "turbo-lumber-evolution"
var flight: Node3D
var soundscape: Soundscape
var _last_tick: int = -1
var _windsock: WeakRef
var last_update_usec: int = 0


func configure(scene: Node3D) -> void:
	flight = scene
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
	soundscape.configure(flight.field, str(propulsion.get("kind", "glow_prop")), audio_seed, glow_family)
	var field_node: Node3D = flight.get("_field_node") as Node3D
	if field_node != null:
		var cues: Array = field_node.get_meta("wind_cues", [])
		if not cues.is_empty():
			_windsock = weakref(cues[0])
	flight.session.resetting.connect(_on_resetting)
	silence_legacy_ambience(flight)


static func silence_legacy_ambience(scene: Node) -> void:
	# The old scenery bed is explicitly superseded for this flight, without editing its owner's code.
	for legacy: Node in scene.find_children("Ambience", "AudioStreamPlayer", true, false):
		legacy.process_mode = Node.PROCESS_MODE_DISABLED
		(legacy as AudioStreamPlayer).stop()


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
		source = flight._airplane.root.global_position, listener = flight._camera.global_position, source_velocity = velocity,
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
	if aircraft_id == TIMBER_ID:
		return 3
	return 2


func _on_resetting() -> void:
	_last_tick = -1
	soundscape.reset_observer()


func _process(delta: float) -> void:
	var started: int = Time.get_ticks_usec()
	if flight == null or soundscape == null:
		return
	var tick: int = flight.session.sim.tick
	if tick < _last_tick:
		soundscape.reset_observer()
	_last_tick = tick
	soundscape.update_sound(snapshot(), delta)
	last_update_usec = Time.get_ticks_usec() - started

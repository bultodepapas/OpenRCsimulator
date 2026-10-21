## AFC-03/05: one controllerless flight, with presentation only at the render boundary.
extends Node3D

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Pilot := preload("res://ai/companions/pilot.gd")
const Frames := preload("res://render/frames.gd")
const Builder := preload("res://render/airplane.gd")
const EngineSound := preload("res://render/engine_sound.gd")
const ControlSurfaces := preload("res://physics/control_surfaces.gd")
const Profiles := preload("res://ai/companions/profile_loader.gd")
const ObservationAirdata := preload("res://ai/companions/observation_airdata.gd")

var session: Node
var pilot: RefCounted
var slot_id := 0
var failure := ""
var view: Dictionary = {}
var _cg_model := Vector3.ZERO
var _engine: AudioStreamPlayer3D
var _prop_angle := 0.0
var _last_command: Dictionary = {}
var _weather_rms := PackedFloat64Array()
var _audio_enabled := false
var _accepted_trim: Dictionary = {}
var _engine_volume := 1.0
var _show_labels := false
var _label_distance_m := 250.0
var _traffic_label: Label3D


func configure(player: Node, field: Dictionary, slot: int, count: int, seed_value: int,
		visuals: bool, audio_enabled: bool, qualification: Dictionary = {}) -> Dictionary:
	slot_id = slot
	name = "Companion%d" % (slot + 1)
	session = Flight.new()
	session.setup(Catalog.entry(Catalog.DEFAULT_ID).data, Catalog.DEFAULT_ID)
	if not session.aircraft.get("ok", false) or not session.set_field(field) \
			or not session.set_lake_context(player.lake_context()) \
			or not session.set_collision_world(player.collision_world()):
		return _refuse("Companion aircraft or field configuration failed.")
	# The manager validates the profile once per launch; direct fixtures validate here.
	if qualification.is_empty():
		qualification = Profiles.load_profile(Catalog.DEFAULT_ID, session.aircraft.input_identity, field)
	if not qualification.get("ok", false):
		return _refuse("; ".join(qualification.get("errors", PackedStringArray(["Companion profile was refused."]))))
	var identity: Dictionary = qualification.get("identity", {})
	if identity.get("aircraft_data_sha256") != session.aircraft.input_identity.get("sha256") \
			or identity.get("aircraft_data_format") != session.aircraft.input_identity.get("format"):
		return _refuse("Companion session data differs from the qualified aircraft.")
	var weather: Dictionary = player.weather_configuration().duplicate(true)
	# Independent aircraft turbulence; the common mean/gust profile keeps the same launch clock.
	if weather.has("turbulence_seed"):
		weather.turbulence_seed = (int(weather.turbulence_seed) + seed_value + slot * 104729) & 0xffffffff
	if not session.setup_weather(weather):
		return _refuse(session.weather_error)
	_weather_rms = PackedFloat64Array(weather.get("turbulence_rms_mps", [0.0, 0.0, 0.0]))
	session.reset()
	if not session.configure_external_driver():
		return _refuse("Controllerless companion session was refused.")
	session.crash_auto_restart = false
	pilot = Pilot.new()
	var trim: Dictionary = session.trims.duplicate()
	trim.throttle = float(session.start.throttle)
	trim.speed_m_s = float(session.start.get("V", 15.0))
	_accepted_trim = trim.duplicate()
	if not pilot.configure(slot, count, seed_value, trim, field):
		return _refuse(pilot.configure_error)
	var pose: Dictionary = pilot.initial_pose()
	if not session.external_spawn_airborne(float(pose.north), float(pose.east),
			float(pose.height_agl_m), float(pose.heading_rad)):
		return _refuse("Companion launch pose was refused.")
	add_child(session)
	if visuals:
		view = Builder.build(Catalog.DEFAULT_ID)
		if view.is_empty():
			return _refuse("Companion model bindings failed.")
		add_child(view.root)
		var datum: Vector2 = Builder.datum(Catalog.DEFAULT_ID)
		_cg_model = Frames.cg_in_model_frame(session.aircraft.model.cg_le, datum.x, datum.y)
		_audio_enabled = audio_enabled
		render(0.0, true)
	return {ok = true, errors = PackedStringArray()}


func _ready() -> void:
	if _audio_enabled and not view.is_empty():
		_engine = EngineSound.create(view.root, session.sim, EngineSound.reference_rpm(session.aircraft.model.propulsion))
		_engine.max_distance = 450.0
		_apply_engine_volume()


## Cosmetic configuration only; the manager validates values before this boundary.
func apply_presentation(settings: Dictionary) -> void:
	_engine_volume = float(settings.engine_volume)
	_show_labels = bool(settings.show_labels)
	_label_distance_m = float(settings.label_distance_m)
	_apply_engine_volume()
	if _show_labels and not view.is_empty() and _traffic_label == null:
		_traffic_label = Label3D.new()
		_traffic_label.name = "TrafficLabel"
		_traffic_label.text = tr("Companion %d") % (slot_id + 1)
		_traffic_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_traffic_label.fixed_size = true
		_traffic_label.font_size = 24
		_traffic_label.pixel_size = 0.0014
		_traffic_label.outline_size = 4
		_traffic_label.no_depth_test = false
		_traffic_label.visible = false
		add_child(_traffic_label)
	if _traffic_label != null:
		_traffic_label.visible = false # The next render checks camera/distance and stop state.


func _apply_engine_volume() -> void:
	if _engine != null:
		_engine.volume_db = -80.0 if _engine_volume == 0.0 else -15.0 + linear_to_db(_engine_volume)


func _refuse(message: String) -> Dictionary:
	failure = message
	if session != null and session.get_parent() == null:
		session.free()
		session = null
	return {ok = false, errors = PackedStringArray([message])}


func observation() -> Dictionary:
	var state: PackedFloat64Array = session.sim.state.duplicate()
	var wind: PackedFloat64Array = session.wind_at(session.sim.time())
	return {id = "companion-%d" % slot_id, slot = slot_id, state = state,
		airspeed_m_s = ObservationAirdata.airspeed_m_s(state, wind), wind_ned = wind,
		ground_clearance_m = -state[2] - float(session.environment.ground(state[0], state[1])[0]),
		trim = _accepted_trim.duplicate(), turbulence_rms_m_s = _weather_rms.duplicate(), is_player = false}


func needs_command(tick: int) -> bool:
	return failure.is_empty() and session.crash.is_empty() and (tick % 4 == 0 or _last_command.is_empty())


func prepare(snapshot: Dictionary, tick: int, traffic: Array) -> bool:
	if not failure.is_empty() or not session.crash.is_empty():
		return false
	if needs_command(tick):
		var planned: Dictionary = pilot.command(snapshot, tick, traffic)
		if not planned.get("ok", false):
			failure = str(planned.get("reason", "Companion pilot refused this state."))
			return false
		_last_command = {roll = planned.roll, pitch = planned.pitch, yaw = planned.yaw, throttle = planned.throttle}
	var checked: Dictionary = session.prepare_external_tick(_last_command)
	if not checked.ok:
		failure = "; ".join(checked.errors)
		return false
	return true


func advance() -> bool:
	if not failure.is_empty():
		return false
	var result: bool = session.step_external_tick()
	if not session.sim.fault_reason.is_empty():
		failure = "Simulation fault: " + session.sim.fault_reason
	elif not result and session.crash.is_empty():
		failure = "Companion session did not accept the scheduled tick."
	return result


func render(delta: float, frozen: bool) -> void:
	if view.is_empty():
		return
	var stopped: bool = frozen or not failure.is_empty() or not session.crash.is_empty()
	var state: PackedFloat64Array = session.sim.interpolated(Engine.get_physics_interpolation_fraction())
	var pose: Vector3 = Frames.ned_to_render([state[0], state[1], state[2]])
	view.root.transform = Frames.root_transform(Frames.quat_to_render(state.slice(6, 10)), pose, _cg_model)
	if _traffic_label != null:
		_traffic_label.position = pose + Vector3.UP * 2.0
		var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
		_traffic_label.visible = _show_labels and failure.is_empty() and session.crash.is_empty() \
			and camera != null and camera.global_position.distance_squared_to(pose) <= _label_distance_m * _label_distance_m
	if not stopped:
		_prop_angle = fposmod(_prop_angle + TAU * float(session.sim.aux[0]) / 60.0 * minf(delta, 0.1), TAU)
	view.propeller.rotation.z = _prop_angle * float(view.get("propeller_spin_sign", 1.0))
	Builder.apply_controls(view, ControlSurfaces.hinge_rotations_from_surfaces(session.surface_angles_deg()), float(session.commands.throttle))
	if _engine != null:
		_engine.stream_paused = stopped or _engine_volume == 0.0
		if not stopped and _engine_volume > 0.0 and _engine.playing:
			EngineSound.update(_engine, 0.0, float(session.sim.aux[0]), EngineSound.reference_rpm(session.aircraft.model.propulsion))


func _exit_tree() -> void:
	if _engine != null:
		_engine.stop()

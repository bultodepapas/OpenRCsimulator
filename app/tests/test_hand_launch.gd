# X8-07: the hand launch. Gearless airplanes only; a helper's throw from the runway edge into the wind, motor at full
# throttle; refusals fail closed (never an airborne fallback); a restart repeats the release exactly.
# Run: godot --headless --path . --script res://tests/test_hand_launch.gd
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const Weather := preload("res://physics/wind_config.gd")
const Propulsion := preload("res://physics/propulsion.gd")

const X8 := "skywalker-x8"
const HANDS_OFF_S := 4.0

var _checks: int = 0
var _failures: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, "  ", detail)


func _session(id: String, field: Dictionary, weather: Dictionary, trim_throttle: float) -> Node:
	var session: Node = Session.new()
	session.start_choice = Session.START_HAND_LAUNCH
	session.input_enabled = false
	session.crash_auto_restart = false
	session.trim_throttle = trim_throttle
	session.setup(Catalog.entry(id).data, id)
	root.add_child(session)
	if not field.is_empty():
		_check(id + " field installs", session.set_field(field))
	_check(id + " weather installs", session.setup_weather(weather), session.weather_error)
	session.reset()
	return session


func _wind(speed: float, from_deg: float) -> Dictionary:
	var weather: Dictionary = Weather.defaults()
	weather.speed_mps = speed
	weather.from_deg = from_deg
	return weather


func _initialize() -> void:
	var field: Dictionary = FieldLoader.load_from().field
	_check("default field loads", not field.is_empty())
	_support()
	_release_geometry(field)
	for trim_throttle: float in [Session.CRUISE_TRIM_THROTTLE, NAN]:
		for weather: Dictionary in [Weather.defaults(), Weather.GENTLE_PRACTICE, _wind(4.0, 270.0), _wind(4.0, 0.0)]:
			_launch(field, weather, trim_throttle)
	_dead_motor(field)
	_refusals(field)
	print("X8-07 hand launch: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _support() -> void:
	var offered := PackedStringArray()
	for id: String in Catalog.ids():
		if Session.hand_launch_aircraft_supported(id):
			offered.append(id)
		_check(id + " never offers both ground starts", not (Session.hand_launch_aircraft_supported(id) and Session.runway_aircraft_supported(id)))
		_check(id + " catalog cache agrees", Catalog.hand_launch_supported(id) == Session.hand_launch_aircraft_supported(id))
	_check("only the gearless X8 is hand-launched", offered == PackedStringArray([X8]), str(offered))


func _release_geometry(field: Dictionary) -> void:
	var calm: Dictionary = Session.hand_launch_release(field, PackedFloat64Array([0.0, 0.0, 0.0]))
	_check("calm release at the runway edge in front of the pilot, east-bound", calm.ok and calm.north == 9.0
		and calm.east == 0.0 and calm.heading == PI / 2.0, str(calm))
	var westerly: Dictionary = Session.hand_launch_release(field, PackedFloat64Array([0.0, 3.0, 0.0]))
	_check("air moving east turns the throw west, into the wind", westerly.ok and westerly.heading == -PI / 2.0
		and westerly.north == 9.0 and westerly.east == 0.0, str(westerly))
	var easterly: Dictionary = Session.hand_launch_release(field, PackedFloat64Array([0.0, -3.0, 0.0]))
	_check("air moving west keeps the throw east, into the wind", easterly.ok and easterly.heading == PI / 2.0)
	var crosswind: Dictionary = Session.hand_launch_release(field, PackedFloat64Array([-4.0, 0.0, 0.0]))
	_check("a pure crosswind keeps the east-bound throw", crosswind.ok and crosswind.heading == PI / 2.0)
	var far_pilot: Dictionary = field.duplicate(true)
	far_pilot.pilot.east = 500.0
	var clamped: Dictionary = Session.hand_launch_release(far_pilot, PackedFloat64Array([0.0, 0.0, 0.0]))
	_check("a pilot beyond the runway end throws from its nearest corner", clamped.ok and clamped.east == 50.0, str(clamped))
	var no_runway: Dictionary = field.duplicate(true)
	no_runway.surfaces = no_runway.surfaces.filter(func(s: Dictionary) -> bool: return s.type != "runway")
	_check("a field without its runway refuses", not Session.hand_launch_release(no_runway, PackedFloat64Array([0.0, 0.0, 0.0])).ok)
	_check("a non-finite wind refuses", not Session.hand_launch_release(field, PackedFloat64Array([0.0, NAN, 0.0])).ok)


func _launch(field: Dictionary, weather: Dictionary, trim_throttle: float) -> void:
	var label: String = "X8 %s m/s from %s°, trim %s" % [str(weather.speed_mps), str(weather.from_deg), "50%" if is_finite(trim_throttle) else "reference"]
	var session: Node = _session(X8, field, weather, trim_throttle)
	_check(label + ": launches", session.start_error.is_empty() and session.is_flyable() and not session.sim.paused
		and session.sim.tick == 0, session.start_error)
	var meta: Dictionary = session.trace_meta()
	_check(label + ": launch metadata", meta.selected_start_choice == Session.START_HAND_LAUNCH
		and meta.launch_choice == Session.START_HAND_LAUNCH and meta.launch_kind == "hand_launch_release"
		and meta.launch_field_id == "default" and meta.launch_error == "" and meta.launch_engine_running == "true", str(meta))
	var s: PackedFloat64Array = session.sim.state.duplicate()
	var release: Dictionary = Session.hand_launch_release(field, session._weather.sample(0.0))
	var ground: float = session.environment.terrain(release.north, release.east)[0]
	_check(label + ": released at shoulder height over the runway edge", s[RB.POS] == release.north and s[RB.POS + 1] == release.east
		and absf(-s[RB.POS + 2] - ground - Session.HAND_LAUNCH_RELEASE_HEIGHT_M) < 1e-12)
	var ground_speed: float = M.norm(M.v3(s[RB.VEL], s[RB.VEL + 1], s[RB.VEL + 2]))
	_check(label + ": the throw speed is ground-relative", absf(ground_speed - Session.HAND_LAUNCH_SPEED_MPS) < 1e-12, str(ground_speed))
	var euler: PackedFloat64Array = M.q_to_euler(M.quat(s[RB.ATT], s[RB.ATT + 1], s[RB.ATT + 2], s[RB.ATT + 3]))
	_check(label + ": wings level, body along the throw, nose up by the throw angle, heading along the throw",
		absf(euler[2]) < 1e-12 and absf(euler[1] - Session.HAND_LAUNCH_CLIMB_RAD) < 1e-9
		and absf(wrapf(euler[0] - release.heading, -PI, PI)) < 1e-9, str(euler))
	_check(label + ": no rotation at release", s[RB.RATE] == 0.0 and s[RB.RATE + 1] == 0.0 and s[RB.RATE + 2] == 0.0)
	var air: Dictionary = session.air_data(s, 0.0)
	var wind: PackedFloat64Array = session._weather.sample(0.0)
	var headwind: float = -(wind[0] * cos(release.heading) + wind[1] * sin(release.heading))
	var ground_ned: PackedFloat64Array = M.q_rotate(M.quat(s[RB.ATT], s[RB.ATT + 1], s[RB.ATT + 2], s[RB.ATT + 3]), M.v3(s[RB.VEL], s[RB.VEL + 1], s[RB.VEL + 2]))
	var expected_air: float = M.norm(M.v3(ground_ned[0] - wind[0], ground_ned[1] - wind[1], ground_ned[2] - wind[2]))
	# Turbulence at release is the only difference (GENTLE_PRACTICE rms 0.15 m/s).
	_check(label + ": airspeed is the throw relative to the mean wind, never a tailwind", absf(air.V - expected_air) < 0.35
		and headwind >= 0.0, "V %.3f expected %.3f headwind %.3f" % [air.V, expected_air, headwind])
	_check(label + ": full throttle, motor already at its full-throttle speed, pilot trim kept",
		session.commands.throttle == Session.HAND_LAUNCH_THROTTLE and session.engine_running
		and session.sim.aux[0] > float(session.start.rpm) and session.trims.pitch == session.start.pitch_command
		and session.trims.roll == session.start.roll_command)
	var restart_state: PackedFloat64Array = s
	var min_height: float = INF
	var min_speed: float = INF
	var climbed: float = 0.0
	for _tick: int in int(HANDS_OFF_S * 240.0):
		# The product tick order: the session's contact and crash gate, then the step.
		if not session._session_after_input():
			break
		session.sim.step()
		var height: float = -session.sim.state[RB.POS + 2] - ground
		min_height = minf(min_height, height)
		min_speed = minf(min_speed, float(session.air_data(session.sim.state).V))
		climbed = height
	_check(label + ": climbs away hands-off without touching the ground", session.crash.is_empty() and session.sim.fault_reason.is_empty()
		and min_height > Session.HAND_LAUNCH_RELEASE_HEIGHT_M - 0.3 and climbed > Session.HAND_LAUNCH_RELEASE_HEIGHT_M + 5.0,
		"crash %s min height %.2f m, height %.2f m after %.0f s" % [str(session.crash), min_height, climbed, HANDS_OFF_S])
	print("%s: min height %.2f m, min airspeed %.2f m/s, height %.2f m after %.0f s" % [label, min_height, min_speed, climbed, HANDS_OFF_S])
	session.reset()
	_check(label + ": restart repeats the release exactly", session.sim.state == restart_state and session.sim.tick == 0
		and session.trace_meta().launch_kind == "hand_launch_release")
	session.free()


## Negative control: the same calm release with the motor stopped stalls into the ground. Full power is what lets a
## 3.1 kg wing leave a 6.5 m/s throw (docs/research/skywalker-x8/X8-07/README.md); the hands-off checks above can fail.
func _dead_motor(field: Dictionary) -> void:
	var session: Node = _session(X8, field, Weather.defaults(), Session.CRUISE_TRIM_THROTTLE)
	session.commands.throttle = 0.0
	session.engine_running = false
	session.sim.inputs = session._inputs()
	var aux: PackedFloat64Array = session.sim.aux
	aux[0] = 0.0
	session.sim.aux = aux
	var release: PackedFloat64Array = session.sim.state.duplicate()
	session.sim.continuous = session._settled_continuous(release, aux)
	_check("dead-motor control resets", session.sim.reset(release))
	var crashed_at: float = INF
	for tick: int in int(HANDS_OFF_S * 240.0):
		if not session._session_after_input():
			crashed_at = tick / 240.0
			break
		session.sim.step()
	_check("a dead-motor release crashes within 2 s", not session.crash.is_empty() and crashed_at < 2.0, "crash %s at %.2f s" % [str(session.crash), crashed_at])
	session.free()


func _refusals(field: Dictionary) -> void:
	var stik: Node = _session(Catalog.DEFAULT_ID, field, Weather.defaults(), Session.CRUISE_TRIM_THROTTLE)
	_check("a geared airplane refuses the hand launch without an airborne fallback", not stik.is_flyable() and stik.sim.paused
		and stik.start_error.contains("without landing gear") and stik.trace_meta().launch_choice == "failed", stik.start_error)
	stik.free()
	var fieldless: Node = _session(X8, {}, Weather.defaults(), Session.CRUISE_TRIM_THROTTLE)
	_check("the hand launch needs a loaded field", not fieldless.is_flyable() and fieldless.sim.paused
		and fieldless.start_error.contains("field") and fieldless.trace_meta().launch_choice == "failed", fieldless.start_error)
	fieldless.free()

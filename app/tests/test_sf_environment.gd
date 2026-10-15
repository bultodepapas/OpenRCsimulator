# SF-07: one environment contract (sim/environment.gd) for every vehicle session. Each session exposes it, its
# legacy queries are views of it, the providers answer identically through it, and a uniform wind is Galilean
# through the contract. Structure and identity checks; trajectories are proven unchanged by the fleet fingerprints.
extends SceneTree

const SimEnvironment := preload("res://sim/environment.gd")
const WeatherField := preload("res://physics/wind_field.gd")
const WeatherConfig := preload("res://physics/wind_config.gd")
const Terrain := preload("res://physics/ground_terrain.gd")
const Air := preload("res://physics/air_data.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const HeliSession := preload("res://sim/helicopter_flight_session.gd")
const GroundSession := preload("res://sim/ground_vehicle/session.gd")
const AircraftCatalog := preload("res://app_state/aircraft_catalog.gd")
const Field := preload("res://data/field_loader.gd")

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_contract_alone()
	_fixed_wing()
	_helicopter()
	_ground_vehicle()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


## A complete openrc-weather v1 record with the given changes.
func _weather(changes: Dictionary) -> Dictionary:
	var result: Dictionary = WeatherConfig.defaults()
	for key: Variant in changes:
		result[key] = changes[key]
	return result


func _contract_alone() -> void:
	var env := SimEnvironment.new()
	var built: Dictionary = WeatherField.build(_weather({ "speed_mps": 3.0, "from_deg": 270.0 }))
	_check("a steady wind builds", built.ok, str(built.errors))
	env.weather = built.field
	var calm_bytes: PackedByteArray = env.weather.sample(1.0).to_byte_array()
	_check("without a turbulence callback the wind is the weather sample byte for byte", env.wind(1.0).to_byte_array() == calm_bytes)
	env.turbulence = func(_t: float) -> PackedFloat64Array: return PackedFloat64Array()
	_check("an empty turbulence sample adds nothing, keeping the exact bytes", env.wind(1.0).to_byte_array() == calm_bytes)
	env.turbulence = func(_t: float) -> PackedFloat64Array: return PackedFloat64Array([0.5, -0.25, 0.125])
	var gusty: PackedFloat64Array = env.wind(1.0)
	var base: PackedFloat64Array = env.weather.sample(1.0)
	_check("a turbulence sample is added axis by axis", gusty[0] == base[0] + 0.5 and gusty[1] == base[1] - 0.25 and gusty[2] == base[2] + 0.125)
	_check("air queries delegate to the weather law", env.air_density(0.0) == env.weather.air_density(0.0) and env.air(0.0) == env.weather.atmosphere(0.0))
	_check("without a surface table the terrain is flat at height zero", env.terrain(12.0, -3.0)[0] == 0.0 and env.ground_max_height() == 0.0)
	_check("without a lake or course those queries are empty", env.water(0.0, 0.0).is_empty() and env.course(0.0, 0.0).is_empty())
	var identity: Dictionary = env.identity()
	_check("identity summarizes the installed providers", identity.weather == env.weather.configuration() and identity.turbulence and identity.lake == "" and not identity.course)
	# Galilean invariance through the contract: a body moving with the wind sees calm air.
	var state := RB.make_state(M.v3(0.0, 0.0, -50.0), M.v3(15.0, 0.0, 0.0), M.q_identity(), M.v3(0.0, 0.0, 0.0))
	env.turbulence = Callable()
	var wind: PackedFloat64Array = env.wind(0.0)
	var moving := state.duplicate()
	for i in 3:
		moving[RB.VEL + i] += wind[i] # identity attitude: body axes coincide with NED
	var still_air: Dictionary = Air.compute(state, PackedFloat64Array([0.0, 0.0, 0.0]), env.air_density(-50.0))
	var windy_air: Dictionary = Air.compute(moving, wind, env.air_density(-50.0))
	_check("a uniform wind through the contract is Galilean for the air data", absf(float(still_air.V) - float(windy_air.V)) < 1e-12
		and absf(float(still_air.alpha) - float(windy_air.alpha)) < 1e-12 and absf(float(still_air.beta) - float(windy_air.beta)) < 1e-12)


func _fixed_wing() -> void:
	var session: Node = FlightSession.new()
	session.input_enabled = false
	session.physics_enabled = false
	session.setup(str(AircraftCatalog.entry("jensen-das-ugly-stik-60").data))
	root.add_child(session)
	_check("Stik flies", session.is_flyable(), session.pause_reason)
	if not session.is_flyable():
		session.free()
		return
	var env: SimEnvironment = session.environment
	_check("the session's weather, surfaces and lake are views of its environment", session._weather == env.weather
		and session.ground_surfaces.to_byte_array() == env.surfaces.to_byte_array() and session._lake == env.lake)
	_check("the session installed its turbulence sample", env.turbulence.is_valid())
	var weather_ok: bool = session.setup_weather(_weather({ "speed_mps": 3.0, "from_deg": 270.0 }))
	session.reset()
	_check("a steady wind installs through the session", weather_ok and session.is_flyable(), session.weather_error + " " + session.pause_reason)
	_check("wind_at is the environment's wind", session.wind_at(0.5).to_byte_array() == env.wind(0.5).to_byte_array())
	var s: PackedFloat64Array = session.sim.state
	_check("air density and the atmosphere query answer through the environment", session.air_density(s) == env.air_density(s[RB.POS + 2])
		and session.environment_at(s) == env.air(s[RB.POS + 2]))
	var field: Dictionary = Field.load_from(Field.DEFAULT_PATH)
	_check("default field loads", field.ok)
	var before: String = str(env.identity().surfaces_sha256)
	_check("installing the field changes the environment's surface identity", field.ok and session.set_field(field.field) and str(env.identity().surfaces_sha256) != before)
	_check("the terrain query is the surface table's sample", env.terrain(6.0, 1.0).to_byte_array() == Terrain.sample_validated(6.0, 1.0, session.ground_surfaces).to_byte_array())
	session.sim.step()
	_check("a windy tick steps", session.sim.fault_reason.is_empty(), session.sim.fault_reason)
	session.free()


func _helicopter() -> void:
	var session: Node = HeliSession.new()
	session.input_enabled = false
	session.physics_enabled = false
	root.add_child(session)
	_check("helicopter prepares", session.setup() and session.reset(), session.start_error)
	var env: SimEnvironment = session.environment
	_check("the helicopter's weather and surfaces are views of its environment", session._weather == env.weather
		and session.ground_surfaces.to_byte_array() == env.surfaces.to_byte_array())
	_check("wind_at and air_density answer through the environment", session.wind_at(0.0).to_byte_array() == env.wind(0.0).to_byte_array()
		and session.air_density() == env.air_density())
	session.sim.step()
	_check("a helicopter tick steps", session.sim.fault_reason.is_empty(), session.sim.fault_reason)
	session.free()


func _ground_vehicle() -> void:
	var session: Node = GroundSession.new()
	root.add_child(session)
	_check("truck prepares", session.prepare_default(), session.load_error)
	var env: SimEnvironment = session.environment
	_check("the course sampler is the environment's road and gravity is the model's", env.road.is_valid() and env.gravity == float(session._model.gravity_m_per_s2))
	var spawn: PackedFloat64Array = session.state_snapshot()
	var direct: Dictionary = session._road.call(spawn[0], spawn[1])
	_check("the course query answers like the installed road and is deterministic", env.course(spawn[0], spawn[1]) == direct and env.course(spawn[0] + 0.3, spawn[1] - 0.2) == session._road.call(spawn[0] + 0.3, spawn[1] - 0.2))
	_check("the truck's identity reports a course and no weather turbulence", env.identity().course and not env.identity().turbulence)
	session.free()

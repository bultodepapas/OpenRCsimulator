## M5-ATM-4 / VAL-AUD-R09: stage position, family adapters, trace timing and lifecycle.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Heli := preload("res://sim/helicopter_flight_session.gd")
const Config := preload("res://physics/wind_config.gd")
const Atmosphere := preload("res://physics/atmosphere.gd")
const Recorder := preload("res://sim/recorder.gd")
const Preferences := preload("res://app_state/preferences.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const PATHS := ["jensen_ugly_stik_60", "sebart_avanti_s_a200", "p51d_mustang_120", "turbo_lumber_evolution", "stik_glow_61fx_2t"]

var checks := 0
var failures := 0

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	for path in PATHS:
		_stage_equivalence(path)
	_climb_trace_restore()
	_runway_and_domain()
	_preferences_and_family_guard()
	print("M5-ATM-4 session: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func column() -> Dictionary:
	return Config.upgrade_column(Config.defaults(), {atmosphere_mode = "standard_column"})

func flight(path: String, config: Dictionary) -> Flight:
	var s := Flight.new()
	s.input_enabled = false
	s.crash_auto_restart = false
	check(path + " weather prepares", s.setup_weather(config))
	s.setup("res://data/aircraft/" + path + ".json")
	if path == "p51d_mustang_120":
		check("coupled shaft selects", s.setup_shaft_integrator("coupled-rk4"))
		s.reset()
	check(path + " starts", s.is_flyable())
	return s

func _stage(s: Flight, body: PackedFloat64Array) -> Dictionary:
	if s.sim.continuous_evaluate.is_valid():
		return s.sim.continuous_evaluate.call(body, s.sim.continuous, 0.0)
	return {loads = s.sim.loads.call(body, 0.0)}

func _near(a: PackedFloat64Array, b: PackedFloat64Array) -> bool:
	if a.size() != b.size(): return false
	for i in a.size():
		if not is_finite(a[i]) or not is_finite(b[i]) or absf(a[i] - b[i]) > 1e-10 * (1.0 + absf(b[i])):
			return false
	return true

func _stage_equivalence(path: String) -> void:
	var s := flight(path, column())
	# Independent reference values use the dry standard-column table retained with the kernel tests.
	var reference_temperature := 281.651022371695
	var uniform := Config.upgrade_atmosphere(Config.defaults(), {atmosphere_mode = "custom",
		field_elevation_m = 1000.0, temperature_c = reference_temperature - 273.15, relative_humidity_pct = 0.0})
	var control := flight(path, uniform)
	var body: PackedFloat64Array = s.sim.state.duplicate()
	body[RB.POS + 2] = -1000.0
	body[RB.RATE] = 0.13
	body[RB.RATE + 1] = -0.09
	body[RB.RATE + 2] = 0.17
	var endpoint_density: float = s.air_density()
	check(path + " explicit stage density differs from accepted endpoint", absf(s.air_density(body) - endpoint_density) > 0.1)
	check(path + " actual geometric altitude reaches table density", absf(s.air_density(body) - 1.11165967369969) < 1e-13)
	var air: Dictionary = s.air_data(body, 0.0)
	check(path + " air data pressure uses stage density", absf(air.qbar - 0.5 * 1.11165967369969 * air.V * air.V) < 1e-9)
	# Same stage body, controls, shaft/fuel/wheel state. Only the environment provider differs:
	# column sampled at the stage versus an independently configured uniform field of equal p/T.
	control.sim.inputs = s.sim.inputs.duplicate()
	control.sim.aux = s.sim.aux.duplicate()
	control.sim.continuous = s.sim.continuous.duplicate()
	control.sim.modes = s.sim.modes.duplicate()
	var actual := _stage(s, body)
	var expected := _stage(control, body)
	check(path + " stage evaluator produces valid loads", actual.has("loads") and expected.has("loads"))
	if actual.has("loads") and expected.has("loads"):
		check(path + " all stage loads match matched uniform p/T", _near(actual.loads, expected.loads))
		for key in ["derivative", "body_derivative", "rotor_momentum"]:
			if expected.has(key):
				check(path + " stage " + key + " matches matched uniform p/T", actual.has(key) and _near(actual[key], expected[key]))
	check(path + " pure stage query does not move accepted body", s.sim.state[RB.POS + 2] == -30.0 and s.air_density() == endpoint_density)
	control.free()
	s.free()

func _climb_trace_restore() -> void:
	var s := flight(PATHS[0], column())
	s.set_start_altitude(1000.0)
	s.reset()
	check("altitude reset re-trims at the start height", s.is_flyable() and absf(s.air_density() - 1.11165967369969) < 1e-13)
	var derivative: PackedFloat64Array = RB.derivative(s.sim.state, s.sim.mass, s.sim.inertia, RB.inertia_inverse(s.sim.inertia),
		s.sim.last_loads.slice(0, 3), s.sim.last_loads.slice(3, 6), s.sim.gravity, s.rotor_momentum(s.sim.aux))
	var residual := 0.0
	for i in [3, 4, 5, 10, 11, 12]: residual = maxf(residual, absf(derivative[i]))
	check("column reset has six-axis equilibrium at altitude", residual < 1e-8)
	var body: PackedFloat64Array = s.sim.state.duplicate()
	body[RB.VEL + 2] -= 4.0
	check("climb scenario resets", s.sim.reset(body))
	var initial := s.checkpoint()
	var r := Recorder.new(s.sim)
	r.start(s.trace_meta())
	var densities := PackedFloat64Array([s.air_density()])
	for tick in 120:
		s.sim.step()
		densities.append(s.air_density())
	check("column climb completes", s.sim.tick == 120 and s.sim.fault_reason.is_empty())
	check("density changes during climb", densities[120] < densities[0] - 1e-5)
	check("column trace version is explicit", r.trace.to_csv().begins_with("# format: openrc-trace v11\n"))
	check("column trace records every accepted row", r.trace.row_count() == 121)
	if r.trace.row_count() == 121:
		check("trace endpoint density is current", r.trace.value(120, "rho_kgm3") == densities[120])
		check("trace force density belongs to k1, not endpoint", r.trace.value(120, "loads_rho_kgm3") == densities[119])
		check("trace geometric altitude uses field datum", r.trace.value(120, "geometric_altitude_m") == -s.sim.state[2])
	r.detach()
	var saved := s.checkpoint()
	check("checkpoint pins column law", saved.get("atmosphere_law") == Atmosphere.STANDARD_COLUMN_LAW)
	var replay := flight(PATHS[0], Config.defaults())
	check("fresh reference session accepts column checkpoint", replay.restore_checkpoint(saved))
	for tick in 60:
		s.sim.step()
		replay.sim.step()
	check("column checkpoint continuation is byte exact", var_to_bytes(s.checkpoint()) == var_to_bytes(replay.checkpoint()))
	var intact := var_to_bytes(replay.checkpoint())
	for defect in ["law", "altitude", "version"]:
		var broken: Dictionary = saved.duplicate(true)
		if defect == "law": broken.atmosphere_law = "unknown-column"
		if defect == "altitude": broken.simulation.state[2] = -11001.0
		if defect == "version": broken.weather_config.format = Config.ATMOSPHERE_FORMAT
		check("reject column " + defect + " before mutation", not replay.restore_checkpoint(broken) and var_to_bytes(replay.checkpoint()) == intact)
	# Recorder must be read-only. Replay the identical initial checkpoint without observers.
	check("observer-off reset restores", replay.restore_checkpoint(initial))
	for tick in 120: replay.sim.step()
	check("observer on/off leaves identical physical state", var_to_bytes(replay.checkpoint()) == var_to_bytes(saved))
	replay.free()
	s.free()

func _runway_and_domain() -> void:
	var s := flight(PATHS[1], column())
	var started: Dictionary = s.try_runway_start(0.0, 0.0, PI / 2.0)
	check("column runway solves", started.get("ok", false))
	if started.get("ok", false):
		var origin: PackedFloat64Array = s.sim.state.slice(0, 3)
		for tick in 480: s.sim.step()
		check("column runway remains stationary for two seconds", s.sim.fault_reason.is_empty() and M.norm(M.sub(origin, s.sim.state.slice(0, 3))) < 1e-7)
	var sample: PackedFloat64Array = s.sim.state.duplicate()
	sample[2] = -11001.0
	check("out-of-domain stage density fails explicitly", is_nan(s.air_density(sample)) and not s.environment_at(sample).ok)
	var tick: int = s.sim.tick
	var previous: PackedByteArray = s.sim.state.to_byte_array()
	check("out-of-domain reset refuses invalid state", not s.sim.reset(sample))
	check("rejected domain reset preserves accepted physical state", s.sim.tick == tick and s.sim.state.to_byte_array() == previous)
	s.free()

func _preferences_and_family_guard() -> void:
	var directory := ProjectSettings.globalize_path("res://../tmp/atmosphere-column-prefs-%d" % OS.get_process_id())
	var path := directory.path_join("preferences.cfg")
	check("column preference fixture directory prepares", DirAccess.make_dir_recursive_absolute(directory) == OK)
	var prefs: Dictionary = Preferences.DEFAULTS.duplicate(true)
	prefs.weather_config = column()
	check("column preferences save", Preferences.save_to(path, prefs) == OK)
	var config := ConfigFile.new()
	check("column preferences advertise new schema", config.load(path) == OK and config.get_value("meta", "schema") == 5)
	check("column preference round trip", Preferences.load_from(path).weather_config == column())
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory)
	var h := Heli.new()
	check("rotorcraft cannot silently adopt fixed-wing column", not h.setup_weather(column()) and h.weather_error.contains("vertical atmosphere"))
	h.free()

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
	if s.sim.model.stage.is_valid():
		return s.sim.model.stage.call(body, s.sim.continuous, 0.0)
	return {loads = s.sim.model.loads.call(body, 0.0)}

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
	# The source-off glow installation is the stationary oracle. Its turbine counterpart burns at idle; fuel-mass
	# changes legitimately settle a compliant suspension by a few micrometres during the same interval.
	var parked := flight(PATHS[4], column())
	var parked_start: Dictionary = parked.try_runway_start(0.0, 0.0, PI / 2.0)
	check("column parked runway solves with source off", parked_start.get("ok", false) and not parked.engine_running)
	if parked_start.get("ok", false):
		var parked_origin: PackedFloat64Array = parked.sim.state.slice(0, 3)
		var parked_fuel: float = parked.mass_properties().fuel_remaining_kg
		for _tick in 480: parked.sim.step()
		var parked_end_fuel: float = parked.mass_properties().fuel_remaining_kg
		check("column parked runway holds still for two seconds", parked.sim.fault_reason.is_empty() and
			M.norm(M.sub(parked_origin, parked.sim.state.slice(0, 3))) < 1e-7)
		check("column parked source-off fuel remains unchanged", parked_fuel == parked_end_fuel)
	parked.free()

	# Compare a running finite turbine in the column against a uniform dry-ISA atmosphere matched at its runway start.
	# The 1e-4 m absolute drift bound is a numerical comparison guard for compliant gear, not physical validation.
	var running_column := flight(PATHS[1], column())
	var column_start: Dictionary = running_column.try_runway_start(0.0, 0.0, PI / 2.0)
	check("column finite turbine runway solves", column_start.get("ok", false) and running_column.liquid_fuel_is_active())
	var matched_sample: Dictionary = running_column.environment_at(running_column.sim.state)
	var matched_uniform := Config.upgrade_atmosphere(Config.defaults(), {
		atmosphere_mode = "custom",
		field_elevation_m = -running_column.sim.state[2],
		temperature_c = float(matched_sample.temperature_k) - 273.15,
		qnh_hpa = 1013.25,
		relative_humidity_pct = 0.0,
	})
	var running_uniform := flight(PATHS[1], matched_uniform)
	var uniform_start: Dictionary = running_uniform.try_runway_start(0.0, 0.0, PI / 2.0)
	check("matched uniform finite turbine runway solves", uniform_start.get("ok", false) and running_uniform.liquid_fuel_is_active())
	if column_start.get("ok", false) and uniform_start.get("ok", false):
		check("column and uniform start densities match", absf(running_column.air_density() - running_uniform.air_density()) < 1e-9)
		var column_origin: PackedFloat64Array = running_column.sim.state.slice(0, 3)
		var uniform_origin: PackedFloat64Array = running_uniform.sim.state.slice(0, 3)
		var column_fuel_before: float = running_column.mass_properties().fuel_remaining_kg
		var uniform_fuel_before: float = running_uniform.mass_properties().fuel_remaining_kg
		for _tick in 480:
			running_column.sim.step()
			running_uniform.sim.step()
		var column_drift: PackedFloat64Array = M.sub(running_column.sim.state.slice(0, 3), column_origin)
		var uniform_drift: PackedFloat64Array = M.sub(running_uniform.sim.state.slice(0, 3), uniform_origin)
		var column_burn: float = column_fuel_before - running_column.mass_properties().fuel_remaining_kg
		var uniform_burn: float = uniform_fuel_before - running_uniform.mass_properties().fuel_remaining_kg
		check("running column and uniform sessions complete without faults", running_column.sim.fault_reason.is_empty() and running_uniform.sim.fault_reason.is_empty())
		check("running finite stores burn at idle", column_burn > 0.0 and uniform_burn > 0.0)
		check("matched finite stores burn equivalently", absf(column_burn - uniform_burn) < 1e-8)
		check("matched column and uniform runway drift agree", M.norm(M.sub(column_drift, uniform_drift)) < 1e-7)
		check("finite-fuel compliant-gear drift stays within numerical bound", M.norm(column_drift) < 1e-4 and M.norm(uniform_drift) < 1e-4)
	running_uniform.free()
	running_column.free()
	var s := flight(PATHS[1], column())
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

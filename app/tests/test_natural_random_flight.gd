# NR-03 numerical qualification: generated recipe/session matrix, finite traces and replay.
extends SceneTree

const NaturalRandom := preload("res://scenarios/natural_random.gd")
const ScenarioConfig := preload("res://scenarios/scenario_config.gd")
const AircraftCatalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const WindField := preload("res://physics/wind_field.gd")
const Turbulence := preload("res://physics/wind_turbulence.gd")
const Sim := preload("res://sim/simulation.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

const AIRCRAFT_IDS := [
	"jensen-das-ugly-stik-60",
	"gp-extra-300s-60",
	"p51d-mustang-120",
	"sebart-avanti-s-a200-p100rx",
	"turbo-lumber-evolution",
]
const RECIPE_IDS := ["calm_air", "gentle_breeze", "lively_afternoon", "windy_day"]
const SEED_SEARCH_LIMIT := 65536
const MATRIX_SECONDS := 1.0
const REPLAY_SECONDS := 5.0
const GUST_PERIOD_ONLY_FLAG := "--gust-period"
const REPLAY_AIRCRAFT_ID := "p51d-mustang-120"
const REPLAY_RECIPE_ID := "windy_day"

var _checks := 0
var _failures := 0
var _policy: Dictionary = {}


func _check(label: String, passed: bool, detail := "") -> void:
	_checks += 1
	print(("ok   " if passed else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))
	if not passed:
		_failures += 1


func _finite_array(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true


func _max_vector_error(left: PackedFloat64Array, right: PackedFloat64Array) -> float:
	if left.size() != 3 or right.size() != 3:
		return INF
	var maximum := 0.0
	for axis in 3:
		if not is_finite(left[axis]) or not is_finite(right[axis]):
			return INF
		maximum = maxf(maximum, absf(left[axis] - right[axis]))
	return maximum


func _key(aircraft_id: String, recipe_id: String) -> String:
	return aircraft_id + "|" + recipe_id


func _find_matrix_seeds() -> Dictionary:
	var selected: Dictionary = {}
	for seed: int in range(SEED_SEARCH_LIMIT):
		var generated: Dictionary = NaturalRandom.generate(seed, FieldLoader.DEFAULT_PATH)
		if not generated.get("ok", false):
			_check("generator resolves every searched uint32 seed", false,
				"seed %d: %s" % [seed, str(generated.get("errors", []))])
			return selected
		var candidate: Dictionary = generated.get("scenario", {})
		var aircraft_id := str(candidate.get("aircraft_id", ""))
		var recipe_id := str(candidate.get("recipe_id", ""))
		if AIRCRAFT_IDS.has(aircraft_id) and RECIPE_IDS.has(recipe_id):
			var key := _key(aircraft_id, recipe_id)
			if not selected.has(key):
				var has_gust: bool = float(candidate.weather_config.get("gust_mps", 0.0)) > 0.0 \
					or absf(float(candidate.weather_config.get("gust_up_mps", 0.0))) > 0.0
				if key != _key(REPLAY_AIRCRAFT_ID, REPLAY_RECIPE_ID) or has_gust:
					selected[key] = {seed = seed, scenario = candidate.duplicate(true)}
		if selected.size() == AIRCRAFT_IDS.size() * RECIPE_IDS.size():
			break
	return selected


func _reset_snapshot(session: Node) -> PackedByteArray:
	return var_to_bytes([
		session.start,
		session.trims,
		session.commands,
		session.sim.tick,
		session.sim.time(),
		session.sim.state,
		session.sim.previous,
		session.sim.inputs,
		session.sim.aux,
		session.sim.continuous,
		session.sim.modes,
		session.sim.last_loads,
	])


func _scripted_input(tick: int) -> Dictionary:
	# Small, deterministic stick samples exercise the ordinary trim-plus-pilot input path.
	# They are a software replay fixture, not a controllability or handling acceptance.
	var phase: int = int(tick / Engine.physics_ticks_per_second) % 3
	match phase:
		0:
			return {roll = 0.025, pitch = 0.01, yaw = -0.01, throttle = 0.0}
		1:
			return {roll = -0.025, pitch = -0.01, yaw = 0.01, throttle = 0.0}
		_:
			return {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}


func _new_ranges() -> Dictionary:
	return {
		airspeed_min = INF, airspeed_max = -INF,
		altitude_min = INF, altitude_max = -INF,
		wind_speed_min = INF, wind_speed_max = -INF,
	}


func _range_value(ranges: Dictionary, name: String, value: float) -> void:
	ranges[name + "_min"] = minf(float(ranges[name + "_min"]), value)
	ranges[name + "_max"] = maxf(float(ranges[name + "_max"]), value)


func _daylight_record(daylight_id: String) -> Dictionary:
	for record_value: Variant in _policy.get("daylight", []):
		if typeof(record_value) == TYPE_DICTIONARY and str(record_value.get("id", "")) == daylight_id:
			return record_value
	return {}


func _apply_standalone_weather(session: Node, config: Dictionary, label: String) -> Dictionary:
	var built: Dictionary = WindField.build(config)
	_check("%s passes strict weather validation" % label, built.get("ok", false), str(built.get("errors", [])))
	if not built.get("ok", false):
		return {}
	var accepted: bool = session.setup_weather(config)
	_check("%s is accepted at the real session reset boundary" % label, accepted, session.weather_error)
	if not accepted:
		return {}
	session.reset()
	_check("%s reset has a finite airborne state and positive density" % label,
		Sim.state_is_valid(session.sim.state) and is_finite(session.air_density()) and session.air_density() > 0.0
		and session.start.get("ok", false), session.pause_reason)
	_check("%s session adopts the separately supplied weather" % label,
		session.weather_configuration() == built.field.configuration()
		and is_equal_approx(session.air_density(), built.field.air_density()))
	return built


func _exercise_directional_weather(session: Node, scenario: Dictionary, key: String) -> void:
	var state: PackedFloat64Array = session.sim.state
	var attitude := M.quat(state[RB.ATT], state[RB.ATT + 1], state[RB.ATT + 2], state[RB.ATT + 3])
	var forward_ned: PackedFloat64Array = M.q_rotate(attitude, M.v3(1.0, 0.0, 0.0))
	var horizontal_forward := M.v3(forward_ned[0], forward_ned[1], 0.0)
	var horizontal_norm: float = M.norm(horizontal_forward)
	_check("%s has a finite horizontal aircraft heading" % key,
		is_finite(horizontal_norm) and horizontal_norm > 0.99)
	if not is_finite(horizontal_norm) or horizontal_norm <= 0.99:
		return
	horizontal_forward = M.scale(horizontal_forward, 1.0 / horizontal_norm)
	var course_deg: float = rad_to_deg(atan2(horizontal_forward[1], horizontal_forward[0]))
	var names: Array[String] = ["headwind", "crosswind-left", "tailwind", "crosswind-right"]
	var offsets: Array[float] = [0.0, 90.0, 180.0, 270.0]
	for index in names.size():
		var standalone: Dictionary = scenario.weather_config.duplicate(true)
		standalone["from_deg"] = fposmod(course_deg + offsets[index], 360.0)
		standalone["speed_mps"] = 3.0
		standalone["gust_mps"] = 0.0
		standalone["gust_up_mps"] = 0.0
		standalone["turbulence_rms_mps"] = [0.0, 0.0, 0.0]
		var label: String = "%s %s standalone probe" % [key, names[index]]
		var built: Dictionary = _apply_standalone_weather(session, standalone, label)
		if built.is_empty():
			continue
		var wind: PackedFloat64Array = session.wind_at(0.0)
		var expected_wind: PackedFloat64Array = built.field.sample(0.0)
		var along_course: float = M.dot(wind, horizontal_forward)
		var wind_error: float = _max_vector_error(wind, expected_wind)
		var directional_ok: bool = wind_error <= 1e-12
		if index == 0:
			directional_ok = directional_ok and along_course < -2.999
		elif index == 1 or index == 3:
			directional_ok = directional_ok and absf(along_course) < 1e-9
		else:
			directional_ok = directional_ok and along_course > 2.999
		_check("%s actual session wind is %s relative to its airborne heading" % [key, names[index]],
			directional_ok, "along-course %.9f m/s; sample error %.9f m/s" % [along_course, wind_error])


func _exercise_atmosphere_corners(session: Node, scenario: Dictionary, key: String) -> void:
	var daylight: Dictionary = _daylight_record(str(scenario.get("daylight_id", "")))
	_check("%s daylight band resolves for atmosphere corners" % key, not daylight.is_empty())
	if daylight.is_empty():
		return
	var temperatures: Array = daylight.get("temperature_c", [])
	var humidities: Array = daylight.get("relative_humidity_pct", [])
	var pressures: Array = daylight.get("qnh_hpa", [])
	if temperatures.size() != 2 or humidities.size() != 2 or pressures.size() != 2:
		_check("%s policy provides three atmosphere corner bands" % key, false)
		return
	var corners: Array[Dictionary] = [
		{"name": "cool-humid-low-pressure", "temperature_c": temperatures[0],
			"relative_humidity_pct": humidities[1], "qnh_hpa": pressures[0]},
		{"name": "warm-dry-high-pressure", "temperature_c": temperatures[1],
			"relative_humidity_pct": humidities[0], "qnh_hpa": pressures[1]},
	]
	for corner: Dictionary in corners:
		var standalone: Dictionary = scenario.weather_config.duplicate(true)
		for name: String in ["temperature_c", "relative_humidity_pct", "qnh_hpa"]:
			standalone[name] = corner[name]
		var label: String = "%s %s standalone atmosphere" % [key, corner.name]
		var built: Dictionary = _apply_standalone_weather(session, standalone, label)
		if built.is_empty():
			continue
		var initial_air: Dictionary = session.air_data(session.sim.state, 0.0)
		_check("%s trims at the %s atmosphere corner" % [key, corner.name],
			is_finite(float(initial_air.get("V", NAN))) and float(initial_air.get("V", 0.0)) > 0.0
			and absf(float(initial_air.get("V", NAN)) - float(session.start.get("V", NAN))) < 1e-6,
			"air %.9f m/s; trim %.9f m/s" % [float(initial_air.get("V", NAN)), float(session.start.get("V", NAN))])


func _record_finite_sample(session: Node, ranges: Dictionary) -> bool:
	if not Sim.state_is_valid(session.sim.state) or not _finite_array(session.sim.previous) \
			or not _finite_array(session.sim.inputs) or not _finite_array(session.sim.aux) \
			or not _finite_array(session.sim.continuous) or not _finite_array(session.sim.last_loads):
		return false
	var time_s: float = session.sim.time()
	var wind: PackedFloat64Array = session.wind_at(time_s)
	var air: Dictionary = session.air_data(session.sim.state, time_s)
	if not _finite_array(wind) or not _finite_array(air.get("v_air", PackedFloat64Array())):
		return false
	for name: String in ["V", "qbar"]:
		if not is_finite(float(air.get(name, NAN))):
			return false
	var altitude_m: float = -session.sim.state[RB.POS + 2]
	var wind_speed_mps: float = M.norm(wind)
	if not is_finite(altitude_m) or not is_finite(wind_speed_mps):
		return false
	_range_value(ranges, "airspeed", float(air.V))
	_range_value(ranges, "altitude", altitude_m)
	_range_value(ranges, "wind_speed", wind_speed_mps)
	return true


func _trace_record(session: Node, trace: PackedByteArray) -> void:
	trace.append_array(var_to_bytes([
		session.sim.tick,
		session.sim.time(),
		session.sim.state,
		session.sim.previous,
		session.sim.inputs,
		session.sim.aux,
		session.sim.continuous,
		session.sim.modes,
		session.sim.last_loads,
		session.wind_at(session.sim.time()),
	]))


func _run_ticks(session: Node, count: int, capture_trace := false) -> Dictionary:
	var trace := PackedByteArray()
	var ranges: Dictionary = _new_ranges()
	var advanced := 0
	for tick in count:
		var requested: Dictionary = _scripted_input(tick)
		var commands: Dictionary = session.commands.duplicate(true)
		commands.roll = requested.roll
		commands.pitch = requested.pitch
		commands.yaw = requested.yaw
		# Keep the launch trim throttle fixed; this fixture only moves the three flight sticks.
		session.commands = commands
		session.sim.inputs = session._inputs()
		session.sim.step()
		if session.sim.paused or session.sim.tick != tick + 1:
			break
		advanced += 1
		if not _record_finite_sample(session, ranges):
			break
		if capture_trace:
			_trace_record(session, trace)
	return {ticks = advanced, trace = trace, ranges = ranges}


func _duration_for_period_sample(scenario: Dictionary) -> float:
	var weather: Dictionary = scenario.get("weather_config", {})
	var has_gust: bool = float(weather.get("gust_mps", 0.0)) > 0.0 \
		or absf(float(weather.get("gust_up_mps", 0.0))) > 0.0
	if not has_gust:
		return 0.0
	return float(weather.get("gust_delay_s", 0.0)) + float(weather.get("gust_period_s", 0.0))


func _dispose_session(session: Node) -> void:
	if session != null and is_instance_valid(session):
		if session.get_parent() != null:
			session.get_parent().remove_child(session)
		session.free()


func _initialize() -> void:
	var gust_period_only: bool = OS.get_cmdline_user_args().has(GUST_PERIOD_ONLY_FLAG)
	_check("flight matrix uses the production 240 Hz solver clock", Engine.physics_ticks_per_second == 240,
		str(Engine.physics_ticks_per_second))
	var loaded_field: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	_check("default field resolves for session setup", loaded_field.get("ok", false), str(loaded_field.get("errors", [])))
	if not loaded_field.get("ok", false):
		print("NR-03 flight qualification draft: %d checks, %d failed" % [_checks, _failures])
		quit(1)
		return
	var field: Dictionary = loaded_field.field
	_policy = ScenarioConfig.policy_catalog()
	_check("Natural Random policy resolves for standalone probe bounds", not _policy.is_empty())
	var matrix: Dictionary = _find_matrix_seeds()
	var expected_cells: int = AIRCRAFT_IDS.size() * RECIPE_IDS.size()
	_check("seed search finds all %d aircraft/recipe cells" % expected_cells, matrix.size() == expected_cells,
		"found %d before seed %d" % [matrix.size(), SEED_SEARCH_LIMIT])
	if matrix.size() != expected_cells:
		print("NR-03 flight qualification draft: %d checks, %d failed" % [_checks, _failures])
		quit(1)
		return

	for aircraft_id: String in AIRCRAFT_IDS:
		for recipe_id: String in RECIPE_IDS:
			if gust_period_only and (aircraft_id != REPLAY_AIRCRAFT_ID or recipe_id != REPLAY_RECIPE_ID):
				continue
			var key: String = _key(aircraft_id, recipe_id)
			var selected: Dictionary = matrix[key]
			var seed: int = int(selected.seed)
			var generated: Dictionary = NaturalRandom.generate(seed, FieldLoader.DEFAULT_PATH)
			_check("named seed regenerates %s" % key, generated.get("ok", false), str(generated.get("errors", [])))
			if not generated.get("ok", false):
				continue
			var scenario: Dictionary = generated.scenario
			_check("seed %d regenerates the same scenario" % seed,
				var_to_bytes(scenario) == var_to_bytes(selected.scenario))
			_check("generated selection matches its matrix cell",
				str(scenario.get("aircraft_id", "")) == aircraft_id
				and str(scenario.get("recipe_id", "")) == recipe_id)
			_check("generated start is airborne", str(scenario.get("start_choice", "")) == FlightSession.START_AIRBORNE)
			_check("generated daylight identity is present",
				["morning", "day", "afternoon"].has(str(scenario.get("daylight_id", ""))))
			var entry: Dictionary = AircraftCatalog.entry(aircraft_id)
			_check("%s resolves to packaged aircraft data" % aircraft_id,
				not entry.is_empty() and not str(entry.get("data", "")).is_empty())
			if entry.is_empty() or str(entry.get("data", "")).is_empty():
				continue

			var weather_config_before: PackedByteArray = var_to_bytes(scenario.get("weather_config", {}))
			var expected_weather: Dictionary = WindField.build(scenario.get("weather_config", {}))
			_check("%s weather validates" % key, expected_weather.get("ok", false),
				str(expected_weather.get("errors", [])))
			if not expected_weather.get("ok", false):
				continue

			var session = FlightSession.new()
			session.setup(str(entry.data), aircraft_id)
			session.input_enabled = false
			root.add_child(session)
			# Do not let a connected local joystick replace this test's explicit deterministic input stream.
			session.radio.disconnect_device()
			var weather_ok: bool = session.setup_weather(scenario.weather_config)
			_check("%s actual session accepts generated weather" % key, weather_ok, session.weather_error)
			var field_ok: bool = session.set_field(field)
			_check("%s actual session accepts the default field" % key, field_ok, session.surface_error)
			session.start_choice = str(scenario.start_choice)
			session.reset()
			_check("%s weather handoff preserves generated configuration" % key,
				session.weather_configuration() == scenario.weather_config)
			_check("%s weather handoff leaves source configuration unchanged" % key,
				var_to_bytes(scenario.weather_config) == weather_config_before)
			var expected_initial_wind: PackedFloat64Array = expected_weather.field.sample(0.0)
			if expected_weather.field.has_turbulence():
				var initial_turbulence: Dictionary = Turbulence.initial(
					expected_weather.field.turbulence_rms(), expected_weather.field.turbulence_seed())
				_check("%s initial turbulence seed resolves" % key, initial_turbulence.get("ok", false))
				if initial_turbulence.get("ok", false):
					for axis in 3:
						expected_initial_wind[axis] += initial_turbulence.values[axis]
			_check("%s session starts in the generated mean/gust/turbulence vector" % key,
				_max_vector_error(session.wind_at(0.0), expected_initial_wind) <= 1e-12,
				"error %.9f m/s" % _max_vector_error(session.wind_at(0.0), expected_initial_wind))
			_check("%s density is finite, positive and matches weather" % key,
				is_finite(session.air_density()) and session.air_density() > 0.0
				and is_equal_approx(session.air_density(), expected_weather.field.air_density()),
				str(session.air_density()))
			_check("%s stock aircraft and trim are accepted" % key,
				session.aircraft.get("ok", false) and session.aircraft.model.get("id", "") == aircraft_id
				and session.start.get("ok", false),
				str(session.start.get("message", session.pause_reason)))
			_check("%s start is finite and has positive trimmed speed" % key,
				Sim.state_is_valid(session.start.get("state", PackedFloat64Array()))
				and is_finite(float(session.start.get("V", NAN))) and float(session.start.get("V", 0.0)) > 0.0)
			_check("%s session reset commits a valid airborne state" % key,
				session.sim.tick == 0 and not session.sim.paused and Sim.state_is_valid(session.sim.state),
				session.pause_reason)
			var initial_air: Dictionary = session.air_data(session.sim.state, 0.0)
			_check("%s wind handoff preserves the trimmed airspeed" % key,
				is_finite(float(initial_air.get("V", NAN)))
				and absf(float(initial_air.get("V", NAN)) - float(session.start.get("V", NAN))) < 1e-6,
				"air %.9f m/s; trim %.9f m/s" % [float(initial_air.get("V", NAN)), float(session.start.get("V", NAN))])
			if not expected_weather.field.has_turbulence():
				_check("%s active mean wind matches the generated weather" % key,
					session.wind_at(0.0) == expected_weather.field.sample(0.0))
			if recipe_id == REPLAY_RECIPE_ID:
				# These separate FlightSession weather probes deliberately do not edit or reseal the generated scenario.
				_exercise_directional_weather(session, scenario, key)
				_exercise_atmosphere_corners(session, scenario, key)
				var restored_weather: bool = session.setup_weather(scenario.weather_config)
				_check("%s restores its untouched generated weather" % key, restored_weather, session.weather_error)
				if restored_weather:
					session.reset()
				_check("%s standalone probes leave scenario and session weather unchanged" % key,
					var_to_bytes(scenario.weather_config) == weather_config_before
					and session.weather_configuration() == scenario.weather_config)

			var replay_row: bool = not gust_period_only and aircraft_id == REPLAY_AIRCRAFT_ID and recipe_id == REPLAY_RECIPE_ID
			var duration_s: float = _duration_for_period_sample(scenario) if gust_period_only else (REPLAY_SECONDS if replay_row else MATRIX_SECONDS)
			if gust_period_only:
				var gust: Dictionary = scenario.weather_config
				_check("long gust row has nonzero gust and one complete period",
					is_equal_approx(duration_s, float(gust.gust_delay_s) + float(gust.gust_period_s))
					and (float(gust.gust_mps) > 0.0 or absf(float(gust.gust_up_mps)) > 0.0))
			var target_ticks: int = ceili(duration_s * 240.0)
			var launch_snapshot: PackedByteArray = _reset_snapshot(session) if replay_row else PackedByteArray()
			var run: Dictionary = _run_ticks(session, target_ticks, replay_row)
			_check("%s advances exactly %d fixed ticks" % [key, target_ticks], int(run.ticks) == target_ticks,
				"advanced %d; fault '%s'" % [int(run.ticks), session.sim.fault_reason])
			_check("%s 240 Hz trace state, loads, wind and ranges remain finite" % key,
				session.sim.tick == target_ticks and Sim.state_is_valid(session.sim.state)
				and _finite_array(session.sim.aux) and _finite_array(session.sim.continuous)
				and _finite_array(session.sim.inputs) and _finite_array(session.sim.last_loads)
				and is_finite(float(run.ranges.airspeed_min)) and is_finite(float(run.ranges.airspeed_max))
				and is_finite(float(run.ranges.altitude_min)) and is_finite(float(run.ranges.altitude_max))
				and is_finite(float(run.ranges.wind_speed_min)) and is_finite(float(run.ranges.wind_speed_max)),
				"air %.3f–%.3f m/s; altitude %.1f–%.1f m; wind %.3f–%.3f m/s" % [
					run.ranges.airspeed_min, run.ranges.airspeed_max,
					run.ranges.altitude_min, run.ranges.altitude_max,
					run.ranges.wind_speed_min, run.ranges.wind_speed_max,
				])
			print("NR-03 row %s seed=%d simulated=%.3f s ticks=%d" % [key, seed, session.sim.time(), session.sim.tick])
			if gust_period_only:
				_check("session integrated through delay plus one complete gust period",
					session.sim.time() >= duration_s - 1.0 / 240.0)

			if replay_row and int(run.ticks) == target_ticks:
				session.reset()
				_check("windy replay reset restores the exact accepted launch", _reset_snapshot(session) == launch_snapshot)
				var repeated: Dictionary = _run_ticks(session, target_ticks, true)
				_check("windy replay repeats every fixed input and complete solver trace exactly",
					int(repeated.ticks) == target_ticks and repeated.trace == run.trace,
					"first %d bytes; repeat %d bytes" % [run.trace.size(), repeated.trace.size()])
			_dispose_session(session)

	print("NR-03 numerical flight qualification: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)

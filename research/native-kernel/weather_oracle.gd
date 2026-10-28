## NK-3 weather component oracle. Each native snapshot is copied once from an
## actually built WeatherField; every subsequent point/time query is native.
## Tests compare exact binary64 bytes, including invalid inputs and rejection.
## This is component evidence, not a production-stage or fleet qualification.
extends "oracle.gd"

const WeatherConfig := preload("res://physics/wind_config.gd")
const WeatherField := preload("res://physics/wind_field.gd")
const SimEnvironment := preload("res://sim/environment.gd")
const WeatherAdapter := preload("res://sim/native/weather_adapter.gd")


func _source_hashes() -> Dictionary:
	var out: Dictionary = super._source_hashes()
	for path: String in ["res://physics/wind_config.gd", "res://physics/atmosphere.gd",
			"res://physics/wind_turbulence.gd", "res://physics/wind_spatial_config.gd",
			"res://physics/wind_spatial_field.gd", "res://physics/wind_spatial_presets.gd",
			"res://physics/wind_thermal_field.gd"]:
		out[path] = FileAccess.get_sha256(path)
	return out


func _checks() -> void:
	_report.format = "openrc-nk3-weather-oracle v1"
	_report.weather = {presets = [], scenarios = [], refusals = {}}
	for name: String in ["prepare_weather", "weather_component", "air_component", "temperature_component"]:
		if not _native.has_method(name):
			_failures.append("native weather component method missing: " + name)
			return
	if _states <= 0:
		_failures.append("weather states must be positive")
		return
	var scenarios: Array[Dictionary] = WeatherConfig.presets()
	_report.weather.presets = scenarios.map(func(row: Dictionary) -> String: return str(row.id))
	# Extra valid configurations cover noncardinal directions, the endpoint canonicalization,
	# combined OU/column behavior, and the v5 spatial provider with a column atmosphere.
	for direction: float in [0.0, 45.0, 90.0, 135.0, 180.0, 270.0, 360.0]:
		var config := WeatherConfig.defaults()
		config.speed_mps = 4.25
		config.from_deg = direction
		config.gust_mps = 2.2
		config.gust_up_mps = 0.75
		scenarios.append({id = "direction-%s" % str(direction), config = config})
	var column_ou: Dictionary = WeatherConfig.upgrade_column(WeatherConfig.GENTLE_PRACTICE,
		{atmosphere_mode = "standard_column", field_elevation_m = 100.0})
	scenarios.append({id = "column-and-ou", config = column_ou})
	var warm: Dictionary = WeatherConfig.upgrade_atmosphere(WeatherConfig.defaults(),
		{atmosphere_mode = "custom", temperature_c = 38.75, field_elevation_m = 725.0})
	scenarios.append({id = "warm-uniform-atmosphere", config = warm})
	var spatial_column: Dictionary = WeatherConfig.preset("spatial-realistic-v1")
	spatial_column.atmosphere_mode = "standard_column"
	spatial_column.field_elevation_m = 100.0
	scenarios.append({id = "spatial-and-column", config = spatial_column})
	var per_scenario := maxi(1, int(ceil(float(_states) / float(scenarios.size()))))
	for scenario: Dictionary in scenarios:
		_check_scenario(scenario, per_scenario)
	_check_weather_refusals()
	_check_spatial_provider_guard()


## Read the real session's initial and advanced OU windows, including its actual
## auxiliary index and tick dt. The session owns and advances the PCG state.
func _session_windows(config: Dictionary) -> Array[Dictionary]:
	var session: Node = Session.new()
	session.setup(str(Catalog.entry(AIRCRAFT).data), AIRCRAFT)
	if not session.is_flyable() or not session.setup_weather(config):
		_failures.append("OU session setup failed: " + str(session.weather_error))
		session.free()
		return []
	session.reset()
	if not session.is_flyable() or not session.start_error.is_empty() or session.sim.paused \
			or not session.sim.fault_reason.is_empty():
		_failures.append("OU session reset failed: " + str(session.start_error))
		session.free()
		return []
	var windows: Array[Dictionary] = []
	for index: int in 3:
		windows.append({aux = session.sim.aux.duplicate(), index = session.turbulence_index(), dt = session.sim.dt()})
		if index < 2:
			session.sim.step()
			if not session.sim.fault_reason.is_empty() or session.sim.paused or session.sim.tick != index + 1:
				_failures.append("OU session did not advance: " + str(session.sim.fault_reason))
				break
	session.free()
	return windows


static func _reference_wind(field: RefCounted, position: PackedFloat64Array, time_s: float,
		window: Dictionary) -> PackedFloat64Array:
	var environment := SimEnvironment.new()
	environment.weather = field
	if field.has_turbulence():
		environment.turbulence = func(at: float) -> PackedFloat64Array:
			var aux: PackedFloat64Array = window.aux
			var index: int = window.index
			if index < 4 or aux.size() != index + 7:
				return PackedFloat64Array([NAN, NAN, NAN])
			return Session.turbulence_at(aux, index, at, window.dt)
	return environment.wind_world(position, time_s)


func _compare_wind(label: String, field: RefCounted, position: PackedFloat64Array,
		time_s: float, window: Dictionary) -> void:
	var reference := _reference_wind(field, position, time_s, window)
	var native: PackedFloat64Array = _native.weather_component(position, time_s, window.aux, window.index, window.dt)
	_compare("weather_wind", reference, native, [label, position, time_s, window])
	_tally("weather", "point_queries")


func _check_scenario(scenario: Dictionary, random_count: int) -> void:
	var label := str(scenario.id)
	var built: Dictionary = WeatherField.build(scenario.config)
	if not built.ok:
		_failures.append("weather scenario %s invalid: %s" % [label, str(built.errors)])
		return
	var field: RefCounted = built.field
	var snapshot := WeatherAdapter.snapshot(field)
	var prepared: Dictionary = _native.prepare_weather(snapshot)
	if not prepared.get("ok", false):
		_failures.append("native weather refused %s: %s" % [label, str(prepared.get("error", ""))])
		return
	_report.weather.scenarios.append(label)
	var windows: Array[Dictionary] = [{aux = PackedFloat64Array(), index = -1, dt = 1.0 / 240.0}]
	if field.has_turbulence():
		windows = _session_windows(scenario.config)
		if windows.size() != 3:
			_failures.append("weather %s lacks three real OU windows" % label)
			return
	var times := PackedFloat64Array([0.0, 0.25, 2.0, 3.0, 4.0, 6.0, 12.0, 15.0, 60.0, 195.0,
		86400.0, 86400.000001, -1.0, NAN, INF])
	if not field.is_spatial():
		var c: Dictionary = field.configuration()
		var delay: float = c.gust_delay_s
		var duration: float = c.gust_duration_s
		var period: float = c.gust_period_s
		times.append_array(PackedFloat64Array([delay, delay + duration * 0.5, delay + duration,
			delay + period, delay + period + duration * 0.5]))
	var positions: Array[PackedFloat64Array] = [PackedFloat64Array([0.0, 0.0, -10.0]),
		PackedFloat64Array([1.5, -2.0, -27.0]), PackedFloat64Array([0.0, 0.0, -0.0001]),
		PackedFloat64Array([0.0, 0.0, 0.0]), PackedFloat64Array([10000.0, -10000.0, -100.0]),
		PackedFloat64Array([10000.000001, 0.0, -10.0]), PackedFloat64Array([0.0, 0.0, NAN]),
		PackedFloat64Array([INF, 0.0, -10.0]), PackedFloat64Array([0.0, 0.0])]
	if field.is_spatial():
		var domain: Dictionary = field.configuration().spatial_wind.domain
		positions.append(PackedFloat64Array([0.0, 0.0, float(domain.ground_extension_m)]))
		positions.append(PackedFloat64Array([0.0, 0.0, float(domain.ground_extension_m) + 0.000001]))
		positions.append(PackedFloat64Array([0.0, 0.0, -float(domain.max_height_agl_m)]))
		positions.append(PackedFloat64Array([0.0, 0.0, -float(domain.max_height_agl_m) - 0.000001]))
	for window: Dictionary in windows:
		if field.has_turbulence():
			var start: float = window.aux[window.index + 6]
			for offset: float in [-0.5, 0.0, 0.5, 1.0, 1.5]:
				_compare_wind(label, field, PackedFloat64Array([10.0, -5.0, -30.0]),
					maxf(0.0, start + offset * window.dt), window)
			_tally("weather", "real_ou_windows")
		for position: PackedFloat64Array in positions:
			for time_s: float in times:
				_compare_wind(label, field, position, time_s, window)
		for _index: int in random_count:
			var position := PackedFloat64Array([_rng.randf_range(-9999.0, 9999.0),
				_rng.randf_range(-9999.0, 9999.0), -_rng.randf_range(0.0, 199.0)])
			_compare_wind(label, field, position, _rng.randf_range(0.0, 1000.0), window)
		if field.is_spatial():
			var spatial: Dictionary = field.configuration().spatial_wind
			if spatial.has("thermal_field"):
				var thermal: Dictionary = spatial.thermal_field
				for cell: Dictionary in thermal.cells:
					for age: float in [0.0, float(cell.duration_s) * 0.5, float(cell.duration_s)]:
						var time_s: float = float(cell.birth_s) + age - float(thermal.identity.epoch_offset_s)
						if time_s < 0.0:
							continue
						var center_n: float = float(cell.center_ne_m[0]) + float(cell.drift_ne_mps[0]) * age
						var center_e: float = float(cell.center_ne_m[1]) + float(cell.drift_ne_mps[1]) * age
						for radial: float in [0.0, 4.0, 4.5, 5.0]:
							var point := PackedFloat64Array([center_n + radial * float(cell.radius_m), center_e,
								-0.5 * float(cell.top_agl_m)])
							_compare_wind(label, field, point, time_s, window)
							_tally("weather", "thermal_cell_samples")
	# Exercise the actual session atmosphere path in addition to the field
	# component. The binding takes only down; environment_at also validates the
	# complete NED position, so compare these queries for finite positions.
	var atmosphere_session: Node = Session.new()
	atmosphere_session.environment.weather = field
	var atmosphere_state := PackedFloat64Array()
	atmosphere_state.resize(RB.SIZE)
	atmosphere_state[0] = 1.0
	atmosphere_state[1] = -2.0
	for down: float in [-11000.0, -1000.0, -100.0, 0.0, 500.0, 500.000001, NAN, INF]:
		var reference := PackedFloat64Array([field.air_density(down), field.engine_charge_ratio(down)])
		var native: PackedFloat64Array = _native.air_component(down)
		_compare("weather_atmosphere", reference, native, [label, down])
		var temperature: float = float(field.atmosphere(down).get("temperature_k", NAN))
		_compare("weather_temperature", PackedFloat64Array([temperature]),
			PackedFloat64Array([_native.temperature_component(down)]), [label, down])
		if is_finite(down):
			atmosphere_state[2] = down
			var session_air: Dictionary = atmosphere_session.environment_at(atmosphere_state)
			_compare("weather_session_temperature", PackedFloat64Array([float(session_air.get("temperature_k", NAN))]),
				PackedFloat64Array([_native.temperature_component(down)]), [label, down])
		_tally("weather", "air_queries")
	atmosphere_session.free()


func _check_weather_refusals() -> void:
	var uniform: Dictionary = WeatherAdapter.snapshot(WeatherField.build(WeatherConfig.defaults()).field)
	var spatial: Dictionary = WeatherAdapter.snapshot(WeatherField.build(WeatherConfig.preset("spatial-realistic-v1")).field)
	var cases := {}
	var bad := uniform.duplicate(true)
	bad.extra = 1
	cases.unknown_key = bad
	bad = uniform.duplicate(true)
	bad.uniform = [0.0, 0.0, 0.0, 0.0, 4.0, 12.0, 2.0]
	cases.wrong_array_type = bad
	bad = uniform.duplicate(true)
	bad.uniform[0] = NAN
	cases.nonfinite_speed = bad
	bad = uniform.duplicate(true)
	bad.uniform[5] = 1.0
	cases.period_before_duration = bad
	bad = uniform.duplicate(true)
	bad.vertical_atmosphere = 1
	cases.wrong_boolean_type = bad
	bad = uniform.duplicate(true)
	bad.temperature_k = NAN
	cases.nonfinite_temperature = bad
	bad = uniform.duplicate(true)
	bad.temperature_k = 0.0
	cases.nonpositive_temperature = bad
	bad = uniform.duplicate(true)
	bad.temperature_k = "288.15"
	cases.wrong_temperature_type = bad
	bad = spatial.duplicate(true)
	bad.has_turbulence = true
	cases.spatial_ou_conflict = bad
	bad = spatial.duplicate(true)
	bad.spatial.modes = bad.spatial.modes.slice(0, bad.spatial.modes.size() - 1)
	cases.incomplete_mode = bad
	bad = spatial.duplicate(true)
	bad.spatial.modes[0] = NAN
	cases.nonfinite_mode = bad
	bad = spatial.duplicate(true)
	bad.spatial.gust_max_duration = -1.0
	cases.invalid_gust_maximum = bad
	bad = spatial.duplicate(true)
	bad.spatial.domain[4] = 0.0
	cases.invalid_ground_extension = bad
	for name: String in cases:
		var good: Dictionary = _native.prepare_weather(uniform)
		var refused: Dictionary = _native.prepare_weather(cases[name])
		var wind: PackedFloat64Array = _native.weather_component(PackedFloat64Array([0.0, 0.0, 0.0]), 0.0,
			PackedFloat64Array(), -1, 1.0 / 240.0)
		var air: PackedFloat64Array = _native.air_component(0.0)
		var clean: bool = good.get("ok", false) and not refused.get("ok", true) \
			and not str(refused.get("error", "")).is_empty() and wind.size() == 3 and air.size() == 2
		for value: float in wind:
			clean = clean and is_nan(value)
		for value: float in air:
			clean = clean and is_nan(value)
		_report.weather.refusals[name] = {refused = not refused.get("ok", true), error = str(refused.get("error", "")),
			cleared = clean}
		_compare("weather_refusal", PackedFloat64Array([1.0]), PackedFloat64Array([1.0 if clean else 0.0]), name)
		if not clean:
			_failures.append("weather refusal failed: " + name)
	var legacy := uniform.duplicate(true)
	legacy.erase("temperature_k")
	var legacy_prepared: Dictionary = _native.prepare_weather(legacy)
	var legacy_temperature: float = _native.temperature_component(0.0)
	_compare("weather_legacy_temperature", PackedFloat64Array([1.0, 288.15]),
		PackedFloat64Array([1.0 if legacy_prepared.get("ok", false) else 0.0, legacy_temperature]))


## Direct provider mutation is attempted only on this disposable session.
## A captured spatial snapshot must not be reused after its seeded modes change.
func _check_spatial_provider_guard() -> void:
	var session: Node = Session.new()
	session.setup(str(Catalog.entry(AIRCRAFT).data), AIRCRAFT)
	if not session.is_flyable() or not session.setup_weather(WeatherConfig.preset("spatial-realistic-v1")):
		_failures.append("spatial provider guard session did not start")
		session.free()
		return
	session.reset()
	var identity := WeatherAdapter.provider_identity(session)
	if not identity.get("ok", false):
		_failures.append("spatial provider guard failed to capture identity")
		session.free()
		return
	var provider: RefCounted = session._weather.get("_spatial")
	var original: PackedFloat64Array = provider.get("_modes")
	var changed := original.duplicate()
	changed[0] += 1.0
	provider.set("_modes", changed)
	var refused: bool = WeatherAdapter.config_for(session).is_empty() \
		and not WeatherAdapter.provider_matches(session, identity)
	provider.set("_modes", original)
	var restored: bool = WeatherAdapter.provider_matches(session, identity)
	_compare("weather_spatial_provider_guard", PackedFloat64Array([1.0]),
		PackedFloat64Array([1.0 if refused and restored else 0.0]))
	if not refused or not restored:
		_failures.append("spatial mode mutation guard failed")
	session.free()

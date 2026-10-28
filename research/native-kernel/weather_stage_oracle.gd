## NK-3 joint-stage weather oracle. Uses the real fixed-wing reference session,
## its shared pre_tick and actual OU aux intervals; native stage owns every RK
## weather query. Spatial v5 runs only with the explicit include-spatial option;
## this research adapter does not change application admission.
extends "stage_oracle.gd"

const WeatherConfig := preload("res://physics/wind_config.gd")
const WeatherAdapter := preload("weather_adapter.gd")
const WindFlow := preload("res://physics/wind_aircraft_flow.gd")


func _extra_option_names() -> PackedStringArray:
	return PackedStringArray(["ticks", "include-spatial"])


func _checks() -> void:
	_report.format = "openrc-nk3-weather-stage-oracle v1"
	_report.weather_stage = {scenarios = [], scenario_coverage = {}, skipped_spatial = [], trajectories = {}, refusals = {}}
	var ticks: int = int(_options.get("ticks", "240"))
	var include_option := str(_options.get("include-spatial", "false"))
	if _states <= 0 or ticks <= 0 or include_option not in ["true", "false"]:
		_failures.append("weather-stage states and trajectory ticks must be positive")
		return
	var include_spatial := include_option == "true"
	_report.weather_stage.include_spatial = include_spatial
	var scenarios: Array[Dictionary] = []
	for preset: Dictionary in WeatherConfig.presets():
		if preset.config.format == WeatherConfig.SPATIAL_FORMAT and not include_spatial:
			_report.weather_stage.skipped_spatial.append(str(preset.id))
		else:
			scenarios.append(preset)
	var angled := WeatherConfig.defaults()
	angled.speed_mps = 3.75
	angled.from_deg = 137.0
	angled.gust_mps = 2.0
	angled.gust_up_mps = -0.4
	scenarios.append({id = "custom-noncardinal", config = angled})
	var combined: Dictionary = WeatherConfig.upgrade_column(WeatherConfig.GENTLE_PRACTICE,
		{atmosphere_mode = "standard_column", field_elevation_m = 100.0})
	scenarios.append({id = "custom-column-and-ou", config = combined})
	if include_spatial:
		var spatial_column: Dictionary = WeatherConfig.preset("spatial-realistic-v1")
		spatial_column.atmosphere_mode = "standard_column"
		spatial_column.field_elevation_m = 100.0
		scenarios.append({id = "custom-spatial-column", config = spatial_column})
	var count := maxi(1, int(ceil(float(_states) / float(scenarios.size()))))
	for scenario: Dictionary in scenarios:
		_check_weather_stage(scenario, count)
	var gust := WeatherConfig.preset("gusty")
	gust.gust_delay_s = 0.0
	var trajectories: Array[Dictionary] = [
		{id = "active-gust", config = gust},
		{id = "turbulent", config = WeatherConfig.preset("turbulent")},
		{id = "standard-column", config = WeatherConfig.preset("standard-column")},
	]
	if include_spatial:
		for preset: Dictionary in WeatherConfig.presets():
			if preset.config.format == WeatherConfig.SPATIAL_FORMAT:
				trajectories.append(preset)
		var active_gust: Dictionary = WeatherConfig.preset("spatial-gusty-v1")
		active_gust.spatial_wind.gusts.events[0].start_s = 0.0
		trajectories.append({id = "spatial-active-gust", config = active_gust})
		var active_thermal: Dictionary = WeatherConfig.preset("spatial-thermal-soaring-v2")
		active_thermal.spatial_wind.thermal_field.cells[0].birth_s = 0.0
		active_thermal.spatial_wind.thermal_field.cells[0].duration_s = 120.0
		active_thermal.spatial_wind.thermal_field.cells[0].center_ne_m = [60.0, -40.0]
		active_thermal.spatial_wind.thermal_field.cells[0].drift_ne_mps = [0.0, 0.0]
		trajectories.append({id = "spatial-active-thermal", config = active_thermal})
	for scenario: Dictionary in trajectories:
		_check_weather_trajectory(scenario, ticks)


## Obtain real aux intervals after the session's pre_tick has advanced PCG/OU;
## no oracle-generated noise values replace the owner's RNG state.
func _weather_windows(session: Node) -> Array[PackedFloat64Array]:
	var windows: Array[PackedFloat64Array] = [session.sim.aux.duplicate()]
	if not session._weather.has_turbulence():
		return windows
	for index: int in 2:
		session.sim.step()
		if session.sim.tick != index + 1 or session.sim.paused or not session.sim.fault_reason.is_empty():
			_failures.append("weather-stage OU pre_tick failed: " + str(session.sim.fault_reason))
			return []
		windows.append(session.sim.aux.duplicate())
	return windows


func _check_weather_stage(scenario: Dictionary, count: int) -> void:
	var label := str(scenario.id)
	var session := _build_session(AIRCRAFT, "trim", false, scenario.config, true)
	if session == null:
		_failures.append("weather-stage %s session failed" % label)
		return
	var provider := WeatherAdapter.provider_identity(session)
	var config := WeatherAdapter.config_for(session)
	if not provider.get("ok", false) or config.is_empty() or not WeatherAdapter.provider_matches(session, provider):
		_failures.append("weather-stage %s provider refused: %s" % [label, str(provider.get("reason", ""))])
		session.free()
		return
	if label == "steady":
		# This session is disposable. Verify that a replaced callback or an
		# in-place cached wind edit cannot reuse the captured provider identity.
		var original: Callable = session.environment.turbulence
		session.environment.turbulence = func(_time: float) -> PackedFloat64Array: return PackedFloat64Array()
		var callback_refused: bool = WeatherAdapter.config_for(session).is_empty() \
			and not WeatherAdapter.provider_matches(session, provider)
		session.environment.turbulence = original
		var old_mean: PackedFloat64Array = session._weather.get("_mean_ned")
		var changed := old_mean.duplicate()
		changed[0] += 1.0
		session._weather.set("_mean_ned", changed)
		var mutation_refused: bool = WeatherAdapter.config_for(session).is_empty() \
			and not WeatherAdapter.provider_matches(session, provider)
		session._weather.set("_mean_ned", old_mean)
		var restored: bool = WeatherAdapter.provider_matches(session, provider)
		var intact := callback_refused and mutation_refused and restored
		_compare("weather_provider_guard", PackedFloat64Array([1.0]), PackedFloat64Array([1.0 if intact else 0.0]), label)
		if not intact:
			_failures.append("weather provider mutation/callback guard failed")
	var prepared: Dictionary = _native.prepare_stage(config)
	if not prepared.get("ok", false):
		_failures.append("weather-stage %s native prepare refused: %s" % [label, str(prepared.get("error", ""))])
		session.free()
		return
	_report.weather_stage.scenarios.append(label)
	var windows := _weather_windows(session)
	if windows.is_empty():
		session.free()
		return
	var context := {model = session.aircraft.model, gear = session.current_landing_gear(session.sim.aux),
		surfaces = session.ground_surfaces, lake = session._lake, rest = session.sim.state.duplicate(),
		aux = session.sim.aux.duplicate(), deflections = session._deflections(session.sim.aux).duplicate()}
	var weather: Dictionary = session.weather_configuration()
	var delay: float = weather.gust_delay_s
	var duration: float = weather.gust_duration_s
	var period: float = weather.gust_period_s
	var turb_index: int = session.turbulence_index() if session._weather.has_turbulence() else -1
	var finite_stages := 0
	for index: int in count:
		var drawn := _stage_state(context, context.surfaces, context.lake)
		var state: PackedFloat64Array = drawn.s
		var aux := _stage_aux(context, session, state)
		if turb_index >= 0:
			var actual: PackedFloat64Array = windows[index % windows.size()]
			for offset: int in 7:
				aux[turb_index + offset] = actual[turb_index + offset]
		var stage_time: float
		match index % 6:
			0: stage_time = 0.0
			1: stage_time = delay
			2: stage_time = delay + duration * 0.5
			3: stage_time = delay + duration
			4: stage_time = delay + period
			_: stage_time = _rng.randf_range(0.0, 120.0)
		if turb_index >= 0 and index % 3 == 0:
			stage_time = aux[turb_index + 6] + session.sim.dt() * [0.0, 0.5, 1.0][int(index / 3) % 3]
		if drawn.malformed and index % 9 == 0:
			stage_time = [NAN, -session.sim.dt(), INF, -INF][(index / 9) % 4]
		session.sim.aux = aux
		var ok: bool = _native.set_tick_context(aux, session.sim.inputs,
			Adapter.deflection_array(session._deflections(aux)), session.sim.time())
		if not ok:
			_failures.append("weather-stage %s native tick context refused" % label)
			break
		var values: PackedFloat64Array = session.sim.continuous.duplicate()
		for wheel: int in values.size():
			values[wheel] = _rng.randf_range(-25.0, 25.0)
		if drawn.malformed and index % 7 == 0 and not values.is_empty():
			values[index % values.size()] = _special()
		if index > 0 and index % 53 == 0:
			values.resize((values.size() + 1) % 5)
		var reference: Dictionary = session._wheel_evaluate(state, values, stage_time)
		var native: Dictionary = _native.stage(state, values, stage_time)
		_compare_stage(reference, native, [label, state, aux, values, stage_time])
		if not reference.is_empty() and reference.get("loads") is PackedFloat64Array:
			var finite := true
			for value: float in reference.loads:
				finite = finite and is_finite(value)
			if finite:
				finite_stages += 1
		_tally("weather_stage", "states")
		_tally("weather_stage", "malformed" if drawn.malformed else "ordinary")
		if turb_index >= 0: _tally("weather_stage", "real_ou_window_states")
	if finite_stages == 0:
		_failures.append("weather-stage %s has no finite shaped stage" % label)
	else:
		_tally("weather_stage", "finite_shaped", finite_stages)
	# True weather capability flags must never be silently cleared: a missing
	# snapshot is refused, even if the unchanged model otherwise prepares.
	if config.not_calm or config.turbulence or config.vertical_atmosphere:
		var missing := config.duplicate(true)
		missing.erase("weather")
		var refused: Dictionary = _native.prepare_stage(missing)
		var correct: bool = not refused.get("ok", true) and not str(refused.get("error", "")).is_empty()
		_report.weather_stage.refusals[label] = {refused = correct, error = str(refused.get("error", ""))}
		_compare("weather_stage_refusal", PackedFloat64Array([1.0]), PackedFloat64Array([1.0 if correct else 0.0]), label)
		if not correct:
			_failures.append("weather-stage %s accepted non-calm capabilities without a snapshot" % label)
	session.free()


static func _weather_tape(session: Node) -> PackedByteArray:
	var sim: Node = session.sim
	return var_to_bytes([sim.tick, sim.state, sim.previous, sim.aux, sim.continuous, sim.inputs, sim.last_loads, sim.modes])


## Compare the real kernel, pre_tick and state publication for one short paired
## tape. The research wrapper hands native the exact aux installed each tick.
func _check_weather_trajectory(scenario: Dictionary, ticks: int) -> void:
	var label := str(scenario.id)
	var reference := _build_session(AIRCRAFT, "trim", false, scenario.config, true)
	var native := _build_session(AIRCRAFT, "trim", false, scenario.config, true)
	if reference == null or native == null:
		_failures.append("weather trajectory %s could not start" % label)
		if reference != null: reference.free()
		if native != null: native.free()
		return
	var config := WeatherAdapter.config_for(native)
	var prepared: Dictionary = _native.prepare_stage(config) if not config.is_empty() else {ok = false, error = "provider identity refused"}
	if not prepared.get("ok", false):
		_failures.append("weather trajectory %s native prepare failed: %s" % [label, str(prepared.get("error", ""))])
		reference.free()
		native.free()
		return
	var inner: Callable = native.sim.model.pre_tick
	var wrapped := func(aux: PackedFloat64Array, inputs: PackedFloat64Array, dt: float) -> Variant:
		var next: Variant = inner.call(aux, inputs, dt)
		if next is PackedFloat64Array and next.size() == aux.size():
			_native.set_tick_context(next, inputs, Adapter.deflection_array(native._deflections(next)), native.sim.time())
		return next
	native.sim.model.pre_tick = wrapped
	native.sim.model.stage = Callable(_native, "stage")
	_native.set_tick_context(native.sim.aux, native.sim.inputs, Adapter.deflection_array(native._deflections(native.sim.aux)), native.sim.time())
	_native.reset_stage_stats(false)
	var previous: Dictionary = _native.stage_stats()
	var complete := true
	var ran := 0
	var first_divergence := -1
	var equal := _compare("weather_trajectory_tick", _weather_tape(reference), _weather_tape(native), [label, 0])
	if not equal: first_divergence = 0
	for index: int in ticks:
		var inputs: PackedFloat64Array = reference.sim.inputs.duplicate()
		if inputs.size() >= 4:
			inputs[0] = 0.04 if index % 40 < 20 else -0.04
			inputs[1] = 0.02 if index % 60 < 30 else -0.02
			inputs[3] = 0.55
		reference.sim.inputs = inputs.duplicate()
		native.sim.inputs = inputs.duplicate()
		reference.sim.step()
		native.sim.step()
		var stats: Dictionary = _native.stage_stats()
		var healthy: bool = reference.sim.tick == index + 1 and native.sim.tick == index + 1 \
			and not reference.sim.paused and not native.sim.paused and reference.sim.fault_reason.is_empty() \
			and native.sim.fault_reason.is_empty() and reference.crash.is_empty() and native.crash.is_empty()
		var covered: bool = native.sim.model.stage == Callable(_native, "stage") and native.sim.model.pre_tick == wrapped \
			and int(stats.get("stage_calls", 0)) - int(previous.get("stage_calls", 0)) >= 4 \
			and int(stats.get("context_calls", 0)) - int(previous.get("context_calls", 0)) >= 1
		if not healthy or not covered:
			_failures.append("weather trajectory %s tick %d failed or lacked native coverage" % [label, index + 1])
			complete = false
			break
		previous = stats
		ran += 1
		equal = _compare("weather_trajectory_tick", _weather_tape(reference), _weather_tape(native), [label, index + 1])
		if not equal and first_divergence < 0: first_divergence = index + 1
	_report.weather_stage.trajectories[label] = {requested_ticks = ticks, ticks_run = ran, complete = complete and ran == ticks,
		first_divergence = first_divergence, native_stage_calls = int(previous.get("stage_calls", 0)),
		native_context_calls = int(previous.get("context_calls", 0))}
	if first_divergence >= 0:
		_failures.append("weather trajectory %s diverged at tick %d" % [label, first_divergence])
	reference.free()
	native.free()

## Native spatial station, aerodynamic correction and wake component oracle.
## Exercises real WeatherField snapshots and native point callbacks; this is not
## a joint-stage or flight-trajectory qualification.
extends "weather_oracle.gd"

const WindFlow := preload("res://physics/wind_aircraft_flow.gd")
const Slipstream := preload("res://physics/slipstream.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const WashTransport := preload("res://physics/wash_transport.gd")
const SmoothFixture := preload("res://tests/test_wash_profile.gd")
const TransportFixture := preload("res://tests/test_wash_transport.gd")


func _source_hashes() -> Dictionary:
	var out: Dictionary = super._source_hashes()
	for path: String in ["res://physics/wind_aircraft_flow.gd", "res://physics/slipstream.gd",
			"res://physics/swirl_loads.gd", "res://physics/wash_transport.gd"]:
		out[path] = FileAccess.get_sha256(path)
	return out


func _checks() -> void:
	_report.format = "openrc-nk3-wake-spatial-oracle v1"
	for name: String in ["prepare_aero", "prepare_propeller", "prepare_weather", "prepare_wake",
			"spatial_aero_component", "spatial_flow_component", "spatial_wake_component"]:
		if not _native.has_method(name):
			_failures.append("native spatial component method missing: " + name)
			return
	if _states <= 0:
		_failures.append("spatial states must be positive")
		return
	var all_models: Array[Dictionary] = []
	for id: String in Catalog.airplane_flyable_ids():
		var loaded: Dictionary = AircraftData.load_file(Catalog.data_for(id))
		if not loaded.ok:
			_failures.append("catalog spatial model failed: " + id)
			continue
		all_models.append({name = id, model = loaded.model})
	_check_direct_aero(all_models)
	var wake_models: Array[Dictionary] = []
	for row: Dictionary in all_models:
		if row.model.propulsion.has("slipstream") or row.name in [AIRCRAFT, "skywalker-x8"]:
			wake_models.append(row)
	var smooth: Dictionary = SmoothFixture.combined_raw()
	smooth.propulsion.propeller.slipstream.swirl_factor.value = 0.4
	for row: Dictionary in [{name = "smooth_swirl", raw = smooth},
			{name = "smooth_transport", raw = TransportFixture.raw_fixture()}]:
		var loaded: Dictionary = AircraftData.validate_and_derive(row.raw)
		if not loaded.ok:
			_failures.append("spatial wake fixture failed: " + str(row.name))
		else:
			wake_models.append({name = row.name, model = loaded.model})
	if wake_models.is_empty():
		_failures.append("no wake models available")
		return
	var scenarios: Array[Dictionary] = WeatherConfig.presets()
	_report.weather_scenarios = scenarios.map(func(row: Dictionary) -> String: return str(row.id))
	var per_pair := maxi(1, int(ceil(float(_states) / float(scenarios.size() * wake_models.size()))))
	for scenario: Dictionary in scenarios:
		_check_weather_models(scenario, wake_models, per_pair)


func _state_case(i: int) -> PackedFloat64Array:
	var s := PackedFloat64Array([_rng.randf_range(-20.0, 20.0), _rng.randf_range(-20.0, 20.0),
		-_rng.randf_range(1.0, 100.0), _rng.randf_range(-25.0, 40.0), _rng.randf_range(-4.0, 4.0),
		_rng.randf_range(-6.0, 6.0), 1.0, 0.0, 0.0, 0.0,
		_rng.randf_range(-2.0, 2.0), _rng.randf_range(-2.0, 2.0), _rng.randf_range(-2.0, 2.0)])
	var attitude: PackedFloat64Array = _random_unit_quaternion()
	for axis in 4: s[6 + axis] = attitude[axis]
	if i % 11 == 0:
		s[3] = 0.0
		s[4] = 0.0
		s[5] = 0.0
	return s


func _controls(model: Dictionary) -> Dictionary:
	var d := {elevator = _rng.randf_range(-0.3, 0.3), aileron_right = _rng.randf_range(-0.2, 0.2),
		aileron_left = _rng.randf_range(-0.2, 0.2), rudder = _rng.randf_range(-0.3, 0.3), flap = 0.0}
	if model.get("capabilities", {}).get("flaps", "") == "simulated":
		d.flap = _rng.randf_range(0.0, deg_to_rad(float(model.flaps.max_angle_deg)))
	return d


func _check_direct_aero(models: Array[Dictionary]) -> void:
	var per_model := maxi(1, int(ceil(float(_states) / float(models.size()))))
	for row: Dictionary in models:
		var model: Dictionary = row.model
		var label := str(row.name)
		var prepared: Dictionary = _native.prepare_aero(model)
		if not prepared.ok:
			_failures.append("spatial aero prepare %s: %s" % [label, str(prepared.error)])
			continue
		for i in per_model:
			var body := _state_case(i)
			var wind := PackedFloat64Array([_rng.randf_range(-4.0, 4.0), _rng.randf_range(-4.0, 4.0), _rng.randf_range(-1.0, 1.0)])
			var rho := _rng.randf_range(0.9, 1.3)
			var air: Dictionary = Air.compute(body, wind, rho)
			var d := _controls(model)
			var deltas := PackedFloat64Array()
			deltas.resize(3 * (model.envelope.station_ys.size() + 2))
			if i % 4 != 0:
				for slot in deltas.size(): deltas[slot] = _rng.randf_range(-0.5, 0.5)
				if model.surfaces.has("tailless"):
					for axis in 3: deltas[3 * model.envelope.station_ys.size() + axis] = 0.0
			var downwash: float = NAN if not model.surfaces.get("horizontal", {}).has("free_slope") or i % 2 == 0 else _rng.randf_range(-4.0, 20.0)
			var ground_up: float = NAN if i % 3 else 0.0
			for continuation: bool in [true, false]:
				var ref: Dictionary = Aero.ambient_spatial_continuation_loads(body, air, d, model, rho, deltas, downwash, ground_up) \
					if continuation else Aero.ambient_spatial_loads(body, air, d, model, rho, deltas, downwash, ground_up)
				var got: Dictionary = _native.spatial_aero_component(body, wind, rho, _deflection_array(d), deltas,
					downwash, ground_up, continuation)
				var args := [label, i, continuation, body, wind, rho, d, deltas, downwash, ground_up]
				_compare("spatial_aero_validity", PackedFloat64Array([1.0 if ref.ok else 0.0]),
					PackedFloat64Array([1.0 if got.ok else 0.0]), args)
				if not ref.ok or not got.ok:
					if not ref.ok and not got.ok:
						_compare("spatial_aero_refusal", str(ref.errors[0]), str(got.error), args)
					continue
				_compare("spatial_aero_loads", ref.loads, got.loads, args)
				_compare("spatial_aero_delta", ref.delta, got.delta, args)
				_compare("spatial_aero_wake", PackedFloat64Array([ref.held_wake_mps]), PackedFloat64Array([got.held_wake_mps]), args)
				_compare("spatial_aero_uniform", PackedFloat64Array([1.0 if ref.uniform else 0.0]),
					PackedFloat64Array([1.0 if got.uniform else 0.0]), args)
				if not ref.uniform and continuation:
					_compare("spatial_aero_zero_planes", PackedFloat64Array([ref.flow.reference_zero_plane_wing_stations,
						ref.flow.spatial_zero_plane_wing_stations]), PackedFloat64Array(got.zero_planes), args)
				_tally("spatial_aero_" + label, "continuation" if continuation else "attached")
				if ref.uniform: _tally("spatial_aero_" + label, "uniform")


func _geometry(prop: Dictionary) -> Dictionary:
	var out := {}
	for key: String in ["diameter", "offset", "ct", "cp", "rotor_inertia", "cp_min", "axis", "normal_force", "pfactor_moment"]:
		if prop.has(key): out[key] = prop[key]
	return out


func _check_weather_models(scenario: Dictionary, models: Array[Dictionary], per_pair: int) -> void:
	var built: Dictionary = WeatherField.build(scenario.config)
	if not built.ok:
		_failures.append("spatial weather build failed: " + str(scenario.id))
		return
	var field: RefCounted = built.field
	var prepared: Dictionary = _native.prepare_weather(WeatherAdapter.snapshot(field))
	if not prepared.ok:
		_failures.append("native spatial weather prepare failed %s: %s" % [scenario.id, prepared.error])
		return
	var windows: Array[Dictionary] = [{aux = PackedFloat64Array(), index = -1, dt = 1.0 / 240.0}]
	if field.has_turbulence():
		windows = _session_windows(scenario.config)
		if windows.size() != 3:
			_failures.append("missing real OU stage windows: " + str(scenario.id))
			return
	for row: Dictionary in models:
		var model: Dictionary = row.model
		var prop: Dictionary = model.propulsion
		var a: Dictionary = _native.prepare_aero(model)
		var p: Dictionary = _native.prepare_propeller(_geometry(prop))
		if not a.ok or not p.ok:
			_failures.append("spatial wake model prepare %s: %s / %s" % [row.name, a.error, p.error])
			continue
		var w: Dictionary = _native.prepare_wake(prop.get("slipstream", {}))
		if not w.ok:
			_failures.append("spatial wake prepare %s: %s" % [row.name, w.error])
			continue
		for i in per_pair:
			var window: Dictionary = windows[i % windows.size()]
			var environment := SimEnvironment.new()
			environment.weather = field
			if field.has_turbulence():
				environment.turbulence = func(at: float) -> PackedFloat64Array:
					return Session.turbulence_at(window.aux, window.index, at, window.dt)
			var body := _state_case(i)
			var time: float = _rng.randf_range(0.0, 60.0)
			if field.has_turbulence(): time = maxf(0.0, float(window.aux[window.index + 6]) + 0.5 * float(window.dt))
			var rho := _rng.randf_range(0.9, 1.3)
			var ref: Dictionary = WindFlow.stage_air(body, model, environment, time, rho, Aero.SPATIAL_CONTINUATION_LAW, false)
			var got: Dictionary = _native.spatial_flow_component(body, time, rho, window.aux, window.index, window.dt)
			var args := [scenario.id, row.name, i, body, time, rho, window]
			_compare("spatial_flow_validity", PackedFloat64Array([1.0 if ref.ok else 0.0]),
				PackedFloat64Array([1.0 if got.ok else 0.0]), args)
			if not ref.ok or not got.ok: continue
			var air: Dictionary = ref.air
			var datum_wind: PackedFloat64Array = environment.wind_world(body.slice(0, 3), time)
			_compare("spatial_reference_wind", datum_wind, got.reference_wind_ned, args)
			_compare("spatial_station_delta", air.aero_station_delta_body, got.station_delta_body, args)
			_compare("spatial_propeller_air", air.propulsion_air_body, got.propulsion_air_body, args)
			_compare("spatial_wake_source_delta", air.wake_source_delta_body, got.wake_source_delta_body, args)
			var controls := _controls(model)
			var packed := _deflection_array(controls)
			var rpm: float = float(prop.max_rpm) * _rng.randf_range(0.2, 1.0)
			if i % 13 == 0: rpm = 0.0
			var tq: PackedFloat64Array = Propulsion.thrust_torque(air.propulsion_air_body, rpm, prop, rho).slice(0, 2)
			var downwash: float = NAN if i % 2 == 0 else _rng.randf_range(-4.0, 20.0)
			var lagged := PackedFloat64Array()
			if WashTransport.enabled(prop):
				for _piece: Variant in prop.slipstream.pieces: lagged.append(_rng.randf_range(0.0, 8.0))
			var expected: PackedFloat64Array = Slipstream.stage_loads(body, air, controls, model, rpm, rho, downwash, lagged, 1, tq)
			var actual: Dictionary = _native.spatial_wake_component(body, time, rho, packed, rpm, tq, downwash,
				lagged, window.aux, window.index, window.dt)
			_compare("spatial_wake_validity", PackedFloat64Array([1.0]), PackedFloat64Array([1.0 if actual.ok else 0.0]), args)
			if actual.ok: _compare("spatial_wake_loads", expected, actual.loads, args)
			_tally("weather_" + str(scenario.id), "flow_states")
			if field.is_spatial(): _tally("weather_" + str(scenario.id), "spatial_field_states")

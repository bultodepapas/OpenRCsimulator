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
			"res://physics/swirl_loads.gd", "res://physics/wash_transport.gd",
			"res://tests/test_wash_profile.gd", "res://tests/test_wash_transport.gd",
			"res://tests/fixtures/stik_wash_profile.json"]:
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
						ref.flow.spatial_zero_plane_wing_stations]), PackedFloat64Array([got.zero_planes[0], got.zero_planes[1]]), args)
				_tally("spatial_aero_" + label, "continuation" if continuation else "attached")
				if ref.uniform: _tally("spatial_aero_" + label, "uniform")
		_check_spatial_boundaries(model, label)


func _check_spatial_boundaries(model: Dictionary, label: String) -> void:
	var base := PackedFloat64Array([0.0, 0.0, -10.0, 20.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var wind := PackedFloat64Array([0.0, 0.0, 0.0])
	var d := {elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0, flap = 0.0}
	var zero := PackedFloat64Array()
	zero.resize(3 * (model.envelope.station_ys.size() + 2))
	var cases: Array[Dictionary] = []
	var invalid_body := base.duplicate()
	invalid_body[3] = NAN
	cases.append({name = "nonfinite_body", body = invalid_body, rho = 1.225, delta = zero, wake = NAN, ground = NAN})
	invalid_body = base.duplicate()
	invalid_body[6] = 0.0
	cases.append({name = "zero_quaternion", body = invalid_body, rho = 1.225, delta = zero, wake = NAN, ground = NAN})
	# q0^2 is the binary64 value immediately below the engine-parsed 1e-24;
	# q1^2 adds exactly one ULP, and the next q0 makes the sum one ULP above.
	var q0: float = _from_bits(PackedInt64Array([0x3d719799812dea11]))[0]
	var q1: float = _from_bits(PackedInt64Array([0x3bd0000000000000]))[0]
	var qnext: float = _from_bits(PackedInt64Array([0x3d719799812dea12]))[0]
	for threshold: Dictionary in [{name = "quaternion_norm_below", q0 = q0, q1 = 0.0},
			{name = "quaternion_norm_equal", q0 = q0, q1 = q1},
			{name = "quaternion_norm_above", q0 = qnext, q1 = 0.0}]:
		var threshold_body := base.duplicate()
		threshold_body[6] = threshold.q0
		threshold_body[7] = threshold.q1
		cases.append({name = threshold.name, body = threshold_body, rho = 1.225, delta = zero, wake = NAN, ground = NAN})
	cases.append({name = "density_bound", body = base, rho = 1001.0, delta = zero, wake = NAN, ground = NAN})
	cases.append({name = "infinite_downwash", body = base, rho = 1.225, delta = zero, wake = INF, ground = NAN})
	cases.append({name = "infinite_ground", body = base, rho = 1.225, delta = zero, wake = NAN, ground = INF})
	cases.append({name = "short_delta", body = base, rho = 1.225, delta = zero.slice(1), wake = NAN, ground = NAN})
	var bad_delta := zero.duplicate()
	bad_delta[0] = NAN
	cases.append({name = "nonfinite_delta", body = base, rho = 1.225, delta = bad_delta, wake = NAN, ground = NAN})
	bad_delta = zero.duplicate()
	bad_delta[0] = 1001.0
	cases.append({name = "delta_bound", body = base, rho = 1.225, delta = bad_delta, wake = NAN, ground = NAN})
	bad_delta = zero.duplicate()
	bad_delta[0] = 600.0
	cases.append({name = "wing_flow_bound", body = base, rho = 1.225, delta = bad_delta, wake = NAN, ground = NAN})
	bad_delta = zero.duplicate()
	bad_delta[3 * (model.envelope.station_ys.size() + 1)] = 600.0
	cases.append({name = "tail_flow_bound", body = base, rho = 1.225, delta = bad_delta, wake = NAN, ground = NAN})
	if model.surfaces.has("tailless"):
		bad_delta = zero.duplicate()
		bad_delta[3 * model.envelope.station_ys.size()] = 0.1
		cases.append({name = "inactive_horizontal", body = base, rho = 1.225, delta = bad_delta, wake = NAN, ground = NAN})
	for test: Dictionary in cases:
		var air: Dictionary = Air.compute(test.body, wind, test.rho)
		var ref: Dictionary = Aero.ambient_spatial_continuation_loads(test.body, air, d, model, test.rho,
			test.delta, test.wake, test.ground)
		var got: Dictionary = _native.spatial_aero_component(test.body, wind, test.rho, _deflection_array(d),
			test.delta, test.wake, test.ground, true)
		var args := [label, test.name]
		_compare("spatial_boundary_validity", PackedFloat64Array([1.0 if ref.ok else 0.0]),
			PackedFloat64Array([1.0 if got.ok else 0.0]), args)
		if not ref.ok and not got.ok:
			_compare("spatial_boundary_error", str(ref.errors[0]), str(got.error), args)
			if got.has("loads") or got.has("delta"):
				_failures.append("spatial refusal exposed partial loads: " + str(args))
		elif ref.ok and got.ok:
			_compare("spatial_boundary_loads", ref.loads, got.loads, args)
		_tally("spatial_boundaries", str(test.name))


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
		if scenario.id == "calm" and row.name == AIRCRAFT:
			_check_flow_quaternion_boundaries(field, model)
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


func _check_flow_quaternion_boundaries(field: RefCounted, model: Dictionary) -> void:
	var environment := SimEnvironment.new()
	environment.weather = field
	var q0: float = _from_bits(PackedInt64Array([0x3d719799812dea11]))[0]
	var q1: float = _from_bits(PackedInt64Array([0x3bd0000000000000]))[0]
	var qnext: float = _from_bits(PackedInt64Array([0x3d719799812dea12]))[0]
	for test: Dictionary in [{name = "below", q0 = q0, q1 = 0.0, expected = false},
			{name = "equal", q0 = q0, q1 = q1, expected = false},
			{name = "above", q0 = qnext, q1 = 0.0, expected = true}]:
		var body := PackedFloat64Array([0.0, 0.0, -10.0, 20.0, 0.0, 0.0, test.q0, test.q1, 0.0, 0.0, 0.0, 0.0, 0.0])
		var ref: Dictionary = WindFlow.stage_air(body, model, environment, 0.0, 1.225, Aero.SPATIAL_CONTINUATION_LAW, false)
		var got: Dictionary = _native.spatial_flow_component(body, 0.0, 1.225, PackedFloat64Array(), -1, 1.0 / 240.0)
		_compare("spatial_flow_quaternion_validity", PackedFloat64Array([1.0 if test.expected else 0.0]),
			PackedFloat64Array([1.0 if ref.ok else 0.0]), test.name)
		_compare("spatial_flow_quaternion_validity", PackedFloat64Array([1.0 if ref.ok else 0.0]),
			PackedFloat64Array([1.0 if got.ok else 0.0]), test.name)

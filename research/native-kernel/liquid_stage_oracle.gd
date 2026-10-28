## NK-3 research-only joint-stage oracle for actual finite-liquid gas and
## turbine sessions. Paired tapes replace only VehicleModel.stage; all tick,
## resource, control, collision, and substep policies remain reference-owned.
extends "stage_oracle.gd"

const LiquidAdapter := preload("liquid_stage_adapter.gd")
const LiquidWeather := preload("res://physics/wind_config.gd")
const LiquidTurbine := preload("res://physics/turbine.gd")

const AIRCRAFT_IDS := ["p51d-mustang-120", "f4u-corsair-250", "sebart-avanti-s-a200-p100rx"]


func _extra_option_names() -> PackedStringArray:
	return PackedStringArray(["ticks"])


func _source_hashes() -> Dictionary:
	var out: Dictionary = super._source_hashes()
	for path: String in ["res://physics/retractable_gear.gd", "res://physics/effective_mass.gd",
			"res://physics/mass_inventory.gd", "res://physics/fixed_datum_body.gd", "res://physics/liquid_fuel.gd",
			"res://sim/liquid_fuel_flight.gd", "res://sim/aircraft_propulsion_runtime.gd", "res://physics/turbine.gd",
			"res://physics/wind_aircraft_flow.gd", "res://physics/wash_transport.gd", "res://physics/slipstream.gd",
			"res://physics/rotor_coupling.gd", "res://data/field_loader.gd", "res://data/lake_loader.gd",
			"res://data/fields/default.json", "res://data/fields/lake.json", "res://data/fuels/openrc-fuel-registry.json",
			"res://app_state/aircraft_catalog.gd", "res://data/aircraft/p51d_mustang_120.json",
			"res://data/aircraft/f4u_corsair_250.json", "res://data/aircraft/sebart_avanti_s_a200.json"]:
		out[path] = FileAccess.get_sha256(path)
	return out


func _checks() -> void:
	_report.format = "openrc-nk3-liquid-stage-oracle v1"
	var ticks: int = int(_options.get("ticks", "32"))
	if _states < 20 or ticks < 1:
		_failures.append("liquid stage needs at least 20 states and one trajectory tick")
		return
	_report.liquid_stage = {cases = [], trajectories = []}
	var scenarios: Array[Dictionary] = []
	for label: String in ["calm", "gusty", "turbulent", "hot-high", "standard-column",
			"spatial-gusty-v1", "spatial-thermal-soaring-v2"]:
		var config: Dictionary = LiquidWeather.preset(label)
		if config.is_empty():
			_failures.append("missing weather preset: " + label)
			continue
		if label == "gusty": config.gust_delay_s = 0.0
		if label == "spatial-gusty-v1": config.spatial_wind.gusts.events[0].start_s = 0.0
		if label == "spatial-thermal-soaring-v2":
			var cell: Dictionary = config.spatial_wind.thermal_field.cells[0]
			cell.birth_s = 0.0
			cell.duration_s = 120.0
			cell.center_ne_m = [60.0, -40.0]
			cell.drift_ne_mps = [0.0, 0.0]
		scenarios.append({id = label, config = config})
	if scenarios.size() != 7: return
	for id: String in AIRCRAFT_IDS:
		for scenario: Dictionary in scenarios:
			_check_case(id, scenario)
		_check_trajectory(id, "runway", scenarios[0], ticks)
		_check_trajectory(id, "trim", scenarios[6], ticks)
	if _report.liquid_stage.cases.size() != AIRCRAFT_IDS.size() * scenarios.size():
		_failures.append("liquid stage aircraft/weather matrix incomplete")
	if _report.liquid_stage.trajectories.size() != AIRCRAFT_IDS.size() * 2:
		_failures.append("liquid runway and airborne trajectory matrix incomplete")


func _liquid_compare(name: String, reference: Dictionary, native: Dictionary, inputs: Array) -> void:
	_compare(name + "_keys", var_to_bytes(reference.keys()), var_to_bytes(native.keys()), inputs)
	for key: String in ["loads", "derivative", "rotor_momentum", "body_derivative"]:
		_compare(name + "_" + key, reference.get(key), native.get(key), inputs)
	_compare(name + "_bytes", var_to_bytes(reference), var_to_bytes(native), inputs)


func _check_case(id: String, scenario: Dictionary) -> void:
	var label := "%s/%s" % [id, str(scenario.id)]
	var session := _build_session(id, "runway", false, scenario.config)
	if session == null: return
	var config: Dictionary = LiquidAdapter.config_for(session)
	var prepared: Dictionary = _native.prepare_stage(config) if not config.is_empty() else {ok = false, error = "missing provider or liquid source snapshot"}
	if not prepared.get("ok", false):
		_failures.append("liquid stage %s prepare refused: %s" % [label, str(prepared.get("error", ""))])
		session.free()
		return
	if session._weather.has_turbulence():
		session.sim.step()
		if session.sim.tick != 1 or session.sim.paused or not session.sim.fault_reason.is_empty():
			_failures.append("liquid weather pre_tick failed: " + label)
			session.free()
			return
	var context := {model = session.aircraft.model, gear = session.aircraft.model.landing_gear,
		surfaces = session.ground_surfaces, lake = session._lake, rest = session.sim.state.duplicate(),
		aux = session.sim.aux.duplicate(), deflections = session._deflections(session.sim.aux).duplicate()}
	var original: PackedFloat64Array = session.sim.continuous.duplicate()
	var rotor: int = session._rotor_index()
	var wheel: int = session.wheel_index()
	var fuel: int = session._liquid_index()
	var capacity: float = float(session.aircraft.model.propulsion.liquid_fuel.capacity_kg) \
		- float(session.aircraft.model.propulsion.liquid_fuel.unusable_kg)
	var turbine: bool = LiquidTurbine.is_turbine(session.aircraft.model.propulsion)
	if fuel + 2 != original.size() or wheel + session.wheel_count() != fuel:
		_failures.append("unexpected liquid layout: " + label)
		session.free()
		return
	# Exact accepted current stage is the only one entitled to the optional
	# substep preview. Test it separately before mutating the sampled states.
	if not LiquidAdapter.set_context(session, _native, session.sim.aux, session.sim.inputs, session.sim.time()):
		_failures.append("liquid stage preview handoff refused: " + label)
		session.free()
		return
	var initial_reference: Dictionary = session.sim.model.stage.call(session.sim.state, original, session.sim.time())
	var initial_native: Dictionary = _native.stage(session.sim.state, original, session.sim.time())
	_liquid_compare("liquid_initial_stage", initial_reference, initial_native, [label, session.sim.state, original, session.sim.time()])
	var preview_expected: bool = session._should_capture_substep_context(session.sim.state, original, session.sim.time())
	_compare("liquid_preview_presence", PackedFloat64Array([1.0 if preview_expected else 0.0]),
		PackedFloat64Array([1.0 if initial_reference.has("stage_context") else 0.0]), [label])
	var finite := 0
	var refused := 0
	var gear_down := 0
	var gear_partial := 0
	var gear_up := 0
	var source_off := 0
	for i: int in _states:
		var drawn := _stage_state(context, context.surfaces, context.lake)
		var body: PackedFloat64Array = drawn.s
		if session._weather.is_spatial() and not drawn.malformed:
			var domain: Dictionary = scenario.config.spatial_wind.domain
			body[0] = clampf(body[0], -float(domain.half_extent_north_m) + 5.0, float(domain.half_extent_north_m) - 5.0)
			body[1] = clampf(body[1], -float(domain.half_extent_east_m) + 5.0, float(domain.half_extent_east_m) - 5.0)
			body[2] = -_rng.randf_range(5.0, float(domain.max_height_agl_m) - 5.0)
			if scenario.id == "spatial-thermal-soaring-v2" and i % 7 == 0:
				body[0] = 60.0
				body[1] = -40.0
				body[2] = -float(scenario.config.spatial_wind.thermal_field.cells[0].top_agl_m) * 0.5
		var aux := _stage_aux(context, session, body)
		var gear_index: int = session.gear_aux_index()
		var fraction: float = [0.0, 0.35, 1.0, 0.7][i % 4]
		aux[gear_index] = fraction
		aux[gear_index + 1] = 1.0 if i % 2 == 0 else 0.0
		if fraction == 0.0: gear_up += 1
		elif fraction == 1.0: gear_down += 1
		else: gear_partial += 1
		if session.flaps_available(): aux[session.flap_aux_index()] = _rng.randf_range(0.0, 1.0)
		session.sim.aux = aux
		session.sim.inputs[3] = _rng.randf_range(0.0, 1.0)
		session.sim.inputs[5] = _rng.randf_range(0.0, 1.0)
		session.engine_running = i % 5 != 0
		if not session.engine_running: source_off += 1
		if not LiquidAdapter.set_context(session, _native, aux, session.sim.inputs, session.sim.time()):
			_failures.append("liquid stage context refused: " + label)
			break
		var values: PackedFloat64Array = original.duplicate()
		for k: int in rotor: values[k] = _rng.randf_range(0.0, 15.0)
		values[rotor] = _rng.randf_range(0.0, float(session.aircraft.model.propulsion.max_rpm))
		for k: int in range(wheel, fuel): values[k] = _rng.randf_range(-25.0, 25.0)
		values[fuel] = capacity * _rng.randf_range(0.0, 1.0)
		values[fuel + 1] = 1.0 if i % 3 != 0 else 0.0
		match i % 13:
			0: values[fuel] = capacity + 1.0
			1: values[fuel] = -0.001
			2: values[fuel + 1] = 2.0
			3: values[rotor] = -0.001
			4: values[rotor] = 0.0
			5: values[rotor] = 0.5
			6: values.resize(values.size() - 1)
			7: values[fuel] = 0.0
			8: values[fuel] = capacity
		var stage_time: float = [0.0, 0.01, 0.5, 4.0, 10.0, 30.0][i % 6]
		if session._weather.has_turbulence():
			stage_time = aux[session.turbulence_index() + 6] + session.sim.dt() * [0.0, 0.5, 1.0][i % 3]
		var reference: Dictionary = session.sim.model.stage.call(body, values, stage_time)
		var native: Dictionary = _native.stage(body, values, stage_time)
		_liquid_compare("liquid_stage", reference, native, [label, i, body, aux, values, stage_time, session.sim.inputs, session.engine_running])
		if _finite_stage(reference, values.size()): finite += 1
		else: refused += 1
	if finite == 0 or refused == 0 or gear_down == 0 or gear_partial == 0 or gear_up == 0 or source_off == 0:
		_failures.append("liquid stage %s missed a required branch" % label)
	_report.liquid_stage.cases.append({name = label, states = _states, finite = finite, refused = refused,
		gear_up = gear_up, gear_partial = gear_partial, gear_down = gear_down, source_off = source_off,
		preview_expected = preview_expected, family = "turbine" if turbine else "gas", wash_count = rotor})
	session.free()


static func _finite_stage(stage: Dictionary, derivative_size: int) -> bool:
	for key: String in ["loads", "derivative", "rotor_momentum", "body_derivative"]:
		if not stage.get(key) is PackedFloat64Array: return false
	if stage.loads.size() != 6 or stage.derivative.size() != derivative_size or stage.rotor_momentum.size() != 3 \
			or stage.body_derivative.size() != 13: return false
	for array: PackedFloat64Array in [stage.loads, stage.derivative, stage.rotor_momentum, stage.body_derivative]:
		for value: float in array:
			if not is_finite(value): return false
	return true


static func _tape(session: Node) -> PackedByteArray:
	var sim: Node = session.sim
	return var_to_bytes([sim.tick, sim.state, sim.previous, sim.aux, sim.continuous, sim.inputs, sim.last_loads, sim.modes])


func _check_trajectory(id: String, start: String, scenario: Dictionary, ticks: int) -> void:
	var label := "%s/%s/%s" % [id, start, str(scenario.id)]
	var reference := _build_session(id, start, false, scenario.config)
	var native := _build_session(id, start, false, scenario.config)
	if reference == null or native == null:
		if reference != null: reference.free()
		if native != null: native.free()
		return
	var config: Dictionary = LiquidAdapter.config_for(native)
	var prepared: Dictionary = _native.prepare_stage(config) if not config.is_empty() else {ok = false, error = "missing provider or liquid source snapshot"}
	if not prepared.get("ok", false):
		_failures.append("liquid trajectory %s prepare refused: %s" % [label, str(prepared.get("error", ""))])
		reference.free()
		native.free()
		return
	var inner: Callable = native.sim.model.pre_tick
	var context_state := {ok = true}
	var wrapped := func(aux: PackedFloat64Array, inputs: PackedFloat64Array, dt: float) -> Variant:
		var next: Variant = inner.call(aux, inputs, dt)
		if next is PackedFloat64Array and next.size() == aux.size():
			context_state.ok = bool(context_state.ok) and LiquidAdapter.set_context(native, _native, next, inputs, native.sim.time())
		return next
	native.sim.model.pre_tick = wrapped
	native.sim.model.stage = Callable(_native, "stage")
	context_state.ok = LiquidAdapter.set_context(native, _native, native.sim.aux, native.sim.inputs, native.sim.time())
	_native.reset_stage_stats(false)
	var previous: Dictionary = _native.stage_stats()
	var complete := true
	var ran := 0
	var first_divergence := -1
	if not _compare("liquid_trajectory_tick", _tape(reference), _tape(native), [label, 0]): first_divergence = 0
	for i: int in ticks:
		var inputs: PackedFloat64Array = reference.sim.inputs.duplicate()
		inputs[0] = 0.02 if i % 40 < 20 else -0.02
		inputs[1] = 0.03 if i % 60 < 30 else -0.03
		inputs[3] = [0.2, 0.5, 0.8][(i / 16) % 3]
		inputs[4] = 1.0 if start == "runway" else (0.0 if i < ticks / 2 else 1.0)
		inputs[5] = 0.15 if start == "runway" else 0.0
		if reference.flaps_available(): inputs[reference.flap_input_index()] = 0.3 if i >= ticks / 2 else 0.0
		reference.sim.inputs = inputs.duplicate()
		native.sim.inputs = inputs.duplicate()
		reference.sim.step()
		native.sim.step()
		var stats: Dictionary = _native.stage_stats()
		var healthy: bool = reference.sim.tick == i + 1 and native.sim.tick == i + 1 and context_state.ok \
			and not reference.sim.paused and not native.sim.paused and reference.sim.fault_reason.is_empty() \
			and native.sim.fault_reason.is_empty() and reference.crash.is_empty() and native.crash.is_empty()
		var covered: bool = native.sim.model.stage == Callable(_native, "stage") and native.sim.model.pre_tick == wrapped \
			and int(stats.get("stage_calls", 0)) - int(previous.get("stage_calls", 0)) >= 4 \
			and int(stats.get("context_calls", 0)) - int(previous.get("context_calls", 0)) >= 1
		if not healthy or not covered:
			_failures.append("liquid trajectory %s tick %d failed or lacked native coverage: %s/%s" %
				[label, i + 1, reference.sim.fault_reason, native.sim.fault_reason])
			complete = false
			break
		previous = stats
		ran += 1
		if not _compare("liquid_trajectory_tick", _tape(reference), _tape(native), [label, i + 1]) and first_divergence < 0:
			first_divergence = i + 1
	_report.liquid_stage.trajectories.append({name = label, requested_ticks = ticks, ticks_run = ran,
		complete = complete and ran == ticks, first_divergence = first_divergence,
		native_stage_calls = int(previous.get("stage_calls", 0)), native_context_calls = int(previous.get("context_calls", 0))})
	if first_divergence >= 0: _failures.append("liquid trajectory %s diverged at tick %d" % [label, first_divergence])
	reference.free()
	native.free()

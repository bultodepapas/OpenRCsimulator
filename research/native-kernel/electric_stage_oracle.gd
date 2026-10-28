## NK-3 research-only electric joint-stage oracle: compare actual coupled
## FlightSession stages and bounded paired kernel tapes. Admission is unchanged.
extends "stage_oracle.gd"

const ElectricAdapter := preload("electric_stage_adapter.gd")
const ElectricWeather := preload("res://physics/wind_config.gd")

const ELECTRIC_AIRCRAFT := ["turbo-lumber-evolution", "skywalker-x8"]


func _extra_option_names() -> PackedStringArray:
	return PackedStringArray(["ticks"])


func _source_hashes() -> Dictionary:
	var out: Dictionary = super._source_hashes()
	for path: String in ["res://physics/rotor_coupling.gd", "res://physics/rigid_body.gd",
			"res://physics/wind_aircraft_flow.gd", "res://physics/wash_transport.gd", "res://physics/slipstream.gd",
			"res://physics/battery/esc_supervisor.gd", "res://app_state/aircraft_catalog.gd",
			"res://data/aircraft/turbo_lumber_evolution.json", "res://data/aircraft/skywalker_x8.json",
			"res://data/aircraft/battery/turbo_lumber_evolution_4s_pack.json",
			"res://data/aircraft/battery/skywalker_x8_6s_pack.json",
			"res://data/batteries/packs/lipo-4s1p-3200-30c-class.json",
			"res://data/batteries/packs/lipo-6s1p-5000-30c-class.json",
			"res://data/batteries/cells/lipo-bak503562-galeotti-v1.json"]:
		out[path] = FileAccess.get_sha256(path)
	return out


func _checks() -> void:
	_report.format = "openrc-nk3-electric-stage-oracle v1"
	var ticks: int = int(_options.get("ticks", "64"))
	if _states < 1 or ticks < 1:
		_failures.append("electric stage states and ticks must be positive")
		return
	_report.electric_stage = {cases = [], trajectories = []}
	var scenarios: Array[Dictionary] = []
	for label: String in ["calm", "gusty", "turbulent", "hot-high", "standard-column",
			"spatial-gusty-v1", "spatial-thermal-soaring-v2"]:
		var config: Dictionary = ElectricWeather.preset(label)
		if config.is_empty():
			_failures.append("electric stage weather preset absent: " + label)
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
	var mode_index := 0
	for id: String in ELECTRIC_AIRCRAFT:
		for battery: String in ["ideal", "pack"]:
			for scenario: Dictionary in scenarios:
				_check_electric_stage(id, battery, scenario, _states)
			# Four complementary short tapes; the larger fleet/weather matrix is a separate gate.
			var trajectory_weather: Dictionary = scenarios[[0, 2, 3, 6][mode_index]]
			_check_electric_trajectory(id, battery, trajectory_weather, ticks)
			mode_index += 1


func _electric_session(id: String, battery: String, weather: Dictionary) -> Node:
	var session: Node = Session.new()
	session.input_enabled = true
	session.physics_enabled = true
	session.crash_auto_restart = false
	session.soft_hull_contacts = true
	session.setup(Catalog.data_for(id, battery), id)
	if not session.is_flyable():
		_failures.append("electric session %s/%s failed: %s" % [id, battery, session.pause_reason])
		session.free()
		return null
	if not session.setup_weather(weather):
		_failures.append("electric weather %s/%s failed: %s" % [id, battery, session.weather_error])
		session.free()
		return null
	var field: Dictionary = FieldLoader.load_from()
	var lake: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	if not field.ok or not lake.ok or not session.set_field(field.field) or not session.set_lake_context(lake.lake):
		_failures.append("electric field/lake setup failed: %s/%s" % [id, battery])
		session.free()
		return null
	session.start_choice = Session.START_AIRBORNE
	session.reset()
	if session.sim.paused or not session.sim.fault_reason.is_empty() or not session.crash.is_empty():
		_failures.append("electric session reset failed %s/%s: %s" % [id, battery, session.pause_reason])
		session.free()
		return null
	return session


func _electric_aux(context: Dictionary, session: Node, state: PackedFloat64Array) -> PackedFloat64Array:
	var gear: Dictionary = context.gear
	var aux: PackedFloat64Array
	if gear.has("contacts") and not gear.contacts.is_empty():
		aux = _stage_aux(context, session, state)
	else:
		aux = context.aux.duplicate()
		for k: int in 3: aux[Session.AUX_SERVO + k] = _rng.randf_range(-1.0, 1.0)
		var lag: int = session.downwash_index()
		if lag >= 0: aux[lag] = _rng.randf_range(-5.0, 30.0)
	if session.flaps_available():
		var flap: int = session.flap_aux_index()
		if flap >= 0 and flap < aux.size(): aux[flap] = _rng.randf_range(0.0, 1.0)
	return aux


func _check_electric_stage(id: String, battery: String, scenario: Dictionary, count: int) -> void:
	var label := "%s/%s/%s" % [id, battery, str(scenario.id)]
	var session := _electric_session(id, battery, scenario.config)
	if session == null: return
	var config: Dictionary = ElectricAdapter.config_for(session)
	var prepared: Dictionary = _native.prepare_stage(config) if not config.is_empty() else {ok = false, error = "provider identity refused"}
	if not prepared.get("ok", false):
		_failures.append("electric stage %s prepare refused: %s" % [label, str(prepared.get("error", ""))])
		session.free()
		return
	# Use the owner's actual OU window after pre_tick, not independently invented noise.
	if session._weather.has_turbulence():
		session.sim.step()
		if session.sim.tick != 1 or session.sim.paused or not session.sim.fault_reason.is_empty():
			_failures.append("electric stage turbulence pre_tick failed: " + label)
			session.free()
			return
	var context := {model = session.aircraft.model, gear = session.current_landing_gear(session.sim.aux),
		surfaces = session.ground_surfaces, lake = session._lake, rest = session.sim.state.duplicate(),
		aux = session.sim.aux.duplicate(), deflections = session._deflections(session.sim.aux).duplicate()}
	var original: PackedFloat64Array = session.sim.continuous.duplicate()
	var rotor_index: int = session._rotor_index()
	var wheel_index: int = session.wheel_index()
	var charge_index: int = rotor_index + 1
	var initial_charge: float = session._battery_initial_charge() if session.battery_is_dynamic() else 0.0
	var finite := 0
	var refused := 0
	for i: int in count:
		var drawn := _stage_state(context, context.surfaces, context.lake)
		var state: PackedFloat64Array = drawn.s
		if session._weather.is_spatial() and not drawn.malformed:
			var domain: Dictionary = scenario.config.spatial_wind.domain
			state[RB.POS] = clampf(state[RB.POS], -float(domain.half_extent_north_m) + 5.0,
				float(domain.half_extent_north_m) - 5.0)
			state[RB.POS + 1] = clampf(state[RB.POS + 1], -float(domain.half_extent_east_m) + 5.0,
				float(domain.half_extent_east_m) - 5.0)
			state[RB.POS + 2] = -_rng.randf_range(5.0, float(domain.max_height_agl_m) - 5.0)
			if scenario.id == "spatial-thermal-soaring-v2" and i % 7 == 0:
				state[RB.POS] = 60.0
				state[RB.POS + 1] = -40.0
				state[RB.POS + 2] = -float(scenario.config.spatial_wind.thermal_field.cells[0].top_agl_m) * 0.5
		var aux := _electric_aux(context, session, state)
		session.sim.aux = aux
		session.sim.inputs[3] = _rng.randf_range(0.0, 1.0)
		session.engine_running = i % 5 != 0
		if not ElectricAdapter.set_context(session, _native, aux, session.sim.inputs, session.sim.time()):
			_failures.append("electric stage context refused: " + label)
			break
		var values: PackedFloat64Array = original.duplicate()
		for k: int in rotor_index: values[k] = _rng.randf_range(-10.0, 20.0)
		values[rotor_index] = _rng.randf_range(0.0, float(session.aircraft.model.propulsion.max_rpm))
		if i % 13 == 0: values[rotor_index] = [0.0, -0.001, 0.5, 1.0][(i / 13) % 4]
		if session.battery_is_dynamic():
			values[charge_index] = _rng.randf_range(0.0, initial_charge)
			if i % 29 == 0: values[charge_index] = [0.0, -0.001, initial_charge, initial_charge + 1.0][(i / 29) % 4]
		for k: int in range(wheel_index, values.size()): values[k] = _rng.randf_range(-25.0, 25.0)
		if i > 0 and i % 83 == 0: values.resize(values.size() - 1)
		var stage_time: float = [0.0, 0.01, 0.5, 4.0, 10.0, 30.0][i % 6]
		if session._weather.has_turbulence():
			var ti: int = session.turbulence_index()
			stage_time = aux[ti + 6] + session.sim.dt() * [0.0, 0.5, 1.0][i % 3]
		var reference: Dictionary = session._coupled_evaluate(state, values, stage_time)
		var native: Dictionary = _native.stage(state, values, stage_time)
		_compare_stage(reference, native, [label, i, state, aux, values, stage_time, session.sim.inputs, session.engine_running])
		if _electric_finite_stage(reference, values.size()): finite += 1
		else: refused += 1
		_tally("electric_stage", "states")
	if finite == 0 or refused == 0:
		_failures.append("electric stage %s missed finite or refused stages" % label)
	_report.electric_stage.cases.append({name = label, states = count, finite = finite, refused = refused,
		wheel_count = session.wheel_count(), wash_count = rotor_index, battery_size = session._battery_block_size()})
	session.free()


static func _electric_finite_stage(stage: Dictionary, derivative_size: int) -> bool:
	if not stage.get("loads") is PackedFloat64Array or not stage.get("derivative") is PackedFloat64Array \
			or not stage.get("rotor_momentum") is PackedFloat64Array or stage.loads.size() != 6 \
			or stage.derivative.size() != derivative_size or stage.rotor_momentum.size() != 3:
		return false
	for values: PackedFloat64Array in [stage.loads, stage.derivative, stage.rotor_momentum]:
		for value: float in values:
			if not is_finite(value): return false
	return true


static func _electric_tape(session: Node) -> PackedByteArray:
	var sim: Node = session.sim
	return var_to_bytes([sim.tick, sim.state, sim.previous, sim.aux, sim.continuous, sim.inputs, sim.last_loads, sim.modes])


func _check_electric_trajectory(id: String, battery: String, scenario: Dictionary, ticks: int) -> void:
	var label := "%s/%s/%s" % [id, battery, str(scenario.id)]
	var reference := _electric_session(id, battery, scenario.config)
	var native := _electric_session(id, battery, scenario.config)
	if reference == null or native == null:
		if reference != null: reference.free()
		if native != null: native.free()
		return
	var config: Dictionary = ElectricAdapter.config_for(native)
	var prepared: Dictionary = _native.prepare_stage(config) if not config.is_empty() else {ok = false, error = "provider identity refused"}
	if not prepared.get("ok", false):
		_failures.append("electric trajectory %s prepare failed: %s" % [label, str(prepared.get("error", ""))])
		reference.free()
		native.free()
		return
	var inner: Callable = native.sim.model.pre_tick
	var context_state := {ok = true}
	var wrapped := func(aux: PackedFloat64Array, inputs: PackedFloat64Array, dt: float) -> Variant:
		var next: Variant = inner.call(aux, inputs, dt)
		if next is PackedFloat64Array and next.size() == aux.size():
			context_state.ok = bool(context_state.ok) and ElectricAdapter.set_context(native, _native, next, inputs, native.sim.time())
		return next
	native.sim.model.pre_tick = wrapped
	native.sim.model.stage = Callable(_native, "stage")
	context_state.ok = ElectricAdapter.set_context(native, _native, native.sim.aux, native.sim.inputs, native.sim.time())
	_native.reset_stage_stats(false)
	var previous: Dictionary = _native.stage_stats()
	var complete := true
	var ran := 0
	var first_divergence := -1
	if not _compare("electric_trajectory_tick", _electric_tape(reference), _electric_tape(native), [label, 0]): first_divergence = 0
	for i: int in ticks:
		var inputs: PackedFloat64Array = reference.sim.inputs.duplicate()
		if inputs.size() >= 4:
			inputs[0] = 0.04 if i % 40 < 20 else -0.04
			inputs[1] = 0.02 if i % 60 < 30 else -0.02
			inputs[3] = [0.2, 0.5, 0.8][(i / 16) % 3]
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
			_failures.append("electric trajectory %s tick %d failed or lacked native coverage: %s/%s" %
				[label, i + 1, reference.sim.fault_reason, native.sim.fault_reason])
			complete = false
			break
		previous = stats
		ran += 1
		if not _compare("electric_trajectory_tick", _electric_tape(reference), _electric_tape(native), [label, i + 1]) and first_divergence < 0:
			first_divergence = i + 1
	_report.electric_stage.trajectories.append({name = label, requested_ticks = ticks, ticks_run = ran,
		complete = complete and ran == ticks, first_divergence = first_divergence,
		native_stage_calls = int(previous.get("stage_calls", 0)), native_context_calls = int(previous.get("context_calls", 0))})
	if first_divergence >= 0: _failures.append("electric trajectory %s diverged at tick %d" % [label, first_divergence])
	reference.free()
	native.free()

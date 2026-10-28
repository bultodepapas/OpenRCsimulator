## Prescribed-fuel shaft/turbine stages on validated reference session fixtures.
## The source fixtures are the existing P-51 and Avanti test constructions:
## disable the finite-fuel adapter, retaining the aircraft's actual coefficients.
extends "stage_oracle.gd"

const PrescribedAdapter := preload("res://sim/native/prescribed_stage_adapter.gd")
const WeatherAdapter := preload("res://sim/native/weather_adapter.gd")
const NativeConfiguration := preload("res://sim/native/native_configuration.gd")
const NativeStage := preload("res://sim/native_stage.gd")
const WheelProfiles := preload("res://physics/wheel_profiles.gd")
const Weather := preload("res://physics/wind_config.gd")
const WashFixture := preload("res://tests/test_wash_profile.gd")

const MODES := ["shaft-split", "shaft-coupled", "shaft-split-transport", "shaft-coupled-transport",
	"turbine-sampled", "turbine-continuous"]
const WEATHER := ["calm", "gusty", "turbulent", "hot-high", "standard-column",
	"spatial-gusty-v1", "spatial-thermal-soaring-v2"]
const P51_PATH := "res://data/aircraft/p51d_mustang_120.json"
const JET_PATH := "res://data/aircraft/sebart_avanti_s_a200.json"
const STIK_PATH := "res://data/aircraft/jensen_ugly_stik_60.json"


func _extra_option_names() -> PackedStringArray:
	return PackedStringArray(["ticks"])


func _source_hashes() -> Dictionary:
	var out: Dictionary = super._source_hashes()
	for path: String in ["res://sim/native/prescribed_stage_adapter.gd", "res://physics/turbine.gd",
			"res://physics/rotor_coupling.gd", "res://physics/wind_aircraft_flow.gd",
			"res://physics/wash_transport.gd", "res://physics/wheel_profiles.gd",
			"res://tests/test_shaft_coupled.gd", "res://tests/test_turbine_continuous.gd",
			"res://tests/test_wash_profile.gd", P51_PATH, JET_PATH, STIK_PATH]:
		out[path] = FileAccess.get_sha256(path)
	return out


func _checks() -> void:
	_report.format = "openrc-nk3-prescribed-stage-oracle v1"
	_report.prescribed_stage = {cases = [], trajectories = [], events = [], callback_routes = [], previews = [], refusals = [],
		shaft_transitions = []}
	var ticks: int = int(_options.get("ticks", "64"))
	if _states <= 0 or ticks <= 0:
		_failures.append("prescribed states and ticks must be positive")
		return
	for mode: String in MODES:
		for weather: String in WEATHER:
			_check_case(mode, weather)
		_check_tape(mode, "calm", ticks, false)
		_check_tape(mode, "calm", ticks, true)
	for mode: String in ["shaft-coupled", "shaft-coupled-transport"]:
		for weather: String in ["calm", "turbulent", "spatial-thermal-soaring-v2"]:
			_check_preview(mode, weather)
	_check_callback_route("legacy-no-gear", false, ticks)
	_check_callback_route("shaft-split-no-gear", false, ticks)
	_check_callback_route("shaft-split-no-gear-transport", true, ticks)
	_check_shaft_transition(ticks)


func _session(mode: String, weather_id: String) -> Node:
	var turbine := mode.begins_with("turbine")
	var generic := mode == "legacy-no-gear"
	var path := STIK_PATH if generic else (JET_PATH if turbine else P51_PATH)
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not generic:
		raw.propulsion.erase("fuel_consumption")
		raw.capabilities.energy = "prescribed_fuel"
	if turbine:
		raw.propulsion.engine.spool_integrator = "rk4" if mode == "turbine-continuous" else "sampled"
	if "transport" in mode:
		var wash: Dictionary = WashFixture.combined_raw().propulsion.propeller.slipstream
		wash.transport_speed_floor = WashFixture.quantity(1.0, "m/s")
		raw.propulsion.propeller.thrust_angles = WashFixture.quantity([0.0, 0.0], "deg")
		raw.propulsion.propeller.slipstream = wash
	if "no-gear" in mode:
		raw.erase("landing_gear")
		raw.capabilities.gear = "locked_up"
		raw.id = "workshop-prescribed-no-gear"
	var checked: Dictionary = AircraftData.validate_and_derive(raw)
	if not checked.get("ok", false):
		_failures.append("prescribed fixture invalid %s: %s" % [mode, str(checked.get("errors", []))])
		return null
	var profiled: Dictionary = WheelProfiles.apply_to_model(checked.model)
	if not profiled.get("ok", false):
		_failures.append("prescribed wheel profile %s: %s" % [mode, str(profiled.get("errors", []))])
		return null
	checked.model = profiled.model
	checked.wheel_profile_identity = profiled.identity
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(JSON.stringify(raw, "", true, true).to_utf8_buffer())
	checked.input_identity = {format = AircraftData.FORMAT, sha256 = digest.finish().hex_encode()}
	var session: Node = Session.new()
	session.input_enabled = false
	session.crash_auto_restart = false
	session.soft_hull_contacts = true
	if mode.begins_with("shaft-coupled") and not session.setup_shaft_integrator("coupled-rk4"):
		_failures.append("prescribed coupled choice refused: " + session.shaft_error)
		session.free()
		return null
	session.setup("synthetic://prescribed-oracle", raw.id, checked)
	if not session.is_flyable() or not session.setup_weather(Weather.preset(weather_id)):
		_failures.append("prescribed session %s/%s refused: %s %s" % [mode, weather_id, session.pause_reason, session.weather_error])
		session.free()
		return null
	var field: Dictionary = FieldLoader.load_from()
	var lake: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	if not field.ok or not lake.ok or not session.set_field(field.field) or not session.set_lake_context(lake.lake):
		_failures.append("prescribed field/lake refused: " + mode)
		session.free()
		return null
	session.start_choice = Session.START_AIRBORNE
	session.reset()
	if not session.is_flyable() or session.sim.paused or not session.sim.fault_reason.is_empty():
		_failures.append("prescribed reset %s/%s refused: %s" % [mode, weather_id, session.pause_reason])
		session.free()
		return null
	return session


func _reference_stage(session: Node, body: PackedFloat64Array, values: PackedFloat64Array, at: float) -> Dictionary:
	if session.sim.model.stage.is_valid():
		return session.sim.model.stage.call(body, values, at)
	return {loads = session.sim.model.block_loads.call(body, values, at),
		derivative = session.sim.model.block_derivative.call(body, values, at),
		rotor_momentum = session.sim.model.rotor_momentum.call(session.sim.aux)}


func _check_case(mode: String, weather_id: String) -> void:
	var label := mode + "/" + weather_id
	var session := _session(mode, weather_id)
	if session == null: return
	var config: Dictionary = PrescribedAdapter.config_for(session)
	var prepared: Dictionary = _native.prepare_stage(config) if not config.is_empty() else {ok = false, error = "missing snapshot"}
	if not prepared.get("ok", false):
		_failures.append("prescribed stage %s refused: %s" % [label, str(prepared.get("error", ""))])
		session.free()
		return
	if session._weather.has_turbulence():
		session.sim.step()
		if session.sim.tick != 1 or not session.sim.fault_reason.is_empty():
			_failures.append("prescribed turbulence pre-tick failed: " + label)
			session.free()
			return
	var context := {model = session.aircraft.model, gear = session.current_landing_gear(session.sim.aux),
		surfaces = session.ground_surfaces, lake = session._lake, rest = session.sim.state.duplicate(),
		aux = session.sim.aux.duplicate(), deflections = session._deflections(session.sim.aux).duplicate()}
	var original: PackedFloat64Array = session.sim.continuous.duplicate()
	var finite := 0
	var refused := 0
	var tested := 0
	for i: int in _states:
		var drawn := _stage_state(context, context.surfaces, context.lake)
		var state: PackedFloat64Array = drawn.s
		if session._weather.is_spatial() and not drawn.malformed:
			var domain: Dictionary = session._weather.configuration().spatial_wind.domain
			state[0] = clampf(state[0], -float(domain.half_extent_north_m) + 5.0, float(domain.half_extent_north_m) - 5.0)
			state[1] = clampf(state[1], -float(domain.half_extent_east_m) + 5.0, float(domain.half_extent_east_m) - 5.0)
			state[2] = -_rng.randf_range(5.0, float(domain.max_height_agl_m) - 5.0)
		var aux := _stage_aux(context, session, state)
		if session.gear_is_retractable():
			aux[session.gear_aux_index()] = [0.0, 0.35, 0.7, 1.0][i % 4]
			aux[session.gear_aux_index() + 1] = float(i % 2)
		if session.flaps_available(): aux[session.flap_aux_index()] = _rng.randf_range(0.0, 1.0)
		session.sim.aux = aux
		session.sim.inputs[3] = _rng.randf_range(0.0, 1.0)
		session.engine_running = i % 5 != 0
		if not PrescribedAdapter.set_context(session, _native, aux, session.sim.inputs, session.sim.time()):
			_failures.append("prescribed context refused: " + label)
			break
		var values: PackedFloat64Array = original.duplicate()
		for k: int in session._rotor_index(): values[k] = _rng.randf_range(0.0, 15.0)
		if session.shaft_is_coupled() or session.turbine_is_continuous():
			values[session._rotor_index()] = _rng.randf_range(0.0, float(session.aircraft.model.propulsion.max_rpm))
			if i % 13 == 0: values[session._rotor_index()] = [0.0, -0.001, 0.5, 1.0][(i / 13) % 4]
		for k: int in range(session.wheel_index(), values.size()): values[k] = _rng.randf_range(-25.0, 25.0)
		if i > 0 and i % 83 == 0: values.resize(values.size() - 1)
		var at: float = [0.0, 0.01, 0.5, 4.0, 10.0, 30.0][i % 6]
		if session._weather.has_turbulence():
			at = aux[session.turbulence_index() + 6] + session.sim.dt() * [0.0, 0.5, 1.0][i % 3]
		var reference := _reference_stage(session, state, values, at)
		var actual: Dictionary = _native.stage(state, values, at)
		_compare_stage(reference, actual, [label, i, state, aux, values, at, session.engine_running])
		if _finite_stage(reference, values.size()): finite += 1
		else: refused += 1
		tested += 1
		_tally("prescribed_stage", "states")
	if finite == 0 or refused == 0: _failures.append("prescribed stage lacks finite/refused coverage: " + label)
	_report.prescribed_stage.cases.append({name = label, states = tested, finite = finite, refused = refused})
	if weather_id == "calm": _check_snapshot_refusals(mode, config, session)
	session.free()


static func _finite_stage(stage: Dictionary, size: int) -> bool:
	if not stage.get("loads") is PackedFloat64Array or not stage.get("derivative") is PackedFloat64Array \
			or not stage.get("rotor_momentum") is PackedFloat64Array or stage.loads.size() != 6 \
			or stage.derivative.size() != size or stage.rotor_momentum.size() != 3: return false
	for array: PackedFloat64Array in [stage.loads, stage.derivative, stage.rotor_momentum]:
		for value: float in array:
			if not is_finite(value): return false
	return true


func _check_snapshot_refusals(mode: String, config: Dictionary, session: Node) -> void:
	var variants := []
	var changed: Dictionary = config.duplicate(true)
	changed.prescribed.source.rotor_inertia = float(changed.prescribed.source.rotor_inertia) + 0.001
	variants.append({name = "source_mismatch", config = changed})
	changed = config.duplicate(true)
	changed.prescribed.kind = "unregistered"
	variants.append({name = "mode", config = changed})
	changed = config.duplicate(true)
	changed.prescribed.extra = 1
	variants.append({name = "extra_key", config = changed})
	changed = config.duplicate(true)
	changed.prescribed.source.unregistered = 1.0
	changed.model.propulsion.unregistered = 1.0
	variants.append({name = "unregistered_source_on_both_sides", config = changed})
	changed = config.duplicate(true)
	changed.rotor_dynamics = not bool(changed.rotor_dynamics)
	variants.append({name = "rotor_capability", config = changed})
	if config.prescribed.source.has("axis"):
		changed = config.duplicate(true)
		var axis: PackedFloat64Array = changed.prescribed.source.axis.duplicate()
		for i: int in axis.size():
			if axis[i] == 0.0:
				axis[i] = _from_bits(PackedInt64Array([-9223372036854775808 if _bits(axis[i]) == 0 else 0]))[0]
				changed.prescribed.source.axis = axis
				variants.append({name = "axis_zero_sign", config = changed})
				break
	if config.has("inverse"):
		changed = config.duplicate(true)
		changed.inverse[0] += 0.001
		variants.append({name = "inverse", config = changed})
	for item: Dictionary in variants:
		var result: Dictionary = _native.prepare_stage(item.config)
		var refused: bool = not result.get("ok", true) and not str(result.get("error", "")).is_empty()
		_compare("prescribed_snapshot_refusal", PackedFloat64Array([1.0]), PackedFloat64Array([1.0 if refused else 0.0]), [mode, item.name])
		_report.prescribed_stage.refusals.append({mode = mode, name = item.name, refused = refused})
		if not refused or not _native.stage(session.sim.state, session.sim.continuous, session.sim.time()).is_empty():
			_failures.append("prescribed snapshot refusal failed: %s/%s" % [mode, item.name])


func _check_preview(mode: String, weather_id: String) -> void:
	var label := mode + "/" + weather_id
	var session := _session(mode, weather_id)
	if session == null: return
	session.engine_running = false
	session.sim.continuous[session._rotor_index()] = 300.0
	session.sim.aux[Session.AUX_RPM] = 300.0
	if not session.sim.reset(session.sim.state.duplicate()):
		_failures.append("prescribed preview seed refused: " + label)
		session.free()
		return
	var prepared: Dictionary = _native.prepare_stage(PrescribedAdapter.config_for(session))
	if not prepared.get("ok", false) or not PrescribedAdapter.set_context(session, _native,
			session.sim.aux, session.sim.inputs, session.sim.time()):
		_failures.append("prescribed preview prepare refused: " + label)
		session.free()
		return
	var body: PackedFloat64Array = session.sim.state
	var values: PackedFloat64Array = session.sim.continuous
	var at: float = session.sim.time()
	var expected: Dictionary = session.sim.model.stage.call(body, values, at)
	var actual: Dictionary = _native.stage(body, values, at)
	var present: bool = expected.has("stage_context") and actual.has("stage_context")
	var equal: bool = _compare("prescribed_preview_presence", PackedFloat64Array([1.0]),
		PackedFloat64Array([1.0 if present else 0.0]), [label])
	if present:
		for key: String in ["loads", "derivative", "rotor_momentum"]:
			equal = _compare("prescribed_preview_" + key, expected.get(key), actual.get(key), [label]) and equal
		var reference: Dictionary = expected.duplicate(true)
		var native: Dictionary = actual.duplicate(true)
		var ref_air: Dictionary = reference.stage_context.air
		var native_air: Dictionary = native.stage_context.air
		if ref_air.has("spatial_sampler") and native_air.has("spatial_sampler"):
			var valid: bool = is_instance_valid(ref_air.spatial_sampler) and is_instance_valid(native_air.spatial_sampler) \
				and ref_air.ambient_delta_body_at is Callable and ref_air.ambient_delta_body_at.is_valid() \
				and native_air.ambient_delta_body_at is Callable and native_air.ambient_delta_body_at.is_valid()
			equal = _compare("prescribed_preview_sampler_valid", PackedFloat64Array([1.0]),
				PackedFloat64Array([1.0 if valid else 0.0]), [label]) and equal
			if valid:
				for point: PackedFloat64Array in [PackedFloat64Array([0.0, 0.0, 0.0]),
						PackedFloat64Array([1.0, 0.5, -0.25]), PackedFloat64Array([-0.5, -0.8, 0.4])]:
					equal = _compare("prescribed_preview_sampler_delta", ref_air.ambient_delta_body_at.call(point),
						native_air.ambient_delta_body_at.call(point), [label, point]) and equal
		for air: Dictionary in [ref_air, native_air]:
			air.erase("spatial_sampler")
			air.erase("ambient_delta_body_at")
		equal = _compare("prescribed_preview_bytes", var_to_bytes(reference), var_to_bytes(native), [label]) and equal
	var no_time_expected: Dictionary = session.sim.model.stage.call(body, values, NAN)
	var no_time_actual: Dictionary = _native.stage(body, values, NAN)
	var no_time_ok: bool = not no_time_expected.has("stage_context") and not no_time_actual.has("stage_context")
	equal = _compare("prescribed_preview_nan_time", var_to_bytes(no_time_expected), var_to_bytes(no_time_actual), [label]) and equal
	# At first setup the owner may have the same empty body in both arguments;
	# its generic preview predicate would accept that equality, but the native
	# adapter must decline capture and still accept the tick context.
	session.sim.state = PackedFloat64Array()
	var would_capture: bool = session._should_capture_substep_context(session.sim.state, values, at)
	var initial_context: bool = PrescribedAdapter.set_context(session, _native, session.sim.aux, session.sim.inputs, at)
	session.sim.state = body
	equal = _compare("prescribed_preview_empty_body", PackedFloat64Array([1.0, 1.0]),
		PackedFloat64Array([1.0 if would_capture else 0.0, 1.0 if initial_context else 0.0]), [label]) and equal
	_report.prescribed_stage.previews.append({name = label, present = present, no_time_ok = no_time_ok,
		initial_body_would_capture = would_capture, initial_context_accepted = initial_context, identical = equal})
	if not present or not no_time_ok or not initial_context or not would_capture or not equal:
		_failures.append("prescribed preview differed: " + label)
	session.free()


static func _tape(session: Node) -> PackedByteArray:
	var sim: Node = session.sim
	return var_to_bytes([sim.tick, sim.state, sim.previous, sim.aux, sim.continuous, sim.inputs,
		sim.last_loads, sim.modes, sim.last_events, session.crash])


func _install_research(session: Node, prescribed: bool, session_owned := false) -> Dictionary:
	var builder: Callable = PrescribedAdapter.config_for if prescribed else WeatherAdapter.config_for
	var boundary: Dictionary = NativeConfiguration.prepare(session, builder)
	if not boundary.get("ok", false): return {ok = false, error = str(boundary.get("reason", "boundary"))}
	var prepared: Dictionary = _native.prepare_stage(boundary.config)
	if not prepared.get("ok", false): return {ok = false, error = str(prepared.get("error", "native"))}
	if not _native.prepare_weather_guard(session, boundary.weather_identity).get("ok", false) \
			or not _native.prepare_configuration_guard(session, boundary.identity).get("ok", false):
		return {ok = false, error = "guard refused"}
	var helper := NativeStage.new()
	helper._native = _native
	helper._prepared = true
	helper._family = "prescribed" if prescribed else "wheel"
	helper._configuration_identity = boundary.identity
	helper._weather_identity = boundary.weather_identity
	var original := {stage = session.sim.model.stage, loads = session.sim.model.loads,
		rotor = session.sim.model.rotor_momentum, pre_tick = session.sim.model.pre_tick}
	if session_owned: session._native_stage = helper
	helper.install(session)
	if not helper.is_installed() or not helper.owns_stage(session) \
			or not helper.tick_context(session, session.sim.aux, session.sim.inputs, session.sim.time()):
		if helper.is_installed(): helper.uninstall(session)
		if session_owned: session._native_stage = null
		return {ok = false, error = helper.reason}
	return {ok = true, helper = helper, original = original}


func _check_tape(mode: String, weather_id: String, ticks: int, event: bool) -> void:
	var reference := _session(mode, weather_id)
	var native := _session(mode, weather_id)
	if reference == null or native == null:
		if reference != null: reference.free()
		if native != null: native.free()
		return
	var label := mode + ("/power-cut-restart" if event else "/" + weather_id)
	if event:
		for flight: Node in [reference, native]:
			var body: PackedFloat64Array = flight.sim.state.duplicate()
			for k: int in range(RB.VEL, RB.VEL + 3): body[k] = 0.0
			for k: int in range(RB.RATE, RB.RATE + 3): body[k] = 0.0
			flight.engine_running = true
			flight.sim.inputs[3] = 0.0
			# The prescribed continuous turbine has no hot-cut/rundown law; seed
			# its supported stopped boundary, while the other modes cut at 0.5 rpm.
			var initial_rpm := 0.0 if mode == "turbine-continuous" else 0.5
			flight.sim.aux[Session.AUX_RPM] = initial_rpm
			if flight.shaft_is_coupled() or flight.turbine_is_continuous(): flight.sim.continuous[flight._rotor_index()] = initial_rpm
			if not flight.sim.reset(body): _failures.append("prescribed event seed refused: " + label)
	var installed := _install_research(native, true)
	if not installed.get("ok", false):
		_failures.append("prescribed tape install %s: %s" % [label, str(installed.get("error", ""))])
		reference.free()
		native.free()
		return
	var helper: RefCounted = installed.helper
	_native.reset_stage_stats(false)
	var previous: Dictionary = _native.stage_stats()
	var ran := 0
	var first := -1
	var cut_ok := false
	var restart_ok := false
	var commands: Array[Dictionary] = []
	if event: commands.append({tick = 0, engine_running = true, throttle = 0.0})
	if not _compare("prescribed_event_tick" if event else "prescribed_trajectory_tick", _tape(reference), _tape(native), [label, 0]): first = 0
	for i: int in ticks:
		if event and i == 0:
			for flight: Node in [reference, native]: flight.engine_running = false
			commands.append({tick = i + 1, engine_running = false, throttle = 0.0})
		elif event and i == 2:
			for flight: Node in [reference, native]:
				flight.engine_running = true
				flight.sim.inputs[3] = 0.7
			commands.append({tick = i + 1, engine_running = true, throttle = 0.7})
		elif not event:
			reference.sim.inputs[3] = [0.2, 0.5, 0.8][(i / 16) % 3]
			native.sim.inputs[3] = reference.sim.inputs[3]
		reference.sim.step()
		native.sim.step()
		var stats: Dictionary = _native.stage_stats()
		var healthy: bool = reference.sim.tick == i + 1 and native.sim.tick == i + 1 \
			and not reference.sim.paused and not native.sim.paused and reference.sim.fault_reason.is_empty() \
			and native.sim.fault_reason.is_empty() and reference.crash.is_empty() and native.crash.is_empty()
		var covered: bool = helper.owns_stage(native) and helper.configuration_matches(native) \
			and int(stats.stage_calls) - int(previous.stage_calls) >= 4 \
			and int(stats.context_calls) - int(previous.context_calls) >= 1
		if not healthy or not covered:
			_failures.append("prescribed tape %s tick %d incomplete: %s / %s" % [label, i + 1, reference.sim.fault_reason, native.sim.fault_reason])
			break
		previous = stats
		ran += 1
		if event:
			var rpm: float = reference.sim.aux[Session.AUX_RPM]
			if i < 2 and not reference.engine_running and rpm <= 1.0: cut_ok = true
			if i >= 2 and reference.engine_running and rpm > 1.0: restart_ok = true
		if not _compare("prescribed_event_tick" if event else "prescribed_trajectory_tick", _tape(reference), _tape(native), [label, i + 1]) and first < 0: first = i + 1
	var row := {name = label, requested_ticks = ticks, ticks_run = ran, complete = ran == ticks,
		first_divergence = first, native_stage_calls = int(previous.stage_calls), native_context_calls = int(previous.context_calls)}
	if event:
		row.merge({event_observed = cut_ok and restart_ok, cut_ok = cut_ok, restart_ok = restart_ok,
			event_tick = 1 if cut_ok else -1, commands = commands,
			seed = "stopped boundary; hot cutoff has no prescribed law" if mode == "turbine-continuous" else "running source at 0.5 rpm"})
		_report.prescribed_stage.events.append(row)
		if not cut_ok or not restart_ok: _failures.append("prescribed cut/restart not observed: " + label)
	else:
		_report.prescribed_stage.trajectories.append(row)
	if first >= 0: _failures.append("prescribed tape diverged: %s tick %d" % [label, first])
	helper.uninstall(native)
	reference.free()
	native.free()


func _check_callback_route(mode: String, transport: bool, ticks: int) -> void:
	var reference := _session(mode, "calm")
	var native := _session(mode, "calm")
	if reference == null or native == null:
		if reference != null: reference.free()
		if native != null: native.free()
		return
	var original_stage: Callable = native.sim.model.stage
	var original_loads: Callable = native.sim.model.loads
	var original_rotor: Callable = native.sim.model.rotor_momentum
	var installed := _install_research(native, mode != "legacy-no-gear")
	if not installed.get("ok", false):
		_failures.append("gearless native install %s: %s" % [mode, str(installed.get("error", ""))])
		reference.free()
		native.free()
		return
	var helper: RefCounted = installed.helper
	var correct_route: bool = not original_stage.is_valid() and \
		((not transport and native.sim.continuous.is_empty() and not native.sim.model.stage.is_valid() \
			and native.sim.model.loads == Callable(_native, "body_loads") \
			and native.sim.model.rotor_momentum == Callable(_native, "body_rotor")) \
		or (transport and not native.sim.continuous.is_empty() and native.sim.model.stage == Callable(_native, "stage")))
	_native.reset_stage_stats(false)
	var previous: Dictionary = _native.stage_stats()
	var ran := 0
	var equal := _compare("prescribed_callback_tick", _tape(reference), _tape(native), [mode, 0])
	for i: int in ticks:
		reference.sim.step()
		native.sim.step()
		var stats: Dictionary = _native.stage_stats()
		if reference.sim.tick != i + 1 or native.sim.tick != i + 1 or not helper.owns_stage(native) \
				or not helper.configuration_matches(native) \
				or int(stats.stage_calls) - int(previous.stage_calls) < 4 or int(stats.context_calls) - int(previous.context_calls) < 1:
			break
		previous = stats
		ran += 1
		equal = _compare("prescribed_callback_tick", _tape(reference), _tape(native), [mode, i + 1]) and equal
	helper.uninstall(native)
	var restored: bool = native.sim.model.stage == original_stage and native.sim.model.loads == original_loads \
		and native.sim.model.rotor_momentum == original_rotor
	var complete := correct_route and equal and restored and ran == ticks
	_report.prescribed_stage.callback_routes.append({name = mode, requested_ticks = ticks, ticks_run = ran,
		complete = complete, correct_route = correct_route, restored = restored,
		native_stage_calls = int(previous.stage_calls), native_context_calls = int(previous.context_calls)})
	if not complete: _failures.append("gearless route incomplete: %s; route=%s restored=%s %d/%d" % [mode, correct_route, restored, ran, ticks])
	reference.free()
	native.free()


## A session-owned body-only evaluator must restore both reference callbacks
## before a launch-time shaft selection releases its native helper. Unlike the
## ordinary callback oracle, this path exercises FlightSession's real owner.
func _check_shaft_transition(ticks: int) -> void:
	var receipt_path := _extension.get_base_dir().path_join("build-receipt_mutant.json" \
		if "_mutant" in _extension.get_file() else "build-receipt.json")
	var receipt: Variant = JSON.parse_string(FileAccess.get_file_as_string(receipt_path))
	if receipt is Dictionary and receipt.has("platforms"):
		receipt = receipt.get("platforms", {}).get("linux", {})
	if not receipt is Dictionary or not receipt.has_all(["binary_sha256", "source_sha256", "lock_sha256"]):
		_failures.append("shaft transition could not read the selected build identity")
		return
	# The research oracle loads the extension directly, before NativeStage's app
	# loader. Its helper still needs the selected binary's real checkpoint identity.
	var previous_receipt: Dictionary = NativeStage._receipt_row
	NativeStage._receipt_row = receipt
	var result := _run_shaft_transition(ticks)
	NativeStage._receipt_row = previous_receipt
	_report.prescribed_stage.shaft_transitions.append(result)
	if not result.get("complete", false):
		_failures.append("gearless shaft transition incomplete: " + str(result))


func _reference_body_callbacks(session: Node) -> bool:
	var model: RefCounted = session.sim.model
	return model.loads.is_valid() and model.rotor_momentum.is_valid() \
		and model.loads == Callable(session, "_loads") \
		and model.rotor_momentum == Callable(session, "rotor_momentum")


func _run_shaft_transition(ticks: int) -> Dictionary:
	var result := {name = "gearless-split-coupled-split", complete = false,
		initial_body_owned = false, coupled_selected = false, coupled_callbacks_restored = false,
		coupled_reset = false, coupled_reinstalled = false, coupled_tape = {},
		split_selected = false, split_callbacks_restored = false, split_reset = false,
		split_reinstalled = false, split_tape = {}, uninstall_restored = false}
	var reference := _session("shaft-split-no-gear", "calm")
	var native := _session("shaft-split-no-gear", "calm")
	if reference == null or native == null:
		if reference != null: reference.free()
		if native != null: native.free()
		return result
	var installed := _install_research(native, true, true)
	if installed.get("ok", false):
		var helper: RefCounted = installed.helper
		result.initial_body_owned = helper.owns_stage(native) and native._native_stage == helper \
			and native.sim.continuous.is_empty() and not native.sim.model.stage.is_valid() \
			and native.sim.model.loads == Callable(_native, "body_loads") \
			and native.sim.model.rotor_momentum == Callable(_native, "body_rotor")
		var reference_selected: bool = reference.setup_shaft_integrator("coupled-rk4")
		var native_selected: bool = native.setup_shaft_integrator("coupled-rk4")
		result.coupled_selected = reference_selected and native_selected and native._native_stage == null
		result.coupled_callbacks_restored = _reference_body_callbacks(native)
		_compare("prescribed_transition_callbacks", PackedFloat64Array([1.0, 1.0]),
			PackedFloat64Array([1.0 if result.coupled_selected else 0.0,
				1.0 if result.coupled_callbacks_restored else 0.0]), ["coupled-selection"])
		if result.coupled_selected and result.coupled_callbacks_restored:
			reference.reset()
			native.reset()
			result.coupled_reset = reference.is_flyable() and native.is_flyable() \
				and reference.start_error.is_empty() and native.start_error.is_empty() \
				and reference.shaft_is_coupled() and native.shaft_is_coupled()
			if result.coupled_reset:
				installed = _install_research(native, true, true)
				result.coupled_reinstalled = installed.get("ok", false)
				if result.coupled_reinstalled:
					result.coupled_tape = _shaft_transition_tape(reference, native, installed.helper, ticks, "coupled")
					# The supported mode choice is restricted to tick zero.
					reference.reset()
					native.reset()
					installed = _install_research(native, true, true) if native.is_flyable() else {ok = false}
					if installed.get("ok", false):
						reference_selected = reference.setup_shaft_integrator("split")
						native_selected = native.setup_shaft_integrator("split")
						result.split_selected = reference_selected and native_selected and native._native_stage == null
						result.split_callbacks_restored = _reference_body_callbacks(native)
						_compare("prescribed_transition_callbacks", PackedFloat64Array([1.0, 1.0]),
							PackedFloat64Array([1.0 if result.split_selected else 0.0,
								1.0 if result.split_callbacks_restored else 0.0]), ["split-selection"])
						if result.split_selected and result.split_callbacks_restored:
							reference.reset()
							native.reset()
							result.split_reset = reference.is_flyable() and native.is_flyable() \
								and reference.start_error.is_empty() and native.start_error.is_empty() \
								and not reference.shaft_is_coupled() and not native.shaft_is_coupled() \
								and native.sim.continuous.is_empty()
							if result.split_reset:
								installed = _install_research(native, true, true)
								result.split_reinstalled = installed.get("ok", false)
								if result.split_reinstalled:
									helper = installed.helper
									result.split_tape = _shaft_transition_tape(reference, native, helper, ticks, "split")
									helper.uninstall(native)
									native._native_stage = null
									result.uninstall_restored = _reference_body_callbacks(native) \
										and not native.sim.model.stage.is_valid()
	result.complete = result.initial_body_owned and result.coupled_selected and result.coupled_callbacks_restored \
		and result.coupled_reset and result.coupled_reinstalled and result.coupled_tape.get("complete", false) \
		and result.split_selected and result.split_callbacks_restored and result.split_reset \
		and result.split_reinstalled and result.split_tape.get("complete", false) and result.uninstall_restored
	if native._native_stage != null:
		native._native_stage.uninstall(native)
		native._native_stage = null
	reference.free()
	native.free()
	return result


func _shaft_transition_tape(reference: Node, native: Node, helper: RefCounted, ticks: int, label: String) -> Dictionary:
	_native.reset_stage_stats(false)
	var previous: Dictionary = _native.stage_stats()
	var ran := 0
	var first := -1
	if not _compare("prescribed_transition_tick", _tape(reference), _tape(native), [label, 0]): first = 0
	for i: int in ticks:
		reference.sim.step()
		native.sim.step()
		var stats: Dictionary = _native.stage_stats()
		if reference.sim.tick != i + 1 or native.sim.tick != i + 1 \
				or not reference.sim.fault_reason.is_empty() or not native.sim.fault_reason.is_empty() \
				or native._native_stage != helper or not helper.owns_stage(native) or not helper.configuration_matches(native) \
				or int(stats.stage_calls) - int(previous.stage_calls) < 4 \
				or int(stats.context_calls) - int(previous.context_calls) < 1:
			break
		previous = stats
		ran += 1
		if not _compare("prescribed_transition_tick", _tape(reference), _tape(native), [label, i + 1]) and first < 0:
			first = i + 1
	return {requested_ticks = ticks, ticks_run = ran, complete = ran == ticks and first < 0,
		first_divergence = first, native_stage_calls = int(previous.stage_calls), native_context_calls = int(previous.context_calls)}

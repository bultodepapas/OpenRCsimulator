# M5-W05c-R2: powered point flow and one-owner aero/propulsion/wash composition.
# In-memory fields and manufactured wash are diagnostic fixtures, not admitted weather or aircraft data.
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const M := preload("res://physics/math3d.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const RB := preload("res://physics/rigid_body.gd")
const Slipstream := preload("res://physics/slipstream.gd")
const Turbine := preload("res://physics/turbine.gd")
const WindAircraftFlow := preload("res://physics/wind_aircraft_flow.gd")
const RHO := Air.RHO_SEA_LEVEL


class SyntheticField extends RefCounted:
	var origin_ned := PackedFloat64Array([0.0, 0.0, 0.0])
	var uniform := false
	var uniform_value := PackedFloat64Array([0.3, -0.2, 0.1])
	var fail_next := false
	var fail_after_time := INF
	var calls := 0

	func wind_world(position_ned: PackedFloat64Array, time_s: float) -> PackedFloat64Array:
		calls += 1
		if fail_next:
			fail_next = false
			return PackedFloat64Array([0.0, NAN, 0.0])
		if time_s > fail_after_time:
			return PackedFloat64Array([0.0, NAN, 0.0])
		if uniform:
			return uniform_value.duplicate()
		var n := position_ned[0] - origin_ned[0]
		var e := position_ned[1] - origin_ned[1]
		var d := position_ned[2] - origin_ned[2]
		return PackedFloat64Array([
			0.25 + 0.035 * n + 0.045 * e - 0.012 * d + 0.015 * time_s,
			-0.10 + 0.018 * n - 0.021 * e + 0.010 * d - 0.008 * time_s,
			0.08 - 0.013 * n + 0.016 * e + 0.019 * d + 0.006 * time_s,
		])


class StageFlight extends "res://sim/flight_session.gd":
	const StageFlow := preload("res://physics/wind_aircraft_flow.gd")
	const StageAir := preload("res://physics/air_data.gd")
	var stage_environment: Object
	var stage_air_calls := 0
	var stage_failures := 0
	var last_stage_air: Dictionary = {}

	func air_data(s: PackedFloat64Array, time_s: float = NAN) -> Dictionary:
		if stage_environment == null:
			return super.air_data(s, time_s)
		var sample_time: float = sim.time() if is_nan(time_s) else time_s
		var rho: float = air_density(s)
		var result: Dictionary = StageFlow.stage_air(s, aircraft.model, stage_environment, sample_time, rho)
		stage_air_calls += 1
		if not result.get("ok", false):
			stage_failures += 1
			# Preserve the ordinary Air dictionary shape so the existing transaction sees nonfinite loads.
			return StageAir.compute(s, PackedFloat64Array([NAN, NAN, NAN]), rho)
		last_stage_air = result.air
		return result.air


var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s%s" % [label, " — " + detail if not detail.is_empty() else ""])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var configs := _catalog_models()
	_check("fleet fixtures include every admitted fixed-wing model and the finite battery pack",
		configs.size() >= 12, "loaded %d" % configs.size())
	for mode: String in ["ideal", "pack"]:
		_check("X8 " + mode + " is covered by powered point flow",
			not _model_for(configs, "skywalker-x8", mode).is_empty())
	_check("finite Lumber pack configuration is present",
		not _model_for(configs, "turbo-lumber-evolution", "pack").is_empty())
	_check_stage_air_fleet(configs)
	_check_uniform_load_parity(configs)
	_check_spatial_composition_and_wash_failure()
	_check_stale_receipts(configs)
	_check_powered_sessions()
	print("Spatial powered stage: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _catalog_models() -> Array:
	var configs: Array = []
	for id: String in Catalog.airplane_flyable_ids():
		var modes: Array[String] = ["ideal"]
		if Catalog.has_battery_mode(id, "pack"):
			modes.append("pack")
		for mode: String in modes:
			var path: String = Catalog.data_for(id, mode)
			var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			_check("%s/%s source parses" % [id, mode], raw is Dictionary, path)
			if not raw is Dictionary:
				continue
			var loaded: Dictionary = AD.validate_and_derive(raw)
			_check("%s/%s physics data normalizes" % [id, mode], bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
			if loaded.get("ok", false):
				configs.append({"id": id, "mode": mode, "model": loaded.model})
	return configs


func _model_for(configs: Array, id: String, mode: String) -> Dictionary:
	for config: Dictionary in configs:
		if config.id == id and config.mode == mode:
			return config.model
	return {}


func _check_stage_air_fleet(configs: Array) -> void:
	var state := _state(M.q_from_euler(0.31, -0.17, 0.12))
	var time_s := 2.375
	var rho := 1.07
	var field := SyntheticField.new()
	field.origin_ned = state.slice(RB.POS, RB.POS + 3)
	for config: Dictionary in configs:
		var model: Dictionary = config.model
		var label: String = "%s/%s" % [config.id, config.mode]
		var result: Dictionary = WindAircraftFlow.stage_air(state, model, field, time_s, rho)
		_check(label + " stage builder succeeds", bool(result.get("ok", false)), str(result.get("errors", [])))
		if not result.get("ok", false):
			continue
		var flow: Dictionary = result.flow
		var air: Dictionary = result.air
		var geometry: Dictionary = WindAircraftFlow.geometry(model)
		_check(label + " fleet geometry succeeds", bool(geometry.get("ok", false)), str(geometry.get("errors", [])))
		if not geometry.get("ok", false):
			continue
		_check(label + " stage law and exact state/time/density receipt",
			air.get("spatial_air_law", "") == WindAircraftFlow.STAGE_AIR_LAW
			and air.spatial_state.to_byte_array() == state.to_byte_array()
			and float(air.spatial_time_s) == time_s and float(air.spatial_rho) == rho)
		var reference_air: Dictionary = Air.compute(state, flow.reference_wind_ned, rho)
		_check(label + " datum Air.compute fields retain exact stage values",
			air.v_air.to_byte_array() == reference_air.v_air.to_byte_array()
			and air.V == reference_air.V and air.alpha == reference_air.alpha
			and air.beta == reference_air.beta and air.qbar == reference_air.qbar)
		var expected_aero_delta: PackedFloat64Array = flow.delta_body.slice(0, 24)
		_check(label + " eight aero stations carry ambient-only deltas",
			air.aero_station_delta_body.to_byte_array() == expected_aero_delta.to_byte_array()
			and air.aero_station_delta_body.size() == 24)

		var propulsion_index: int = int(flow.propulsion_index)
		_check(label + " includes its physical hub/intake station", propulsion_index >= 0,
			str(model.propulsion.get("kind", "")))
		if propulsion_index < 0:
			continue
		var point_start := propulsion_index * 3
		var arm: PackedFloat64Array = geometry.offsets_body.slice(point_start, point_start + 3)
		var point_position := M.add(state.slice(RB.POS, RB.POS + 3), M.q_rotate(state.slice(RB.ATT, RB.ATT + 4), arm))
		var sampled_position: PackedFloat64Array = flow.positions_ned.slice(point_start, point_start + 3)
		_check(label + " hub/intake world position uses authored FRD geometry",
			_near_array(sampled_position, point_position) and geometry.offsets_body.to_byte_array() == flow.offsets_body.to_byte_array(),
			"%s != %s" % [sampled_position, point_position])
		var independent_delta := _ambient_delta(field, state, arm, time_s)
		var expected_point_air := _point_air(state, reference_air.v_air, arm, independent_delta)
		var sampled_point_air: PackedFloat64Array = flow.relative_body.slice(point_start, point_start + 3)
		_check(label + " point flow has ambient delta and omega-cross-arm exactly once",
			_near_array(sampled_point_air, expected_point_air))
		_check(label + " Air carries the complete point velocity and ambient-only wake delta",
			air.propulsion_air_body.to_byte_array() == sampled_point_air.to_byte_array()
			and air.wake_source_delta_body.to_byte_array() == flow.delta_body.slice(point_start, point_start + 3).to_byte_array())
		var sampler: Callable = air.get("ambient_delta_body_at", Callable())
		_check(label + " has a valid per-point ambient-delta sampler", sampler.is_valid())
		if sampler.is_valid():
			var sampled_delta: PackedFloat64Array = sampler.call(arm)
			_check(label + " point sampler queries the same physical point/time",
				_near_array(sampled_delta, independent_delta))
		var explicit: Dictionary = Propulsion.stage_air_velocity(state, air, model.propulsion)
		_check(label + " propulsion accepts the explicit complete point flow",
			bool(explicit.get("ok", false)) and explicit.velocity_body.to_byte_array() == sampled_point_air.to_byte_array(),
			str(explicit.get("message", "")))
		var legacy: Dictionary = Propulsion.stage_air_velocity(state, reference_air, model.propulsion)
		var expected_legacy := _legacy_point_air(state, reference_air.v_air, model.propulsion)
		_check(label + " no-key propulsion fallback retains direct local-point arithmetic",
			bool(legacy.get("ok", false)) and legacy.velocity_body.to_byte_array() == expected_legacy.to_byte_array())


func _check_uniform_load_parity(configs: Array) -> void:
	var state := _state(M.q_from_euler(-0.19, 0.13, -0.09))
	var time_s := 1.75
	var rho := 1.11
	var deflections := _neutral()
	for config: Dictionary in configs:
		var model: Dictionary = config.model
		var label: String = "%s/%s" % [config.id, config.mode]
		var field := SyntheticField.new()
		field.uniform = true
		field.origin_ned = state.slice(RB.POS, RB.POS + 3)
		var stage: Dictionary = WindAircraftFlow.stage_air(state, model, field, time_s, rho)
		_check(label + " uniform stage airs", bool(stage.get("ok", false)), str(stage.get("errors", [])))
		if not stage.get("ok", false):
			continue
		var air: Dictionary = stage.air
		var rpm := _test_rpm(model.propulsion)
		var actual: PackedFloat64Array = Dynamics.loads_from_air(state, model, deflections, rpm, rho, air)
		var reference_air: Dictionary = Air.compute(state, field.uniform_value, rho)
		var geometry: Dictionary = WindAircraftFlow.geometry(model)
		var point_start: int = 3 * int(geometry.propulsion_index)
		var arm: PackedFloat64Array = geometry.offsets_body.slice(point_start, point_start + 3)
		var expected_point := _point_air(state, reference_air.v_air, arm, PackedFloat64Array([0.0, 0.0, 0.0]))
		_check(label + " uniform explicit point retains authored station rotation at nonzero body rates",
			_near_array(air.propulsion_air_body, expected_point, 1e-11),
			"%s != physical point %s at arm %s" % [air.propulsion_air_body, expected_point, arm])
		_check(label + " Dynamics consumes the explicit stage point and composes loads once",
			actual.to_byte_array() == _manual_air_loads(state, model, deflections, rpm, rho, air).to_byte_array(),
			"%s != composed %s" % [actual, _manual_air_loads(state, model, deflections, rpm, rho, air)])
		var legacy_air: Dictionary = reference_air
		var legacy_point: Dictionary = Propulsion.stage_air_velocity(state, legacy_air, model.propulsion)
		var legacy_direct: PackedFloat64Array = legacy_point.get("velocity_body", PackedFloat64Array())
		var legacy_manual: PackedFloat64Array = _manual_air_loads(state, model, deflections, rpm, rho, legacy_air)
		var legacy_actual: PackedFloat64Array = Dynamics.loads(state, model, deflections, rpm, rho, field.uniform_value)
		_check(label + " no-field Dynamics preserves exact historical fallback and loads",
			bool(legacy_point.get("ok", false)) and legacy_direct.to_byte_array()
			== _legacy_point_air(state, legacy_air.v_air, model.propulsion).to_byte_array()
			and legacy_actual.to_byte_array() == legacy_manual.to_byte_array(),
			"fallback %s; actual %s; manual %s" % [legacy_direct, legacy_actual, legacy_manual])
		_check(label + " explicit uniform point can differ from legacy no-key flow by omega cross arm",
			_near_array(legacy_direct, expected_point, 1e-11)
			== _near_array(air.propulsion_air_body, legacy_direct, 1e-11),
			"explicit %s; legacy %s" % [air.propulsion_air_body, legacy_direct])


func _check_spatial_composition_and_wash_failure() -> void:
	var model := _synthetic_wash_model()
	_check("manufactured in-memory wash model validates", not model.is_empty())
	if model.is_empty():
		return
	var state := _state(M.q_identity(), M.v3(15.0, 0.1, -0.05), M.v3(0.18, -0.14, 0.11))
	var time_s := 0.625
	var field := SyntheticField.new()
	field.origin_ned = state.slice(RB.POS, RB.POS + 3)
	var rho := RHO
	var rpm := _test_rpm(model.propulsion)
	var d := _neutral()
	var stage: Dictionary = WindAircraftFlow.stage_air(state, model, field, time_s, rho)
	_check("wash fixture stage builds", bool(stage.get("ok", false)), str(stage.get("errors", [])))
	if not stage.get("ok", false):
		return
	var air: Dictionary = stage.air
	var aero: Dictionary = Aero.ambient_spatial_loads(state, air, d, model, rho,
		air.aero_station_delta_body, 0.0, NAN)
	_check("spatial wing/tail bridge accepts the synthetic field", bool(aero.get("ok", false)), str(aero.get("errors", [])))
	if not aero.get("ok", false):
		return
	var point: Dictionary = Propulsion.stage_air_velocity(state, air, model.propulsion)
	_check("wash fixture has explicit point inflow", bool(point.get("ok", false)), str(point.get("message", "")))
	if not point.get("ok", false):
		return
	var point_air: PackedFloat64Array = point.velocity_body
	var prop_loads: PackedFloat64Array = Propulsion.loads(point_air, rpm, model.propulsion, rho)
	var tq: PackedFloat64Array = Propulsion.thrust_torque(point_air, rpm, model.propulsion, rho).slice(0, 2)
	var wash: PackedFloat64Array = Slipstream.stage_loads(state, air, d, model, rpm, rho, 0.0,
		PackedFloat64Array(), 1, tq)
	var expected: PackedFloat64Array = aero.loads.duplicate()
	for axis in 6:
		expected[axis] += prop_loads[axis]
		expected[axis] += wash[axis]
	var actual: PackedFloat64Array = Dynamics.loads_from_air(state, model, d, rpm, rho, air, 0.0)
	_check("Dynamics consumes aero, point propulsion and matched wash once each",
		_finite(actual, 6) and actual.to_byte_array() == expected.to_byte_array(),
		"actual %s != composed %s" % [actual, expected])
	_check("fixture excites the unwashed spatial aero correction", _norm6(aero.delta) > 1e-8,
		str(aero.delta))
	var without_point_sampler: Dictionary = air.duplicate()
	without_point_sampler.erase("ambient_delta_body_at")
	var wash_at_datum: PackedFloat64Array = Slipstream.stage_loads(state, without_point_sampler, d, model,
		rpm, rho, 0.0, PackedFloat64Array(), 1, tq)
	_check("fixture excites matched free-versus-washed tail point deltas",
		_norm6(_subtract(wash, wash_at_datum)) > 1e-8,
		"matched %s; datum-only %s" % [wash, wash_at_datum])
	_check("wake source uses ambient hub delta without adding hub rotation",
		Slipstream.source_air(air).to_byte_array() == _add(air.v_air, air.wake_source_delta_body).to_byte_array())

	# Force only the later wash-point callback to fail. The earlier datum, wing, tail and hub samples all succeeded.
	var bad_field := SyntheticField.new()
	bad_field.origin_ned = state.slice(RB.POS, RB.POS + 3)
	var bad_stage: Dictionary = WindAircraftFlow.stage_air(state, model, bad_field, time_s, rho)
	_check("bad-wash fixture stage builds before poisoning the sampler", bool(bad_stage.get("ok", false)))
	if bad_stage.get("ok", false):
		bad_field.fail_next = true
		var bad_loads: PackedFloat64Array = Dynamics.loads_from_air(state, model, d, rpm, rho, bad_stage.air, 0.0)
		_check("a nonfinite wash-point ambient sample refuses the complete load vector",
			bad_field.fail_next == false and not _finite(bad_loads, 6), str(bad_loads))


func _check_stale_receipts(configs: Array) -> void:
	if configs.is_empty():
		_check("receipt model available", false)
		return
	var model: Dictionary = configs[0].model
	var state := _state(M.q_identity())
	var field := SyntheticField.new()
	field.uniform = true
	field.origin_ned = state.slice(RB.POS, RB.POS + 3)
	var rho := 1.03
	var stage: Dictionary = WindAircraftFlow.stage_air(state, model, field, 1.0, rho)
	_check("receipt fixture stage builds", bool(stage.get("ok", false)))
	if not stage.get("ok", false):
		return
	var air: Dictionary = stage.air
	var d := _neutral()
	var rpm := _test_rpm(model.propulsion)
	var stale_state := state.duplicate()
	stale_state[RB.VEL] += 0.01
	var stale_state_loads: PackedFloat64Array = Dynamics.loads_from_air(stale_state, model, d, rpm, rho, air)
	_check("stage air from another body state fails closed", not _finite(stale_state_loads, 6), str(stale_state_loads))
	var stale_density_loads: PackedFloat64Array = Dynamics.loads_from_air(state, model, d, rpm, rho * 0.99, air)
	_check("stage air from another density fails closed", not _finite(stale_density_loads, 6), str(stale_density_loads))
	var malformed: Dictionary = air.duplicate()
	malformed.aero_station_delta_body = PackedFloat64Array([0.0, 0.0, 0.0])
	var malformed_loads: PackedFloat64Array = Dynamics.loads_from_air(state, model, d, rpm, rho, malformed)
	_check("malformed full stage receipt fails closed", not _finite(malformed_loads, 6), str(malformed_loads))
	var incomplete_air: Dictionary = Air.compute(state, field.uniform_value, rho)
	incomplete_air.propulsion_air_body = PackedFloat64Array([18.0, 0.0, 0.0])
	var incomplete_loads: PackedFloat64Array = Dynamics.loads_from_air(state, model, d, rpm, rho, incomplete_air)
	_check("a lone propulsion point field cannot masquerade as a complete stage receipt",
		not _finite(incomplete_loads, 6), str(incomplete_loads))
	var rejected := WindAircraftFlow.stage_air(state, model, field, 1.0, NAN)
	_check("nonfinite stage density is rejected before use", not rejected.get("ok", false)
		and rejected.get("air", {}).is_empty(), str(rejected.get("errors", [])))


func _check_powered_sessions() -> void:
	var cases: Array[Dictionary] = [
		{"id": "turbo-lumber-evolution", "mode": "ideal", "kind": "electric_prop", "rollback": true},
		{"id": "stik-glow-61fx-2t", "mode": "ideal", "kind": "glow_prop", "rollback": false},
		{"id": "sebart-avanti-s-a200-p100rx", "mode": "ideal", "kind": "turbine", "rollback": false},
	]
	for entry: Dictionary in cases:
		var path: String = Catalog.data_for(entry.id, entry.mode)
		var session := StageFlight.new()
		session.input_enabled = false
		session.physics_enabled = false
		session.setup(path)
		root.add_child(session)
		var label: String = "session %s" % entry.id
		_check(label + " prepares", session.is_flyable())
		if not session.is_flyable():
			session.free()
			continue
		var installed_model: Dictionary = session.aircraft.get("model", {})
		var installed_prop: Dictionary = installed_model.get("propulsion", {})
		_check(label + " installs a normalized propulsion model", not installed_prop.is_empty(), str(installed_model.keys()))
		if installed_prop.is_empty():
			session.free()
			continue
		var field := SyntheticField.new()
		field.origin_ned = session.sim.state.slice(RB.POS, RB.POS + 3)
		session.stage_environment = field
		var state: PackedFloat64Array = session.sim.state.duplicate()
		state[RB.RATE] = 0.23
		state[RB.RATE + 1] = -0.17
		state[RB.RATE + 2] = 0.12
		var time_s: float = session.sim.time()
		var result: Dictionary = _session_evaluate(session, state, time_s)
		var loads: PackedFloat64Array = result.get("loads", PackedFloat64Array())
		_check(label + " actual model stage consumes the injected exact stage air",
			_finite(loads, 6) and session.stage_air_calls > 0
			and session.last_stage_air.get("spatial_state", PackedFloat64Array()).to_byte_array() == state.to_byte_array(),
			"calls %d; %s" % [session.stage_air_calls, loads])
		_check(label + " route matches its propulsion family", Propulsion.source_kind(installed_prop) == entry.kind,
			str(installed_prop.get("kind", "missing")))
		if session.last_stage_air.has("propulsion_air_body"):
			var point: Dictionary = Propulsion.stage_air_velocity(state, session.last_stage_air, installed_prop)
			_check(label + " session point inflow remains complete through its family consumer",
				bool(point.get("ok", false)) and _near_array(point.velocity_body,
					session.last_stage_air.propulsion_air_body, 1e-11))
		else:
			_check(label + " session retained stage propulsion sample", false)
		if entry.rollback:
			session.sim.paused = false
			var before: Dictionary = session.sim.checkpoint()
			var previous: PackedFloat64Array = session.sim.previous.duplicate()
			var last_loads: PackedFloat64Array = session.sim.last_loads.duplicate()
			var published_ticks := [0]
			session.sim.stepped.connect(func(_tick, _time, _state, _loads, _inputs, _aux): published_ticks[0] += 1)
			field.fail_after_time = time_s + session.sim.dt() * 0.25
			session.sim.step()
			_check(label + " invalid RK stage reports a fault and pauses", session.sim.paused
				and not session.sim.fault_reason.is_empty() and session.stage_failures > 0 and published_ticks[0] == 0)
			var restored := not before.is_empty()
			for key: String in ["state", "aux", "continuous", "modes", "inputs"]:
				restored = restored and var_to_bytes(session.sim.get(key)) == var_to_bytes(before.get(key, PackedFloat64Array()))
			restored = restored and session.sim.tick == int(before.get("tick", -1))
			restored = restored and session.sim.previous.to_byte_array() == previous.to_byte_array()
			restored = restored and session.sim.last_loads.to_byte_array() == last_loads.to_byte_array()
			restored = restored and session.sim.mass == float(before.get("mass", NAN))
			restored = restored and session.sim.gravity == float(before.get("gravity", NAN))
			restored = restored and session.sim.inertia.to_byte_array() == before.get("inertia", PackedFloat64Array()).to_byte_array()
			restored = restored and session.sim.stop_at_tick == int(before.get("stop_at_tick", -1))
			_check(label + " invalid RK stage rolls back body/aux/continuous/RNG/inputs/tick/mass/inertia",
				restored, "checkpoint keys %s; fault %s" % [before.keys(), session.sim.fault_reason])
		session.free()


func _session_evaluate(session: StageFlight, state: PackedFloat64Array, time_s: float) -> Dictionary:
	if session.sim.model.stage.is_valid():
		return session.sim.model.stage.call(state, session.sim.continuous, time_s)
	if not session.sim.continuous.is_empty():
		return {loads = session.sim.model.block_loads.call(state, session.sim.continuous, time_s),
			derivative = session.sim.model.block_derivative.call(state, session.sim.continuous, time_s)}
	return {loads = session.sim.model.loads.call(state, time_s)}


func _synthetic_wash_model() -> Dictionary:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft/jensen_ugly_stik_60.json"))
	var propeller: Dictionary = raw.propulsion.propeller
	propeller.thrust_angles = _quantity([0.0, 0.0], "deg")
	var pieces: Array = []
	for entry: Array in [["horizontal", 1.0], ["horizontal", -1.0], ["vertical", 1.0]]:
		var vertical: bool = entry[0] == "vertical"
		var tail: Dictionary = raw.aero.surfaces[entry[0]]
		pieces.append({surface = entry[0], area = _quantity(0.016, "m2"),
			root = _quantity([tail.position.value[0], 0.0, 0.0 if vertical else -0.04064], "m"),
			span_dir = _quantity([0.0, 0.0, 1.0] if vertical else [0.0, float(entry[1]), 0.0], "1"),
			span = _quantity(0.08, "m"), chords = _quantity([0.2, 0.2], "m")})
	propeller.slipstream = {hub = _quantity([-0.293276, 0.0, 0.0], "m"),
		wash_factor = _quantity([1.0, 1.0], "1"), swirl_factor = _quantity(0.0, "1"),
		vertical_drift = _quantity(0.0, "1"), pieces = pieces}
	var loaded: Dictionary = AD.validate_and_derive(raw)
	return loaded.model if loaded.get("ok", false) else {}


func _quantity(value: Variant, unit: String) -> Dictionary:
	return {value = value, unit = unit, kind = "estimated", source = "M5-W05c-R2 manufactured test fixture; no aircraft calibration"}


func _state(attitude: PackedFloat64Array, velocity := PackedFloat64Array([18.0, 0.2, -0.1]),
		rates := PackedFloat64Array([0.45, -0.25, 0.19])) -> PackedFloat64Array:
	return RB.make_state(M.v3(120.0, -17.0, -22.0), velocity, attitude, rates)


func _ambient_delta(field: SyntheticField, state: PackedFloat64Array, arm: PackedFloat64Array,
		time_s: float) -> PackedFloat64Array:
	var q: PackedFloat64Array = state.slice(RB.ATT, RB.ATT + 4)
	var datum: PackedFloat64Array = state.slice(RB.POS, RB.POS + 3)
	var point: PackedFloat64Array = M.add(datum, M.q_rotate(q, arm))
	var reference_wind: PackedFloat64Array = field.wind_world(datum, time_s)
	var point_wind: PackedFloat64Array = field.wind_world(point, time_s)
	return M.q_rotate(M.q_conj(q), M.sub(reference_wind, point_wind))


func _point_air(state: PackedFloat64Array, datum_air: PackedFloat64Array, arm: PackedFloat64Array,
		ambient_delta: PackedFloat64Array) -> PackedFloat64Array:
	var out: PackedFloat64Array = datum_air.duplicate()
	var rotation: PackedFloat64Array = M.cross(state.slice(RB.RATE, RB.RATE + 3), arm)
	for axis in 3:
		out[axis] += rotation[axis]
		out[axis] += ambient_delta[axis]
	return out


func _legacy_point_air(state: PackedFloat64Array, datum_air: PackedFloat64Array, prop: Dictionary) -> PackedFloat64Array:
	if Turbine.is_turbine(prop):
		return Turbine.local_intake_velocity(datum_air, state.slice(RB.RATE, RB.RATE + 3), prop)
	if Propulsion.is_glow(prop) or Propulsion.is_electric(prop):
		return Propulsion.hub_air_velocity(state, datum_air, prop.offset)
	return datum_air.duplicate()


func _manual_air_loads(state: PackedFloat64Array, model: Dictionary, d: Dictionary, rpm: float, rho: float,
		air: Dictionary) -> PackedFloat64Array:
	var aero_loads: PackedFloat64Array
	if air.has("spatial_air_law"):
		var spatial: Dictionary = Aero.ambient_spatial_loads(state, air, d, model, rho,
			air.aero_station_delta_body, NAN, NAN)
		if not spatial.get("ok", false):
			return PackedFloat64Array([NAN, NAN, NAN, NAN, NAN, NAN])
		aero_loads = spatial.loads
	else:
		aero_loads = Aero.loads(state, air, d, model, rho)
	var point: Dictionary = Propulsion.stage_air_velocity(state, air, model.propulsion)
	if not point.get("ok", false):
		return PackedFloat64Array([NAN, NAN, NAN, NAN, NAN, NAN])
	var prop_air: PackedFloat64Array = point.velocity_body
	var washed: bool = not model.propulsion.get("slipstream", {}).is_empty()
	var thrust_torque := PackedFloat64Array()
	var propulsion_loads: PackedFloat64Array
	if washed and (Propulsion.is_glow(model.propulsion) or air.has("propulsion_air_body")):
		thrust_torque = Propulsion.thrust_torque(prop_air, rpm, model.propulsion, rho).slice(0, 2)
		propulsion_loads = Propulsion.loads_from_thrust_torque(prop_air, rpm, model.propulsion, rho,
			thrust_torque[0], thrust_torque[1])
	else:
		propulsion_loads = Propulsion.loads(prop_air, rpm, model.propulsion, rho)
	var total := aero_loads.duplicate()
	for axis in 6:
		total[axis] += propulsion_loads[axis]
	if washed:
		var wash: PackedFloat64Array = Slipstream.stage_loads(state, air, d, model, rpm, rho, NAN,
			PackedFloat64Array(), 1, thrust_torque)
		for axis in 6:
			total[axis] += wash[axis]
	return total


func _neutral() -> Dictionary:
	return {"elevator": 0.0, "aileron_left": 0.0, "aileron_right": 0.0, "rudder": 0.0, "flap": 0.0}


func _test_rpm(prop: Dictionary) -> float:
	var maximum: float = float(prop.get("max_rpm", 10000.0))
	return maximum * 0.72


func _near_array(actual: PackedFloat64Array, expected: PackedFloat64Array, tolerance := 2e-11) -> bool:
	if actual.size() != expected.size():
		return false
	for i in actual.size():
		if not is_finite(actual[i]) or not is_finite(expected[i]) or absf(actual[i] - expected[i]) > tolerance:
			return false
	return true


func _finite(values: PackedFloat64Array, size: int) -> bool:
	if values.size() != size:
		return false
	for value: float in values:
		if not is_finite(value):
			return false
	return true


func _norm6(values: PackedFloat64Array) -> float:
	var total := 0.0
	for value: float in values:
		total += value * value
	return sqrt(total)


func _add(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	var result: PackedFloat64Array = a.duplicate()
	for i in result.size():
		result[i] += b[i]
	return result


func _subtract(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	var result: PackedFloat64Array = a.duplicate()
	for i in result.size():
		result[i] -= b[i]
	return result

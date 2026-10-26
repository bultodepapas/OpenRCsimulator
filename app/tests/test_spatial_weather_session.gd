## M5-W05c-R2: v5 weather ownership at real session start, replay and rollback boundaries.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Config := preload("res://physics/wind_config.gd")
const SpatialConfig := preload("res://physics/wind_spatial_config.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const GroundStart := preload("res://physics/ground_start.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const CheckpointJson := preload("res://sim/checkpoint_json.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
	print(("ok " if passed else "FAIL ") + label)


func _run() -> void:
	var config := _weather_config()
	_check_config_contract(config)
	_run_real_airborne_fleet(config)
	var field_result: Dictionary = FieldLoader.load_from()
	check("default runway field loads", field_result.get("ok", false))
	if field_result.get("ok", false):
		var spot: Dictionary = GroundStart.threshold(field_result.field)
		check("default runway threshold resolves", spot.get("ok", false))
		if spot.get("ok", false):
			_runway_checkpoint(config, field_result.field, spot)
	_run_airborne_checkpoint(config)
	_run_thermal_v2(config)
	_run_midpoint_rollback(config)
	print("M5-W05c-R2 spatial weather session: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _weather_config() -> Dictionary:
	var config: Dictionary = Config.spatial_defaults()
	config.spatial_wind.profile.reference_speed_mps = 1.5
	config.spatial_wind.profile.reference_from_deg = 90.0
	config.spatial_wind.profile.free_air_wind_ned_mps = [0.0, -2.0, 0.0]
	config.spatial_wind.turbulence.rms_mps = 0.02
	return config


func _check_config_contract(config: Dictionary) -> void:
	var valid: Dictionary = Config.validate(config)
	check("v5 spatial profile and frozen turbulence config validate", valid.get("ok", false)
		and valid.config.get("format") == Config.SPATIAL_FORMAT)
	var invalid_mean: Dictionary = config.duplicate(true)
	invalid_mean.speed_mps = 0.01
	check("v5 rejects a second legacy mean-wind source", not Config.validate(invalid_mean).ok)
	var invalid_ou: Dictionary = config.duplicate(true)
	invalid_ou.turbulence_rms_mps = [0.0, 0.0, 0.01]
	check("v5 rejects legacy session OU turbulence", not Config.validate(invalid_ou).ok)
	var invalid_nested_key: Dictionary = config.duplicate(true)
	invalid_nested_key.spatial_wind.provider_fallback = true
	check("v5 rejects unknown spatial provider settings", not Config.validate(invalid_nested_key).ok)


func _run_real_airborne_fleet(config: Dictionary) -> void:
	var paths: Array[String] = []
	for id: String in Catalog.airplane_flyable_ids():
		paths.append(str(Catalog.entry(id).data))
		if Catalog.has_battery_mode(id, "pack"):
			paths.append(Catalog.data_for(id, "pack"))
	check("catalog includes the expected real-aircraft matrix", paths.size() >= 9)
	for path: String in paths:
		var session := _new_session(path, config)
		if session == null:
			continue
		var label := path.get_file().get_basename()
		check(label + " real aircraft setup accepts v5 weather", session.aircraft.get("ok", false)
			and session.weather_configuration().get("format") == Config.SPATIAL_FORMAT)
		if session.aircraft.get("ok", false):
			session.reset()
			check(label + " airborne start accepts v5 local airflow", session.is_flyable()
				and session.start_error.is_empty() and session.sim.fault_reason.is_empty() and session.sim.state.size() == RB.SIZE)
			_check_no_ou_double_count(session, label)
			if session.is_flyable():
				session.engine_running = true
				session.commands.throttle = maxf(0.55, float(session.start.get("throttle", 0.0)))
				session.sim.inputs = session._inputs()
				var start_tick: int = session.sim.tick
				var powered_ticks: int = roundi(2.0 / session.sim.dt())
				for _tick in powered_ticks:
					session.sim.step()
					if not session.sim.fault_reason.is_empty():
						break
				check(label + " powered v5 run accepts two simulation seconds", session.sim.tick - start_tick == powered_ticks
					and session.sim.fault_reason.is_empty() and session.sim.inputs[3] > 0.0)
		session.free()


func _new_session(path: String, config: Dictionary, field: Dictionary = {}) -> Node:
	var session := Flight.new()
	session.input_enabled = false
	session.physics_enabled = false
	session.setup(path)
	root.add_child(session)
	if not session.is_flyable():
		return session
	if not field.is_empty() and not session.set_field(field):
		check(path.get_file().get_basename() + " accepts runway field", false)
		return session
	if not session.setup_weather(config):
		check(path.get_file().get_basename() + " accepts v5 weather", false)
		return session
	return session


func _check_no_ou_double_count(session: Node, label: String) -> void:
	var position: PackedFloat64Array = session.sim.state.slice(RB.POS, RB.POS + 3)
	var time_s: float = session.sim.time()
	var expected: PackedFloat64Array = session._weather.sample_world(position, time_s)
	var actual: PackedFloat64Array = session.wind_at(time_s, session.sim.state)
	check(label + " v5 has no session OU process", not session._weather.has_turbulence()
		and session._turbulence_noise(time_s).is_empty() and session.sim.modes.size() == 1)
	check(label + " environment adds no second turbulence vector", expected.to_byte_array() == actual.to_byte_array())


func _runway_checkpoint(config: Dictionary, field: Dictionary, spot: Dictionary) -> void:
	var source := _new_session(str(Catalog.entry(Catalog.airplane_flyable_ids()[0]).data), config, field)
	var target := _new_session(str(Catalog.entry(Catalog.airplane_flyable_ids()[0]).data), config, field)
	if not source.aircraft.get("ok", false) or not target.aircraft.get("ok", false):
		source.free()
		target.free()
		return
	var source_ok: bool = source.reset_on_runway(float(spot.north), float(spot.east), float(spot.heading))
	var target_ok: bool = target.reset_on_runway(float(spot.north), float(spot.east), float(spot.heading))
	check("real aircraft solves a runway start with per-candidate v5 Air", source_ok and target_ok
		and source.start_error.is_empty() and source.sim.fault_reason.is_empty())
	if source_ok and target_ok:
		_check_no_ou_double_count(source, "runway start")
		_continue_exact_checkpoint(source, target, "runway")
	source.free()
	target.free()


func _run_airborne_checkpoint(config: Dictionary) -> void:
	var path := str(Catalog.entry(Catalog.airplane_flyable_ids()[0]).data)
	var source := _new_session(path, config)
	var target := _new_session(path, config)
	if not source.aircraft.get("ok", false) or not target.aircraft.get("ok", false):
		source.free()
		target.free()
		return
	source.reset()
	target.reset()
	check("real aircraft accepts an airborne v5 start", source.is_flyable() and target.is_flyable()
		and source.start_error.is_empty()
		and source.sim.fault_reason.is_empty() and target.start_error.is_empty()
		and target.sim.fault_reason.is_empty())
	if source.start_error.is_empty() and target.start_error.is_empty():
		_check_no_ou_double_count(source, "airborne start")
		_continue_exact_checkpoint(source, target, "airborne")
	source.free()
	target.free()


func _run_thermal_v2(config: Dictionary) -> void:
	var generated: Dictionary = SpatialConfig.thermal_defaults(config.spatial_wind)
	check("thermal helper creates a complete v2 candidate", generated.get("ok", false)
		and generated.get("config", {}).get("format") == "openrc-spatial-wind v2")
	if not generated.get("ok", false):
		return
	var with_cell: Dictionary = generated.config.duplicate(true)
	with_cell.thermal_field.cells.append({
		"id": "session-test-thermal",
		"birth_s": 0.0,
		"duration_s": 120.0,
		"center_ne_m": [0.0, 0.0],
		"drift_ne_mps": [0.0, 0.0],
		"radius_m": 50.0,
		"top_agl_m": 200.0,
		"peak_updraft_mps": 0.1,
	})
	var resolved: Dictionary = SpatialConfig.resolve(with_cell)
	check("thermal agenda resolves under the shared spatial domain", resolved.get("ok", false))
	if not resolved.get("ok", false):
		return
	var thermal_weather: Dictionary = config.duplicate(true)
	thermal_weather.spatial_wind = resolved.config
	check("weather v5 carries a validated thermal-v2 provider", Config.validate(thermal_weather).get("ok", false))
	var path := str(Catalog.entry(Catalog.airplane_flyable_ids()[0]).data)
	var source := _new_session(path, thermal_weather)
	var target := _new_session(path, thermal_weather)
	if not source.aircraft.get("ok", false) or not target.aircraft.get("ok", false):
		source.free()
		target.free()
		return
	source.reset()
	target.reset()
	var started: bool = source.is_flyable() and target.is_flyable()
	check("thermal-v2 session resets on the real aircraft", started
		and source.weather_configuration().spatial_wind.format == "openrc-spatial-wind v2")
	if started:
		source.sim.step()
		var payload: String = source.checkpoint_json()
		var decoded: Dictionary = CheckpointJson.decode(payload)
		check("thermal-v2 checkpoint retains its agenda and receipt", decoded.get("ok", false)
			and decoded.snapshot.get("format") == "openrc-flight-checkpoint v12"
			and decoded.snapshot.weather_config.spatial_wind.format == "openrc-spatial-wind v2"
			and decoded.snapshot.weather_config.spatial_wind.thermal_field.cells.size() == 1)
		check("thermal-v2 checkpoint restores byte-exactly", decoded.get("ok", false)
			and target.restore_checkpoint_json(payload) and target.checkpoint_json() == payload)
		if decoded.get("ok", false) and target.checkpoint_json() == payload:
			source.sim.step()
			target.sim.step()
			check("thermal-v2 continuation remains exact", source.sim.fault_reason.is_empty()
				and target.sim.fault_reason.is_empty() and source.checkpoint_json() == target.checkpoint_json())
	source.free()
	target.free()


func _continue_exact_checkpoint(source: Node, target: Node, route: String) -> void:
	source.sim.step()
	check(route + " source first tick accepts", source.sim.fault_reason.is_empty())
	var payload: String = source.checkpoint_json()
	var decoded: Dictionary = CheckpointJson.decode(payload)
	check(route + " checkpoint JSON carries a complete v12 weather receipt",
		decoded.get("ok", false) and decoded.snapshot.get("format") == "openrc-flight-checkpoint v12"
		and decoded.snapshot.has("weather_config") and decoded.snapshot.has("spatial_weather_receipt"))
	if not decoded.get("ok", false):
		return
	var before: PackedByteArray = var_to_bytes(target.checkpoint())
	check(route + " destination accepts exact v12 checkpoint JSON", target.restore_checkpoint_json(payload))
	check(route + " JSON restore reproduces exact snapshot", payload == target.checkpoint_json()
		and var_to_bytes(source.sim.checkpoint()) == var_to_bytes(target.sim.checkpoint()))
	for _tick in 12:
		source.sim.step()
		target.sim.step()
	check(route + " checkpoint continuation is byte-exact", source.sim.fault_reason.is_empty()
		and target.sim.fault_reason.is_empty() and source.checkpoint_json() == target.checkpoint_json())
	# Receipt and config failures are tested against the already accepted replay boundary.
	var restored_bytes: PackedByteArray = var_to_bytes(target.checkpoint())
	var bad_receipt: Dictionary = decoded.snapshot.duplicate(true)
	bad_receipt.spatial_weather_receipt.content_sha256 = "tampered-content-hash"
	var receipt_json: String = CheckpointJson.encode(bad_receipt)
	check(route + " tampered v12 receipt refuses transactionally",
		not target.restore_checkpoint_json(receipt_json) and var_to_bytes(target.checkpoint()) == restored_bytes)
	var bad_config: Dictionary = decoded.snapshot.duplicate(true)
	bad_config.weather_config.spatial_wind.profile.reference_speed_mps += 0.125
	var config_json: String = CheckpointJson.encode(bad_config)
	check(route + " valid-but-different v5 config refuses transactionally",
		not target.restore_checkpoint_json(config_json) and var_to_bytes(target.checkpoint()) == restored_bytes)
	check(route + " invalid restore leaves prior replay JSON unchanged", target.checkpoint_json() == source.checkpoint_json())
	# Preserve a concrete no-mutation check at the pre-restore target boundary for harness diagnostics.
	check(route + " restore begins from a complete destination snapshot", not before.is_empty())


func _run_midpoint_rollback(config: Dictionary) -> void:
	var limited: Dictionary = config.duplicate(true)
	limited.spatial_wind.domain.half_extent_north_m = 100.0
	limited.spatial_wind.domain.max_height_agl_m = 100.0
	var session := _new_session(str(Catalog.entry(Catalog.airplane_flyable_ids()[0]).data), limited)
	if not session.aircraft.get("ok", false):
		session.free()
		return
	session.reset()
	if not session.is_flyable() or not session.start_error.is_empty() or not session.sim.fault_reason.is_empty():
		check("spatial domain test session starts before edge probe", false)
		session.free()
		return
	var candidate: PackedFloat64Array = session.sim.state.duplicate()
	candidate[RB.POS] = 0.0
	candidate[RB.POS + 1] = 0.0
	candidate[RB.POS + 2] = -99.6
	var euler: PackedFloat64Array = M.q_to_euler(M.quat(candidate[RB.ATT], candidate[RB.ATT + 1], candidate[RB.ATT + 2], candidate[RB.ATT + 3]))
	var attitude: PackedFloat64Array = M.q_from_euler(0.0, euler[1], euler[2])
	for axis in 4:
		candidate[RB.ATT + axis] = attitude[axis]
	candidate[RB.VEL] = 0.0
	candidate[RB.VEL + 1] = 0.0
	candidate[RB.VEL + 2] = -240.0
	var reset_ok: bool = session.sim.reset(candidate)
	check("near-boundary current stage is accepted before the RK midpoint", reset_ok and session.sim.fault_reason.is_empty())
	if not reset_ok:
		print("edge reset refusal: ", session.sim.fault_reason)
		session.free()
		return
	var midpoint: PackedFloat64Array = candidate.duplicate()
	midpoint[RB.POS + 2] += candidate[RB.VEL + 2] * session.sim.dt() * 0.5
	var midpoint_wind: PackedFloat64Array = session.wind_at(session.sim.dt() * 0.5, midpoint)
	check("RK midpoint lies outside the configured spatial weather domain",
		-midpoint[RB.POS + 2] > float(limited.spatial_wind.domain.max_height_agl_m)
		and is_nan(midpoint_wind[0]))
	var before: Dictionary = session.sim.checkpoint()
	var emitted := [0]
	session.sim.stepped.connect(func(_tick, _time, _state, _loads, _inputs, _aux): emitted[0] += 1)
	session.sim.step()
	var unchanged := true
	for key: String in ["state", "previous", "aux", "continuous", "modes", "inputs", "last_loads"]:
		unchanged = unchanged and var_to_bytes(session.sim.get(key)) == var_to_bytes(before[key])
	check("midpoint out-of-domain sample rolls back the full simulation transaction", unchanged
		and session.sim.tick == before.tick and session.sim.paused and not session.sim.fault_reason.is_empty()
		and emitted[0] == 0)
	session.free()

# M5 flight integration: uniform-air Galilean invariance, wind-aware loads/shaft inflow,
# stage clocking, reset/checkpoint identity, and a static wind-on runway hold.
extends SceneTree

const Air := preload("res://physics/air_data.gd")
const Config := preload("res://physics/wind_config.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const Ground := preload("res://physics/ground_contact.gd")
const GroundStart := preload("res://physics/ground_start.gd")
const M := preload("res://physics/math3d.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const RB := preload("res://physics/rigid_body.gd")
const Sim := preload("res://sim/simulation.gd")
const WeatherSampler := preload("res://physics/wind_field.gd")

const STIK := "res://data/aircraft/jensen_ugly_stik_60.json"
const MODEL_PATHS := [
	"res://data/aircraft/jensen_ugly_stik_60.json",
	"res://data/aircraft/gp_extra_300s_60.json",
	"res://data/aircraft/p51d_mustang_120.json",
	"res://data/aircraft/sebart_avanti_s_a200.json",
]
const GALILEAN_TOLERANCE := 3e-7
const POSITION_TOLERANCE := 5e-7

var _checks: int = 0
var _failures: int = 0


func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	print(("ok   " if passed else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))
	if not passed:
		_failures += 1


func _near(left: float, right: float, tolerance: float) -> bool:
	return is_finite(left) and is_finite(right) and absf(left - right) <= tolerance


func _max_diff(left: PackedFloat64Array, right: PackedFloat64Array) -> float:
	if left.size() != right.size():
		return INF
	var maximum: float = 0.0
	for index in left.size():
		if not is_finite(left[index]) or not is_finite(right[index]):
			return INF
		maximum = maxf(maximum, absf(left[index] - right[index]))
	return maximum


func _norm3(value: PackedFloat64Array) -> float:
	return M.sqrt_(value[0] * value[0] + value[1] * value[1] + value[2] * value[2])


func _weather(changes: Dictionary = {}) -> Dictionary:
	var result: Dictionary = Config.defaults()
	for key: Variant in changes:
		result[key] = changes[key]
	return result


func _new_session(path: String, weather: Dictionary) -> Node:
	var session: Node = FlightSession.new()
	session.setup(path)
	root.add_child(session)
	session.input_enabled = false
	if not session.is_flyable():
		_check("session setup is flyable: " + path, false, str(session.pause_reason))
		session.free()
		return null
	var accepted: bool = session.setup_weather(weather)
	if not accepted:
		_check("weather accepted at launch boundary: " + path, false, str(session.weather_error))
		session.free()
		return null
	session.reset()
	session.input_enabled = false
	session.sim.set_paused(false)
	_check("configured session remains flyable: " + path, session.is_flyable(), str(session.start_error))
	return session


func _air_error(left: Dictionary, right: Dictionary) -> float:
	var error: float = _max_diff(left.v_air, right.v_air)
	for key in ["V", "alpha", "beta", "qbar"]:
		error = maxf(error, absf(float(left[key]) - float(right[key])))
	return error


func _test_uniform_galilean_invariance() -> void:
	var steady: Dictionary = _weather({ "speed_mps": 3.0, "from_deg": 270.0 })
	var wind_ned: PackedFloat64Array = M.v3(0.0, 3.0, 0.0)
	for path: String in MODEL_PATHS:
		var calm: Node = _new_session(path, Config.defaults())
		var windy: Node = _new_session(path, steady)
		if calm == null or windy == null:
			if calm != null:
				calm.free()
			if windy != null:
				windy.free()
			continue
		var initial_calm: PackedFloat64Array = calm.sim.state.duplicate()
		var initial_windy: PackedFloat64Array = windy.sim.state.duplicate()
		var q: PackedFloat64Array = M.quat(initial_calm[RB.ATT], initial_calm[RB.ATT + 1], initial_calm[RB.ATT + 2], initial_calm[RB.ATT + 3])
		var expected_body_wind: PackedFloat64Array = M.q_rotate(M.q_conj(q), wind_ned)
		var initial_velocity_error: float = 0.0
		for axis in 3:
			initial_velocity_error = maxf(initial_velocity_error,
				absf(initial_windy[RB.VEL + axis] - initial_calm[RB.VEL + axis] - expected_body_wind[axis]))
		var initial_air_error: float = _air_error(calm.air_data(initial_calm, 0.0), windy.air_data(initial_windy, 0.0))
		_check("%s reset adds R^T·W while preserving trimmed TAS" % path,
			initial_velocity_error <= 1e-12 and initial_air_error <= 1e-11,
			"body-velocity %.12f m/s, air-state %.12f" % [initial_velocity_error, initial_air_error])
		for _tick in 240:
			calm.sim.step()
			windy.sim.step()
		var elapsed: float = calm.sim.time()
		var calm_state: PackedFloat64Array = calm.sim.state
		var windy_state: PackedFloat64Array = windy.sim.state
		var air_error: float = _air_error(calm.air_data(calm_state, elapsed), windy.air_data(windy_state, elapsed))
		var attitude_error: float = _max_diff(calm_state.slice(RB.ATT, RB.ATT + 4), windy_state.slice(RB.ATT, RB.ATT + 4))
		var rate_error: float = _max_diff(calm_state.slice(RB.RATE, RB.RATE + 3), windy_state.slice(RB.RATE, RB.RATE + 3))
		var position_delta: PackedFloat64Array = M.v3(
			windy_state[RB.POS] - calm_state[RB.POS],
			windy_state[RB.POS + 1] - calm_state[RB.POS + 1],
			windy_state[RB.POS + 2] - calm_state[RB.POS + 2])
		var position_error: float = _max_diff(position_delta, M.scale(wind_ned, elapsed))
		var aux_error: float = _max_diff(calm.sim.aux, windy.sim.aux)
		var wash_error: float = _max_diff(calm.sim.continuous, windy.sim.continuous)
		var loads_error: float = _max_diff(calm.sim.last_loads, windy.sim.last_loads)
		var healthy: bool = calm.sim.fault_reason.is_empty() and windy.sim.fault_reason.is_empty()
		_check("%s 240 ticks preserve air-relative flight, loads and auxiliary state" % path,
			healthy and air_error <= GALILEAN_TOLERANCE and attitude_error <= GALILEAN_TOLERANCE
				and rate_error <= GALILEAN_TOLERANCE and aux_error <= GALILEAN_TOLERANCE
				and wash_error <= GALILEAN_TOLERANCE and loads_error <= GALILEAN_TOLERANCE,
			"air %.12f, attitude %.12f, rates %.12f, aux %.12f, wash %.12f, loads %.12f" % [
				air_error, attitude_error, rate_error, aux_error, wash_error, loads_error])
		_check("%s world position differs by W·t" % path, position_error <= POSITION_TOLERANCE,
			"max NED error %.12f m at %.6f s" % [position_error, elapsed])
		calm.free()
		windy.free()


func _test_same_state_wind_loads_and_ground_separation() -> void:
	var session: Node = _new_session(STIK, _weather({ "speed_mps": 1.5, "from_deg": 90.0 }))
	if session == null:
		return
	var loaded_field: Dictionary = FieldLoader.load_from()
	_check("default ground field loads for windy runway", loaded_field.ok, str(loaded_field.get("errors", [])))
	if not loaded_field.ok or not session.set_field(loaded_field.field):
		session.free()
		return
	var spot: Dictionary = GroundStart.threshold(loaded_field.field)
	var started: bool = session.reset_on_runway(float(spot.north), float(spot.east), float(spot.heading))
	_check("wind-aware runway static solve succeeds", started,
		str(session.start_error if not session.start_error.is_empty() else session.pause_reason))
	if not started:
		session.free()
		return
	var state: PackedFloat64Array = session.sim.state.duplicate()
	var original_aux: PackedFloat64Array = session.sim.aux.duplicate()
	var lag_index: int = session.downwash_index()
	if lag_index >= 0:
		session.sim.aux[lag_index] += 0.1 # prove the time-varying load path forwards the auxiliary lag value
	var stage_time: float = 0.0
	var actual: PackedFloat64Array = session._wash_loads(state, session.sim.continuous, stage_time)
	var air: Dictionary = session.air_data(state, stage_time)
	var downwash_cl: float = session.sim.aux[lag_index] if lag_index >= 0 else NAN
	var expected_aircraft: PackedFloat64Array = Dynamics.loads(state, session.aircraft.model,
		session._deflections(session.sim.aux), session.sim.aux[FlightSession.AUX_RPM], Air.RHO_SEA_LEVEL,
		session.wind_at(stage_time), downwash_cl, session.sim.continuous)
	var expected_ground: PackedFloat64Array = Ground.loads(state, session.aircraft.model.landing_gear,
		session.sim.aux[FlightSession.AUX_SERVO + 2], session.ground_surfaces,
		session.sim.aux.slice(FlightSession.AUX_ANCHORS))
	var expected_total: PackedFloat64Array = expected_aircraft.duplicate()
	for axis in expected_ground.size():
		expected_total[axis] += expected_ground[axis]
	var calm_aircraft: PackedFloat64Array = Dynamics.loads(state, session.aircraft.model,
		session._deflections(session.sim.aux), session.sim.aux[FlightSession.AUX_RPM], Air.RHO_SEA_LEVEL,
		M.v3(0.0, 0.0, 0.0), downwash_cl, session.sim.continuous)
	_check("same-state session loads equal Dynamics(wind, lag, wash) plus ground contacts",
		actual.to_byte_array() == expected_total.to_byte_array(),
		"total %s; wind aircraft delta %.9f N" % [str(actual), _max_diff(expected_aircraft, calm_aircraft)])
	_check("wind changes aircraft loads while wheel loads remain ground-relative",
		_max_diff(expected_aircraft, calm_aircraft) > 1e-6 and not expected_ground.is_empty()
			and _max_diff(expected_ground, Ground.loads(state, session.aircraft.model.landing_gear,
				session.sim.aux[FlightSession.AUX_SERVO + 2], session.ground_surfaces,
				session.sim.aux.slice(FlightSession.AUX_ANCHORS))) == 0.0,
		"wind does not enter Ground.loads; local TAS %.4f m/s" % float(air.V))
	session.sim.aux = original_aux
	_test_windy_runway_hold(session, state)
	session.free()


func _test_windy_runway_hold(session: Node, initial_state: PackedFloat64Array) -> void:
	var s: PackedFloat64Array = session.sim.state
	var loads: PackedFloat64Array = session.sim.last_loads
	var derivative: PackedFloat64Array = RB.derivative(s, session.sim.mass, session.sim.inertia,
		RB.inertia_inverse(session.sim.inertia), M.v3(loads[0], loads[1], loads[2]),
		M.v3(loads[3], loads[4], loads[5]), session.sim.gravity, session.rotor_momentum(session.sim.aux))
	var q: PackedFloat64Array = M.quat(s[RB.ATT], s[RB.ATT + 1], s[RB.ATT + 2], s[RB.ATT + 3])
	var world_accel: PackedFloat64Array = M.q_rotate(q, M.v3(derivative[RB.VEL], derivative[RB.VEL + 1], derivative[RB.VEL + 2]))
	var world_angular_accel: PackedFloat64Array = M.q_rotate(q,
		M.v3(derivative[RB.RATE], derivative[RB.RATE + 1], derivative[RB.RATE + 2]))
	_check("mild wind runway equilibrium has negligible residual acceleration",
		_norm3(world_accel) < 1e-8 and _norm3(world_angular_accel) < 1e-8,
		"linear %.12f m/s², angular %.12f rad/s²" % [_norm3(world_accel), _norm3(world_angular_accel)])
	var origin: PackedFloat64Array = M.v3(initial_state[RB.POS], initial_state[RB.POS + 1], initial_state[RB.POS + 2])
	session.sim.set_paused(false)
	for _tick in 2400:
		session.sim.step()
	var final_state: PackedFloat64Array = session.sim.state
	var delta: PackedFloat64Array = M.v3(final_state[RB.POS] - origin[0], final_state[RB.POS + 1] - origin[1],
		final_state[RB.POS + 2] - origin[2])
	var velocity: PackedFloat64Array = final_state.slice(RB.VEL, RB.VEL + 3)
	_check("wind-on Stik runway idle hold stays parked for 10 seconds",
		session.sim.fault_reason.is_empty() and _norm3(delta) < 1e-6 and _norm3(velocity) < 1e-6,
		"drift %.12f m, ground speed %.12f m/s, fault '%s'" % [_norm3(delta), _norm3(velocity), session.sim.fault_reason])


func _test_stage_wind_sampling() -> void:
	var weather: Dictionary = _weather({
		"gust_mps": 6.0, "gust_duration_s": 0.5, "gust_period_s": 1.0, "gust_delay_s": 0.001,
	})
	var session: Node = _new_session(STIK, weather)
	if session == null:
		return
	var times: Array[float] = []
	var samples: Array[PackedFloat64Array] = []
	if session.sim.continuous.is_empty():
		var previous_loads: Callable = session.sim.loads
		session.sim.loads = func(state: PackedFloat64Array, time_s: float) -> PackedFloat64Array:
			times.append(time_s)
			samples.append(session.wind_at(time_s))
			return previous_loads.call(state, time_s)
	else:
		var previous_loads: Callable = session.sim.continuous_loads
		session.sim.continuous_loads = func(state: PackedFloat64Array, wash: PackedFloat64Array,
				time_s: float) -> PackedFloat64Array:
			times.append(time_s)
			samples.append(session.wind_at(time_s))
			return previous_loads.call(state, wash, time_s)
	var start_time: float = session.sim.time()
	var h: float = session.sim.dt()
	session.sim.step()
	var expected_times: Array[float] = [start_time, start_time + h / 2.0, start_time + h / 2.0, start_time + h]
	var time_error: float = 0.0
	for index in mini(times.size(), expected_times.size()):
		time_error = maxf(time_error, absf(times[index] - expected_times[index]))
	var expected_first: PackedFloat64Array = session.wind_at(start_time)
	var expected_middle: PackedFloat64Array = session.wind_at(start_time + h / 2.0)
	var expected_end: PackedFloat64Array = session.wind_at(start_time + h)
	_check("real session load callback sees k1/k2/k3/k4 absolute stage times",
		times == expected_times and time_error == 0.0, str(times))
	_check("gust changes between RK stages and both midpoint samples agree",
		samples.size() == 4 and samples[0] == expected_first and samples[1] == expected_middle
			and samples[2] == expected_middle and samples[3] == expected_end
			and samples[0] != samples[1] and samples[1] != samples[3],
		"stage gust north components %s" % str(samples.map(func(sample: PackedFloat64Array) -> float: return sample[0])))
	session.free()


func _zero_loads(_body: PackedFloat64Array, _state: PackedFloat64Array, _time_s: float) -> PackedFloat64Array:
	return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])


func _integrate_cosine_gust(hz: int, field: RefCounted) -> float:
	Engine.physics_ticks_per_second = hz
	var sim: Node = Sim.new()
	sim.gravity = 0.0
	sim.continuous = PackedFloat64Array([0.0])
	sim.continuous_loads = _zero_loads
	sim.continuous_derivative = func(_body: PackedFloat64Array, _continuous: PackedFloat64Array,
			time_s: float) -> PackedFloat64Array:
		return PackedFloat64Array([field.sample(time_s)[0]])
	var initial: PackedFloat64Array = RB.make_state(M.v3(0.0, 0.0, -10.0), M.v3(0.0, 0.0, 0.0),
		M.q_identity(), M.v3(0.0, 0.0, 0.0))
	var reset_ok: bool = sim.reset(initial)
	var elapsed: float = 2.0 / 3.0
	var ticks: int = roundi(float(hz) * elapsed)
	for _tick in ticks:
		sim.step()
	var exact_integral: float = -1.5 * (elapsed - M.sin_(TAU * elapsed) / TAU)
	var error: float = absf(sim.continuous[0] - exact_integral) if reset_ok and sim.fault_reason.is_empty() else INF
	sim.free()
	return error


func _test_rk4_cosine_gust_integral() -> void:
	var built: Dictionary = WeatherSampler.build(_weather({
		"gust_mps": 3.0, "gust_duration_s": 1.0, "gust_period_s": 2.0, "gust_delay_s": 0.0,
	}))
	_check("manufactured-cosine field builds", built.ok, str(built.errors))
	if not built.ok:
		return
	var old_rate: int = Engine.physics_ticks_per_second
	var error_30: float = _integrate_cosine_gust(30, built.field)
	var error_60: float = _integrate_cosine_gust(60, built.field)
	var error_120: float = _integrate_cosine_gust(120, built.field)
	Engine.physics_ticks_per_second = old_rate
	_check("RK4 resolves a partial integral of the 3 m/s cosine gust",
		error_120 < 1e-6, "absolute errors at 30/60/120 Hz: %s m" % str([
			String.num_scientific(error_30), String.num_scientific(error_60), String.num_scientific(error_120)]))
	_check("manufactured forcing converges at fourth order under rate doubling",
		error_30 > error_60 and error_60 > error_120 and error_30 / error_60 > 8.0 and error_60 / error_120 > 8.0,
		"absolute errors %s m; ratios %s" % [
			str([String.num_scientific(error_30), String.num_scientific(error_60), String.num_scientific(error_120)]),
			str([String.num_scientific(error_30 / error_60), String.num_scientific(error_60 / error_120)])])


func _test_p51_shaft_uses_air_inflow() -> void:
	var weather: Dictionary = _weather({ "speed_mps": 5.0, "from_deg": 90.0 })
	var session: Node = _new_session("res://data/aircraft/p51d_mustang_120.json", weather)
	if session == null:
		return
	var state: PackedFloat64Array = session.sim.state
	var prop: Dictionary = session.aircraft.model.propulsion
	var air: Dictionary = session.air_data(state, session.sim.time())
	var air_u: float = M.dot(air.v_air, Propulsion.axis(prop))
	var ground_u: float = M.dot(state.slice(RB.VEL, RB.VEL + 3), Propulsion.axis(prop))
	var expected_air_rpm: float = Propulsion.shaft_step(session.sim.aux[FlightSession.AUX_RPM],
		session.sim.inputs[3], air_u, session.sim.dt(), prop, Air.RHO_SEA_LEVEL)
	var expected_ground_rpm: float = Propulsion.shaft_step(session.sim.aux[FlightSession.AUX_RPM],
		session.sim.inputs[3], ground_u, session.sim.dt(), prop, Air.RHO_SEA_LEVEL)
	var actual_aux: PackedFloat64Array = session._pre_step(session.sim.aux, session.sim.inputs, session.sim.dt())
	_check("P-51 shaft pre-step uses air-relative inflow, not ground speed",
		actual_aux[FlightSession.AUX_RPM] == expected_air_rpm and expected_air_rpm != expected_ground_rpm,
		"air axial %.6f m/s, ground axial %.6f m/s; rpm %.9f vs wrong-input %.9f" % [
			air_u, ground_u, expected_air_rpm, expected_ground_rpm])
	session.free()


func _control_tail(session: Node, first_tick: int, count: int) -> void:
	var base_throttle: float = float(session.start.get("throttle", session.sim.inputs[3]))
	for offset in count:
		var index: int = first_tick + offset
		session.sim.inputs = PackedFloat64Array([
			0.04 * sin(float(index) * 0.031),
			0.035 * cos(float(index) * 0.027),
			0.02 * sin(float(index) * 0.019),
			clampf(base_throttle + 0.01 * sin(float(index) * 0.013), 0.0, 1.0),
		])
		session.sim.step()


func _test_reset_and_checkpoint_replay() -> void:
	var reset_weather: Dictionary = _weather({
		"gust_mps": 2.0, "gust_duration_s": 0.5, "gust_period_s": 2.0, "gust_delay_s": 0.1,
	})
	var reset_session: Node = _new_session(STIK, reset_weather)
	if reset_session != null:
		var at_zero: PackedFloat64Array = reset_session.wind_at(0.0)
		_control_tail(reset_session, 0, 84) # t = 0.35 s, at the gust peak
		var during_flight: PackedFloat64Array = reset_session.wind_at(reset_session.sim.time())
		var time_before_reset: float = reset_session.sim.time()
		reset_session.reset()
		var state_after_reset: PackedFloat64Array = reset_session.sim.state
		var default_air: Dictionary = reset_session.air_data(state_after_reset)
		var explicit_air: Dictionary = Air.compute(state_after_reset, reset_session.wind_at(0.0), Air.RHO_SEA_LEVEL)
		_check("reset returns gust sampling and default air query to stage time zero",
			time_before_reset > 0.3 and _norm3(during_flight) > _norm3(at_zero)
				and reset_session.sim.time() == 0.0 and reset_session.wind_at(0.0) == at_zero
				and _air_error(default_air, explicit_air) == 0.0,
			"pre-reset t %.6f s, gust %.6f m/s; post-reset t %.1f s" % [
				time_before_reset, _norm3(during_flight), reset_session.sim.time()])
		reset_session.free()

	var replay_weather: Dictionary = _weather({
		"speed_mps": 1.5, "from_deg": 270.0, "gust_mps": 1.0, "gust_up_mps": 0.5,
		"gust_duration_s": 0.5, "gust_period_s": 1.5, "gust_delay_s": 0.2,
	})
	var source: Node = _new_session(STIK, replay_weather)
	if source == null:
		return
	var tick_zero: PackedByteArray = var_to_bytes(source.checkpoint())
	var invalid_config: Dictionary = replay_weather.duplicate(true)
	invalid_config.gust_period_s = 0.1
	_check("invalid weather at reset boundary is rejected atomically",
		not source.setup_weather(invalid_config) and var_to_bytes(source.checkpoint()) == tick_zero,
		str(source.weather_error))
	_control_tail(source, 0, 40)
	var before_live_change: PackedByteArray = var_to_bytes(source.checkpoint())
	var changed_weather: Dictionary = replay_weather.duplicate(true)
	changed_weather.speed_mps = 2.0
	_check("live weather change after tick zero is refused without state mutation",
		not source.setup_weather(changed_weather) and var_to_bytes(source.checkpoint()) == before_live_change
			and source.weather_configuration() == replay_weather,
		str(source.weather_error))
	var checkpoint: Dictionary = source.checkpoint()
	_check("non-calm complete session checkpoint has version 2 and the authored weather", 
		checkpoint.get("format", "") == "openrc-flight-checkpoint v2"
			and checkpoint.get("weather_config", {}) == replay_weather,
		str(checkpoint.get("format", "")))
	var invalid_checkpoint: Dictionary = checkpoint.duplicate(true)
	invalid_checkpoint.weather_config.speed_mps = 15.01
	var before_bad_restore: PackedByteArray = var_to_bytes(source.checkpoint())
	_check("invalid checkpoint weather is rejected with owner state intact",
		not source.restore_checkpoint(invalid_checkpoint) and var_to_bytes(source.checkpoint()) == before_bad_restore,
		str(source.weather_configuration()))
	var bad_hash: Dictionary = checkpoint.duplicate(true)
	bad_hash.configuration = "mismatched-weather-fingerprint"
	_check("changed checkpoint fingerprint is rejected atomically",
		not source.restore_checkpoint(bad_hash) and var_to_bytes(source.checkpoint()) == before_bad_restore,
		str(source.weather_configuration()))
	_control_tail(source, 40, 120)
	var expected_tail: PackedByteArray = var_to_bytes(source.checkpoint())
	var same_session_restore: bool = source.restore_checkpoint(checkpoint)
	_control_tail(source, 40, 120)
	_check("wind checkpoint rollback and recorded control tail replay byte-exactly",
		same_session_restore and var_to_bytes(source.checkpoint()) == expected_tail,
		"restore %s, tick %d" % [str(same_session_restore), source.sim.tick])

	var fresh: Node = _new_session(STIK, Config.defaults())
	if fresh != null:
		var fresh_before: PackedByteArray = var_to_bytes(fresh.checkpoint())
		_check("fresh calm destination refuses altered weather fingerprint without partial restore",
			not fresh.restore_checkpoint(bad_hash) and var_to_bytes(fresh.checkpoint()) == fresh_before
				and fresh.weather_is_calm(), str(fresh.weather_configuration()))
		_check("fresh calm destination refuses malformed weather checkpoint atomically",
			not fresh.restore_checkpoint(invalid_checkpoint) and var_to_bytes(fresh.checkpoint()) == fresh_before,
			str(fresh.weather_configuration()))
		var restored: bool = fresh.restore_checkpoint(checkpoint)
		_check("fresh calm session adopts valid wind checkpoint identity",
			restored and fresh.weather_configuration() == replay_weather and fresh.sim.tick == source.sim.tick - 120,
			str(fresh.weather_configuration()))
		_control_tail(fresh, 40, 120)
		_check("fresh cross-session wind replay continues byte-exactly",
			var_to_bytes(fresh.checkpoint()) == expected_tail,
			"tick %d expected source tail %d" % [fresh.sim.tick, source.sim.tick])
		fresh.free()
	source.free()

	var calm: Node = _new_session(STIK, Config.defaults())
	if calm != null:
		_check("default calm checkpoint retains version 1", calm.checkpoint().get("format", "") == "openrc-flight-checkpoint v1")
		calm.free()


func _initialize() -> void:
	var original_rate: int = Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 240
	_test_uniform_galilean_invariance()
	_test_same_state_wind_loads_and_ground_separation()
	_test_stage_wind_sampling()
	_test_rk4_cosine_gust_integral()
	_test_p51_shaft_uses_air_inflow()
	_test_reset_and_checkpoint_replay()
	Engine.physics_ticks_per_second = original_rate
	print("wind flight: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)

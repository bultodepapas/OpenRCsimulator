extends SceneTree

## External, deterministic refinement probe for the P-51 production flight session.
## Run with `godot --headless --path app --script <absolute-path-to-this-file> -- --mode=coupled-rk4`.
## Only tick-boundary commands change; the three servo channels remain at the production trim values.

const Session := preload("res://sim/flight_session.gd")
const Commands := preload("res://input/commands.gd")
const WeatherConfig := preload("res://physics/wind_config.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const DATA_PATH := "res://data/aircraft/p51d_mustang_120.json"
const DEFAULT_RATES := [60, 120, 240, 480, 960, 1920, 3840]
const RUN_DURATION := 0.5


func _initialize() -> void:
	var options := _options()
	var mode: String = str(options.get("mode", "coupled-rk4"))
	if mode not in ["split", "coupled-rk4"]:
		push_error("mode must be split or coupled-rk4")
		quit(2)
		return
	var duration: float = float(options.get("duration", RUN_DURATION))
	if not is_finite(duration) or duration <= 0.0 or duration > 1.0:
		push_error("duration must be finite and in (0, 1] seconds")
		quit(2)
		return
	var rates: Array[int] = _rates(str(options.get("rates", "")))
	if rates.is_empty():
		push_error("rates must be positive comma-separated integer Hz values")
		quit(2)
		return
	var cases: Array[Dictionary] = [
		{"name": "throttle_step", "weather": WeatherConfig.defaults(), "throttle": "trim_plus_0.03"},
		{"name": "smooth_gust", "weather": _gust_weather(), "throttle": "trim"},
		{"name": "practical_punch", "weather": WeatherConfig.defaults(), "throttle": 0.8},
	]
	var rows: Array[Dictionary] = []
	for scenario: Dictionary in cases:
		for hz: int in rates:
			var row: Dictionary = _run_case(str(scenario.name), scenario.weather, scenario.throttle, mode, hz, duration)
			if not row.get("ok", false):
				push_error("%s at %d Hz: %s" % [scenario.name, hz, row.get("error", "unknown failure")])
				print("REFINEMENT_JSON:" + JSON.stringify({"ok": false, "error": row.get("error", "unknown failure"),
					"case": scenario.name, "mode": mode, "rate_hz": hz}))
				quit(1)
				return
			rows.append(row)
	print("REFINEMENT_JSON:" + JSON.stringify({
		"format": "openrc-g2a-rk4-refinement-probe v1",
		"ok": true,
		"mode": mode,
		"duration_s": duration,
		"rates_hz": rates,
		"rows": rows,
	}, "", true, true))
	quit(0)


func _options() -> Dictionary:
	var out := {}
	for raw: String in OS.get_cmdline_user_args():
		if not raw.begins_with("--"):
			continue
		var parts: PackedStringArray = raw.trim_prefix("--").split("=", true, 1)
		if parts.size() == 2:
			out[parts[0]] = parts[1]
	return out


func _rates(value: String) -> Array[int]:
	if value.is_empty():
		return DEFAULT_RATES.duplicate()
	var out: Array[int] = []
	for item: String in value.split(","):
		if not item.is_valid_int():
			return []
		var hz := int(item)
		if hz < 1 or out.has(hz):
			return []
		out.append(hz)
	out.sort()
	return out


func _gust_weather() -> Dictionary:
	return {
		"format": "openrc-weather v1",
		"speed_mps": 0.0,
		"from_deg": 270.0,
		"gust_mps": 3.0,
		"gust_up_mps": 1.5,
		"gust_duration_s": RUN_DURATION,
		"gust_period_s": 2.0,
		"gust_delay_s": 0.0,
	}


func _run_case(case_name: String, weather: Dictionary, throttle_spec: Variant, mode: String,
		hz: int, duration: float) -> Dictionary:
	var exact_ticks: float = duration * float(hz)
	var tick_count := roundi(exact_ticks)
	if tick_count < 1 or absf(exact_ticks - float(tick_count)) > 1e-10:
		return {"ok": false, "error": "duration is not an integer number of ticks"}
	Engine.physics_ticks_per_second = hz
	var session = Session.new()
	session.input_enabled = false
	session.physics_enabled = false
	if not session.setup_shaft_integrator(mode):
		session.free()
		return {"ok": false, "error": session.shaft_error}
	if not session.setup_weather(weather):
		session.free()
		return {"ok": false, "error": session.weather_error}
	session.setup(DATA_PATH)
	if not session.is_flyable():
		var reason: String = session.start_error if not session.start_error.is_empty() else str(session.sim.fault_reason)
		session.free()
		return {"ok": false, "error": "P-51 session did not start: " + reason}
	var trim_throttle: float = float(session.start.throttle)
	var throttle: float = trim_throttle
	if typeof(throttle_spec) == TYPE_FLOAT or typeof(throttle_spec) == TYPE_INT:
		throttle = float(throttle_spec)
	elif throttle_spec == "trim_plus_0.03":
		throttle = minf(1.0, trim_throttle + 0.03)
	session.commands = Commands.neutral_commands()
	session.commands.throttle = throttle
	session.sim.inputs = session._inputs()
	var prop: Dictionary = session.aircraft.model.propulsion
	var diagnostics := {
		"stage_query_count": 0,
		"stage_rpm_min": INF,
		"stage_rpm_max": -INF,
		"stage_j_min": INF,
		"stage_j_max": -INF,
		"endpoint_crossings": {"cp_j": [], "ct_j": [], "shaft_rpm": []},
	}
	var observe_stage := func(body: PackedFloat64Array, values: PackedFloat64Array, stage_time: float) -> void:
		var rpm: float = session._coupled_rpm(values) if mode == "coupled-rk4" else float(session.sim.aux[Session.AUX_RPM])
		var air: Dictionary = session.air_data(body, stage_time)
		var speed: float = maxf(0.0, M.dot(air.v_air, prop.get("axis", PackedFloat64Array([1.0, 0.0, 0.0]))))
		var revolutions_s: float = rpm / 60.0
		var advance: float = speed / (revolutions_s * float(prop.diameter)) if revolutions_s > 0.0 else NAN
		diagnostics.stage_query_count += 1
		diagnostics.stage_rpm_min = minf(float(diagnostics.stage_rpm_min), rpm)
		diagnostics.stage_rpm_max = maxf(float(diagnostics.stage_rpm_max), rpm)
		if is_finite(advance):
			diagnostics.stage_j_min = minf(float(diagnostics.stage_j_min), advance)
			diagnostics.stage_j_max = maxf(float(diagnostics.stage_j_max), advance)
	if not session.sim.continuous.is_empty():
		var original_continuous_loads: Callable = session.sim.continuous_loads
		if not original_continuous_loads.is_valid():
			session.free()
			return {"ok": false, "error": "production continuous-load callback is unavailable"}
		session.sim.continuous_loads = func(body: PackedFloat64Array, values: PackedFloat64Array,
				stage_time: float) -> PackedFloat64Array:
			observe_stage.call(body, values, stage_time)
			return original_continuous_loads.call(body, values, stage_time)
	else:
		var original_body_loads: Callable = session.sim.loads
		if not original_body_loads.is_valid():
			session.free()
			return {"ok": false, "error": "production body-load callback is unavailable"}
		session.sim.loads = func(body: PackedFloat64Array, stage_time: float) -> PackedFloat64Array:
			observe_stage.call(body, PackedFloat64Array(), stage_time)
			return original_body_loads.call(body, stage_time)
	var previous_j: float = _advance_ratio(session, session.sim.state, float(session.sim.aux[Session.AUX_RPM]), 0.0, prop)
	var previous_rpm: float = float(session.sim.aux[Session.AUX_RPM])
	var start_j := previous_j
	for _tick: int in tick_count:
		session.sim.step()
		if not session.sim.fault_reason.is_empty():
			var fault: String = str(session.sim.fault_reason)
			session.free()
			return {"ok": false, "error": "simulation fault: " + fault}
		var rpm: float = float(session.sim.aux[Session.AUX_RPM])
		var advance: float = _advance_ratio(session, session.sim.state, rpm, session.sim.time(), prop)
		_add_crossings(prop.cp, previous_j, advance, diagnostics.endpoint_crossings.cp_j)
		_add_crossings(prop.ct, previous_j, advance, diagnostics.endpoint_crossings.ct_j)
		_add_crossings(prop.shaft.power_curve, previous_rpm, rpm, diagnostics.endpoint_crossings.shaft_rpm)
		previous_j = advance
		previous_rpm = rpm
	var state: PackedFloat64Array = session.sim.state.duplicate()
	var end_rpm: float = float(session.sim.aux[Session.AUX_RPM])
	var stage_cp_knots: Array[float] = _knots_in_range(prop.cp, diagnostics.stage_j_min, diagnostics.stage_j_max)
	var stage_ct_knots: Array[float] = _knots_in_range(prop.ct, diagnostics.stage_j_min, diagnostics.stage_j_max)
	var stage_rpm_knots: Array[float] = _knots_in_range(prop.shaft.power_curve,
		diagnostics.stage_rpm_min, diagnostics.stage_rpm_max)
	var result := {
		"ok": true,
		"case": case_name,
		"mode": mode,
		"rate_hz": hz,
		"duration_s": duration,
		"ticks": tick_count,
		"trim_throttle": trim_throttle,
		"throttle": throttle,
		"throttle_delta": throttle - trim_throttle,
		"weather": weather,
		"state": Array(state),
		"rpm": end_rpm,
		"start_rpm": float(session.start.rpm),
		"start_j": start_j,
		"end_j": previous_j,
		"stage_queries": diagnostics,
		"stage_j_knots_in_range": stage_cp_knots,
		"stage_ct_knots_in_range": stage_ct_knots,
		"stage_shaft_rpm_knots_in_range": stage_rpm_knots,
	}
	session.free()
	return result


func _advance_ratio(session, body: PackedFloat64Array, rpm: float, time_s: float, prop: Dictionary) -> float:
	var air: Dictionary = session.air_data(body, time_s)
	var axial_speed: float = maxf(0.0, M.dot(air.v_air, prop.get("axis", PackedFloat64Array([1.0, 0.0, 0.0]))))
	var rev_s: float = rpm / 60.0
	return axial_speed / (rev_s * float(prop.diameter)) if rev_s > 0.0 else NAN


func _add_crossings(table: PackedFloat64Array, before: float, after: float, found: Array) -> void:
	if not is_finite(before) or not is_finite(after):
		return
	for index: int in range(0, table.size(), 2):
		var knot: float = table[index]
		var crossed: bool = (before < knot and after >= knot) or (before > knot and after <= knot)
		if crossed and not found.has(knot):
			found.append(knot)


func _knots_in_range(table: PackedFloat64Array, low: float, high: float) -> Array[float]:
	var out: Array[float] = []
	if not is_finite(low) or not is_finite(high):
		return out
	for index: int in range(0, table.size(), 2):
		var knot: float = table[index]
		if knot >= low and knot <= high:
			out.append(knot)
	return out

# EX-06 bounded, descriptive flight-envelope probe for the GP Extra 300S .60.
# Run with Godot 4.7: --headless --path app --script <absolute path> -- --output=<absolute-json-path> [--hz=240]
# This records model predictions, not physical acceptance. It adds no thresholds and makes no fidelity claim.
# Ground launch/landing is omitted: FlightSession's supported runway start is Stik-only. Knife-edge, outside-loop,
# snap-roll, wind, and fuel/lifecycle cases remain explicitly unprobed in this bounded core audit.
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Maneuvers := preload("res://sim/maneuvers.gd")
const Recorder := preload("res://sim/recorder.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const Trim := preload("res://physics/trim.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

const EXTRA_ID := "gp-extra-300s-60"
const G := 9.80665
const LOW_TRAVEL_FRACTION := { roll = 0.4, pitch = 0.6, yaw = 0.6 }


func _initialize() -> void:
	var output_path := ""
	var hz := 240
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output_path = arg.trim_prefix("--output=")
		elif arg.begins_with("--hz=") and arg.trim_prefix("--hz=").is_valid_int():
			hz = int(arg.trim_prefix("--hz="))
	if output_path.is_empty():
		printerr("EX-06 probe requires --output=<absolute-json-path>")
		quit(2)
		return
	if hz < 30 or hz > 2000:
		printerr("EX-06 probe --hz must be between 30 and 2000")
		quit(2)
		return
	Engine.physics_ticks_per_second = hz

	var session := Session.new()
	session.setup(Catalog.entry(EXTRA_ID).data, EXTRA_ID)
	root.add_child(session)
	var report := {
		"schema": "openrc-extra-envelope-probe-v1",
		"probe": "EX-06 bounded descriptive audit",
		"aircraft_id": EXTRA_ID,
		"physics_hz": hz,
		"dt_s": 1.0 / float(hz),
		"scope": "Deterministic calm-air simulation metrics; descriptive only; not physical validation or a pass/fail gate.",
		"coverage_inventory": _coverage_inventory(),
		"cases": [],
	}
	if not session.aircraft.get("ok", false) or not session.start.get("ok", false):
		report["setup"] = { "available": false, "message": str(session.start.get("message", "aircraft data or initial trim failed")) }
		_write_json(output_path, report)
		quit(1)
		return

	var model: Dictionary = session.aircraft.model
	var own_start: Dictionary = session.start
	report["setup"] = {
		"available": true,
		"model_start_trim": _trim_snapshot(own_start),
		"high_rate_throws_deg": model.controls.throw_deg.duplicate(true),
		"manual_low_rate_mapping": _manual_rate_mapping(model),
		"environment": "default calm air and reference density; no wind or turbulence override",
	}
	var cases: Array = report["cases"]

	# The model's own start trim is replayed for 30 seconds with neutral pilot input.
	var hands_off: Callable = func(_t: float, _s: PackedFloat64Array) -> Dictionary: return Maneuvers._hands_off()
	_store_case(cases, session, "own_trim_hands_off_30s", "level", float(model.start_speed), 30.0, -1.0, hands_off)

	# Low and high rates are compared for both signs on all three pilot axes. Low amplitudes are derived from angular
	# travel equivalence: asin(fraction * sin(high throw)) / high throw, not the raw linear travel fraction.
	var rate_map: Dictionary = _manual_rate_mapping(model)
	for axis: String in ["roll", "pitch", "yaw"]:
		var angle_data: Dictionary = rate_map[axis]
		for direction: int in [-1, 1]:
			for rate_name: String in ["low", "high"]:
				var amplitude: float = float(angle_data.angular_command_fraction) if rate_name == "low" else 1.0
				amplitude *= float(direction)
				var axis_command: String = axis
				var stick: Callable = func(t: float, _s: PackedFloat64Array) -> Dictionary:
					var c := Maneuvers._hands_off()
					if t >= 0.25 and t < 1.25:
						c[axis_command] = amplitude
					return c
				var case_id := "%s_%s_%s" % [axis, "positive" if direction > 0 else "negative", rate_name]
				var result := _run_flight_case(session, case_id, "level", 15.0, 3.5, 80.0, stick)
				result.summary["control_probe"] = {
					"pilot_axis": axis,
					"command_sign": direction,
					"rate": rate_name,
					"pilot_command_amplitude": amplitude,
					"high_throw_deg": angle_data.high_throw_deg,
					"low_equivalent_throw_deg": angle_data.low_throw_deg,
					"low_angular_command_fraction": angle_data.angular_command_fraction,
					"pulse_window_s": [0.25, 1.25],
				}
				cases.append(result.summary)

	# Throttle transient, a modest banked turn with counter-roll recovery, and a sustained full-power climb.
	var throttle_step: Callable = func(t: float, _s: PackedFloat64Array) -> Dictionary:
		return { "roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle_delta": 1.0 if t >= 0.25 and t < 1.25 else 0.0 }
	_store_case(cases, session, "throttle_full_step_and_return", "level", 15.0, 5.0, 60.0, throttle_step)

	var turn: Callable = func(t: float, s: PackedFloat64Array) -> Dictionary:
		var c := Maneuvers._hands_off()
		if t >= 0.25 and t < 1.25:
			c.roll = 0.35
		elif t >= 4.25 and t < 5.25:
			c.roll = -0.35
		return Maneuvers._coordinated(c, s)
	_store_case(cases, session, "banked_turn_and_counter_roll_recovery", "level", 17.0, 7.0, 70.0, turn)

	# Separate the open-loop bank disturbance above from an ordinary, altitude-controlled turn. These are explicit
	# probe pilot gains, not aircraft coefficients; commands remain within the manual low-rate travel fractions.
	for direction: int in [-1, 1]:
		var turn_direction := direction
		var turn_pilot: Callable = func(t: float, s: PackedFloat64Array) -> Dictionary:
			var target_bank := float(turn_direction) * deg_to_rad(30.0) if t >= 0.5 and t < 7.0 else 0.0
			var attitude := M.quat(s[RB.ATT], s[RB.ATT + 1], s[RB.ATT + 2], s[RB.ATT + 3])
			var bank := M.q_to_euler(attitude)[2]
			var down_rate := M.q_rotate(attitude, M.v3(s[RB.VEL], s[RB.VEL + 1], s[RB.VEL + 2]))[2]
			var c := Maneuvers._hands_off()
			c.roll = clampf(1.5 * (target_bank - bank) - 0.4 * s[RB.RATE], -float(rate_map.roll.angular_command_fraction), float(rate_map.roll.angular_command_fraction))
			c.pitch = clampf(0.015 * (100.0 + s[RB.POS + 2]) + 0.05 * down_rate - 0.2 * s[RB.RATE + 1], -float(rate_map.pitch.angular_command_fraction), float(rate_map.pitch.angular_command_fraction))
			c = Maneuvers._coordinated(c, s)
			c.yaw = clampf(c.yaw, -float(rate_map.yaw.angular_command_fraction), float(rate_map.yaw.angular_command_fraction))
			return c
		_store_case(cases, session, "guided_30deg_turn_" + ("right" if direction > 0 else "left"), "level", 17.0, 12.0, 100.0, turn_pilot)

	var climb: Callable = func(_t: float, _s: PackedFloat64Array) -> Dictionary:
		return { "roll": 0.0, "pitch": 0.12, "yaw": 0.0, "throttle_delta": 1.0 }
	_store_case(cases, session, "full_power_climb_input", "level", 18.0, 5.0, 70.0, climb)

	var stall: Callable = func(t: float, _s: PackedFloat64Array) -> Dictionary:
		return Maneuvers._pulse(t, 0.25, 4.0, { "pitch": 1.0 })
	_store_case(cases, session, "power_off_full_up_stall", "glide", 12.0, 4.0, 100.0, stall)

	# Power-off descent and an engine-stopped glide/approach start are separate: the first idles a running engine;
	# the second uses FlightSession's explicit glide trim and stopped-engine mode.
	var idle_descent: Callable = func(_t: float, _s: PackedFloat64Array) -> Dictionary:
		return { "roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle_delta": -1.0 }
	_store_case(cases, session, "running_engine_idle_descent", "level", 15.0, 8.0, 70.0, idle_descent)

	var glide: Callable = func(_t: float, _s: PackedFloat64Array) -> Dictionary: return Maneuvers._hands_off()
	_store_case(cases, session, "engine_off_glide_approach", "glide", 15.0, 10.0, 80.0, glide)

	# Standard power-off spin entry and recovery, mirrored for the opposite rudder direction.
	for direction: int in [-1, 1]:
		var spin_direction := direction
		var spin_stick: Callable = func(t: float, _s: PackedFloat64Array) -> Dictionary:
			var c := Maneuvers._pulse(t, 0.25, 4.0, { "pitch": 1.0, "yaw": float(spin_direction) })
			if t >= 4.0 and t < 4.9:
				c = { "roll": 0.0, "pitch": -0.5, "yaw": -float(spin_direction), "throttle_delta": 0.0 }
			c.throttle_delta = -1.0
			return c
		var spin_id := "spin_right_rudder" if direction > 0 else "spin_left_rudder"
		var spin := _run_flight_case(session, spin_id, "level", 12.0, 8.0, 150.0, spin_stick)
		if spin.get("trace") != null:
			spin.summary["spin_windows"] = _spin_window_metrics(spin.trace)
		cases.append(spin.summary)

	# Research-only inverted 6DOF straight-flight trim. A converged solution is replayed hands-off; a failure is
	# emitted as an unavailable case with its reason, never replaced by an upright trim or treated as a test failure.
	var inverted := _solve_inverted_trim(model, 18.0, session.sim.gravity, session.air_density(), session.engine_charge_ratio())
	report["inverted_trim_solver"] = {
		"method": "bounded finite-difference Newton solve of the model's six rigid-body acceleration residuals",
		"available": inverted.get("ok", false),
		"message": str(inverted.get("message", "no solution")),
		"speed_mps": 18.0,
		"residual_l2": _finite_or_null(inverted.get("residual_l2", null)),
		"iterations": int(inverted.get("iterations", 0)),
		"trim": _trim_snapshot(inverted) if inverted.get("ok", false) else {},
	}
	if inverted.get("ok", false):
		var inverted_case := _run_inverted_hands_off(session, inverted, 7.0, 100.0)
		cases.append(inverted_case.summary)
	else:
		cases.append({
			"id": "inverted_hands_off_7s",
			"available": false,
			"reason": str(inverted.get("message", "research-only inverted trim did not converge")),
		})

	var saved := _write_json(output_path, report)
	if saved:
		print("EX-06 probe wrote %s (%d cases, %d Hz)" % [output_path, cases.size(), hz])
		quit(0)
	else:
		quit(1)


func _coverage_inventory() -> Array:
	return [
		{ "case": "own trim and hands-off", "status": "probed" },
		{ "case": "roll, pitch, yaw; both signs; low and high rate", "status": "probed" },
		{ "case": "throttle transient and power climb input", "status": "probed" },
		{ "case": "banked turn and counter-roll recovery", "status": "probed" },
		{ "case": "running-engine idle descent and engine-off glide/approach", "status": "probed" },
		{ "case": "power-off stall plus spin entry and standard recovery, both rudder directions", "status": "probed" },
		{ "case": "inverted straight trim and hands-off", "status": "conditional on research trim convergence" },
		{ "case": "takeoff, landing and runway rollout", "status": "omitted: current supported runway-start helper is Stik-only" },
		{ "case": "knife-edge, outside loop and snap roll", "status": "omitted from bounded probe; requires dedicated maneuver definitions and review" },
		{ "case": "wind/turbulence response and fuel/energy lifecycle", "status": "omitted; outputs include only specific mechanical-energy proxy, not a fuel/energy audit" },
	]


func _manual_rate_mapping(model: Dictionary) -> Dictionary:
	var high: Dictionary = model.controls.throw_deg
	var mapping := {}
	for axis: String in ["roll", "pitch", "yaw"]:
		var throw_key: String = { "roll": "aileron", "pitch": "elevator", "yaw": "rudder" }[axis]
		var high_deg := _number(high.get(throw_key, 0.0))
		var fraction := float(LOW_TRAVEL_FRACTION[axis])
		var high_rad := deg_to_rad(high_deg)
		var low_rad := asin(clampf(fraction * sin(high_rad), -1.0, 1.0))
		mapping[axis] = {
			"low_linear_travel_fraction": fraction,
			"high_throw_deg": high_deg,
			"low_throw_deg": rad_to_deg(low_rad),
			"angular_command_fraction": low_rad / high_rad if high_rad != 0.0 else 0.0,
			"calculation": "asin(low_linear_fraction * sin(high_throw)) / high_throw",
		}
	return mapping


func _store_case(cases: Array, session: Node, case_id: String, mode: String, speed: float,
		duration: float, altitude: float, sticks: Callable) -> void:
	var result := _run_flight_case(session, case_id, mode, speed, duration, altitude, sticks)
	cases.append(result.summary)


func _run_flight_case(session: Node, case_id: String, mode: String, speed: float, duration: float,
		altitude: float, sticks: Callable) -> Dictionary:
	var trim: Dictionary = session.trim_at(speed, mode)
	if not trim.get("ok", false):
		return { "summary": { "id": case_id, "available": false, "reason": str(trim.get("message", "trim failed")) } }
	var maneuver := { "mode": mode, "speed": speed, "duration": duration, "sticks": sticks }
	if altitude >= 0.0:
		maneuver["altitude"] = altitude
	var trace: RefCounted = Maneuvers.fly(session, maneuver)
	return {
		"summary": {
			"id": case_id,
			"available": true,
			"mode": mode,
			"trim": _trim_snapshot(trim),
			"flight": _trace_metrics(trace, session.sim.dt(), duration),
			"simulation_fault": str(session.sim.fault_reason),
		},
		"trace": trace,
	}


func _trim_snapshot(trim: Dictionary) -> Dictionary:
	var residual_value: Variant = trim.get("residual_l2", trim.get("residual", null))
	var residual_norm: Variant = null
	if typeof(residual_value) in [TYPE_FLOAT, TYPE_INT]:
		residual_norm = _finite_or_null(residual_value)
	elif residual_value is PackedFloat64Array:
		var sum := 0.0
		var all_finite := true
		for component: float in residual_value:
			if not is_finite(component):
				all_finite = false
				break
			sum += component * component
		if all_finite:
			residual_norm = sqrt(sum)
	return {
		"ok": bool(trim.get("ok", false)),
		"mode": str(trim.get("mode", "")),
		"speed_mps": _number(trim.get("V", 0.0)),
		"alpha_deg": rad_to_deg(_number(trim.get("alpha", 0.0))),
		"beta_deg": rad_to_deg(_number(trim.get("beta", 0.0))),
		"gamma_deg": rad_to_deg(_number(trim.get("gamma", 0.0))),
		"throttle": _number(trim.get("throttle", 0.0)),
		"rpm": _number(trim.get("rpm", 0.0)),
		"aero_surface_angles_deg": {
			"elevator_te_down_positive": rad_to_deg(_number(trim.get("elevator", 0.0))),
			"aileron_te_down_positive": rad_to_deg(_number(trim.get("aileron", 0.0))),
			"rudder_te_left_positive": rad_to_deg(_number(trim.get("rudder", 0.0))),
		},
		"pilot_trim_commands": {
			"roll": _number(trim.get("roll_command", 0.0)),
			"pitch": _number(trim.get("pitch_command", 0.0)),
			"yaw": _number(trim.get("yaw_command", 0.0)),
		},
		"residual_l2": residual_norm,
		"iterations": int(trim.get("iterations", 0)),
		"message": str(trim.get("message", "")),
	}


func _trace_metrics(trace: RefCounted, dt: float, requested_duration: float) -> Dictionary:
	var rows: int = trace.row_count()
	var metric_names := [
		"speed_mps", "alt_m", "alpha_deg", "beta_deg", "roll_deg", "pitch_deg", "yaw_deg",
		"p_radps", "q_radps", "r_radps", "engine_rpm", "cmd_roll", "cmd_pitch", "cmd_yaw",
		"cmd_throttle", "srv_roll", "srv_pitch", "srv_yaw", "specific_energy_m2_s2",
	]
	var accumulators := {}
	for name: String in metric_names:
		accumulators[name] = { "count": 0, "first": 0.0, "last": 0.0, "min": 1.0e300, "max": -1.0e300, "max_abs": 0.0 }
	var nonfinite_scalars := 0
	var columns: Array = trace.columns()
	for row in rows:
		for column: String in columns:
			if not is_finite(trace.value(row, column)):
				nonfinite_scalars += 1
		var u: float = trace.value(row, "u_mps")
		var v: float = trace.value(row, "v_mps")
		var w: float = trace.value(row, "w_mps")
		var speed: float = trace.value(row, "speed_mps")
		var altitude: float = trace.value(row, "alt_m")
		var beta: float = rad_to_deg(atan2(v, sqrt(u * u + w * w)))
		var alpha: float = rad_to_deg(atan2(w, u))
		var energy: float = G * altitude + 0.5 * speed * speed
		var values := {
			"speed_mps": speed, "alt_m": altitude, "alpha_deg": alpha, "beta_deg": beta,
			"roll_deg": trace.value(row, "roll_deg"), "pitch_deg": trace.value(row, "pitch_deg"),
			"yaw_deg": trace.value(row, "yaw_deg"), "p_radps": trace.value(row, "p_radps"),
			"q_radps": trace.value(row, "q_radps"), "r_radps": trace.value(row, "r_radps"),
			"engine_rpm": trace.value(row, "engine_rpm"), "cmd_roll": trace.value(row, "cmd_roll"),
			"cmd_pitch": trace.value(row, "cmd_pitch"), "cmd_yaw": trace.value(row, "cmd_yaw"),
			"cmd_throttle": trace.value(row, "cmd_throttle"), "srv_roll": trace.value(row, "srv_roll"),
			"srv_pitch": trace.value(row, "srv_pitch"), "srv_yaw": trace.value(row, "srv_yaw"),
			"specific_energy_m2_s2": energy,
		}
		for name: String in metric_names:
			_append_metric(accumulators[name], float(values[name]))
	var metrics := {}
	for name: String in metric_names:
		var a: Dictionary = accumulators[name]
		var has_samples: bool = int(a.count) > 0
		metrics[name] = {
			"start": _number(a.first) if has_samples else 0.0,
			"end": _number(a.last) if has_samples else 0.0,
			"min": _number(a.min) if has_samples else 0.0,
			"max": _number(a.max) if has_samples else 0.0,
			"max_abs": _number(a.max_abs) if has_samples else 0.0,
			"delta": _number(a.last - a.first) if has_samples else 0.0,
			"finite_samples": int(a.count),
		}
	return {
		"rows": rows,
		"expected_rows": roundi(requested_duration / dt) + 1,
		"duration_s": maxf(0.0, (trace.value(rows - 1, "t_s") - trace.value(0, "t_s"))) if rows > 0 else 0.0,
		"trace_continuous": trace.is_continuous(),
		"nonfinite_scalar_count": nonfinite_scalars,
		"metrics": metrics,
		"energy_note": "specific mechanical-energy proxy = g*altitude + 0.5*speed^2 (m^2/s^2); excludes fuel, engine and thermal energy",
	}


func _append_metric(accumulator: Dictionary, value: float) -> void:
	if not is_finite(value):
		return
	if int(accumulator.count) == 0:
		accumulator.first = value
	accumulator.last = value
	accumulator.count = int(accumulator.count) + 1
	accumulator.min = minf(float(accumulator.min), value)
	accumulator.max = maxf(float(accumulator.max), value)
	accumulator.max_abs = maxf(float(accumulator.max_abs), absf(value))


func _spin_window_metrics(trace: RefCounted) -> Dictionary:
	var entry := _window_series(trace, "r_radps", 2.5, 4.0)
	var recovery := _window_series(trace, "r_radps", 4.0, 4.9)
	var after := _window_series(trace, "r_radps", 7.0, 8.0)
	var entry_alt := _window_series(trace, "alt_m", 2.5, 4.0)
	var alpha := _window_series(trace, "alpha_deg", 2.5, 4.0)
	return {
		"entry_yaw_rate_rad_s_2p5_to_4s": entry,
		"recovery_yaw_rate_rad_s_4_to_4p9s": recovery,
		"post_recovery_yaw_rate_rad_s_7_to_8s": after,
		"entry_altitude_m_2p5_to_4s": entry_alt,
		"entry_alpha_deg_2p5_to_4s": alpha,
	}


func _window_series(trace: RefCounted, column: String, t0: float, t1: float) -> Dictionary:
	var count := 0
	var total := 0.0
	var low := 1.0e300
	var high := -1.0e300
	var max_abs := 0.0
	for row in trace.row_count():
		var t: float = trace.value(row, "t_s")
		if t < t0 or t > t1:
			continue
		var value: float
		if column == "alpha_deg":
			value = rad_to_deg(atan2(trace.value(row, "w_mps"), trace.value(row, "u_mps")))
		else:
			value = trace.value(row, column)
		if not is_finite(value):
			continue
		count += 1
		total += value
		low = minf(low, value)
		high = maxf(high, value)
		max_abs = maxf(max_abs, absf(value))
	return {
		"samples": count,
		"mean": total / float(count) if count > 0 else 0.0,
		"min": low if count > 0 else 0.0,
		"max": high if count > 0 else 0.0,
		"max_abs": max_abs,
	}


func _solve_inverted_trim(model: Dictionary, speed: float, gravity: float, rho: float, charge: float) -> Dictionary:
	var throws: Dictionary = model.controls.throw_rad
	var upright: Dictionary = Trim.solve("level", speed, model, gravity, throws, rho, charge)
	var seeds: Array = []
	if upright.get("ok", false):
		seeds.append(PackedFloat64Array([
			-float(upright.alpha), -float(upright.elevator), float(upright.throttle),
			-float(upright.beta), float(upright.aileron), float(upright.rudder),
		]))
	seeds.append(PackedFloat64Array([-0.08, 0.04, 0.55, 0.0, 0.0, 0.0]))
	seeds.append(PackedFloat64Array([-0.16, 0.08, 0.75, 0.0, 0.0, 0.0]))
	var best_norm := 1.0e300
	var best_x := PackedFloat64Array()
	var best_iterations := 0
	var best_message := "no finite inverted-flight residual from any initial guess"
	for seed: PackedFloat64Array in seeds:
		var x := seed.duplicate()
		var evaluated := _inverted_residual(x, speed, model, gravity, rho, charge)
		if not evaluated.get("ok", false):
			continue
		var residual: PackedFloat64Array = evaluated.residual
		var norm := _norm(residual)
		for iteration in range(41):
			if norm < best_norm:
				best_norm = norm
				best_x = x.duplicate()
				best_iterations = iteration
			if norm <= 1.0e-8:
				break
			var jacobian: Array = []
			for _i in 6:
				jacobian.append(PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]))
			var jacobian_ok := true
			for k in 6:
				var h := 1.0e-6 * maxf(1.0, absf(x[k]))
				var perturbed := x.duplicate()
				perturbed[k] += h
				var perturbed_result := _inverted_residual(perturbed, speed, model, gravity, rho, charge)
				if not perturbed_result.get("ok", false):
					perturbed[k] -= 2.0 * h
					perturbed_result = _inverted_residual(perturbed, speed, model, gravity, rho, charge)
					h = -h
				if not perturbed_result.get("ok", false):
					jacobian_ok = false
					break
				var r_perturbed: PackedFloat64Array = perturbed_result.residual
				for i in 6:
					jacobian[i][k] = (r_perturbed[i] - residual[i]) / h
			if not jacobian_ok:
				best_message = "finite-difference Jacobian unavailable near an iterate"
				break
			var negative := PackedFloat64Array()
			for component: float in residual:
				negative.append(-component)
			var delta: PackedFloat64Array = Trim.solve_linear(jacobian, negative)
			if delta.is_empty():
				best_message = "singular or nonfinite inverted-trim Jacobian"
				break
			var accepted := false
			for scale: float in [1.0, 0.5, 0.25, 0.125, 0.0625, 0.03125, 0.015625]:
				var candidate := x.duplicate()
				for k in 6:
					candidate[k] += scale * delta[k]
				if not _inverted_iterate_in_bounds(candidate, throws):
					continue
				var candidate_result := _inverted_residual(candidate, speed, model, gravity, rho, charge)
				if candidate_result.get("ok", false):
					var candidate_norm := _norm(candidate_result.residual)
					if candidate_norm < norm:
						x = candidate
						residual = candidate_result.residual
						norm = candidate_norm
						accepted = true
						break
			if not accepted:
				best_message = "damped Newton iteration could not reduce the inverted-flight residual"
				break
		if norm <= 1.0e-8:
			if absf(x[1]) <= throws.elevator and absf(x[4]) <= throws.aileron and absf(x[5]) <= throws.rudder:
				var final_eval := _inverted_residual(x, speed, model, gravity, rho, charge)
				var state: PackedFloat64Array = final_eval.state
				var rpm := float(final_eval.rpm)
				return _inverted_trim_result(true, "research-only inverted 6DOF trim converged", x, state, rpm, norm, best_iterations, speed, throws)
			best_message = "converged residual requires a surface beyond the model's mechanical throw"
	return {
		"ok": false,
		"message": best_message,
		"residual_l2": best_norm if best_norm < 1.0e299 else 0.0,
		"iterations": best_iterations,
	}


func _inverted_residual(x: PackedFloat64Array, speed: float, model: Dictionary, gravity: float,
		rho: float, charge: float) -> Dictionary:
	if x.size() != 6 or not _finite_array(x) or x[2] < 0.0 or x[2] > 1.0:
		return { "ok": false }
	var alpha := x[0]
	var beta := x[3]
	var velocity := M.v3(speed * cos(alpha) * cos(beta), speed * sin(beta), speed * sin(alpha) * cos(beta))
	var state := RB.make_state(M.v3(0.0, 0.0, -100.0), velocity, M.q_from_euler(0.0, -alpha, PI), M.v3(0.0, 0.0, 0.0))
	var axial_speed := M.dot(velocity, Propulsion.axis(model.propulsion))
	var rpm := Propulsion.steady_rpm(x[2], axial_speed, model.propulsion, rho, charge)
	if not is_finite(rpm):
		return { "ok": false }
	var deflections := {
		"elevator": x[1], "aileron_right": x[4], "aileron_left": -x[4], "rudder": x[5],
	}
	var derivative: PackedFloat64Array = Dynamics.evaluate(state, model, deflections, rpm, rho, M.v3(0.0, 0.0, 0.0), gravity).derivative
	var residual := PackedFloat64Array([
		derivative[RB.VEL], derivative[RB.VEL + 2], derivative[RB.RATE + 1],
		derivative[RB.VEL + 1], derivative[RB.RATE], derivative[RB.RATE + 2],
	])
	if not _finite_array(residual):
		return { "ok": false }
	return { "ok": true, "residual": residual, "state": state, "rpm": rpm }


func _inverted_iterate_in_bounds(x: PackedFloat64Array, throws: Dictionary) -> bool:
	return _finite_array(x) and x[0] >= -0.6 and x[0] <= 0.25 \
		and absf(x[1]) <= 3.0 * throws.elevator and x[2] >= 0.0 and x[2] <= 1.0 \
		and absf(x[3]) <= 0.5 and absf(x[4]) <= 3.0 * throws.aileron \
		and absf(x[5]) <= 3.0 * throws.rudder


func _inverted_trim_result(ok: bool, message: String, x: PackedFloat64Array, state: PackedFloat64Array,
		rpm: float, residual_norm: float, iterations: int, speed: float, throws: Dictionary) -> Dictionary:
	return {
		"ok": ok,
		"message": message,
		"mode": "inverted_level",
		"V": speed,
		"alpha": x[0],
		"beta": x[3],
		"gamma": 0.0,
		"throttle": x[2],
		"rpm": rpm,
		"elevator": x[1],
		"aileron": x[4],
		"rudder": x[5],
		"pitch_command": -x[1] / throws.elevator,
		"roll_command": -x[4] / throws.aileron,
		"yaw_command": -x[5] / throws.rudder,
		"state": state,
		"residual_l2": residual_norm,
		"iterations": iterations,
	}


func _run_inverted_hands_off(session: Node, trim: Dictionary, duration: float, altitude: float) -> Dictionary:
	var start: Dictionary = trim.duplicate(true)
	var state: PackedFloat64Array = start.state.duplicate()
	state[RB.POS + 2] = -altitude
	start.state = state
	start["ok"] = true
	session.start = start
	session.trims = { "roll": trim.roll_command, "pitch": trim.pitch_command, "yaw": trim.yaw_command }
	session.reset()
	var recorder := Recorder.new(session.sim, session.electrical_state)
	recorder.start(session.trace_meta())
	var steps := roundi(duration / session.sim.dt())
	for _i in steps:
		session.commands = {
			"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": float(trim.throttle),
		}
		session.sim.inputs = session._inputs()
		session.sim.step()
	recorder.detach()
	var trace: RefCounted = recorder.trace
	return {
		"summary": {
			"id": "inverted_hands_off_7s",
			"available": true,
			"mode": "inverted_level",
			"trim": _trim_snapshot(trim),
			"flight": _trace_metrics(trace, session.sim.dt(), duration),
			"simulation_fault": str(session.sim.fault_reason),
			"interpretation": "research-only model prediction; no measured inverted-flight acceptance target",
		},
	}


func _finite_array(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true


func _norm(values: PackedFloat64Array) -> float:
	var sum := 0.0
	for value: float in values:
		sum += value * value
	return sqrt(sum)


func _number(value: Variant, fallback: float = 0.0) -> float:
	if typeof(value) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(value)):
		return float(value)
	return fallback


func _finite_or_null(value: Variant) -> Variant:
	if typeof(value) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(value)):
		return float(value)
	return null


func _write_json(path: String, report: Dictionary) -> bool:
	var resolved := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	var dir := resolved.get_base_dir()
	var dir_error := DirAccess.make_dir_recursive_absolute(dir)
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		printerr("EX-06 probe could not create output directory: %s (error %d)" % [dir, dir_error])
		return false
	var file := FileAccess.open(resolved, FileAccess.WRITE)
	if file == null:
		printerr("EX-06 probe could not open JSON output: %s (error %d)" % [resolved, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	file.close()
	return true

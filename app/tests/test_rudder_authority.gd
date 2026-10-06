# D10-R1: rudder authority and recovery through the real flight-session paths.
# The 15 m/s doublet limits are estimated engineering screens from docs/RUDDER-REPAIR-PLAN.md, not flight data.
# Other amplitudes, pulse lengths, and speeds are numerical/route samples only; they have no doublet limits.
# Run: godot --headless --path . --script res://tests/test_rudder_authority.gd
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Maneuvers := preload("res://sim/maneuvers.gd")
const Recorder := preload("res://sim/recorder.gd")
const Trace := preload("res://sim/trace.gd")

const REFERENCE_HZ := 240
const BETA_LIMIT_DEG := 25.0 # estimated screen in RUDDER-REPAIR-PLAN.md
const YAW_RATE_LIMIT_DEG_S := 120.0 # estimated screen in RUDDER-REPAIR-PLAN.md
const RELEASE_YAW_RATE_LIMIT_DEG_S := 15.0 # at 1.5 s after release; estimated screen in RUDDER-REPAIR-PLAN.md
const AUDITED_BORROWED_CNDR := -0.1811 # old borrowed datum, documented in docs/research/ugly-stik-rudder-audit.md
const FINITE_COLUMNS := Trace.COLUMNS
const DEVICE_ID := 61

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])
	if not ok:
		_failures += 1


func _new_session() -> Node:
	var session := Session.new()
	session.setup()
	# Session.setup prepares data but main.gd normally calls reset() after adding the node to the tree.
	# Initialize first so the first automatic physics notification never sees an empty state.
	session.reset()
	root.add_child(session)
	return session


func _run_maneuver(maneuver: Dictionary, hz: int, restore_borrowed_cndr := false) -> Dictionary:
	Engine.physics_ticks_per_second = hz
	var session := _new_session()
	if restore_borrowed_cndr:
		session.aircraft.model.aero.Cndr = AUDITED_BORROWED_CNDR
	var trace: RefCounted = Maneuvers.fly(session, maneuver)
	var fault := _fault_reason(session.sim)
	var tick_count: int = session.sim.tick
	session.free()
	return { trace = trace, fault = fault, ticks = tick_count, hz = hz }


func _doublet(reverse := false) -> Dictionary:
	var maneuver: Dictionary = Maneuvers.all().rudder_doublet.duplicate()
	if reverse:
		maneuver.sticks = func(t: float, _state: PackedFloat64Array) -> Dictionary:
			return _pulse(t, 0.5, 1.0, -1.0) if t < 1.0 else _pulse(t, 1.0, 1.5, 1.0)
	return maneuver


func _pulse_maneuver(speed: float, amplitude: float, pulse_s: float, direction: float, mode := "level") -> Dictionary:
	var start_s := 0.1
	var end_s := start_s + pulse_s
	return {
		mode = mode,
		speed = speed,
		duration = end_s + 0.5,
		sticks = func(t: float, _state: PackedFloat64Array) -> Dictionary:
			return _pulse(t, start_s, end_s, amplitude * direction),
	}


func _pulse(t: float, start_s: float, end_s: float, yaw: float) -> Dictionary:
	var command := 0.0
	if t >= start_s and t < end_s:
		command = yaw
	return { roll = 0.0, pitch = 0.0, yaw = command, throttle_delta = 0.0 }


func _trace_stats(trace: RefCounted, rudder_throw_deg: float) -> Dictionary:
	var stats := {
		finite = trace.row_count() > 1,
		continuous = trace.is_continuous(),
		beta_peak_deg = 0.0,
		alpha_peak_deg = 0.0,
		r_peak_deg_s = 0.0,
		r_positive_deg_s = -INF,
		r_negative_deg_s = INF,
		p_peak_deg_s = 0.0,
		roll_peak_deg = 0.0,
		speed_min_mps = INF,
		speed_max_mps = -INF,
		altitude_min_m = INF,
		altitude_max_m = -INF,
		altitude_change_peak_m = 0.0,
		engine_rpm_peak = 0.0,
		rms_beta_deg = 0.0,
		rms_r_deg_s = 0.0,
		rudder_right_delta_deg = -INF,
		rudder_left_delta_deg = INF,
		r_at_3s_deg_s = NAN,
		has_r_at_3s = false,
		r_final_deg_s = NAN,
		first_phase_yaw_deg_s = 0.0,
		first_phase_yaw_min_deg_s = INF,
		second_phase_yaw_deg_s = 0.0,
		second_phase_yaw_max_deg_s = -INF,
	}
	if trace.row_count() <= 1:
		stats.finite = false
		return stats
	var t0: float = trace.value(0, "t_s")
	var rudder_zero: float = trace.value(0, "srv_yaw") * rudder_throw_deg
	var beta_sq_sum := 0.0
	var r_sq_sum := 0.0
	for row in trace.row_count():
		for column in FINITE_COLUMNS:
			if not is_finite(trace.value(row, column)):
				stats.finite = false
		var t: float = trace.value(row, "t_s") - t0
		var u: float = trace.value(row, "u_mps")
		var v: float = trace.value(row, "v_mps")
		var w: float = trace.value(row, "w_mps")
		var beta := rad_to_deg(atan2(v, sqrt(u * u + w * w)))
		var alpha := rad_to_deg(atan2(w, u))
		var yaw_rate := rad_to_deg(trace.value(row, "r_radps"))
		var roll_rate := rad_to_deg(trace.value(row, "p_radps"))
		stats.beta_peak_deg = maxf(stats.beta_peak_deg, absf(beta))
		stats.alpha_peak_deg = maxf(stats.alpha_peak_deg, absf(alpha))
		stats.r_peak_deg_s = maxf(stats.r_peak_deg_s, absf(yaw_rate))
		stats.r_positive_deg_s = maxf(stats.r_positive_deg_s, yaw_rate)
		stats.r_negative_deg_s = minf(stats.r_negative_deg_s, yaw_rate)
		stats.p_peak_deg_s = maxf(stats.p_peak_deg_s, absf(roll_rate))
		stats.roll_peak_deg = maxf(stats.roll_peak_deg, absf(trace.value(row, "roll_deg")))
		stats.speed_min_mps = minf(stats.speed_min_mps, trace.value(row, "speed_mps"))
		stats.speed_max_mps = maxf(stats.speed_max_mps, trace.value(row, "speed_mps"))
		stats.altitude_min_m = minf(stats.altitude_min_m, trace.value(row, "alt_m"))
		stats.altitude_max_m = maxf(stats.altitude_max_m, trace.value(row, "alt_m"))
		stats.altitude_change_peak_m = maxf(stats.altitude_change_peak_m,
			absf(trace.value(row, "alt_m") - trace.value(0, "alt_m")))
		stats.engine_rpm_peak = maxf(stats.engine_rpm_peak, trace.value(row, "engine_rpm"))
		beta_sq_sum += beta * beta
		r_sq_sum += yaw_rate * yaw_rate
		var actual_rudder_deg: float = trace.value(row, "srv_yaw") * rudder_throw_deg - rudder_zero
		stats.rudder_right_delta_deg = maxf(stats.rudder_right_delta_deg, actual_rudder_deg)
		stats.rudder_left_delta_deg = minf(stats.rudder_left_delta_deg, actual_rudder_deg)
		if t >= 0.5 and t < 1.0:
			stats.first_phase_yaw_deg_s = maxf(stats.first_phase_yaw_deg_s, yaw_rate)
			stats.first_phase_yaw_min_deg_s = minf(stats.first_phase_yaw_min_deg_s, yaw_rate)
		if t >= 1.0 and t < 1.5:
			stats.second_phase_yaw_deg_s = minf(stats.second_phase_yaw_deg_s, yaw_rate)
			stats.second_phase_yaw_max_deg_s = maxf(stats.second_phase_yaw_max_deg_s, yaw_rate)
	var n := float(trace.row_count())
	stats.rms_beta_deg = sqrt(beta_sq_sum / n)
	stats.rms_r_deg_s = sqrt(r_sq_sum / n)
	var dt: float = trace.value(1, "t_s") - trace.value(0, "t_s")
	var sample_at_3s := roundi(3.0 / dt)
	if sample_at_3s < trace.row_count() and absf(trace.value(sample_at_3s, "t_s") - t0 - 3.0) <= dt * 0.01:
		stats.r_at_3s_deg_s = rad_to_deg(trace.value(sample_at_3s, "r_radps"))
		stats.has_r_at_3s = true
	stats.r_final_deg_s = rad_to_deg(trace.value(trace.row_count() - 1, "r_radps"))
	return stats


func _stats_detail(stats: Dictionary) -> String:
	var r_at_3s := "%.2f°/s" % stats.r_at_3s_deg_s if stats.has_r_at_3s else "unavailable"
	return "βpk %.2f° RMS %.2f°, rpk %.2f°/s RMS %.2f°/s, ppk %.2f°/s, αpk %.2f°, rollpk %.2f°, altitude %.2f–%.2f m (Δpk %.2f m), rpm pk %.0f, r@3s %s, rfinal %.2f°/s" % [
		stats.beta_peak_deg, stats.rms_beta_deg, stats.r_peak_deg_s, stats.rms_r_deg_s,
		stats.p_peak_deg_s, stats.alpha_peak_deg, stats.roll_peak_deg, stats.altitude_min_m,
		stats.altitude_max_m, stats.altitude_change_peak_m, stats.engine_rpm_peak, r_at_3s, stats.r_final_deg_s]


func _check_run_integrity(label: String, run: Dictionary, expected_rows: int, throw_deg: float) -> Dictionary:
	var trace: RefCounted = run.trace
	var stats := _trace_stats(trace, throw_deg)
	_check("%s completes without a simulation fault" % label, run.fault.is_empty(), str(run.fault))
	_check("%s records every tick" % label, trace.row_count() == expected_rows and trace.is_continuous(),
		"%d rows, expected %d; sim tick %d" % [trace.row_count(), expected_rows, run.ticks])
	_check("%s state, loads and commands stay finite" % label, stats.finite, _stats_detail(stats))
	return stats


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _joy_motion(device: int, axis: int, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = axis as JoyAxis
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _manual_ticks(session: Node, count: int) -> void:
	for i in count:
		session._physics_process(session.sim.dt())
		session.sim.step()


func _fault_reason(sim: Node) -> String:
	for property in sim.get_property_list():
		if property.name == "fault_reason":
			return str(sim.get("fault_reason"))
	return ""


func _initialize() -> void:
	await _run()


func _run() -> void:
	var saved_hz := Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = REFERENCE_HZ
	var reference_session := _new_session()
	var throws: Dictionary = reference_session.aircraft.model.controls.throw_deg
	var rudder_throw_deg: float = throws.rudder
	reference_session.free()

	# Reference ± doublet through the real session → commands → servo → aero → RK4 path.
	var right_first := _run_maneuver(_doublet(false), REFERENCE_HZ)
	var expected_reference_rows := roundi(3.0 * REFERENCE_HZ) + 1
	var right_stats := _check_run_integrity("right-first reference doublet", right_first, expected_reference_rows, rudder_throw_deg)
	_check("right-first doublet moves the real rudder both ways",
		right_stats.rudder_right_delta_deg > 20.0 and right_stats.rudder_left_delta_deg < -20.0,
		"δr right %.2f°, left %.2f°" % [right_stats.rudder_right_delta_deg, right_stats.rudder_left_delta_deg])
	_check("right-first doublet yaws in both commanded directions",
		right_stats.first_phase_yaw_deg_s > 0.0 and right_stats.second_phase_yaw_deg_s < 0.0,
		"right-phase r %.2f°/s, left-phase r %.2f°/s" % [right_stats.first_phase_yaw_deg_s, right_stats.second_phase_yaw_deg_s])
	_check("reference doublet |β| peak ≤25° (estimated screen)", right_stats.beta_peak_deg <= BETA_LIMIT_DEG, _stats_detail(right_stats))
	_check("reference doublet |r| peak ≤120°/s (estimated screen)", right_stats.r_peak_deg_s <= YAW_RATE_LIMIT_DEG_S, _stats_detail(right_stats))
	_check("|r| at 3.0 s (1.5 s after release) ≤15°/s (estimated recovery screen)",
		right_stats.has_r_at_3s and absf(right_stats.r_at_3s_deg_s) <= RELEASE_YAW_RATE_LIMIT_DEG_S,
		_stats_detail(right_stats))
	print("RUDDER_REFERENCE 15 m/s, 240 Hz: " + _stats_detail(right_stats))
	var old_cndr := _run_maneuver(_doublet(false), REFERENCE_HZ, true)
	var old_cndr_stats := _trace_stats(old_cndr.trace, rudder_throw_deg)
	_check("restoring the audited borrowed Cndr makes the reference test reject the old authority",
		old_cndr.fault.is_empty() and old_cndr_stats.finite and
		(old_cndr_stats.beta_peak_deg > BETA_LIMIT_DEG or old_cndr_stats.r_peak_deg_s > YAW_RATE_LIMIT_DEG_S),
		"legacy Cndr %.5f; %s" % [AUDITED_BORROWED_CNDR, _stats_detail(old_cndr_stats)])

	# The mirrored reference doublet uses the same provisional limits; longer/stronger inputs below do not.
	var left_first := _run_maneuver(_doublet(true), REFERENCE_HZ)
	var left_stats := _check_run_integrity("left-first reverse doublet", left_first, expected_reference_rows, rudder_throw_deg)
	_check("left-first doublet produces left then right yaw response",
		left_stats.rudder_left_delta_deg < -20.0 and left_stats.rudder_right_delta_deg > 20.0
		and left_stats.first_phase_yaw_min_deg_s < 0.0 and left_stats.second_phase_yaw_max_deg_s > 0.0,
		"δr left %.2f°, right %.2f°; phase r %.2f°/s then %.2f°/s" % [left_stats.rudder_left_delta_deg,
			left_stats.rudder_right_delta_deg, left_stats.first_phase_yaw_min_deg_s, left_stats.second_phase_yaw_max_deg_s])

	_check("mirrored reference doublet respects the same authority/recovery screens",
		left_stats.beta_peak_deg <= BETA_LIMIT_DEG and left_stats.r_peak_deg_s <= YAW_RATE_LIMIT_DEG_S
		and left_stats.has_r_at_3s and absf(left_stats.r_at_3s_deg_s) <= RELEASE_YAW_RATE_LIMIT_DEG_S, _stats_detail(left_stats))

	# Timestep comparison at the same 15 m/s reference maneuver; event times align exactly at both rates.
	var fine := _run_maneuver(_doublet(false), 2 * REFERENCE_HZ)
	var fine_stats := _check_run_integrity("reference doublet at 480 Hz", fine, roundi(3.0 * 2 * REFERENCE_HZ) + 1, rudder_throw_deg)
	var beta_dt_error: float = absf(fine_stats.beta_peak_deg - right_stats.beta_peak_deg)
	var yaw_dt_error: float = absf(fine_stats.r_peak_deg_s - right_stats.r_peak_deg_s)
	var final_yaw_dt_error: float = absf(fine_stats.r_final_deg_s - right_stats.r_final_deg_s)
	# Engineering numerical check only: halving dt keeps integrated peaks close and final-rate residual O(dt).
	_check("dt/2 converges: β peak ≤0.25°, r peak ≤1°/s, final r ≤0.5°/s apart",
		beta_dt_error <= 0.25 and yaw_dt_error <= 1.0 and final_yaw_dt_error <= 0.5,
		"Δβ %.3f°, Δrpk %.3f°/s, Δrfinal %.3f°/s; 240 Hz [%s]; 480 Hz [%s]" % [
			beta_dt_error, yaw_dt_error, final_yaw_dt_error, _stats_detail(right_stats), _stats_detail(fine_stats)])

	# Range samples intentionally cover distinct amplitudes, pulse lengths, directions and speeds. They check
	# trace continuity and finiteness only: the reference doublet limits do not apply to sustained/extreme inputs.
	var cases := []
	for pair in [[0.1, 0.1], [0.25, 0.25], [0.5, 0.5], [1.0, 2.0]]:
		for direction in [-1.0, 1.0]:
			cases.append({ speed = 15.0, amplitude = pair[0], duration = pair[1], direction = direction,
				mode = "level", kind = "sustained_2s" if pair[0] == 1.0 else "pulse" })
	for speed in [12.0, 20.0]:
		for direction in [-1.0, 1.0]:
			cases.append({ speed = speed, amplitude = 0.5, duration = 0.25, direction = direction, mode = "level", kind = "pulse" })
	for direction in [-1.0, 1.0]:
		cases.append({ speed = 15.0, amplitude = 0.5, duration = 0.5, direction = direction, mode = "glide", kind = "glide" })
	var sweep_beta_peak := 0.0
	var sweep_yaw_peak := 0.0
	var sweep_alpha_peak := 0.0
	var sweep_speed_min := INF
	var sweep_speed_max := -INF
	var sweep_rms_beta := 0.0
	var sweep_rms_yaw := 0.0
	var sweep_rows := 0
	var sweep_ok := true
	var sustained_hold_count := 0
	var sustained_holds_ok := true
	var glide_count := 0
	var glide_ok := true
	var glide_rpm_peak := 0.0
	for case in cases:
		var maneuver := _pulse_maneuver(case.speed, case.amplitude, case.duration, case.direction, case.mode)
		var run := _run_maneuver(maneuver, REFERENCE_HZ)
		var expected_rows := roundi(maneuver.duration * REFERENCE_HZ) + 1
		var stats := _trace_stats(run.trace, rudder_throw_deg)
		var case_ok: bool = run.fault.is_empty() and stats.finite and stats.continuous and run.trace.row_count() == expected_rows
		sweep_ok = sweep_ok and case_ok
		if case.kind == "sustained_2s":
			sustained_hold_count += 1
			sustained_holds_ok = sustained_holds_ok and case_ok
		if case.kind == "glide":
			glide_count += 1
			glide_ok = glide_ok and case_ok
			glide_rpm_peak = maxf(glide_rpm_peak, stats.engine_rpm_peak)
		sweep_beta_peak = maxf(sweep_beta_peak, stats.beta_peak_deg)
		sweep_yaw_peak = maxf(sweep_yaw_peak, stats.r_peak_deg_s)
		sweep_alpha_peak = maxf(sweep_alpha_peak, stats.alpha_peak_deg)
		sweep_speed_min = minf(sweep_speed_min, stats.speed_min_mps)
		sweep_speed_max = maxf(sweep_speed_max, stats.speed_max_mps)
		sweep_rms_beta += stats.rms_beta_deg * stats.rms_beta_deg * run.trace.row_count()
		sweep_rms_yaw += stats.rms_r_deg_s * stats.rms_r_deg_s * run.trace.row_count()
		sweep_rows += run.trace.row_count()
	var rms_beta := sqrt(sweep_rms_beta / maxf(1.0, float(sweep_rows)))
	var rms_yaw := sqrt(sweep_rms_yaw / maxf(1.0, float(sweep_rows)))
	_check("full rudder held for 2 s remains finite in both directions", sustained_holds_ok and sustained_hold_count == 2,
		"%d direction cases" % sustained_hold_count)
	_check("retrimming glide at 15 m/s with rudder pulses remains finite in both directions", glide_ok and glide_count == 2,
		"%d direction cases; engine rpm pk %.0f" % [glide_count, glide_rpm_peak])
	_check("amplitude/duration/speed sweep stays finite in both rudder directions", sweep_ok,
		"%d cases; βpk %.2f° RMS %.2f°, rpk %.2f°/s RMS %.2f°/s, αpk %.2f°, speed %.2f–%.2f m/s" % [
			cases.size(), sweep_beta_peak, rms_beta, sweep_yaw_peak, rms_yaw, sweep_alpha_peak, sweep_speed_min, sweep_speed_max])
	print("RUDDER_SWEEP finite-only: %d cases, βpk %.2f° RMS %.2f°, rpk %.2f°/s RMS %.2f°/s, αpk %.2f°, speed %.2f–%.2f m/s" % [
		cases.size(), sweep_beta_peak, rms_beta, sweep_yaw_peak, rms_yaw, sweep_alpha_peak, sweep_speed_min, sweep_speed_max])

	# Basic live input adapters are sampled through FlightSession's ordinary input and servo code. Limits above stay
	# specific to the reference doublet; these routes require only finite data and the expected yaw direction.
	var key_right := await _run_keyboard_case(KEY_D, 1.0, rudder_throw_deg)
	_check("injected keyboard D reaches right rudder and right yaw", key_right.fault.is_empty()
		and key_right.stats.finite and key_right.stats.rudder_right_delta_deg > 10.0 and key_right.stats.r_positive_deg_s > 0.0,
		_stats_detail(key_right.stats))
	var key_left := await _run_keyboard_case(KEY_A, -1.0, rudder_throw_deg)
	_check("injected keyboard A reaches left rudder and left yaw", key_left.fault.is_empty()
		and key_left.stats.finite and key_left.stats.rudder_left_delta_deg < -10.0 and key_left.stats.r_negative_deg_s < 0.0,
		_stats_detail(key_left.stats))
	_check("traces shorter than 3 s leave the 3 s recovery sample unavailable",
		not key_right.stats.has_r_at_3s and is_nan(key_right.stats.r_at_3s_deg_s)
		and not key_left.stats.has_r_at_3s and is_nan(key_left.stats.r_at_3s_deg_s),
		"keyboard trace duration 0.75 s; r@3s remains unavailable")
	var radio_right := await _run_device_case(DEVICE_ID, false, 1.0, rudder_throw_deg)
	_check("simulated radio path reaches right rudder with finite flight data", radio_right.fault.is_empty()
		and radio_right.stats.finite and radio_right.stats.rudder_right_delta_deg > 10.0 and radio_right.stats.r_positive_deg_s > 0.0,
		_stats_detail(radio_right.stats))
	var gamepad_left := await _run_device_case(DEVICE_ID + 1, true, -1.0, rudder_throw_deg)
	_check("simulated gamepad path reaches left rudder with finite flight data", gamepad_left.fault.is_empty()
		and gamepad_left.stats.finite and gamepad_left.stats.rudder_left_delta_deg < -5.0 and gamepad_left.stats.r_negative_deg_s < 0.0,
		_stats_detail(gamepad_left.stats))

	Engine.physics_ticks_per_second = saved_hz
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _run_keyboard_case(code: Key, direction: float, throw_deg: float) -> Dictionary:
	var session := _new_session()
	await process_frame # run FlightSession._ready and connect the real input callbacks
	session.input_enabled = true
	session.radio.disconnect_device()
	session.reset()
	session.sim.stop_at_tick = 0 # use manual ticks while still calling the real session input sampler
	var recorder := Recorder.new(session.sim)
	recorder.start({ route = "keyboard InputEventKey", direction = direction })
	_key(code, true)
	_manual_ticks(session, 120) # 0.5 s through the keyboard limiter and actual servo path
	_key(code, false)
	_manual_ticks(session, 60)
	recorder.detach()
	var trace: RefCounted = recorder.trace
	var stats := _trace_stats(trace, throw_deg)
	var fault := _fault_reason(session.sim)
	session.free()
	return { trace = trace, stats = stats, fault = fault }


func _run_device_case(device_id: int, gamepad: bool, direction: float, throw_deg: float) -> Dictionary:
	var session := _new_session()
	var axes := PackedFloat64Array()
	axes.resize(10)
	session.input_enabled = true
	session.profiles_path = "user://test_rudder_authority_device_%d.cfg" % device_id
	session.device_info = func(_device: int) -> Dictionary:
		return { guid = "rudder-authority", name = "Test Gamepad" if gamepad else "Fake EdgeTX",
			vendor_id = 0x1234, product_id = device_id, known = gamepad }
	session.read_axis = func(_device: int, axis: int) -> float:
		return axes[axis]
	await process_frame # let FlightSession connect its real device/input signals
	session.radio.disconnect_device()
	session.reset()
	session.sim.stop_at_tick = 0
	Input.joy_connection_changed.emit(device_id, true)
	session.resume() # device connection intentionally enters the ordinary failsafe pause
	var yaw_axis := 0 if gamepad else 3
	if not gamepad:
		axes[2] = -1.0 # radio throttle low: arm using its real safety rule
		_joy_motion(device_id, 2, -1.0)
		_manual_ticks(session, 2)
	var yaw_position := direction * (0.8 if gamepad else 1.0)
	axes[yaw_axis] = yaw_position
	_joy_motion(device_id, yaw_axis, yaw_position)
	var recorder := Recorder.new(session.sim)
	recorder.start({ route = "simulated gamepad" if gamepad else "simulated radio", direction = direction })
	_manual_ticks(session, 120)
	axes[yaw_axis] = 0.0
	_joy_motion(device_id, yaw_axis, 0.0)
	_manual_ticks(session, 60)
	recorder.detach()
	Input.joy_connection_changed.emit(device_id, false)
	var trace: RefCounted = recorder.trace
	var stats := _trace_stats(trace, throw_deg)
	var fault := _fault_reason(session.sim)
	session.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_rudder_authority_device_%d.cfg" % device_id))
	return { trace = trace, stats = stats, fault = fault }

extends SceneTree

const SOURCE_PATH := "res://physics/ground_vehicle/vehicle_dynamics.gd"
const Data := preload("res://physics/ground_vehicle/vehicle_data.gd")
const M := preload("res://physics/math3d.gd")
const DRIVE := {"throttle": 1.0, "steering": 0.0, "brake": 0.0, "reverse": false}
const BRAKE := {"throttle": 0.0, "steering": 0.0, "brake": 1.0, "reverse": false}

func _initialize() -> void:
	_run.call_deferred()

func _road(_n: float, _e: float) -> Dictionary:
	return {"height_m": 0.0, "normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]),
		"mu": 0.85, "rolling": 1.0, "surface_id": "brake_audit_flat"}

func _run() -> void:
	var loaded: Dictionary = Data.load_default()
	if not bool(loaded.get("ok", false)):
		print("LOAD_FAIL ", JSON.stringify(loaded))
		quit(1)
		return
	var base: Dictionary = loaded.model
	var kernels := {}
	# Historical cap probe: changing this source constant does not affect step()
	# when _evaluate_active selects the native backend. No reference override was
	# set for the recorded run, so the nominal 24-sweep trace is not convergence
	# evidence. Keep the caveat visible if rerunning this driver.
	for sweeps in [6, 24]:
		var script := GDScript.new()
		script.source_code = FileAccess.get_file_as_string(SOURCE_PATH).replace(
			"const FRICTION_SWEEPS := 6", "const FRICTION_SWEEPS := %d" % sweeps)
		if script.reload() != OK:
			print("KERNEL_FAIL sweeps=", sweeps)
			quit(1)
			return
		kernels[sweeps] = script
		print("SWEEP_CAP_PROBE ", JSON.stringify(_cap_execution(script, sweeps)))
	for hz in [240, 480]:
		var dt := 1.0 / float(hz)
		var initial := _accelerate(kernels[6], base, dt)
		if initial.is_empty():
			print("ACCEL_FAIL hz=", hz)
			quit(1)
			return
		for brake_nm in [1.2, 1.5]:
			var trial: Dictionary = base.duplicate(true)
			trial.brake_torque_per_wheel_nm = brake_nm
			for sweeps in [6, 24]:
				_run_case(hz, dt, brake_nm, sweeps, kernels[sweeps], trial, initial)
	print("PARTIAL_CONVERGENCE complete")
	quit(0)

func _accelerate(kernel: GDScript, model: Dictionary, dt: float) -> PackedFloat64Array:
	var initialized: Dictionary = kernel.call("initialize", model, _road, 0.0, 0.0)
	if not bool(initialized.get("ok", false)):
		return PackedFloat64Array()
	var state: PackedFloat64Array = initialized.state
	for _tick in int(round(6.0 / dt)):
		state = kernel.call("step", state, model, DRIVE, dt, _road)
		if state.size() != 31:
			return PackedFloat64Array()
	return state

func _run_case(hz: int, dt: float, brake_nm: float, sweeps: int, kernel: GDScript,
		model: Dictionary, initial: PackedFloat64Array) -> void:
	var state := initial.duplicate()
	var max_yaw := absf(_yaw(state))
	var min_upright := _upright(state)
	var max_abs_v := absf(state[4])
	var u_flip := -1.0
	var stop_time := -1.0
	var stop_distance := 0.0
	var elapsed := 0
	for tick in int(round(2.5 / dt)):
		elapsed = tick + 1
		state = kernel.call("step", state, model, BRAKE, dt, _road)
		if state.size() != 31:
			print("STEP_FAIL hz=", hz, " brake=", brake_nm, " requested_gdscript_sweep_cap=", sweeps)
			return
		var yaw := _yaw(state)
		var speed := M.sqrt_(state[3] * state[3] + state[4] * state[4] + state[5] * state[5])
		max_yaw = maxf(max_yaw, absf(yaw))
		min_upright = minf(min_upright, _upright(state))
		max_abs_v = maxf(max_abs_v, absf(state[4]))
		if u_flip < 0.0 and state[3] < -0.02:
			u_flip = elapsed * dt
		if stop_time < 0.0 and speed < 0.1:
			stop_time = elapsed * dt
			stop_distance = state[0] - initial[0]
		if elapsed in [24, 96, 192, 288]:
			var eval: Dictionary = kernel.call("_evaluate", state, model, BRAKE, _road, false, true)
			var sample := {"hz": hz, "brake_nm": brake_nm,
				"t": elapsed * dt, "u": state[3], "v": state[4],
				"yaw": yaw, "yaw_rate": state[12], "wheel_load": eval.wheel_load_n,
				"long_force": eval.wheel_longitudinal_force_n,
				"lat_force": eval.wheel_lateral_force_n,
				"brake_torque": eval.wheel_brake_torque_n_m,
				"slip_angle": eval.wheel_slip_angle_rad,
				"reference_diagnostic_sweeps_used": eval.friction_sweeps_used}
			sample.merge(_cap_execution(kernel, sweeps))
			print("PARTIAL_SAMPLE ", JSON.stringify(sample))
		if stop_time >= 0.0 and elapsed * dt > stop_time + 0.2:
			break
	var final_speed := M.sqrt_(state[3] * state[3] + state[4] * state[4] + state[5] * state[5])
	var summary := {"hz": hz, "brake_nm": brake_nm,
		"u_start": initial[3], "v_start": initial[4], "yaw_start": _yaw(initial),
		"u_end": state[3], "v_end": state[4], "yaw_end": _yaw(state), "speed_end": final_speed,
		"max_abs_yaw": max_yaw, "max_abs_v": max_abs_v, "min_upright": min_upright,
		"u_flip_s": u_flip, "stop_s": stop_time, "stop_distance_m": stop_distance,
		"elapsed_s": elapsed * dt}
	summary.merge(_cap_execution(kernel, sweeps))
	print("PARTIAL_SUMMARY ", JSON.stringify(summary))

func _cap_execution(kernel: GDScript, requested_cap: int) -> Dictionary:
	var identity: Dictionary = kernel.call("backend_identity")
	var backend := str(identity.get("backend", "unknown"))
	var reference_backend := backend == "gdscript_reference"
	return {
		"requested_gdscript_sweep_cap": requested_cap,
		"actual_backend": backend,
		"requested_gdscript_cap_is_active": reference_backend,
		"cap_comparison_valid_for_sweep_convergence": reference_backend,
		"effective_cap": requested_cap if reference_backend else "native compiled cap; GDScript source edit is ineffective",
	}

func _yaw(state: PackedFloat64Array) -> float:
	var q := PackedFloat64Array([state[6], state[7], state[8], state[9]])
	var forward := M.q_rotate(q, PackedFloat64Array([1.0, 0.0, 0.0]))
	return M.atan2_(forward[1], forward[0])

func _upright(state: PackedFloat64Array) -> float:
	var q := PackedFloat64Array([state[6], state[7], state[8], state[9]])
	return -M.q_rotate(q, PackedFloat64Array([0.0, 0.0, -1.0]))[2]

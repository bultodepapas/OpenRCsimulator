extends SceneTree

const SOURCE_PATH := "res://physics/ground_vehicle/vehicle_dynamics.gd"
const Data := preload("res://physics/ground_vehicle/vehicle_data.gd")
const M := preload("res://physics/math3d.gd")
const DRIVE := {"throttle": 1.0, "steering": 0.0, "brake": 0.0, "reverse": false}

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
	print("MODEL ", JSON.stringify({"corner_x": base.corner_x_m, "corner_y": base.corner_y_m,
		"brake_nm": base.brake_torque_per_wheel_nm, "drive_nm": base.drive_torque_per_wheel_nm,
		"fade_rad_s": base.drive_torque_fade_rad_s, "relaxation_s": base.tire_slip_relaxation_s,
		"tire_mu_scale": base.tire_friction_scale}))
	var kernels := {}
	# This does not force the reference backend. The report below identifies the
	# selected backend and flags when the source-level cap request is ineffective.
	for sweep_count in [6, 24]:
		var source := FileAccess.get_file_as_string(SOURCE_PATH)
		var script := GDScript.new()
		script.source_code = source.replace("const FRICTION_SWEEPS := 6", "const FRICTION_SWEEPS := %d" % sweep_count)
		var error := script.reload()
		if error != OK:
			print("KERNEL_FAIL sweeps=", sweep_count, " error=", error)
			quit(1)
			return
		kernels[sweep_count] = script
		print("SWEEP_CAP_PROBE ", JSON.stringify(_cap_execution(script, sweep_count)))
	for hz in [240, 480]:
		var dt := 1.0 / float(hz)
		var kernel: GDScript = kernels[6]
		var initial := _accelerate(kernel, base, dt)
		if initial.is_empty():
			print("ACCEL_FAIL hz=", hz)
			quit(1)
			return
		var start_eval: Dictionary = kernel.call("_evaluate", initial, base, DRIVE, _road, false, true)
		print("START ", JSON.stringify({"hz": hz, "yaw": _yaw(initial), "yaw_rate": initial[12],
			"u": initial[3], "v": initial[4], "upright": _upright(initial),
			"wheel_load": start_eval.get("wheel_load_n", PackedFloat64Array()),
			"lat_force": start_eval.get("wheel_lateral_force_n", PackedFloat64Array()),
			"slip_angle": start_eval.get("wheel_slip_angle_rad", PackedFloat64Array()),
			"sweeps": start_eval.get("friction_sweeps_used", -1)}))
		_run_brake("step", hz, dt, base, kernel, initial, 0.2, false, 6)
		_run_brake("ramp200ms", hz, dt, base, kernel, initial, 0.2, true, 6)
		if hz == 240:
			_run_brake("step", hz, dt, base, kernels[24], initial, 0.2, false, 24)
	print("CONVERGENCE_POLICY complete")
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

func _run_brake(policy: String, hz: int, dt: float, model: Dictionary, kernel: GDScript,
		initial: PackedFloat64Array, ramp_s: float, ramp: bool, requested_cap: int) -> void:
	var state := initial.duplicate()
	var max_yaw := absf(_yaw(state))
	var min_upright := _upright(state)
	var max_lateral_speed := absf(state[4])
	var start_yaw := _yaw(state)
	var u_flip := -1.0
	var stop_time := -1.0
	var stop_n := 0.0
	var stop_e := 0.0
	var stop_speed := 0.0
	var max_ticks := int(round(2.5 / dt))
	var controls := {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false}
	var stride := maxi(1, int(round(0.2 / dt)))
	var elapsed_ticks := 0
	for tick in max_ticks:
		elapsed_ticks = tick + 1
		controls.brake = clampf((tick + 1) * dt / ramp_s, 0.0, 1.0) if ramp else 1.0
		state = kernel.call("step", state, model, controls, dt, _road)
		if state.size() != 31:
			print("STEP_FAIL policy=", policy, " hz=", hz)
			return
		var yaw := _yaw(state)
		var speed := M.sqrt_(state[3] * state[3] + state[4] * state[4] + state[5] * state[5])
		max_yaw = maxf(max_yaw, absf(yaw))
		min_upright = minf(min_upright, _upright(state))
		max_lateral_speed = maxf(max_lateral_speed, absf(state[4]))
		if u_flip < 0.0 and state[3] < -0.02:
			u_flip = (tick + 1) * dt
		if stop_time < 0.0 and speed < 0.1:
			stop_time = (tick + 1) * dt
			stop_n = state[0] - initial[0]
			stop_e = state[1] - initial[1]
			stop_speed = speed
		if (tick + 1) % stride == 0:
			print("BRAKE_SAMPLE ", JSON.stringify({"policy": policy, "hz": hz, "t": (tick + 1) * dt,
				"brake": controls.brake, "u": state[3], "v": state[4], "r": state[12], "yaw": yaw,
				"speed": speed, "upright": _upright(state), "n": state[0] - initial[0], "e": state[1] - initial[1]}))
		if stop_time >= 0.0 and (tick + 1) * dt > stop_time + 0.2:
			break
	var final_speed := M.sqrt_(state[3] * state[3] + state[4] * state[4] + state[5] * state[5])
	var summary := {"policy": policy, "hz": hz,
		"start_yaw": start_yaw, "end_yaw": _yaw(state), "max_abs_yaw": max_yaw,
		"max_lateral_speed": max_lateral_speed, "min_upright": min_upright,
		"u_flip_s": u_flip, "stop_s": stop_time, "stop_n_m": stop_n, "stop_e_m": stop_e,
		"stop_speed": stop_speed, "end_speed": final_speed, "elapsed_s": elapsed_ticks * dt}
	summary.merge(_cap_execution(kernel, requested_cap))
	print("BRAKE_SUMMARY ", JSON.stringify(summary))

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

# EX-08a: deterministic Extra 300S ground and runway probe. Predictions only; no physical acceptance is implied.
# Run: godot --headless --path app --script "$PWD/research/extra-300/ex06/ground_probe.gd" -- --hz=240 --output=/tmp/extra-ground.json
extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const GroundStart := preload("res://physics/ground_start.gd")
const Ground := preload("res://physics/ground_contact.gd")
const GroundWheels := preload("res://physics/ground_wheels.gd")
const GroundTerrain := preload("res://physics/ground_terrain.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Commands := preload("res://input/commands.gd")

const AIRCRAFT_PATH := "res://data/aircraft/gp_extra_300s_60.json"
const AIRCRAFT_ID := "gp-extra-300s-60"
const AUX_RPM := 0
const AUX_SERVO := 1
const G := 9.80665
const TAKEOFF_MAX_S := 25.0
const LIFTOFF_DEBOUNCE_S := 0.08
const LIFTOFF_OBSERVE_S := 0.75
const TOUCHDOWN_ROLLOUT_S := 4.0
const REST_CONSTRAINED_ACCEL_GUARD := 1e-6

var _hz := 240
var _output_path := ""
var _session: Node
var _model: Dictionary
var _field: Dictionary
var _runway := {}
var _rest_state := PackedFloat64Array()
var _rest_setup := {}
var _report := {}
var _failures := PackedStringArray()


func _initialize() -> void:
	if not _parse_args():
		quit(2)
		return
	ProjectSettings.set_setting("physics/common/physics_ticks_per_second", _hz)
	Engine.physics_ticks_per_second = _hz
	_session = FlightSession.new()
	_session.physics_enabled = false
	_session.setup(AIRCRAFT_PATH, AIRCRAFT_ID)
	root.add_child(_session)
	_session.physics_enabled = true
	_session.input_enabled = false # deterministic, device-free pilot commands below
	_session.crash_auto_restart = false
	_session.sim.set_paused(true)
	if not _session.aircraft.get("ok", false) or not _session.start.get("ok", false):
		_failures.append("Extra aircraft data or initial trim did not load: %s" % str(_session.start.get("message", "aircraft data invalid")))
		_finish()
		return
	_model = _session.aircraft.model
	var loaded_field: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	_field = loaded_field.get("field", loaded_field)
	if not _session.set_field(_field):
		_failures.append("default field surfaces refused: %s" % _session.surface_error)
		_finish()
		return
	if _session.wheel_count() != 3 or _session.anchor_count() != 0 or _model.get("wheel_profile", {}).get("status", "") != "applied":
		_failures.append("the applied Extra wheel profile, three continuous wheel states, and zero session anchors are required")
		_finish()
		return
	_runway = GroundStart.threshold(_field)
	if not _runway.get("ok", false):
		_failures.append("default field has no usable runway: %s" % str(_runway.get("message", "unknown")))
		_finish()
		return
	_initialize_aux_for_rest()
	var solved: Dictionary = _solve_engine_off_rest_pose()
	if not solved.get("ok", false):
		_failures.append("engine-off ground rest pose failed: %s" % str(solved.get("message", "unknown")))
		_finish()
		return
	_rest_state = solved.rest_state.duplicate()
	var solved_contacts: Dictionary = _contacts(_rest_state)
	var solved_attitude: PackedFloat64Array = _euler(_rest_state)
	var solved_height_m: float = -_rest_state[RB.POS + 2]
	if int(solved_contacts.count) != 3:
		_failures.append("engine-off ground rest pose must start on all three gear contacts; got %s" % str(solved_contacts.names))
		_finish()
		return
	if solved_height_m <= 0.0 or absf(rad_to_deg(solved_attitude[1])) >= 30.0 or absf(rad_to_deg(solved_attitude[2])) >= 30.0:
		_failures.append("engine-off rest pose failed sanity bounds (CG height %.3f m, pitch %.2f deg, roll %.2f deg)" %
			[solved_height_m, rad_to_deg(solved_attitude[1]), rad_to_deg(solved_attitude[2])])
		_finish()
		return
	var rest_install: Dictionary = _install_start(_rest_state, false)
	if not rest_install.get("ok", false):
		_failures.append("unmodified session rejected the solved rest pose: %s" % str(rest_install.get("message", "unknown")))
		_finish()
		return
	var actual_linear_residual: float = float(rest_install.translation_accel_max_mps2)
	var actual_angular_residual: float = float(rest_install.angular_accel_max_radps2)
	var constrained_residual: float = maxf(absf(float(rest_install.translation_accel_world_mps2[2])),
		maxf(absf(float(rest_install.angular_accel_world_radps2[0])), absf(float(rest_install.angular_accel_world_radps2[1]))))
	_rest_setup = {
		"rest_pose_method": "GroundStart Stage 1 engine-off 3-DOF Newton solve on the unmodified model with no anchors; no stiction clone, anchor creation, or idle stage",
		"solver_model": "loaded Extra model, unmodified",
		"engine_rpm": 0.0,
		"geometry_initial_pitch_guess_deg": float(solved.initial_pitch_guess_deg),
		"geometry_initial_down_guess_m": float(solved.initial_down_guess_m),
		"solved_cg_height_above_ned_datum_m": solved_height_m,
		"solved_pitch_deg": rad_to_deg(solved_attitude[1]),
		"solved_roll_deg": rad_to_deg(solved_attitude[2]),
		"solved_contact_names": solved_contacts.names,
		"ground_start_max_abs_equilibrium_residual_mixed_mps2_radps2": float(solved.residual),
		"ground_start_solver_iterations": int(solved.iterations),
		"ground_start_body_linear_acceleration_mps2": solved.solver_body_linear_acceleration_mps2,
		"ground_start_body_angular_acceleration_radps2": solved.solver_body_angular_acceleration_radps2,
		"ground_start_world_linear_acceleration_mps2": solved.solver_world_linear_acceleration_mps2,
		"ground_start_world_angular_acceleration_radps2": solved.solver_world_angular_acceleration_radps2,
		"ground_start_solver_loads_body_N_Nm": solved.solver_loads_body_N_Nm,
		"session_initial_wind_ned_mps": Array(_session.wind_at(0.0)),
		"ground_start_initial_wind_ned_mps": Array(_session._initial_wind()),
		"session_downwash_index": _session.downwash_index(),
		"session_downwash_cl": float(_session.sim.aux[_session.downwash_index()]) if _session.downwash_index() >= 0 else null,
		"actual_session_reset_ok": true,
		"actual_session_translation_accel_max_mps2": actual_linear_residual,
		"actual_session_angular_accel_max_radps2": actual_angular_residual,
		"actual_session_body_linear_acceleration_mps2": rest_install.translation_accel_body_mps2,
		"actual_session_body_angular_acceleration_radps2": rest_install.angular_accel_body_radps2,
		"actual_session_world_linear_acceleration_mps2": rest_install.translation_accel_world_mps2,
		"actual_session_world_angular_acceleration_radps2": rest_install.angular_accel_world_radps2,
		"actual_session_unconstrained_horizontal_acceleration_world_mps2": [rest_install.translation_accel_world_mps2[0], rest_install.translation_accel_world_mps2[1]],
		"actual_session_unconstrained_yaw_acceleration_world_radps2": rest_install.angular_accel_world_radps2[2],
		"actual_session_constrained_component_max_mps2_radps2": constrained_residual,
		"actual_session_constrained_component_guard": REST_CONSTRAINED_ACCEL_GUARD,
		"actual_session_rest_loads_body_N_Nm": Array(_session.sim.last_loads),
		"actual_minus_ground_start_loads_body_N_Nm": _subtract_vectors(_session.sim.last_loads, solved.solver_loads_body_N_Nm),
		"actual_session_contact_terrain": _terrain_contact_report(_rest_state),
		"actual_session_continuous_size": _session.sim.continuous.size(),
		"wheel_index_in_continuous": _session.wheel_index(),
		"wheel_count": _session.wheel_count(),
		"session_anchor_count": _session.anchor_count(),
		"session_wheel_speeds_mps": _wheel_speeds(_session.sim.continuous),
	}
	_report = {
		"format": "openrc-extra-ground-probe v1",
		"evidence_kind": "simulator prediction; not physical validation",
		"physical_validation": false,
		"tick_rate_hz": Engine.physics_ticks_per_second,
		"ground_rest_setup": _rest_setup,
	}
	if constrained_residual > REST_CONSTRAINED_ACCEL_GUARD:
		_failures.append("unmodified FlightSession vertical/roll/pitch rest residual exceeds fixture guard (%s m/s^2 or rad/s^2)" %
			String.num_scientific(constrained_residual))
		_finish()
		return
	if not _array_finite(_session.sim.continuous) or not _array_finite(_session.sim.aux):
		_failures.append("rest reset created nonfinite auxiliary or continuous state")
		_finish()
		return
	_run_cases()
	_finish()


func _parse_args() -> bool:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var arg := args[i]
		if arg.begins_with("--hz="):
			_hz = arg.trim_prefix("--hz=").to_int()
		elif arg == "--hz" and i + 1 < args.size():
			i += 1
			_hz = args[i].to_int()
		elif arg.begins_with("--output="):
			_output_path = arg.trim_prefix("--output=")
		elif arg == "--output" and i + 1 < args.size():
			i += 1
			_output_path = args[i]
		else:
			printerr("ground_probe: unknown or incomplete argument '%s'" % arg)
			return false
		i += 1
	if _hz not in [240, 480]:
		printerr("ground_probe: --hz must be 240 or 480")
		return false
	return true


## This probe needs a quiet initial pose, but the Extra has no production stiction/anchor model and its free wheels
## must not be made to touch by injecting fake brakes. Reuse only GroundStart's engine-off Stage 1 force path and
## solve its vertical acceleration plus two horizontal-axis angular accelerations on the real, unmodified model.
func _solve_engine_off_rest_pose() -> Dictionary:
	var gear: Dictionary = _model.landing_gear
	var main_position := PackedFloat64Array()
	var tail_position := PackedFloat64Array()
	for contact: Dictionary in gear.contacts:
		var name: String = str(contact.name)
		if name == "main_left":
			main_position = contact.position
		elif name == "tail":
			tail_position = contact.position
	if main_position.size() != 3 or tail_position.size() != 3:
		return { ok = false, message = "loaded gear is missing main_left or tail contact geometry" }
	# Match the three-point taildragger fixture shape from the generic ground-probe pattern, using this model's own
	# body-FRD points. The generated JSON points are in the LE frame and are not suitable here.
	var pitch_guess: float = atan2(float(main_position[2] - tail_position[2]), float(main_position[0] - tail_position[0]))
	var down_guess: float = -(-main_position[0] * sin(pitch_guess) + main_position[2] * cos(pitch_guess)) + float(gear.static_sag)
	var free_anchors := PackedFloat64Array() # empty means no stiction/anchor forces in Ground.loads
	var pose := PackedFloat64Array([
		float(_runway.north), float(_runway.east), down_guess, 0.0, pitch_guess, float(_runway.heading),
	])
	var inv: PackedFloat64Array = RB.inertia_inverse(_model.inertia)
	var surfaces: PackedFloat64Array = _session.ground_surfaces
	var deflections: Dictionary = _session._deflections(_session.sim.aux)
	var steer: float = float(_session.sim.aux[AUX_SERVO + 2])
	var density: float = _session.air_density()
	var gravity: float = _session.sim.gravity
	var wind: PackedFloat64Array = _session._initial_wind()
	var rest_residual := func(x: PackedFloat64Array) -> PackedFloat64Array:
		var p := PackedFloat64Array([float(_runway.north), float(_runway.east), x[0], x[1], x[2], float(_runway.heading)])
		var a: PackedFloat64Array = GroundStart._accelerations(GroundStart._state(p), _model, inv, gear, surfaces,
			deflections, steer, 0.0, density, gravity, free_anchors, false, wind, true)
		var q: PackedFloat64Array = GroundStart._quat(p)
		var linear_world: PackedFloat64Array = M.q_rotate(q, M.v3(a[0], a[1], a[2]))
		var angular_world: PackedFloat64Array = M.q_rotate(q, M.v3(a[3], a[4], a[5]))
		return PackedFloat64Array([linear_world[2], angular_world[0], angular_world[1]])
	var solved: Dictionary = GroundStart._newton(rest_residual, PackedFloat64Array([pose[2], pose[3], pose[4]]))
	if not solved.get("ok", false):
		return { ok = false, message = "Newton failed (mixed acceleration residual %s)" % String.num_scientific(float(solved.get("residual", INF))) }
	pose[2] = solved.x[0]
	pose[3] = solved.x[1]
	pose[4] = solved.x[2]
	var rest_state: PackedFloat64Array = GroundStart._state(pose)
	var solver_accelerations: PackedFloat64Array = GroundStart._accelerations(rest_state, _model, inv, gear, surfaces,
		deflections, steer, 0.0, density, gravity, free_anchors, false, wind, true)
	var solver_q: PackedFloat64Array = GroundStart._quat(pose)
	var solver_world_linear: PackedFloat64Array = M.q_rotate(solver_q, M.v3(solver_accelerations[0], solver_accelerations[1], solver_accelerations[2]))
	var solver_world_angular: PackedFloat64Array = M.q_rotate(solver_q, M.v3(solver_accelerations[3], solver_accelerations[4], solver_accelerations[5]))
	var solver_loads := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	if wind[0] != 0.0 or wind[1] != 0.0 or wind[2] != 0.0:
		solver_loads = Dynamics.loads(rest_state, _model, deflections, 0.0, density, wind)
	var solver_wheels := PackedFloat64Array()
	solver_wheels.resize(gear.contacts.size())
	var solver_ground_loads: PackedFloat64Array = Ground.loads(rest_state, gear, steer, surfaces, free_anchors, solver_wheels)
	for axis in solver_ground_loads.size():
		solver_loads[axis] += solver_ground_loads[axis]
	return { ok = true, rest_state = rest_state, residual = solved.residual, iterations = solved.iterations,
		solver_body_linear_acceleration_mps2 = solver_accelerations.slice(0, 3),
		solver_body_angular_acceleration_radps2 = solver_accelerations.slice(3, 6),
		solver_world_linear_acceleration_mps2 = solver_world_linear,
		solver_world_angular_acceleration_radps2 = solver_world_angular,
		solver_loads_body_N_Nm = solver_loads,
		initial_pitch_guess_deg = rad_to_deg(pitch_guess), initial_down_guess_m = down_guess }


## Align all reset-owned state while keeping the session's full aux layout and wheel-bearing continuous layout.
func _initialize_aux_for_rest() -> void:
	_session.engine_running = false
	_session.commands = Commands.neutral_commands()
	_session.commands.throttle = 0.0
	_session.sim.inputs = _session._inputs()
	var aux: PackedFloat64Array = _session.sim.aux.duplicate()
	aux[AUX_RPM] = 0.0
	for axis in 3:
		aux[AUX_SERVO + axis] = _session.sim.inputs[axis]
	var downwash: int = _session.downwash_index()
	if downwash >= 0:
		aux[downwash] = _session._wing_cl(_session.sim.state, aux, 0.0)
	_session.sim.aux = aux
	return


func _install_start(state: PackedFloat64Array, engine_on: bool) -> Dictionary:
	_session.sim.set_paused(true)
	_session.crash = {}
	_session.pause_reason = ""
	_session.commands = Commands.neutral_commands()
	_session.commands.throttle = 0.0
	_session.engine_running = engine_on
	_session.sim.inputs = _session._inputs()
	var aux: PackedFloat64Array = _session.sim.aux.duplicate()
	aux[AUX_RPM] = Propulsion.steady_rpm(0.0, 0.0, _model.propulsion, _session.air_density(), _session.engine_charge_ratio()) if engine_on else 0.0
	for axis in 3:
		aux[AUX_SERVO + axis] = _session.sim.inputs[axis]
	var downwash: int = _session.downwash_index()
	if downwash >= 0:
		aux[downwash] = _session._wing_cl(state, aux, 0.0)
	_session.sim.aux = aux
	# The session helper builds wash/shaft/battery/wheel state in its live layout; it initializes every wheel rim slot
	# to rest while preserving the index order (wash and any shaft states before wheel_index()).
	_session.sim.continuous = _session._settled_continuous(state, aux)
	_session.sim.stop_at_tick = -1
	if not _session.sim.reset(state):
		return { ok = false, message = _session.sim.fault_reason }
	var derivative: PackedFloat64Array = RB.derivative(state, float(_model.mass_kg), _model.inertia,
		RB.inertia_inverse(_model.inertia), M.v3(_session.sim.last_loads[0], _session.sim.last_loads[1], _session.sim.last_loads[2]),
		M.v3(_session.sim.last_loads[3], _session.sim.last_loads[4], _session.sim.last_loads[5]), _session.sim.gravity,
		_session.rotor_momentum(_session.sim.aux))
	var linear_max := 0.0
	var angular_max := 0.0
	var linear_accel_body := PackedFloat64Array()
	var angular_accel_body := PackedFloat64Array()
	for axis in 3:
		linear_accel_body.append(derivative[RB.VEL + axis])
		angular_accel_body.append(derivative[RB.RATE + axis])
		linear_max = maxf(linear_max, absf(derivative[RB.VEL + axis]))
		angular_max = maxf(angular_max, absf(derivative[RB.RATE + axis]))
	var q: PackedFloat64Array = M.quat(state[RB.ATT], state[RB.ATT + 1], state[RB.ATT + 2], state[RB.ATT + 3])
	var linear_accel_world: PackedFloat64Array = M.q_rotate(q, M.v3(linear_accel_body[0], linear_accel_body[1], linear_accel_body[2]))
	var angular_accel_world: PackedFloat64Array = M.q_rotate(q, M.v3(angular_accel_body[0], angular_accel_body[1], angular_accel_body[2]))
	_session.sim.set_paused(false)
	return { ok = is_finite(linear_max) and is_finite(angular_max), translation_accel_max_mps2 = linear_max,
		angular_accel_max_radps2 = angular_max, derivative = derivative,
		translation_accel_body_mps2 = linear_accel_body, angular_accel_body_radps2 = angular_accel_body,
		translation_accel_world_mps2 = linear_accel_world, angular_accel_world_radps2 = angular_accel_world }


func _run_cases() -> void:
	var dt: float = _session.sim.dt()
	var density: float = _session.air_density()
	var stall_estimate: float = sqrt(2.0 * float(_model.mass_kg) * _session.sim.gravity / (density * float(_model.reference.S) * float(_model.envelope.CL_max)))
	var idle_rpm: float = Propulsion.steady_rpm(0.0, 0.0, _model.propulsion, density, _session.engine_charge_ratio())
	var initial_trims: Dictionary = _session.trims.duplicate(true)
	_report = {
		"format": "openrc-extra-ground-probe v1",
		"evidence_kind": "simulator prediction; not physical validation",
		"physical_validation": false,
		"generated_utc": Time.get_datetime_string_from_system(true),
		"aircraft_id": AIRCRAFT_ID,
		"model_data_sha256": str(_model.get("data_sha256", "")),
		"tick_rate_hz": Engine.physics_ticks_per_second,
		"dt_s": dt,
		"air_density_kg_m3": density,
		"field_id": _field.get("id", ""),
		"runway_heading_rad": float(_runway.heading),
		"runway_start_north_m": float(_runway.north),
		"runway_start_east_m": float(_runway.east),
		"model_derived_1g_stall_estimate_mps": stall_estimate,
		"model_target_idle_rpm": idle_rpm,
		"stall_estimate_source": "EX-05 model CLmax and wing area; estimated aerodynamic input, not flight measurement",
		"wheel_profile": _wheel_profile_report(),
		"ground_rest_setup": _rest_setup,
		"cases": [],
		"scenario_settings": {
			"taxi_throttle_command": 0.12,
			"taxi_yaw_commands": [-0.65, 0.65],
			"takeoff_throttle_ramp_s": 1.5,
			"guided_rotation_gate_mps": 1.1 * stall_estimate,
			"guided_shallow_climb_attitude_deg": 7.0,
			"landing_approach_speed_mps": 1.25 * stall_estimate,
			"landing_path_angle_deg": 3.0,
			"landing_touchdown_target_east_m": 0.0,
			"controller_values_are_probe_settings": true,
		},
	}
	var pilot_neutral := func(t: float, _s: PackedFloat64Array) -> Dictionary:
		return { roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0 }
	var off := _run_case("parked-engine-off", false, 8.0, pilot_neutral)
	_append_case(off)
	var idle := _run_case("parked-engine-idle", true, 8.0, pilot_neutral)
	_append_case(idle)
	for direction in [-1.0, 1.0]:
		var yaw_command: float = direction * 0.65
		var taxi_pilot := func(t: float, _s: PackedFloat64Array) -> Dictionary:
			return { roll = 0.0, pitch = 0.0, yaw = yaw_command, throttle = 0.12 * minf(t / 1.0, 1.0) }
		var taxi_name := "taxi-left-rudder" if direction < 0.0 else "taxi-right-rudder"
		_append_case(_run_case(taxi_name, true, 6.0, taxi_pilot))
	var runway_heading: float = float(_runway.heading)
	var unguided := func(t: float, _s: PackedFloat64Array) -> Dictionary:
		return { roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = minf(t / 1.5, 1.0) }
	_append_case(_run_case("takeoff-unguided", true, TAKEOFF_MAX_S, unguided, runway_heading, stall_estimate, true))
	var guided := func(t: float, s: PackedFloat64Array) -> Dictionary:
		var yaw_error: float = wrapf(runway_heading - _euler(s)[0], -PI, PI)
		var yaw_command: float = clampf(3.0 * yaw_error - 0.8 * s[RB.RATE + 2], -1.0, 1.0)
		var pitch_command := 0.0
		if _speed(s) >= 1.1 * stall_estimate:
			pitch_command = _hold_pitch(s, deg_to_rad(7.0))
		return { roll = _hold_roll(s, 0.0), pitch = pitch_command, yaw = yaw_command, throttle = minf(t / 1.5, 1.0) }
	_append_case(_run_case("takeoff-feedback-guided", true, TAKEOFF_MAX_S, guided, runway_heading, stall_estimate, true))
	_session.trims = initial_trims.duplicate(true)
	_append_case(_run_approach(stall_estimate))


func _run_approach(stall_estimate: float) -> Dictionary:
	var approach: Dictionary = _session.trim_at(1.25 * stall_estimate, "level")
	if not approach.get("ok", false):
		return { "name": "approach-flare-touchdown", "setup_error": "trim refused: %s" % str(approach.get("message", "unknown")) }
	var state: PackedFloat64Array = approach.state.duplicate()
	var pitch_attitude: float = _euler(state)[1]
	var approach_heading := -PI / 2.0
	var path_angle := deg_to_rad(3.0)
	var height0: float = 145.0 * tan(path_angle)
	var desired_alpha: float = pitch_attitude + path_angle
	var desired_u: float = (1.25 * stall_estimate) / sqrt(1.0 + tan(desired_alpha) * tan(desired_alpha))
	state[RB.POS] = float(_runway.north)
	state[RB.POS + 1] = 145.0
	state[RB.POS + 2] = -height0
	state[RB.VEL] = desired_u
	state[RB.VEL + 1] = 0.0
	state[RB.VEL + 2] = desired_u * tan(desired_alpha)
	var attitude := M.q_from_euler(approach_heading, pitch_attitude, _euler(state)[2])
	for axis in 4:
		state[RB.ATT + axis] = attitude[axis]
	var target_speed: float = 1.25 * stall_estimate
	var pilot := func(_t: float, s: PackedFloat64Array) -> Dictionary:
		var euler := _euler(s)
		var yaw_error: float = wrapf(approach_heading - euler[0], -PI, PI)
		var yaw_command: float = clampf(3.0 * yaw_error - 0.8 * s[RB.RATE + 2], -1.0, 1.0)
		var speed := _speed(s)
		var height: float = -s[RB.POS + 2]
		var remaining: float = maxf(0.0, s[RB.POS + 1])
		var target_height: float = remaining * tan(path_angle)
		var climb_rate := -_world_down_speed(s)
		var desired_climb: float = -target_speed * tan(path_angle)
		var pitch_target := pitch_attitude + 0.04 * (speed - target_speed)
		var throttle := clampf(0.16 + 0.035 * (target_height - height) + 0.08 * (desired_climb - climb_rate), 0.06, 0.45)
		var pitch_command: float
		if height < 1.5:
			pitch_target = deg_to_rad(5.0) + 0.04 * (speed - target_speed)
			pitch_command = _hold_pitch(s, pitch_target)
			throttle = clampf(0.10 + 0.025 * (speed - target_speed), 0.05, 0.25)
		else:
			pitch_command = _hold_pitch(s, pitch_target)
		if int(_contacts(s).count) > 0:
			pitch_command = _hold_pitch(s, deg_to_rad(3.0))
			throttle = 0.0
		return { roll = _hold_roll(s, 0.0), pitch = pitch_command, yaw = yaw_command, throttle = throttle }
	var case: Dictionary = _run_case("approach-flare-touchdown", true, 24.0, pilot, approach_heading, stall_estimate, false, state, true, TOUCHDOWN_ROLLOUT_S)
	case["approach_target_speed_mps"] = target_speed
	case["approach_target_gamma_deg"] = -3.0
	case["approach_start_height_m"] = height0
	case["approach_start_east_m"] = 145.0
	case["touchdown_target_east_m"] = 0.0
	case["flare_trigger_height_m"] = 1.5
	case["flare_nose_attitude_target_deg"] = 5.0
	var metrics: Dictionary = case.get("metrics", {})
	case["flare_observed"] = float(metrics.get("minimum_ned_height_m", INF)) < 1.5
	case["flare_observation_definition"] = "minimum sampled CG height below NED datum is under the configured 1.5 m flare trigger"
	case["touchdown_time_s"] = float(metrics.get("touchdown_time_s", -1.0))
	case["touchdown_speed_mps"] = float(metrics.get("touchdown_speed_mps", 0.0))
	case["touchdown_sink_mps"] = float(metrics.get("touchdown_sink_mps", 0.0))
	return case


func _run_case(name: String, engine_on: bool, duration_s: float, pilot: Callable, heading: float = NAN,
		stall_estimate: float = 0.0, detect_liftoff := false, requested_state := PackedFloat64Array(),
		stop_on_touchdown := false, rollout_s := TOUCHDOWN_ROLLOUT_S) -> Dictionary:
	var state: PackedFloat64Array = _rest_state if requested_state.is_empty() else requested_state
	var installed: Dictionary = _install_start(state, engine_on)
	if not installed.get("ok", false):
		return { "name": name, "setup_error": str(installed.get("message", "session reset failed")) }
	var sim: Node = _session.sim
	var dt: float = sim.dt()
	var initial: PackedFloat64Array = sim.state.duplicate()
	var initial_rpm: float = float(sim.aux[AUX_RPM])
	var initial_contacts: Dictionary = _contacts(initial)
	var h0: float = float(_euler(initial)[0]) if is_nan(heading) else heading
	var previous_state: PackedFloat64Array = initial.duplicate()
	var previous_contacts: Dictionary = initial_contacts
	var path_m := 0.0
	var ground_path_m := 0.0
	var max_speed := _speed(initial)
	var max_rpm := initial_rpm
	var max_contact_count: int = int(initial_contacts.count)
	var max_heading_error := 0.0
	var max_lateral_m := 0.0
	var max_abs_yaw_command := 0.0
	var max_right_yaw_command := 0.0
	var min_left_yaw_command := 0.0
	var max_abs_yaw_servo := absf(float(sim.aux[AUX_SERVO + 2]))
	var tail_up_s := -1.0
	var liftoff_s := -1.0
	var liftoff_distance_m := 0.0
	var liftoff_speed_mps := 0.0
	var no_contact_since := -1.0
	var no_contact_position := initial.duplicate()
	var no_contact_speed := 0.0
	var touchdown_s := -1.0
	var touchdown_speed_mps := 0.0
	var touchdown_sink_mps := 0.0
	var minimum_ned_height_m: float = -initial[RB.POS + 2]
	var samples := 0
	var steps: int = roundi(duration_s / dt)
	for k in steps:
		var t: float = float(k) * dt
		var controls: Dictionary = pilot.call(t, sim.state)
		_session.commands = {
			"roll": clampf(float(controls.get("roll", 0.0)), -1.0, 1.0),
			"pitch": clampf(float(controls.get("pitch", 0.0)), -1.0, 1.0),
			"yaw": clampf(float(controls.get("yaw", 0.0)), -1.0, 1.0),
			"throttle": clampf(float(controls.get("throttle", 0.0)), 0.0, 1.0),
		}
		max_abs_yaw_command = maxf(max_abs_yaw_command, absf(float(_session.commands.yaw)))
		max_right_yaw_command = maxf(max_right_yaw_command, float(_session.commands.yaw))
		min_left_yaw_command = minf(min_left_yaw_command, float(_session.commands.yaw))
		sim.inputs = _session._inputs()
		_session._physics_process(dt) # real FlightSession crash/contact boundary, then its real fixed-step Simulation
		if not _session.crash.is_empty():
			break
		sim.step()
		if not sim.fault_reason.is_empty():
			break
		var current: PackedFloat64Array = sim.state
		minimum_ned_height_m = minf(minimum_ned_height_m, -current[RB.POS + 2])
		var current_contacts: Dictionary = _contacts(current)
		max_contact_count = maxi(max_contact_count, int(current_contacts.count))
		var segment := _position_distance(previous_state, current)
		path_m += segment
		if int(previous_contacts.count) > 0 or int(current_contacts.count) > 0:
			ground_path_m += segment
		var speed := _speed(current)
		max_speed = maxf(max_speed, speed)
		max_rpm = maxf(max_rpm, float(sim.aux[AUX_RPM]))
		max_abs_yaw_servo = maxf(max_abs_yaw_servo, absf(float(sim.aux[AUX_SERVO + 2])))
		var euler := _euler(current)
		max_heading_error = maxf(max_heading_error, absf(wrapf(euler[0] - h0, -PI, PI)))
		max_lateral_m = maxf(max_lateral_m, absf(_cross_track(initial, current, h0)))
		if tail_up_s < 0.0 and _tail_up(current_contacts):
			tail_up_s = float(k + 1) * dt
		if detect_liftoff:
			if int(current_contacts.count) == 0:
				if no_contact_since < 0.0:
					no_contact_since = float(k + 1) * dt
					no_contact_position = current.duplicate()
					no_contact_speed = speed
				elif liftoff_s < 0.0 and float(k + 1) * dt - no_contact_since >= LIFTOFF_DEBOUNCE_S:
					liftoff_s = no_contact_since
					liftoff_distance_m = _along_track(initial, no_contact_position, h0)
					liftoff_speed_mps = no_contact_speed
			elif int(current_contacts.count) > 0:
				no_contact_since = -1.0
		if stop_on_touchdown and touchdown_s < 0.0 and int(previous_contacts.count) == 0 and int(current_contacts.count) > 0:
			touchdown_s = float(k + 1) * dt
			touchdown_speed_mps = speed
			touchdown_sink_mps = _world_down_speed(current)
		previous_state = current.duplicate()
		previous_contacts = current_contacts
		samples += 1
		if detect_liftoff and liftoff_s >= 0.0 and float(k + 1) * dt >= liftoff_s + LIFTOFF_OBSERVE_S:
			break
		if stop_on_touchdown and touchdown_s >= 0.0 and float(k + 1) * dt >= touchdown_s + rollout_s:
			break
	# Catch a contact/crash occurring on the final integration step without advancing another physics tick.
	_session._physics_process(dt)
	var final_state: PackedFloat64Array = sim.state.duplicate()
	var final_contacts: Dictionary = _contacts(final_state)
	var final_heading: float = _euler(final_state)[0]
	var finite: bool = _array_finite(final_state) and _array_finite(sim.aux) and _array_finite(sim.continuous) \
		and _array_finite(sim.last_loads) and sim.fault_reason.is_empty()
	var metrics := {
		"finite": finite,
		"simulation_fault": sim.fault_reason,
		"crash": not _session.crash.is_empty(),
		"crash_reason": str(_session.crash.get("why", "")),
		"crash_speed_mps": float(_session.crash.get("speed", 0.0)),
		"elapsed_s": sim.time(),
		"steps": samples,
		"initial_contact_count": int(initial_contacts.count),
		"initial_contacts": initial_contacts.names,
		"final_contact_count": int(final_contacts.count),
		"final_contacts": final_contacts.names,
		"max_contact_count": max_contact_count,
		"ground_distance_m": ground_path_m,
		"total_path_distance_m": path_m,
		"runway_axis_displacement_m": _along_track(initial, final_state, h0),
		"max_cross_track_m": max_lateral_m,
		"initial_speed_mps": _speed(initial),
		"initial_engine_rpm": initial_rpm,
		"final_speed_mps": _speed(final_state),
		"minimum_ned_height_m": minimum_ned_height_m,
		"max_speed_mps": max_speed,
		"initial_heading_deg": rad_to_deg(h0),
		"final_heading_deg": rad_to_deg(final_heading),
		"heading_change_deg": rad_to_deg(wrapf(final_heading - h0, -PI, PI)),
		"max_heading_error_deg": rad_to_deg(max_heading_error),
		"tail_up_time_s": tail_up_s,
		"liftoff_time_s": liftoff_s,
		"liftoff_distance_m": liftoff_distance_m,
		"liftoff_speed_mps": liftoff_speed_mps,
		"touchdown_time_s": touchdown_s,
		"touchdown_speed_mps": touchdown_speed_mps,
		"touchdown_sink_mps": touchdown_sink_mps,
		"max_engine_rpm": max_rpm,
		"final_engine_rpm": float(sim.aux[AUX_RPM]),
		"max_abs_yaw_command": max_abs_yaw_command,
		"max_right_yaw_command": max_right_yaw_command,
		"max_left_yaw_command": min_left_yaw_command,
		"max_abs_yaw_servo": max_abs_yaw_servo,
		"wheel_state_layout": _session.wheel_state_layout(),
		"wheel_state_values_mps": _wheel_speeds(sim.continuous),
		"final_state_ned_body": Array(final_state),
	}
	if not is_nan(heading) and stall_estimate > 0.0:
		metrics["stall_estimate_mps"] = stall_estimate
	return { "name": name, "engine_running": engine_on, "metrics": metrics }


func _append_case(case: Dictionary) -> void:
	if case.has("setup_error"):
		_failures.append("case '%s' setup failed: %s" % [str(case.get("name", "unknown")), str(case.setup_error)])
	else:
		var metrics: Dictionary = case.get("metrics", {})
		if int(metrics.get("steps", 0)) <= 0 or float(metrics.get("elapsed_s", 0.0)) <= 0.0:
			_failures.append("case '%s' did not complete a simulation tick; inspect its crash/setup metrics" % str(case.get("name", "unknown")))
	var cases: Array = _report.cases
	cases.append(case)
	_report.cases = cases


func _wheel_profile_report() -> Array:
	var rows: Array = []
	for contact: Dictionary in _model.landing_gear.contacts:
		var prov: Dictionary = contact.get("wheel_provenance", {})
		rows.append({
			"contact": str(contact.name),
			"radius_m": float(contact.wheel_radius),
			"radius_source": str(prov.get("wheel_radius", {}).get("source", "")),
			"inertia_kg_m2": float(contact.wheel_inertia),
			"inertia_source": str(prov.get("wheel_inertia", {}).get("source", "")),
			"spin_relaxation_s": float(contact.spin_relaxation),
			"brake_torque_nm": float(contact.brake_torque),
			"brake_availability": str(contact.brake_availability),
		})
	return rows


func _terrain_contact_report(state: PackedFloat64Array) -> Array:
	var rows: Array = []
	var gear: Dictionary = _model.landing_gear
	var steer: float = float(_session.sim.aux[AUX_SERVO + 2])
	var anchors := PackedFloat64Array()
	var wheel_speeds: PackedFloat64Array = _session.sim.continuous.slice(_session.wheel_index(), _session.wheel_index() + _session.wheel_count())
	var wheel_diagnostics: Dictionary = Ground.evaluate(state, gear, steer, _session.ground_surfaces, anchors,
		wheel_speeds, 0.0, true)
	var diagnostic_rows: Array = wheel_diagnostics.get("wheels", [])
	for i in gear.contacts.size():
		var contact: Dictionary = gear.contacts[i]
		var frame: Dictionary = GroundWheels.frame(state, contact, steer, _session.ground_surfaces, PackedFloat64Array(), true)
		var point: PackedFloat64Array = frame.position
		var terrain: PackedFloat64Array = GroundTerrain.sample_validated(point[0], point[1], _session.ground_surfaces)
		var wheel: Dictionary = diagnostic_rows[i] if i < diagnostic_rows.size() else {}
		rows.append({
			"contact": str(contact.name),
			"surface_point_ned_m": Array(point),
			"terrain_height_up_m": terrain[0],
			"terrain_slope_north": terrain[1],
			"terrain_slope_east": terrain[2],
			"terrain_normal_ned": Array(frame.normal),
			"compression_m": frame.compression,
			"normal_load_N": float(wheel.get("normal_load", 0.0)),
		})
	return rows


func _wheel_speeds(continuous: PackedFloat64Array) -> Array:
	var values: Array = []
	for i in _session.wheel_count():
		var at: int = _session.wheel_index() + i
		values.append(float(continuous[at]) if at < continuous.size() else NAN)
	return values


func _contacts(state: PackedFloat64Array) -> Dictionary:
	var compressions: PackedFloat64Array = _session.gear_compressions(state)
	var names: Array = []
	var by_contact: Array = []
	for i in compressions.size():
		var c: float = compressions[i]
		var name: String = str(_model.landing_gear.contacts[i].name)
		by_contact.append({ "name": name, "compression_m": c, "contact": c > 0.0 })
		if c > 0.0:
			names.append(name)
	return { "count": names.size(), "names": names, "by_contact": by_contact }


func _tail_up(contacts: Dictionary) -> bool:
	var rows: Array = contacts.by_contact
	var mains := 0
	var tail_down := false
	for row: Dictionary in rows:
		if str(row.name).begins_with("main_") and bool(row.contact):
			mains += 1
		if str(row.name) == "tail" and bool(row.contact):
			tail_down = true
	return mains == 2 and not tail_down


func _euler(state: PackedFloat64Array) -> PackedFloat64Array:
	return M.q_to_euler(M.quat(state[RB.ATT], state[RB.ATT + 1], state[RB.ATT + 2], state[RB.ATT + 3]))


func _speed(state: PackedFloat64Array) -> float:
	return M.sqrt_(state[RB.VEL] * state[RB.VEL] + state[RB.VEL + 1] * state[RB.VEL + 1] + state[RB.VEL + 2] * state[RB.VEL + 2])


func _world_down_speed(state: PackedFloat64Array) -> float:
	var q := M.quat(state[RB.ATT], state[RB.ATT + 1], state[RB.ATT + 2], state[RB.ATT + 3])
	return M.q_rotate(q, M.v3(state[RB.VEL], state[RB.VEL + 1], state[RB.VEL + 2]))[2]


func _hold_pitch(state: PackedFloat64Array, target: float) -> float:
	var pitch_error: float = target - _euler(state)[1]
	return clampf(3.0 * pitch_error - 0.6 * state[RB.RATE + 1], -1.0, 1.0)


func _hold_roll(state: PackedFloat64Array, target: float) -> float:
	return clampf(2.0 * (target - _euler(state)[2]) - 0.3 * state[RB.RATE], -1.0, 1.0)


func _position_distance(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var dn: float = b[RB.POS] - a[RB.POS]
	var de: float = b[RB.POS + 1] - a[RB.POS + 1]
	var dd: float = b[RB.POS + 2] - a[RB.POS + 2]
	return M.sqrt_(dn * dn + de * de + dd * dd)


func _along_track(initial: PackedFloat64Array, current: PackedFloat64Array, heading: float) -> float:
	var dn: float = current[RB.POS] - initial[RB.POS]
	var de: float = current[RB.POS + 1] - initial[RB.POS + 1]
	return cos(heading) * dn + sin(heading) * de


func _cross_track(initial: PackedFloat64Array, current: PackedFloat64Array, heading: float) -> float:
	var dn: float = current[RB.POS] - initial[RB.POS]
	var de: float = current[RB.POS + 1] - initial[RB.POS + 1]
	return -sin(heading) * dn + cos(heading) * de


func _array_finite(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true


func _subtract_vectors(a: PackedFloat64Array, b: PackedFloat64Array) -> Array:
	if a.size() != b.size():
		return []
	var result: Array = []
	for i in a.size():
		result.append(a[i] - b[i])
	return result


func _finish() -> void:
	if not _failures.is_empty():
		_report["format"] = _report.get("format", "openrc-extra-ground-probe v1")
		_report["evidence_kind"] = _report.get("evidence_kind", "simulator prediction; not physical validation")
		_report["physical_validation"] = false
		_report["tick_rate_hz"] = _hz
		_report["errors"] = Array(_failures)
	var encoded := JSON.stringify(_report, "  ", true, true)
	if _output_path.is_empty():
		print(encoded)
	else:
		var file := FileAccess.open(_output_path, FileAccess.WRITE)
		if file == null:
			printerr("ground_probe: cannot open output '%s' (error %d)" % [_output_path, FileAccess.get_open_error()])
			quit(2)
			return
		file.store_string(encoded + "\n")
		file.close()
		print("ground_probe: wrote %s" % _output_path)
	quit(1 if not _failures.is_empty() else 0)

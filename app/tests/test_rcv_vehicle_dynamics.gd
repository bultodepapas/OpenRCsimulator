## RCV-05 coupled 6-DOF vehicle kernel: static support, 4WD/reverse/brakes,
## steering signs, terrain impacts, free flight, rollover contacts, and RK4.
## Run with `.tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_rcv_vehicle_dynamics.gd`.
extends SceneTree

const M := preload("res://physics/math3d.gd")
const Data := preload("res://physics/ground_vehicle/vehicle_data.gd")
const Course := preload("res://physics/ground_vehicle/course.gd")
const Vehicle := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const Integrator := preload("res://physics/integrator.gd")
const Session := preload("res://sim/ground_vehicle/session.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const GroundSurfaces := preload("res://physics/ground_surfaces.gd")
const GroundTerrain := preload("res://physics/ground_terrain.gd")

const DT := 1.0 / 240.0
const FORWARD := 3
const POS_NORTH := 0
const DOWN := 2
const VEL_DOWN := 5
const ATTITUDE := 6
const RATE := 10
const STEER_RATE := 30
const TRAVEL := 13
const TRAVEL_RATE := 17
const WHEEL_SPIN := 21
const STEER := 29

var _failures := 0
var _checks := 0


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	print(("ok   " if condition else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not condition:
		_failures += 1


func _controls(throttle := 0.0, steering := 0.0, brake := 0.0, reverse := false) -> Dictionary:
	return {"throttle": throttle, "steering": steering, "brake": brake, "reverse": reverse}


func _run_steps(state: PackedFloat64Array, model: Dictionary, controls: Dictionary, road: Callable, count: int) -> PackedFloat64Array:
	var result := state.duplicate()
	for tick in count:
		var previous := result
		result = Vehicle.step(result, model, controls, DT, road)
		if result.is_empty():
			push_error("Vehicle.step failed at tick %d controls=%s diagnostic=%s" % [tick, str(controls), _diagnose_tick(previous, model, controls, road)])
			return PackedFloat64Array()
	return result


func _diagnose_tick(state: PackedFloat64Array, model: Dictionary, controls: Dictionary, road: Callable) -> String:
	var current := state.duplicate()
	var dt := DT / float(Vehicle.SUBSTEPS_PER_TICK)
	for substep in Vehicle.SUBSTEPS_PER_TICK:
		var k1 := Vehicle.derivative(current, model, controls, road)
		if k1.is_empty():
			return "substep %d k1 %s" % [substep, str(Vehicle._evaluate(current, model, controls, road).get("error", ""))]
		var stage_2 := Integrator.axpy(current, 0.5 * dt, k1)
		var k2 := Vehicle.derivative(stage_2, model, controls, road)
		if k2.is_empty():
			return "substep %d k2 %s" % [substep, str(Vehicle._evaluate(stage_2, model, controls, road).get("error", ""))]
		var stage_3 := Integrator.axpy(current, 0.5 * dt, k2)
		var k3 := Vehicle.derivative(stage_3, model, controls, road)
		if k3.is_empty():
			return "substep %d k3 %s" % [substep, str(Vehicle._evaluate(stage_3, model, controls, road).get("error", ""))]
		var stage_4 := Integrator.axpy(current, dt, k3)
		var k4 := Vehicle.derivative(stage_4, model, controls, road)
		if k4.is_empty():
			return "substep %d k4 %s" % [substep, str(Vehicle._evaluate(stage_4, model, controls, road).get("error", ""))]
		current = Vehicle._rk4_step(current, model, controls, road, dt)
		if current.is_empty():
			return "substep %d final-combination" % substep
	return "not reproducible in stage replay"


func _max_abs(values: PackedFloat64Array) -> float:
	var result := 0.0
	for value in values:
		result = maxf(result, absf(value))
	return result


func _max_abs_difference(a: PackedFloat64Array, b: PackedFloat64Array, count: int) -> float:
	if a.size() < count or b.size() < count:
		return INF
	var result := 0.0
	for index in count:
		result = maxf(result, absf(a[index] - b[index]))
	return result


func _sum(values: PackedFloat64Array) -> float:
	var result := 0.0
	for value in values:
		result += value
	return result


func _test_generalized_solve(state: PackedFloat64Array, model: Dictionary) -> void:
	var geometry := Vehicle._corner_geometry(state, model, state[STEER], state[STEER_RATE], 0.0)
	if not bool(geometry.get("ok", false)):
		_check("block generalized mass setup succeeds", false)
		return
	var matrix: PackedFloat64Array = Vehicle._generalized_mass_matrix(model, geometry)
	var factor: Dictionary = Vehicle._factor_generalized_mass_matrix(matrix)
	var rhs := PackedFloat64Array()
	for degree in Vehicle.GENERALIZED_SIZE:
		rhs.append(0.25 + 0.17 * float(degree + 1))
	var solution: PackedFloat64Array = Vehicle._solve_generalized(factor, rhs) if bool(factor.get("ok", false)) else PackedFloat64Array()
	var residual := PackedFloat64Array()
	residual.resize(Vehicle.GENERALIZED_SIZE)
	if solution.size() == Vehicle.GENERALIZED_SIZE:
		for row in Vehicle.GENERALIZED_SIZE:
			var value := 0.0
			for column in Vehicle.GENERALIZED_SIZE:
				value += matrix[row * Vehicle.GENERALIZED_SIZE + column] * solution[column]
			residual[row] = value - rhs[row]
	_check("6-body + 8 local Schur solve matches the full mass matrix", bool(factor.get("ok", false))
		and solution.size() == Vehicle.GENERALIZED_SIZE and _max_abs(residual) < 1.0e-8,
		"max residual %.9f" % _max_abs(residual))


func _test_energy_opt_out(state: PackedFloat64Array, model: Dictionary, road: Callable) -> void:
	var controls := _controls()
	var complete: Dictionary = Vehicle._evaluate(state, model, controls, road, true)
	var dynamics_only: Dictionary = Vehicle._evaluate(state, model, controls, road, false)
	var complete_acceleration: PackedFloat64Array = complete.get("generalized_acceleration", PackedFloat64Array())
	var dynamics_acceleration: PackedFloat64Array = dynamics_only.get("generalized_acceleration", PackedFloat64Array())
	_check("energy opt-out preserves acceleration and leaves the energy path available",
		bool(complete.get("ok", false)) and bool(dynamics_only.get("ok", false))
		and complete_acceleration == dynamics_acceleration
		and is_finite(float(complete.get("energy_j", NAN))) and float(dynamics_only.get("energy_j", NAN)) == 0.0)


func _test_friction_convergence(state: PackedFloat64Array, model: Dictionary, road: Callable) -> void:
	var longitudinal := state.duplicate()
	longitudinal[FORWARD] = 0.4
	for corner in 4:
		longitudinal[WHEEL_SPIN + corner] = 0.4 / float(model["tire_radius_m"])
	_compare_friction_to_reference("driven longitudinal contact", longitudinal, model, _controls(0.05), road, false)
	var braking := state.duplicate()
	braking[FORWARD] = 2.0
	for corner in 4:
		braking[WHEEL_SPIN + corner] = 2.0 / float(model["tire_radius_m"])
	_compare_friction_to_reference("braking contact", braking, model, _controls(0.0, 0.0, 1.0), road, false)
	var airborne := state.duplicate()
	airborne[DOWN] -= 0.25
	airborne[VEL_DOWN] = -1.5
	airborne[FORWARD] = 1.5
	for corner in 4:
		airborne[WHEEL_SPIN + corner] = 1.5 / float(model["tire_radius_m"]) + 2.0
	_compare_friction_to_reference("airborne jump braking", airborne, model, _controls(0.0, 0.0, 0.4), road, true)


func _compare_friction_to_reference(
	case_name: String,
	state: PackedFloat64Array,
	model: Dictionary,
	controls: Dictionary,
	road: Callable,
	require_early_exit: bool,
) -> void:
	var adaptive: Dictionary = Vehicle._evaluate(state, model, controls, road, false, true)
	var six_sweep_reference: Dictionary = Vehicle._evaluate(state, model, controls, road, false, false)
	var adaptive_acceleration: PackedFloat64Array = adaptive.get("generalized_acceleration", PackedFloat64Array())
	var reference_acceleration: PackedFloat64Array = six_sweep_reference.get("generalized_acceleration", PackedFloat64Array())
	var acceleration_delta := _max_abs_difference(adaptive_acceleration, reference_acceleration, Vehicle.GENERALIZED_SIZE) if adaptive_acceleration.size() == reference_acceleration.size() else INF
	var adaptive_long: PackedFloat64Array = adaptive.get("wheel_longitudinal_force_n", PackedFloat64Array())
	var reference_long: PackedFloat64Array = six_sweep_reference.get("wheel_longitudinal_force_n", PackedFloat64Array())
	var adaptive_lateral: PackedFloat64Array = adaptive.get("wheel_lateral_force_n", PackedFloat64Array())
	var reference_lateral: PackedFloat64Array = six_sweep_reference.get("wheel_lateral_force_n", PackedFloat64Array())
	var adaptive_brake: PackedFloat64Array = adaptive.get("wheel_brake_torque_n_m", PackedFloat64Array())
	var reference_brake: PackedFloat64Array = six_sweep_reference.get("wheel_brake_torque_n_m", PackedFloat64Array())
	var long_delta := _max_abs_difference(adaptive_long, reference_long, Vehicle.CORNER_COUNT) if adaptive_long.size() == reference_long.size() else INF
	var lateral_delta := _max_abs_difference(adaptive_lateral, reference_lateral, Vehicle.CORNER_COUNT) if adaptive_lateral.size() == reference_lateral.size() else INF
	var brake_delta := _max_abs_difference(adaptive_brake, reference_brake, Vehicle.CORNER_COUNT) if adaptive_brake.size() == reference_brake.size() else INF
	var sweeps_used := int(adaptive.get("friction_sweeps_used", Vehicle.FRICTION_SWEEPS + 1))
	_check("adaptive PGS matches six-sweep reference: " + case_name,
		bool(adaptive.get("ok", false)) and bool(six_sweep_reference.get("ok", false))
		and sweeps_used >= 0 and sweeps_used <= Vehicle.FRICTION_SWEEPS
		and (not require_early_exit or sweeps_used < Vehicle.FRICTION_SWEEPS)
		and acceleration_delta < 0.01 and long_delta < 0.01 and lateral_delta < 0.01 and brake_delta < 0.01,
		"sweeps %d/%d, Δa %.6f, ΔFx %.6f N, ΔFy %.6f N, ΔTbrake %.6f Nm" % [
			sweeps_used, Vehicle.FRICTION_SWEEPS, acceleration_delta, long_delta, lateral_delta, brake_delta,
		])


func _flat_road(_north_m: float, _east_m: float) -> Dictionary:
	return {
		"height_m": 0.0,
		"normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]),
		"mu": 0.85,
		"rolling": 0.025,
		"surface_id": "asphalt",
	}


func _bump_road(north_m: float, _east_m: float) -> Dictionary:
	var fraction := maxf(0.0, 1.0 - absf(north_m - 0.18) / 0.18)
	return {
		"height_m": 0.025 * fraction,
		"normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]),
		# The test isolates vertical terrain/suspension response from longitudinal
		# tire braking while the truck crosses the profile.
		"mu": 0.0,
		"rolling": 0.025,
		"surface_id": "bump-test",
	}


func _test_terrain_spawn(model: Dictionary) -> void:
	var field := FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	var materials := GroundSurfaces.load_table()
	var surfaces := GroundSurfaces.build(materials.table, field.field)
	var road := func(north: float, east: float) -> Dictionary:
		var sample := GroundTerrain.sample(north, east, surfaces.rects)
		var normal := PackedFloat64Array([-sample[1], -sample[2], -1.0])
		return {"height_m": sample[0], "normal_ned": M.scale(normal, 1.0 / M.norm(normal)), "mu": 0.68, "rolling": 0.05}
	var pose := {"id": "runway", "north_m": 15.0, "east_m": 0.0, "heading_rad": PI / 2.0, "vehicle_up_m": 0.5}
	var snapshot := model.duplicate(true)
	var state := Vehicle.make_terrain_state(model, pose, road)
	_check("real uneven runway supports a complete zero-speed spawn", state.size() == Vehicle.STATE_SIZE)
	if state.size() != Vehicle.STATE_SIZE: return
	_check("terrain placement preserves model and requested horizontal pose", model == snapshot and state[0] == 15.0 and state[1] == 0.0 and _max_abs(state.slice(3, 6)) == 0.0)
	var observed := Vehicle.telemetry(state, model, road)
	var load_sum := _sum(observed.wheel_load_n)
	var weight := (float(model.sprung_mass_kg) + 4.0 * float(model.unsprung_mass_kg)) * float(model.gravity_m_per_s2)
	_check("all four terrain tires are preloaded without hull support", observed.wheel_in_contact.count(1) == 4 and observed.hull_in_contact.count(1) == 0 and absf(load_sum - weight) < 1.0e-5)
	var rested := _run_steps(state, model, _controls(), road, 240)
	_check("runway start settles without a launch or significant drift", rested.size() == Vehicle.STATE_SIZE and _max_abs_difference(rested, state, 3) < 0.02 and M.norm(rested.slice(3, 6)) < 0.05)
	var flat := Callable(self, "_flat_road")
	var on_flat := Vehicle.make_terrain_state(model, pose, flat)
	var flat_support := Vehicle.initialize(model, flat, 15.0, 0.0)
	_check("terrain initializer retains flat support altitude", on_flat.size() == Vehicle.STATE_SIZE and absf(on_flat[2] - flat_support.state[2]) < 1.0e-12)
	var bad := func(_n: float, _e: float) -> Dictionary:
		return {"height_m": NAN, "normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]), "mu": 0.7, "rolling": 0.05}
	_check("terrain spawn refuses nonfinite road data", Vehicle.make_terrain_state(model, pose, bad).is_empty())
	var steep := func(n: float, _e: float) -> Dictionary:
		return {"height_m": 0.5 * n, "normal_ned": M.scale(PackedFloat64Array([-0.5, 0.0, -1.0]), 1.0 / M.sqrt_(1.25)), "mu": 0.7, "rolling": 0.05}
	_check("runway initializer refuses unsupported steep starts", Vehicle.make_terrain_state(model, pose, steep).is_empty())
	var zero_g := model.duplicate(true)
	zero_g.gravity_m_per_s2 = 0.0
	var zero_state := Vehicle.make_terrain_state(zero_g, pose, road)
	_check("zero-gravity laboratory starts remain finite", zero_state.size() == Vehicle.STATE_SIZE and _max_abs(Vehicle.derivative(zero_state, zero_g, _controls(), road)) < 1.0e-5)


func _initialize() -> void:
	var loaded := Data.load_default()
	_check("strict vehicle source loads", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if not bool(loaded.get("ok", false)):
		quit(1)
		return
	var model: Dictionary = loaded["model"]
	_test_terrain_spawn(model)
	var flat := Callable(self, "_flat_road")
	var reset := Vehicle.initialize(model, flat, 0.0, 0.0)
	_check("flat reset produces a 31-value state", bool(reset.get("ok", false)) and reset.get("state", PackedFloat64Array()).size() == Vehicle.STATE_SIZE, str(reset.get("error", "")))
	if not bool(reset.get("ok", false)):
		quit(1)
		return
	var start: PackedFloat64Array = reset["state"]
	var original := start.duplicate()
	var initial_derivative := Vehicle.derivative(start, model, _controls(), flat)
	_check("level static reset has finite derivative", initial_derivative.size() == Vehicle.STATE_SIZE and _max_abs(initial_derivative) < 1.0e-7, "max |xdot| %.6f" % _max_abs(initial_derivative))
	var half_turn := start.duplicate()
	var half_turn_q := M.q_from_euler(PI, 0.0, 0.0)
	for component in 4:
		half_turn[ATTITUDE + component] = half_turn_q[component]
	var half_turn_derivative := Vehicle.derivative(half_turn, model, _controls(), flat)
	_check("pure 180-degree yaw quaternion remains valid in the derivative path",
		half_turn_derivative.size() == Vehicle.STATE_SIZE and _max_abs(half_turn_derivative) < 1.0e-7,
		"max |xdot| %.8f" % _max_abs(half_turn_derivative))
	var telemetry := Vehicle.telemetry(start, model, flat)
	var expected_corner_load := (float(model["sprung_mass_kg"]) / 4.0 + float(model["unsprung_mass_kg"])) * float(model["gravity_m_per_s2"])
	var loads: PackedFloat64Array = telemetry.get("wheel_load_n", PackedFloat64Array())
	_check("static tire loads support sprung and unsprung weight", loads.size() == 4 and _max_abs(PackedFloat64Array([
		loads[0] - expected_corner_load, loads[1] - expected_corner_load,
		loads[2] - expected_corner_load, loads[3] - expected_corner_load,
	])) < 1.0e-6, str(loads))
	var performance_start_usec := Time.get_ticks_usec()
	var rested := _run_steps(start, model, _controls(), flat, 240)
	var rest_elapsed_usec := Time.get_ticks_usec() - performance_start_usec
	_check("zero controls keep the supported truck at rest", not rested.is_empty() and _max_abs_difference(rested, start, 13) < 1.0e-5,
		"max rigid-state drift %.6f" % _max_abs_difference(rested, start, 13))
	print("headless baseline: 240 steps %.3f ms/tick (%.3f ms simulated / real-time)" % [
		float(rest_elapsed_usec) / 240000.0,
		float(rest_elapsed_usec) / 1000.0,
	])
	_check("step leaves caller-owned state untouched", start == original)
	var contact_count := 0
	var contacts: PackedByteArray = telemetry.get("wheel_in_contact", PackedByteArray())
	for contact in contacts:
		contact_count += int(contact)
	_check("telemetry reports all four tire contacts", contacts.size() == 4 and contact_count == 4)

	# The closed-form body/hub support is a force and moment balance, not a
	# hand-authored vertical offset. This checks the reset against tire loads.
	_check("reset altitude is finite and above tire radius", is_finite(start[DOWN]) and -start[DOWN] > float(model["tire_radius_m"]))
	_check("state layout keeps the rigid-body prefix and append offsets", Vehicle.POS == 0 and Vehicle.VEL == 3 and Vehicle.ATT == 6 and Vehicle.RATE == 10 and Vehicle.TRAVEL == 13 and Vehicle.TRAVEL_RATE == 17 and Vehicle.WHEEL_SPIN == 21 and Vehicle.WHEEL_ANGLE == 25 and Vehicle.STEER == 29 and Vehicle.STEER_RATE == 30)
	_check("checkpoint-visible solver version is explicit", Vehicle.SOLVER_VERSION == "openrc-ground-vehicle-dynamics-rk4-v2")
	var reference_identity := Vehicle._reference_backend_identity()
	_check("reference identity pins actual source or remapped bytecode bytes",
		Vehicle._sha256_is_valid(reference_identity.get("source_sha256", ""))
		and str(reference_identity.get("implementation_artifact_kind", ""))
		in ["gdscript_source", "gdscript_remapped_bytecode"])
	_test_backend_trajectory_equivalence(start, model, flat)
	_test_generalized_solve(start, model)
	_test_energy_opt_out(start, model, flat)
	_test_friction_convergence(start, model, flat)

	_test_drivetrain(start, model, flat)
	_test_steering(start, model, flat)
	_test_stops(start, model, flat)
	_test_bump(start, model)
	_test_airborne(start, model, flat)
	_test_freeflight_momentum(model, flat)
	_test_roof_contact(start, model, flat)
	_test_experiment_equilibrium(loaded, flat)
	_test_lab_extreme_drop(loaded, flat)
	_test_step_refinement(start, model, flat)
	_test_driven_tick_cost(start, model, flat)
	_test_session_tick_cost()

	print("RCV-05 vehicle dynamics: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


func _test_backend_trajectory_equivalence(start: PackedFloat64Array, model: Dictionary, road: Callable) -> void:
	var automatic_identity := Vehicle.backend_identity()
	if str(automatic_identity.get("backend", "")) != Vehicle.BACKEND_NATIVE:
		print("SKIP native/reference trajectory comparison: pinned native backend is not staged")
		return
	var reference_selected := Vehicle.set_backend_override_for_tests(Vehicle.BACKEND_GDSCRIPT_REFERENCE)
	var reference_identity := Vehicle.backend_identity()
	var reference_states: Array[PackedFloat64Array] = []
	var reference_state := start.duplicate()
	var reference_ok := reference_selected and str(reference_identity.get("backend", "")) == Vehicle.BACKEND_GDSCRIPT_REFERENCE
	for tick_index in 180:
		var controls := _controls()
		if tick_index < 70:
			controls.throttle = 0.45
			controls.steering = 0.16
		elif tick_index < 115:
			controls.steering = -0.08
		else:
			controls.brake = 0.75
		reference_state = Vehicle.step(reference_state, model, controls, DT, road)
		if reference_state.size() != Vehicle.STATE_SIZE:
			reference_ok = false
			break
		reference_states.append(reference_state.duplicate())
	var native_selected := Vehicle.set_backend_override_for_tests(Vehicle.BACKEND_NATIVE)
	var native_identity := Vehicle.backend_identity()
	var native_state := start.duplicate()
	var maximum_state_delta := 0.0
	var native_ok := native_selected and str(native_identity.get("backend", "")) == Vehicle.BACKEND_NATIVE
	if reference_states.size() == 180:
		for tick_index in 180:
			var controls := _controls()
			if tick_index < 70:
				controls.throttle = 0.45
				controls.steering = 0.16
			elif tick_index < 115:
				controls.steering = -0.08
			else:
				controls.brake = 0.75
			native_state = Vehicle.step(native_state, model, controls, DT, road)
			if native_state.size() != Vehicle.STATE_SIZE:
				native_ok = false
				break
			maximum_state_delta = maxf(maximum_state_delta,
				_max_abs_difference(native_state, reference_states[tick_index], Vehicle.STATE_SIZE))
	var automatic_restored := Vehicle.set_backend_override_for_tests("")
	var restored_identity := Vehicle.backend_identity()
	_check("debug test override runs both production backend paths and restores automatic selection",
		reference_ok and native_ok and automatic_restored
		and str(restored_identity.get("backend", "")) == Vehicle.BACKEND_NATIVE)
	_check("native and GDScript reference agree over a driven, steered, then braked 180-tick trajectory",
		reference_states.size() == 180 and native_state.size() == Vehicle.STATE_SIZE
		and is_finite(maximum_state_delta) and maximum_state_delta < 2.0e-6,
		"max state delta %.9f; native source %s" % [maximum_state_delta, str(native_identity.get("source_sha256", ""))])


func _test_drivetrain(start: PackedFloat64Array, model: Dictionary, flat: Callable) -> void:
	var driven := _run_steps(start, model, _controls(0.8), flat, 120)
	_check("4WD throttle accelerates forward and spins all wheels forward", not driven.is_empty() and driven[FORWARD] > 0.5 and driven[WHEEL_SPIN] > 0.0 and driven[WHEEL_SPIN + 3] > 0.0,
		"u %.3f m/s, spin FL/RR %.3f / %.3f rad/s" % [driven[FORWARD], driven[WHEEL_SPIN], driven[WHEEL_SPIN + 3]])
	var rolling := start.duplicate()
	rolling[FORWARD] = 2.0
	for corner in 4:
		rolling[WHEEL_SPIN + corner] = 2.0 / float(model["tire_radius_m"])
	var brake_controls := _controls(0.0, 0.0, 1.0)
	var brake_start := Vehicle.derivative(rolling, model, brake_controls, flat)
	var braked := _run_steps(rolling, model, brake_controls, flat, 90)
	var brake_end := Vehicle.derivative(braked, model, brake_controls, flat) if not braked.is_empty() else PackedFloat64Array()
	var brake_telemetry := Vehicle.telemetry(braked, model, flat, brake_controls) if not braked.is_empty() else {"ok": false}
	var brake_moments: PackedFloat64Array = brake_telemetry.get("wheel_brake_torque_n_m", PackedFloat64Array())
	var brake_moment_limit := float(model["brake_torque_per_wheel_nm"])
	_check("brake torque opposes wheel spin and produces useful tire braking", not braked.is_empty()
		and brake_start.size() == Vehicle.STATE_SIZE and brake_start[WHEEL_SPIN] < 0.0
		and absf(braked[FORWARD]) < 0.25
		and _max_abs(braked.slice(Vehicle.WHEEL_SPIN, Vehicle.WHEEL_SPIN + 4)) < 1.0
		and brake_moments.size() == 4 and _max_abs(brake_moments) <= brake_moment_limit + 1.0e-8
		and bool(brake_telemetry.get("ok", false)),
		"before %.3f, after %.3f m/s; u_dot %.2f→%.2f m/s²; FL spin %.3f (alpha %.2f) rad/s; FL force %.2f N; brake %.2f Nm" % [
			rolling[FORWARD], braked[FORWARD] if not braked.is_empty() else NAN,
			brake_start[FORWARD] if brake_start.size() > FORWARD else NAN,
			brake_end[FORWARD] if brake_end.size() > FORWARD else NAN,
			braked[WHEEL_SPIN] if not braked.is_empty() else NAN,
			brake_end[WHEEL_SPIN] if brake_end.size() > WHEEL_SPIN else NAN,
			brake_telemetry.get("wheel_longitudinal_force_n", PackedFloat64Array([NAN]))[0],
			brake_moments[0] if brake_moments.size() > 0 else NAN,
		])
	var rolling_back := rolling.duplicate()
	rolling_back[FORWARD] = -2.0
	for corner in 4:
		rolling_back[WHEEL_SPIN + corner] = -2.0 / float(model["tire_radius_m"])
	var braked_backwards := _run_steps(rolling_back, model, brake_controls, flat, 90)
	_check("brakes stop reverse travel without injecting unbounded reverse speed",
		not braked_backwards.is_empty() and absf(braked_backwards[FORWARD]) < 0.25
		and _max_abs(braked_backwards.slice(Vehicle.WHEEL_SPIN, Vehicle.WHEEL_SPIN + 4)) < 1.0,
		"before %.3f, after %.3f m/s, maximum wheel spin %.3f rad/s" % [
			rolling_back[FORWARD], braked_backwards[FORWARD] if not braked_backwards.is_empty() else NAN,
			_max_abs(braked_backwards.slice(Vehicle.WHEEL_SPIN, Vehicle.WHEEL_SPIN + 4)) if not braked_backwards.is_empty() else NAN,
		])
	var reverse := _run_steps(start, model, _controls(0.8, 0.0, 0.0, true), flat, 120)
	_check("reverse command drives backward", not reverse.is_empty() and reverse[FORWARD] < -0.3 and reverse[WHEEL_SPIN] < 0.0,
		"u %.3f m/s, wheel spin %.3f rad/s" % [reverse[FORWARD], reverse[WHEEL_SPIN]])
	var no_grip_road := func(_north_m: float, _east_m: float) -> Dictionary:
		return {"height_m": 0.0, "normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]), "mu": 0.0, "rolling": 0.0}
	var wheelspin := _run_steps(start, model, _controls(0.8), no_grip_road, 60)
	_check("zero-friction surface spins wheels without normal drive acceleration", not wheelspin.is_empty() and wheelspin[WHEEL_SPIN] > 0.0 and wheelspin[FORWARD] < driven[FORWARD],
		"u %.3f m/s, wheel spin %.3f rad/s" % [wheelspin[FORWARD], wheelspin[WHEEL_SPIN]])


func _test_steering(start: PackedFloat64Array, model: Dictionary, flat: Callable) -> void:
	var state := start.duplicate()
	state[FORWARD] = 1.5
	state[WHEEL_SPIN] = 1.5 / float(model["tire_radius_m"])
	state[WHEEL_SPIN + 1] = state[WHEEL_SPIN]
	state[WHEEL_SPIN + 2] = state[WHEEL_SPIN]
	state[WHEEL_SPIN + 3] = state[WHEEL_SPIN]
	var turned := _run_steps(state, model, _controls(0.0, 0.8), flat, 180)
	var turned_servo := turned[STEER] if turned.size() > STEER else NAN
	var turned_yaw_rate := turned[RATE + 2] if turned.size() > RATE + 2 else NAN
	_check("positive steering input turns wheels and yaw right", not turned.is_empty() and turned_servo > 0.0 and turned_yaw_rate > 0.0,
		"servo %.3f rad, yaw rate %.3f rad/s" % [turned_servo, turned_yaw_rate])
	var left := _run_steps(state, model, _controls(0.0, -0.8), flat, 180)
	var left_servo := left[STEER] if left.size() > STEER else NAN
	var left_yaw_rate := left[RATE + 2] if left.size() > RATE + 2 else NAN
	_check("negative steering input mirrors yaw sign", not left.is_empty() and left_servo < 0.0 and left_yaw_rate < 0.0,
		"servo %.3f rad, yaw rate %.3f rad/s" % [left_servo, left_yaw_rate])


func _test_stops(start: PackedFloat64Array, model: Dictionary, flat: Callable) -> void:
	var bump := start.duplicate()
	bump[TRAVEL] = float(model["travel_bump_m"]) + 0.01
	var bump_derivative := Vehicle.derivative(bump, model, _controls(), flat)
	_check("bump stop restores compression travel", not bump_derivative.is_empty() and bump_derivative[TRAVEL_RATE] < 0.0,
		"travel acceleration %.3f m/s²" % bump_derivative[TRAVEL_RATE])
	var droop := start.duplicate()
	droop[TRAVEL] = -float(model["travel_droop_m"]) - 0.01
	var droop_derivative := Vehicle.derivative(droop, model, _controls(), flat)
	_check("droop stop restores extension travel", not droop_derivative.is_empty() and droop_derivative[TRAVEL_RATE] > 0.0,
		"travel acceleration %.3f m/s²" % droop_derivative[TRAVEL_RATE])


func _test_bump(start: PackedFloat64Array, model: Dictionary) -> void:
	var state := start.duplicate()
	state[POS_NORTH] = -0.8
	state[FORWARD] = 2.0
	var initial_travel: PackedFloat64Array = PackedFloat64Array([state[TRAVEL], state[TRAVEL + 1], state[TRAVEL + 2], state[TRAVEL + 3]])
	var crossed := state.duplicate()
	var max_height := 0.0
	var travel_change := 0.0
	for _tick in 180:
		crossed = Vehicle.step(crossed, model, _controls(), DT, Callable(self, "_bump_road"))
		if crossed.is_empty():
			break
		max_height = maxf(max_height, float(_bump_road(crossed[POS_NORTH], 0.0)["height_m"]))
		for corner in 4:
			travel_change = maxf(travel_change, absf(crossed[TRAVEL + corner] - initial_travel[corner]))
	_check("suspension responds to a finite-width road bump", not crossed.is_empty() and travel_change > 0.002,
		"max suspension travel change %.4f m, max sampled height %.4f m, final north %.3f m" % [travel_change, max_height, crossed[POS_NORTH] if not crossed.is_empty() else NAN])


func _test_airborne(start: PackedFloat64Array, model: Dictionary, flat: Callable) -> void:
	var conservative_model := model.duplicate(true)
	conservative_model["suspension_damping_n_s_per_m"] = 0.0
	conservative_model["tire_damping_n_s_per_m"] = 0.0
	var state := start.duplicate()
	state[DOWN] -= 0.7
	var telemetry := Vehicle.telemetry(state, conservative_model, flat)
	_check("airborne state has no tire or hull support", bool(telemetry.get("ok", false)) and bool(telemetry.get("airborne", false)))
	var energy_before := Vehicle.energy(state, conservative_model, flat)
	var falling := _run_steps(state, conservative_model, _controls(), flat, 60)
	_check("free-fall converts altitude into downward velocity", not falling.is_empty() and falling[DOWN] > state[DOWN] and falling[VEL_DOWN] > 1.0,
		"down %.4f→%.4f m, w %.3f m/s" % [state[DOWN], falling[DOWN], falling[VEL_DOWN]])
	var energy_after := Vehicle.energy(falling, conservative_model, flat) if not falling.is_empty() else NAN
	_check("unforced free-flight energy uses the NED gravity sign", is_finite(energy_before) and is_finite(energy_after) and absf(energy_after - energy_before) < 1.0e-3,
		"energy %.6f→%.6f J" % [energy_before, energy_after])


func _momentum_world(state: PackedFloat64Array, model: Dictionary) -> PackedFloat64Array:
	var q := PackedFloat64Array([state[ATTITUDE], state[ATTITUDE + 1], state[ATTITUDE + 2], state[ATTITUDE + 3]])
	var velocity := PackedFloat64Array([state[3], state[4], state[5]])
	var rate := PackedFloat64Array([state[RATE], state[RATE + 1], state[RATE + 2]])
	var momentum_body := M.scale(velocity, float(model["sprung_mass_kg"]))
	var geometry: Dictionary = Vehicle._corner_geometry(state, model, state[STEER], state[STEER_RATE], 0.0)
	var hubs: Array = geometry["hub_position_body"]
	var derivatives: Array = geometry["hub_position_derivative_body"]
	for corner in 4:
		var hub_velocity := M.add(velocity, M.add(
			M.cross(rate, hubs[corner]),
			M.scale(derivatives[corner], state[TRAVEL_RATE + corner]),
		))
		momentum_body = M.add(momentum_body, M.scale(hub_velocity, float(model["unsprung_mass_kg"])))
	return M.q_rotate(q, momentum_body)


func _angular_momentum_world(state: PackedFloat64Array, model: Dictionary) -> PackedFloat64Array:
	var q := PackedFloat64Array([state[ATTITUDE], state[ATTITUDE + 1], state[ATTITUDE + 2], state[ATTITUDE + 3]])
	var velocity := PackedFloat64Array([state[3], state[4], state[5]])
	var rate := PackedFloat64Array([state[RATE], state[RATE + 1], state[RATE + 2]])
	var inertia: PackedFloat64Array = model["sprung_inertia_kg_m2"]
	var momentum_body := PackedFloat64Array([
		inertia[0] * rate[0] + inertia[3] * rate[1] + inertia[4] * rate[2],
		inertia[3] * rate[0] + inertia[1] * rate[1] + inertia[5] * rate[2],
		inertia[4] * rate[0] + inertia[5] * rate[1] + inertia[2] * rate[2],
	])
	var geometry: Dictionary = Vehicle._corner_geometry(state, model, state[STEER], state[STEER_RATE], 0.0)
	var hubs: Array = geometry["hub_position_body"]
	var derivatives: Array = geometry["hub_position_derivative_body"]
	var axes: Array = geometry["spin_axis_body"]
	for corner in 4:
		var hub_velocity := M.add(velocity, M.add(
			M.cross(rate, hubs[corner]),
			M.scale(derivatives[corner], state[TRAVEL_RATE + corner]),
		))
		momentum_body = M.add(momentum_body, M.cross(hubs[corner], M.scale(hub_velocity, float(model["unsprung_mass_kg"]))))
		var axis: PackedFloat64Array = axes[corner]
		var rotor_rate := M.dot(rate, axis) + state[WHEEL_SPIN + corner]
		momentum_body = M.add(momentum_body, M.scale(axis, float(model["wheel_spin_inertia_kg_m2"]) * rotor_rate))
	var angular_momentum_world := M.q_rotate(q, momentum_body)
	var position_world := PackedFloat64Array([state[POS_NORTH], state[POS_NORTH + 1], state[DOWN]])
	return M.add(angular_momentum_world, M.cross(position_world, _momentum_world(state, model)))


func _test_freeflight_momentum(model: Dictionary, flat: Callable) -> void:
	var free_model: Dictionary = model.duplicate(true)
	free_model["gravity_m_per_s2"] = 0.0
	var reset: Dictionary = Vehicle.initialize(free_model, flat)
	if not bool(reset.get("ok", false)):
		_check("zero-gravity momentum setup", false, str(reset.get("error", "")))
		return
	var translating: PackedFloat64Array = reset["state"].duplicate()
	translating[DOWN] = -8.0
	translating[FORWARD] = 1.25
	translating[4] = -0.2
	var p_before := _momentum_world(translating, free_model)
	var translated := _run_steps(translating, free_model, _controls(), flat, 60)
	var p_after := _momentum_world(translated, free_model) if not translated.is_empty() else PackedFloat64Array()
	_check("isolated flat-ground-free translation conserves total linear momentum", p_after.size() == 3 and _max_abs(M.sub(p_after, p_before)) < 1.0e-8,
		"momentum change %.9f kg m/s" % (_max_abs(M.sub(p_after, p_before)) if p_after.size() == 3 else INF))
	var rotating := translating.duplicate()
	rotating[FORWARD] = 0.0
	rotating[4] = 0.0
	rotating[RATE] = 0.08
	rotating[RATE + 1] = -0.06
	rotating[RATE + 2] = 0.10
	for corner in 4:
		rotating[WHEEL_SPIN + corner] = 2.0
	var h_before := _angular_momentum_world(rotating, free_model)
	var rotated := _run_steps(rotating, free_model, _controls(), flat, 60)
	var h_after := _angular_momentum_world(rotated, free_model) if not rotated.is_empty() else PackedFloat64Array()
	_check("isolated body/hub/rotor coupling conserves world angular momentum", h_after.size() == 3 and _max_abs(M.sub(h_after, h_before)) < 2.0e-4,
		"angular momentum change %.8f N m s" % (_max_abs(M.sub(h_after, h_before)) if h_after.size() == 3 else INF))


func _test_roof_contact(start: PackedFloat64Array, model: Dictionary, flat: Callable) -> void:
	var state := start.duplicate()
	var q := M.q_from_euler(0.0, 0.0, PI * 0.5)
	for i in 4:
		state[ATTITUDE + i] = q[i]
	var initial_telemetry := Vehicle.telemetry(state, model, flat)
	var initial_hull: PackedByteArray = initial_telemetry.get("hull_in_contact", PackedByteArray())
	var initial_hull_count := 0
	for contact in initial_hull:
		initial_hull_count += int(contact)
	_check("side-down orientation engages the chassis contact envelope", bool(initial_telemetry.get("ok", false)) and initial_hull_count > 0,
		"hull probes %d" % initial_hull_count)
	var flipped := _run_steps(state, model, _controls(), flat, 12)
	var telemetry := Vehicle.telemetry(flipped, model, flat) if not flipped.is_empty() else {"ok": false}
	var hull_contacts: PackedByteArray = telemetry.get("hull_in_contact", PackedByteArray())
	var supported_hull := 0
	for contact in hull_contacts:
		supported_hull += int(contact)
	_check("inverted truck remains finite through the chassis impact and rebound", not flipped.is_empty() and bool(telemetry.get("ok", false)),
		"hull contacts %d" % supported_hull)


func _test_experiment_equilibrium(loaded: Dictionary, flat: Callable) -> void:
	var changed := Data.with_experiment(loaded, {
		"gravity_scale": 0.85,
		"grip_scale": 0.8,
		"spring_scale": 1.2,
		"damper_scale": 0.8,
		"ballast_kg": 0.5,
		"ballast_height_m": 0.10,
	})
	_check("source-annotated experiment creates a valid derived model", bool(changed.get("ok", false)), str(changed.get("errors", [])))
	if not bool(changed.get("ok", false)):
		return
	var state := Vehicle.initialize(changed["model"], flat)
	var derivative := Vehicle.derivative(state.get("state", PackedFloat64Array()), changed["model"], _controls(), flat) if bool(state.get("ok", false)) else PackedFloat64Array()
	_check("experiment mass/CG inertia shifts preserve static balance", bool(state.get("ok", false)) and derivative.size() == Vehicle.STATE_SIZE and _max_abs(derivative) < 1.0e-7,
		"max |xdot| %.6f" % _max_abs(derivative))


func _test_lab_extreme_drop(loaded: Dictionary, flat: Callable) -> void:
	var changed := Data.with_experiment(loaded, {
		"gravity_scale": 2.0,
		"grip_scale": 2.0,
		"spring_scale": 2.0,
		"damper_scale": 2.0,
		"ballast_kg": 1.5,
		"ballast_height_m": 0.12,
	})
	if not bool(changed.get("ok", false)):
		_check("extreme lab profile loads", false, str(changed.get("errors", [])))
		return
	var high_model: Dictionary = changed["model"].duplicate(true)
	high_model["tire_stiffness_n_per_m"] = float(high_model["tire_stiffness_n_per_m"]) * 2.0
	high_model["tire_damping_n_s_per_m"] = float(high_model["tire_damping_n_s_per_m"]) * 2.0
	high_model["hull_contact_stiffness_n_per_m"] = float(high_model["hull_contact_stiffness_n_per_m"]) * 2.0
	high_model["hull_contact_damping_n_s_per_m"] = float(high_model["hull_contact_damping_n_s_per_m"]) * 2.0
	var reset: Dictionary = Vehicle.initialize(high_model, flat)
	if not bool(reset.get("ok", false)):
		_check("high-load high-stiffness profile equilibrates", false, str(reset.get("error", "")))
		return
	_check("high-load high-stiffness profile equilibrates", _max_abs(Vehicle.derivative(reset["state"], high_model, _controls(), flat)) < 1.0e-7)
	var dropped: PackedFloat64Array = reset["state"].duplicate()
	dropped[DOWN] -= 0.16
	dropped[VEL_DOWN] = 3.0
	var result := _run_steps(dropped, high_model, _controls(), flat, 120)
	_check("one-tick RK4 stays finite through high-gravity tire and hull impact", result.size() == Vehicle.STATE_SIZE and _max_abs(result) < 1.0e6,
		"down %.4f m, vertical speed %.4f m/s" % [result[DOWN] if not result.is_empty() else NAN, result[VEL_DOWN] if not result.is_empty() else NAN])
	var stop_state: PackedFloat64Array = reset["state"].duplicate()
	stop_state[TRAVEL] = float(high_model["travel_bump_m"]) + 0.01
	var stop_rate := Vehicle.derivative(stop_state, high_model, _controls(), flat)
	_check("doubled bump-stop stiffness remains restoring", stop_rate.size() == Vehicle.STATE_SIZE and stop_rate[TRAVEL_RATE] < 0.0)


func _test_step_refinement(start: PackedFloat64Array, model: Dictionary, flat: Callable) -> void:
	var quarter := _run_steps(start, model, _controls(0.45, 0.0, 0.0), flat, 120)
	var half_state := start.duplicate()
	for tick in 240:
		half_state = Vehicle.step(half_state, model, _controls(0.45), DT * 0.5, flat)
		if half_state.is_empty():
			break
	var state_error := 0.0
	if not quarter.is_empty() and not half_state.is_empty():
		for index in [0, 1, 2, 3, 4, 5, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23]:
			state_error = maxf(state_error, absf(quarter[index] - half_state[index]))
	_check("240 Hz result converges toward two half-size public steps", not quarter.is_empty() and not half_state.is_empty() and state_error < 0.08,
		"max body/suspension/spin delta %.5f" % state_error)


func _test_driven_tick_cost(start: PackedFloat64Array, model: Dictionary, flat: Callable) -> void:
	var state := start.duplicate()
	var controls := _controls(0.4, 0.2)
	var sweep_histogram := PackedInt32Array()
	sweep_histogram.resize(Vehicle.FRICTION_SWEEPS + 1)
	var started := Time.get_ticks_usec()
	for _tick in 60:
		state = Vehicle.step(state, model, controls, DT, flat)
		if state.is_empty():
			break
		var current_telemetry := Vehicle.telemetry(state, model, flat, controls)
		if not bool(current_telemetry.get("ok", false)):
			state = PackedFloat64Array()
			break
		var sweeps_used := int(current_telemetry.get("friction_sweeps_used", -1))
		if sweeps_used >= 0 and sweeps_used < sweep_histogram.size():
			sweep_histogram[sweeps_used] += 1
	var elapsed_usec := Time.get_ticks_usec() - started
	_check("driven tick/post-step telemetry performance sample completed", state.size() == Vehicle.STATE_SIZE)
	print("headless driven+telemetry baseline: 60 ticks %.3f ms/tick (%.3f ms simulated / real-time)" % [
		float(elapsed_usec) / 60000.0,
		float(elapsed_usec) / 1000.0,
	])
	print("driven PGS sweep histogram 0..%d: %s" % [Vehicle.FRICTION_SWEEPS, str(sweep_histogram)])
	if state.size() == Vehicle.STATE_SIZE:
		_profile_evaluation_phases(state, model, controls, flat)


func _profile_evaluation_phases(state: PackedFloat64Array, model: Dictionary, controls: Dictionary, road: Callable) -> void:
	const SAMPLES := 24
	var evaluate_ok := true
	var start_usec := Time.get_ticks_usec()
	for _sample in SAMPLES:
		var evaluated: Dictionary = Vehicle._evaluate(state, model, controls, road)
		evaluate_ok = evaluate_ok and bool(evaluated.get("ok", false))
	var evaluate_usec := Time.get_ticks_usec() - start_usec
	start_usec = Time.get_ticks_usec()
	for _sample in SAMPLES:
		var derivative := Vehicle.derivative(state, model, controls, road)
		evaluate_ok = evaluate_ok and derivative.size() == Vehicle.STATE_SIZE
	var derivative_usec := Time.get_ticks_usec() - start_usec
	start_usec = Time.get_ticks_usec()
	for _sample in SAMPLES:
		var current_telemetry := Vehicle.telemetry(state, model, road, controls)
		evaluate_ok = evaluate_ok and bool(current_telemetry.get("ok", false))
	var telemetry_usec := Time.get_ticks_usec() - start_usec
	start_usec = Time.get_ticks_usec()
	var stepped := state.duplicate()
	for _sample in SAMPLES:
		stepped = Vehicle.step(stepped, model, controls, DT, road)
		evaluate_ok = evaluate_ok and stepped.size() == Vehicle.STATE_SIZE
		if stepped.is_empty():
			break
	var step_usec := Time.get_ticks_usec() - start_usec
	_check("evaluation-phase performance samples completed", evaluate_ok)
	print("phase cost: evaluate %.3f ms, derivative %.3f ms, telemetry %.3f ms, step %.3f ms per call" % [
		float(evaluate_usec) / float(SAMPLES) / 1000.0,
		float(derivative_usec) / float(SAMPLES) / 1000.0,
		float(telemetry_usec) / float(SAMPLES) / 1000.0,
		float(step_usec) / float(SAMPLES) / 1000.0,
	])
	_profile_solver_stages(state, model, road)


func _profile_solver_stages(state: PackedFloat64Array, model: Dictionary, road: Callable) -> void:
	const SAMPLES := 32
	var geometry := Vehicle._corner_geometry(state, model, state[STEER], state[STEER_RATE], 0.0)
	var matrix: PackedFloat64Array = Vehicle._generalized_mass_matrix(model, geometry)
	var factor: Dictionary = Vehicle._factor_generalized_mass_matrix(matrix)
	var rhs := PackedFloat64Array()
	rhs.resize(Vehicle.GENERALIZED_SIZE)
	rhs[0] = 1.0
	var base_acceleration: PackedFloat64Array = Vehicle._solve_generalized(factor, rhs)
	var started := Time.get_ticks_usec()
	for _sample in SAMPLES:
		geometry = Vehicle._corner_geometry(state, model, state[STEER], state[STEER_RATE], 0.0)
	var geometry_usec := Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	for _sample in SAMPLES:
		matrix = Vehicle._generalized_mass_matrix(model, geometry)
	var mass_assembly_usec := Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	for _sample in SAMPLES:
		factor = Vehicle._factor_generalized_mass_matrix(matrix)
	var factor_usec := Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	for _sample in SAMPLES:
		base_acceleration = Vehicle._solve_generalized(factor, rhs)
	var solve_usec := Time.get_ticks_usec() - started
	var contacts: Array[Dictionary] = _profile_tire_contacts(state, model, geometry)
	var pgs_ok := bool(factor.get("ok", false)) and base_acceleration.size() == Vehicle.GENERALIZED_SIZE and contacts.size() == Vehicle.CORNER_COUNT
	started = Time.get_ticks_usec()
	for _sample in SAMPLES:
		var adaptive_acceleration := base_acceleration.duplicate()
		var force_long := PackedFloat64Array()
		var force_lateral := PackedFloat64Array()
		var brake_torque := PackedFloat64Array()
		force_long.resize(Vehicle.CORNER_COUNT)
		force_lateral.resize(Vehicle.CORNER_COUNT)
		brake_torque.resize(Vehicle.CORNER_COUNT)
		var adaptive_result := Vehicle._solve_tangent_friction(factor, adaptive_acceleration, contacts, force_long, force_lateral, brake_torque, true)
		pgs_ok = pgs_ok and bool(adaptive_result.get("ok", false))
	var adaptive_pgs_usec := Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	for _sample in SAMPLES:
		var reference_acceleration := base_acceleration.duplicate()
		var force_long := PackedFloat64Array()
		var force_lateral := PackedFloat64Array()
		var brake_torque := PackedFloat64Array()
		force_long.resize(Vehicle.CORNER_COUNT)
		force_lateral.resize(Vehicle.CORNER_COUNT)
		brake_torque.resize(Vehicle.CORNER_COUNT)
		var reference_result := Vehicle._solve_tangent_friction(factor, reference_acceleration, contacts, force_long, force_lateral, brake_torque, false)
		pgs_ok = pgs_ok and bool(reference_result.get("ok", false))
	var fixed_pgs_usec := Time.get_ticks_usec() - started
	_check("solver-stage profiling fixtures are valid", pgs_ok, "contacts %d" % contacts.size())
	print("solver-stage cost (%d samples): geometry %.3f ms, mass assembly %.3f ms, Schur factor %.3f ms, generalized solve %.3f ms, adaptive PGS %.3f ms, fixed-six PGS %.3f ms" % [
		SAMPLES,
		float(geometry_usec) / float(SAMPLES) / 1000.0,
		float(mass_assembly_usec) / float(SAMPLES) / 1000.0,
		float(factor_usec) / float(SAMPLES) / 1000.0,
		float(solve_usec) / float(SAMPLES) / 1000.0,
		float(adaptive_pgs_usec) / float(SAMPLES) / 1000.0,
		float(fixed_pgs_usec) / float(SAMPLES) / 1000.0,
	])
	_profile_course_road_samples(state, model, SAMPLES)


func _profile_course_road_samples(state: PackedFloat64Array, model: Dictionary, sample_count: int) -> void:
	var course_result: Dictionary = Course.load_default()
	if not bool(course_result.get("ok", false)):
		_check("course sampling profile fixture loads", false, str(course_result.get("errors", [])))
		return
	var course: Dictionary = course_result["course"]
	var course_road := func(north_m: float, east_m: float) -> Dictionary:
		return Course.sample(course, north_m, east_m)
	var hull_radii: PackedFloat64Array = model["hull_probe_radii_m"]
	var calls_per_evaluation := Vehicle.CORNER_COUNT + hull_radii.size()
	var total_calls := sample_count * calls_per_evaluation
	var road_ok := true
	var started := Time.get_ticks_usec()
	for sample_index in total_calls:
		var north_m := state[POS_NORTH] + float(sample_index % calls_per_evaluation) * 0.001
		var east_m := state[POS_NORTH + 1] + float(sample_index / calls_per_evaluation) * 0.001
		var surface: Variant = course_road.call(north_m, east_m)
		road_ok = road_ok and typeof(surface) == TYPE_DICTIONARY
	var raw_callback_usec := Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	for sample_index in total_calls:
		var north_m := state[POS_NORTH] + float(sample_index % calls_per_evaluation) * 0.001
		var east_m := state[POS_NORTH + 1] + float(sample_index / calls_per_evaluation) * 0.001
		var checked_surface: Dictionary = Vehicle._sample_surface(course_road, north_m, east_m)
		road_ok = road_ok and bool(checked_surface.get("ok", false))
	var checked_callback_usec := Time.get_ticks_usec() - started
	_check("course sampling profile fixture returns valid surfaces", road_ok)
	print("course road lookup (%d samples; %d per evaluate): raw Course.sample %.3f ms/call, validated _sample_surface %.3f ms/call" % [
		total_calls,
		calls_per_evaluation,
		float(raw_callback_usec) / float(total_calls) / 1000.0,
		float(checked_callback_usec) / float(total_calls) / 1000.0,
	])


func _profile_tire_contacts(state: PackedFloat64Array, model: Dictionary, geometry: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var q := M.q_normalized(PackedFloat64Array([state[ATTITUDE], state[ATTITUDE + 1], state[ATTITUDE + 2], state[ATTITUDE + 3]]))
	var q_conjugate := M.q_conj(q)
	var normal := PackedFloat64Array([0.0, 0.0, -1.0])
	var rho_body := M.q_rotate(q_conjugate, PackedFloat64Array([0.0, 0.0, float(model["tire_radius_m"])]))
	var hubs: Array = geometry["hub_position_body"]
	var derivatives: Array = geometry["hub_position_derivative_body"]
	var axes: Array = geometry["spin_axis_body"]
	var normal_load := (float(model["sprung_mass_kg"]) / 4.0 + float(model["unsprung_mass_kg"])) * float(model["gravity_m_per_s2"])
	for corner in Vehicle.CORNER_COUNT:
		var left_angle := -state[STEER] if corner < 2 else 0.0
		var forward_body := PackedFloat64Array([M.cos_(left_angle), -M.sin_(left_angle), 0.0])
		var forward_world := M.q_rotate(q, forward_body)
		var lateral_world := M.cross(forward_world, normal)
		var rows := Vehicle._tire_contact_rows(
			q_conjugate, forward_world, lateral_world, hubs[corner], rho_body,
			derivatives[corner], axes[corner], corner,
		)
		var mu_load := 0.85 * float(model["tire_friction_scale"]) * normal_load
		result.append({
			"rows": rows,
			"directions": [forward_world, lateral_world],
			"slip": PackedFloat64Array([0.2, 0.03]),
			"bias": PackedFloat64Array([0.0, 0.0, 0.0]),
			"mu_load": mu_load,
			"tau": float(model["tire_slip_relaxation_s"]),
			"kind": "wheel",
			"index": corner,
		})
	return result


func _test_session_tick_cost() -> void:
	var session = Session.new()
	if not session.prepare_default():
		_check("ground-vehicle session prepares for end-to-end timing", false, str(session.load_error))
		session.free()
		return
	var neutral := {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true}
	if not session.tick_once(neutral) or not session.resume():
		_check("ground-vehicle session arms and resumes for end-to-end timing", false)
		session.free()
		return
	var controls := {"throttle": 0.4, "steering": 0.2, "brake": 0.0, "reverse": false, "armed": true}
	var started := Time.get_ticks_usec()
	var completed := 0
	for _tick in 60:
		if not session.tick_once(controls):
			break
		completed += 1
	var elapsed_usec := Time.get_ticks_usec() - started
	_check("actual Session.tick_once advances 60 driven ticks", completed == 60 and session.tick == 60,
		"completed %d, fault %s" % [completed, session.fault_reason])
	print("actual Session.tick_once driven baseline: 60 ticks %.3f ms/tick (%.3f ms simulated / real-time)" % [
		float(elapsed_usec) / 60000.0,
		float(elapsed_usec) / 1000.0,
	])
	session.free()


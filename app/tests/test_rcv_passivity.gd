## F6: each nonelastic tire and brake must not do positive work at its own slip.
extends SceneTree

const Vehicle := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const Data := preload("res://physics/ground_vehicle/vehicle_data.gd")
const M := preload("res://physics/math3d.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(label: String, condition: bool, detail := "") -> void:
	checks += 1
	if condition:
		print("ok ", label)
	else:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func flat(_north: float, _east: float) -> Dictionary:
	return {"height_m": 0.0, "normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]), "mu": 0.9, "rolling": 1.0}


func zeros(size: int) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	result.resize(size)
	return result


func factor(anisotropic: bool = false) -> Dictionary:
	var mass := zeros(14 * 14)
	for i in 14:
		mass[i * 14 + i] = 1.0
	if anisotropic:
		# Inverse is the independently chosen W=[[4,1],[1,2]].
		mass[0] = 2.0 / 7.0
		mass[1] = -1.0 / 7.0
		mass[14] = -1.0 / 7.0
		mass[15] = 4.0 / 7.0
	return Vehicle._factor_generalized_mass_matrix(mass)


func wheel(slip_x: float, slip_y: float, accel_x: float, accel_y: float,
		limit: float = 10.0, anisotropic: bool = false) -> Dictionary:
	var row_x := zeros(14)
	var row_y := zeros(14)
	row_x[0] = 1.0
	row_y[1] = 1.0
	var contacts: Array[Dictionary] = [{"kind": "wheel", "index": 0, "rows": [row_x, row_y],
		"slip": PackedFloat64Array([slip_x, slip_y]), "bias": PackedFloat64Array([0.0, 0.0, 0.0]),
		"directions": [PackedFloat64Array([1.0, 0.0, 0.0]), PackedFloat64Array([0.0, 1.0, 0.0])],
		"mu_load": limit, "tau": 1.0}]
	var acceleration := zeros(14)
	acceleration[0] = accel_x
	acceleration[1] = accel_y
	var longitudinal := zeros(4)
	var lateral := zeros(4)
	var brakes := zeros(4)
	var result: Dictionary = Vehicle._solve_tangent_friction(factor(anisotropic), acceleration, contacts,
		longitudinal, lateral, brakes)
	return {"ok": result.ok, "x": longitudinal[0], "y": lateral[0], "sweeps": result.sweeps_used}


func brake(spin: float, accel: float, limit: float = 10.0) -> Dictionary:
	var row := zeros(14)
	row[10] = 1.0
	var contacts: Array[Dictionary] = [{"kind": "brake", "index": 0, "rows": [row],
		"slip": PackedFloat64Array([spin]), "bias": PackedFloat64Array([0.0, 0.0, 0.0]),
		"mu_load": limit, "tau": 1.0}]
	var acceleration := zeros(14)
	acceleration[10] = accel
	var longitudinal := zeros(4)
	var lateral := zeros(4)
	var brakes := zeros(4)
	var result: Dictionary = Vehicle._solve_tangent_friction(factor(), acceleration, contacts,
		longitudinal, lateral, brakes)
	return {"ok": result.ok, "torque": brakes[0], "sweeps": result.sweeps_used}


## Independent contact-point kinematics, including hub travel and wheel/body spin.
func stage_power(state: PackedFloat64Array, model: Dictionary, controls: Dictionary) -> Dictionary:
	var result: Dictionary = Vehicle._evaluate(state, model, controls, flat, false)
	if not result.get("ok", false):
		return {"ok": false}
	var q := M.q_normalized(PackedFloat64Array([state[6], state[7], state[8], state[9]]))
	var body_velocity := PackedFloat64Array([state[3], state[4], state[5]])
	var body_rate := PackedFloat64Array([state[10], state[11], state[12]])
	var angle := state[Vehicle.STEER]
	var rate := state[Vehicle.STEER_RATE]
	var frequency: float = model.steer_servo_natural_frequency_rad_s
	var acceleration: float = frequency * frequency * (float(controls.steering) * float(model.max_steer_angle_rad) - angle) \
		- 2.0 * float(model.steer_servo_damping_ratio) * frequency * rate
	var geometry: Dictionary = Vehicle._corner_geometry(state, model, angle, rate, acceleration)
	if not geometry.get("ok", false):
		return {"ok": false}
	var normal := PackedFloat64Array([0.0, 0.0, -1.0])
	var rho := M.q_rotate(M.q_conj(q), M.scale(normal, -float(model.tire_radius_m)))
	var tire_sum := 0.0
	var brake_sum := 0.0
	var worst_tire := 0.0
	var worst_brake := 0.0
	var all_passive := true
	for corner in 4:
		var r: PackedFloat64Array = geometry.hub_position_body[corner]
		var r_prime: PackedFloat64Array = geometry.hub_position_derivative_body[corner]
		var axis: PackedFloat64Array = geometry.spin_axis_body[corner]
		var hub_velocity := M.add(body_velocity, M.add(M.cross(body_rate, r), M.scale(r_prime, state[Vehicle.TRAVEL_RATE + corner])))
		var left_angle := -angle if corner < 2 else 0.0
		var left_rate := -rate if corner < 2 else 0.0
		var omega := M.add(body_rate, M.add(PackedFloat64Array([0.0, 0.0, -left_rate]),
			M.scale(axis, state[Vehicle.WHEEL_SPIN + corner])))
		var contact_velocity := M.q_rotate(q, M.add(hub_velocity, M.cross(omega, rho)))
		var forward := M.q_rotate(q, PackedFloat64Array([M.cos_(left_angle), -M.sin_(left_angle), 0.0]))
		forward = M.sub(forward, M.scale(normal, M.dot(forward, normal)))
		forward = M.scale(forward, 1.0 / M.norm(forward))
		var lateral := M.cross(forward, normal)
		lateral = M.scale(lateral, 1.0 / M.norm(lateral))
		var sx := M.dot(contact_velocity, forward)
		var sy := M.dot(contact_velocity, lateral)
		var px: float = result.wheel_longitudinal_force_n[corner] * sx
		var py: float = result.wheel_lateral_force_n[corner] * sy
		var p := px + py
		var b: float = result.wheel_brake_torque_n_m[corner] * state[Vehicle.WHEEL_SPIN + corner]
		all_passive = all_passive and p <= 1.0e-10 * maxf(1.0, absf(px) + absf(py)) \
			and b <= 1.0e-10 * maxf(1.0, absf(b))
		worst_tire = maxf(worst_tire, p)
		worst_brake = maxf(worst_brake, b)
		tire_sum += p
		brake_sum += b
	return {"ok": all_passive, "tire": tire_sum, "brake": brake_sum,
		"worst_tire": worst_tire, "worst_brake": worst_brake, "sweeps": result.friction_sweeps_used}


func drive_sequence(initial: PackedFloat64Array, model: Dictionary, hz: int, combined := false) -> Dictionary:
	var state := initial.duplicate()
	var dt := 1.0 / float(hz)
	var status := {"ok": true, "stages": 0, "worst_tire": 0.0, "worst_brake": 0.0,
		"tire_work": 0.0, "brake_work": 0.0, "max_sweeps": 0, "cap_stages": 0, "stage_match": true}
	var snap_225 := PackedFloat64Array()
	for tick in int(3.5 * hz):
		var t := float(tick) / float(hz)
		var driving := t < 1.5 or (t >= 1.75 and t < 2.75)
		var controls := {"throttle": 1.0 if driving else 0.0, "steering": 0.0,
			"brake": 0.0 if driving else 1.0, "reverse": false}
		if combined:
			controls.steering = 0.55 if t < 1.0 or t >= 2.6 else -0.45
			controls.reverse = t >= 1.75 and t < 2.75
			if t >= 2.75:
				controls.throttle = 0.35 # intentional brake/drive overlap in an admitted core state
		var stage_results: Array[Dictionary] = []
		var sample := func(y: PackedFloat64Array, _time: float) -> PackedFloat64Array:
			var observed := stage_power(y, model, controls)
			stage_results.append(observed)
			return Vehicle.stage_derivative(y, model, controls, flat)
		var k1: PackedFloat64Array = sample.call(state, t)
		var next: PackedFloat64Array = Vehicle.tick_policy(state, t, dt, sample, k1, 1)
		if next.size() != Vehicle.STATE_SIZE or stage_results.size() != 4:
			status.ok = false
			break
		if tick % roundi(float(hz) * 0.5) == 0:
			var production := Vehicle.step(state, model, controls, dt, flat)
			status.stage_match = status.stage_match and production.to_byte_array() == next.to_byte_array()
		var weights := [1.0, 2.0, 2.0, 1.0]
		for index in 4:
			var observed: Dictionary = stage_results[index]
			if not observed.has("tire"):
				status.ok = false
				break
			status.ok = status.ok and observed.ok
			status.stages += 1
			status.worst_tire = maxf(status.worst_tire, observed.worst_tire)
			status.worst_brake = maxf(status.worst_brake, observed.worst_brake)
			status.max_sweeps = maxi(status.max_sweeps, observed.sweeps)
			if observed.sweeps == Vehicle.FRICTION_SWEEPS:
				status.cap_stages += 1
			status.tire_work += dt / 6.0 * weights[index] * observed.tire
			status.brake_work += dt / 6.0 * weights[index] * observed.brake
		state = next
		if tick + 1 == int(2.25 * hz):
			snap_225 = state.duplicate()
	status["state_225"] = snap_225
	status["end_state"] = state
	return status


func run() -> void:
	check("reference backend selected", Vehicle.set_backend_override_for_tests("gdscript_reference"))
	var positive := wheel(1.0, 0.0, -2.0, 0.0)
	var negative := wheel(-1.0, 0.0, 2.0, 0.0)
	check("scalar positive-slip tire cannot accelerate slip", positive.ok and positive.x <= 0.0, str(positive))
	check("scalar negative-slip tire cannot accelerate slip", negative.ok and negative.x >= 0.0, str(negative))
	var brake_positive := brake(1.0, -2.0)
	var brake_negative := brake(-1.0, 2.0)
	check("positive-spin brake cannot add work", brake_positive.ok and brake_positive.torque <= 0.0, str(brake_positive))
	check("negative-spin brake cannot add work", brake_negative.ok and brake_negative.torque >= 0.0, str(brake_negative))
	var holding := brake(0.0, 2.0)
	var holding_mirror := brake(0.0, -2.0)
	check("zero spin keeps either static brake reaction", holding.ok and holding_mirror.ok
		and absf(holding.torque + 2.0) < 1.0e-12 and absf(holding_mirror.torque - 2.0) < 1.0e-12)
	var stuck := wheel(0.0, 0.0, -2.0, 3.0)
	check("zero slip keeps two-dimensional static tire reaction", stuck.ok
		and absf(stuck.x - 2.0) < 1.0e-12 and absf(stuck.y + 3.0) < 1.0e-12)
	var coupled := wheel(3.0, 4.0, -9.0, -9.0, 5.0, true)
	# Unconstrained [1,2], W=[[4,1],[1,2]], s=[3,4]. On the active
	# diameter F=lambda*(-4/5,3/5), the exact minimizer is [18/29,-27/58].
	check("combined slip uses anisotropic mobility-metric diameter", coupled.ok
		and absf(coupled.x - 18.0 / 29.0) < 1.0e-10
		and absf(coupled.y + 27.0 / 58.0) < 1.0e-10, str(coupled))
	check("combined reaction allows a positive individual component but no net work", coupled.ok
		and coupled.x > 0.0 and 3.0 * coupled.x + 4.0 * coupled.y <= 1.0e-12)
	var bounded := wheel(3.0, 4.0, -9.0, -9.0, 0.2, true)
	check("active diameter respects the force circle", bounded.ok
		and absf(sqrt(bounded.x * bounded.x + bounded.y * bounded.y) - 0.2) < 1.0e-10
		and 3.0 * bounded.x + 4.0 * bounded.y <= 1.0e-12, str(bounded))
	var no_grip := wheel(3.0, 4.0, -9.0, -9.0, 0.0, true)
	check("zero normal/grip permits no tangent force", no_grip.ok and no_grip.x == 0.0 and no_grip.y == 0.0)
	# Construct subnormals from binary64 bytes: source literals can be rounded to zero by the parser.
	var subnormal := PackedByteArray([0, 0, 0, 0, 0, 0, 4, 0]).decode_double(0)
	for case: Array in [["positive tiny", 1.0e-250, true], ["negative tiny", -1.0e-250, true],
			["positive subnormal", subnormal, false], ["negative subnormal", -subnormal, false]]:
		var tiny: float = case[1]
		if tiny == 0.0:
			if case[2]:
				check("normal tiny value is nonzero: " + str(case[0]), false)
			else:
				print("SKIP subnormal rounded to zero: ", case[0])
			continue
		var direction := 1.0 if tiny > 0.0 else -1.0
		var near_tire := wheel(tiny, 0.0, -2.0 if tiny > 0.0 else 2.0, 0.0)
		var near_brake := brake(tiny, -2.0 if tiny > 0.0 else 2.0)
		check("nonzero tire slip keeps its sign constraint: " + str(case[0]), near_tire.ok and near_tire.x * direction <= 0.0)
		check("nonzero spin keeps its sign constraint: " + str(case[0]), near_brake.ok and near_brake.torque * direction <= 0.0)
	var loaded: Dictionary = Data.load_default()
	check("stock vehicle loaded", loaded.get("ok", false))
	if loaded.get("ok", false):
		var initial: Dictionary = Vehicle.initialize(loaded.model, flat)
		check("flat-road stock initialized", initial.get("ok", false))
		if initial.get("ok", false):
			var state: PackedFloat64Array = initial.state.duplicate()
			state[Vehicle.VEL] = 5.0
			for corner in 4:
				state[Vehicle.WHEEL_SPIN + corner] = 30.0
			var controls := {"throttle": 1.0, "steering": 0.0, "brake": 0.0, "reverse": false}
			var evaluation: Dictionary = Vehicle._evaluate(state, loaded.model, controls, flat)
			var passive := bool(evaluation.get("ok", false))
			if passive:
				for corner in 4:
					var slip: float = 5.0 - float(loaded.model.tire_radius_m) * 30.0
					passive = passive and evaluation.wheel_longitudinal_force_n[corner] * slip <= 1.0e-12
			check("stock driven witness is passive at every tire", passive, str(evaluation.get("wheel_longitudinal_force_n", [])))
			var derivative := Vehicle.derivative(state, loaded.model, controls, flat)
			var epsilon := 1.0e-6
			var plus := state.duplicate()
			var minus := state.duplicate()
			for i in state.size():
				plus[i] += epsilon * derivative[i]
				minus[i] -= epsilon * derivative[i]
			var energy_rate := (Vehicle.energy(plus, loaded.model, flat) - Vehicle.energy(minus, loaded.model, flat)) / (2.0 * epsilon)
			var spin := 30.0
			var motor_per_wheel: float = float(loaded.model.drive_torque_per_wheel_nm) \
				* maxf(0.0, 1.0 - spin / float(loaded.model.drive_torque_fade_rad_s))
			var expected_rate := 0.0
			for corner in 4:
				var tire_slip: float = 5.0 - float(loaded.model.tire_radius_m) * spin
				var rolling: float = float(loaded.model.rolling_resistance_coefficient) \
					* evaluation.wheel_load_n[corner] * float(loaded.model.tire_radius_m) \
					* spin / sqrt(spin * spin + 1.0e-6)
				expected_rate += motor_per_wheel * spin - rolling * spin \
					+ evaluation.wheel_longitudinal_force_n[corner] * tire_slip
			check("stock energy derivative accounts for motor, rolling and passive tires",
				is_finite(energy_rate) and absf(energy_rate - expected_rate) < 1.0e-4,
				"measured=%s expected=%s" % [str(energy_rate), str(expected_rate)])
			var coarse := drive_sequence(initial.state, loaded.model, 240)
			var fine := drive_sequence(initial.state, loaded.model, 480)
			var combined := drive_sequence(initial.state, loaded.model, 240, true)
			print("F6 RK stage work 240/480 Hz: ", [coarse.tire_work, coarse.brake_work,
				fine.tire_work, fine.brake_work], " max positive tire/brake W: ",
				[coarse.worst_tire, coarse.worst_brake, fine.worst_tire, fine.worst_brake],
				" capped stages: ", [coarse.cap_stages, fine.cap_stages])
			check("all 240 Hz RK stages are individually passive", coarse.ok and coarse.stages == 840 * 4
				and coarse.tire_work <= 1.0e-8 and coarse.brake_work <= 1.0e-8)
			check("all 480 Hz RK stages are individually passive", fine.ok and fine.stages == 1680 * 4
				and fine.tire_work <= 1.0e-8 and fine.brake_work <= 1.0e-8)
			print("F6 combined/reverse RK work and cap: ", [combined.tire_work, combined.brake_work,
				combined.worst_tire, combined.worst_brake, combined.cap_stages, combined.max_sweeps])
			check("combined-slip reversal and drive/brake overlap stay passive at every stage",
				combined.ok and combined.stages == 840 * 4 and combined.tire_work <= 1.0e-8 and combined.brake_work <= 1.0e-8)
			check("instrumented stage path matches production steps", coarse.stage_match and fine.stage_match and combined.stage_match)
			if coarse.state_225.size() == Vehicle.STATE_SIZE and fine.state_225.size() == Vehicle.STATE_SIZE:
				var position_error := 0.0
				var velocity_error := 0.0
				for axis in 3:
					position_error = maxf(position_error, absf(coarse.state_225[axis] - fine.state_225[axis]))
					velocity_error = maxf(velocity_error, absf(coarse.state_225[Vehicle.VEL + axis] - fine.state_225[Vehicle.VEL + axis]))
				print("F6 2.25 s 240/480 Hz: max position delta ", position_error,
					" m; max body velocity delta ", velocity_error, " m/s")
				check("refinement retains the same driving regime", position_error < 0.25 and velocity_error < 1.0)
			else:
				check("refinement completes both control tapes", false)
			var airborne: PackedFloat64Array = initial.state.duplicate()
			airborne[Vehicle.POS + 2] -= 2.0
			for corner in 4:
				airborne[Vehicle.WHEEL_SPIN + corner] = 100.0 if corner % 2 == 0 else -100.0
			var braking := {"throttle": 0.0, "steering": 0.0, "brake": 1.0, "reverse": false}
			var flying: Dictionary = Vehicle._evaluate(airborne, loaded.model, braking, flat)
			var air_ok: bool = bool(flying.get("ok", false)) and bool(flying.get("airborne", false))
			if air_ok:
				for corner in 4:
					air_ok = air_ok and flying.wheel_load_n[corner] == 0.0 \
						and flying.wheel_longitudinal_force_n[corner] == 0.0 and flying.wheel_lateral_force_n[corner] == 0.0 \
						and flying.wheel_brake_torque_n_m[corner] * airborne[Vehicle.WHEEL_SPIN + corner] <= 0.0
			check("airborne wheel braking stays passive with no tire load", air_ok)
			var reacquired := false
			for _tick in 240:
				airborne = Vehicle.step(airborne, loaded.model, braking, 1.0 / 240.0, flat)
				if airborne.size() != Vehicle.STATE_SIZE:
					break
				var landing: Dictionary = Vehicle._evaluate(airborne, loaded.model, braking, flat)
				if landing.get("ok", false) and landing.wheel_in_contact.has(1):
					reacquired = stage_power(airborne, loaded.model, braking).get("ok", false)
					break
			check("load reacquisition restores passive tire contact", reacquired)
	print("RCV passivity: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

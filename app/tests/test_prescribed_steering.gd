extends SceneTree

const Actuators := preload("res://physics/control_actuators.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const RK := preload("res://physics/integrator.gd")
const Rotor := preload("res://physics/rotor_coupling.gd")
const FixedDatum := preload("res://physics/fixed_datum_body.gd")
const Sim := preload("res://sim/simulation.gd")
const VM := preload("res://sim/vehicle_model.gd")
const CARRIER := [1.2, 1.7, 2.1, 0.03, -0.04, 0.06]
const AXIAL := [0.1, 0.08]
const TRANSVERSE := [0.06, 0.05]
const REFERENCE := [0.6, -0.8, 0.0]
var _checks := 0
var _failures := 0
var _prepared: Dictionary


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL ", label, " ", detail)


func _initialize() -> void:
	_prepared = Actuators.prepare_prescribed_angle(_raw())
	_check("explicit source-bearing law prepares", _prepared.ok, str(_prepared))
	if not _prepared.ok:
		quit(1)
		return
	_validation_and_identity()
	_analytic_response()
	_invariant_stages()
	_rodrigues_oracles()
	_rotor_virtual_work()
	_kernel_reference()
	print("Prescribed steering: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _q(value: float, unit: String) -> Dictionary:
	return {value = value, unit = unit, kind = "estimated", source = "synthetic prescribed-actuator numerical fixture; no installed hardware claim"}


func _raw() -> Dictionary:
	return {format = Actuators.PRESCRIBED_ANGLE_FORMAT, id = "synthetic_steering",
		angle_limit = _q(0.5, "rad"), signed_full_scale_angle = _q(0.5, "rad"), lag_time = _q(0.25, "s"),
		max_rate = _q(4.0, "rad/s"), max_acceleration = _q(32.0, "rad/s^2")}


func _validation_and_identity() -> void:
	var raw := _raw()
	var before := var_to_bytes(raw)
	var p := Actuators.prepare_prescribed_angle(raw)
	_check("prepare retains source and deterministic law identity", p.identity == Actuators.prepare_prescribed_angle(raw).identity and p.provenance == raw and before == var_to_bytes(raw))
	_check("certification exposes conservative rate/acceleration and RK step", p.certified_rate_bound_radps == 4.0 and p.certified_acceleration_bound_radps2 == 32.0 and p.maximum_rk4_step_s == 0.25)
	p.provenance.lag_time.value = 99.0
	_check("prepared output does not alias source", before == var_to_bytes(raw))
	var mutations := [
		func(x: Dictionary) -> void: x.erase("lag_time"),
		func(x: Dictionary) -> void: x.lag_time.kind = "unknown",
		func(x: Dictionary) -> void: x.max_acceleration.source = "",
		func(x: Dictionary) -> void: x.max_rate.value = 3.99,
		func(x: Dictionary) -> void: x.max_acceleration.value = 31.99,
		func(x: Dictionary) -> void: x.signed_full_scale_angle.value = 0.51,
		func(x: Dictionary) -> void: x.lag_time.value = 0.0,
		func(x: Dictionary) -> void: x.lag_time.unit = "ms",
		func(x: Dictionary) -> void: x.angle_limit.value = INF,
		func(x: Dictionary) -> void: x.max_acceleration.value = NAN,
		func(x: Dictionary) -> void: x.torque_limit = 10.0,
		func(x: Dictionary) -> void: x.format = "legacy-servo",
		func(x: Dictionary) -> void: x.id += "\n",
	]
	for index in mutations.size():
		var altered := _raw()
		mutations[index].call(altered)
		_check("missing/unknown/incompatible source declaration rejects %d" % index, not Actuators.prepare_prescribed_angle(altered).ok)
	raw.signed_full_scale_angle.value = -0.5
	var negative := Actuators.prepare_prescribed_angle(raw)
	_check("signed linkage preserves tailwheel reversal", negative.ok and Actuators.prescribed_angle_response(negative, PackedFloat64Array([0, 0]), 1.0).target_rad == -0.5
		and negative.identity != _prepared.identity)
	var state := PackedFloat64Array([0.1, -0.2])
	var snapshot := var_to_bytes([_prepared, state])
	var forward := Actuators.prescribed_angle_response(_prepared, state, 1.0)
	var reverse := Actuators.prescribed_angle_response(_prepared, state, -1.0)
	_check("retargeting changes acceleration but never angle or rate", forward.ok and reverse.ok and forward.angle_rad == reverse.angle_rad
		and forward.rate_radps == reverse.rate_radps and forward.acceleration_radps2 != reverse.acceleration_radps2)
	forward.derivative[0] = 999.0
	_check("response and derivative arrays never alias caller state", snapshot == var_to_bytes([_prepared, state]) and Actuators.prescribed_angle_response(_prepared, state, 1.0).derivative[0] == -0.2)
	for invalid: PackedFloat64Array in [PackedFloat64Array(), PackedFloat64Array([0]), PackedFloat64Array([0, NAN]), PackedFloat64Array([0.50001, 0]), PackedFloat64Array([0.49, 0.1])]:
		_check("invalid state or outward latent angle rejects " + str(invalid), not Actuators.prescribed_angle_response(_prepared, invalid, 0.0).ok)
	_check("out-of-range upstream actual rejects without clipping", not Actuators.prescribed_angle_response(_prepared, state, 1.00001).ok and not Actuators.prescribed_angle_response(_prepared, state, NAN).ok)
	var altered := _prepared.duplicate(true)
	altered.values.lag_time = 0.0
	_check("malformed compiled configuration rejects cleanly", not Actuators.prescribed_angle_state_valid(altered, state))
	var one := Actuators.prescribed_angle_substeps(_prepared, 0.25, 1)
	_check("h/tau exactly one is admitted", one.ok and one.substeps == 1 and one.max_step_ratio == 1.0)
	_check("h/tau above one rejects an insufficient budget", not Actuators.prescribed_angle_substeps(_prepared, 0.250001, 1).ok)
	var split := Actuators.prescribed_angle_substeps(_prepared, 0.250001, 2)
	_check("existing substep owner can satisfy the unchanged rate envelope", split.ok and split.substeps == 2 and split.max_step_ratio <= 1.0)
	for dt: float in [0.0, -0.1, INF, NAN]:
		_check("invalid duration rejects selector " + str(dt), not Actuators.prescribed_angle_substeps(_prepared, dt).ok)


func _step(state: PackedFloat64Array, target: float, dt: float, inspected: Array) -> PackedFloat64Array:
	# Use the production integrator, with the two controller values appended to a
	# neutral body. This is a scalar fixture, not an alternative simulation kernel.
	var combined := RB.make_state(M.v3(0, 0, 0), M.v3(0, 0, 0), M.q_identity(), M.v3(0, 0, 0))
	combined.append_array(state)
	var derivative := func(s: PackedFloat64Array) -> PackedFloat64Array:
		var local := s.slice(13, 15)
		inspected.append(local.duplicate())
		var response := Actuators.prescribed_angle_response(_prepared, local, target)
		var out := PackedFloat64Array()
		out.resize(15)
		if response.ok:
			out[13] = response.derivative[0]
			out[14] = response.derivative[1]
		return out
	return RK.rk4_step(combined, dt, derivative).slice(13, 15)


func _analytic(initial: PackedFloat64Array, target: float, dt: float) -> PackedFloat64Array:
	# Independent closed critical-response formula; no production derivative,
	# latent-angle implementation or integration coefficients are used.
	var tau := 0.25
	var equilibrium := 0.5 * target
	var displacement := initial[0] - equilibrium
	var coefficient := initial[1] + displacement / tau
	var decay := exp(-dt / tau)
	return PackedFloat64Array([equilibrium + (displacement + coefficient * dt) * decay,
		(initial[1] - coefficient * dt / tau) * decay])


func _analytic_response() -> void:
	var previous := INF
	for n in [16, 32, 64]:
		var state := PackedFloat64Array([0, 0])
		var dt := 0.5 / float(n)
		var worst := 0.0
		for tick in n:
			state = _step(state, 1.0, dt, [])
			var time: float = (tick + 1) * dt
			var expected := PackedFloat64Array([0.5 * (1.0 - (1.0 + time / 0.25) * exp(-time / 0.25)),
				0.5 * time / pow(0.25, 2) * exp(-time / 0.25)])
			worst = maxf(worst, M.norm(M.sub(M.v3(state[0], state[1], 0), M.v3(expected[0], expected[1], 0))))
		_check("zero-state analytic critical step response %d" % n, worst < 2e-5, str(worst))
		_check("critical response converges at fourth order %d" % n, worst < previous / 12.0, str(worst))
		previous = worst
		print("GP12 analytic critical n=", n, " max_state_error=", worst)
	var state := PackedFloat64Array([0.2, 0.3])
	var oracle := state.duplicate()
	for target: float in [-1.0, 0.7, -0.2, 1.0]:
		for tick in 96: state = _step(state, target, 1.0 / 480.0, [])
		oracle = _analytic(oracle, target, 0.2)
		_check("reversal carries existing velocity into the next command", absf(state[0] - oracle[0]) < 1e-9 and absf(state[1] - oracle[1]) < 1e-9, str(state) + " / " + str(oracle))


func _invariant_stages() -> void:
	var maximum_rate := 0.0
	var maximum_acceleration := 0.0
	for ratio: float in [0.05, 0.5, 1.0]:
		for theta: float in [-0.5, 0.5]:
			for latent: float in [-0.5, 0.5]:
				for target: float in [-1.0, 0.37, 1.0]:
					var stages: Array = []
					var result := _step(PackedFloat64Array([theta, (latent - theta) / 0.25]), target, 0.25 * ratio, stages)
					_check("RK4 endpoint remains in invariant rectangle r=%s" % ratio, Actuators.prescribed_angle_state_valid(_prepared, result))
					for stage: PackedFloat64Array in stages:
						var response := Actuators.prescribed_angle_response(_prepared, stage, target)
						_check("every RK4 stage is admitted including invariant corners", response.ok)
						if response.ok:
							maximum_rate = maxf(maximum_rate, absf(response.rate_radps))
							maximum_acceleration = maxf(maximum_acceleration, absf(response.acceleration_radps2))
	_check("corner states attain but never exceed certified rate", maximum_rate == 4.0, str(maximum_rate))
	_check("corner commands attain but never exceed certified acceleration", maximum_acceleration == 32.0, str(maximum_acceleration))
	var state := PackedFloat64Array([0.0, 0.0])
	var valid := true
	var no_boundary_rate_resets := false
	for tick in 5000:
		var target: float = (1.0 if tick % 53 < 27 else -1.0) * (0.7 + 0.3 * sin(0.013 * tick))
		var stages: Array = []
		var next := _step(state, target, 1.0 / 240.0, stages)
		for stage: PackedFloat64Array in stages: valid = valid and Actuators.prescribed_angle_state_valid(_prepared, stage)
		valid = valid and Actuators.prescribed_angle_state_valid(_prepared, next)
		no_boundary_rate_resets = no_boundary_rate_resets or absf(next[1]) > 0.1
		state = next
	_check("long retarget sequence preserves invariant without angle clamps", valid and no_boundary_rate_resets, str(state))
	var rest := PackedFloat64Array([0.5, 0.0])
	var at_stop := _step(rest, 1.0, 0.25, [])
	_check("mechanical limit at rest holds with exactly zero acceleration", at_stop == rest and Actuators.prescribed_angle_response(_prepared, rest, 1.0).acceleration_radps2 == 0.0)
	_check("opposite command departs limit continuously inward", Actuators.prescribed_angle_response(_prepared, rest, -1.0).derivative[0] == 0.0
		and Actuators.prescribed_angle_response(_prepared, rest, -1.0).derivative[1] < 0.0)


func _hinge() -> PackedFloat64Array:
	var axis := M.v3(0.2, 0.3, 0.93)
	return M.scale(axis, 1.0 / M.norm(axis))


func _rodrigues_oracles() -> void:
	var reference := PackedFloat64Array(REFERENCE)
	var hinge := _hinge()
	var snapshot := var_to_bytes([reference, hinge])
	var worst_rate := 0.0
	var worst_acceleration := 0.0
	for sign_value: float in [-1.0, 1.0]:
		var angle := 0.3 * sign_value
		var rate := -0.7 * sign_value
		var acceleration := 1.1 * sign_value
		var motion := Actuators.fixed_axis_motion(reference, hinge, angle, rate, acceleration)
		var independent := M.q_rotate(M.q_from_axis_angle(hinge, angle), reference)
		_check("Rodrigues axle agrees with independent quaternion rotation", motion.ok and M.norm(M.sub(independent, motion.axis_body)) < 1e-15 and absf(M.norm(motion.axis_body) - 1.0) < 1e-15)
		var epsilon := 1e-5
		var plus := Actuators.fixed_axis_motion(reference, hinge, angle + rate * epsilon + 0.5 * acceleration * epsilon * epsilon, rate + acceleration * epsilon, acceleration)
		var minus := Actuators.fixed_axis_motion(reference, hinge, angle - rate * epsilon + 0.5 * acceleration * epsilon * epsilon, rate - acceleration * epsilon, acceleration)
		var rate_fd := M.scale(M.sub(plus.axis_body, minus.axis_body), 0.5 / epsilon)
		worst_rate = maxf(worst_rate, M.norm(M.sub(rate_fd, M.cross(motion.carrier_rate_body, motion.axis_body))))
		var acceleration_fd := M.scale(M.sub(plus.carrier_rate_body, minus.carrier_rate_body), 0.5 / epsilon)
		worst_acceleration = maxf(worst_acceleration, M.norm(M.sub(acceleration_fd, motion.carrier_accel_body)))
		var signed := Actuators.fixed_axis_motion(M.v3(0, -1, 0), M.v3(0, 0, 1), angle, rate, acceleration)
		_check("positive FRD z angle turns forward wheel heading right", M.norm(M.sub(signed.axis_body, M.v3(sin(angle), -cos(angle), 0))) < 1e-15)
	_check("axle finite difference equals nu cross axle", worst_rate < 1e-9, str(worst_rate))
	_check("carrier acceleration is body-coordinate nu derivative", worst_acceleration < 1e-10, str(worst_acceleration))
	var coaxial := Actuators.fixed_axis_motion(reference, reference, 0.4, 0.7, -0.3)
	_check("full axial carrier twist survives unchanged axle direction", coaxial.ok and M.norm(M.sub(coaxial.axis_body, reference)) < 1e-15 and M.norm(coaxial.carrier_rate_body) > 0.6 and M.norm(coaxial.carrier_accel_body) > 0.2)
	_check("kinematics leave caller axes byte-identical", snapshot == var_to_bytes([reference, hinge]))
	_check("zero/nonunit/nonfinite hinge kinematics reject", not Actuators.fixed_axis_motion(reference, M.v3(0, 0, 0), 0, 0, 0).ok
		and not Actuators.fixed_axis_motion(M.v3(0, 2, 0), hinge, 0, 0, 0).ok
		and not Actuators.fixed_axis_motion(reference, hinge, 0, NAN, 0).ok)


func _inventory() -> Dictionary:
	var axes := PackedFloat64Array(REFERENCE)
	axes.append_array(M.v3(1, 0, 0))
	var locked := PackedFloat64Array(CARRIER)
	for i in 2:
		var a := axes.slice(3 * i, 3 * i + 3)
		var d: float = AXIAL[i] - TRANSVERSE[i]
		for k in 3: locked[k] += TRANSVERSE[i] + d * a[k] * a[k]
		locked[3] += d * a[0] * a[1]
		locked[4] += d * a[0] * a[2]
		locked[5] += d * a[1] * a[2]
	var system := Rotor.prepare_system(locked, PackedFloat64Array(AXIAL), PackedFloat64Array(TRANSVERSE), axes,
		{partition_id = "synthetic-steering", reference_pose_id = "zero-angle", kind = "estimated", source = "test-only carrier and intrinsic rotor inventory"})
	return {system = system, locked = locked}


func _motion(state: PackedFloat64Array, acceleration: float) -> Dictionary:
	var motion := Actuators.fixed_axis_motion(PackedFloat64Array(REFERENCE), _hinge(), state[0], state[1], acceleration)
	var axes: PackedFloat64Array = motion.axis_body.duplicate()
	axes.append_array(M.v3(1, 0, 0))
	var rates: PackedFloat64Array = motion.carrier_rate_body.duplicate()
	rates.append_array(M.v3(0, 0, 0))
	var accels: PackedFloat64Array = motion.carrier_accel_body.duplicate()
	accels.append_array(M.v3(0, 0, 0))
	return {axes = axes, rates = rates, accels = accels}


func _mechanics(inv: Dictionary, omega: PackedFloat64Array, local: PackedFloat64Array, acceleration: float, braking := false) -> Dictionary:
	var motion := _motion(local, acceleration)
	var internal := PackedFloat64Array([-0.02 * local[2], -0.01 * local[3]]) if braking else PackedFloat64Array([0, 0])
	return Rotor.evaluate_system(inv.system, inv.locked, omega, local.slice(2, 4), motion.axes, motion.rates, motion.accels,
		M.v3(0, 0, 0), PackedFloat64Array([0, 0, 0, 0, 0, 0]), internal)


func _energy_momentum(omega: PackedFloat64Array, local: PackedFloat64Array) -> Dictionary:
	# Independent scalar axisymmetric component tensor oracle; no production
	# rotor matrix/energy/work/momentum functions or kinematics output are used.
	var carrier_h := M.v3(CARRIER[0] * omega[0] + CARRIER[3] * omega[1] + CARRIER[4] * omega[2],
		CARRIER[3] * omega[0] + CARRIER[1] * omega[1] + CARRIER[5] * omega[2],
		CARRIER[4] * omega[0] + CARRIER[5] * omega[1] + CARRIER[2] * omega[2])
	var momentum := carrier_h.duplicate()
	var energy := 0.5 * M.dot(omega, carrier_h)
	var first := M.q_rotate(M.q_from_axis_angle(_hinge(), local[0]), PackedFloat64Array(REFERENCE))
	for i in 2:
		var axis := first if i == 0 else M.v3(1, 0, 0)
		var carrier := M.scale(_hinge(), local[1]) if i == 0 else M.v3(0, 0, 0)
		var absolute := M.add(M.add(omega, carrier), M.scale(axis, local[2 + i]))
		var h := M.add(M.scale(absolute, TRANSVERSE[i]), M.scale(axis, (AXIAL[i] - TRANSVERSE[i]) * M.dot(axis, absolute)))
		momentum = M.add(momentum, h)
		energy += 0.5 * M.dot(absolute, h)
	return {energy = energy, momentum = momentum}


func _rotor_virtual_work() -> void:
	var inv := _inventory()
	_check("simultaneous moving wheel plus dynamic shaft partition prepares", inv.system.ok)
	var omega := M.v3(0.4, -0.6, 0.3)
	var local := PackedFloat64Array([0.1, 0.2, 17.0, -11.0])
	var controller := Actuators.prescribed_angle_response(_prepared, local.slice(0, 2), -0.8)
	var out := _mechanics(inv, omega, local, controller.acceleration_radps2)
	_check("moving-axis steering feeds one common solve", out.ok)
	if not out.ok: return
	var epsilon := 1e-6
	var plus := local.duplicate()
	var minus := local.duplicate()
	var derivative: PackedFloat64Array = controller.derivative.duplicate()
	derivative.append_array(out.spin_acceleration)
	for i in 4:
		plus[i] += epsilon * derivative[i]
		minus[i] -= epsilon * derivative[i]
	var ep := _energy_momentum(M.add(omega, M.scale(out.angular_acceleration, epsilon)), plus)
	var em := _energy_momentum(M.sub(omega, M.scale(out.angular_acceleration, epsilon)), minus)
	var base := _energy_momentum(omega, local)
	var fd_energy: float = (ep.energy - em.energy) / (2.0 * epsilon)
	var fd_momentum := M.add(M.scale(M.sub(ep.momentum, em.momentum), 0.5 / epsilon), M.cross(omega, base.momentum))
	_check("independent energy gradient equals signed actuator work", absf(fd_energy - out.actuator_power) < 2e-8, str(fd_energy - out.actuator_power))
	_check("internal prescribed steering preserves inertial angular momentum", M.norm(fd_momentum) < 2e-9, str(fd_momentum))
	_check("mechanism actuation has nonzero signed work", absf(out.actuator_power) > 1e-5)
	print("GP12 steering FD power_error_W=", fd_energy - out.actuator_power, " Hdot_error_Nm=", M.norm(fd_momentum))


func _kernel_reference() -> void:
	var original_rate := Engine.physics_ticks_per_second
	var inv := _inventory()
	var properties := {mass_kg = 1.0, cg_body_m = M.v3(0, 0, 0), inertia = inv.locked, inverse = RB.inertia_inverse(inv.locked)}
	var initial := RB.make_state(M.v3(0, 0, -100), M.v3(0, 0, 0), M.q_from_euler(0.2, -0.1, 0.3), M.v3(0.4, -0.6, 0.3))
	var previous_energy := INF
	var previous_h := INF
	for rate in [120, 240, 480]:
		Engine.physics_ticks_per_second = rate
		var sim := Sim.new()
		sim.gravity = 0.0
		sim.inertia = inv.locked
		sim.aux = PackedFloat64Array()
		sim.continuous = PackedFloat64Array([0.0, 0.0, 17.0, -11.0, 0.0, 0.0]) # theta,v,two spins,actuator work,brake heat
		var held_actual := [1.0]
		var step_s := 1.0 / float(rate)
		var model := VM.new()
		model.aux_size = 0
		model.modes_size = 0
		model.continuous_size = 6
		model.identity = {law = Actuators.PRESCRIBED_ANGLE_LAW, actuator = _prepared.identity, fixture = "closed-fixed-centers-moving-axis"}
		model.state_layout_identity = "synthetic-prescribed-steering-closed-rotors-v1"
		model.state_validator = func(frame: Dictionary, _context: Dictionary) -> bool:
			return Actuators.prescribed_angle_state_valid(_prepared, frame.continuous.slice(0, 2))
		model.substeps = func(_body: PackedFloat64Array, _values: PackedFloat64Array, _time: float) -> int:
			var admission := Actuators.prescribed_angle_substeps(_prepared, step_s, Sim.MAX_SUBSTEPS)
			return admission.substeps if admission.ok else Sim.MAX_SUBSTEPS + 1
		model.stage = func(body: PackedFloat64Array, values: PackedFloat64Array, _time: float) -> Dictionary:
			var controller := Actuators.prescribed_angle_response(_prepared, values.slice(0, 2), held_actual[0])
			if not controller.ok: return {loads = PackedFloat64Array()}
			var out := _mechanics(inv, body.slice(10, 13), values, controller.acceleration_radps2, true)
			if not out.ok: return {loads = PackedFloat64Array()}
			var body_rate := FixedDatum.derivative_with_angular_acceleration(body, properties, M.v3(0, 0, 0), 0.0, out.angular_acceleration)
			var local: PackedFloat64Array = controller.derivative.duplicate()
			local.append_array(out.spin_acceleration)
			local.append(out.actuator_power)
			local.append(-out.internal_spin_power)
			return {loads = PackedFloat64Array([0, 0, 0, 0, 0, 0]), derivative = local, body_derivative = body_rate, rotor_momentum = M.v3(0, 0, 0)}
		var installed := sim.set_model(model) and sim.reset(initial)
		_check("actual kernel continuous steering state installs %d" % rate, installed, sim.fault_reason)
		if not installed:
			sim.free()
			continue
		var beginning := _energy_momentum(initial.slice(10, 13), sim.continuous)
		var h0 := M.q_rotate(initial.slice(6, 10), beginning.momentum)
		var max_energy := 0.0
		var max_h := 0.0
		var min_power := INF
		var max_power := -INF
		var heat_monotone := true
		var last_heat := 0.0
		var boundary_continuity := true
		for tick in rate * 2:
			var before_rate: float = sim.continuous[1]
			held_actual[0] = 1.0 if tick < rate / 2 else (-1.0 if tick < rate else 0.0)
			# Changing the sampled command is not a velocity/reset operation.
			boundary_continuity = boundary_continuity and sim.continuous[1] == before_rate
			sim.step()
			if not sim.fault_reason.is_empty(): break
			var now := _energy_momentum(sim.state.slice(10, 13), sim.continuous)
			max_energy = maxf(max_energy, absf(now.energy + sim.continuous[5] - sim.continuous[4] - beginning.energy))
			max_h = maxf(max_h, M.norm(M.sub(M.q_rotate(sim.state.slice(6, 10), now.momentum), h0)))
			var controller := Actuators.prescribed_angle_response(_prepared, sim.continuous.slice(0, 2), held_actual[0])
			var mechanics := _mechanics(inv, sim.state.slice(10, 13), sim.continuous, controller.acceleration_radps2, true)
			min_power = minf(min_power, mechanics.actuator_power)
			max_power = maxf(max_power, mechanics.actuator_power)
			heat_monotone = heat_monotone and sim.continuous[5] >= last_heat
			last_heat = sim.continuous[5]
		_check("actual kernel steering and rotor stages complete %d" % rate, sim.tick == rate * 2 and sim.fault_reason.is_empty(), sim.fault_reason)
		_check("continuous steering target changes never reset v %d" % rate, boundary_continuity)
		_check("independent T plus heat minus actuator work closes %d" % rate, max_energy < 2e-6, str(max_energy))
		_check("independent inertial angular momentum closes %d" % rate, max_h < 2e-7, str(max_h))
		_check("mechanism can supply and absorb work while brake remains passive %d" % rate, min_power < -1e-5 and max_power > 1e-5 and heat_monotone and last_heat > 0.0)
		_check("steering energy error converges under actual kernel refinement %d" % rate, max_energy < previous_energy)
		_check("steering momentum error converges under actual kernel refinement %d" % rate, max_h < previous_h)
		previous_energy = max_energy
		previous_h = max_h
		var checkpoint := sim.checkpoint()
		for tick in 8: sim.step()
		var expected := var_to_bytes([sim.state, sim.continuous])
		var restored := sim.restore_checkpoint(checkpoint)
		for tick in 8: sim.step()
		_check("angle/rate/rotors/work checkpoint replay is byte-identical %d" % rate, restored and expected == var_to_bytes([sim.state, sim.continuous]))
		var accepted := var_to_bytes([sim.state, sim.continuous, sim.tick])
		held_actual[0] = 1.1
		sim.step()
		_check("invalid steering stage rejects atomically without impulse/work %d" % rate, not sim.fault_reason.is_empty() and accepted == var_to_bytes([sim.state, sim.continuous, sim.tick]))
		print("GP12 steering kernel rate_Hz=", rate, " energy_work_error_J=", max_energy, " H_error_Nms=", max_h,
			" power_range_W=", min_power, ",", max_power)
		sim.free()
	Engine.physics_ticks_per_second = original_rate

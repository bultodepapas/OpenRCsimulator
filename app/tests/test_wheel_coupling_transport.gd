# GP-09b: independent component energy and inertial momentum oracles.
extends SceneTree

const WC := preload("res://physics/wheel_coupling.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Sim := preload("res://sim/simulation.gd")
const VM := preload("res://sim/vehicle_model.gd")

const CARRIER := [1.2, 1.7, 2.1, 0.03, -0.04, 0.06]
const RADII := [0.2, 0.15]
const AXIAL := [0.1, 0.08]
const TRANSVERSE := [0.06, 0.05]
const AXES := [0.6, -0.8, 0.0, 0.0, 0.6, 0.8]

var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)


func _initialize() -> void:
	_coaxial_frame_twist()
	_independent_oracles()
	_fixed_axis_limit()
	_rejections()
	_kernel_ledger()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _prepared() -> Dictionary:
	return WC.prepare_transport(PackedFloat64Array(CARRIER), PackedFloat64Array(RADII),
		PackedFloat64Array(AXIAL), PackedFloat64Array(TRANSVERSE))


func _coaxial_frame_twist() -> void:
	var j := PackedFloat64Array([1.0, 1.0, 1.0, 0.0, 0.0, 0.0])
	var prepared := WC.prepare_transport(j, PackedFloat64Array([0.2]), PackedFloat64Array([0.1]), PackedFloat64Array([0.06]))
	var zero := M.v3(0.0, 0.0, 0.0)
	var a := M.v3(0.0, 0.0, 1.0)
	var nu := M.v3(0.0, 0.0, 2.0)
	var out := WC.evaluate_transport(prepared, zero, PackedFloat64Array([0.6]), a, nu, zero,
		zero, zero, PackedFloat64Array([-0.2]))
	_check("coaxial brake includes relative spin power -0.6 W", out.ok and absf(out.internal_spin_power + 0.6) < 1e-14)
	_check("coaxial brake stator demands actuator power -0.4 W", absf(out.actuator_power + 0.4) < 1e-14)
	_check("coaxial full energy rate is tau*(sigma+nu)=-1 W", absf(out.kinetic_energy_rate + 1.0) < 1e-14)
	_check("coaxial brake body reaction conserves total momentum", absf(out.angular_acceleration[2] - 0.2) < 1e-14)
	_check("coaxial torque ledger closes independently differentiated energy", absf(out.power_residual) < 1e-14)
	var gauge := WC.evaluate_transport(prepared, zero, PackedFloat64Array([-0.4]), a, nu, M.v3(0.0, 0.0, 0.7),
		zero, zero, PackedFloat64Array([0.0]))
	_check("axial prescribed frame acceleration preserves inertial rest", absf(gauge.derivative[0] + 0.14) < 1e-14 \
		and M.norm(gauge.angular_acceleration) < 1e-14 and absf(gauge.kinetic_energy_rate) < 1e-14)
	_check("carrier axial twist is modeled despite identically zero axis rate", M.norm(M.cross(nu, a)) == 0.0 and absf(out.actuator_power) > 0.1)


# Independent scalar component tensor/energy. No production tensor assembly,
# solver factor, transport bias or actuator ledger is used in these oracles.
func _rotor_h(index: int, omega: PackedFloat64Array, rims: PackedFloat64Array,
		axes: PackedFloat64Array, rates: PackedFloat64Array) -> PackedFloat64Array:
	var a := axes.slice(3 * index, 3 * index + 3)
	var absolute := PackedFloat64Array()
	for k in 3:
		absolute.append(omega[k] + rates[3 * index + k] + rims[index] / RADII[index] * a[k])
	var axial_projection := a[0] * absolute[0] + a[1] * absolute[1] + a[2] * absolute[2]
	return PackedFloat64Array([
		TRANSVERSE[index] * absolute[0] + (AXIAL[index] - TRANSVERSE[index]) * axial_projection * a[0],
		TRANSVERSE[index] * absolute[1] + (AXIAL[index] - TRANSVERSE[index]) * axial_projection * a[1],
		TRANSVERSE[index] * absolute[2] + (AXIAL[index] - TRANSVERSE[index]) * axial_projection * a[2]])


func _energy(omega: PackedFloat64Array, rims: PackedFloat64Array,
		axes: PackedFloat64Array, rates: PackedFloat64Array) -> float:
	var result: float = 0.5 * (CARRIER[0] * omega[0] * omega[0] + CARRIER[1] * omega[1] * omega[1] \
		+ CARRIER[2] * omega[2] * omega[2]) + CARRIER[3] * omega[0] * omega[1] \
		+ CARRIER[4] * omega[0] * omega[2] + CARRIER[5] * omega[1] * omega[2]
	for i in 2:
		var x: float = omega[0] + rates[3 * i] + rims[i] / RADII[i] * axes[3 * i]
		var y: float = omega[1] + rates[3 * i + 1] + rims[i] / RADII[i] * axes[3 * i + 1]
		var z: float = omega[2] + rates[3 * i + 2] + rims[i] / RADII[i] * axes[3 * i + 2]
		var projected: float = axes[3 * i] * x + axes[3 * i + 1] * y + axes[3 * i + 2] * z
		result += 0.5 * (TRANSVERSE[i] * (x * x + y * y + z * z) + (AXIAL[i] - TRANSVERSE[i]) * projected * projected)
	return result


func _momentum(omega: PackedFloat64Array, rims: PackedFloat64Array,
		axes: PackedFloat64Array, rates: PackedFloat64Array) -> PackedFloat64Array:
	var body := PackedFloat64Array([
		CARRIER[0] * omega[0] + CARRIER[3] * omega[1] + CARRIER[4] * omega[2],
		CARRIER[3] * omega[0] + CARRIER[1] * omega[1] + CARRIER[5] * omega[2],
		CARRIER[4] * omega[0] + CARRIER[5] * omega[1] + CARRIER[2] * omega[2]])
	for i in 2:
		body = M.add(body, _rotor_h(i, omega, rims, axes, rates))
	return body


# Rodrigues from a rotation vector, also used to move reference axes and body
# momenta into inertial space. nu_dot enters its second-order time Taylor term.
func _rotate(value: PackedFloat64Array, rotation_vector: PackedFloat64Array) -> PackedFloat64Array:
	var angle := M.norm(rotation_vector)
	if angle == 0.0:
		return value.duplicate()
	var b := M.scale(rotation_vector, 1.0 / angle)
	return M.add(M.add(M.scale(value, M.cos_(angle)), M.scale(M.cross(b, value), M.sin_(angle))),
		M.scale(b, M.dot(b, value) * (1.0 - M.cos_(angle))))


func _perturbed_axes(axes: PackedFloat64Array, rates: PackedFloat64Array,
		accels: PackedFloat64Array, dt: float) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	for i in 2:
		result.append_array(_rotate(axes.slice(3 * i, 3 * i + 3),
			M.add(M.scale(rates.slice(3 * i, 3 * i + 3), dt), M.scale(accels.slice(3 * i, 3 * i + 3), 0.5 * dt * dt))))
	return result


func _independent_oracles() -> void:
	var prepared := _prepared()
	_check("full physical axisymmetric inventory prepares", prepared.ok)
	var axes := PackedFloat64Array(AXES)
	var rates := PackedFloat64Array([0.7, -0.4, 1.1, -0.3, 0.5, 0.8])
	var accels := PackedFloat64Array([-0.2, 0.1, 0.3, 0.2, -0.3, 0.1])
	var external := PackedFloat64Array([0.2, -0.1, 0.3, -0.3, 0.4, 0.1])
	var internal := PackedFloat64Array([-0.07, 0.04])
	var moment := M.v3(0.3, -0.4, 0.7)
	var eps := 1e-5
	var worst_power := 0.0
	var worst_momentum := 0.0
	var worst_axial := 0.0
	var worst_actuator := 0.0
	for trial in 20:
		var omega := M.v3(-1.0 + 0.13 * trial, 0.3 - 0.1 * trial, 0.7 + 0.03 * trial)
		var rims := PackedFloat64Array([1.1 + 0.04 * trial, -0.7 - 0.02 * trial])
		var out := WC.evaluate_transport(prepared, omega, rims, axes, rates, accels, moment, external, internal)
		_check("arbitrary moving-axis stage solves %d" % trial, out.ok)
		# External virtual work written as a body-only moment plus full rotor
		# angular velocities, independently of the generalized power split.
		var body_external := moment.duplicate()
		var physical_power := 0.0
		var relative_power := 0.0
		for i in 2:
			var couple := external.slice(3 * i, 3 * i + 3)
			body_external = M.sub(body_external, couple)
			var absolute := M.add(M.add(omega, rates.slice(3 * i, 3 * i + 3)),
				M.scale(axes.slice(3 * i, 3 * i + 3), rims[i] / RADII[i]))
			physical_power += M.dot(absolute, couple)
			relative_power += internal[i] * rims[i] / RADII[i]
		physical_power += M.dot(omega, body_external)
		_check("external virtual work and internal relative torque power %d" % trial,
			absf(out.external_power - physical_power) < 1e-13 and absf(out.internal_spin_power - relative_power) < 1e-13)
		var alpha: PackedFloat64Array = out.angular_acceleration
		var rim_rate: PackedFloat64Array = out.derivative
		var plus_w := M.add(omega, M.scale(alpha, eps))
		var minus_w := M.sub(omega, M.scale(alpha, eps))
		var plus_u := rims.duplicate()
		var minus_u := rims.duplicate()
		var plus_nu := rates.duplicate()
		var minus_nu := rates.duplicate()
		for i in 2:
			plus_u[i] += eps * rim_rate[i]
			minus_u[i] -= eps * rim_rate[i]
		for k in 6:
			plus_nu[k] += eps * accels[k]
			minus_nu[k] -= eps * accels[k]
		var plus_a := _perturbed_axes(axes, rates, accels, eps)
		var minus_a := _perturbed_axes(axes, rates, accels, -eps)
		var fd_power := (_energy(plus_w, plus_u, plus_a, plus_nu) - _energy(minus_w, minus_u, minus_a, minus_nu)) / (2.0 * eps)
		worst_power = maxf(worst_power, absf(fd_power - out.external_power - out.internal_spin_power - out.actuator_power))
		_check("direct component energy/momentum agree %d" % trial,
			absf(out.kinetic_energy - _energy(omega, rims, axes, rates)) < 1e-12 \
			and _near(out.angular_momentum, _momentum(omega, rims, axes, rates), 1e-13))
		var plus_body_rotation := M.add(M.scale(omega, eps), M.scale(alpha, 0.5 * eps * eps))
		var minus_body_rotation := M.add(M.scale(omega, -eps), M.scale(alpha, 0.5 * eps * eps))
		var plus_h := _rotate(_momentum(plus_w, plus_u, plus_a, plus_nu), plus_body_rotation)
		var minus_h := _rotate(_momentum(minus_w, minus_u, minus_a, minus_nu), minus_body_rotation)
		var h_dot := M.scale(M.sub(plus_h, minus_h), 0.5 / eps)
		worst_momentum = maxf(worst_momentum, M.norm(M.sub(h_dot, moment)))
		for i in 2:
			var rotor_plus := _rotate(_rotor_h(i, plus_w, plus_u, plus_a, plus_nu), plus_body_rotation)
			var rotor_minus := _rotate(_rotor_h(i, minus_w, minus_u, minus_a, minus_nu), minus_body_rotation)
			var demand := M.sub(M.scale(M.sub(rotor_plus, rotor_minus), 0.5 / eps), external.slice(3 * i, 3 * i + 3))
			worst_actuator = maxf(worst_actuator, M.norm(M.sub(demand, out.actuator_torques.slice(3 * i, 3 * i + 3))))
			var p_plus: float = AXIAL[i] * (M.dot(plus_a.slice(3 * i, 3 * i + 3), M.add(plus_w, plus_nu.slice(3 * i, 3 * i + 3))) + plus_u[i] / RADII[i])
			var p_minus: float = AXIAL[i] * (M.dot(minus_a.slice(3 * i, 3 * i + 3), M.add(minus_w, minus_nu.slice(3 * i, 3 * i + 3))) + minus_u[i] / RADII[i])
			var expected_axial := M.dot(axes.slice(3 * i, 3 * i + 3), external.slice(3 * i, 3 * i + 3)) + internal[i]
			worst_axial = maxf(worst_axial, absf((p_plus - p_minus) / (2.0 * eps) - expected_axial))
		_check("analytic torque/power ledger closes %d" % trial, absf(out.power_residual) < 1e-12)
		if trial == 0:
			# Positive control: merely changing axes in the old fixed-axis solve
			# must fail the independent inertial momentum oracle.
			var axle := PackedFloat64Array()
			for i in 2:
				axle.append(M.dot(axes.slice(3 * i, 3 * i + 3), external.slice(3 * i, 3 * i + 3)) + internal[i])
			var naive := WC.evaluate(WC.prepare(_locked_tensor(axes), PackedFloat64Array(RADII), PackedFloat64Array(AXIAL), axes),
				omega, rims, moment, axle)
			var naive_plus_w := M.add(omega, M.scale(naive.angular_acceleration, eps))
			var naive_minus_w := M.sub(omega, M.scale(naive.angular_acceleration, eps))
			var naive_plus_u := rims.duplicate()
			var naive_minus_u := rims.duplicate()
			for i in 2:
				naive_plus_u[i] += eps * naive.derivative[i]
				naive_minus_u[i] -= eps * naive.derivative[i]
			var naive_plus_h := _rotate(_momentum(naive_plus_w, naive_plus_u, plus_a, plus_nu),
				M.add(M.scale(omega, eps), M.scale(naive.angular_acceleration, 0.5 * eps * eps)))
			var naive_minus_h := _rotate(_momentum(naive_minus_w, naive_minus_u, minus_a, minus_nu),
				M.add(M.scale(omega, -eps), M.scale(naive.angular_acceleration, 0.5 * eps * eps)))
			var missing_transport := M.norm(M.sub(M.scale(M.sub(naive_plus_h, naive_minus_h), 0.5 / eps), moment))
			_check("independent oracle rejects naive moving-axis substitution", missing_transport > 1e-3, str(missing_transport))
			print("GP-09b naive axis-substitution momentum residual_Nm=", missing_transport)
	_check("independent moving-axis finite-difference energy/work oracle", worst_power < 1e-7, str(worst_power))
	_check("independent inertial total momentum derivative oracle", worst_momentum < 1e-7, str(worst_momentum))
	_check("independent cyclic spin momentum derivative oracle", worst_axial < 1e-8, str(worst_axial))
	_check("independent inertial rotor actuator torque oracle", worst_actuator < 1e-7, str(worst_actuator))
	print("GP-09b moving-axis FD maxima: power_W=", worst_power, " inertial_momentum_Nm=", worst_momentum,
		" axial_torque_Nm=", worst_axial, " actuator_torque_Nm=", worst_actuator)


func _fixed_axis_limit() -> void:
	var axes := PackedFloat64Array(AXES)
	var locked := _locked_tensor(axes)
	var fixed := WC.prepare(locked, PackedFloat64Array(RADII), PackedFloat64Array(AXIAL), axes)
	var omega := M.v3(0.4, -0.6, 0.3)
	var rims := PackedFloat64Array([1.1, -0.7])
	var external := PackedFloat64Array([0.2, -0.1, 0.3, -0.3, 0.4, 0.1])
	var internal := PackedFloat64Array([-0.07, 0.04])
	var axle := PackedFloat64Array()
	for i in 2:
		axle.append(M.dot(axes.slice(3 * i, 3 * i + 3), external.slice(3 * i, 3 * i + 3)) + internal[i])
	var moment := M.v3(0.3, -0.4, 0.7)
	var reference := WC.evaluate(fixed, omega, rims, moment, axle)
	var zero := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var transport := WC.evaluate_transport(_prepared(), omega, rims, axes, zero, zero, moment, external, internal)
	_check("zero prescribed rates recover GP-09a angular/rim derivative", _near(transport.angular_acceleration, reference.angular_acceleration, 1e-14) \
		and _near(transport.derivative, reference.derivative, 1e-14))
	_check("fixed carriers perform exactly zero actuator work", transport.actuator_power == 0.0)
	_check("original fixed-axis law identity remains unchanged", WC.LAW == "fixed-axis-relative-rim-coupling-v1")


func _locked_tensor(axes: PackedFloat64Array) -> PackedFloat64Array:
	var tensor := PackedFloat64Array(CARRIER)
	for i in 2:
		var a := axes.slice(3 * i, 3 * i + 3)
		var difference: float = AXIAL[i] - TRANSVERSE[i]
		tensor[0] += TRANSVERSE[i] + difference * a[0] * a[0]
		tensor[1] += TRANSVERSE[i] + difference * a[1] * a[1]
		tensor[2] += TRANSVERSE[i] + difference * a[2] * a[2]
		tensor[3] += difference * a[0] * a[1]
		tensor[4] += difference * a[0] * a[2]
		tensor[5] += difference * a[1] * a[2]
	return tensor


func _rejections() -> void:
	_check("nonphysical axisymmetric J>2K rejects", not WC.prepare_transport(PackedFloat64Array(CARRIER), PackedFloat64Array([0.2]),
		PackedFloat64Array([0.2]), PackedFloat64Array([0.05])).ok)
	_check("nonphysical carrier tensor rejects", not WC.prepare_transport(PackedFloat64Array([1.0, 1.0, 3.0, 0.0, 0.0, 0.0]),
		PackedFloat64Array(RADII), PackedFloat64Array(AXIAL), PackedFloat64Array(TRANSVERSE)).ok)
	_check("zero transverse rotor inertia rejects", not WC.prepare_transport(PackedFloat64Array(CARRIER), PackedFloat64Array([0.2]),
		PackedFloat64Array([0.1]), PackedFloat64Array([0.0])).ok)
	var zeros := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	_check("mismatched rate layout rejects", not WC.evaluate_transport(_prepared(), M.v3(0.0, 0.0, 0.0), PackedFloat64Array([0.0, 0.0]),
		PackedFloat64Array(AXES), PackedFloat64Array(), zeros, M.v3(0.0, 0.0, 0.0), zeros, PackedFloat64Array([0.0, 0.0])).ok)
	var nonunit := PackedFloat64Array(AXES)
	nonunit[0] = 2.0
	_check("nonunit moving axle rejects", not WC.evaluate_transport(_prepared(), M.v3(0.0, 0.0, 0.0), PackedFloat64Array([0.0, 0.0]),
		nonunit, zeros, zeros, M.v3(0.0, 0.0, 0.0), zeros, PackedFloat64Array([0.0, 0.0])).ok)
	var invalid := zeros.duplicate()
	invalid[2] = NAN
	_check("nonfinite prescribed carrier acceleration rejects", not WC.evaluate_transport(_prepared(), M.v3(0.0, 0.0, 0.0), PackedFloat64Array([0.0, 0.0]),
		PackedFloat64Array(AXES), zeros, invalid, M.v3(0.0, 0.0, 0.0), zeros, PackedFloat64Array([0.0, 0.0])).ok)
	_check("fixed-axis preparation cannot silently select moving law", not WC.evaluate_transport({ok = true}, M.v3(0.0, 0.0, 0.0), PackedFloat64Array([0.0, 0.0]),
		PackedFloat64Array(AXES), zeros, zeros, M.v3(0.0, 0.0, 0.0), zeros, PackedFloat64Array([0.0, 0.0])).ok)


func _kernel_ledger() -> void:
	var original_rate := Engine.physics_ticks_per_second
	var previous_error := INF
	var prepared := _prepared()
	var body_inertia := PackedFloat64Array(CARRIER)
	var inverse := RB.inertia_inverse(body_inertia)
	var initial := RB.make_state(M.v3(0.0, 0.0, -5.0), M.v3(0.0, 0.0, 0.0),
		M.q_from_euler(0.2, -0.1, 0.3), M.v3(0.4, -0.6, 0.3))
	for rate in [120, 240, 480]:
		Engine.physics_ticks_per_second = rate
		var sim := Sim.new()
		sim.inertia = body_inertia
		sim.gravity = 0.0
		sim.continuous = PackedFloat64Array([0.7, -0.4, 0.0, 0.0]) # rims, actuator work, brake heat
		var model := VM.new()
		model.continuous_size = 4
		model.identity = {law = WC.TRANSPORT_LAW, fixture = "fixed-centers-prescribed-carriers"}
		model.stage = func(body: PackedFloat64Array, values: PackedFloat64Array, time: float) -> Dictionary:
			var motion := _mechanism(time)
			var internal := PackedFloat64Array([-0.03 * values[0], -0.02 * values[1]])
			var out := WC.evaluate_transport(prepared, body.slice(10, 13), values.slice(0, 2), motion.axes, motion.rates,
				motion.accels, M.v3(0.0, 0.0, 0.0), PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]), internal)
			var body_rate := RB.derivative(body, 1.0, body_inertia, inverse, M.v3(0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0), 0.0)
			for k in 3:
				body_rate[10 + k] = out.angular_acceleration[k]
			var local: PackedFloat64Array = out.derivative
			local.append(out.actuator_power)
			local.append(-out.internal_spin_power)
			return {loads = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]), derivative = local,
				body_derivative = body_rate, rotor_momentum = M.v3(0.0, 0.0, 0.0)}
		var installed := sim.set_model(model) and sim.reset(initial)
		_check("same-kernel transport reference installs at %d Hz" % rate, installed, sim.fault_reason)
		if not installed:
			sim.free()
			continue
		var motion0 := _mechanism(0.0)
		var e0 := _energy(initial.slice(10, 13), sim.continuous.slice(0, 2), motion0.axes, motion0.rates)
		var h0 := M.q_rotate(initial.slice(6, 10), _momentum(initial.slice(10, 13), sim.continuous.slice(0, 2), motion0.axes, motion0.rates))
		var max_energy := 0.0
		var max_momentum := 0.0
		var heat_monotonic := true
		var last_heat := 0.0
		for _tick in rate * 2:
			sim.step()
			var motion := _mechanism(sim.time())
			var total := _energy(sim.state.slice(10, 13), sim.continuous.slice(0, 2), motion.axes, motion.rates) \
				+ sim.continuous[3] - sim.continuous[2]
			max_energy = maxf(max_energy, absf(total - e0))
			var world_h := M.q_rotate(sim.state.slice(6, 10),
				_momentum(sim.state.slice(10, 13), sim.continuous.slice(0, 2), motion.axes, motion.rates))
			max_momentum = maxf(max_momentum, M.norm(M.sub(world_h, h0)))
			heat_monotonic = heat_monotonic and sim.continuous[3] >= last_heat
			last_heat = sim.continuous[3]
		_check("same-kernel prescribed carriers complete without fault %d" % rate, sim.tick == rate * 2 and sim.fault_reason.is_empty(), sim.fault_reason)
		_check("independent T+brake heat-actuator work closes %d" % rate, max_energy < 1e-7, str(max_energy))
		_check("inertial momentum conserved with moving carrier actuation %d" % rate, max_momentum < 1e-7, str(max_momentum))
		_check("brake heat monotonic and actuator work nonzero %d" % rate, heat_monotonic and sim.continuous[3] > 0.0 and absf(sim.continuous[2]) > 1e-4)
		_check("moving-axis refinement decreases conservation error %d" % rate, maxf(max_energy, max_momentum) < previous_error)
		previous_error = maxf(max_energy, max_momentum)
		var checkpoint := sim.checkpoint()
		for _tick in 8:
			sim.step()
		var expected_body := var_to_bytes(sim.state)
		var expected_local := var_to_bytes(sim.continuous)
		var restored := sim.restore_checkpoint(checkpoint)
		for _tick in 8:
			sim.step()
		_check("transport work/heat checkpoint repeat is byte-identical %d" % rate, restored \
			and var_to_bytes(sim.state) == expected_body and var_to_bytes(sim.continuous) == expected_local)
		print("GP-09b kernel rate_Hz=", rate, " energy_ledger_error_J=", max_energy, " inertial_momentum_error_Nms=", max_momentum)
		sim.free()
	Engine.physics_ticks_per_second = original_rate


func _mechanism(time: float) -> Dictionary:
	var first := _rotate(PackedFloat64Array(AXES).slice(0, 3), M.v3(0.0, 0.0, 0.8 * time + 0.1 * time * time))
	var second := _rotate(PackedFloat64Array(AXES).slice(3, 6), M.v3(-0.6 * time + 0.075 * time * time, 0.0, 0.0))
	first.append_array(second)
	return {axes = first, rates = PackedFloat64Array([0.0, 0.0, 0.8 + 0.2 * time, -0.6 + 0.15 * time, 0.0, 0.0]),
		accels = PackedFloat64Array([0.0, 0.0, 0.2, 0.15, 0.0, 0.0])}


func _near(a: PackedFloat64Array, b: PackedFloat64Array, tolerance: float) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not is_finite(a[i]) or not is_finite(b[i]) or absf(a[i] - b[i]) > tolerance:
			return false
	return true

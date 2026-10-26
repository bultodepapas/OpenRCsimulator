# GP-09: independent cross-term energy gradients, angular momentum and passivity.
extends SceneTree

const WC := preload("res://physics/wheel_coupling.gd")
const Wheels := preload("res://physics/ground_wheels.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const Sim := preload("res://sim/simulation.gd")
const VM := preload("res://sim/vehicle_model.gd")

var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)


func _initialize() -> void:
	_carrier_moment_fixture()
	_arbitrary_axis_oracles()
	_contact_virtual_work()
	_input_rejection()
	_kernel_reference()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _one() -> Dictionary:
	return WC.prepare(PackedFloat64Array([1.0, 1.0, 1.0, 0.0, 0.0, 0.0]),
		PackedFloat64Array([0.2]), PackedFloat64Array([0.1]), PackedFloat64Array([0.0, -1.0, 0.0]))


func _carrier_moment_fixture() -> void:
	var state := RB.make_state(M.v3(0.0, 0.0, -0.04), M.v3(2.95, 0.0, 0.0),
		M.quat(1.0, 0.0, 0.0, 0.0), M.v3(0.0, 1.0, 0.0))
	var gear := {reach = 0.1, side_friction = 0.5, rolling_resistance = 0.0,
		contacts = [{position = M.v3(0.0, 0.0, 0.05), stiffness = 100.0, damping = 1.0,
		wheel_radius = 0.2, wheel_inertia = 0.1, spin_relaxation = 0.03}]}
	var legacy := Wheels.evaluate(state, gear, 0.0, PackedFloat64Array(), PackedFloat64Array(), PackedFloat64Array([3.0]))
	_check("counterexample executes legacy zero-slip contact", legacy.wheels.size() == 1 \
		and absf(legacy.wheels[0].longitudinal_slip) < 1e-14 and legacy.derivative[0] == 0.0)
	var inertia := PackedFloat64Array([1.0, 1.0, 1.0, 0.0, 0.0, 0.0])
	var old := RB.derivative(state, 1.0, inertia, RB.inertia_inverse(inertia), legacy.loads.slice(0, 3),
		M.add(M.v3(0.0, -1.0, 0.0), legacy.loads.slice(3, 6)), 0.0)
	var old_power: float = (-0.5) * old[11] + 7.0 * legacy.derivative[0]
	_check("actual old source reproduces +1.5 W unexplained residual", absf(old_power - (-1.0) - 1.5) < 1e-14)
	print("GP-09 legacy source instantaneous power residual: ", old_power + 1.0, " W")
	var prepared := _one()
	_check("declared once-included rotor partition is SPD", prepared.ok)
	var new := WC.evaluate(prepared, M.v3(0.0, 1.0, 0.0), PackedFloat64Array([3.0]),
		M.v3(0.0, -1.0, 0.0), PackedFloat64Array([0.0]))
	_check("coupled pitch acceleration matches independent -1/0.9", new.ok and absf(new.angular_acceleration[1] + 1.0 / 0.9) < 1e-14)
	_check("free wheel retains absolute axial spin under carrier torque", absf(new.derivative[0] - 0.2 * new.angular_acceleration[1]) < 1e-14)
	var new_power: float = (-0.5) * new.angular_acceleration[1] + 7.0 * new.derivative[0]
	_check("coupled cross-term energy power equals -1 W", absf(new_power + 1.0) < 1e-14)
	# Isolated airborne brake: no load/grip needed in the generalized equations.
	var braking := WC.evaluate(prepared, M.v3(0.0, 0.0, 0.0), PackedFloat64Array([3.0]),
		M.v3(0.0, 0.0, 0.0), PackedFloat64Array([-0.4]))
	var brake_power: float = -1.5 * braking.angular_acceleration[1] + 7.5 * braking.derivative[0]
	_check("airborne internal brake dissipates tau*sigma", absf(brake_power + 6.0) < 1e-13)
	_check("internal brake has zero total angular momentum derivative", absf(braking.angular_acceleration[1] - 0.5 * braking.derivative[0]) < 1e-14)
	var no_relative_spin := WC.evaluate(prepared, M.v3(0.0, 1.0, 0.0), PackedFloat64Array([0.0]),
		M.v3(0.0, -1.0, 0.0), PackedFloat64Array([0.0]))
	_check("zero relative rim does not suppress carrier/wheel coupling", absf(no_relative_spin.derivative[0] + 0.2 / 0.9) < 1e-14)


# Independent scalar energy written with absolute spin and residual carrier tensor:
# 1/2*w^T*(I-sum J aa^T)*w + sum 1/2*J*(a.w+u/R)^2.
# This form does not reuse the production generalized matrix or factor.
func _energy(j: PackedFloat64Array, radii: PackedFloat64Array, inertias: PackedFloat64Array,
		axes: PackedFloat64Array, omega: PackedFloat64Array, rims: PackedFloat64Array) -> float:
	var energy := 0.5 * (j[0] * omega[0] * omega[0] + j[1] * omega[1] * omega[1] + j[2] * omega[2] * omega[2]) \
		+ j[3] * omega[0] * omega[1] + j[4] * omega[0] * omega[2] + j[5] * omega[1] * omega[2]
	for i in rims.size():
		var projected := axes[3 * i] * omega[0] + axes[3 * i + 1] * omega[1] + axes[3 * i + 2] * omega[2]
		var absolute := projected + rims[i] / radii[i]
		energy += 0.5 * inertias[i] * (absolute * absolute - projected * projected)
	return energy


func _arbitrary_axis_oracles() -> void:
	var j := PackedFloat64Array([1.2, 1.7, 2.1, 0.03, -0.04, 0.06])
	var radii := PackedFloat64Array([0.2, 0.15, 0.1])
	var inertias := PackedFloat64Array([0.1, 0.08, 0.02])
	var axes := PackedFloat64Array([0.6, -0.8, 0.0, 0.0, 0.6, 0.8, 1.0, 0.0, 0.0])
	var prepared := WC.prepare(j, radii, inertias, axes)
	_check("nonparallel arbitrary axles/offdiagonal inertia prepare", prepared.ok)
	var worst_energy := 0.0
	var worst_momentum := 0.0
	var worst_brake := 0.0
	for trial in 20:
		var omega := M.v3(0.17 * trial - 1.3, 0.23 * trial - 2.0, -0.11 * trial + 0.8)
		var rims := PackedFloat64Array([1.0 + trial * 0.1, -0.7 - trial * 0.05, 0.3])
		var torque := M.v3(0.7, -1.1, 0.6)
		var axle := PackedFloat64Array([-0.2, 0.13, -0.04])
		var out := WC.evaluate(prepared, omega, rims, torque, axle)
		var alpha: PackedFloat64Array = out.angular_acceleration
		var rim_rate: PackedFloat64Array = out.derivative
		var eps := 1e-5
		var plus := omega.duplicate()
		var minus := omega.duplicate()
		var rim_plus := rims.duplicate()
		var rim_minus := rims.duplicate()
		for k in 3:
			plus[k] += eps * alpha[k]
			minus[k] -= eps * alpha[k]
			rim_plus[k] += eps * rim_rate[k]
			rim_minus[k] -= eps * rim_rate[k]
		var power := (_energy(j, radii, inertias, axes, plus, rim_plus) - _energy(j, radii, inertias, axes, minus, rim_minus)) / (2.0 * eps)
		var expected := M.dot(torque, omega)
		for k in 3:
			expected += axle[k] * rims[k] / radii[k]
		worst_energy = maxf(worst_energy, absf(power - expected))
		var h := RB.inertia_mul(j, omega)
		var hdot := RB.inertia_mul(j, alpha)
		for wheel in 3:
			for k in 3:
				h[k] += inertias[wheel] / radii[wheel] * rims[wheel] * axes[3 * wheel + k]
				hdot[k] += inertias[wheel] / radii[wheel] * rim_rate[wheel] * axes[3 * wheel + k]
		var residual := M.sub(M.add(hdot, M.cross(omega, h)), torque)
		for k in 3:
			worst_momentum = maxf(worst_momentum, absf(residual[k]))
		# This fixture is purely internal braking: each axle opposes relative spin.
		var internal := WC.evaluate(prepared, omega, rims, M.v3(0.0, 0.0, 0.0), axle)
		var derivative_power := M.dot(h, internal.angular_acceleration)
		var braking_power := 0.0
		for wheel in 3:
			var a_dot_w := 0.0
			for k in 3:
				a_dot_w += axes[3 * wheel + k] * omega[k]
			derivative_power += inertias[wheel] / radii[wheel] * (a_dot_w + rims[wheel] / radii[wheel]) * internal.derivative[wheel]
			braking_power += axle[wheel] * rims[wheel] / radii[wheel]
		worst_brake = maxf(worst_brake, absf(derivative_power - braking_power))
		_check("arbitrary-axis brake passivity trial %d" % trial, derivative_power <= 0.0)
	_check("independent finite-difference energy gradient balances arbitrary-axis power", worst_energy < 1e-8, str(worst_energy))
	_check("total angular momentum includes body transport/gyroscopic term", worst_momentum < 1e-13, str(worst_momentum))
	_check("arbitrary-axis internal brake energy loss matches relative work", worst_brake < 1e-13, str(worst_brake))
	print("GP-09 arbitrary-axis oracle maxima: power_fd_W=", worst_energy,
		" momentum_Nm=", worst_momentum, " brake_power_W=", worst_brake)
	var omega := M.v3(0.3, -0.5, 0.7)
	var other := M.v3(0.2, 0.4, -0.1)
	var with_other := WC.evaluate(prepared, omega, PackedFloat64Array([0.0, 0.0, 0.0]),
		M.cross(omega, other), PackedFloat64Array([0.0, 0.0, 0.0]), other)
	var without_other := WC.evaluate(prepared, omega, PackedFloat64Array([0.0, 0.0, 0.0]),
		M.v3(0.0, 0.0, 0.0), PackedFloat64Array([0.0, 0.0, 0.0]))
	_check("separately owned propeller momentum retains its gyro reaction", M.dot(M.sub(with_other.angular_acceleration, without_other.angular_acceleration),
		M.sub(with_other.angular_acceleration, without_other.angular_acceleration)) < 1e-27)


func _input_rejection() -> void:
	var j := PackedFloat64Array([1.0, 1.0, 1.0, 0.0, 0.0, 0.0])
	_check("impossible once-included rotor inertia split rejects", not WC.prepare(j, PackedFloat64Array([0.2]),
		PackedFloat64Array([1.1]), M.v3(0.0, -1.0, 0.0)).ok)
	_check("nonunit axle rejects", not WC.prepare(j, PackedFloat64Array([0.2]), PackedFloat64Array([0.1]), M.v3(0.0, -2.0, 0.0)).ok)
	_check("zero radius rejects", not WC.prepare(j, PackedFloat64Array([0.0]), PackedFloat64Array([0.1]), M.v3(0.0, -1.0, 0.0)).ok)
	_check("nonfinite wheel inertia rejects", not WC.prepare(j, PackedFloat64Array([0.2]), PackedFloat64Array([NAN]), M.v3(0.0, -1.0, 0.0)).ok)
	_check("invalid stage shape rejects", not WC.evaluate(_one(), M.v3(0.0, 0.0, 0.0), PackedFloat64Array(),
		M.v3(0.0, 0.0, 0.0), PackedFloat64Array([0.0])).ok)


# Retained force law, isolated flat/no-camber geometry: external tire force is
# represented at the contact arm and by its axle torque through virtual work.
# This does not qualify legacy point geometry at camber or moving axles.
func _contact_virtual_work() -> void:
	var prepared := _one()
	var arm := M.v3(0.1, 0.2, 0.05)
	var omega := M.v3(0.2, 0.5, 0.1)
	var gear := {reach = 0.1, side_friction = 0.5, rolling_resistance = 0.02,
		contacts = [{position = arm, stiffness = 100.0, damping = 1.0,
		wheel_radius = 0.2, wheel_inertia = 0.1, spin_relaxation = 0.03, brake_torque = 0.1}]}
	var worst := 0.0
	for direction in [-1.0, 1.0]:
		var velocity := M.v3(direction * 4.0, 0.4, -0.01)
		var state := RB.make_state(M.v3(0.0, 0.0, -0.04), velocity,
			M.quat(1.0, 0.0, 0.0, 0.0), omega)
		var rim: float = direction * 2.0
		var old := Wheels.evaluate(state, gear, 0.0, PackedFloat64Array(), PackedFloat64Array(), PackedFloat64Array([rim]), 0.7)
		var contact: Dictionary = old.wheels[0]
		var tangential := M.v3(contact.longitudinal_force, contact.lateral_force, 0.0)
		var axle: float = -0.2 * contact.slip_force - contact.brake_torque
		var coupled := WC.evaluate(prepared, omega, PackedFloat64Array([rim]), M.cross(arm, tangential), PackedFloat64Array([axle]))
		var h := M.v3(omega[0], omega[1] - 0.5 * rim, omega[2])
		var rotor_gradient: float = -0.5 * omega[1] + 2.5 * rim
		var rate: float = M.dot(velocity, tangential) + M.dot(h, coupled.angular_acceleration) + rotor_gradient * coupled.derivative[0]
		var contact_velocity := M.add(velocity, M.cross(omega, arm))
		var slip_power: float = contact.slip_force * contact.longitudinal_slip \
			+ contact.rolling_force * contact.long_speed + contact.lateral_force * contact_velocity[1] - contact.brake_torque * rim / 0.2
		worst = maxf(worst, absf(rate - slip_power))
		_check("retained finite-slope tire/brake power is passive direction %s" % direction, rate <= 0.0)
	_check("single contact force/axle virtual work closes without spin patch", worst < 1e-13, str(worst))


# A synthetic VehicleModel uses exactly the production Simulation joint-stage
# transaction and RK4. It has no prop shaft, moving axis, tire geometry or fuel.
# Those combinations require separate qualification before session migration.
func _kernel_reference() -> void:
	var original_rate := Engine.physics_ticks_per_second
	var j := PackedFloat64Array([1.2, 1.7, 2.1, 0.03, -0.04, 0.06])
	var radii := PackedFloat64Array([0.2, 0.15])
	var inertias := PackedFloat64Array([0.1, 0.08])
	var axes := PackedFloat64Array([0.6, -0.8, 0.0, 0.0, 0.6, 0.8])
	var prepared := WC.prepare(j, radii, inertias, axes)
	var inverse := RB.inertia_inverse(j)
	var initial := RB.make_state(M.v3(0.0, 0.0, -5.0), M.v3(0.7, -0.3, 0.2),
		M.q_from_euler(0.3, -0.2, 0.1), M.v3(0.7, -0.4, 0.6))
	var previous_error := INF
	for braking in [false, true]:
		previous_error = INF
		for rate in [120, 240, 480]:
			Engine.physics_ticks_per_second = rate
			var sim := Sim.new()
			sim.inertia = j
			sim.gravity = 0.0
			sim.continuous = PackedFloat64Array([2.1, -1.3, 0.0]) # rims, accumulated brake heat
			var model := VM.new()
			model.continuous_size = 3
			model.identity = {law = WC.LAW, fixture = "fixed-axes-no-prop-closed-inventory"}
			model.stage = func(body: PackedFloat64Array, values: PackedFloat64Array, _time: float) -> Dictionary:
				var rims := values.slice(0, 2)
				var axle := PackedFloat64Array([-0.08 * rims[0], -0.08 * rims[1]]) if braking else PackedFloat64Array([0.0, 0.0])
				var coupled := WC.evaluate(prepared, body.slice(10, 13), rims, M.v3(0.0, 0.0, 0.0), axle)
				var body_rate := RB.derivative(body, 1.0, j, inverse, M.v3(0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0), 0.0)
				for k in 3:
					body_rate[10 + k] = coupled.angular_acceleration[k]
				var local_rate: PackedFloat64Array = coupled.derivative
				local_rate.append(-axle[0] * rims[0] / radii[0] - axle[1] * rims[1] / radii[1])
				return {loads = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]),
					derivative = local_rate, body_derivative = body_rate, rotor_momentum = M.v3(0.0, 0.0, 0.0)}
			var installed := sim.set_model(model) and sim.reset(initial)
			_check("same-kernel fixed-axis reference installs %s/%d" % [braking, rate], installed, sim.fault_reason)
			if not installed:
				sim.free()
				continue
			var start_energy := _energy(j, radii, inertias, axes, initial.slice(10, 13), sim.continuous.slice(0, 2))
			var start_h := _world_momentum(j, radii, inertias, axes, sim.state, sim.continuous)
			var max_energy := 0.0
			var max_momentum := 0.0
			var heat_monotonic := true
			var last_heat := 0.0
			for _tick in rate * 2:
				sim.step()
				var total := _energy(j, radii, inertias, axes, sim.state.slice(10, 13), sim.continuous.slice(0, 2)) + sim.continuous[2]
				max_energy = maxf(max_energy, absf(total - start_energy))
				var h := _world_momentum(j, radii, inertias, axes, sim.state, sim.continuous)
				for k in 3:
					max_momentum = maxf(max_momentum, absf(h[k] - start_h[k]))
				heat_monotonic = heat_monotonic and sim.continuous[2] >= last_heat
				last_heat = sim.continuous[2]
			_check("joint-stage integration completes without fault %s/%d" % [braking, rate], sim.tick == rate * 2 and sim.fault_reason.is_empty(), sim.fault_reason)
			_check("cross-term energy plus brake heat closes %s/%d" % [braking, rate], max_energy < 1e-8, str(max_energy))
			_check("world total angular momentum conserved %s/%d" % [braking, rate], max_momentum < 1e-8, str(max_momentum))
			_check("airborne brake heat is monotonic %s/%d" % [braking, rate], heat_monotonic and (sim.continuous[2] > 0.0 if braking else sim.continuous[2] == 0.0))
			_check("refinement reduces integrated conservation error %s/%d" % [braking, rate], maxf(max_energy, max_momentum) < previous_error)
			print("GP-09 kernel braking=", braking, " rate_Hz=", rate, " energy_heat_error_J=", max_energy,
				" world_momentum_error_Nms=", max_momentum)
			previous_error = maxf(max_energy, max_momentum)
			var checkpoint := sim.checkpoint()
			for _tick in 8:
				sim.step()
			var expected_body := var_to_bytes(sim.state)
			var expected_local := var_to_bytes(sim.continuous)
			var restored := sim.restore_checkpoint(checkpoint)
			for _tick in 8:
				sim.step()
			_check("joint body/rim/heat checkpoint repeat is byte-identical %s/%d" % [braking, rate], restored \
				and var_to_bytes(sim.state) == expected_body and var_to_bytes(sim.continuous) == expected_local)
			sim.free()
	Engine.physics_ticks_per_second = original_rate


func _world_momentum(j: PackedFloat64Array, radii: PackedFloat64Array, inertias: PackedFloat64Array,
		axes: PackedFloat64Array, body: PackedFloat64Array, local: PackedFloat64Array) -> PackedFloat64Array:
	var h := RB.inertia_mul(j, body.slice(10, 13))
	for wheel in radii.size():
		for k in 3:
			h[k] += inertias[wheel] / radii[wheel] * local[wheel] * axes[3 * wheel + k]
	return M.q_rotate(body.slice(6, 10), h)

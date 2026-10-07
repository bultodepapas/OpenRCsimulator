# H11: characterize coupled landing-gear modes and the RK4 contact policy at 240 Hz.
# Uses production Ground.loads and Simulation/RK4; no contact-law implementation is duplicated.
# Run: godot --headless --path . --script res://tests/test_contact_policy.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Sim := preload("res://sim/simulation.gd")
const Ground := preload("res://physics/ground_contact.gd")
const AD := preload("res://physics/aircraft_data.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")

const AIRCRAFT_PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const G := 9.80665
# This is an evidence boundary for the tested Stik contact family below, not a
# universal damping/layout limit. AircraftData's existing loader limit stays 0.1.
const SUPPORT_RHO := 0.3
const ENERGY_GAIN_TOLERANCE_J := 1e-9
const RINGDOWN_SECONDS := 1.0
const TOUCHDOWN_SECONDS := 1.0

var _failures := 0
var _count := 0
var _results: Array[Dictionary] = []


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not ok:
		_failures += 1


func _zero3() -> Array:
	return [PackedFloat64Array([0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0])]


func _make_case(label: String, mass: float, target_sag: float, zeta: float, base: Dictionary, keep_base: bool) -> Dictionary:
	var base_mass: float = base.mass_kg
	var size_scale := pow(mass / base_mass, 1.0 / 3.0) if not keep_base else 1.0
	var inertia_scale := (mass / base_mass) * size_scale * size_scale
	var inertia: PackedFloat64Array = base.inertia.duplicate()
	for i in inertia.size():
		inertia[i] *= inertia_scale
	var gear: Dictionary = base.landing_gear.duplicate(true)
	var old_total_k := 0.0
	for contact in gear.contacts:
		old_total_k += float(contact.stiffness)
	var stiffness_scale := 1.0 if keep_base else mass * G / target_sag / old_total_k
	for contact in gear.contacts:
		var position: PackedFloat64Array = contact.position
		contact.position = M.v3(position[0] * size_scale, position[1] * size_scale, position[2] * size_scale)
		contact.max_compression = float(contact.max_compression) * size_scale
		contact.stiffness = float(contact.stiffness) * stiffness_scale
		# E1b: the damping onset is a fraction of the static compression, which scales with load / stiffness.
		contact.damping_onset = float(contact.get("damping_onset", 0.0)) * (mass / base_mass) / stiffness_scale
		if not keep_base:
			contact.damping = 2.0 * zeta * sqrt(float(contact.stiffness) * mass / gear.contacts.size())
	gear.reach = float(gear.reach) * size_scale
	# Disable tyre forces so the measured energy belongs only to the rigid body, gravity and normal gear springs.
	gear.side_friction = 0.0
	gear.rolling_resistance = 0.0
	var total_k := 0.0
	for contact in gear.contacts:
		total_k += float(contact.stiffness)
	var sag := mass * G / total_k
	return {
		"name": label,
		"mass": mass,
		"inertia": inertia,
		"gear": gear,
		"size_scale": size_scale,
		"target_sag": sag,
		"zeta": zeta,
		"scalar_omega": sqrt(total_k / mass),
	}


func _matrix_multiply(a: Array, b: Array) -> Array:
	var result := _zero3()
	for row in 3:
		for col in 3:
			var sum := 0.0
			for k in 3:
				sum += float(a[row][k]) * float(b[k][col])
			result[row][col] = sum
	return result


func _transpose3(a: Array) -> Array:
	var result := _zero3()
	for row in 3:
		for col in 3:
			result[row][col] = a[col][row]
	return result


func _effective_roll_pitch_inertia(inertia: PackedFloat64Array) -> PackedFloat64Array:
	# Gear forces have no yaw torque or yaw stiffness. Eliminate the free yaw
	# acceleration from the full body inertia tensor before forming roll/pitch modes.
	var izz: float = inertia[2]
	assert(izz > 0.0)
	return PackedFloat64Array([
		inertia[0] - inertia[4] * inertia[4] / izz,
		inertia[1] - inertia[5] * inertia[5] / izz,
		inertia[3] - inertia[4] * inertia[5] / izz,
	])


func _stiffness_matrix(gear: Dictionary, contact_mask: int) -> Array:
	var matrix := _zero3()
	for i in gear.contacts.size():
		if (contact_mask & (1 << i)) == 0:
			continue
		var contact: Dictionary = gear.contacts[i]
		var r: PackedFloat64Array = contact.position
		# Small vertical displacement at a wheel: dz + y·roll − x·pitch.
		var jacobian := PackedFloat64Array([1.0, r[1], -r[0]])
		for row in 3:
			for col in 3:
				matrix[row][col] += float(contact.stiffness) * jacobian[row] * jacobian[col]
	return matrix


func _mass_whitened_stiffness(k: Array, mass: float, inertia: PackedFloat64Array) -> Array:
	# The full generalized mass includes free yaw. Vertical wheel forces have zero yaw torque,
	# so first Schur-eliminate yaw, then compute L⁻¹ K L⁻ᵀ for heave/roll/pitch.
	var effective := _effective_roll_pitch_inertia(inertia)
	var l11 := sqrt(effective[0])
	var l21 := effective[2] / l11
	var l22_sq := effective[1] - l21 * l21
	assert(mass > 0.0 and l11 > 0.0 and l22_sq > 0.0)
	var l22 := sqrt(l22_sq)
	var inverse_l := _zero3()
	inverse_l[0][0] = 1.0 / sqrt(mass)
	inverse_l[1][1] = 1.0 / l11
	inverse_l[2][1] = -l21 / (l11 * l22)
	inverse_l[2][2] = 1.0 / l22
	return _matrix_multiply(_matrix_multiply(inverse_l, k), _transpose3(inverse_l))


func _check_coupled_inertia_reference() -> void:
	# Full tensor [Jxx,Jyy,Jzz,Jxy,Jxz,Jyz]. Eliminating yaw gives the known
	# roll/pitch block [[4.75,1.3],[1.3,6.0]]. For Krot=diag(19,12),
	# det(K−λM)=0 has λmax=4.479892739585835; heave λ=1 is lower.
	var tensor := PackedFloat64Array([5.0, 7.0, 4.0, 0.8, 1.0, -2.0])
	var effective := _effective_roll_pitch_inertia(tensor)
	var effective_ok := absf(effective[0] - 4.75) < 1e-14 \
		and absf(effective[1] - 6.0) < 1e-14 and absf(effective[2] - 1.3) < 1e-14
	_check("free-yaw inertia Schur complement matches the analytic tensor reference", effective_ok,
		"effective Ixx %.12f, Iyy %.12f, Ixy %.12f" % [effective[0], effective[1], effective[2]])
	var stiffness := _zero3()
	stiffness[0][0] = 2.0
	stiffness[1][1] = 19.0
	stiffness[2][2] = 12.0
	var actual_lambda := _largest_symmetric_eigenvalue(_mass_whitened_stiffness(stiffness, 2.0, tensor))
	var expected_lambda := 4.479892739585835
	var reference_ok := absf(actual_lambda - expected_lambda) < 1e-12
	_check("coupled mode eigenvalue matches the analytic full-inertia reference", reference_ok,
		"λmax %.15f, expected %.15f" % [actual_lambda, expected_lambda])
	_results.append({
		"reference_check": "full inertia tensor with free yaw",
		"tensor_jxx_jyy_jzz_jxy_jxz_jyz": tensor,
		"effective_roll_pitch_jxx_jyy_jxy": effective,
		"expected_lambda_max": expected_lambda,
		"observed_lambda_max": actual_lambda,
	})


func _largest_symmetric_eigenvalue(matrix: Array) -> float:
	var a := _zero3()
	for row in 3:
		for col in 3:
			a[row][col] = matrix[row][col]
	for _iteration in 32:
		var p := 0
		var q := 1
		var offdiag := absf(float(a[0][1]))
		if absf(float(a[0][2])) > offdiag:
			p = 0
			q = 2
			offdiag = absf(float(a[0][2]))
		if absf(float(a[1][2])) > offdiag:
			p = 1
			q = 2
			offdiag = absf(float(a[1][2]))
		if offdiag < 1e-14:
			break
		var apq: float = a[p][q]
		var tau := (float(a[q][q]) - float(a[p][p])) / (2.0 * apq)
		var sign_tau := 1.0 if tau >= 0.0 else -1.0
		var t := sign_tau / (absf(tau) + sqrt(1.0 + tau * tau))
		var c := 1.0 / sqrt(1.0 + t * t)
		var s := t * c
		var app: float = a[p][p]
		var aqq: float = a[q][q]
		a[p][p] = app - t * apq
		a[q][q] = aqq + t * apq
		a[p][q] = 0.0
		a[q][p] = 0.0
		for k in 3:
			if k == p or k == q:
				continue
			var akp: float = a[k][p]
			var akq: float = a[k][q]
			a[k][p] = c * akp - s * akq
			a[p][k] = a[k][p]
			a[k][q] = s * akp + c * akq
			a[q][k] = a[k][q]
	return maxf(float(a[0][0]), maxf(float(a[1][1]), float(a[2][2])))


func _coupled_modes(case_data: Dictionary) -> Dictionary:
	var gear: Dictionary = case_data.gear
	var maximum_omega := 0.0
	var limiting_mask := 0
	for mask in range(1, 1 << gear.contacts.size()):
		var k := _stiffness_matrix(gear, mask)
		var whitened := _mass_whitened_stiffness(k, float(case_data.mass), case_data.inertia)
		var eigenvalue := _largest_symmetric_eigenvalue(whitened)
		var omega := sqrt(maxf(0.0, eigenvalue))
		if omega > maximum_omega:
			maximum_omega = omega
			limiting_mask = mask
	return {
		"omega_max": maximum_omega,
		"rho_240": maximum_omega / 240.0,
		"limiting_contact_mask": limiting_mask,
		"scalar_rho_240": float(case_data.scalar_omega) / 240.0,
	}


func _make_sim(case_data: Dictionary) -> Node:
	var simulation: Node = Sim.new()
	simulation.mass = case_data.mass
	simulation.inertia = case_data.inertia.duplicate()
	var gear: Dictionary = case_data.gear
	simulation.loads = func(state: PackedFloat64Array, _time: float) -> PackedFloat64Array:
		var loads := Ground.loads(state, gear)
		return loads if not loads.is_empty() else PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	return simulation


func _initial_drop_state(case_data: Dictionary, gap: float, sink_speed: float) -> PackedFloat64Array:
	var gear: Dictionary = case_data.gear
	var contact_down := 0.0
	for contact in gear.contacts:
		contact_down -= float(contact.position[2])
	contact_down /= gear.contacts.size()
	return RB.make_state(M.v3(0.0, 0.0, contact_down - gap), M.v3(0.0, 0.0, sink_speed), M.q_identity(), M.v3(0.0, 0.0, 0.0))


func _contact_mask(state: PackedFloat64Array, gear: Dictionary) -> int:
	var compressions: PackedFloat64Array = Ground.compressions(state, gear)
	var mask := 0
	for i in compressions.size():
		if compressions[i] > 0.0:
			mask |= 1 << i
	return mask


func _mechanical_energy(state: PackedFloat64Array, mass: float, inertia: PackedFloat64Array, gear: Dictionary) -> float:
	var velocity := M.v3(state[RB.VEL], state[RB.VEL + 1], state[RB.VEL + 2])
	var rates := M.v3(state[RB.RATE], state[RB.RATE + 1], state[RB.RATE + 2])
	return 0.5 * mass * M.dot(velocity, velocity) + 0.5 * M.dot(rates, RB.inertia_mul(inertia, rates)) \
		- mass * G * state[RB.POS + 2] + Ground.spring_energy(state, gear)


func _simulate(case_data: Dictionary, initial: PackedFloat64Array, hz: int, seconds: float, capture := true) -> Dictionary:
	Engine.physics_ticks_per_second = hz
	var simulation := _make_sim(case_data)
	simulation.reset(initial)
	var gear: Dictionary = case_data.gear
	var snapshots: Array[PackedFloat64Array] = []
	var energy_before := _mechanical_energy(simulation.state, case_data.mass, case_data.inertia, gear)
	var maximum_energy_gain := -INF
	var previous_mask := _contact_mask(simulation.state, gear)
	var switches := 0
	var maximum_contacts := 0
	for i in gear.contacts.size():
		if (previous_mask & (1 << i)) != 0:
			maximum_contacts += 1
	var ticks := roundi(seconds * hz)
	for _tick in ticks:
		simulation.step()
		var energy := _mechanical_energy(simulation.state, case_data.mass, case_data.inertia, gear)
		maximum_energy_gain = maxf(maximum_energy_gain, energy - energy_before)
		energy_before = energy
		var active_mask := _contact_mask(simulation.state, gear)
		if active_mask != previous_mask:
			switches += 1
		previous_mask = active_mask
		var active_count := 0
		for i in gear.contacts.size():
			if (active_mask & (1 << i)) != 0:
				active_count += 1
		maximum_contacts = maxi(maximum_contacts, active_count)
		if capture and (_tick + 1) % maxi(1, roundi(hz / 20.0)) == 0:
			snapshots.append(simulation.state.duplicate())
	var outcome := {
		"state": simulation.state.duplicate(),
		"snapshots": snapshots,
		"fault": simulation.fault_reason,
		"max_energy_gain": maximum_energy_gain,
		"contact_switches": switches,
		"max_contacts": maximum_contacts,
	}
	simulation.free()
	return outcome


func _state_difference(a: PackedFloat64Array, b: PackedFloat64Array, case_data: Dictionary, omega: float) -> Dictionary:
	var position_error := 0.0
	var velocity_error := 0.0
	var attitude_dot := 0.0
	var rate_error := 0.0
	for i in 3:
		position_error += (a[RB.POS + i] - b[RB.POS + i]) ** 2
		velocity_error += (a[RB.VEL + i] - b[RB.VEL + i]) ** 2
		rate_error += (a[RB.RATE + i] - b[RB.RATE + i]) ** 2
	for i in 4:
		attitude_dot += a[RB.ATT + i] * b[RB.ATT + i]
	var attitude_sign := 1.0 if attitude_dot >= 0.0 else -1.0
	var attitude_difference_sq := 0.0
	for i in 4:
		var q_delta: float = a[RB.ATT + i] - attitude_sign * b[RB.ATT + i]
		attitude_difference_sq += q_delta * q_delta
	var attitude_error := 2.0 * sqrt(attitude_difference_sq)
	position_error = sqrt(position_error)
	velocity_error = sqrt(velocity_error)
	rate_error = sqrt(rate_error)
	var sag: float = case_data.target_sag
	var arm := 0.0
	for contact in case_data.gear.contacts:
		var r: PackedFloat64Array = contact.position
		arm = maxf(arm, sqrt(r[0] * r[0] + r[1] * r[1]))
	var angle_scale := sag / maxf(arm, 0.01)
	var normalized := sqrt((position_error / sag) ** 2 + (velocity_error / (omega * sag)) ** 2
		+ (attitude_error / angle_scale) ** 2 + (rate_error / omega) ** 2)
	return {
		"position_m": position_error,
		"velocity_mps": velocity_error,
		"attitude_rad": attitude_error,
		"rate_radps": rate_error,
		"normalized": normalized,
	}


func _trajectory_difference(a: Array[PackedFloat64Array], b: Array[PackedFloat64Array], case_data: Dictionary, omega: float) -> Dictionary:
	assert(a.size() == b.size())
	var peak := {"position_m": 0.0, "velocity_mps": 0.0, "attitude_rad": 0.0, "rate_radps": 0.0, "normalized": 0.0, "time_s": 0.0}
	for i in a.size():
		var difference := _state_difference(a[i], b[i], case_data, omega)
		peak.position_m = maxf(float(peak.position_m), float(difference.position_m))
		peak.velocity_mps = maxf(float(peak.velocity_mps), float(difference.velocity_mps))
		peak.attitude_rad = maxf(float(peak.attitude_rad), float(difference.attitude_rad))
		peak.rate_radps = maxf(float(peak.rate_radps), float(difference.rate_radps))
		if float(difference.normalized) > float(peak.normalized):
			peak.normalized = difference.normalized
			peak.time_s = float(i + 1) / 20.0
	return peak


func _settled_state(case_data: Dictionary) -> Dictionary:
	var initial := _initial_drop_state(case_data, 0.05 * float(case_data.size_scale), 0.0)
	return _simulate(case_data, initial, 960, 3.0, false)


func _run_ringdown(case_data: Dictionary, modes: Dictionary, supported: bool) -> Dictionary:
	var settled := _settled_state(case_data)
	var initial: PackedFloat64Array = settled.state.duplicate()
	initial[RB.POS + 2] += 0.20 * float(case_data.target_sag)
	var delta_attitude := M.q_from_euler(0.0, -0.003, 0.004)
	var base_attitude := PackedFloat64Array([initial[RB.ATT], initial[RB.ATT + 1], initial[RB.ATT + 2], initial[RB.ATT + 3]])
	var perturbed_attitude := M.q_normalized(M.q_mul(base_attitude, delta_attitude))
	for i in 4:
		initial[RB.ATT + i] = perturbed_attitude[i]
	var start_mask := _contact_mask(initial, case_data.gear)
	var settled_velocity := sqrt(settled.state[RB.VEL] ** 2 + settled.state[RB.VEL + 1] ** 2 + settled.state[RB.VEL + 2] ** 2)
	var settled_rate := sqrt(settled.state[RB.RATE] ** 2 + settled.state[RB.RATE + 1] ** 2 + settled.state[RB.RATE + 2] ** 2)
	var start_energy := _mechanical_energy(initial, case_data.mass, case_data.inertia, case_data.gear)
	var at_240 := _simulate(case_data, initial, 240, RINGDOWN_SECONDS)
	var at_480 := _simulate(case_data, initial, 480, RINGDOWN_SECONDS)
	var at_960 := _simulate(case_data, initial, 960, RINGDOWN_SECONDS)
	var d_240_480 := _trajectory_difference(at_240.snapshots, at_480.snapshots, case_data, modes.omega_max)
	var d_480_960 := _trajectory_difference(at_480.snapshots, at_960.snapshots, case_data, modes.omega_max)
	var error_ratio: float = float(d_240_480.normalized) / maxf(float(d_480_960.normalized), 1e-30)
	var end_energy := _mechanical_energy(at_240.state, case_data.mass, case_data.inertia, case_data.gear)
	var result := {
		"start_contact_mask": start_mask,
		"switches_240": at_240.contact_switches,
		"max_contacts_240": at_240.max_contacts,
		"max_tick_energy_gain_240_j": at_240.max_energy_gain,
		"energy_loss_240_j": start_energy - end_energy,
		"delta_240_480": d_240_480,
		"delta_480_960": d_480_960,
		"smooth_refinement_ratio": error_ratio,
		"supported": supported,
	}
	var full_mask: int = (1 << case_data.gear.contacts.size()) - 1
	var contact_mode_ok: bool = start_mask == full_mask if supported else start_mask != 0
	_check("%s: ring-down probe starts from a settled contact mode" % case_data.name,
		settled.fault.is_empty() and contact_mode_ok and settled_velocity < 0.01 and settled_rate < 0.1,
		"settle fault '%s', mask %d, speed %s m/s, rate %s rad/s" % [settled.fault, start_mask, str(settled_velocity), str(settled_rate)])
	_check("%s: ring-down remains finite and passive at 240 Hz" % case_data.name,
		at_240.fault.is_empty() and at_240.max_energy_gain <= ENERGY_GAIN_TOLERANCE_J
			and start_energy >= end_energy - ENERGY_GAIN_TOLERANCE_J,
		"max tick ΔE %s J, total loss %s J" % [str(at_240.max_energy_gain), str(start_energy - end_energy)])
	if supported:
		_check("%s: smooth 240/480 sampled trajectory within H11 contact budget" % case_data.name,
			d_240_480.position_m <= 0.001 and d_240_480.velocity_mps <= 0.01
				and d_240_480.attitude_rad <= 0.002 and d_240_480.rate_radps <= 0.02,
			"Δx %s m, Δv %s m/s, Δθ %s rad, Δω %s rad/s" % [
				d_240_480.position_m, d_240_480.velocity_mps, d_240_480.attitude_rad, d_240_480.rate_radps])
		_check("%s: smooth ring-down refinement is approximately fourth order" % case_data.name,
			d_480_960.normalized > 1e-14 and error_ratio >= 8.0 and error_ratio <= 32.0
				and at_240.contact_switches == 0 and at_480.contact_switches == 0,
			"ratio %.3f, contact switches %d/%d" % [error_ratio, at_240.contact_switches, at_480.contact_switches])
	return result


func _run_touchdown(case_data: Dictionary, supported: bool) -> Dictionary:
	var gap := 0.015 * float(case_data.size_scale)
	var initial := _initial_drop_state(case_data, gap, 0.35 * sqrt(float(case_data.size_scale)))
	var at_240 := _simulate(case_data, initial, 240, TOUCHDOWN_SECONDS)
	var at_480 := _simulate(case_data, initial, 480, TOUCHDOWN_SECONDS)
	var at_960 := _simulate(case_data, initial, 960, TOUCHDOWN_SECONDS)
	var modes := _coupled_modes(case_data)
	var d_240_480 := _trajectory_difference(at_240.snapshots, at_480.snapshots, case_data, modes.omega_max)
	var d_480_960 := _trajectory_difference(at_480.snapshots, at_960.snapshots, case_data, modes.omega_max)
	var result := {
		"switches_240": at_240.contact_switches,
		"max_contacts_240": at_240.max_contacts,
		"max_tick_energy_gain_240_j": at_240.max_energy_gain,
		"delta_240_480": d_240_480,
		"delta_480_960": d_480_960,
		"supported": supported,
	}
	_check("%s: touchdown trace crosses a contact mode" % case_data.name,
		at_240.fault.is_empty() and at_240.contact_switches > 0 and at_240.max_contacts > 0,
		"fault '%s', switches %d, max loaded wheels %d" % [at_240.fault, at_240.contact_switches, at_240.max_contacts])
	_check("%s: switching touchdown has no resolved 240 Hz energy gain" % case_data.name,
		at_240.max_energy_gain <= ENERGY_GAIN_TOLERANCE_J,
		"max tick ΔE %s J (tolerance %s J)" % [str(at_240.max_energy_gain), str(ENERGY_GAIN_TOLERANCE_J)])
	if supported:
		_check("%s: switching touchdown 240/480 sampled trajectory stays within the declared budget" % case_data.name,
			d_240_480.position_m <= 0.001 and d_240_480.velocity_mps <= 0.01
				and d_240_480.attitude_rad <= 0.002 and d_240_480.rate_radps <= 0.02,
			"Δx %s m, Δv %s m/s, Δθ %s rad, Δω %s rad/s" % [
				d_240_480.position_m, d_240_480.velocity_mps, d_240_480.attitude_rad, d_240_480.rate_radps])
	return result


func _run_case(case_data: Dictionary) -> void:
	var modes := _coupled_modes(case_data)
	var supported: bool = modes.rho_240 <= SUPPORT_RHO + 1e-12
	var mode_detail := "ωmax %.4f rad/s, ρ240 %.6f, heave proxy ρ240 %.6f, active mask %d" % [
		modes.omega_max, modes.rho_240, modes.scalar_rho_240, modes.limiting_contact_mask]
	_check("%s: coupled active-set mode screen computed" % case_data.name, modes.omega_max > 0.0, mode_detail)
	_check("%s: 240 Hz fixture-range classification" % case_data.name, true,
		"%s under tested Stik-family boundary ρ240 ≤ %.2f; not a universal gear limit" % [
			"inside fixture range" if supported else "outside fixture range", SUPPORT_RHO])
	var ringdown := _run_ringdown(case_data, modes, supported)
	var touchdown := _run_touchdown(case_data, supported)
	_results.append({
		"case": case_data.name,
		"mass_kg": case_data.mass,
		"static_sag_m": case_data.target_sag,
		"damping_case_zeta": case_data.zeta,
		"mode": modes,
		"inside_tested_fixture_boundary_240_hz": supported,
		"ringdown": ringdown,
		"touchdown": touchdown,
	})


func _initialize() -> void:
	var saved_hz := Engine.physics_ticks_per_second
	_check_coupled_inertia_reference()
	var loaded := AD.load_file(AIRCRAFT_PATH)
	_check("Stik contact data loads", loaded.ok, str(loaded.errors))
	if not loaded.ok:
		Engine.physics_ticks_per_second = saved_hz
		quit(1)
		return
	var base: Dictionary = loaded.model
	var original_sag: float = base.mass_kg * G / _sum_stiffness(base.landing_gear)
	var cases: Array[Dictionary] = [
		_make_case("light-1kg-18mm-zeta02", 1.0, original_sag, 0.2, base, false),
		_make_case("stik-actual", base.mass_kg, original_sag, 0.4, base, true),
		_make_case("stik-10mm-zeta04", base.mass_kg, 0.010, 0.4, base, false),
		_make_case("giant-18kg-18mm-zeta07", 18.21, original_sag, 0.7, base, false),
		_make_case("giant-18kg-5mm-zeta04", 18.21, 0.005, 0.4, base, false),
		_make_case("stik-2mm-zeta04", base.mass_kg, 0.002, 0.4, base, false),
		_make_case("stik-0.5mm-zeta04", base.mass_kg, 0.0005, 0.4, base, false),
	]
	for case_data in cases:
		_run_case(case_data)
	_screen_catalog_contacts()
	Engine.physics_ticks_per_second = saved_hz
	print("H11_RESULT_JSON " + JSON.stringify(_results))
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _sum_stiffness(gear: Dictionary) -> float:
	var total := 0.0
	for contact in gear.contacts:
		total += float(contact.stiffness)
	return total


func _screen_catalog_contacts() -> void:
	var scanned_ids := PackedStringArray()
	for entry in Catalog.ENTRIES:
		var aircraft_id: String = entry.id
		scanned_ids.append(aircraft_id)
		var loaded := AD.load_file(entry.data)
		_check("catalog %s physics data loads for contact screen" % aircraft_id, loaded.ok, str(loaded.errors))
		if not loaded.ok:
			continue
		var model: Dictionary = loaded.model
		var gear: Dictionary = model.get("landing_gear", {})
		var contacts: Array = gear.get("contacts", [])
		if contacts.is_empty():
			var why := "no landing-gear contact data"
			if aircraft_id == "sebart-avanti-s-a200-p100rx":
				why = "no landing-gear contact data; catalog configuration is gear-up, in-air start only"
			_check("catalog %s: gearless config is reported, not inferred" % aircraft_id, true, why)
			_results.append({
				"catalog_id": aircraft_id,
				"contact_mode_screened": false,
				"contact_count": 0,
				"reason": why,
			})
			continue
		var total_k := _sum_stiffness(gear)
		var scalar_omega := sqrt(total_k / float(model.mass_kg))
		var actual_case := {
			"name": "catalog:%s" % aircraft_id,
			"mass": float(model.mass_kg),
			"inertia": model.inertia,
			"gear": gear,
			"target_sag": float(model.mass_kg) * G / total_k,
			"scalar_omega": scalar_omega,
		}
		var modes := _coupled_modes(actual_case)
		var contact_details: Array[Dictionary] = []
		for contact in contacts:
			var share_mass: float = float(model.mass_kg) / contacts.size()
			var stiffness := float(contact.stiffness)
			var damping := float(contact.damping)
			var nominal_share_zeta := damping / (2.0 * sqrt(stiffness * share_mass))
			contact_details.append({
				"name": contact.name,
				"position_body_m": contact.position,
				"stiffness_n_per_m": stiffness,
				"damping_ns_per_m": damping,
				"equal_mass_share_zeta_estimate": nominal_share_zeta,
			})
		var full_mask := (1 << contacts.size()) - 1
		var screen := {
			"catalog_id": aircraft_id,
			"contact_mode_screened": true,
			"mass_kg": float(model.mass_kg),
			"contact_count": contacts.size(),
			"contact_subset_masks_screened": range(1, full_mask + 1),
			"active_subset_count_screened": full_mask,
			"contact_layout": contact_details,
			"static_sag_proxy_m": actual_case.target_sag,
			"coupled_omega_max_rad_per_s": modes.omega_max,
			"coupled_rho_240": modes.rho_240,
			"heave_scalar_rho_240": modes.scalar_rho_240,
			"limiting_contact_mask": modes.limiting_contact_mask,
			"classification": "catalog mode screen only; no aircraft-specific touchdown/refinement claim",
		}
		_check("catalog %s: coupled gear modes screened" % aircraft_id, modes.omega_max > 0.0,
			"mass %.4f kg, contacts %d, ωmax %.4f rad/s, ρ240 %.6f, heave ρ240 %.6f, subsets %d" % [
				model.mass_kg, contacts.size(), modes.omega_max, modes.rho_240, modes.scalar_rho_240, full_mask])
		_results.append(screen)
	_check("H11 screens every aircraft in the current catalog", scanned_ids == Catalog.ids(), str(scanned_ids))

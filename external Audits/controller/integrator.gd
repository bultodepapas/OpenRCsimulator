# BL-03..BL-06: stage law of the generic RC blimp. Pure functions of (model, body, continuous, inputs, time, wind,
# ground sampler); nothing here advances state or reads a clock, node or random generator.
#
# Coupled 6-DOF law about the fixed datum O (body FRD), constant properties, calm or steady uniform wind:
#   (M_RB + M_A) nu_dot = tau_ext - C_RB(nu) nu - C_A(nu_r) nu_r - M_A [omega x w_b, 0]
# with nu = [v, omega] (ground-relative velocity of O), nu_r = [v - w_b, omega], w_b the world-fixed wind in body
# axes. C_RB uses the rigid momenta p = m (v + omega x r_g), h = I_O omega + m r_g x v; C_A is Kirchhoff's fluid
# momentum transport (it contains the ideal Munk moment, so no separate potential-flow hull moment is added).
# tau_ext: weight at CG, buoyancy rho V g at CB, hull axial drag and viscous crossflow by strips, low-aspect-ratio
# fins over the full angle range, gondola bluff-body drag, propellers with inflow lapse and torque reaction, gear and
# envelope contact. The returned body_derivative replaces RigidBody.derivative and contains kinematics and gravity
# exactly once. Rotor gyroscopic momentum is omitted (bounded: under 1e-2 N*m*s against 3 kg-class inertia).
# 64-bit floats only.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const GC := preload("res://physics/generalized_coordinates.gd")
const Data := preload("res://physics/airship/airship_data.gd")

const LAW := "airship-kirchhoff-6dof-v1"
const MIXER_LAW := "airship-mixer-v1"
const FRICTION_SPEED := 0.05
const THRUST_LIMIT := 1.5
## Penetration over which contact damping ramps in, so the normal force starts at zero on first touch.
const CONTACT_DAMPING_DEPTH := 0.005


## Actuator targets from the four pilot sticks [roll, pitch, yaw, throttle] (pitch > 0 = stick back = nose up,
## yaw > 0 = nose right). Returns [motor x4 (normalized speed command), vector x3 (rad), fin x3 (rad, CTRL sign)].
static func mixer_targets(model: Dictionary, inputs: PackedFloat64Array) -> PackedFloat64Array:
	var roll := clampf(inputs[0], -1.0, 1.0)
	var pitch := clampf(inputs[1], -1.0, 1.0)
	var yaw := clampf(inputs[2], -1.0, 1.0)
	var throttle := clampf(inputs[3], 0.0, 1.0)
	var mix: Dictionary = model.mixer
	var diff: float = mix.differential
	var out := PackedFloat64Array()
	out.resize(10)
	out[0] = clampf(throttle * (1.0 + diff * roll), 0.0, 1.0)
	out[1] = clampf(throttle * (1.0 - diff * roll), 0.0, 1.0)
	out[2] = clampf(throttle * float(mix.stern_axial_share), 0.0, 1.0)
	out[3] = clampf(float(mix.lateral_on_yaw) * yaw * float(model.lateral_sign), -1.0, 1.0)
	var vectors: Array = model.vectors
	for i in 2:
		var travel: PackedFloat64Array = vectors[i].travel
		var amount := maxf(pitch, 0.0) * float(mix.vector_on_pitch)
		out[4 + i] = deg_to_rad(lerpf(travel[0], travel[1], amount))
	var stern_travel: PackedFloat64Array = vectors[2].travel
	var stern_sign: float = mix.stern_vector_sign
	var stern_amount := maxf(pitch * stern_sign, 0.0) if stern_sign != 0.0 else 0.0
	out[6] = deg_to_rad(lerpf(stern_travel[0], stern_travel[1], stern_amount))
	var pitch_norm: float = model.fin_pitch_norm
	var yaw_norm: float = model.fin_yaw_norm
	var fins: Array = model.fins
	for i in 3:
		var fin: Dictionary = fins[i]
		var n: PackedFloat64Array = fin.normal
		var demand := clampf(pitch * pitch_norm * n[2] - yaw * yaw_norm * n[1], -1.0, 1.0)
		# The fin must push along its normal by `demand`: lift opposes trailing-edge displacement.
		var te_displacement := -deg_to_rad(float(fin.travel)) * demand
		out[7 + i] = te_displacement * float(fin.te_sign)
	return out


## One joint stage for Simulation: {loads, derivative, rotor_momentum, body_derivative}.
static func stage(model: Dictionary, body: PackedFloat64Array, continuous: PackedFloat64Array,
		inputs: PackedFloat64Array, wind_ned: PackedFloat64Array, ground: Callable) -> Dictionary:
	var r := evaluate(model, body, continuous, inputs, wind_ned, ground, false)
	return {loads = r.loads, derivative = r.derivative, rotor_momentum = PackedFloat64Array([0.0, 0.0, 0.0]),
		body_derivative = r.body_derivative}


## Full evaluation. With detail = true the result also carries force breakdowns, thrusts, battery bus and contacts
## for telemetry; the arithmetic of loads and derivatives is identical either way.
static func evaluate(model: Dictionary, body: PackedFloat64Array, continuous: PackedFloat64Array,
		inputs: PackedFloat64Array, wind_ned: PackedFloat64Array, ground: Callable, detail: bool) -> Dictionary:
	var q := PackedFloat64Array([body[6], body[7], body[8], body[9]])
	var qc := PackedFloat64Array([body[6], -body[7], -body[8], -body[9]])
	var v := PackedFloat64Array([body[3], body[4], body[5]])
	var w := PackedFloat64Array([body[10], body[11], body[12]])
	var wind_b := M.q_rotate(qc, wind_ned)
	var vr := PackedFloat64Array([v[0] - wind_b[0], v[1] - wind_b[1], v[2] - wind_b[2]])
	var rho: float = model.rho
	var g: float = model.gravity
	var mass: float = model.mass
	var cg: PackedFloat64Array = model.cg
	var cb: PackedFloat64Array = model.cb
	var volume: float = model.envelope.volume
	var force := PackedFloat64Array([0.0, 0.0, 0.0])
	var moment := PackedFloat64Array([0.0, 0.0, 0.0])
	var info := {}
	# --- buoyancy (gravity enters the body derivative below) ---
	var gb := M.q_rotate(qc, PackedFloat64Array([0.0, 0.0, g]))
	var lift := -rho * volume
	_apply3(force, moment, gb[0] * lift, gb[1] * lift, gb[2] * lift, cb)
	if detail:
		info.buoyancy_n = rho * volume * g
	# --- hull: axial drag and viscous crossflow strips ---
	var speed := M.norm(vr)
	var hull_aero: Dictionary = model.hull_aero
	var hull_f := PackedFloat64Array([-0.5 * rho * float(hull_aero.axial_drag) * float(model.ref_area) * vr[0] * speed, 0.0, 0.0])
	var hull_m := PackedFloat64Array([0.0, 0.0, 0.0])
	var stations: PackedFloat64Array = model.hull_stations
	var half_rho := 0.5 * rho
	for i in stations.size() / 2:
		var x := stations[2 * i]
		var weight := stations[2 * i + 1] * half_rho
		var vy := vr[1] + w[2] * x
		var vz := vr[2] - w[1] * x
		var vn := sqrt(vy * vy + vz * vz)
		var fy := -weight * vy * vn
		var fz := -weight * vz * vn
		hull_f[1] += fy
		hull_f[2] += fz
		hull_m[1] -= x * fz
		hull_m[2] += x * fy
	# I06 afterbody (Hopkins 1951; Allen and Perkins 1951): aft of the separation station x0 the slender-body potential
	# normal force density u d(m' v_n)/dx is lost to separated flow. Cancelling it there leaves the ideal Munk moment
	# of the C_A term intact over the forebody and adds the stabilizing, rate-dependent viscous afterbody load.
	# Forward flight only (u > 0); in reverse flow the correction is omitted (declared domain limit).
	var u_axial := vr[0]
	var afterbody_loss: float = hull_aero.afterbody_loss
	if u_axial > 0.0 and afterbody_loss > 0.0:
		var after: PackedFloat64Array = model.afterbody
		for i in after.size() / 2 - 1:
			var xa := after[2 * i]
			var xb := after[2 * i + 2]
			var ma := afterbody_loss * rho * after[2 * i + 1]
			var mb := afterbody_loss * rho * after[2 * i + 3]
			var fy := -u_axial * (ma * (vr[1] + w[2] * xa) - mb * (vr[1] + w[2] * xb))
			var fz := -u_axial * (ma * (vr[2] - w[1] * xa) - mb * (vr[2] - w[1] * xb))
			var xm := 0.5 * (xa + xb)
			hull_f[1] += fy
			hull_f[2] += fz
			hull_m[1] -= xm * fz
			hull_m[2] += xm * fy
	var lin_f: PackedFloat64Array = hull_aero.linear_force
	var lin_m: PackedFloat64Array = hull_aero.linear_moment
	for k in 3:
		hull_f[k] -= lin_f[k] * vr[k]
		hull_m[k] -= lin_m[k] * w[k]
		force[k] += hull_f[k]
		moment[k] += hull_m[k]
	if detail:
		info.hull_force = hull_f
		info.hull_moment = hull_m
	# --- fins ---
	var fins: Array = model.fins
	var fin_detail: Array = []
	for i in 3:
		var fin: Dictionary = fins[i]
		var rf: PackedFloat64Array = fin.centroid
		var vfx := vr[0] + (w[1] * rf[2] - w[2] * rf[1])
		var vfy := vr[1] + (w[2] * rf[0] - w[0] * rf[2])
		var vfz := vr[2] + (w[0] * rf[1] - w[1] * rf[0])
		var n: PackedFloat64Array = fin.normal
		var aft: PackedFloat64Array = fin.aft
		var a_n := -(vfx * n[0] + vfy * n[1] + vfz * n[2])
		var a_t := -(vfx * aft[0] + vfy * aft[1] + vfz * aft[2])
		var area: float = fin.area
		var q_area := half_rho * area * (a_n * a_n + a_t * a_t)
		var alpha := M.atan2_(a_n, a_t) if q_area > 0.0 else 0.0
		var delta: float = continuous[Data.FIN + i]
		var alpha_e: float = alpha - float(fin.flap_tau) * delta * float(fin.te_sign)
		var sa := M.sin_(alpha_e)
		var ca := M.cos_(alpha_e)
		var cn: float = float(fin.lift_slope) * sa * ca + float(fin.crossflow_drag) * sa * absf(sa)
		var air_speed := sqrt(vfx * vfx + vfy * vfy + vfz * vfz)
		var drag_k := half_rho * area * float(fin.drag) * air_speed
		var normal_force := q_area * cn
		var ffx := n[0] * normal_force - drag_k * vfx
		var ffy := n[1] * normal_force - drag_k * vfy
		var ffz := n[2] * normal_force - drag_k * vfz
		_apply3(force, moment, ffx, ffy, ffz, rf)
		if detail:
			fin_detail.append({id = fin.id, alpha_deg = rad_to_deg(alpha), normal_force_n = normal_force,
				force = PackedFloat64Array([ffx, ffy, ffz])})
	# --- gondola bluff-body drag ---
	var gondola: Dictionary = model.gondola
	var gc: PackedFloat64Array = gondola.center
	var vgx := vr[0] + (w[1] * gc[2] - w[2] * gc[1])
	var vgy := vr[1] + (w[2] * gc[0] - w[0] * gc[2])
	var vgz := vr[2] + (w[0] * gc[1] - w[1] * gc[0])
	var areas: PackedFloat64Array = gondola.areas
	var gk := -half_rho * float(gondola.drag) * sqrt(vgx * vgx + vgy * vgy + vgz * vgz)
	_apply3(force, moment, gk * areas[0] * vgx, gk * areas[1] * vgy, gk * areas[2] * vgz, gc)
	# --- battery bus: one pack, one terminal voltage per stage ---
	var battery: Dictionary = model.battery
	var soc: float = continuous[Data.SOC]
	var cells: float = battery.cells
	var ocv := cells * _ocv(battery.ocv, soc)
	var rotors: Array = model.rotors
	var electrical := 0.0
	for i in 4:
		var n_i: float = continuous[Data.MOTOR + i]
		var rotor: Dictionary = rotors[i]
		electrical += float(rotor.shaft_power) * absf(n_i * n_i * n_i) / float(rotor.motor_efficiency)
	var resistance: float = battery.resistance
	var disc := ocv * ocv - 4.0 * electrical * resistance
	# Beyond the pack's maximum transferable power (disc <= 0) the bus sits at OCV/2 and delivers only OCV^2/(4R).
	var volts := 0.5 * (ocv + sqrt(disc)) if disc > 0.0 else 0.5 * ocv
	var current := electrical / volts if disc > 0.0 and volts > 0.0 else (ocv - volts) / resistance if resistance > 0.0 else 0.0
	var cutoff := clampf((volts - cells * float(battery.cutoff_cell)) / float(battery.cutoff_band), 0.0, 1.0)
	var supply := volts / float(battery.reference_voltage) * cutoff
	# --- actuators: targets, servo and motor responses ---
	var targets := mixer_targets(model, inputs)
	var derivative := PackedFloat64Array()
	derivative.resize(Data.CONTINUOUS_SIZE)
	for i in 4:
		var rotor: Dictionary = rotors[i]
		derivative[Data.MOTOR + i] = (targets[i] * supply - continuous[Data.MOTOR + i]) / float(rotor.response_time)
	var vectors: Array = model.vectors
	for i in 3:
		var vec: Dictionary = vectors[i]
		var rate := deg_to_rad(float(vec.max_rate))
		derivative[Data.VECTOR + i] = clampf((targets[4 + i] - continuous[Data.VECTOR + i]) / float(vec.response_time), -rate, rate)
	for i in 3:
		var fin: Dictionary = fins[i]
		var rate := deg_to_rad(float(fin.max_rate))
		derivative[Data.FIN + i] = clampf((targets[7 + i] - continuous[Data.FIN + i]) / float(fin.response_time), -rate, rate)
	derivative[Data.SOC] = -current / (3600.0 * float(battery.capacity)) if soc > 0.0 else 0.0
	# --- propellers ---
	var thrusts := PackedFloat64Array()
	var thrust_dirs: Array = []
	for i in 4:
		var rotor: Dictionary = rotors[i]
		var d: PackedFloat64Array = rotor.thrust_axis
		var hub: PackedFloat64Array = rotor.hub
		var vector_index: int = rotor.vector
		if vector_index >= 0:
			var vec: Dictionary = vectors[vector_index]
			var angle: float = continuous[Data.VECTOR + vector_index]
			var moved := _rotate_axis_and_hub(d, hub, vec.pivot, vec.axis, angle)
			d = moved.slice(0, 3)
			hub = moved.slice(3, 6)
		var n_i: float = continuous[Data.MOTOR + i]
		var inflow := (vr[0] + (w[1] * hub[2] - w[2] * hub[1])) * d[0] + (vr[1] + (w[2] * hub[0] - w[0] * hub[2])) * d[1] \
			+ (vr[2] + (w[0] * hub[1] - w[1] * hub[0])) * d[2]
		var efficiency: float = 1.0 if n_i >= 0.0 else float(rotor.reverse_efficiency)
		var t0: float = rotor.static_thrust
		var thrust := clampf(t0 * efficiency * (n_i * absf(n_i) - absf(n_i) * inflow / float(rotor.pitch_speed)),
			-THRUST_LIMIT * t0, THRUST_LIMIT * t0)
		_apply3(force, moment, d[0] * thrust, d[1] * thrust, d[2] * thrust, hub)
		var reaction := -float(rotor.rotation_sense) * signf(n_i) * float(rotor.torque_ratio) * t0 * n_i * n_i
		moment[0] += reaction * d[0]
		moment[1] += reaction * d[1]
		moment[2] += reaction * d[2]
		thrusts.append(thrust)
		if detail:
			thrust_dirs.append(d)
	# --- contacts (conservative skip when the whole vehicle is clearly above the ground) ---
	var contact := _contacts(model, body, continuous, q, v, w, ground, force, moment, detail)
	# --- coupled rigid body + added mass solve ---
	var tau := PackedFloat64Array([force[0] + mass * gb[0], force[1] + mass * gb[1], force[2] + mass * gb[2],
		moment[0], moment[1], moment[2]])
	# Weight moment about O: cg x (m g_b).
	var mgx := gb[0] * mass
	var mgy := gb[1] * mass
	var mgz := gb[2] * mass
	tau[3] += cg[1] * mgz - cg[2] * mgy
	tau[4] += cg[2] * mgx - cg[0] * mgz
	tau[5] += cg[0] * mgy - cg[1] * mgx
	# Rigid momenta p = m (v + w x r_g), h = I_O w + m r_g x v, and C_RB = [w x p, w x h + v x p].
	var p_rb := PackedFloat64Array([mass * (v[0] + (w[1] * cg[2] - w[2] * cg[1])), mass * (v[1] + (w[2] * cg[0] - w[0] * cg[2])),
		mass * (v[2] + (w[0] * cg[1] - w[1] * cg[0]))])
	var iw := _mul3(model.inertia, w)
	var h_rb := PackedFloat64Array([iw[0] + mass * (cg[1] * v[2] - cg[2] * v[1]), iw[1] + mass * (cg[2] * v[0] - cg[0] * v[2]),
		iw[2] + mass * (cg[0] * v[1] - cg[1] * v[0])])
	var c1 := _cross(w, p_rb)
	var c2 := _cross_sum(w, h_rb, v, p_rb)
	var m_a: PackedFloat64Array = model.m_a
	var nu_r := PackedFloat64Array([vr[0], vr[1], vr[2], w[0], w[1], w[2]])
	# Fluid momenta [p_a, h_a] = M_A nu_r and C_A = [w x p_a, w x h_a + v_r x p_a].
	var fluid := _mul6(m_a, nu_r)
	var pa := fluid.slice(0, 3)
	var ca1 := _cross(w, pa)
	var ca2 := _cross_sum(w, fluid.slice(3, 6), vr, pa)
	# Fluid transport of a world-fixed wind seen from rotating axes (zero, and skipped, in calm air).
	var transport := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	if wind_b[0] != 0.0 or wind_b[1] != 0.0 or wind_b[2] != 0.0:
		var transport_v := M.cross(w, wind_b)
		transport = _mul6(m_a, PackedFloat64Array([transport_v[0], transport_v[1], transport_v[2], 0.0, 0.0, 0.0]))
	var rhs := PackedFloat64Array([
		tau[0] - c1[0] - ca1[0] - transport[0], tau[1] - c1[1] - ca1[1] - transport[1], tau[2] - c1[2] - ca1[2] - transport[2],
		tau[3] - c2[0] - ca2[0] - transport[3], tau[4] - c2[1] - ca2[1] - transport[4], tau[5] - c2[2] - ca2[2] - transport[5]])
	var nu_dot := GC.solve_cholesky(model.lower, rhs, 6)
	if nu_dot.size() != 6:
		nu_dot = PackedFloat64Array([NAN, NAN, NAN, NAN, NAN, NAN])
	var pos_dot := M.q_rotate(q, v)
	var q0 := q[0]
	var q1 := q[1]
	var q2 := q[2]
	var q3 := q[3]
	var body_derivative := PackedFloat64Array([pos_dot[0], pos_dot[1], pos_dot[2], nu_dot[0], nu_dot[1], nu_dot[2],
		(-q1 * w[0] - q2 * w[1] - q3 * w[2]) * 0.5,
		(q0 * w[0] + q2 * w[2] - q3 * w[1]) * 0.5,
		(q0 * w[1] - q1 * w[2] + q3 * w[0]) * 0.5,
		(q0 * w[2] + q1 * w[1] - q2 * w[0]) * 0.5,
		nu_dot[3], nu_dot[4], nu_dot[5]])
	var result := {loads = PackedFloat64Array([force[0], force[1], force[2], moment[0], moment[1], moment[2]]),
		derivative = derivative, body_derivative = body_derivative}
	if detail:
		info.weight_n = mass * g
		info.air_speed_mps = speed
		info.wind_body = wind_b
		info.fins = fin_detail
		info.thrust_n = thrusts
		info.thrust_dirs = thrust_dirs
		info.targets = targets
		info.battery = {volts = volts, current_a = current, power_w = electrical, ocv = ocv, cutoff = cutoff, soc = soc}
		info.contact = contact
		info.acceleration = nu_dot
		result.info = info
	return result


## Gear and envelope contacts against the terrain sampler [height_up, dh/dnorth, dh/deast]. Penalty normal force
## with depth-scaled damping (Hunt-Crossley-like: no force jump at first touch, never pulling) and regularized
## Coulomb friction in the ground plane. Witnesses above the field ceiling are never sampled. When more than
## FOOTPRINT_SAMPLES remain, the skip tests sample the terrain under O and at +-R north/east and rely on
## the admitted field slope (at most TERRAIN_SLOPE_LIMIT inside the footprint; a steeper cliff is outside the
## domain): a witness higher than min(field ceiling, min_k(h_k + slope * distance_k)) + TERRAIN_SKIP_MARGIN cannot
## touch, so it is not sampled; the field ceiling bound holds without any slope assumption. Skipping changes no
## arithmetic: an unsampled witness would contribute exactly nothing.
## Propeller points follow their vector pivots and are observed only (terminal event, observe_props = true); the
## integration stages never evaluate them.
const TERRAIN_SLOPE_LIMIT := 0.3
const TERRAIN_SKIP_MARGIN := 0.05
## Above this many witnesses not cleared by the field ceiling, footprint samples tighten the bound first.
const FOOTPRINT_SAMPLES := 5


static func _contacts(model: Dictionary, body: PackedFloat64Array, continuous: PackedFloat64Array, q: PackedFloat64Array,
		v: PackedFloat64Array, w: PackedFloat64Array, ground: Callable, force: PackedFloat64Array, moment: PackedFloat64Array,
		observe_props: bool) -> Dictionary:
	var out := {checked = false, gear_load_n = 0.0, hull_contact = false, prop_contact = false, max_approach_mps = 0.0,
		hull_approach_mps = 0.0, clearance_m = INF}
	if not ground.is_valid():
		return out
	var radius: float = model.bound_radius
	var ceiling: float = model.get("ground_ceiling", INF)
	# Global ceiling of the field (session-supplied) first: far above every terrain point, no sampling is needed.
	if -body[2] - 1.3 * radius - 0.5 > ceiling:
		return out
	# World-down direction in body axes: a body point p sits dot(down_b, p) below O. A vectored propeller point stays
	# within |p - pivot| of its pivot, whatever the vector angle.
	var down_b := M.q_rotate(PackedFloat64Array([q[0], -q[1], -q[2], -q[3]]), PackedFloat64Array([0.0, 0.0, 1.0]))
	var contacts: Dictionary = model.contacts
	var hull: PackedFloat64Array = contacts.hull_points
	var gear_items: Array = contacts.gear
	var props: PackedFloat64Array = contacts.prop_points
	var assign: PackedInt64Array = model.prop_vector
	var vectors: Array = model.vectors
	var floor_bound := ceiling + TERRAIN_SKIP_MARGIN
	# Witnesses the ceiling alone cannot clear. Few of them: sample each directly. Many (relief above them):
	# the five footprint samples first tighten the bound under the admitted slope limit.
	var low := 0
	for i in hull.size() / 3:
		if -(body[2] + down_b[0] * hull[3 * i] + down_b[1] * hull[3 * i + 1] + down_b[2] * hull[3 * i + 2]) <= floor_bound:
			low += 1
	for gear: Dictionary in gear_items:
		var gp: PackedFloat64Array = gear.point
		if -(body[2] + down_b[0] * gp[0] + down_b[1] * gp[1] + down_b[2] * gp[2]) <= floor_bound:
			low += 1
	var prop_reach := PackedFloat64Array()
	if observe_props:
		prop_reach.resize(props.size() / 3)
		for i in props.size() / 3:
			var px := props[3 * i]
			var py := props[3 * i + 1]
			var pz := props[3 * i + 2]
			var reach := down_b[0] * px + down_b[1] * py + down_b[2] * pz
			if assign[i] >= 0:
				var pivot: PackedFloat64Array = vectors[assign[i]].pivot
				var dx := px - pivot[0]
				var dy := py - pivot[1]
				var dz := pz - pivot[2]
				reach = down_b[0] * pivot[0] + down_b[1] * pivot[1] + down_b[2] * pivot[2] + sqrt(dx * dx + dy * dy + dz * dz)
			prop_reach[i] = reach
			if -(body[2] + reach) <= floor_bound:
				low += 1
	if low == 0:
		return out
	var samples := PackedFloat64Array([ceiling])
	var coarse := floor_bound
	if low > FOOTPRINT_SAMPLES:
		# Footprint samples: samples[0] is the global ceiling, then [north, east, height] under O and at +-R north/east.
		var under: PackedFloat64Array = ground.call(body[0], body[1])
		out.clearance_m = -body[2] - under[0]
		samples.append_array([body[0], body[1], under[0]])
		var highest := under[0]
		for k in 4:
			var dn := radius if k == 0 else (-radius if k == 1 else 0.0)
			var de := radius if k == 2 else (-radius if k == 3 else 0.0)
			var h_k: float = ground.call(body[0] + dn, body[1] + de)[0]
			samples.append_array([body[0] + dn, body[1] + de, h_k])
			highest = maxf(highest, h_k)
		if -body[2] - highest > 1.3 * radius + 0.5:
			return out
		# Coarse per-witness bound (every witness lies within R of O, so it dominates the per-point bound).
		coarse = minf(ceiling, highest + TERRAIN_SLOPE_LIMIT * radius) + TERRAIN_SKIP_MARGIN
	out.checked = true
	for gear: Dictionary in gear_items:
		var gp: PackedFloat64Array = gear.point
		if -(body[2] + down_b[0] * gp[0] + down_b[1] * gp[1] + down_b[2] * gp[2]) > coarse:
			continue
		var normal_load := _contact_point(body, q, v, w, gp, gear.stiffness, gear.damping, gear.mu_roll, gear.mu_side,
			true, ground, force, moment, out, samples)
		out.gear_load_n += normal_load
	for i in hull.size() / 3:
		if -(body[2] + down_b[0] * hull[3 * i] + down_b[1] * hull[3 * i + 1] + down_b[2] * hull[3 * i + 2]) > coarse:
			continue
		var before: float = out.max_approach_mps
		out.max_approach_mps = 0.0
		var normal_load := _contact_point(body, q, v, w, hull.slice(3 * i, 3 * i + 3), contacts.hull_stiffness, contacts.hull_damping,
			contacts.hull_mu, contacts.hull_mu, false, ground, force, moment, out, samples)
		if normal_load > 0.0:
			out.hull_contact = true
			out.hull_approach_mps = maxf(float(out.hull_approach_mps), float(out.max_approach_mps))
		out.max_approach_mps = maxf(before, float(out.max_approach_mps))
	if not observe_props:
		return out
	for i in props.size() / 3:
		if -(body[2] + prop_reach[i]) > coarse:
			continue
		var p := props.slice(3 * i, 3 * i + 3)
		if assign[i] >= 0:
			var vec: Dictionary = vectors[assign[i]]
			p = M.add(vec.pivot, _rotate_about(M.sub(p, vec.pivot), vec.axis, continuous[Data.VECTOR + assign[i]]))
		var world := M.add(body.slice(0, 3), M.q_rotate(q, p))
		if _terrain_clear(world, samples):
			continue
		var h: PackedFloat64Array = ground.call(world[0], world[1])
		if world[2] + h[0] > 0.0:
			out.prop_contact = true
	return out

## Propeller witness points (body FRD from O) rotated with their vector pivots at the current vector angles.
static func prop_points(model: Dictionary, continuous: PackedFloat64Array) -> PackedFloat64Array:
	var props: PackedFloat64Array = model.contacts.prop_points
	var assign: PackedInt64Array = model.prop_vector
	var vectors: Array = model.vectors
	var out := PackedFloat64Array()
	for i in props.size() / 3:
		var p := props.slice(3 * i, 3 * i + 3)
		var vector_index := assign[i]
		if vector_index >= 0:
			var vec: Dictionary = vectors[vector_index]
			p = M.add(vec.pivot, _rotate_about(M.sub(p, vec.pivot), vec.axis, continuous[Data.VECTOR + vector_index]))
		out.append_array(p)
	return out


## True when a world NED point is provably above the terrain under the admitted footprint slope limit.
static func _terrain_clear(world: PackedFloat64Array, samples: PackedFloat64Array) -> bool:
	var bound := samples[0]
	for k in (samples.size() - 1) / 3:
		var dn := world[0] - samples[3 * k + 1]
		var de := world[1] - samples[3 * k + 2]
		bound = minf(bound, samples[3 * k + 3] + TERRAIN_SLOPE_LIMIT * sqrt(dn * dn + de * de))
	return -world[2] > bound + TERRAIN_SKIP_MARGIN


## Terminal-event observation of an accepted state: gear, envelope and propeller contacts without integrating.
static func observe_contacts(model: Dictionary, body: PackedFloat64Array, continuous: PackedFloat64Array,
		ground: Callable) -> Dictionary:
	var q := PackedFloat64Array([body[6], body[7], body[8], body[9]])
	var v := PackedFloat64Array([body[3], body[4], body[5]])
	var w := PackedFloat64Array([body[10], body[11], body[12]])
	return _contacts(model, body, continuous, q, v, w, ground, PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([0.0, 0.0, 0.0]), true)


static func _contact_point(body: PackedFloat64Array, q: PackedFloat64Array, v: PackedFloat64Array, w: PackedFloat64Array,
		p: PackedFloat64Array, stiffness: float, damping: float, mu_roll: float, mu_side: float, wheel: bool, ground: Callable,
		force: PackedFloat64Array, moment: PackedFloat64Array, out: Dictionary, samples: PackedFloat64Array) -> float:
	var offset := M.q_rotate(q, p)
	var world := PackedFloat64Array([body[0] + offset[0], body[1] + offset[1], body[2] + offset[2]])
	if _terrain_clear(world, samples):
		return 0.0
	var h: PackedFloat64Array = ground.call(world[0], world[1])
	var penetration := world[2] + h[0]
	if not (penetration > 0.0):
		return 0.0
	var up := PackedFloat64Array([-h[1], -h[2], -1.0])
	up = M.scale(up, 1.0 / M.norm(up))
	var depth := penetration * -up[2]
	var v_world := M.q_rotate(q, M.add(v, M.cross(w, p)))
	var vn := M.dot(v_world, up)
	out.max_approach_mps = maxf(float(out.max_approach_mps), -vn)
	var normal := maxf(stiffness * depth - damping * minf(depth / CONTACT_DAMPING_DEPTH, 1.0) * vn, 0.0)
	var vt := M.sub(v_world, M.scale(up, vn))
	var friction := PackedFloat64Array([0.0, 0.0, 0.0])
	if wheel:
		# Rolling direction: the body x axis projected into the ground plane; side = up x roll.
		var nose := M.q_rotate(q, PackedFloat64Array([1.0, 0.0, 0.0]))
		var roll := M.sub(nose, M.scale(up, M.dot(nose, up)))
		var roll_norm := M.norm(roll)
		roll = M.scale(roll, 1.0 / roll_norm) if roll_norm > 1e-9 else PackedFloat64Array([1.0, 0.0, 0.0])
		var side := M.cross(up, roll)
		var vr := M.dot(vt, roll)
		var vs := M.dot(vt, side)
		var reg := 1.0 / sqrt(vr * vr + vs * vs + FRICTION_SPEED * FRICTION_SPEED)
		friction = M.add(M.scale(roll, -normal * mu_roll * vr * reg), M.scale(side, -normal * mu_side * vs * reg))
	else:
		var reg := 1.0 / sqrt(M.dot(vt, vt) + FRICTION_SPEED * FRICTION_SPEED)
		friction = M.scale(vt, -normal * mu_roll * reg)
	var qc := PackedFloat64Array([q[0], -q[1], -q[2], -q[3]])
	_apply(force, moment, M.q_rotate(qc, M.add(M.scale(up, normal), friction)), p)
	return normal


static func _apply3(force: PackedFloat64Array, moment: PackedFloat64Array, fx: float, fy: float, fz: float,
		r: PackedFloat64Array) -> void:
	force[0] += fx
	force[1] += fy
	force[2] += fz
	moment[0] += r[1] * fz - r[2] * fy
	moment[1] += r[2] * fx - r[0] * fz
	moment[2] += r[0] * fy - r[1] * fx


static func _apply(force: PackedFloat64Array, moment: PackedFloat64Array, f: PackedFloat64Array, r: PackedFloat64Array) -> void:
	force[0] += f[0]
	force[1] += f[1]
	force[2] += f[2]
	moment[0] += r[1] * f[2] - r[2] * f[1]
	moment[1] += r[2] * f[0] - r[0] * f[2]
	moment[2] += r[0] * f[1] - r[1] * f[0]


## Rotor thrust axis d and hub rotated together about a vector pivot (one sine/cosine pair): [d, hub].
static func _rotate_axis_and_hub(d: PackedFloat64Array, hub: PackedFloat64Array, pivot: PackedFloat64Array,
		k: PackedFloat64Array, angle: float) -> PackedFloat64Array:
	var c := M.cos_(angle)
	var s := M.sin_(angle)
	var out := PackedFloat64Array()
	out.resize(6)
	for part in 2:
		var x := d[0] if part == 0 else hub[0] - pivot[0]
		var y := d[1] if part == 0 else hub[1] - pivot[1]
		var z := d[2] if part == 0 else hub[2] - pivot[2]
		var kd := (k[0] * x + k[1] * y + k[2] * z) * (1.0 - c)
		var rx := x * c + (k[1] * z - k[2] * y) * s + k[0] * kd
		var ry := y * c + (k[2] * x - k[0] * z) * s + k[1] * kd
		var rz := z * c + (k[0] * y - k[1] * x) * s + k[2] * kd
		out[3 * part] = rx if part == 0 else pivot[0] + rx
		out[3 * part + 1] = ry if part == 0 else pivot[1] + ry
		out[3 * part + 2] = rz if part == 0 else pivot[2] + rz
	return out


static func _cross(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]])


## a x b + c x d.
static func _cross_sum(a: PackedFloat64Array, b: PackedFloat64Array, c: PackedFloat64Array, d: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([(a[1] * b[2] - a[2] * b[1]) + (c[1] * d[2] - c[2] * d[1]),
		(a[2] * b[0] - a[0] * b[2]) + (c[2] * d[0] - c[0] * d[2]), (a[0] * b[1] - a[1] * b[0]) + (c[0] * d[1] - c[1] * d[0])])


## Rodrigues rotation of v about unit axis k by angle (right-handed).
static func _rotate_about(v: PackedFloat64Array, k: PackedFloat64Array, angle: float) -> PackedFloat64Array:
	var c := M.cos_(angle)
	var s := M.sin_(angle)
	var kv := M.cross(k, v)
	var kd := M.dot(k, v) * (1.0 - c)
	return PackedFloat64Array([v[0] * c + kv[0] * s + k[0] * kd, v[1] * c + kv[1] * s + k[1] * kd, v[2] * c + kv[2] * s + k[2] * kd])


static func _mul3(j: PackedFloat64Array, v: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([j[0] * v[0] + j[3] * v[1] + j[4] * v[2], j[3] * v[0] + j[1] * v[1] + j[5] * v[2],
		j[4] * v[0] + j[5] * v[1] + j[2] * v[2]])


static func _mul6(a: PackedFloat64Array, x: PackedFloat64Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(6)
	for r in 6:
		var s := 0.0
		for c in 6:
			s += a[r * 6 + c] * x[c]
		out[r] = s
	return out


## Linear interpolation of the cell open-circuit voltage table [soc, volts, ...] (soc clamped to 0..1).
static func _ocv(table: PackedFloat64Array, soc: float) -> float:
	var s := clampf(soc, 0.0, 1.0)
	for i in table.size() / 2 - 1:
		var s1 := table[2 * i + 2]
		if s <= s1:
			var s0 := table[2 * i]
			var f := (s - s0) / (s1 - s0)
			return table[2 * i + 1] + f * (table[2 * i + 3] - table[2 * i + 1])
	return table[table.size() - 1]


## Kinetic energy 0.5 nu^T (M_RB + M_A) nu_r-style diagnostic for calm air: used by the energy tests.
static func kinetic_energy(model: Dictionary, body: PackedFloat64Array) -> float:
	var nu := PackedFloat64Array([body[3], body[4], body[5], body[10], body[11], body[12]])
	var mn := _mul6(model.m_total, nu)
	var e := 0.0
	for i in 6:
		e += nu[i] * mn[i]
	return 0.5 * e

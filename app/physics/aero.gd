# Float64 aerodynamic loads about CG [Fx,Fy,Fz,Mx,My,Mz], gravity excluded.
# The corrected empirical model remains the exact small-angle oracle. Outside its local-flow
# validity region, complete loads blend to passive wing/tail elements: flow = v + omega cross r,
# lift perpendicular to flow, drag against flow, moment = r cross F. No independently scaled
# stall deficits or residual damping moments. The tail replaces global derivatives, never adds them.
# Parameters/provenance: aero.surfaces in aircraft JSON. See docs/research/flight-repair-implementation.md.
# coefficients() describes the reference empirical curve, not summed nonlinear surface loads.
# No propwash, dynamic stall memory or ground effect yet.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

## Equal-area elements per wing side (numerical resolution, not an aircraft parameter).
const WING_STATIONS_PER_SIDE := 3


## Our pilot-side surface angles (degrees, trailing edge UP for ailerons/elevator, RIGHT for rudder,
## as in input/commands.gd surface_deflections_deg) → the data's conventions (radians, +TE down / +TE left).
## The only place where the two sign conventions meet.
static func deflections_from_surfaces(surfaces_deg: Dictionary) -> Dictionary:
	return {
		elevator = -deg_to_rad(surfaces_deg.elevator),
		aileron_right = -deg_to_rad(surfaces_deg.aileron_right),
		aileron_left = -deg_to_rad(surfaces_deg.aileron_left),
		rudder = -deg_to_rad(surfaces_deg.rudder),
	}


## Stall blend weight at angle of attack α (rad): 0 in attached flow, 1 in separated (flat-plate) flow.
## env: { a1, a2 (positive stall start/end), n1, n2 (negative, magnitudes), b1, b2 (sideslip), CD90 }; {} = linear.
static func stall_weight(alpha: float, env: Dictionary) -> float:
	if env.is_empty():
		return 0.0
	if alpha >= 0.0:
		return _smoothstep((alpha - env.a1) / (env.a2 - env.a1))
	return _smoothstep((-alpha - env.n1) / (env.n2 - env.n1))


static func sideslip_weight(beta: float, env: Dictionary) -> float:
	return 0.0 if env.is_empty() else _smoothstep((absf(beta) - env.b1) / (env.b2 - env.b1))


static func _smoothstep(x: float) -> float:
	if x <= 0.0:
		return 0.0
	if x >= 1.0:
		return 1.0
	return x * x * (3.0 - 2.0 * x)


## The α-dependent part of the lift coefficient (no control terms), attached → flat plate.
static func lift_alpha(alpha: float, a: Dictionary, env: Dictionary) -> float:
	var base: float = a.CL0 + a.CLa * alpha
	var w := stall_weight(alpha, env)
	return base if w == 0.0 else (1.0 - w) * base + w * 0.5 * float(env.CD90) * M.sin_(2.0 * alpha)


## Nondimensional coefficients for the given air data, body rates (rad/s) and deflections (data conventions).
## Rate damping is dimensionalized separately in _global_loads to avoid division by zero.
## This reference curve is not a force/power diagnostic for the local model.
static func coefficients(air: Dictionary, rates: PackedFloat64Array, d: Dictionary, a: Dictionary, env := {}) -> Dictionary:
	var alpha: float = air.alpha
	var beta: float = air.beta
	var de: float = d.elevator
	var dar: float = d.aileron_right
	var dal: float = d.aileron_left
	var dr: float = d.rudder
	var w := stall_weight(alpha, env)
	var wb := sideslip_weight(beta, env)
	var sb := beta if wb == 0.0 else (1.0 - wb) * beta + wb * M.sin_(beta) # effective sideslip for the β terms
	var cl_controls: float = a.CLde * de + a.CLda_each * (dar + dal)
	var cl: float = a.CL0 + a.CLa * alpha + cl_controls
	var cd_aero: float = a.CD0 + a.k_induced * M.pow_(cl - a.CL_minD, 2)
	if not env.is_empty():
		cl = lift_alpha(alpha, a, env) + cl_controls
		cd_aero = (1.0 - w) * cd_aero + w * (a.CD0 + env.CD90 * M.sin_(alpha) * M.sin_(alpha))
	var cd: float = cd_aero + absf(a.CDda_each * dar) + absf(a.CDda_each * dal) + absf(a.CDdr * dr) + absf(a.CDde * de)
	var cm_alpha: float = a.Cm0 + a.Cma * alpha
	if w != 0.0:
		cm_alpha = (1.0 - w) * cm_alpha + w * (a.Cm0 + a.Cma * M.sin_(alpha))
	var cl_total: float = a.Clb * sb + a.Clda_right * dar + a.Clda_left * dal + a.Cldr * dr
	var cn_total: float = a.Cnb * sb + a.Cnda_right * dar + a.Cnda_left * dal + a.Cndr * dr
	return {
		CL = cl, CD = cd,
		CY = a.CYb * sb + a.CYdr * dr,
		Cl = cl_total,
		Cm = cm_alpha + a.Cmde * de + a.Cmda_each * (dar + dal),
		Cn = cn_total,
	}


## Body loads about the CG [Fx, Fy, Fz, Mx, My, Mz], gravity excluded.
## model: AircraftData model (reference S, b, c, arp_le; cg_le; aero).
static func _global_loads(s: PackedFloat64Array, air: Dictionary, d: Dictionary, model: Dictionary, rho: float) -> PackedFloat64Array:
	var ref: Dictionary = model.reference
	var a: Dictionary = model.aero
	var S: float = ref.S
	var b: float = ref.b
	var c: float = ref.c
	var qbar: float = air.qbar
	var p := s[RB.RATE]
	var q := s[RB.RATE + 1]
	var r := s[RB.RATE + 2]
	# H15: coefficients() inlined in its own operation order (no Dictionary result); see
	# tests/attached_flow_reference.gd. coefficients() stays the public reference curve for trim and linearization.
	var env: Dictionary = model.get("envelope", {})
	var alpha: float = air.alpha
	var beta: float = air.beta
	var de: float = d.elevator
	var dar: float = d.aileron_right
	var dal: float = d.aileron_left
	var dr: float = d.rudder
	var w := stall_weight(alpha, env)
	var wb := sideslip_weight(beta, env)
	var beta_eff := beta if wb == 0.0 else (1.0 - wb) * beta + wb * M.sin_(beta)
	var cl_controls: float = a.CLde * de + a.CLda_each * (dar + dal)
	var cl0: float = a.CL0
	var cla: float = a.CLa
	var cd0: float = a.CD0
	var co_cl: float = cl0 + cla * alpha + cl_controls
	var cd_aero: float = cd0 + a.k_induced * M.pow_(co_cl - a.CL_minD, 2)
	if not env.is_empty():
		var base: float = cl0 + cla * alpha
		var cd90: float = env.CD90
		co_cl = (base if w == 0.0 else (1.0 - w) * base + w * 0.5 * cd90 * M.sin_(2.0 * alpha)) + cl_controls
		var sin_alpha := M.sin_(alpha)
		cd_aero = (1.0 - w) * cd_aero + w * (cd0 + cd90 * sin_alpha * sin_alpha)
	var co_cd: float = cd_aero + absf(a.CDda_each * dar) + absf(a.CDda_each * dal) + absf(a.CDdr * dr) + absf(a.CDde * de)
	var cm0: float = a.Cm0
	var cma: float = a.Cma
	var cm_alpha: float = cm0 + cma * alpha
	if w != 0.0:
		cm_alpha = (1.0 - w) * cm_alpha + w * (cm0 + cma * M.sin_(alpha))
	var co_cy: float = a.CYb * beta_eff + a.CYdr * dr
	var co_roll: float = a.Clb * beta_eff + a.Clda_right * dar + a.Clda_left * dal + a.Cldr * dr
	var co_pitch: float = cm_alpha + a.Cmde * de + a.Cmda_each * (dar + dal)
	var co_yaw: float = a.Cnb * beta_eff + a.Cnda_right * dar + a.Cnda_left * dal + a.Cndr * dr

	# Rate (damping) terms in dimensional form: qbar·x̂ = ½ρV²·(rate·L/2V) = ¼ρ·V·rate·L. Finite as V → 0.
	var k := 0.25 * rho * float(air.V)
	var cl_rate: float = k * c * a.CLq * q # = qbar·CLq·q̂
	var cy_rate: float = k * b * (a.CYp * p + a.CYr * r)
	var roll_rate: float = k * b * (a.Clp * p + a.Clr * r)
	var pitch_rate: float = k * c * a.Cmq * q
	var yaw_rate: float = k * b * (a.Cnp * p + a.Cnr * r)

	var lift: float = (qbar * co_cl + cl_rate) * S
	var drag: float = qbar * co_cd * S
	var side: float = (qbar * co_cy + cy_rate) * S

	# Wind axes → body axes. Wind-axis force = [-D, Y, -L].
	var ca := M.cos_(alpha)
	var sa := M.sin_(alpha)
	var cb := M.cos_(beta)
	var sb := M.sin_(beta)
	var fx: float = ca * cb * (-drag) - ca * sb * side + sa * lift
	var fy: float = sb * (-drag) + cb * side
	var fz: float = sa * cb * (-drag) - sa * sb * side - ca * lift

	# Moments about the aero reference point, then transferred to the CG: M_cg = M_arp + r × F, r = arp − cg (body).
	var mx: float = (qbar * co_roll + roll_rate) * S * b
	var my: float = (qbar * co_pitch + pitch_rate) * S * c
	var mz: float = (qbar * co_yaw + yaw_rate) * S * b
	var arp: PackedFloat64Array = ref.arp_le
	var cg: PackedFloat64Array = model.cg_le
	var rx: float = -(arp[0] - cg[0]) # le frame → body FRD
	var ry: float = arp[1] - cg[1]
	var rz: float = -(arp[2] - cg[2])
	return PackedFloat64Array([fx, fy, fz, mx + (ry * fz - rz * fy), my + (rz * fx - rx * fz), mz + (rx * fy - ry * fx)])


# Local surface loads: lift is perpendicular to local velocity, drag opposes it;
# the moment is exactly r cross F. Passive by construction for fixed controls.
static func _surface(v: PackedFloat64Array, rates: PackedFloat64Array, arm: PackedFloat64Array,
		area: float, cl: float, cd: float, vertical: bool, rho: float) -> PackedFloat64Array:
	var flow := M.add(v, M.cross(rates, arm))
	var speed := M.sqrt_(M.dot(flow, flow))
	if speed < 1e-10:
		return PackedFloat64Array([0., 0., 0., 0., 0., 0.])
	var plane_speed := M.sqrt_(flow[0]*flow[0] + flow[1 if vertical else 2]*flow[1 if vertical else 2])
	var force := M.scale(flow, -0.5*rho*speed*area*cd)
	if plane_speed > 1e-10:
		var lift := 0.5*rho*plane_speed*plane_speed*area*cl
		force[0] += lift*flow[1 if vertical else 2]/plane_speed
		force[1 if vertical else 2] -= lift*flow[0]/plane_speed
	var moment := M.cross(arm, force)
	return PackedFloat64Array([force[0], force[1], force[2], moment[0], moment[1], moment[2]])


static func _surface_with_flow(flow: PackedFloat64Array, arm: PackedFloat64Array,
		area: float, cl: float, cd: float, vertical: bool, rho: float) -> PackedFloat64Array:
	var speed := M.sqrt_(M.dot(flow, flow))
	if speed < 1e-10:
		return PackedFloat64Array([0., 0., 0., 0., 0., 0.])
	var plane_speed := M.sqrt_(flow[0]*flow[0] + flow[1 if vertical else 2]*flow[1 if vertical else 2])
	var force_scale := -0.5*rho*speed*area*cd
	var fx: float = flow[0] * force_scale
	var fy: float = flow[1] * force_scale
	var fz: float = flow[2] * force_scale
	if plane_speed > 1e-10:
		var lift := 0.5*rho*plane_speed*plane_speed*area*cl
		fx += lift*flow[1 if vertical else 2]/plane_speed
		if vertical:
			fy -= lift*flow[0]/plane_speed
		else:
			fz -= lift*flow[0]/plane_speed
	var mx: float = arm[1] * fz - arm[2] * fy
	var my: float = arm[2] * fx - arm[0] * fz
	var mz: float = arm[0] * fy - arm[1] * fx
	return PackedFloat64Array([fx, fy, fz, mx, my, mz])


static func _tail_curve(alpha: float, slope: float, surfaces: Dictionary) -> float:
	# Continuous periodic flat-plate blend. No raw alpha survives the reverse-flow seam.
	var blend := _smoothstep((absf(alpha) - surfaces.tail_local_limit)/(surfaces.tail_stall_end - surfaces.tail_local_limit))
	return (1.0 - blend)*slope*alpha + blend*0.5*float(surfaces.tail_CD90)*M.sin_(2.0*alpha)


## H12: scalar form of the frozen vector oracle in tests/aero_flow_reference.gd. Every product and sum keeps the
## oracle's order (including the + 0.0 arm terms, which turn -0.0 into +0.0); test_aero_flow.gd compares bytes.
static func _local_loads(s: PackedFloat64Array, air: Dictionary, d: Dictionary, model: Dictionary, rho: float) -> PackedFloat64Array:
	var p: float = s[RB.RATE]
	var q: float = s[RB.RATE+1]
	var r: float = s[RB.RATE+2]
	var v: PackedFloat64Array = air.v_air
	var v0: float = v[0]
	var v1: float = v[1]
	var v2: float = v[2]
	var a: Dictionary = model.aero
	var env: Dictionary = model.envelope
	var ref: Dictionary = model.reference
	var surfaces: Dictionary = model.surfaces
	var cg: PackedFloat64Array = model.cg_le
	var arp: PackedFloat64Array = ref.arp_le
	var ax: float = -(arp[0]-cg[0]) + 0.0
	var ay: float = arp[1]-cg[1]
	var az: float = -(arp[2]-cg[2]) + 0.0
	var twist: PackedFloat64Array = surfaces.get("station_incidence", PackedFloat64Array())
	var has_twist := not twist.is_empty()
	var ys: PackedFloat64Array = env.station_ys
	var stations := ys.size()
	var station_area: float = ref.S / stations
	var aileron_effect: float = surfaces.wing_aileron_effectiveness
	var da_right: float = d.aileron_right
	var da_left: float = d.aileron_left
	var cl0: float = a.CL0
	var cla: float = a.CLa
	var cd0: float = a.CD0
	var k_induced: float = a.k_induced
	var cl_min_d: float = a.CL_minD
	var cd90: float = env.CD90
	var a1: float = env.a1
	var a_span: float = env.a2 - env.a1
	var n1: float = env.n1
	var n_span: float = env.n2 - env.n1
	var lift_q := 0.5*rho
	var drag_q := -0.5*rho
	var fx_sum := 0.0
	var fy_sum := 0.0
	var fz_sum := 0.0
	var mx_sum := 0.0
	var my_sum := 0.0
	var mz_sum := 0.0
	for i in stations:
		var y: float = ys[i]
		var arm_y: float = ay + y
		var f0: float = v0 + (q*az - r*arm_y)
		var f1: float = v1 + (r*ax - p*az)
		var f2: float = v2 + (p*arm_y - q*ax)
		var da: float = da_right if y > 0 else da_left
		var effective := wrapf(M.atan2_(f2, f0) + aileron_effect * da, -PI, PI)
		if has_twist:
			effective = wrapf(effective + twist[i], -PI, PI)
		var weight := _smoothstep((effective - a1) / a_span) if effective >= 0.0 \
			else _smoothstep((-effective - n1) / n_span)
		var base: float = cl0 + cla * effective
		var cl: float = base if weight == 0.0 else (1.0 - weight) * base + weight * 0.5 * cd90 * M.sin_(2.0 * effective)
		var cd: float = cd0 + (1.0-weight)*k_induced*M.pow_(cl-cl_min_d, 2) + weight*cd90*M.pow_(M.sin_(effective), 2)
		var speed := M.sqrt_(f0 * f0 + f1 * f1 + f2 * f2)
		if speed < 1e-10:
			continue # the oracle adds +0.0, which never changes a sum that starts at +0.0
		var plane_speed := M.sqrt_(f0*f0 + f2*f2)
		var force_scale: float = drag_q*speed*station_area*cd
		var fx: float = f0 * force_scale
		var fy: float = f1 * force_scale
		var fz: float = f2 * force_scale
		if plane_speed > 1e-10:
			var lift: float = lift_q*plane_speed*plane_speed*station_area*cl
			fx += lift*f2/plane_speed
			fz -= lift*f0/plane_speed
		fx_sum += fx
		fy_sum += fy
		fz_sum += fz
		mx_sum += arm_y * fz - az * fy
		my_sum += az * fx - ax * fz
		mz_sum += ax * fy - arm_y * fx
	var tail_limit: float = surfaces.tail_local_limit
	var tail_span: float = surfaces.tail_stall_end - surfaces.tail_local_limit
	var tail_cd0: float = surfaces.tail_CD0
	var tail_k: float = surfaces.tail_k
	var tail_cd90: float = surfaces.tail_CD90
	for tail_index in 2: # horizontal, then vertical: the oracle's summation order
		var vertical := tail_index == 1
		var tail: Dictionary = surfaces.vertical if vertical else surfaces.horizontal
		var position: PackedFloat64Array = tail.position
		var tx: float = -(position[0]-cg[0])
		var ty: float = position[1]-cg[1]
		var tz: float = -(position[2]-cg[2])
		var f0: float = v0 + (q*tz - r*ty)
		var f1: float = v1 + (r*tx - p*tz)
		var f2: float = v2 + (p*ty - q*tx)
		var control: float = -float(d.rudder) if vertical else float(d.elevator)
		var normal: float = f1 if vertical else f2
		var effective := wrapf(M.atan2_(normal, f0) + tail.control_effectiveness*control + tail.incidence, -PI, PI)
		var slope: float = tail.lift_slope
		var blend := _smoothstep((absf(effective) - tail_limit)/tail_span)
		var cl: float = (1.0 - blend)*slope*effective + blend*0.5*tail_cd90*M.sin_(2.0*effective)
		var cd: float = tail_cd0 + tail_k*cl*cl + tail_cd90*M.pow_(M.sin_(effective), 2)
		var speed := M.sqrt_(f0 * f0 + f1 * f1 + f2 * f2)
		if speed < 1e-10:
			continue
		var area: float = tail.area
		var plane_speed := M.sqrt_(f0*f0 + normal*normal)
		var force_scale: float = drag_q*speed*area*cd
		var fx: float = f0 * force_scale
		var fy: float = f1 * force_scale
		var fz: float = f2 * force_scale
		if plane_speed > 1e-10:
			var lift: float = lift_q*plane_speed*plane_speed*area*cl
			fx += lift*normal/plane_speed
			if vertical:
				fy -= lift*f0/plane_speed
			else:
				fz -= lift*f0/plane_speed
		fx_sum += fx
		fy_sum += fy
		fz_sum += fz
		mx_sum += ty * fz - tz * fy
		my_sum += tz * fx - tx * fz
		mz_sum += tx * fy - ty * fx
	return PackedFloat64Array([fx_sum, fy_sum, fz_sum, mx_sum, my_sum, mz_sum])


## One tail surface's load about the CG with the law of _local_loads, on `area` (m2), its arm moved by `shift` and
## its velocity through the air changed by `extra` (both body axes). For the slipstream increment (E0b, opt-in).
static func tail_surface_load(v: PackedFloat64Array, rates: PackedFloat64Array, d: Dictionary, model: Dictionary,
		name: String, area: float, shift: PackedFloat64Array, extra: PackedFloat64Array, rho: float) -> PackedFloat64Array:
	var surfaces: Dictionary = model.surfaces
	var tail: Dictionary = surfaces[name]
	var vertical := name == "vertical"
	var arm := M.add(_arm(tail.position, model.cg_le), shift)
	var flow_v := M.add(v, extra)
	var effective := _tail_angle(flow_v, rates, arm, d, tail, vertical)
	var cl := _tail_curve(effective, tail.lift_slope, surfaces)
	var cd: float = surfaces.tail_CD0 + surfaces.tail_k*cl*cl + surfaces.tail_CD90*M.pow_(M.sin_(effective), 2)
	return _surface(flow_v, rates, arm, area, cl, cd, vertical, rho)


## Washed-minus-free load for one immersed tail piece. The two evaluations share their arm and rate cross product.
static func tail_surface_increment(v: PackedFloat64Array, rates: PackedFloat64Array, d: Dictionary, model: Dictionary,
		name: String, area: float, shift: PackedFloat64Array, extra: PackedFloat64Array, rho: float) -> PackedFloat64Array:
	var surfaces: Dictionary = model.surfaces
	var tail: Dictionary = surfaces[name]
	var vertical := name == "vertical"
	var arm := M.add(_arm(tail.position, model.cg_le), shift)
	var rate_arm := M.cross(rates, arm)
	var free_velocity := M.add(v, M.v3(0.0, 0.0, 0.0))
	var free_flow := M.add(free_velocity, rate_arm)
	var washed_velocity := M.add(v, extra)
	var washed_flow := M.add(washed_velocity, rate_arm)
	var free := _tail_surface_from_flow(free_flow, arm, d, tail, surfaces, area, vertical, rho)
	var washed := _tail_surface_from_flow(washed_flow, arm, d, tail, surfaces, area, vertical, rho)
	for k in 6:
		washed[k] -= free[k]
	return washed


static func _tail_surface_from_flow(flow: PackedFloat64Array, arm: PackedFloat64Array, d: Dictionary,
		tail: Dictionary, surfaces: Dictionary, area: float, vertical: bool, rho: float) -> PackedFloat64Array:
	var control: float = -d.rudder if vertical else d.elevator
	var effective := wrapf(M.atan2_(flow[1 if vertical else 2], flow[0])
		+ tail.control_effectiveness*control + tail.incidence, -PI, PI)
	var cl := _tail_curve(effective, tail.lift_slope, surfaces)
	var cd: float = surfaces.tail_CD0 + surfaces.tail_k*cl*cl + surfaces.tail_CD90*M.pow_(M.sin_(effective), 2)
	return _surface_with_flow(flow, arm, area, cl, cd, vertical, rho)


## LE datum [aft,right,up] to a body-axis arm about the current CG.
static func _arm(position: PackedFloat64Array, cg: PackedFloat64Array) -> PackedFloat64Array:
	return M.v3(-(position[0]-cg[0]), position[1]-cg[1], -(position[2]-cg[2]))


static func _tail_angle(v: PackedFloat64Array, rates: PackedFloat64Array, arm: PackedFloat64Array,
		d: Dictionary, tail: Dictionary, vertical: bool) -> float:
	var flow := M.add(v, M.cross(rates, arm))
	return _tail_angle_from_flow(flow, d, tail, vertical)


static func _tail_angle_from_flow(flow: PackedFloat64Array, d: Dictionary, tail: Dictionary, vertical: bool) -> float:
	var control: float = -d.rudder if vertical else d.elevator
	return wrapf(M.atan2_(flow[1 if vertical else 2], flow[0]) + tail.control_effectiveness*control + tail.incidence, -PI, PI)


## 0 = empirical attached oracle; 1 = complete local model. Includes tail/control angles,
## not just body alpha: a rapid pitch or a deflected tail can leave the oracle while the wing is attached.
static func local_flow_weight(s: PackedFloat64Array, air: Dictionary, d: Dictionary, model: Dictionary) -> float:
	var env: Dictionary = model.envelope
	var surfaces: Dictionary = model.surfaces
	var limit: float = surfaces.attached_limit
	var v: PackedFloat64Array = air.v_air
	# Only angle components are needed; preserve vector-form product/sum order.
	var p: float = s[RB.RATE]
	var q: float = s[RB.RATE+1]
	var r: float = s[RB.RATE+2]
	var a1: float = env.a1
	var a1_span: float = a1 - limit
	var blend := maxf(_smoothstep((absf(air.alpha)-limit)/a1_span), sideslip_weight(air.beta, env))
	if blend == 1.0:
		return blend
	# H15: dictionary reads hoisted out of the loops; every product, sum and comparison is unchanged.
	var v0: float = v[0]
	var v1: float = v[1]
	var v2: float = v[2]
	var n1_span: float = float(env.n1) - limit
	var position: PackedFloat64Array = model.reference.arp_le
	var cg: PackedFloat64Array = model.cg_le
	var arm_x: float = -(position[0]-cg[0]) + 0.0
	var arm_y: float = position[1]-cg[1]
	var arm_z: float = -(position[2]-cg[2]) + 0.0
	var twist: PackedFloat64Array = surfaces.get("station_incidence", PackedFloat64Array())
	var has_twist := not twist.is_empty()
	var ys: PackedFloat64Array = env.station_ys
	var aileron_effect: float = surfaces.wing_aileron_effectiveness
	var da_right: float = d.aileron_right
	var da_left: float = d.aileron_left
	for i in ys.size():
		var y: float = ys[i]
		var station_y: float = arm_y + y
		var flow_x: float = v0 + (q*arm_z - r*station_y)
		var flow_z: float = v2 + (p*station_y - q*arm_x)
		var da: float = da_right if y > 0 else da_left
		var angle := wrapf(M.atan2_(flow_z, flow_x) + aileron_effect*da, -PI, PI)
		if has_twist:
			angle = wrapf(angle + twist[i], -PI, PI)
		blend = maxf(blend, _smoothstep((absf(angle)-limit)/(a1_span if angle >= 0.0 else n1_span)))
		if blend == 1.0:
			return blend
	var tail_span: float = float(surfaces.tail_local_limit) - limit
	for tail_index in 2: # horizontal, then vertical
		var vertical := tail_index == 1
		var tail: Dictionary = surfaces.vertical if vertical else surfaces.horizontal
		var tail_position: PackedFloat64Array = tail.position
		var tx: float = -(tail_position[0]-cg[0])
		var ty: float = tail_position[1]-cg[1]
		var tz: float = -(tail_position[2]-cg[2])
		var flow_x: float = v0 + (q*tz - r*ty)
		var component: float = v1 + (r*tx - p*tz) if vertical else v2 + (p*ty - q*tx)
		var control: float = -float(d.rudder) if vertical else float(d.elevator)
		var angle: float = wrapf(M.atan2_(component, flow_x) + tail.control_effectiveness*control + tail.incidence, -PI, PI)
		blend = maxf(blend, _smoothstep((absf(angle)-limit)/tail_span))
	return blend


static func loads(s: PackedFloat64Array, air: Dictionary, d: Dictionary, model: Dictionary, rho: float) -> PackedFloat64Array:
	if model.get("envelope", {}).is_empty():
		return _global_loads(s, air, d, model, rho)
	var blend := local_flow_weight(s, air, d, model)
	if blend == 0.0:
		return _global_loads(s, air, d, model, rho)
	var local := _local_loads(s, air, d, model, rho)
	if blend == 1.0:
		return local
	var global := _global_loads(s, air, d, model, rho)
	for k in 6:
		global[k] = lerpf(global[k], local[k], blend)
	return global

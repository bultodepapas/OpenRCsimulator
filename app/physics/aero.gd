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
	var cd_aero: float = a.CD0 + a.k_induced * pow(cl - a.CL_minD, 2)
	if not env.is_empty():
		cl = lift_alpha(alpha, a, env) + cl_controls
		cd_aero = (1.0 - w) * cd_aero + w * (a.CD0 + env.CD90 * sin(alpha) * sin(alpha))
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
	var co := coefficients(air, PackedFloat64Array([p, q, r]), d, a, model.get("envelope", {}))

	# Rate (damping) terms in dimensional form: qbar·x̂ = ½ρV²·(rate·L/2V) = ¼ρ·V·rate·L. Finite as V → 0.
	var k := 0.25 * rho * float(air.V)
	var cl_rate: float = k * c * a.CLq * q # = qbar·CLq·q̂
	var cy_rate: float = k * b * (a.CYp * p + a.CYr * r)
	var roll_rate: float = k * b * (a.Clp * p + a.Clr * r)
	var pitch_rate: float = k * c * a.Cmq * q
	var yaw_rate: float = k * b * (a.Cnp * p + a.Cnr * r)

	var lift: float = (qbar * co.CL + cl_rate) * S
	var drag: float = qbar * co.CD * S
	var side: float = (qbar * co.CY + cy_rate) * S

	# Wind axes → body axes. Wind-axis force = [-D, Y, -L].
	var ca := M.cos_(air.alpha)
	var sa := M.sin_(air.alpha)
	var cb := M.cos_(air.beta)
	var sb := M.sin_(air.beta)
	var fx: float = ca * cb * (-drag) - ca * sb * side + sa * lift
	var fy: float = sb * (-drag) + cb * side
	var fz: float = sa * cb * (-drag) - sa * sb * side - ca * lift

	# Moments about the aero reference point, then transferred to the CG: M_cg = M_arp + r × F, r = arp − cg (body).
	var mx: float = (qbar * co.Cl + roll_rate) * S * b
	var my: float = (qbar * co.Cm + pitch_rate) * S * c
	var mz: float = (qbar * co.Cn + yaw_rate) * S * b
	var arp: PackedFloat64Array = ref.arp_le
	var cg: PackedFloat64Array = model.cg_le
	var rr := M.v3(-(arp[0] - cg[0]), arp[1] - cg[1], -(arp[2] - cg[2])) # le frame → body FRD
	var transfer := M.cross(rr, M.v3(fx, fy, fz))
	return PackedFloat64Array([fx, fy, fz, mx + transfer[0], my + transfer[1], mz + transfer[2]])


# Local surface loads: lift is perpendicular to local velocity, drag opposes it;
# the moment is exactly r cross F. Passive by construction for fixed controls.
static func _surface(v: PackedFloat64Array, rates: PackedFloat64Array, arm: PackedFloat64Array,
		area: float, cl: float, cd: float, vertical: bool, rho: float) -> PackedFloat64Array:
	var flow := M.add(v, M.cross(rates, arm))
	var speed := sqrt(M.dot(flow, flow))
	if speed < 1e-10:
		return PackedFloat64Array([0., 0., 0., 0., 0., 0.])
	var plane_speed := sqrt(flow[0]*flow[0] + flow[1 if vertical else 2]*flow[1 if vertical else 2])
	var force := M.scale(flow, -0.5*rho*speed*area*cd)
	if plane_speed > 1e-10:
		var lift := 0.5*rho*plane_speed*plane_speed*area*cl
		force[0] += lift*flow[1 if vertical else 2]/plane_speed
		force[1 if vertical else 2] -= lift*flow[0]/plane_speed
	var moment := M.cross(arm, force)
	return PackedFloat64Array([force[0], force[1], force[2], moment[0], moment[1], moment[2]])


static func _add_load(out: PackedFloat64Array, l: PackedFloat64Array) -> void:
	for k in 6:
		out[k] += l[k]


static func _tail_curve(alpha: float, slope: float, surfaces: Dictionary) -> float:
	# Continuous periodic flat-plate blend. No raw alpha survives the reverse-flow seam.
	var blend := _smoothstep((absf(alpha) - surfaces.tail_local_limit)/(surfaces.tail_stall_end - surfaces.tail_local_limit))
	return (1.0 - blend)*slope*alpha + blend*0.5*float(surfaces.tail_CD90)*sin(2.0*alpha)


static func _local_loads(s: PackedFloat64Array, air: Dictionary, d: Dictionary, model: Dictionary, rho: float) -> PackedFloat64Array:
	var out := PackedFloat64Array([0., 0., 0., 0., 0., 0.])
	var rates := s.slice(RB.RATE, RB.RATE+3)
	var v: PackedFloat64Array = air.v_air
	var a: Dictionary = model.aero
	var env: Dictionary = model.envelope
	var ref: Dictionary = model.reference
	var surfaces: Dictionary = model.surfaces
	var ar := M.v3(-(ref.arp_le[0]-model.cg_le[0]), ref.arp_le[1]-model.cg_le[1], -(ref.arp_le[2]-model.cg_le[2]))
	var twist: PackedFloat64Array = surfaces.get("station_incidence", PackedFloat64Array())
	for i in env.station_ys.size():
		var y: float = env.station_ys[i]
		var arm := M.add(ar, M.v3(0, y, 0))
		var flow := M.add(v, M.cross(rates, arm))
		var da: float = d.aileron_right if y > 0 else d.aileron_left
		var effective := wrapf(atan2(flow[2], flow[0]) + surfaces.wing_aileron_effectiveness * da, -PI, PI)
		if not twist.is_empty():
			effective = wrapf(effective + twist[i], -PI, PI)
		var cl := lift_alpha(effective, a, env)
		var weight := stall_weight(effective, env)
		var cd: float = a.CD0 + (1.0-weight)*a.k_induced*pow(cl-a.CL_minD, 2) + weight*env.CD90*pow(sin(effective), 2)
		_add_load(out, _surface(v, rates, arm, ref.S / env.station_ys.size(), cl, cd, false, rho))
	for name in ["horizontal", "vertical"]:
		var tail: Dictionary = surfaces[name]
		var vertical: bool = name == "vertical"
		var arm := _arm(tail.position, model.cg_le)
		var effective := _tail_angle(v, rates, arm, d, tail, vertical)
		var cl := _tail_curve(effective, tail.lift_slope, surfaces)
		var cd: float = surfaces.tail_CD0 + surfaces.tail_k*cl*cl + surfaces.tail_CD90*pow(sin(effective), 2)
		_add_load(out, _surface(v, rates, arm, tail.area, cl, cd, vertical, rho))
	return out


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
	var cd: float = surfaces.tail_CD0 + surfaces.tail_k*cl*cl + surfaces.tail_CD90*pow(sin(effective), 2)
	return _surface(flow_v, rates, arm, area, cl, cd, vertical, rho)


## LE datum [aft,right,up] to a body-axis arm about the current CG.
static func _arm(position: PackedFloat64Array, cg: PackedFloat64Array) -> PackedFloat64Array:
	return M.v3(-(position[0]-cg[0]), position[1]-cg[1], -(position[2]-cg[2]))


static func _tail_angle(v: PackedFloat64Array, rates: PackedFloat64Array, arm: PackedFloat64Array,
		d: Dictionary, tail: Dictionary, vertical: bool) -> float:
	var flow := M.add(v, M.cross(rates, arm))
	var control: float = -d.rudder if vertical else d.elevator
	return wrapf(atan2(flow[1 if vertical else 2], flow[0]) + tail.control_effectiveness*control + tail.incidence, -PI, PI)


## 0 = empirical attached oracle; 1 = complete local model. Includes tail/control angles,
## not just body alpha: a rapid pitch or a deflected tail can leave the oracle while the wing is attached.
static func local_flow_weight(s: PackedFloat64Array, air: Dictionary, d: Dictionary, model: Dictionary) -> float:
	var env: Dictionary = model.envelope
	var surfaces: Dictionary = model.surfaces
	var limit: float = surfaces.attached_limit
	var v: PackedFloat64Array = air.v_air
	var rates := s.slice(RB.RATE, RB.RATE+3)
	var blend := maxf(_smoothstep((absf(air.alpha)-limit)/(env.a1-limit)), sideslip_weight(air.beta, env))
	if blend == 1.0:
		return blend
	var arp := _arm(model.reference.arp_le, model.cg_le)
	var twist: PackedFloat64Array = surfaces.get("station_incidence", PackedFloat64Array())
	for i in env.station_ys.size():
		var y: float = env.station_ys[i]
		var flow := M.add(v, M.cross(rates, M.add(arp, M.v3(0, y, 0))))
		var da: float = d.aileron_right if y > 0 else d.aileron_left
		var angle := wrapf(atan2(flow[2], flow[0]) + surfaces.wing_aileron_effectiveness*da, -PI, PI)
		if not twist.is_empty():
			angle = wrapf(angle + twist[i], -PI, PI)
		var end: float = env.a1 if angle >= 0.0 else env.n1
		blend = maxf(blend, _smoothstep((absf(angle)-limit)/(end-limit)))
		if blend == 1.0:
			return blend
	for name in ["horizontal", "vertical"]:
		var tail: Dictionary = surfaces[name]
		var angle := _tail_angle(v, rates, _arm(tail.position, model.cg_le), d, tail, name == "vertical")
		blend = maxf(blend, _smoothstep((absf(angle)-limit)/(surfaces.tail_local_limit-limit)))
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

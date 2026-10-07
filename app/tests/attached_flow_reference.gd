# H15: frozen attached-flow oracle, before scalar allocation removal. Verbatim copies of Aero._global_loads,
# Aero.coefficients and their helpers, Air.compute, and the math3d vector/quaternion helpers they reach, at 77cdae9.
extends RefCounted
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const RHO_SEA_LEVEL := 1.225


static func global_loads(s: PackedFloat64Array, air: Dictionary, d: Dictionary, model: Dictionary, rho: float) -> PackedFloat64Array:
	var ref: Dictionary = model.reference
	var a: Dictionary = model.aero
	var S: float = ref.S
	var b: float = ref.b
	var c: float = ref.c
	var qbar: float = air.qbar
	var p := s[RB.RATE]
	var q := s[RB.RATE + 1]
	var r := s[RB.RATE + 2]
	var co := _h15_coefficients(air, PackedFloat64Array([p, q, r]), d, a, model.get("envelope", {}))

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
	var rr := _v3(-(arp[0] - cg[0]), arp[1] - cg[1], -(arp[2] - cg[2])) # le frame → body FRD
	var transfer := _cross(rr, _v3(fx, fy, fz))
	return PackedFloat64Array([fx, fy, fz, mx + transfer[0], my + transfer[1], mz + transfer[2]])


static func _h15_coefficients(air: Dictionary, rates: PackedFloat64Array, d: Dictionary, a: Dictionary, env := {}) -> Dictionary:
	var alpha: float = air.alpha
	var beta: float = air.beta
	var de: float = d.elevator
	var dar: float = d.aileron_right
	var dal: float = d.aileron_left
	var dr: float = d.rudder
	var w := _h15_stall_weight(alpha, env)
	var wb := _h15_sideslip_weight(beta, env)
	var sb := beta if wb == 0.0 else (1.0 - wb) * beta + wb * M.sin_(beta) # effective sideslip for the β terms
	var cl_controls: float = a.CLde * de + a.CLda_each * (dar + dal)
	var cl: float = a.CL0 + a.CLa * alpha + cl_controls
	var cd_aero: float = a.CD0 + a.k_induced * M.pow_(cl - a.CL_minD, 2)
	if not env.is_empty():
		cl = _h15_lift_alpha(alpha, a, env) + cl_controls
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


static func _h15_stall_weight(alpha: float, env: Dictionary) -> float:
	if env.is_empty():
		return 0.0
	if alpha >= 0.0:
		return _h15_smoothstep((alpha - env.a1) / (env.a2 - env.a1))
	return _h15_smoothstep((-alpha - env.n1) / (env.n2 - env.n1))


static func _h15_sideslip_weight(beta: float, env: Dictionary) -> float:
	return 0.0 if env.is_empty() else _h15_smoothstep((absf(beta) - env.b1) / (env.b2 - env.b1))


static func _h15_lift_alpha(alpha: float, a: Dictionary, env: Dictionary) -> float:
	var base: float = a.CL0 + a.CLa * alpha
	var w := _h15_stall_weight(alpha, env)
	return base if w == 0.0 else (1.0 - w) * base + w * 0.5 * float(env.CD90) * M.sin_(2.0 * alpha)


static func _h15_smoothstep(x: float) -> float:
	if x <= 0.0:
		return 0.0
	if x >= 1.0:
		return 1.0
	return x * x * (3.0 - 2.0 * x)


static func air_compute(s: PackedFloat64Array, wind_ned: PackedFloat64Array, rho := RHO_SEA_LEVEL) -> Dictionary:
	var q := _quat(s[RB.ATT], s[RB.ATT + 1], s[RB.ATT + 2], s[RB.ATT + 3])
	var wind_body := _q_rotate(_q_conj(q), wind_ned)
	var u := s[RB.VEL] - wind_body[0]
	var v := s[RB.VEL + 1] - wind_body[1]
	var w := s[RB.VEL + 2] - wind_body[2]
	var speed := M.sqrt_(u * u + v * v + w * w)
	return {
		v_air = _v3(u, v, w),
		V = speed,
		alpha = M.atan2_(w, u),
		# atan2 form of asin(v / V): identical for V > 0, and well defined at V = 0.
		beta = M.atan2_(v, M.sqrt_(u * u + w * w)),
		qbar = 0.5 * rho * speed * speed,
	}


static func _quat(w: float, x: float, y: float, z: float) -> PackedFloat64Array:
	return PackedFloat64Array([w, x, y, z])


static func _q_conj(q: PackedFloat64Array) -> PackedFloat64Array:
	return _quat(q[0], -q[1], -q[2], -q[3])


static func _q_rotate(q: PackedFloat64Array, v: PackedFloat64Array) -> PackedFloat64Array:
	var u := _v3(q[1], q[2], q[3])
	var t := _scale(_cross(u, v), 2.0)
	return _add(_add(v, _scale(t, q[0])), _cross(u, t))


static func _v3(x: float, y: float, z: float) -> PackedFloat64Array:
	return PackedFloat64Array([x, y, z])


static func _add(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return _v3(a[0] + b[0], a[1] + b[1], a[2] + b[2])


static func _scale(a: PackedFloat64Array, k: float) -> PackedFloat64Array:
	return _v3(a[0] * k, a[1] * k, a[2] * k)


static func _cross(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return _v3(a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])

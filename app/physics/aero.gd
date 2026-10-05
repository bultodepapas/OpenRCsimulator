# Six-axis aerodynamic model: linear (D3) inside the attached-flow region, full envelope beyond it (D9a).
# 64-bit floats only (guarded).
# Coefficients and their conventions come from the aircraft data file (app/data/aircraft/, see "aero.conventions"):
#   rates p̂ = p·b/2V, q̂ = q·c/2V, r̂ = r·b/2V; elevator and each aileron +TE down; rudder +TE left;
#   lift/drag/side in wind axes; moments in body axes about the aero reference point.
# Output: body-axis loads about the CG, gravity excluded: [Fx, Fy, Fz, Mx, My, Mz] (N, N·m).
# Full envelope (D9a, model.envelope from AircraftData): past the stall start the lift, drag and pitching moment blend
# smoothly (smoothstep weight w) into flat-plate forms: CL → (CD90/2)·sin 2α, CD → CD0 + CD90·sin²α, Cm0 + Cmα·α →
# Cm0 + Cmα·sin α (restoring up to 90°, unstable tail-first); beyond the sideslip blend the β terms use sin β.
# Where the weights are 0 (|α| below the stall start, |β| below the sideslip blend) the result is EXACTLY the
# linear model, which stays the test oracle (an empty envelope = the linear model everywhere).
# Asymmetric stall (D9b, as CRRCSim does it with three): the wing is checked at WING_STATIONS_PER_SIDE equal-area strips
# per side, each at its local α from the roll and yaw rates (α_i = atan2(w + p·y_i, u − r·y_i)). Only the stall DEFICIT against the linear
# model is added (lift, drag, and the roll/yaw moments of their left/right difference), so the linear rate damping is
# not counted twice: a stalling down-going wing loses lift and gains drag → it keeps rolling (autorotation: spins,
# snaps, tip stalls). Pitch uses the body α (D9a). The station moments are scaled by κ = |Clp| / (CLα·Σ…) so that the
# strips reproduce the data's roll damping exactly in attached flow (strip theory alone gives a different value). Two
# stations were too coarse: at high roll rates the up-going one stayed attached and the roll ran away (D9b log). The drag deficit
# for the FORCE cancels the linear drag exactly (so a fully stalled wing has flat-plate drag); for the YAW moment it is
# measured against the linear drag at the lift capped to the stall limits (beyond them induced drag means nothing).
# Not modelled yet: CLα̇, propwash, ground effect, compressibility (irrelevant here).
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

## Strips per wing side for the asymmetric stall (model resolution, not aircraft data). 2 stations per wing ran away.
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
## Rate terms are returned already multiplied by V so callers never divide by airspeed:
##   coefficient = static + (rate_term / (2V)); see loads().
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
	var cl_roll := 0.0
	var cn_yaw := 0.0
	if not env.is_empty():
		# Strips at signed y_i (left negative, right positive), local α from the body flow plus ω × r.
		var ys: PackedFloat64Array = env.station_ys
		var n := ys.size()
		var alphas := PackedFloat64Array()
		alphas.resize(n)
		var has_flow: bool = air.has("v_air")
		var v: PackedFloat64Array = air.v_air if has_flow else PackedFloat64Array()
		for i in n:
			alphas[i] = M.atan2_(v[2] + rates[0] * ys[i], v[0] - rates[2] * ys[i]) if has_flow else alpha
		var dcl := PackedFloat64Array()
		var dcd := PackedFloat64Array()
		var dcn := PackedFloat64Array() # normal-force deficit (body z): the roll moment
		var dca := PackedFloat64Array() # axial-force deficit (body x), against the capped linear model: the yaw moment
		for arr in [dcl, dcd, dcn, dca]:
			arr.resize(n)
		var any_stall := false
		for i in n:
			var wi := stall_weight(alphas[i], env)
			if wi != 0.0:
				any_stall = true
				var ai := alphas[i]
				var lin_i: float = a.CL0 + a.CLa * ai + cl_controls
				var capped := clampf(lin_i, env.CL_min, env.CL_max)
				var si := M.sin_(ai)
				var ci := M.cos_(ai)
				var plate_cl: float = 0.5 * float(env.CD90) * M.sin_(2.0 * ai) + cl_controls
				var plate_cd: float = a.CD0 + float(env.CD90) * si * si
				var lin_cd: float = a.CD0 + a.k_induced * pow(lin_i - a.CL_minD, 2)
				var cap_cd: float = a.CD0 + a.k_induced * pow(capped - a.CL_minD, 2)
				dcl[i] = wi * (plate_cl - lin_i)
				dcd[i] = wi * (plate_cd - lin_cd)
				# Body axes: CN = CL·cos α + CD·sin α (up the wing's normal), CA = CD·cos α − CL·sin α (aft).
				dcn[i] = wi * ((plate_cl - lin_i) * ci + (plate_cd - lin_cd) * si)
				dca[i] = wi * ((plate_cd * ci - plate_cl * si) - (cap_cd * ci - capped * si))
		if any_stall:
			# Equal strips S/n: ΔCL, ΔCD = means; ΔCl = −κ·Σ ΔCN_i·(1/n)·(y_i/b); ΔCn = κ·Σ ΔCA_i·(1/n)·(y_i/b).
			var kappa: float = env.station_kappa
			var b: float = env.span
			var sum_l := 0.0
			var sum_d := 0.0
			var roll := 0.0
			var yaw := 0.0
			for i in n:
				sum_l += dcl[i]
				sum_d += dcd[i]
			# Mirror pairs (left strip k, right strip k + n/2, same |y|): a symmetric stall gives exactly zero.
			var half := n / 2
			for k in half:
				var arm: float = ys[k + half] / b
				roll += (dcn[k + half] - dcn[k]) * arm
				yaw += (dca[k + half] - dca[k]) * arm
			cl += sum_l / n
			cd_aero += sum_d / n
			cl_roll = -kappa * roll / n
			cn_yaw = kappa * yaw / n
	var cd: float = cd_aero + absf(a.CDda_each * dar) + absf(a.CDda_each * dal) + absf(a.CDdr * dr) + absf(a.CDde * de)
	var cm_alpha: float = a.Cm0 + a.Cma * alpha
	if w != 0.0:
		cm_alpha = (1.0 - w) * cm_alpha + w * (a.Cm0 + a.Cma * M.sin_(alpha))
	var cl_total: float = a.Clb * sb + a.Clda_right * dar + a.Clda_left * dal + a.Cldr * dr
	var cn_total: float = a.Cnb * sb + a.Cnda_right * dar + a.Cnda_left * dal + a.Cndr * dr
	return {
		CL = cl, CD = cd,
		CY = a.CYb * sb + a.CYdr * dr,
		Cl = cl_total if cl_roll == 0.0 else cl_total + cl_roll,
		Cm = cm_alpha + a.Cmde * de + a.Cmda_each * (dar + dal),
		Cn = cn_total if cn_yaw == 0.0 else cn_total + cn_yaw,
	}


## Body loads about the CG [Fx, Fy, Fz, Mx, My, Mz], gravity excluded.
## model: AircraftData model (reference S, b, c, arp_le; cg_le; aero).
static func loads(s: PackedFloat64Array, air: Dictionary, d: Dictionary, model: Dictionary, rho: float) -> PackedFloat64Array:
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

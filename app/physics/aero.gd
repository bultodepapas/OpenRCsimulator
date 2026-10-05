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
# Asymmetric stall (D9b, as CRRCSim does it): the wing is checked at two half-wing stations (y = ±b/4), each at its
# local α from the roll and yaw rates (α_i = atan2(w + p·y_i, u − r·y_i)). Only the stall DEFICIT against the linear
# model is added (lift, drag, and the roll/yaw moments of their left/right difference), so the linear rate damping is
# not counted twice: a stalling down-going wing loses lift and gains drag → it keeps rolling (autorotation: spins,
# snaps, tip stalls). Pitch uses the body α (D9a).
# Not modelled yet: CLα̇, propwash, ground effect, compressibility (irrelevant here).
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")


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
		# Half-wing stations: [left (y = −Y), right (y = +Y)], local α from the body flow plus ω × r.
		var alphas := PackedFloat64Array([alpha, alpha])
		if air.has("v_air"):
			var v: PackedFloat64Array = air.v_air
			var y: float = env.station_y
			alphas = PackedFloat64Array([M.atan2_(v[2] - rates[0] * y, v[0] + rates[2] * y), M.atan2_(v[2] + rates[0] * y, v[0] - rates[2] * y)])
		var dcl := PackedFloat64Array([0.0, 0.0])
		var dcd := PackedFloat64Array([0.0, 0.0])
		for i in 2:
			var wi := stall_weight(alphas[i], env)
			if wi != 0.0:
				var ai := alphas[i]
				var lin_i: float = a.CL0 + a.CLa * ai + cl_controls
				var si := M.sin_(ai)
				dcl[i] = wi * (0.5 * float(env.CD90) * M.sin_(2.0 * ai) + cl_controls - lin_i)
				dcd[i] = wi * (a.CD0 + float(env.CD90) * si * si - (a.CD0 + a.k_induced * pow(lin_i - a.CL_minD, 2)))
		if dcl[0] != 0.0 or dcl[1] != 0.0:
			cl += 0.5 * (dcl[0] + dcl[1])
			cd_aero += 0.5 * (dcd[0] + dcd[1])
			# Each half-wing has S/2 at |y| = b/4: ΔCl = −Σ ΔCL_i·(S_i/S)·(y_i/b), ΔCn = Σ ΔCD_i·(S_i/S)·(y_i/b).
			cl_roll = -(dcl[1] - dcl[0]) / 8.0
			cn_yaw = (dcd[1] - dcd[0]) / 8.0
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

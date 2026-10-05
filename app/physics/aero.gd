# Linear six-axis aerodynamic model (D3). 64-bit floats only (guarded).
# Coefficients and their conventions come from the aircraft data file (app/data/aircraft/, see "aero.conventions"):
#   rates p̂ = p·b/2V, q̂ = q·c/2V, r̂ = r·b/2V; elevator and each aileron +TE down; rudder +TE left;
#   lift/drag/side in wind axes; moments in body axes about the aero reference point.
# Output: body-axis loads about the CG, gravity excluded: [Fx, Fy, Fz, Mx, My, Mz] (N, N·m).
# Not modelled yet: stall (D9), CLα̇, propwash, ground effect, compressibility (irrelevant here).
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


## Nondimensional coefficients for the given air data, body rates (rad/s) and deflections (data conventions).
## Rate terms are returned already multiplied by V so callers never divide by airspeed:
##   coefficient = static + (rate_term / (2V)); see loads().
static func coefficients(air: Dictionary, rates: PackedFloat64Array, d: Dictionary, a: Dictionary) -> Dictionary:
	var alpha: float = air.alpha
	var beta: float = air.beta
	var de: float = d.elevator
	var dar: float = d.aileron_right
	var dal: float = d.aileron_left
	var dr: float = d.rudder
	var cl: float = a.CL0 + a.CLa * alpha + a.CLde * de + a.CLda_each * (dar + dal)
	var cd: float = a.CD0 + a.k_induced * pow(cl - a.CL_minD, 2) \
		+ absf(a.CDda_each * dar) + absf(a.CDda_each * dal) + absf(a.CDdr * dr) + absf(a.CDde * de)
	return {
		CL = cl, CD = cd,
		CY = a.CYb * beta + a.CYdr * dr,
		Cl = a.Clb * beta + a.Clda_right * dar + a.Clda_left * dal + a.Cldr * dr,
		Cm = a.Cm0 + a.Cma * alpha + a.Cmde * de + a.Cmda_each * (dar + dal),
		Cn = a.Cnb * beta + a.Cnda_right * dar + a.Cnda_left * dal + a.Cndr * dr,
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
	var co := coefficients(air, PackedFloat64Array([p, q, r]), d, a)

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

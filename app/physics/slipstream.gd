# E0b, first slice (opt-in per aircraft, P51-12): the propeller's slipstream on the tail surfaces.
# Momentum theory (actuator disc): disc induced velocity w = ½(−u + sqrt(u² + 2T/(ρA))), far-wake radius
# r_s = R·sqrt((u + w)/(u + 2w)). The velocity added at the tail is k_w·w, with k_w rising linearly from the static to
# the forward-flight value over the mass-flow ratio m = u/(u + w) ∈ [0, 0.75] (Selig 2010, AIAA 2010-7938, Fig. 5:
# 0.8 and 1.8, below the ideal 2 because of the fuselage). Swirl: the shaft torque leaves as angular momentum flux
# Q = ṁ·r·v_t at every radius (free vortex, core clamped at 0.3R), ṁ = ρπR²(u + w), decayed with the axial wash (k_w/2)
# and times a straightening factor.
# Each tail piece (the fin, each stab half) is a strip along its span with a linear chord; the part of it inside the
# slipstream circle (around the shaft axis, drifted with the free stream at angle of attack and sideslip) gets the
# INCREMENT  F(local tail law with the washed flow) − F(same law with the free stream), so the free-stream tail
# (oracle or local model) is untouched and a stopped propeller adds exactly nothing.
# Not modelled: wing in the slipstream, fuselage scrubbing drag, wash lag. 64-bit floats only (guarded).
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Aero := preload("res://physics/aero.gd")
const Propulsion := preload("res://physics/propulsion.gd")

## The mass-flow speed u + w used for the swirl never falls below this (m/s).
const SWIRL_SPEED_FLOOR := 1.0
## Wake radius limits as a fraction of the propeller radius: full contraction at rest (1/√2), expansion behind a
## braking (negative-thrust) propeller capped at 1.5.
const RADIUS_MIN := 0.7071
const RADIUS_MAX := 1.5


## Derived data (AircraftData model.propulsion.slipstream): { hub (le), wash_factor [static, forward], swirl_factor,
## vertical_drift,
## pieces: [{
## surface, area (m2), root (le), span_dir (le unit), span (m), chords [root, tip] }] }.
## Returns body loads [Fx, Fy, Fz, Mx, My, Mz] about the CG.
static func loads(state: PackedFloat64Array, air: Dictionary, d: Dictionary, model: Dictionary, rpm: float,
		rho: float) -> PackedFloat64Array:
	var out := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var prop: Dictionary = model.propulsion
	if rpm < Propulsion.STOPPED_RPM:
		return out
	var tq := Propulsion.thrust_torque(air.v_air, rpm, prop, rho)
	var w := wake(air.v_air, tq[0], tq[1], prop, rho)
	var ss: Dictionary = prop.slipstream
	var v: PackedFloat64Array = air.v_air
	var rates := state.slice(RB.RATE, RB.RATE + 3)
	var speed := sqrt(M.dot(v, v))
	for piece in ss.pieces:
		var im := immersion(piece, w, ss.hub, prop, v, speed, model)
		if im.area <= 0.0:
			continue
		var extra := M.sub(M.scale(Propulsion.axis(prop), w.dv), im.swirl)
		var washed := Aero.tail_surface_load(v, rates, d, model, piece.surface, im.area, im.shift, extra, rho)
		var free := Aero.tail_surface_load(v, rates, d, model, piece.surface, im.area, im.shift, M.v3(0, 0, 0), rho)
		for k in 6:
			out[k] += washed[k] - free[k]
	return out


## Wake state: { u (axial airspeed), w (disc induced velocity), dv (velocity increment at the tail), rs (radius),
## swirl (free-vortex strength k·Q/ṁ, m²/s: v_t = swirl/r; + = clockwise from behind), core (m) }.
static func wake(v_air: PackedFloat64Array, thrust: float, torque: float, prop: Dictionary, rho: float) -> Dictionary:
	var ss: Dictionary = prop.slipstream
	var R: float = 0.5 * prop.diameter
	var area := PI * R * R
	var u := maxf(M.dot(v_air, Propulsion.axis(prop)), 0.0)
	var vs := sqrt(maxf(u * u + 2.0 * thrust / (rho * area), 0.0))
	var w := 0.5 * (vs - u)
	var ratio := clampf((u + w) / maxf(u + 2.0 * w, 1e-6), RADIUS_MIN * RADIUS_MIN, RADIUS_MAX * RADIUS_MAX)
	var m := u / maxf(u + w, 1e-6) if w > 0.0 else 1.0
	var k_w: float = lerpf(ss.wash_factor[0], ss.wash_factor[1], clampf(m / 0.75, 0.0, 1.0))
	# Mixing that leaves k_w·w of the ideal 2w at the tail spreads the angular momentum over proportionally more air:
	# the tangential velocity falls by the same k_w/2, so the swirl ANGLE is the ideal wake's times swirl_factor.
	var swirl: float = ss.swirl_factor * 0.5 * k_w * torque / (rho * area * maxf(u + w, SWIRL_SPEED_FLOOR))
	return { u = u, w = w, vs = u + 2.0 * w, dv = k_w * w, rs = R * sqrt(ratio), swirl = swirl, core = 0.3 * R }


## The immersed part of one piece: { area (m2), shift (body arm change from the surface's reference position),
## swirl (body air velocity at the immersed centroid) }. The wake centre at the piece follows the shaft from the
## hub and drifts with the free stream by the angle (V/V_s)·(flow angle) over the distance from the hub.
static func immersion(piece: Dictionary, w: Dictionary, hub: PackedFloat64Array, prop: Dictionary,
		v: PackedFloat64Array, speed: float, model: Dictionary) -> Dictionary:
	var none := { area = 0.0, shift = M.v3(0, 0, 0), swirl = M.v3(0, 0, 0) }
	var root: PackedFloat64Array = piece.root
	var ax := Propulsion.axis(prop) # body
	var ax_le := M.v3(-ax[0], ax[1], -ax[2]) # le frame, pointing forward (x_aft negative)
	var dist := root[0] - hub[0] # aft distance hub → piece (m)
	var centre := M.add(hub, M.scale(ax_le, dist / ax_le[0])) # ax_le[0] < 0: steps aft along the shaft
	if speed > 1e-6 and w.vs > 1e-6:
		# Free-stream drift over the travel time dist/(u + w): the wake leans with the airflow (body w > 0: flow from
		# below, wake rises aft, less the wing's downwash: vertical_drift = 1 − dε/dα); sideslip pushes it sideways.
		var lean := minf(speed / (w.u + w.w), 1.0) * dist / speed
		centre[1] -= v[1] * lean
		centre[2] += v[2] * lean * float(prop.slipstream.vertical_drift)
	var e: PackedFloat64Array = piece.span_dir
	var rel := M.sub(root, centre)
	var along := M.dot(rel, e)
	var perp := M.sub(rel, M.scale(e, along))
	var d2 := M.dot(perp, perp)
	var rs: float = w.rs
	if d2 >= rs * rs:
		return none
	var half := sqrt(rs * rs - d2)
	var span: float = piece.span
	var a := clampf(-along - half, 0.0, span)
	var b := clampf(-along + half, 0.0, span)
	if b <= a:
		return none
	var c0: float = piece.chords[0]
	var slope: float = (piece.chords[1] - c0) / span
	var area_of := func(x: float) -> float: return c0 * x + 0.5 * slope * x * x
	var moment_of := func(x: float) -> float: return 0.5 * c0 * x * x + slope * x * x * x / 3.0
	var area: float = area_of.call(b) - area_of.call(a)
	var full: float = area_of.call(span)
	if area <= 0.0:
		return none
	var eta: float = (moment_of.call(b) - moment_of.call(a)) / area
	var point := M.add(root, M.scale(e, eta)) # le frame
	var tail_pos: PackedFloat64Array = model.surfaces[piece.surface].position
	var shift := M.v3(0.0, point[1] - tail_pos[1], -(point[2] - tail_pos[2]))
	var radial := M.sub(point, centre)
	var radial_body := M.v3(-radial[0], radial[1], -radial[2])
	radial_body = M.sub(radial_body, M.scale(ax, M.dot(radial_body, ax)))
	# Free vortex: v_t = Γ/r along ax × r̂ (clockwise from behind: the air above the shaft moves right).
	var r := maxf(sqrt(M.dot(radial_body, radial_body)), w.core)
	return { area = piece.area * area / full, shift = shift, swirl = M.scale(M.cross(ax, radial_body), w.swirl / (r * r)) }

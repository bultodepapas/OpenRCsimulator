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
	var shaft_axis := Propulsion.axis(prop)
	var wash_velocity := M.scale(shaft_axis, w.dv)
	var speed := M.sqrt_(M.dot(v, v))
	for piece in ss.pieces:
		var im := immersion(piece, w, ss.hub, prop, v, speed, model, shaft_axis)
		if im.area <= 0.0:
			continue
		var extra := M.sub(wash_velocity, im.swirl)
		var increment := Aero.tail_surface_increment(v, rates, d, model, piece.surface, im.area, im.shift, extra, rho)
		for k in 6:
			out[k] += increment[k]
	return out


## Wake state: { u (axial airspeed), w (disc induced velocity), dv (velocity increment at the tail), rs (radius),
## swirl (free-vortex strength k·Q/ṁ, m²/s: v_t = swirl/r; + = clockwise from behind), core (m) }.
static func wake(v_air: PackedFloat64Array, thrust: float, torque: float, prop: Dictionary, rho: float) -> Dictionary:
	var ss: Dictionary = prop.slipstream
	var R: float = 0.5 * prop.diameter
	var area := PI * R * R
	var u := maxf(M.dot(v_air, Propulsion.axis(prop)), 0.0)
	var vs := M.sqrt_(maxf(u * u + 2.0 * thrust / (rho * area), 0.0))
	var w := 0.5 * (vs - u)
	var ratio := clampf((u + w) / maxf(u + 2.0 * w, 1e-6), RADIUS_MIN * RADIUS_MIN, RADIUS_MAX * RADIUS_MAX)
	var m := u / maxf(u + w, 1e-6) if w > 0.0 else 1.0
	var k_w: float = lerpf(ss.wash_factor[0], ss.wash_factor[1], clampf(m / 0.75, 0.0, 1.0))
	# Mixing that leaves k_w·w of the ideal 2w at the tail spreads the angular momentum over proportionally more air:
	# the tangential velocity falls by the same k_w/2, so the swirl ANGLE is the ideal wake's times swirl_factor.
	var swirl: float = ss.swirl_factor * 0.5 * k_w * torque / (rho * area * maxf(u + w, SWIRL_SPEED_FLOOR))
	return { u = u, w = w, vs = u + 2.0 * w, dv = k_w * w, rs = R * M.sqrt_(ratio), swirl = swirl, core = 0.3 * R }


## The immersed part of one piece: { area (m2), shift (body arm change from the surface's reference position),
## swirl (body air velocity at the immersed centroid) }. The wake centre at the piece follows the shaft from the
## hub and drifts with the free stream by the angle (V/V_s)·(flow angle) over the distance from the hub.
static func immersion(piece: Dictionary, w: Dictionary, hub: PackedFloat64Array, prop: Dictionary,
		v: PackedFloat64Array, speed: float, model: Dictionary, shaft_axis := PackedFloat64Array()) -> Dictionary:
	var none := { area = 0.0, shift = M.v3(0, 0, 0), swirl = M.v3(0, 0, 0) }
	var root: PackedFloat64Array = piece.root
	var ax: PackedFloat64Array = shaft_axis if not shaft_axis.is_empty() else Propulsion.axis(prop) # body
	var ax_le_0: float = -ax[0] # le frame, pointing forward (x_aft negative)
	var ax_le_1: float = ax[1]
	var ax_le_2: float = -ax[2]
	var dist := root[0] - hub[0] # aft distance hub → piece (m)
	var shaft_scale: float = dist / ax_le_0
	var centre_0: float = hub[0] + ax_le_0 * shaft_scale
	var centre_1: float = hub[1] + ax_le_1 * shaft_scale
	var centre_2: float = hub[2] + ax_le_2 * shaft_scale
	if speed > 1e-6 and w.vs > 1e-6:
		# Free-stream drift over the travel time dist/(u + w): the wake leans with the airflow (body w > 0: flow from
		# below, wake rises aft, less the wing's downwash: vertical_drift = 1 − dε/dα); sideslip pushes it sideways.
		var lean := minf(speed / (w.u + w.w), 1.0) * dist / speed
		centre_1 -= v[1] * lean
		centre_2 += v[2] * lean * float(prop.slipstream.vertical_drift)
	var e: PackedFloat64Array = piece.span_dir
	var rel_0: float = root[0] - centre_0
	var rel_1: float = root[1] - centre_1
	var rel_2: float = root[2] - centre_2
	var along: float = rel_0 * e[0] + rel_1 * e[1] + rel_2 * e[2]
	var perp_0: float = rel_0 - e[0] * along
	var perp_1: float = rel_1 - e[1] * along
	var perp_2: float = rel_2 - e[2] * along
	var d2: float = perp_0 * perp_0 + perp_1 * perp_1 + perp_2 * perp_2
	var rs: float = w.rs
	if d2 >= rs * rs:
		return none
	var half := M.sqrt_(rs * rs - d2)
	var span: float = piece.span
	var a := clampf(-along - half, 0.0, span)
	var b := clampf(-along + half, 0.0, span)
	if b <= a:
		return none
	var c0: float = piece.chords[0]
	var slope: float = (piece.chords[1] - c0) / span
	# Keep the polynomial term order while avoiding two captured Callable allocations per immersed piece.
	var area_b: float = c0 * b + 0.5 * slope * b * b
	var area_a: float = c0 * a + 0.5 * slope * a * a
	var area: float = area_b - area_a
	var full: float = c0 * span + 0.5 * slope * span * span
	if area <= 0.0:
		return none
	var moment_b: float = 0.5 * c0 * b * b + slope * b * b * b / 3.0
	var moment_a: float = 0.5 * c0 * a * a + slope * a * a * a / 3.0
	var eta: float = (moment_b - moment_a) / area
	var point_0: float = root[0] + e[0] * eta # le frame
	var point_1: float = root[1] + e[1] * eta
	var point_2: float = root[2] + e[2] * eta
	var tail_pos: PackedFloat64Array = model.surfaces[piece.surface].position
	var shift: PackedFloat64Array = PackedFloat64Array([0.0, point_1 - tail_pos[1], -(point_2 - tail_pos[2])])
	var radial_0: float = point_0 - centre_0
	var radial_1: float = point_1 - centre_1
	var radial_2: float = point_2 - centre_2
	var radial_body_0: float = -radial_0
	var radial_body_1: float = radial_1
	var radial_body_2: float = -radial_2
	var axial_projection: float = radial_body_0 * ax[0] + radial_body_1 * ax[1] + radial_body_2 * ax[2]
	radial_body_0 -= ax[0] * axial_projection
	radial_body_1 -= ax[1] * axial_projection
	radial_body_2 -= ax[2] * axial_projection
	# Free vortex: v_t = Γ/r along ax × r̂ (clockwise from behind: the air above the shaft moves right).
	var radius: float = maxf(M.sqrt_(radial_body_0 * radial_body_0 + radial_body_1 * radial_body_1 + radial_body_2 * radial_body_2), w.core)
	var swirl_scale: float = w.swirl / (radius * radius)
	var swirl: PackedFloat64Array = PackedFloat64Array([
		(ax[1] * radial_body_2 - ax[2] * radial_body_1) * swirl_scale,
		(ax[2] * radial_body_0 - ax[0] * radial_body_2) * swirl_scale,
		(ax[0] * radial_body_1 - ax[1] * radial_body_0) * swirl_scale,
	])
	return { area = piece.area * area / full, shift = shift, swirl = swirl }

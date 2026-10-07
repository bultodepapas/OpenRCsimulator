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
## H13: scalar form of the frozen oracle in tests/slipstream_reference.gd (immersion() and
## Aero.tail_surface_increment() inlined). Every product and sum keeps the oracle's order, including its + 0.0 terms;
## test_slipstream_scalar.gd compares bytes for legacy tails. E0b3a adds the E0a2 free-tail law with the same wing
## downwash in the two passes. downwash_cl = NAN uses instantaneous wing CL; the session passes its held lag.
static func loads(state: PackedFloat64Array, air: Dictionary, d: Dictionary, model: Dictionary, rpm: float,
		rho: float, downwash_cl: float = NAN) -> PackedFloat64Array:
	var prop: Dictionary = model.propulsion
	if rpm < Propulsion.STOPPED_RPM or prop.get("slipstream", {}).is_empty():
		return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var v: PackedFloat64Array = air.v_air
	var tq := Propulsion.thrust_torque(v, rpm, prop, rho)
	var w := wake(v, tq[0], tq[1], prop, rho)
	var ss: Dictionary = prop.slipstream
	var v0: float = v[0]
	var v1: float = v[1]
	var v2: float = v[2]
	var p: float = state[RB.RATE]
	var q: float = state[RB.RATE + 1]
	var r: float = state[RB.RATE + 2]
	var ax := Propulsion.axis(prop)
	var dv: float = w.dv
	var wash_0: float = ax[0] * dv
	var wash_1: float = ax[1] * dv
	var wash_2: float = ax[2] * dv
	var speed := M.sqrt_(v0 * v0 + v1 * v1 + v2 * v2)
	# Piece-independent immersion terms.
	var hub: PackedFloat64Array = ss.hub
	var ax_le_0: float = -ax[0]
	var ax_le_1: float = ax[1]
	var ax_le_2: float = -ax[2]
	var drifts: bool = speed > 1e-6 and w.vs > 1e-6
	var lean_ratio: float = minf(speed / (w.u + w.w), 1.0) if drifts else 0.0
	var vertical_drift: float = ss.vertical_drift
	var rs: float = w.rs
	var core: float = w.core
	var swirl_strength: float = w.swirl
	# Tail-law terms.
	var cg: PackedFloat64Array = model.cg_le
	var surfaces: Dictionary = model.surfaces
	# E0b3a: resolve wing downwash once per evaluation, not from the washed flow. The same held/instantaneous
	# CL must feed the free and washed evaluations. This is E0a2's angle law, not a new wake-transport model.
	var wing_cl: float = 0.0
	if surfaces.horizontal.has("free_slope"):
		wing_cl = Aero.wing_lift_coefficient(state, air, d, model) if is_nan(downwash_cl) else downwash_cl
	var tail_limit: float = surfaces.tail_local_limit
	var tail_span: float = surfaces.tail_stall_end - surfaces.tail_local_limit
	var tail_cd0: float = surfaces.tail_CD0
	var tail_k: float = surfaces.tail_k
	var tail_cd90: float = surfaces.tail_CD90
	var lift_q := 0.5*rho
	var drag_q := -0.5*rho
	var o0 := 0.0
	var o1 := 0.0
	var o2 := 0.0
	var o3 := 0.0
	var o4 := 0.0
	var o5 := 0.0
	for piece_value in ss.pieces:
		var piece: Dictionary = piece_value
		# --- immersion() ---
		var root: PackedFloat64Array = piece.root
		var dist: float = root[0] - hub[0]
		var shaft_scale: float = dist / ax_le_0
		var centre_0: float = hub[0] + ax_le_0 * shaft_scale
		var centre_1: float = hub[1] + ax_le_1 * shaft_scale
		var centre_2: float = hub[2] + ax_le_2 * shaft_scale
		if drifts:
			var lean: float = lean_ratio * dist / speed
			centre_1 -= v1 * lean
			centre_2 += v2 * lean * vertical_drift
		var e: PackedFloat64Array = piece.span_dir
		var rel_0: float = root[0] - centre_0
		var rel_1: float = root[1] - centre_1
		var rel_2: float = root[2] - centre_2
		var along: float = rel_0 * e[0] + rel_1 * e[1] + rel_2 * e[2]
		var perp_0: float = rel_0 - e[0] * along
		var perp_1: float = rel_1 - e[1] * along
		var perp_2: float = rel_2 - e[2] * along
		var d2: float = perp_0 * perp_0 + perp_1 * perp_1 + perp_2 * perp_2
		if d2 >= rs * rs:
			continue
		var half := M.sqrt_(rs * rs - d2)
		var span: float = piece.span
		var a := clampf(-along - half, 0.0, span)
		var b := clampf(-along + half, 0.0, span)
		if b <= a:
			continue
		var chords: PackedFloat64Array = piece.chords
		var c0: float = chords[0]
		var slope: float = (chords[1] - c0) / span
		var area_b: float = c0 * b + 0.5 * slope * b * b
		var area_a: float = c0 * a + 0.5 * slope * a * a
		var immersed: float = area_b - area_a
		var full: float = c0 * span + 0.5 * slope * span * span
		if immersed <= 0.0:
			continue
		var moment_b: float = 0.5 * c0 * b * b + slope * b * b * b / 3.0
		var moment_a: float = 0.5 * c0 * a * a + slope * a * a * a / 3.0
		var eta: float = (moment_b - moment_a) / immersed
		var point_0: float = root[0] + e[0] * eta
		var point_1: float = root[1] + e[1] * eta
		var point_2: float = root[2] + e[2] * eta
		var tail: Dictionary = surfaces[piece.surface]
		var tail_pos: PackedFloat64Array = tail.position
		var shift_1: float = point_1 - tail_pos[1]
		var shift_2: float = -(point_2 - tail_pos[2])
		var radial_body_0: float = -(point_0 - centre_0)
		var radial_body_1: float = point_1 - centre_1
		var radial_body_2: float = -(point_2 - centre_2)
		var axial_projection: float = radial_body_0 * ax[0] + radial_body_1 * ax[1] + radial_body_2 * ax[2]
		radial_body_0 -= ax[0] * axial_projection
		radial_body_1 -= ax[1] * axial_projection
		radial_body_2 -= ax[2] * axial_projection
		var radius: float = maxf(M.sqrt_(radial_body_0 * radial_body_0 + radial_body_1 * radial_body_1 + radial_body_2 * radial_body_2), core)
		var swirl_scale: float = swirl_strength / (radius * radius)
		var swirl_0: float = (ax[1] * radial_body_2 - ax[2] * radial_body_1) * swirl_scale
		var swirl_1: float = (ax[2] * radial_body_0 - ax[0] * radial_body_2) * swirl_scale
		var swirl_2: float = (ax[0] * radial_body_1 - ax[1] * radial_body_0) * swirl_scale
		var piece_area: float = piece.area
		var area: float = piece_area * immersed / full
		if area <= 0.0:
			continue
		# --- Aero.tail_surface_increment(): washed minus free load on the immersed area ---
		var vertical: bool = piece.surface == "vertical"
		var arm_0: float = -(tail_pos[0]-cg[0]) + 0.0
		var arm_1: float = tail_pos[1]-cg[1] + shift_1
		var arm_2: float = -(tail_pos[2]-cg[2]) + shift_2
		var rate_arm_0: float = q * arm_2 - r * arm_1
		var rate_arm_1: float = r * arm_0 - p * arm_2
		var rate_arm_2: float = p * arm_1 - q * arm_0
		var control: float = -float(d.rudder) if vertical else float(d.elevator)
		var control_angle: float = tail.control_effectiveness*control
		var incidence: float = tail.incidence
		var has_downwash: bool = not vertical and tail.has("free_slope")
		var lift_slope: float = tail.free_slope if has_downwash else tail.lift_slope
		var washed_0 := 0.0
		var washed_1 := 0.0
		var washed_2 := 0.0
		var washed_3 := 0.0
		var washed_4 := 0.0
		var washed_5 := 0.0
		var free_0 := 0.0
		var free_1 := 0.0
		var free_2 := 0.0
		var free_3 := 0.0
		var free_4 := 0.0
		var free_5 := 0.0
		for washed_pass in 2: # 0: free stream, 1: washed (pure and independent; order does not affect values)
			var f0: float
			var f1: float
			var f2: float
			if washed_pass == 1:
				f0 = (v0 + (wash_0 - swirl_0)) + rate_arm_0
				f1 = (v1 + (wash_1 - swirl_1)) + rate_arm_1
				f2 = (v2 + (wash_2 - swirl_2)) + rate_arm_2
			else:
				f0 = (v0 + 0.0) + rate_arm_0
				f1 = (v1 + 0.0) + rate_arm_1
				f2 = (v2 + 0.0) + rate_arm_2
			var normal: float = f1 if vertical else f2
			var effective: float
			if has_downwash:
				effective = wrapf(M.atan2_(normal, f0) - float(tail.downwash_per_cl) * wing_cl
					+ float(tail.elevator_tau) * control + float(tail.free_incidence), -PI, PI)
			else:
				effective = wrapf(M.atan2_(normal, f0) + control_angle + incidence, -PI, PI)
			var blend := Aero._smoothstep((absf(effective) - tail_limit)/tail_span)
			var cl: float = (1.0 - blend)*lift_slope*effective + blend*0.5*tail_cd90*M.sin_(2.0*effective)
			var cd: float = tail_cd0 + tail_k*cl*cl + tail_cd90*M.pow_(M.sin_(effective), 2)
			var fx := 0.0
			var fy := 0.0
			var fz := 0.0
			var mx := 0.0
			var my := 0.0
			var mz := 0.0
			var flow_speed := M.sqrt_(f0 * f0 + f1 * f1 + f2 * f2)
			if not flow_speed < 1e-10: # the oracle's test, so NaN takes the same branch
				var plane_speed := M.sqrt_(f0*f0 + normal*normal)
				var force_scale: float = drag_q*flow_speed*area*cd
				fx = f0 * force_scale
				fy = f1 * force_scale
				fz = f2 * force_scale
				if plane_speed > 1e-10:
					var lift: float = lift_q*plane_speed*plane_speed*area*cl
					fx += lift*normal/plane_speed
					if vertical:
						fy -= lift*f0/plane_speed
					else:
						fz -= lift*f0/plane_speed
				mx = arm_1 * fz - arm_2 * fy
				my = arm_2 * fx - arm_0 * fz
				mz = arm_0 * fy - arm_1 * fx
			if washed_pass == 1:
				washed_0 = fx
				washed_1 = fy
				washed_2 = fz
				washed_3 = mx
				washed_4 = my
				washed_5 = mz
			else:
				free_0 = fx
				free_1 = fy
				free_2 = fz
				free_3 = mx
				free_4 = my
				free_5 = mz
		o0 += washed_0 - free_0
		o1 += washed_1 - free_1
		o2 += washed_2 - free_2
		o3 += washed_3 - free_3
		o4 += washed_4 - free_4
		o5 += washed_5 - free_5
	return PackedFloat64Array([o0, o1, o2, o3, o4, o5])


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

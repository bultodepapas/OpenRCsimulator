# E0b, first slice (opt-in per aircraft, P51-12): the propeller's slipstream on the tail surfaces.
# Momentum theory (actuator disc): disc induced velocity w = ½(−u + sqrt(u² + 2T/(ρA))), far-wake radius
# r_s = R·sqrt((u + w)/(u + 2w)). The velocity added at the tail is k_w·w, with k_w rising linearly from the static to
# the forward-flight value over the mass-flow ratio m = u/(u + w) ∈ [0, 0.75] (Selig 2010, AIAA 2010-7938, Fig. 5:
# 0.8 and 1.8, below the ideal 2 because of the fuselage). Swirl strength is scaled from shaft torque:
# Γ = swirl_factor·(k_w/2)·Q/ṁ, ṁ = ρπR² max(u + w, 1 m/s). This is a torque-scaled heuristic,
# NOT a closed angular-momentum balance: the estimated decay and solid core (0.3R) reduce the nominal flux.
# E0b6 documents the deficit; neither the core nor k_w/2 has measured Stik swirl support.
# Each tail piece (the fin, each stab half) is a strip along its span with a linear chord; the part of it inside the
# slipstream circle (around the shaft axis, drifted with the free stream at angle of attack and sideslip) gets the
# INCREMENT  F(local tail law with the washed flow) − F(same law with the free stream), so the free-stream tail
# (oracle or local model) is untouched. A stopped propeller adds nothing in the quasi-static path;
# E0b5 can supply a decaying residual axial speed from its continuous state.
# Not modelled: wing in the slipstream, fuselage scrubbing drag, transported direction/radius. 64-bit floats only (guarded).
# P51-26 opt-in (propeller_sidewash, legacy path): each immersed piece is split at the swirl core crossings and the jet
# centre; every segment gets its own area, centroid and chord-weighted Gauss mean swirl, and the jet crossflow follows
# Ribner's far-wake relation instead of keeping the free-stream crossflow.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Aero := preload("res://physics/aero.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const SwirlLoads = preload("res://physics/swirl_loads.gd")

## The mass-flow speed u + w used for the swirl never falls below this (m/s).
const SWIRL_SPEED_FLOOR := 1.0
## Wake radius limits as a fraction of the propeller radius: full contraction at rest (1/√2), expansion behind a
## braking (negative-thrust) propeller capped at 1.5.
const RADIUS_MIN := 0.7071
const RADIUS_MAX := 1.5
# Five-point Gauss-Legendre integrates chord × cubic squared-radius taper × span moment (degree 8) exactly.
const PROFILE_X: Array[float] = [-0.906179845938664, -0.538469310105683, 0.0, 0.538469310105683, 0.906179845938664]
const PROFILE_W: Array[float] = [0.236926885056189, 0.478628670499366, 0.568888888888889, 0.478628670499366, 0.236926885056189]


## Derived data (AircraftData model.propulsion.slipstream): { hub (le), wash_factor [static, forward], swirl_factor,
## vertical_drift,
## pieces: [{
## surface, area (m2), root (le), span_dir (le unit), span (m), chords [root, tip] }] }.
## E0b3b: edge_fraction/reverse_fade opt in to smooth occupancy and a flat profile [a,b,c_a,c_b,...]
## instead of chords. Geometry moments are exact; axial loads retain a centroid approximation. E0b6 adds
## distributed swirl-minus-axial loads, so zero swirl remains exact and continuous without a centroid swirl bias.
## Returns body loads [Fx, Fy, Fz, Mx, My, Mz] about the CG.
## H13: scalar form of the frozen oracle in tests/slipstream_reference.gd (immersion() and
## Aero.tail_surface_increment() inlined). Every product and sum keeps the oracle's order, including its + 0.0 terms;
## test_slipstream_scalar.gd compares bytes for legacy tails. E0b3a adds the E0a2 free-tail law with the same wing
## downwash in the two passes. downwash_cl = NAN uses instantaneous wing CL; the session passes its held lag.
## transported_dv: optional per-piece axial speed (m/s) at the RK stage; empty uses the equilibrium wake.
## swirl_subdivisions: P51-26 convergence checks only; splits each swirl segment into equal parts (1 = runtime).
static func loads(state: PackedFloat64Array, air: Dictionary, d: Dictionary, model: Dictionary, rpm: float,
		rho: float, downwash_cl: float = NAN, transported_dv: PackedFloat64Array = PackedFloat64Array(),
		swirl_subdivisions: int = 1) -> PackedFloat64Array:
	return stage_loads(state, air, d, model, rpm, rho, downwash_cl, transported_dv, swirl_subdivisions, PackedFloat64Array())


## loads() with EX-14c's stage_thrust_torque: optional [thrust N, shaft torque N·m] the propeller already produced at
## this RK stage (the Glow hub-inflow result), so the wake carries the shaft's thrust and torque; empty re-evaluates them.
static func stage_loads(state: PackedFloat64Array, air: Dictionary, d: Dictionary, model: Dictionary, rpm: float,
		rho: float, downwash_cl: float, transported_dv: PackedFloat64Array, swirl_subdivisions: int,
		stage_thrust_torque: PackedFloat64Array) -> PackedFloat64Array:
	var prop: Dictionary = model.propulsion
	if (rpm < Propulsion.STOPPED_RPM and transported_dv.is_empty()) or prop.get("slipstream", {}).is_empty():
		return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var v: PackedFloat64Array = air.v_air
	# Electric disk induction uses hub inflow; drift and free-tail loads retain datum flow.
	var disk_v: PackedFloat64Array = Propulsion.hub_air_velocity(state, v, prop.offset) if Propulsion.is_electric(prop) else v
	var smooth: bool = prop.slipstream.has("edge_fraction")
	var fade: float = reverse_weight(disk_v, rpm, prop) if smooth else 1.0
	# A stopped source leaves a decaying axial wake. Reverse flow still removes its tail occupancy.
	if not transported_dv.is_empty() and rpm < Propulsion.STOPPED_RPM:
		fade = 1.0 if v[0] >= 0.0 else 0.0
	if fade == 0.0:
		return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var tq := stage_thrust_torque if stage_thrust_torque.size() >= 2 else Propulsion.thrust_torque(disk_v, rpm, prop, rho)
	var w := wake(disk_v, tq[0], tq[1], prop, rho)
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
	var swirl_strength: float = 0.0 if smooth else w.swirl
	# Tail-law terms.
	var cg: PackedFloat64Array = model.cg_le
	var surfaces: Dictionary = model.surfaces
	# E0b3a: resolve wing downwash once per evaluation, not from the washed flow. The same held/instantaneous
	# dimensional source must feed the free and washed evaluations. This is E0a2's angle law, not a new wake-transport model.
	var wing_cl: float = 0.0
	if surfaces.horizontal.has("free_slope"):
		wing_cl = Aero.wing_wake_velocity(state, air, d, model) if is_nan(downwash_cl) else downwash_cl
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
	# P51-26 (opt-in, legacy path only): piecewise swirl quadrature and Ribner's propeller sidewash.
	var segmented: bool = ss.has("propeller_sidewash")
	var crossflow := PackedFloat64Array([0.0, 0.0, 0.0])
	if segmented:
		crossflow = sidewash(disk_v, rpm, prop, w, ax, rho, float(ss.propeller_sidewash))
	for piece_index in ss.pieces.size():
		var piece: Dictionary = ss.pieces[piece_index]
		if not transported_dv.is_empty():
			wash_0 = ax[0] * transported_dv[piece_index]
			wash_1 = ax[1] * transported_dv[piece_index]
			wash_2 = ax[2] * transported_dv[piece_index]
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
		var immersed: float
		var full: float
		var eta: float
		if smooth:
			var moments: PackedFloat64Array = profile_moments(piece.profile, along, d2, rs, ss.edge_fraction)
			immersed = moments[0]
			if immersed <= 0.0:
				continue
			full = piece.area
			eta = moments[1] / immersed
		else:
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
			if segmented:
				var segment_loads := _segmented_increment(piece, surfaces[piece.surface], a, b, c0, slope, along, d2,
					PackedFloat64Array([centre_0, centre_1, centre_2]), ax, core, swirl_strength,
					PackedFloat64Array([wash_0 + crossflow[0], wash_1 + crossflow[1], wash_2 + crossflow[2]]), state, v, d, model,
					rho, wing_cl, swirl_subdivisions)
				o0 += segment_loads[0]
				o1 += segment_loads[1]
				o2 += segment_loads[2]
				o3 += segment_loads[3]
				o4 += segment_loads[4]
				o5 += segment_loads[5]
				continue
			var area_b: float = c0 * b + 0.5 * slope * b * b
			var area_a: float = c0 * a + 0.5 * slope * a * a
			immersed = area_b - area_a
			full = c0 * span + 0.5 * slope * span * span
			if immersed <= 0.0:
				continue
			var moment_b: float = 0.5 * c0 * b * b + slope * b * b * b / 3.0
			var moment_a: float = 0.5 * c0 * a * a + slope * a * a * a / 3.0
			eta = (moment_b - moment_a) / immersed
		var point_0: float = root[0] + e[0] * eta
		var point_1: float = root[1] + e[1] * eta
		var point_2: float = root[2] + e[2] * eta
		var tail: Dictionary = surfaces[piece.surface]
		var tail_pos: PackedFloat64Array = tail.position
		var shift_1: float = point_1 - tail_pos[1]
		var shift_2: float = -(point_2 - tail_pos[2])
		# The neutral coverage plane is distinct from the established aerodynamic load plane (Stik: 5 mm).
		if smooth and piece.surface == "horizontal":
			shift_2 = 0.0
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
		var arm := M.v3(arm_0, arm_1, arm_2)
		var free := Aero._tail_surface_from_flow(M.v3((v0+0.0)+rate_arm_0, (v1+0.0)+rate_arm_1, (v2+0.0)+rate_arm_2),
			arm, d, tail, surfaces, area, vertical, rho, wing_cl)
		var washed := Aero._tail_surface_from_flow(M.v3((v0+(wash_0-swirl_0))+rate_arm_0,
			(v1+(wash_1-swirl_1))+rate_arm_1, (v2+(wash_2-swirl_2))+rate_arm_2),
			arm, d, tail, surfaces, area, vertical, rho, wing_cl)
		o0 += washed[0] - free[0]
		o1 += washed[1] - free[1]
		o2 += washed[2] - free[2]
		o3 += washed[3] - free[3]
		o4 += washed[4] - free[4]
		o5 += washed[5] - free[5]
	if smooth:
		var result: PackedFloat64Array = PackedFloat64Array([o0*fade, o1*fade, o2*fade, o3*fade, o4*fade, o5*fade])
		if w.swirl != 0.0:
			var correction: PackedFloat64Array = SwirlLoads.correction(state, air, d, model, w, fade, rho, wing_cl)
			for component: int in 6:
				result[component] += correction[component]
		return result
	return PackedFloat64Array([o0, o1, o2, o3, o4, o5])


## Wake state: { u (axial airspeed), w (disc induced velocity), dv (velocity increment at the tail), rs (radius),
## swirl (free-vortex strength k·Q/ṁ, m²/s: v_t = swirl/r; + = clockwise from behind), core (m) }.
static func wake(v_air: PackedFloat64Array, thrust: float, torque: float, prop: Dictionary, rho: float) -> Dictionary:
	var ss: Dictionary = prop.slipstream
	var R: float = 0.5 * prop.diameter
	var area := PI * R * R
	var smooth: bool = ss.has("edge_fraction")
	# Signed momentum flow only in the new bounded route: reverse_weight removes loads by -0.2 vi0 in the fixture.
	var axial: float = M.dot(v_air, Propulsion.axis(prop))
	var u: float = axial if smooth else maxf(axial, 0.0)
	var vs := M.sqrt_(maxf(u * u + 2.0 * thrust / (rho * area), 0.0))
	var w := 0.5 * (vs - u)
	var ratio := clampf((u + w) / maxf(u + 2.0 * w, 1e-6), (0.25 if smooth else RADIUS_MIN * RADIUS_MIN), RADIUS_MAX * RADIUS_MAX)
	var m := u / maxf(u + w, 1e-6) if w > 0.0 else 1.0
	var k_w: float = lerpf(ss.wash_factor[0], ss.wash_factor[1], clampf(m / 0.75, 0.0, 1.0))
	# k_w/2 is an estimated swirl attenuation, not a consequence of the axial decay law. The current radius
	# is still the ideal contracted radius; no expanded mass-flow or missing reaction is tracked (E0b6).
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
	var area: float
	var full: float
	var eta: float
	var smooth: bool = prop.slipstream.has("edge_fraction")
	if smooth:
		var moments: PackedFloat64Array = profile_moments(piece.profile, along, d2, rs, prop.slipstream.edge_fraction)
		area = moments[0]
		if area <= 0.0:
			return none
		full = piece.area
		eta = moments[1] / area
	else:
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
		area = area_b - area_a
		full = c0 * span + 0.5 * slope * span * span
		if area <= 0.0:
			return none
		var moment_b: float = 0.5 * c0 * b * b + slope * b * b * b / 3.0
		var moment_a: float = 0.5 * c0 * a * a + slope * a * a * a / 3.0
		eta = (moment_b - moment_a) / area
	var point_0: float = root[0] + e[0] * eta # le frame
	var point_1: float = root[1] + e[1] * eta
	var point_2: float = root[2] + e[2] * eta
	var tail_pos: PackedFloat64Array = model.surfaces[piece.surface].position
	var shift: PackedFloat64Array = PackedFloat64Array([0.0, point_1 - tail_pos[1], -(point_2 - tail_pos[2])])
	if smooth and piece.surface == "horizontal":
		shift[2] = 0.0
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


## E0b3b regularization, not a validated vortex-ring model. Positive magnitudes are in units of static induced
## velocity at the CURRENT rpm. Density cancels in vi0 = n D sqrt(2 Ct(0)/pi). Applies to the entire increment.
static func reverse_weight(v: PackedFloat64Array, rpm: float, prop: Dictionary) -> float:
	if rpm < Propulsion.STOPPED_RPM:
		return 0.0
	var vi0: float = rpm / 60.0 * float(prop.diameter) * M.sqrt_(2.0 * float(prop.ct[1]) / PI)
	var bounds: PackedFloat64Array = prop.slipstream.reverse_fade
	var ratio: float = -M.dot(v, Propulsion.axis(prop)) / vi0
	return 1.0 - Aero._smoothstep((ratio - bounds[0]) / (bounds[1] - bounds[0]))


## Integral of chord × occupancy and its first span moment. Occupancy is a C1 cubic in squared radius,
## one inside (1-edge)*rs and zero outside (1+edge)*rs. It weights the load increment, NOT the local air speed.
## This avoids hard-circle tangency kinks without claiming a measured radial wake profile.
static func profile_moments(profile: PackedFloat64Array, along: float, d2: float, rs: float, edge: float) -> PackedFloat64Array:
	var inner2: float = rs*rs*(1.0-edge)*(1.0-edge)
	var outer2: float = rs*rs*(1.0+edge)*(1.0+edge)
	if d2 >= outer2:
		return PackedFloat64Array([0.0, 0.0])
	var outer: float = M.sqrt_(outer2-d2)
	var inner: float = M.sqrt_(maxf(inner2-d2, 0.0))
	var total: float = 0.0
	var moment: float = 0.0
	for i in range(0, profile.size(), 4):
		var start: float = profile[i]
		var end: float = profile[i+1]
		var a: float = maxf(start, -along-outer)
		var b: float = minf(end, -along+outer)
		if b <= a:
			continue
		var slope: float = (profile[i+3]-profile[i+2])/(end-start)
		for zone in 3:
			var lo: float = a
			var hi: float = b
			if zone == 0:
				hi = minf(b, -along-inner)
			elif zone == 1:
				lo = maxf(a, -along-inner)
				hi = minf(b, -along+inner)
			else:
				lo = maxf(a, -along+inner)
			if hi <= lo:
				continue
			var middle: float = 0.5*(lo+hi)
			var half: float = 0.5*(hi-lo)
			var chord: float = profile[i+2] + slope*(middle-start)
			if zone == 1:
				var strip: float = 2.0*half*chord
				total += strip
				moment += middle*strip + slope*2.0*half*half*half/3.0
			else:
				for k in 5:
					var offset: float = half*PROFILE_X[k]
					var eta: float = middle+offset
					var radial: float = eta+along
					var t: float = clampf((d2+radial*radial-inner2)/(outer2-inner2), 0.0, 1.0)
					var strip: float = half*PROFILE_W[k]*(chord+slope*offset)*(1.0-t*t*(3.0-2.0*t))
					total += strip
					moment += eta*strip
	return PackedFloat64Array([total, moment])


## P51-26: Ribner's far-wake crossflow correction (NACA ARR L4I12a, eq. 8, in momentum form), body axes, m/s. The jet's
## crossflow becomes h(a)·v_c + ½·g(a)·N/ṁ; the shaft-axis wash already carries v_c, so only the difference is returned.
## a = w/u is the disc inflow factor; g and h stay within 1.0–1.2 for every a ≥ 0, and ṁ uses the swirl's speed floor,
## so the term is bounded at static thrust and vanishes with the crossflow. gain 1 is the published relation. Without a
## normal_force table N is zero and only the h(a) term remains.
static func sidewash(v: PackedFloat64Array, rpm: float, prop: Dictionary, w: Dictionary, ax: PackedFloat64Array, rho: float,
		gain: float) -> PackedFloat64Array:
	var inflow: float = w.w / maxf(w.u, 1e-6)
	var k: float = 1.0 + 2.0 * inflow
	var denominator: float = 1.0 + k * k
	var g: float = 2.0 * (1.0 + inflow) * k / denominator
	var h: float = k * (2.0 + 2.0 * inflow) / denominator
	var mass_flow: float = rho * PI * 0.25 * float(prop.diameter) * float(prop.diameter) * maxf(w.u + w.w, SWIRL_SPEED_FLOOR)
	var normal := Propulsion.normal_force(v, rpm, prop, rho)
	var along: float = v[0] * ax[0] + v[1] * ax[1] + v[2] * ax[2]
	var out := PackedFloat64Array([0.0, 0.0, 0.0])
	for c in 3:
		out[c] = gain * (0.5 * g * normal[c] / mass_flow + (h - 1.0) * (v[c] - ax[c] * along))
	return out


## P51-26: washed-minus-free load of one legacy piece's immersed interval [a, b] (m along its span), split at the swirl
## core crossings and the jet centre so each segment's free-vortex swirl is smooth. Each segment uses its exact area and
## centroid and its chord-weighted 5-point Gauss mean swirl. wash: axial wash plus the Ribner crossflow (body).
static func _segmented_increment(piece: Dictionary, tail: Dictionary, a: float, b: float, c0: float, slope: float,
		along: float, d2: float, centre: PackedFloat64Array, ax: PackedFloat64Array, core: float, swirl: float,
		wash: PackedFloat64Array, state: PackedFloat64Array, v: PackedFloat64Array, d: Dictionary, model: Dictionary,
		rho: float, wing_cl: float, subdivisions: int = 1) -> PackedFloat64Array:
	var cuts: Array[float] = [a, b]
	if core * core > d2:
		var core_half := M.sqrt_(core * core - d2)
		for cut: float in [-along - core_half, -along + core_half]:
			if cut > a and cut < b:
				cuts.append(cut)
	if -along > a and -along < b:
		cuts.append(-along)
	cuts.sort()
	if subdivisions > 1:
		var fine: Array[float] = []
		for j in cuts.size() - 1:
			for k in subdivisions:
				fine.append(cuts[j] + (cuts[j + 1] - cuts[j]) * float(k) / subdivisions)
		fine.append(cuts[-1])
		cuts = fine
	var root: PackedFloat64Array = piece.root
	var e: PackedFloat64Array = piece.span_dir
	var span: float = piece.span
	var full: float = c0 * span + 0.5 * slope * span * span
	var cg: PackedFloat64Array = model.cg_le
	var tail_pos: PackedFloat64Array = tail.position
	var law := _tail_law(tail, model.surfaces, d, piece.surface == "vertical", wing_cl, rho)
	# Cache the geometry arrays once; the quadrature samples reuse these exact scalar values.
	var root_0: float = root[0]
	var root_1: float = root[1]
	var root_2: float = root[2]
	var e_0: float = e[0]
	var e_1: float = e[1]
	var e_2: float = e[2]
	var centre_0: float = centre[0]
	var centre_1: float = centre[1]
	var centre_2: float = centre[2]
	var ax_0: float = ax[0]
	var ax_1: float = ax[1]
	var ax_2: float = ax[2]
	var p: float = state[RB.RATE]
	var q: float = state[RB.RATE + 1]
	var r: float = state[RB.RATE + 2]
	var out := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	for j in cuts.size() - 1:
		var lo: float = cuts[j]
		var hi: float = cuts[j + 1]
		var segment_area: float = (c0 * hi + 0.5 * slope * hi * hi) - (c0 * lo + 0.5 * slope * lo * lo)
		if segment_area <= 0.0:
			continue
		var eta: float = ((0.5 * c0 * hi * hi + slope * hi * hi * hi / 3.0) - (0.5 * c0 * lo * lo + slope * lo * lo * lo / 3.0)) / segment_area
		var s0 := 0.0
		var s1 := 0.0
		var s2 := 0.0
		var weights := 0.0
		var gauss_middle: float = 0.5 * (lo + hi)
		var gauss_half: float = 0.5 * (hi - lo)
		for k in 5:
			var x: float = gauss_middle + gauss_half * PROFILE_X[k]
			var weight: float = (c0 + slope * x) * PROFILE_W[k]
			var rb0: float = -(root_0 + e_0 * x - centre_0)
			var rb1: float = root_1 + e_1 * x - centre_1
			var rb2: float = -(root_2 + e_2 * x - centre_2)
			var axial: float = rb0 * ax_0 + rb1 * ax_1 + rb2 * ax_2
			rb0 -= ax_0 * axial
			rb1 -= ax_1 * axial
			rb2 -= ax_2 * axial
			var radius: float = maxf(M.sqrt_(rb0 * rb0 + rb1 * rb1 + rb2 * rb2), core)
			var scale: float = swirl / (radius * radius) * weight
			s0 += (ax_1 * rb2 - ax_2 * rb1) * scale
			s1 += (ax_2 * rb0 - ax_0 * rb2) * scale
			s2 += (ax_0 * rb1 - ax_1 * rb0) * scale
			weights += weight
		s0 /= weights
		s1 /= weights
		s2 /= weights
		# Segment centroid on the span line; its arm follows the legacy piece convention (shift from the surface position).
		var arm_0: float = -(tail_pos[0] - cg[0])
		var arm_1: float = tail_pos[1] - cg[1] + (root[1] + e[1] * eta - tail_pos[1])
		var arm_2: float = -(tail_pos[2] - cg[2]) - (root[2] + e[2] * eta - tail_pos[2])
		var rate_0: float = q * arm_2 - r * arm_1
		var rate_1: float = r * arm_0 - p * arm_2
		var rate_2: float = p * arm_1 - q * arm_0
		var area: float = float(piece.area) * segment_area / full
		_add_tail_load(out, law, 1.0, v[0] + (wash[0] - s0) + rate_0, v[1] + (wash[1] - s1) + rate_1, v[2] + (wash[2] - s2) + rate_2,
			arm_0, arm_1, arm_2, area)
		_add_tail_load(out, law, -1.0, v[0] + rate_0, v[1] + rate_1, v[2] + rate_2, arm_0, arm_1, arm_2, area)
	return out


## The tail law of Aero._tail_surface_from_flow with its per-surface constants resolved once:
## [vertical, slope, angle offset, downwash gain (0 = none), wake, limit, stall span, CD0, k, CD90, ½ρ].
static func _tail_law(tail: Dictionary, surfaces: Dictionary, d: Dictionary, vertical: bool, wake: float,
		rho: float) -> PackedFloat64Array:
	var control: float = -d.rudder if vertical else d.elevator
	var free_law: bool = not vertical and tail.has("free_slope")
	var slope: float = tail.free_slope if free_law else tail.lift_slope
	var offset: float = float(tail.elevator_tau) * control + float(tail.free_incidence) if free_law 		else tail.control_effectiveness * control + tail.incidence
	var gain: float = float(tail.downwash_per_cl) if free_law else 0.0
	return PackedFloat64Array([1.0 if vertical else 0.0, slope, offset, gain, wake if free_law else 0.0,
		surfaces.tail_local_limit, surfaces.tail_stall_end - surfaces.tail_local_limit, surfaces.tail_CD0, surfaces.tail_k,
		surfaces.tail_CD90, 0.5 * rho])


## Adds sign × the tail law's load for body flow f at arm (about the CG) to out, without allocating. Same expressions as
## Aero._tail_surface_from_flow / _tail_curve / _surface_with_flow; test_slipstream_sidewash.gd compares the two.
static func _add_tail_load(out: PackedFloat64Array, law: PackedFloat64Array, sign: float, f0: float, f1: float, f2: float,
		arm_0: float, arm_1: float, arm_2: float, area: float) -> void:
	var vertical: bool = law[0] == 1.0
	var normal: float = f1 if vertical else f2
	var plane: float = M.sqrt_(f0 * f0 + normal * normal)
	if plane == 0.0:
		return
	var angle: float = M.atan2_(normal, f0)
	if law[3] != 0.0 and law[4] != 0.0:
		angle -= M.atan2_(law[3] * law[4], plane)
	var effective: float = wrapf(angle + law[2], -PI, PI)
	var blend: float = clampf((absf(effective) - law[5]) / law[6], 0.0, 1.0)
	blend = blend * blend * (3.0 - 2.0 * blend)
	var cl: float = (1.0 - blend) * law[1] * effective + blend * 0.5 * law[9] * M.sin_(2.0 * effective)
	var cd: float = law[7] + law[8] * cl * cl + law[9] * M.pow_(M.sin_(effective), 2)
	var force_scale: float = -law[10] * plane * area * cd
	var lift: float = law[10] * plane * plane * area * cl
	var fx: float = f0 * force_scale + lift * normal / plane
	var fy := 0.0
	var fz := 0.0
	if vertical:
		fy = normal * force_scale - lift * f0 / plane
	else:
		fz = normal * force_scale - lift * f0 / plane
	out[0] += sign * fx
	out[1] += sign * fy
	out[2] += sign * fz
	out[3] += sign * (arm_1 * fz - arm_2 * fy)
	out[4] += sign * (arm_2 * fx - arm_0 * fz)
	out[5] += sign * (arm_0 * fy - arm_1 * fx)

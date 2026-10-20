## H17: original loads and segmented quadrature; unchanged helpers inherited.
extends "res://physics/slipstream.gd"


static func loads(state: PackedFloat64Array, air: Dictionary, d: Dictionary, model: Dictionary, rpm: float,
		rho: float, downwash_cl: float = NAN, transported_dv: PackedFloat64Array = PackedFloat64Array(),
		swirl_subdivisions: int = 1) -> PackedFloat64Array:
	var prop: Dictionary = model.propulsion
	if (rpm < Propulsion.STOPPED_RPM and transported_dv.is_empty()) or prop.get("slipstream", {}).is_empty():
		return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var v: PackedFloat64Array = air.v_air
	var smooth: bool = prop.slipstream.has("edge_fraction")
	var fade: float = reverse_weight(v, rpm, prop) if smooth else 1.0
	# A stopped source leaves a decaying axial wake. Reverse flow still removes its tail occupancy.
	if not transported_dv.is_empty() and rpm < Propulsion.STOPPED_RPM:
		fade = 1.0 if v[0] >= 0.0 else 0.0
	if fade == 0.0:
		return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
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
		crossflow = sidewash(v, rpm, prop, w, ax, rho, float(ss.propeller_sidewash))
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
		for k in 5:
			var x: float = 0.5 * (lo + hi) + 0.5 * (hi - lo) * PROFILE_X[k]
			var weight: float = (c0 + slope * x) * PROFILE_W[k]
			var rb0: float = -(root[0] + e[0] * x - centre[0])
			var rb1: float = root[1] + e[1] * x - centre[1]
			var rb2: float = -(root[2] + e[2] * x - centre[2])
			var axial: float = rb0 * ax[0] + rb1 * ax[1] + rb2 * ax[2]
			rb0 -= ax[0] * axial
			rb1 -= ax[1] * axial
			rb2 -= ax[2] * axial
			var radius: float = maxf(M.sqrt_(rb0 * rb0 + rb1 * rb1 + rb2 * rb2), core)
			var scale: float = swirl / (radius * radius) * weight
			s0 += (ax[1] * rb2 - ax[2] * rb1) * scale
			s1 += (ax[2] * rb0 - ax[0] * rb2) * scale
			s2 += (ax[0] * rb1 - ax[1] * rb0) * scale
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

# E0b6: bounded spanwise quadrature for the nonzero-swirl correction to the smooth-profile centroid baseline.
# Each real profile interval is split at occupancy radii and the regularized vortex core, then integrated with fixed
# 5-point Gauss-Legendre nodes. It computes only washed(local axial + local swirl) - washed(local axial), so the
# exact zero-swirl path remains the caller's existing centroid baseline.
# E0b6p inlines the two tail laws and hoists piece constants to avoid per-node arrays/dictionary lookups.
# tests/swirl_e0b6_reference.gd freezes the general-helper implementation; keep quadrature and arithmetic order.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Aero := preload("res://physics/aero.gd")
const Propulsion := preload("res://physics/propulsion.gd")

const GAUSS_X: Array[float] = [
	-0.9061798459386640, -0.5384693101056831, 0.0,
	0.5384693101056831, 0.9061798459386640,
]
const GAUSS_W: Array[float] = [
	0.2369268850561891, 0.4786286704993665, 0.5688888888888889,
	0.4786286704993665, 0.2369268850561891,
]
const ROOT_TOLERANCE: float = 1.0e-14


## Distributed swirl effect only, added to the existing smooth-profile axial centroid load.
## wake is Slipstream.wake(...); fade is Slipstream.reverse_weight(...), both computed by the caller.
static func correction(state: PackedFloat64Array, air: Dictionary, d: Dictionary, model: Dictionary,
		wake: Dictionary, fade: float, rho: float, downwash_cl: float = NAN) -> PackedFloat64Array:
	var result: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	if fade == 0.0 or float(wake.get("swirl", 0.0)) == 0.0:
		return result
	var prop: Dictionary = model.propulsion
	var ss: Dictionary = prop.get("slipstream", {})
	if ss.is_empty() or not ss.has("edge_fraction"):
		return result
	var surfaces: Dictionary = model.surfaces
	var wing_cl: float = 0.0
	if surfaces.horizontal.has("free_slope"):
		wing_cl = Aero.wing_lift_coefficient(state, air, d, model) if is_nan(downwash_cl) else downwash_cl
	var v: PackedFloat64Array = air.v_air
	var rates: PackedFloat64Array = state.slice(RB.RATE, RB.RATE + 3)
	var axis: PackedFloat64Array = Propulsion.axis(prop)
	var wash: PackedFloat64Array = PackedFloat64Array([
		axis[0] * float(wake.dv), axis[1] * float(wake.dv), axis[2] * float(wake.dv),
	])
	for piece: Dictionary in ss.pieces:
		var local: PackedFloat64Array = _piece_correction(v, rates, d, model, piece, axis, wash, wake,
			float(ss.edge_fraction), rho, wing_cl)
		for component in 6:
			result[component] += local[component]
	for component in 6:
		result[component] *= fade
	return result


static func _piece_correction(v: PackedFloat64Array, rates: PackedFloat64Array, d: Dictionary, model: Dictionary,
		piece: Dictionary, axis: PackedFloat64Array, wash: PackedFloat64Array, wake: Dictionary,
		edge: float, rho: float, wing_cl: float) -> PackedFloat64Array:
	var result: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var profile: PackedFloat64Array = piece.profile
	var profile_area: float = 0.0
	for i in range(0, profile.size(), 4):
		profile_area += 0.5 * (profile[i + 2] + profile[i + 3]) * (profile[i + 1] - profile[i])
	if profile_area <= 0.0:
		return result
	var area_scale: float = float(piece.area) / profile_area
	var hub: PackedFloat64Array = model.propulsion.slipstream.hub
	var root: PackedFloat64Array = piece.root
	var e: PackedFloat64Array = piece.span_dir
	var ax_le_0: float = -axis[0]
	var ax_le_1: float = axis[1]
	var ax_le_2: float = -axis[2]
	var distance: float = root[0] - hub[0]
	var shaft_scale: float = distance / ax_le_0
	var centre_0: float = hub[0] + ax_le_0 * shaft_scale
	var centre_1: float = hub[1] + ax_le_1 * shaft_scale
	var centre_2: float = hub[2] + ax_le_2 * shaft_scale
	var speed: float = M.sqrt_(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
	if speed > 1.0e-6 and float(wake.vs) > 1.0e-6:
		var lean: float = minf(speed / (float(wake.u) + float(wake.w)), 1.0) * distance / speed
		centre_1 -= v[1] * lean
		centre_2 += v[2] * lean * float(model.propulsion.slipstream.vertical_drift)
	var rel_0: float = root[0] - centre_0
	var rel_1: float = root[1] - centre_1
	var rel_2: float = root[2] - centre_2
	var along: float = rel_0 * e[0] + rel_1 * e[1] + rel_2 * e[2]
	var perp_0: float = rel_0 - e[0] * along
	var perp_1: float = rel_1 - e[1] * along
	var perp_2: float = rel_2 - e[2] * along
	var d2: float = perp_0 * perp_0 + perp_1 * perp_1 + perp_2 * perp_2
	var rs: float = float(wake.rs)
	var core: float = float(wake.core)
	var swirl_strength: float = float(wake.swirl)
	var inner_radius: float = rs * (1.0 - edge)
	var outer_radius: float = rs * (1.0 + edge)
	var inner2: float = inner_radius * inner_radius
	var outer2: float = outer_radius * outer_radius
	# Smooth-profile validation requires an axial shaft and a transverse span, so the projected
	# distance to the core follows the same circle equation as occupancy.
	var core_roots: Array[float] = _circle_intersections(along, d2, core * core)
	var inner_roots: Array[float] = _circle_intersections(along, d2, inner2)
	var outer_roots: Array[float] = _circle_intersections(along, d2, outer2)
	var tail: Dictionary = model.surfaces[piece.surface]
	var tail_pos: PackedFloat64Array = tail.position
	var cg: PackedFloat64Array = model.cg_le
	var tail_pos_0: float = tail_pos[0]
	var tail_pos_1: float = tail_pos[1]
	var tail_pos_2: float = tail_pos[2]
	var arm_base_0: float = -(tail_pos_0 - cg[0]) + 0.0
	var arm_base_1: float = tail_pos_1 - cg[1]
	var arm_base_2: float = -(tail_pos_2 - cg[2])
	var horizontal: bool = piece.surface == "horizontal"
	var vertical: bool = piece.surface == "vertical"
	var has_downwash: bool = not vertical and tail.has("free_slope")
	var control: float = -float(d.rudder) if vertical else float(d.elevator)
	var control_angle: float = float(tail.control_effectiveness) * control
	var incidence: float = float(tail.incidence)
	var downwash_product: float = float(tail.get("downwash_per_cl", 0.0)) * wing_cl
	var elevator_tau_control: float = float(tail.get("elevator_tau", 0.0)) * control
	var free_incidence: float = float(tail.get("free_incidence", 0.0))
	var lift_slope: float = float(tail.free_slope) if has_downwash else float(tail.lift_slope)
	var tail_limit: float = float(model.surfaces.tail_local_limit)
	var tail_span: float = float(model.surfaces.tail_stall_end) - tail_limit
	var tail_cd0: float = float(model.surfaces.tail_CD0)
	var tail_k: float = float(model.surfaces.tail_k)
	var tail_cd90: float = float(model.surfaces.tail_CD90)
	var v0: float = v[0]
	var v1: float = v[1]
	var v2: float = v[2]
	var p: float = rates[0]
	var q: float = rates[1]
	var r: float = rates[2]
	var axis_0: float = axis[0]
	var axis_1: float = axis[1]
	var axis_2: float = axis[2]
	var wash_0: float = wash[0]
	var wash_1: float = wash[1]
	var wash_2: float = wash[2]
	var root_0: float = root[0]
	var root_1: float = root[1]
	var root_2: float = root[2]
	var e_0: float = e[0]
	var e_1: float = e[1]
	var e_2: float = e[2]
	for profile_index in range(0, profile.size(), 4):
		var start: float = profile[profile_index]
		var end: float = profile[profile_index + 1]
		var chord_start: float = profile[profile_index + 2]
		var chord_end: float = profile[profile_index + 3]
		var splits: Array[float] = [start, end]
		_add_interior_roots(splits, inner_roots, start, end)
		_add_interior_roots(splits, outer_roots, start, end)
		_add_interior_roots(splits, core_roots, start, end)
		splits.sort()
		for interval in range(splits.size() - 1):
			var lo: float = splits[interval]
			var hi: float = splits[interval + 1]
			if hi - lo <= ROOT_TOLERANCE:
				continue
			var piece_delta: PackedFloat64Array = _integrate_interval(v0, v1, v2, p, q, r,
				root_0, root_1, root_2, e_0, e_1, e_2,
				centre_0, centre_1, centre_2, along, d2,
				axis_0, axis_1, axis_2, wash_0, wash_1, wash_2, core, swirl_strength,
				inner2, outer2, area_scale, start, end, chord_start, chord_end, lo, hi,
				tail_pos_1, tail_pos_2, arm_base_0, arm_base_1, arm_base_2,
				horizontal, vertical, has_downwash, control_angle, incidence, downwash_product,
				elevator_tau_control, free_incidence, lift_slope,
				tail_limit, tail_span, tail_cd0, tail_k, tail_cd90, rho)
			for component in 6:
				result[component] += piece_delta[component]
	return result


static func _integrate_interval(v0: float, v1: float, v2: float, p: float, q: float, r: float,
		root_0: float, root_1: float, root_2: float, e_0: float, e_1: float, e_2: float,
		centre_0: float, centre_1: float, centre_2: float, along: float, d2: float,
		axis_0: float, axis_1: float, axis_2: float, wash_0: float, wash_1: float, wash_2: float,
		core: float, swirl_strength: float, inner2: float, outer2: float, area_scale: float,
		profile_start: float, profile_end: float, chord_start: float, chord_end: float,
		lo: float, hi: float, tail_pos_1: float, tail_pos_2: float,
		arm_base_0: float, arm_base_1: float, arm_base_2: float,
		horizontal: bool, vertical: bool, has_downwash: bool, control_angle: float,
		incidence: float, downwash_product: float, elevator_tau_control: float,
		free_incidence: float, lift_slope: float, tail_limit: float, tail_span: float,
		tail_cd0: float, tail_k: float, tail_cd90: float, rho: float) -> PackedFloat64Array:
	var result: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var middle: float = 0.5 * (lo + hi)
	var half: float = 0.5 * (hi - lo)
	var chord_slope: float = (chord_end - chord_start) / (profile_end - profile_start)
	for node in GAUSS_X.size():
		var eta: float = middle + half * GAUSS_X[node]
		var occupancy: float = _occupancy(eta, along, d2, inner2, outer2)
		if occupancy <= 0.0:
			continue
		var chord: float = chord_start + chord_slope * (eta - profile_start)
		var sample_area: float = area_scale * half * GAUSS_W[node] * chord * occupancy
		if sample_area <= 0.0:
			continue
		var point_0: float = root_0 + e_0 * eta
		var point_1: float = root_1 + e_1 * eta
		var point_2: float = root_2 + e_2 * eta
		var shift_1: float = point_1 - tail_pos_1
		var shift_2: float = 0.0 if horizontal else -(point_2 - tail_pos_2)
		var arm_0: float = arm_base_0 + 0.0
		var arm_1: float = arm_base_1 + shift_1
		var arm_2: float = arm_base_2 + shift_2
		var rate_arm_0: float = q * arm_2 - r * arm_1
		var rate_arm_1: float = r * arm_0 - p * arm_2
		var rate_arm_2: float = p * arm_1 - q * arm_0
		var radial_body_0: float = -(point_0 - centre_0)
		var radial_body_1: float = point_1 - centre_1
		var radial_body_2: float = -(point_2 - centre_2)
		var axial_projection: float = radial_body_0 * axis_0 + radial_body_1 * axis_1 + radial_body_2 * axis_2
		radial_body_0 -= axis_0 * axial_projection
		radial_body_1 -= axis_1 * axial_projection
		radial_body_2 -= axis_2 * axial_projection
		var radius: float = maxf(M.sqrt_(radial_body_0 * radial_body_0 + radial_body_1 * radial_body_1
			+ radial_body_2 * radial_body_2), core)
		var swirl_scale: float = swirl_strength / (radius * radius)
		var swirl_0: float = (axis_1 * radial_body_2 - axis_2 * radial_body_1) * swirl_scale
		var swirl_1: float = (axis_2 * radial_body_0 - axis_0 * radial_body_2) * swirl_scale
		var swirl_2: float = (axis_0 * radial_body_1 - axis_1 * radial_body_0) * swirl_scale

		# The arm and rate cross are common to the axial-only and axial-plus-swirl loads.
		# Keep the original vector addition grouping while evaluating each tail law directly in scalars.
		var axial_flow_0: float = (v0 + wash_0) + rate_arm_0
		var axial_flow_1: float = (v1 + wash_1) + rate_arm_1
		var axial_flow_2: float = (v2 + wash_2) + rate_arm_2
		var axial_normal: float = axial_flow_1 if vertical else axial_flow_2
		var axial_effective: float
		if has_downwash:
			axial_effective = wrapf(M.atan2_(axial_flow_2, axial_flow_0) - downwash_product
				+ elevator_tau_control + free_incidence, -PI, PI)
		else:
			axial_effective = wrapf(M.atan2_(axial_normal, axial_flow_0) + control_angle + incidence, -PI, PI)
		var axial_blend_input: float = (absf(axial_effective) - tail_limit) / tail_span
		var axial_blend: float
		if axial_blend_input <= 0.0:
			axial_blend = 0.0
		elif axial_blend_input >= 1.0:
			axial_blend = 1.0
		else:
			axial_blend = axial_blend_input * axial_blend_input * (3.0 - 2.0 * axial_blend_input)
		var axial_cl: float = (1.0 - axial_blend) * lift_slope * axial_effective \
			+ axial_blend * 0.5 * tail_cd90 * M.sin_(2.0 * axial_effective)
		var axial_sine: float = M.sin_(axial_effective)
		var axial_cd: float = tail_cd0 + tail_k * axial_cl * axial_cl + tail_cd90 * M.pow_(axial_sine, 2)
		var axial_flow_speed: float = M.sqrt_(axial_flow_0 * axial_flow_0 + axial_flow_1 * axial_flow_1
			+ axial_flow_2 * axial_flow_2)
		var axial_fx: float = 0.0
		var axial_fy: float = 0.0
		var axial_fz: float = 0.0
		var axial_mx: float = 0.0
		var axial_my: float = 0.0
		var axial_mz: float = 0.0
		if not axial_flow_speed < 1.0e-10:
			var axial_plane_speed: float = M.sqrt_(axial_flow_0 * axial_flow_0 + axial_normal * axial_normal)
			var axial_force_scale: float = -0.5 * rho * axial_flow_speed * sample_area * axial_cd
			axial_fx = axial_flow_0 * axial_force_scale
			axial_fy = axial_flow_1 * axial_force_scale
			axial_fz = axial_flow_2 * axial_force_scale
			if axial_plane_speed > 1.0e-10:
				var axial_lift: float = 0.5 * rho * axial_plane_speed * axial_plane_speed * sample_area * axial_cl
				axial_fx += axial_lift * axial_normal / axial_plane_speed
				if vertical:
					axial_fy -= axial_lift * axial_flow_0 / axial_plane_speed
				else:
					axial_fz -= axial_lift * axial_flow_0 / axial_plane_speed
			axial_mx = arm_1 * axial_fz - arm_2 * axial_fy
			axial_my = arm_2 * axial_fx - arm_0 * axial_fz
			axial_mz = arm_0 * axial_fy - arm_1 * axial_fx

		var swirl_extra_0: float = wash_0 - swirl_0
		var swirl_extra_1: float = wash_1 - swirl_1
		var swirl_extra_2: float = wash_2 - swirl_2
		var swirl_flow_0: float = (v0 + swirl_extra_0) + rate_arm_0
		var swirl_flow_1: float = (v1 + swirl_extra_1) + rate_arm_1
		var swirl_flow_2: float = (v2 + swirl_extra_2) + rate_arm_2
		var swirl_normal: float = swirl_flow_1 if vertical else swirl_flow_2
		var swirl_effective: float
		if has_downwash:
			swirl_effective = wrapf(M.atan2_(swirl_flow_2, swirl_flow_0) - downwash_product
				+ elevator_tau_control + free_incidence, -PI, PI)
		else:
			swirl_effective = wrapf(M.atan2_(swirl_normal, swirl_flow_0) + control_angle + incidence, -PI, PI)
		var swirl_blend_input: float = (absf(swirl_effective) - tail_limit) / tail_span
		var swirl_blend: float
		if swirl_blend_input <= 0.0:
			swirl_blend = 0.0
		elif swirl_blend_input >= 1.0:
			swirl_blend = 1.0
		else:
			swirl_blend = swirl_blend_input * swirl_blend_input * (3.0 - 2.0 * swirl_blend_input)
		var swirl_cl: float = (1.0 - swirl_blend) * lift_slope * swirl_effective \
			+ swirl_blend * 0.5 * tail_cd90 * M.sin_(2.0 * swirl_effective)
		var swirl_sine: float = M.sin_(swirl_effective)
		var swirl_cd: float = tail_cd0 + tail_k * swirl_cl * swirl_cl + tail_cd90 * M.pow_(swirl_sine, 2)
		var swirl_flow_speed: float = M.sqrt_(swirl_flow_0 * swirl_flow_0 + swirl_flow_1 * swirl_flow_1
			+ swirl_flow_2 * swirl_flow_2)
		var swirl_fx: float = 0.0
		var swirl_fy: float = 0.0
		var swirl_fz: float = 0.0
		var swirl_mx: float = 0.0
		var swirl_my: float = 0.0
		var swirl_mz: float = 0.0
		if not swirl_flow_speed < 1.0e-10:
			var swirl_plane_speed: float = M.sqrt_(swirl_flow_0 * swirl_flow_0 + swirl_normal * swirl_normal)
			var swirl_force_scale: float = -0.5 * rho * swirl_flow_speed * sample_area * swirl_cd
			swirl_fx = swirl_flow_0 * swirl_force_scale
			swirl_fy = swirl_flow_1 * swirl_force_scale
			swirl_fz = swirl_flow_2 * swirl_force_scale
			if swirl_plane_speed > 1.0e-10:
				var swirl_lift: float = 0.5 * rho * swirl_plane_speed * swirl_plane_speed * sample_area * swirl_cl
				swirl_fx += swirl_lift * swirl_normal / swirl_plane_speed
				if vertical:
					swirl_fy -= swirl_lift * swirl_flow_0 / swirl_plane_speed
				else:
					swirl_fz -= swirl_lift * swirl_flow_0 / swirl_plane_speed
			swirl_mx = arm_1 * swirl_fz - arm_2 * swirl_fy
			swirl_my = arm_2 * swirl_fx - arm_0 * swirl_fz
			swirl_mz = arm_0 * swirl_fy - arm_1 * swirl_fx

		result[0] += swirl_fx - axial_fx
		result[1] += swirl_fy - axial_fy
		result[2] += swirl_fz - axial_fz
		result[3] += swirl_mx - axial_mx
		result[4] += swirl_my - axial_my
		result[5] += swirl_mz - axial_mz
	return result


static func _occupancy(eta: float, along: float, d2: float, inner2: float, outer2: float) -> float:
	var radial: float = eta + along
	var radius2: float = d2 + radial * radial
	if radius2 <= inner2:
		return 1.0
	if radius2 >= outer2:
		return 0.0
	var t: float = clampf((radius2 - inner2) / (outer2 - inner2), 0.0, 1.0)
	return 1.0 - t * t * (3.0 - 2.0 * t)


static func _circle_intersections(along: float, d2: float, radius2: float) -> Array[float]:
	var result: Array[float] = []
	var radial2: float = radius2 - d2
	if radial2 < 0.0:
		return result
	var half: float = M.sqrt_(radial2)
	result.append(-along - half)
	if half > ROOT_TOLERANCE:
		result.append(-along + half)
	return result


static func _add_interior_roots(splits: Array[float], roots: Array[float], start: float, end: float) -> void:
	for root: float in roots:
		if root > start and root < end:
			splits.append(root)

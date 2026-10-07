extends RefCounted

# Independent composite-midpoint reference for smooth span profiles. This intentionally does not call
# Slipstream.profile_moments() or the production swirl quadrature.
const Aero = preload("res://physics/aero.gd")
const M = preload("res://physics/math3d.gd")
const Propulsion = preload("res://physics/propulsion.gd")
const RB = preload("res://physics/rigid_body.gd")

static func integrate(state: PackedFloat64Array, air: Dictionary, controls: Dictionary, model: Dictionary,
		wake: Dictionary, fade: float, rho: float, downwash_cl: float,
		samples_per_interval: int = 128) -> Dictionary:
	var axial_total: PackedFloat64Array = _zero_load()
	var swirled_total: PackedFloat64Array = _zero_load()
	if samples_per_interval < 1:
		return {axial = axial_total, swirled = swirled_total, correction = _zero_load()}

	var prop: Dictionary = model.propulsion
	var slipstream: Dictionary = prop.slipstream
	var axis: PackedFloat64Array = Propulsion.axis(prop)
	for piece: Dictionary in slipstream.pieces:
		var integrated_piece: Dictionary = _integrate_piece(
			state, air, controls, model, piece, wake, axis, rho, downwash_cl, samples_per_interval)
		var axial_piece: PackedFloat64Array = integrated_piece.axial
		var swirled_piece: PackedFloat64Array = integrated_piece.swirled
		for component in 6:
			axial_total[component] += axial_piece[component]
			swirled_total[component] += swirled_piece[component]

	var correction: PackedFloat64Array = _zero_load()
	for component in 6:
		axial_total[component] *= fade
		swirled_total[component] *= fade
		correction[component] = swirled_total[component] - axial_total[component]
	return {axial = axial_total, swirled = swirled_total, correction = correction}


static func _integrate_piece(state: PackedFloat64Array, air: Dictionary, controls: Dictionary, model: Dictionary,
		piece: Dictionary, wake: Dictionary, axis: PackedFloat64Array, rho: float, downwash_cl: float,
		samples_per_interval: int) -> Dictionary:
	var prop: Dictionary = model.propulsion
	var slipstream: Dictionary = prop.slipstream
	var root: PackedFloat64Array = piece.root
	var direction: PackedFloat64Array = piece.span_dir
	var hub: PackedFloat64Array = slipstream.hub
	var axis_le_0: float = -axis[0]
	var axis_le_1: float = axis[1]
	var axis_le_2: float = -axis[2]
	var distance: float = root[0] - hub[0]
	var shaft_scale: float = distance / axis_le_0
	var centre_0: float = hub[0] + axis_le_0 * shaft_scale
	var centre_1: float = hub[1] + axis_le_1 * shaft_scale
	var centre_2: float = hub[2] + axis_le_2 * shaft_scale
	var velocity: PackedFloat64Array = air.v_air
	if air.V > 1e-6 and wake.vs > 1e-6:
		var lean: float = minf(air.V / (wake.u + wake.w), 1.0) * distance / air.V
		centre_1 -= velocity[1] * lean
		centre_2 += velocity[2] * lean * float(slipstream.vertical_drift)

	var relative_0: float = root[0] - centre_0
	var relative_1: float = root[1] - centre_1
	var relative_2: float = root[2] - centre_2
	var along: float = relative_0 * direction[0] + relative_1 * direction[1] + relative_2 * direction[2]
	var perp_0: float = relative_0 - direction[0] * along
	var perp_1: float = relative_1 - direction[1] * along
	var perp_2: float = relative_2 - direction[2] * along
	var perpendicular_squared: float = perp_0 * perp_0 + perp_1 * perp_1 + perp_2 * perp_2
	var inner_squared: float = wake.rs * wake.rs * pow(1.0 - float(slipstream.edge_fraction), 2)
	var outer_squared: float = wake.rs * wake.rs * pow(1.0 + float(slipstream.edge_fraction), 2)

	var profile: PackedFloat64Array = piece.profile
	var profile_area: float = 0.0
	for interval in range(0, profile.size(), 4):
		profile_area += 0.5 * (profile[interval + 2] + profile[interval + 3]) \
			* (profile[interval + 1] - profile[interval])
	if profile_area <= 0.0:
		return {axial = _zero_load(), swirled = _zero_load()}
	var area_scale: float = float(piece.area) / profile_area
	var axial_total: PackedFloat64Array = _zero_load()
	var swirled_total: PackedFloat64Array = _zero_load()
	var rates: PackedFloat64Array = state.slice(RB.RATE, RB.RATE + 3)
	var axial_extra: PackedFloat64Array = M.scale(axis, wake.dv)

	for interval in range(0, profile.size(), 4):
		var start: float = profile[interval]
		var finish: float = profile[interval + 1]
		var step: float = (finish - start) / float(samples_per_interval)
		var chord_slope: float = (profile[interval + 3] - profile[interval + 2]) / (finish - start)
		for sample_index in samples_per_interval:
			var eta: float = start + (float(sample_index) + 0.5) * step
			var radial: float = eta + along
			var t: float = clampf(
				(perpendicular_squared + radial * radial - inner_squared) / (outer_squared - inner_squared),
				0.0, 1.0)
			var occupancy: float = 1.0 - t * t * (3.0 - 2.0 * t)
			if occupancy <= 0.0:
				continue
			var chord: float = profile[interval + 2] + chord_slope * (eta - start)
			var sample_area: float = area_scale * step * chord * occupancy
			if sample_area <= 0.0:
				continue

			var point_0: float = root[0] + direction[0] * eta
			var point_1: float = root[1] + direction[1] * eta
			var point_2: float = root[2] + direction[2] * eta
			var tail: Dictionary = model.surfaces[piece.surface]
			var tail_position: PackedFloat64Array = tail.position
			var shift: PackedFloat64Array = PackedFloat64Array([
				0.0,
				point_1 - tail_position[1],
				0.0 if piece.surface == "horizontal" else -(point_2 - tail_position[2]),
			])

			var radial_body_0: float = -(point_0 - centre_0)
			var radial_body_1: float = point_1 - centre_1
			var radial_body_2: float = -(point_2 - centre_2)
			var axial_projection: float = radial_body_0 * axis[0] \
				+ radial_body_1 * axis[1] + radial_body_2 * axis[2]
			radial_body_0 -= axis[0] * axial_projection
			radial_body_1 -= axis[1] * axial_projection
			radial_body_2 -= axis[2] * axial_projection
			var radius: float = maxf(M.sqrt_(
				radial_body_0 * radial_body_0 + radial_body_1 * radial_body_1 + radial_body_2 * radial_body_2),
				wake.core)
			var swirl_scale: float = wake.swirl / (radius * radius)
			var swirl: PackedFloat64Array = PackedFloat64Array([
				(axis[1] * radial_body_2 - axis[2] * radial_body_1) * swirl_scale,
				(axis[2] * radial_body_0 - axis[0] * radial_body_2) * swirl_scale,
				(axis[0] * radial_body_1 - axis[1] * radial_body_0) * swirl_scale,
			])
			var extra_with_swirl: PackedFloat64Array = M.sub(axial_extra, swirl)
			var axial_increment: PackedFloat64Array = Aero.tail_surface_increment(
				velocity, rates, controls, model, piece.surface, sample_area, shift, axial_extra, rho, downwash_cl)
			var swirled_increment: PackedFloat64Array = Aero.tail_surface_increment(
				velocity, rates, controls, model, piece.surface, sample_area, shift, extra_with_swirl, rho, downwash_cl)
			for component in 6:
				axial_total[component] += axial_increment[component]
				swirled_total[component] += swirled_increment[component]

	return {axial = axial_total, swirled = swirled_total}


static func _zero_load() -> PackedFloat64Array:
	return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])


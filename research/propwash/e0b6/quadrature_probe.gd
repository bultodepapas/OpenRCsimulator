# E0b6 numerical development probe; this fixture is synthetic and is not aircraft calibration.
# Compare the event-split Gauss correction against an independent composite midpoint load integral.
extends SceneTree
const Fixture = preload("res://tests/test_wash_profile.gd")
const AD = preload("res://physics/aircraft_data.gd")
const S = preload("res://physics/slipstream.gd")
const SwirlLoads = preload("res://physics/swirl_loads.gd")
const Aero = preload("res://physics/aero.gd")
const Air = preload("res://physics/air_data.gd")
const Prop = preload("res://physics/propulsion.gd")
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
const RHO: float = 1.225
const DOWNWASH_CL: float = 0.3
const SAMPLES_PER_PROFILE_INTERVAL: int = 8192

func _initialize() -> void:
	var raw: Dictionary = Fixture.combined_raw()
	raw.propulsion.propeller.slipstream.swirl_factor.value = 0.4
	var loaded: Dictionary = AD.validate_and_derive(raw)
	if not loaded.ok:
		push_error(str(loaded.errors))
		quit(1)
		return
	var worst_force: float = 0.0
	var worst_moment: float = 0.0
	var finite: bool = true
	for scenario: Dictionary in scenarios():
		var errors: Dictionary = compare_case(loaded.model, scenario)
		worst_force = maxf(worst_force, float(errors.force_error))
		worst_moment = maxf(worst_moment, float(errors.moment_error))
		finite = finite and bool(errors.finite)
		print(JSON.stringify(errors))
	print("worst normalized dense swirl correction error: force=", worst_force, " moment=", worst_moment, " finite=", finite)
	quit(0 if finite else 1)

func scenarios() -> Array[Dictionary]:
	return [
		{name = "static_controls_core", speed = 0.0, alpha = 0.0, rates = [0.0, 0.0, 0.0], elevator = 0.1, rudder = -0.1},
		{name = "forward_15_alpha3", speed = 15.0, alpha = deg_to_rad(3.0), rates = [0.3, -0.2, 0.4], elevator = 0.0, rudder = 0.0},
		{name = "near_outer_edge", speed = 15.0, alpha = deg_to_rad(15.0), rates = [0.0, 0.0, 0.0], elevator = 0.2, rudder = 0.0},
		{name = "reverse_fade_midpoint", speed = -0.15, alpha = 0.0, rates = [0.1, 0.2, -0.1], elevator = -0.1, rudder = 0.1},
	]

func compare_case(model: Dictionary, scenario: Dictionary) -> Dictionary:
	var alpha: float = float(scenario.alpha)
	var s: PackedFloat64Array = PackedFloat64Array([0, 0, -100, float(scenario.speed)*cos(alpha), 0, float(scenario.speed)*sin(alpha), 1, 0, 0, 0, float(scenario.rates[0]), float(scenario.rates[1]), float(scenario.rates[2])])
	var controls: Dictionary = {elevator = float(scenario.elevator), rudder = float(scenario.rudder), aileron_left = 0.0, aileron_right = 0.0}
	var air: Dictionary = Air.compute(s, M.v3(0, 0, 0), RHO)
	var prop: Dictionary = model.propulsion
	var rpm: float = prop.max_rpm
	var tq: PackedFloat64Array = Prop.thrust_torque(air.v_air, rpm, prop, RHO)
	var wake: Dictionary = S.wake(air.v_air, tq[0], tq[1], prop, RHO)
	var fade: float = S.reverse_weight(air.v_air, rpm, prop)
	var actual: PackedFloat64Array = SwirlLoads.correction(s, air, controls, model, wake, fade, RHO, DOWNWASH_CL)
	var dense: PackedFloat64Array = PackedFloat64Array([0, 0, 0, 0, 0, 0])
	for piece: Dictionary in prop.slipstream.pieces:
		var piece_delta: PackedFloat64Array = dense_piece(s, air, controls, model, piece, wake)
		for component in 6:
			dense[component] += piece_delta[component]
	for component in 6:
		dense[component] *= fade
	var error: PackedFloat64Array = PackedFloat64Array([0, 0, 0, 0, 0, 0])
	for component in 6:
		error[component] = actual[component] - dense[component]
	var force_ref: float = norm3(dense, 0)
	var moment_ref: float = norm3(dense, 3)
	var force_error: float = norm3(error, 0)
	var moment_error: float = norm3(error, 3)
	return {scenario = scenario.name, correction = actual, dense = dense, force_error = force_error / force_ref if force_ref > 1.0e-9 else null, moment_error = moment_error / moment_ref if moment_ref > 1.0e-9 else null, absolute_force_error = force_error, absolute_moment_error = moment_error, finite = all_finite(actual) and all_finite(dense)}

func dense_piece(s: PackedFloat64Array, air: Dictionary, controls: Dictionary, model: Dictionary, piece: Dictionary, wake: Dictionary) -> PackedFloat64Array:
	var prop: Dictionary = model.propulsion
	var axis: PackedFloat64Array = Prop.axis(prop)
	var root: PackedFloat64Array = piece.root
	var direction: PackedFloat64Array = piece.span_dir
	var hub: PackedFloat64Array = prop.slipstream.hub
	var ax_le_0: float = -axis[0]
	var ax_le_1: float = axis[1]
	var ax_le_2: float = -axis[2]
	var distance: float = root[0] - hub[0]
	var shaft_scale: float = distance / ax_le_0
	var centre_0: float = hub[0] + ax_le_0 * shaft_scale
	var centre_1: float = hub[1] + ax_le_1 * shaft_scale
	var centre_2: float = hub[2] + ax_le_2 * shaft_scale
	var speed: float = M.sqrt_(air.v_air[0]*air.v_air[0] + air.v_air[1]*air.v_air[1] + air.v_air[2]*air.v_air[2])
	if speed > 1e-6 and wake.vs > 1e-6:
		var lean: float = minf(speed/(wake.u+wake.w), 1.0)*distance/speed
		centre_1 -= air.v_air[1]*lean
		centre_2 += air.v_air[2]*lean*float(prop.slipstream.vertical_drift)
	var rel_0: float = root[0]-centre_0
	var rel_1: float = root[1]-centre_1
	var rel_2: float = root[2]-centre_2
	var along: float = rel_0*direction[0]+rel_1*direction[1]+rel_2*direction[2]
	var perp_0: float = rel_0-direction[0]*along
	var perp_1: float = rel_1-direction[1]*along
	var perp_2: float = rel_2-direction[2]*along
	var d2: float = perp_0*perp_0+perp_1*perp_1+perp_2*perp_2
	var edge: float = float(prop.slipstream.edge_fraction)
	var inner2: float = pow(wake.rs*(1-edge), 2)
	var outer2: float = pow(wake.rs*(1+edge), 2)
	var profile: PackedFloat64Array = piece.profile
	var profile_area: float = 0.0
	for i in range(0, profile.size(), 4):
		profile_area += 0.5*(profile[i+2]+profile[i+3])*(profile[i+1]-profile[i])
	var area_scale: float = float(piece.area)/profile_area
	var delta: PackedFloat64Array = PackedFloat64Array([0, 0, 0, 0, 0, 0])
	for i in range(0, profile.size(), 4):
		var start: float = profile[i]
		var end: float = profile[i+1]
		var h: float = (end-start)/float(SAMPLES_PER_PROFILE_INTERVAL)
		var chord_slope: float = (profile[i+3]-profile[i+2])/(end-start)
		for j in SAMPLES_PER_PROFILE_INTERVAL:
			var eta: float = start+(float(j)+0.5)*h
			var radial: float = eta+along
			var radius2: float = d2+radial*radial
			var occupancy: float = 1.0
			if radius2 > inner2:
				if radius2 >= outer2:
					continue
				var t: float = (radius2-inner2)/(outer2-inner2)
				occupancy = 1.0-t*t*(3.0-2.0*t)
			var chord: float = profile[i+2]+chord_slope*(eta-start)
			var area: float = area_scale*h*chord*occupancy
			var point_0: float = root[0]+direction[0]*eta
			var point_1: float = root[1]+direction[1]*eta
			var point_2: float = root[2]+direction[2]*eta
			var tail_pos: PackedFloat64Array = model.surfaces[piece.surface].position
			var shift: PackedFloat64Array = PackedFloat64Array([0, point_1-tail_pos[1], 0 if piece.surface=="horizontal" else -(point_2-tail_pos[2])])
			var rb0: float = -(point_0-centre_0)
			var rb1: float = point_1-centre_1
			var rb2: float = -(point_2-centre_2)
			var projection: float = rb0*axis[0]+rb1*axis[1]+rb2*axis[2]
			rb0 -= axis[0]*projection
			rb1 -= axis[1]*projection
			rb2 -= axis[2]*projection
			var radius: float = maxf(M.sqrt_(rb0*rb0+rb1*rb1+rb2*rb2), wake.core)
			var scale: float = wake.swirl/(radius*radius)
			var swirl: PackedFloat64Array = PackedFloat64Array([(axis[1]*rb2-axis[2]*rb1)*scale,(axis[2]*rb0-axis[0]*rb2)*scale,(axis[0]*rb1-axis[1]*rb0)*scale])
			var axial: PackedFloat64Array = PackedFloat64Array([axis[0]*wake.dv,axis[1]*wake.dv,axis[2]*wake.dv])
			var swirled: PackedFloat64Array = M.sub(axial, swirl)
			var axial_inc: PackedFloat64Array = Aero.tail_surface_increment(air.v_air, s.slice(RB.RATE,RB.RATE+3), controls, model, piece.surface, area, shift, axial, RHO, DOWNWASH_CL)
			var swirl_inc: PackedFloat64Array = Aero.tail_surface_increment(air.v_air, s.slice(RB.RATE,RB.RATE+3), controls, model, piece.surface, area, shift, swirled, RHO, DOWNWASH_CL)
			for c in 6:
				delta[c] += swirl_inc[c]-axial_inc[c]
	return delta

func norm3(values: PackedFloat64Array, start: int) -> float:
	return M.sqrt_(values[start]*values[start]+values[start+1]*values[start+1]+values[start+2]*values[start+2])

func all_finite(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true

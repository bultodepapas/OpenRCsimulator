# H13: frozen slipstream oracle, before scalar allocation removal. Verbatim copies of Slipstream.loads/wake/immersion
# and the Aero tail-increment helpers at 99936a1, so later edits to either file cannot move the oracle.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Propulsion := preload("res://physics/propulsion.gd")

const SWIRL_SPEED_FLOOR := 1.0
const RADIUS_MIN := 0.7071
const RADIUS_MAX := 1.5


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
		var increment := tail_surface_increment(v, rates, d, model, piece.surface, im.area, im.shift, extra, rho)
		for k in 6:
			out[k] += increment[k]
	return out


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


static func tail_surface_increment(v: PackedFloat64Array, rates: PackedFloat64Array, d: Dictionary, model: Dictionary,
		name: String, area: float, shift: PackedFloat64Array, extra: PackedFloat64Array, rho: float) -> PackedFloat64Array:
	var surfaces: Dictionary = model.surfaces
	var tail: Dictionary = surfaces[name]
	var vertical := name == "vertical"
	var arm := M.add(_arm(tail.position, model.cg_le), shift)
	var rate_arm := M.cross(rates, arm)
	var free_velocity := M.add(v, M.v3(0.0, 0.0, 0.0))
	var free_flow := M.add(free_velocity, rate_arm)
	var washed_velocity := M.add(v, extra)
	var washed_flow := M.add(washed_velocity, rate_arm)
	var free := _tail_surface_from_flow(free_flow, arm, d, tail, surfaces, area, vertical, rho)
	var washed := _tail_surface_from_flow(washed_flow, arm, d, tail, surfaces, area, vertical, rho)
	for k in 6:
		washed[k] -= free[k]
	return washed


static func _tail_surface_from_flow(flow: PackedFloat64Array, arm: PackedFloat64Array, d: Dictionary,
		tail: Dictionary, surfaces: Dictionary, area: float, vertical: bool, rho: float) -> PackedFloat64Array:
	var control: float = -d.rudder if vertical else d.elevator
	var effective := wrapf(M.atan2_(flow[1 if vertical else 2], flow[0])
		+ tail.control_effectiveness*control + tail.incidence, -PI, PI)
	var cl := _tail_curve(effective, tail.lift_slope, surfaces)
	var cd: float = surfaces.tail_CD0 + surfaces.tail_k*cl*cl + surfaces.tail_CD90*M.pow_(M.sin_(effective), 2)
	return _surface_with_flow(flow, arm, area, cl, cd, vertical, rho)


static func _tail_curve(alpha: float, slope: float, surfaces: Dictionary) -> float:
	# Continuous periodic flat-plate blend. No raw alpha survives the reverse-flow seam.
	var blend := _smoothstep((absf(alpha) - surfaces.tail_local_limit)/(surfaces.tail_stall_end - surfaces.tail_local_limit))
	return (1.0 - blend)*slope*alpha + blend*0.5*float(surfaces.tail_CD90)*M.sin_(2.0*alpha)


static func _surface_with_flow(flow: PackedFloat64Array, arm: PackedFloat64Array,
		area: float, cl: float, cd: float, vertical: bool, rho: float) -> PackedFloat64Array:
	var speed := M.sqrt_(M.dot(flow, flow))
	if speed < 1e-10:
		return PackedFloat64Array([0., 0., 0., 0., 0., 0.])
	var plane_speed := M.sqrt_(flow[0]*flow[0] + flow[1 if vertical else 2]*flow[1 if vertical else 2])
	var force_scale := -0.5*rho*speed*area*cd
	var fx: float = flow[0] * force_scale
	var fy: float = flow[1] * force_scale
	var fz: float = flow[2] * force_scale
	if plane_speed > 1e-10:
		var lift := 0.5*rho*plane_speed*plane_speed*area*cl
		fx += lift*flow[1 if vertical else 2]/plane_speed
		if vertical:
			fy -= lift*flow[0]/plane_speed
		else:
			fz -= lift*flow[0]/plane_speed
	var mx: float = arm[1] * fz - arm[2] * fy
	var my: float = arm[2] * fx - arm[0] * fz
	var mz: float = arm[0] * fy - arm[1] * fx
	return PackedFloat64Array([fx, fy, fz, mx, my, mz])


static func _arm(position: PackedFloat64Array, cg: PackedFloat64Array) -> PackedFloat64Array:
	return M.v3(-(position[0]-cg[0]), position[1]-cg[1], -(position[2]-cg[2]))


static func _smoothstep(x: float) -> float:
	if x <= 0.0:
		return 0.0
	if x >= 1.0:
		return 1.0
	return x * x * (3.0 - 2.0 * x)

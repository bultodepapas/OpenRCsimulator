# H4: frozen vector-form local-flow oracle, before scalar allocation removal.
extends RefCounted
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Aero := preload("res://physics/aero.gd")

static func local_flow_weight(s: PackedFloat64Array, air: Dictionary, d: Dictionary, model: Dictionary) -> float:
	var env: Dictionary = model.envelope
	var surfaces: Dictionary = model.surfaces
	var limit: float = surfaces.attached_limit
	var v: PackedFloat64Array = air.v_air
	var rates := s.slice(RB.RATE, RB.RATE+3)
	var blend := maxf(Aero._smoothstep((absf(air.alpha)-limit)/(env.a1-limit)), Aero.sideslip_weight(air.beta, env))
	if blend == 1.0:
		return blend
	var arp := _arm(model.reference.arp_le, model.cg_le)
	var twist: PackedFloat64Array = surfaces.get("station_incidence", PackedFloat64Array())
	for i in env.station_ys.size():
		var y: float = env.station_ys[i]
		var flow := M.add(v, M.cross(rates, M.add(arp, M.v3(0, y, 0))))
		var da: float = d.aileron_right if y > 0 else d.aileron_left
		var angle := wrapf(M.atan2_(flow[2], flow[0]) + surfaces.wing_aileron_effectiveness*da, -PI, PI)
		if not twist.is_empty():
			angle = wrapf(angle + twist[i], -PI, PI)
		var end: float = env.a1 if angle >= 0.0 else env.n1
		blend = maxf(blend, Aero._smoothstep((absf(angle)-limit)/(end-limit)))
		if blend == 1.0:
			return blend
	for name in ["horizontal", "vertical"]:
		var tail: Dictionary = surfaces[name]
		var angle := _tail_angle(v, rates, _arm(tail.position, model.cg_le), d, tail, name == "vertical")
		blend = maxf(blend, Aero._smoothstep((absf(angle)-limit)/(surfaces.tail_local_limit-limit)))
	return blend


static func _arm(position: PackedFloat64Array, cg: PackedFloat64Array) -> PackedFloat64Array:
	return M.v3(-(position[0]-cg[0]), position[1]-cg[1], -(position[2]-cg[2]))

static func _tail_angle(v: PackedFloat64Array, rates: PackedFloat64Array, arm: PackedFloat64Array, d: Dictionary, tail: Dictionary, vertical: bool) -> float:
	var flow := M.add(v, M.cross(rates, arm))
	var control: float = -d.rudder if vertical else d.elevator
	return wrapf(M.atan2_(flow[1 if vertical else 2], flow[0]) + tail.control_effectiveness*control + tail.incidence, -PI, PI)


# H12: frozen vector-form local loads, before scalar allocation removal. Verbatim copies of
# Aero._local_loads and its helpers at fe26ef0, so later edits to aero.gd cannot move the oracle.
static func local_loads(s: PackedFloat64Array, air: Dictionary, d: Dictionary, model: Dictionary, rho: float) -> PackedFloat64Array:
	var out := PackedFloat64Array([0., 0., 0., 0., 0., 0.])
	var rates := s.slice(RB.RATE, RB.RATE+3)
	var v: PackedFloat64Array = air.v_air
	var a: Dictionary = model.aero
	var env: Dictionary = model.envelope
	var ref: Dictionary = model.reference
	var surfaces: Dictionary = model.surfaces
	var ar := M.v3(-(ref.arp_le[0]-model.cg_le[0]), ref.arp_le[1]-model.cg_le[1], -(ref.arp_le[2]-model.cg_le[2]))
	var twist: PackedFloat64Array = surfaces.get("station_incidence", PackedFloat64Array())
	for i in env.station_ys.size():
		var y: float = env.station_ys[i]
		var arm := M.add(ar, M.v3(0, y, 0))
		var flow := M.add(v, M.cross(rates, arm))
		var da: float = d.aileron_right if y > 0 else d.aileron_left
		var effective := wrapf(M.atan2_(flow[2], flow[0]) + surfaces.wing_aileron_effectiveness * da, -PI, PI)
		if not twist.is_empty():
			effective = wrapf(effective + twist[i], -PI, PI)
		var cl := _lift_alpha(effective, a, env)
		var weight := _stall_weight(effective, env)
		var cd: float = a.CD0 + (1.0-weight)*a.k_induced*M.pow_(cl-a.CL_minD, 2) + weight*env.CD90*M.pow_(M.sin_(effective), 2)
		_add_load(out, _surface_with_flow(flow, arm, ref.S / env.station_ys.size(), cl, cd, false, rho))
	for name in ["horizontal", "vertical"]:
		var tail: Dictionary = surfaces[name]
		var vertical: bool = name == "vertical"
		var arm := _arm(tail.position, model.cg_le)
		var flow := M.add(v, M.cross(rates, arm))
		var effective := _tail_angle_from_flow(flow, d, tail, vertical)
		var cl := _tail_curve(effective, tail.lift_slope, surfaces)
		var cd: float = surfaces.tail_CD0 + surfaces.tail_k*cl*cl + surfaces.tail_CD90*M.pow_(M.sin_(effective), 2)
		_add_load(out, _surface_with_flow(flow, arm, tail.area, cl, cd, vertical, rho))
	return out


static func _stall_weight(alpha: float, env: Dictionary) -> float:
	if env.is_empty():
		return 0.0
	if alpha >= 0.0:
		return _smooth((alpha - env.a1) / (env.a2 - env.a1))
	return _smooth((-alpha - env.n1) / (env.n2 - env.n1))


static func _lift_alpha(alpha: float, a: Dictionary, env: Dictionary) -> float:
	var base: float = a.CL0 + a.CLa * alpha
	var w := _stall_weight(alpha, env)
	return base if w == 0.0 else (1.0 - w) * base + w * 0.5 * float(env.CD90) * M.sin_(2.0 * alpha)


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


static func _add_load(out: PackedFloat64Array, l: PackedFloat64Array) -> void:
	for k in 6:
		out[k] += l[k]


static func _tail_curve(alpha: float, slope: float, surfaces: Dictionary) -> float:
	var blend := _smooth((absf(alpha) - surfaces.tail_local_limit)/(surfaces.tail_stall_end - surfaces.tail_local_limit))
	return (1.0 - blend)*slope*alpha + blend*0.5*float(surfaces.tail_CD90)*M.sin_(2.0*alpha)


static func _tail_angle_from_flow(flow: PackedFloat64Array, d: Dictionary, tail: Dictionary, vertical: bool) -> float:
	var control: float = -d.rudder if vertical else d.elevator
	return wrapf(M.atan2_(flow[1 if vertical else 2], flow[0]) + tail.control_effectiveness*control + tail.incidence, -PI, PI)


static func _smooth(x: float) -> float:
	if x <= 0.0:
		return 0.0
	if x >= 1.0:
		return 1.0
	return x * x * (3.0 - 2.0 * x)

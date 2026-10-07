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
